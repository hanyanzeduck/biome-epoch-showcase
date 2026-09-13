class_name CreatureHaulBehavior
extends Node

const MIN_BUILDING_HAUL_ARRIVAL_DISTANCE: float = 96.0

enum Result { NO_HAUL, MOVING_TO_PICKUP, MOVING_TO_STORAGE, DEPOSITING, WAITING_WITH_CARGO }
enum FlowState {
	IDLE,
	RESOLVING_TASK,
	MOVING_TO_SOURCE,
	PICKING_UP,
	MOVING_TO_DESTINATION,
	DELIVERING,
	RECOVERING,
	WAITING_WITH_CARGO,
}

signal cargo_changed(item_data: ItemData, quantity: int)
signal haul_target_changed(source: Node, storage: ItemStorageComponent)
signal activity_stopped(reason: CreatureActivityStopReason.Reason)

@export_group("References")
@export var creature: Creature
@export var work_capability_component: WorkCapabilityComponent
@export var item_pickup_scene: PackedScene

@export_group("Carry Capacity")
@export_range(1, 999, 1) var base_carry_quantity: int = 10

@export_group("Search / Movement")
@export_range(0.05, 5.0, 0.05) var haul_scan_interval: float = 0.35
@export_range(5.0, 200.0, 1.0) var pickup_arrival_distance: float = 30.0
@export_range(0.1, 3.0, 0.05) var haul_move_speed_multiplier: float = 0.85
@export_range(0.5, 30.0, 0.5) var unreachable_pickup_retry_cooldown: float = 4.0
@export_range(0.5, 30.0, 0.5) var unreachable_production_source_retry_cooldown: float = 4.0
@export_range(0.5, 30.0, 0.5) var unreachable_storage_retry_cooldown: float = 4.0

@export_group("Debug")
@export var print_haul_events: bool = false

# 字段名称和语义保持兼容，避免场景、调试器和上层行为失效。
var current_pickup: ItemPickup
var current_production_source: Node
var current_production_item_data: ItemData
var current_storage: ItemStorageComponent
var planned_pickup_quantity: int = 0
var carried_item_data: ItemData
var carried_quantity: int = 0
var carried_source: Node
var carried_required_storage: ItemStorageComponent
var carried_requires_logistics_storage: bool = false
var haul_scan_remaining: float = 0.0
var current_flow_state: int = FlowState.IDLE

# 长生命周期协作者；不在每帧或每次扫描时重新创建。
var _recovery_policy := HaulRecoveryPolicy.new()
var _endpoint_resolver := HaulEndpointResolver.new()
var _task_resolver := HaulTaskResolver.new()
var _transfer_executor := HaulTransferExecutor.new()
var _action := CreatureActionCoordinator.new()
var _pickup_reservation := CreatureReservationLease.new()
var _production_reservation := CreatureReservationLease.new()
var _storage_reservation := CreatureReservationLease.new()


func _ready() -> void:
	_endpoint_resolver.configure(_recovery_policy)
	_task_resolver.configure(_endpoint_resolver)
	_transfer_executor.configure(_endpoint_resolver)
	_resolve_references()
	_action.configure(creature)
	if creature == null:
		push_error("%s 没有找到 Creature。" % name)
	if work_capability_component == null:
		push_warning("%s 没有找到 WorkCapabilityComponent。" % name)


func has_cargo() -> bool:
	return carried_item_data != null and carried_quantity > 0


func can_transport() -> bool:
	return work_capability_component != null and work_capability_component.can_do_work(
		WorkType.Type.TRANSPORTING
	)


func _is_base_transport_enabled() -> bool:
	if creature == null:
		return true
	var instance_data: CreatureInstanceData = creature.get_instance_data()
	return instance_data == null or instance_data.is_base_work_enabled(WorkType.Type.TRANSPORTING)


func get_max_carry_quantity(item_data: ItemData) -> int:
	if item_data == null or not can_transport():
		return 0
	var multiplier: float = work_capability_component.get_work_speed_multiplier(
		WorkType.Type.TRANSPORTING
	)
	if multiplier <= 0.0:
		return 0
	var capacity: int = floori(float(base_carry_quantity) * multiplier)
	return mini(maxi(capacity, 0), maxi(item_data.max_stack, 1))


func process_existing_cargo(delta: float, home_center: Vector2, home_radius: float) -> Result:
	if not has_cargo():
		_set_flow_state(FlowState.IDLE)
		return Result.NO_HAUL
	if creature == null or delta <= 0.0:
		_set_flow_state(FlowState.WAITING_WITH_CARGO)
		return Result.WAITING_WITH_CARGO
	if not _ensure_storage_for_cargo(home_center, home_radius):
		_stop_movement()
		_set_flow_state(FlowState.WAITING_WITH_CARGO)
		return Result.WAITING_WITH_CARGO
	if _is_base_transport_enabled():
		var collect_result := _process_collect_more_same_item(home_center, home_radius)
		if collect_result != Result.NO_HAUL:
			return collect_result
	return _process_move_to_storage(home_center, home_radius)


func process_new_haul(delta: float, home_center: Vector2, home_radius: float) -> Result:
	if has_cargo():
		return process_existing_cargo(delta, home_center, home_radius)
	if not _is_base_transport_enabled() or not can_transport():
		_cancel_unpicked_task()
		return Result.NO_HAUL
	if creature == null or delta <= 0.0:
		return Result.NO_HAUL
	var safe_radius: float = maxf(home_radius, 0.0)
	if safe_radius <= 0.0 or not _endpoint_resolver.is_position_inside_circle(
		creature.global_position, home_center, safe_radius
	):
		_cancel_unpicked_task()
		return Result.NO_HAUL
	if not _is_unpicked_task_valid(home_center, safe_radius):
		_cancel_unpicked_task()
	if current_pickup == null and current_production_source == null:
		haul_scan_remaining = maxf(haul_scan_remaining - delta, 0.0)
		if haul_scan_remaining > 0.0:
			_set_flow_state(FlowState.IDLE)
			return Result.NO_HAUL
		haul_scan_remaining = maxf(haul_scan_interval, 0.05)
		_try_acquire_nearest_haul_task(home_center, safe_radius)
	if current_pickup != null:
		return _process_move_to_pickup(home_center, safe_radius)
	if current_production_source != null:
		return _process_move_to_production_source(home_center, safe_radius)
	_set_flow_state(FlowState.IDLE)
	return Result.NO_HAUL


func interrupt_for_combat() -> void:
	_recovery_policy.interrupted(has_cargo())
	if has_cargo():
		_cancel_additional_pickup_task()
		_finish_activity(CreatureActivityStopReason.Reason.COMBAT)
		_set_flow_state(FlowState.WAITING_WITH_CARGO)
		return
	_cancel_unpicked_task(true, CreatureActivityStopReason.Reason.COMBAT)


func interrupt_for_return_home() -> void:
	_recovery_policy.interrupted(has_cargo())
	if has_cargo():
		_cancel_additional_pickup_task()
		_finish_activity(CreatureActivityStopReason.Reason.RETURN_HOME)
		_set_flow_state(FlowState.WAITING_WITH_CARGO)
		return
	_cancel_unpicked_task(true, CreatureActivityStopReason.Reason.RETURN_HOME)


func cancel_unpicked_task_for_work() -> void:
	if not has_cargo():
		_cancel_unpicked_task(
			false,
			CreatureActivityStopReason.Reason.WORK_PREEMPTED
		)


func prepare_for_world_removal(drop_cargo: bool = true) -> void:
	_release_pickup_reservation()
	_release_production_source_reservation()
	_release_storage_reservation()
	current_pickup = null
	current_production_source = null
	current_production_item_data = null
	current_storage = null
	planned_pickup_quantity = 0
	if drop_cargo and has_cargo():
		_drop_cargo_to_world()
	_clear_cargo()
	_finish_activity(CreatureActivityStopReason.Reason.WORLD_REMOVAL)
	_set_flow_state(FlowState.IDLE)


func _try_acquire_nearest_haul_task(home_center: Vector2, home_radius: float) -> void:
	if creature == null:
		return
	var worker_id := _get_worker_instance_id()
	if worker_id.is_empty():
		return
	_set_flow_state(FlowState.RESOLVING_TASK)
	_recovery_policy.prune()
	var task := _task_resolver.resolve_new_task(
		worker_id,
		creature.global_position,
		home_center,
		home_radius,
		_get_base_carry_limit()
	)
	match int(task.get("kind", HaulTaskResolver.TaskKind.NONE)):
		HaulTaskResolver.TaskKind.GROUND_PICKUP:
			_acquire_pickup_haul_task(task.get("pickup") as ItemPickup, home_center, home_radius)
		HaulTaskResolver.TaskKind.PRODUCTION_OUTPUT:
			_acquire_production_haul_task(
				task.get("source") as Node,
				task.get("item_data") as ItemData,
				home_center,
				home_radius
			)


func _acquire_pickup_haul_task(
	pickup: ItemPickup,
	home_center: Vector2,
	home_radius: float
) -> void:
	if pickup == null:
		return
	var item_data: ItemData = pickup.item_data
	var plan := _transfer_executor.reserve_pickup_task(
		_get_worker_instance_id(),
		pickup,
		get_max_carry_quantity(item_data),
		home_center,
		home_radius
	)
	if plan.is_empty():
		return
	current_pickup = pickup
	current_production_source = null
	current_production_item_data = null
	current_storage = plan.get("storage") as ItemStorageComponent
	_hold_pickup_reservation(current_pickup)
	_hold_storage_reservation(current_storage)
	planned_pickup_quantity = int(plan.get("quantity", 0))
	haul_target_changed.emit(current_pickup, current_storage)
	_set_flow_state(FlowState.MOVING_TO_SOURCE)
	_debug("Haul：%s 预约地面 %s ×%d → %s" % [
		creature.get_display_name(), item_data.display_name, planned_pickup_quantity,
		str(current_storage.get_parent().name),
	])


func _acquire_production_haul_task(
	source: Node,
	item_data: ItemData,
	home_center: Vector2,
	home_radius: float
) -> void:
	if source == null or item_data == null:
		return
	var plan := _transfer_executor.reserve_production_task(
		_get_worker_instance_id(), source, item_data, get_max_carry_quantity(item_data),
		home_center, home_radius
	)
	if plan.is_empty():
		return
	current_pickup = null
	current_production_source = source
	current_production_item_data = item_data
	current_storage = plan.get("storage") as ItemStorageComponent
	_hold_production_reservation(current_production_source)
	_hold_storage_reservation(current_storage)
	planned_pickup_quantity = int(plan.get("quantity", 0))
	haul_target_changed.emit(current_production_source, current_storage)
	_set_flow_state(FlowState.MOVING_TO_SOURCE)
	_debug("Haul：%s 预约生产成品 %s ×%d → %s" % [
		creature.get_display_name(), item_data.display_name, planned_pickup_quantity,
		str(current_storage.get_parent().name),
	])


func _process_move_to_pickup(home_center: Vector2, home_radius: float) -> Result:
	if current_pickup == null:
		return Result.NO_HAUL
	if not _is_unpicked_task_valid(home_center, home_radius):
		_recovery_policy.source_became_invalid(false)
		_cancel_unpicked_task()
		return Result.NO_HAUL
	_set_flow_state(FlowState.MOVING_TO_SOURCE)
	var move_result := _move_toward(current_pickup.global_position, pickup_arrival_distance)
	if move_result == CreatureNavigationComponent.MoveResult.MOVING:
		return Result.MOVING_TO_PICKUP
	if move_result == CreatureNavigationComponent.MoveResult.BLOCKED:
		_recovery_policy.mark_pickup_unreachable(
			current_pickup, unreachable_pickup_retry_cooldown
		)
		_set_flow_state(FlowState.RECOVERING)
		_cancel_unpicked_task(
			true,
			CreatureActivityStopReason.Reason.NAVIGATION_BLOCKED
		)
		return Result.NO_HAUL
	_set_flow_state(FlowState.PICKING_UP)
	var worker_id := _get_worker_instance_id()
	var transfer := _transfer_executor.take_pickup(
		worker_id, current_pickup, planned_pickup_quantity
	)
	var item_data := transfer.get("item_data") as ItemData
	var taken_quantity: int = int(transfer.get("quantity", 0))
	# 与旧实现一致：真实取货尝试之后才停止当前接近动作。
	_stop_movement()
	_pickup_reservation.clear_without_release()
	current_pickup = null
	planned_pickup_quantity = 0
	if item_data == null or taken_quantity <= 0:
		_release_storage_reservation()
		current_storage = null
		_set_flow_state(FlowState.RECOVERING)
		_finish_activity(
			CreatureActivityStopReason.Reason.RESERVATION_LOST,
			false
		)
		return Result.NO_HAUL
	carried_item_data = item_data
	carried_quantity = taken_quantity
	carried_source = null
	carried_required_storage = null
	carried_requires_logistics_storage = false
	cargo_changed.emit(carried_item_data, carried_quantity)
	_shrink_storage_reservation_to_cargo(worker_id)
	_debug("Haul：%s 拿起 %s ×%d" % [
		creature.get_display_name(), carried_item_data.display_name, carried_quantity,
	])
	_set_flow_state(FlowState.MOVING_TO_DESTINATION)
	return Result.MOVING_TO_STORAGE


func _process_move_to_production_source(
	home_center: Vector2,
	home_radius: float
) -> Result:
	if current_production_source == null:
		return Result.NO_HAUL
	if not _is_production_task_valid(home_center, home_radius):
		_recovery_policy.source_became_invalid(false)
		_cancel_unpicked_task()
		return Result.NO_HAUL
	var source_position: Vector2 = current_production_source.get_haul_output_world_position()
	var arrival_distance: float = maxf(
		float(current_production_source.get_haul_output_arrival_distance()),
		MIN_BUILDING_HAUL_ARRIVAL_DISTANCE
	)
	_set_flow_state(FlowState.MOVING_TO_SOURCE)
	var move_result := _move_toward(source_position, arrival_distance)
	if move_result == CreatureNavigationComponent.MoveResult.MOVING:
		return Result.MOVING_TO_PICKUP
	if move_result == CreatureNavigationComponent.MoveResult.BLOCKED:
		_recovery_policy.mark_production_source_unreachable(
			current_production_source,
			unreachable_production_source_retry_cooldown
		)
		_set_flow_state(FlowState.RECOVERING)
		_cancel_unpicked_task(
			true,
			CreatureActivityStopReason.Reason.NAVIGATION_BLOCKED
		)
		haul_scan_remaining = 0.0
		return Result.NO_HAUL
	_set_flow_state(FlowState.PICKING_UP)
	var worker_id := _get_worker_instance_id()
	var source_item: ItemData = current_production_item_data
	if source_item == null:
		_cancel_unpicked_task()
		return Result.NO_HAUL
	# 最后一份成品被取走时订单元数据可能被清空，先固化本趟目的约束。
	var constraint := _endpoint_resolver.resolve_cargo_destination_constraint(
		current_storage, source_item, current_production_source
	)
	carried_required_storage = constraint.get("required_storage") as ItemStorageComponent
	carried_requires_logistics_storage = bool(constraint.get("requires_logistics", false))
	var source_before_take: Node = current_production_source
	var taken_quantity: int = _transfer_executor.take_production_output(
		worker_id, current_production_source, source_item, planned_pickup_quantity
	)
	_stop_movement()
	_production_reservation.clear_without_release()
	if taken_quantity > 0:
		carried_source = source_before_take
	current_production_source = null
	current_production_item_data = null
	planned_pickup_quantity = 0
	if taken_quantity <= 0:
		_release_storage_reservation()
		current_storage = null
		carried_source = null
		carried_required_storage = null
		carried_requires_logistics_storage = false
		_set_flow_state(FlowState.RECOVERING)
		_finish_activity(
			CreatureActivityStopReason.Reason.RESERVATION_LOST,
			false
		)
		return Result.NO_HAUL
	carried_item_data = source_item
	carried_quantity = taken_quantity
	_shrink_storage_reservation_to_cargo(worker_id)
	cargo_changed.emit(carried_item_data, carried_quantity)
	_debug("Haul：%s 从生产设施拿起 %s ×%d" % [
		creature.get_display_name(), carried_item_data.display_name, carried_quantity,
	])
	_set_flow_state(FlowState.MOVING_TO_DESTINATION)
	return Result.MOVING_TO_STORAGE


func _process_collect_more_same_item(home_center: Vector2, home_radius: float) -> Result:
	if not has_cargo() or current_storage == null:
		return Result.NO_HAUL
	if not is_instance_valid(current_storage):
		_storage_reservation.clear_without_release()
		current_storage = null
		return Result.NO_HAUL
	var carry_limit: int = get_max_carry_quantity(carried_item_data)
	if carry_limit <= 0:
		return Result.NO_HAUL
	if carried_quantity >= carry_limit:
		_release_additional_pickup_reservation()
		return Result.NO_HAUL
	if current_pickup != null:
		if not _is_additional_pickup_task_valid(home_center, home_radius):
			_cancel_additional_pickup_task()
		else:
			return _process_move_to_additional_pickup(home_center, home_radius)
	if not _try_acquire_nearest_additional_pickup(home_center, home_radius, carry_limit):
		return Result.NO_HAUL
	return _process_move_to_additional_pickup(home_center, home_radius)


func _try_acquire_nearest_additional_pickup(
	home_center: Vector2,
	home_radius: float,
	carry_limit: int
) -> bool:
	if not has_cargo() or current_storage == null or not is_instance_valid(current_storage):
		return false
	var worker_id := _get_worker_instance_id()
	if worker_id.is_empty():
		return false
	var plan := _task_resolver.resolve_additional_pickup(
		worker_id,
		creature.global_position,
		carried_item_data,
		carried_quantity,
		carry_limit,
		current_storage,
		home_center,
		home_radius
	)
	if plan.is_empty():
		return false
	var pickup := plan.get("pickup") as ItemPickup
	var quantity: int = int(plan.get("quantity", 0))
	if not _transfer_executor.reserve_additional_pickup(
		worker_id,
		pickup,
		current_storage,
		carried_item_data,
		carried_quantity + quantity
	):
		return false
	current_pickup = pickup
	_hold_pickup_reservation(current_pickup)
	planned_pickup_quantity = quantity
	haul_target_changed.emit(current_pickup, current_storage)
	_debug("Haul：%s 继续收集 %s，当前 ×%d，计划再拿 ×%d" % [
		creature.get_display_name(), carried_item_data.display_name,
		carried_quantity, planned_pickup_quantity,
	])
	return true


func _process_move_to_additional_pickup(
	home_center: Vector2,
	home_radius: float
) -> Result:
	if not _is_additional_pickup_task_valid(home_center, home_radius):
		_cancel_additional_pickup_task()
		return Result.NO_HAUL
	_set_flow_state(FlowState.MOVING_TO_SOURCE)
	var move_result := _move_toward(current_pickup.global_position, pickup_arrival_distance)
	if move_result == CreatureNavigationComponent.MoveResult.MOVING:
		return Result.MOVING_TO_PICKUP
	if move_result == CreatureNavigationComponent.MoveResult.BLOCKED:
		_recovery_policy.mark_pickup_unreachable(
			current_pickup, unreachable_pickup_retry_cooldown
		)
		_stop_movement()
		_set_flow_state(FlowState.RECOVERING)
		_cancel_additional_pickup_task()
		_finish_activity(
			CreatureActivityStopReason.Reason.NAVIGATION_BLOCKED,
			false
		)
		return Result.NO_HAUL
	_set_flow_state(FlowState.PICKING_UP)
	var worker_id := _get_worker_instance_id()
	var transfer := _transfer_executor.take_pickup(
		worker_id, current_pickup, planned_pickup_quantity
	)
	var taken_quantity: int = int(transfer.get("quantity", 0))
	_stop_movement()
	_pickup_reservation.clear_without_release()
	current_pickup = null
	planned_pickup_quantity = 0
	if taken_quantity <= 0:
		_transfer_executor.resize_storage_reservation(
			worker_id, current_storage, carried_item_data, carried_quantity
		)
		return Result.MOVING_TO_PICKUP
	carried_quantity += taken_quantity
	_transfer_executor.resize_storage_reservation(
		worker_id, current_storage, carried_item_data, carried_quantity
	)
	cargo_changed.emit(carried_item_data, carried_quantity)
	_debug("Haul：%s 当前携带 %s ×%d" % [
		creature.get_display_name(), carried_item_data.display_name, carried_quantity,
	])
	return Result.MOVING_TO_PICKUP


func _is_additional_pickup_task_valid(home_center: Vector2, home_radius: float) -> bool:
	return has_cargo() and _endpoint_resolver.is_additional_pickup_task_valid(
		current_pickup,
		current_storage,
		_get_worker_instance_id(),
		carried_item_data,
		carried_quantity,
		planned_pickup_quantity,
		home_center,
		home_radius
	)


func _cancel_additional_pickup_task() -> void:
	_release_additional_pickup_reservation()
	current_pickup = null
	planned_pickup_quantity = 0
	if current_storage != null and is_instance_valid(current_storage) and has_cargo():
		_transfer_executor.resize_storage_reservation(
			_get_worker_instance_id(), current_storage, carried_item_data, carried_quantity
		)


func _release_additional_pickup_reservation() -> void:
	_release_pickup_reservation()


func _ensure_storage_for_cargo(home_center: Vector2, home_radius: float) -> bool:
	if not has_cargo():
		return false
	var worker_id := _get_worker_instance_id()
	if worker_id.is_empty():
		return false
	if _endpoint_resolver.has_valid_storage_reservation(
		current_storage, worker_id, carried_item_data, home_center, home_radius
	):
		return true
	_recovery_policy.destination_became_invalid(true)
	_release_storage_reservation()
	current_storage = null
	var source_for_delivery: Node = carried_source
	if source_for_delivery != null and not is_instance_valid(source_for_delivery):
		source_for_delivery = null
		carried_source = null
	if carried_required_storage != null and not _endpoint_resolver.is_live_node(
		carried_required_storage
	):
		carried_required_storage = null
	var storage_plan := _find_storage_plan(
		carried_item_data,
		carried_quantity,
		creature.global_position,
		home_center,
		home_radius,
		source_for_delivery,
		carried_required_storage,
		carried_requires_logistics_storage
	)
	if storage_plan.is_empty():
		return false
	var storage := storage_plan.get("storage") as ItemStorageComponent
	var quantity: int = int(storage_plan.get("quantity", 0))
	if storage == null or quantity < carried_quantity:
		return false
	if not _transfer_executor.resize_storage_reservation(
		worker_id, storage, carried_item_data, carried_quantity
	):
		return false
	current_storage = storage
	_hold_storage_reservation(current_storage)
	haul_target_changed.emit(current_pickup, current_storage)
	return true


func _process_move_to_storage(home_center: Vector2, home_radius: float) -> Result:
	if not has_cargo():
		return Result.NO_HAUL
	if not _ensure_storage_for_cargo(home_center, home_radius):
		_stop_movement()
		_set_flow_state(FlowState.WAITING_WITH_CARGO)
		return Result.WAITING_WITH_CARGO
	if current_storage == null:
		_set_flow_state(FlowState.WAITING_WITH_CARGO)
		return Result.WAITING_WITH_CARGO
	var storage_position: Vector2 = current_storage.get_storage_world_position()
	var arrival_distance: float = current_storage.get_storage_arrival_distance()
	_set_flow_state(FlowState.MOVING_TO_DESTINATION)
	var move_result := _move_toward(storage_position, arrival_distance)
	if move_result == CreatureNavigationComponent.MoveResult.MOVING:
		return Result.MOVING_TO_STORAGE
	if move_result == CreatureNavigationComponent.MoveResult.BLOCKED:
		_recovery_policy.mark_storage_unreachable(
			current_storage, unreachable_storage_retry_cooldown
		)
		_stop_movement()
		_release_storage_reservation()
		current_storage = null
		haul_scan_remaining = 0.0
		haul_target_changed.emit(null, null)
		_set_flow_state(FlowState.RECOVERING)
		_finish_activity(
			CreatureActivityStopReason.Reason.NAVIGATION_BLOCKED,
			false
		)
		return Result.WAITING_WITH_CARGO
	_set_flow_state(FlowState.DELIVERING)
	var delivered_storage: ItemStorageComponent = current_storage
	var delivered_quantity: int = carried_quantity
	var remaining: int = _transfer_executor.deposit_cargo(
		_get_worker_instance_id(), current_storage, carried_item_data, carried_quantity
	)
	# deposit_reserved 已真实执行，成功或部分失败都结束当前接近动作。
	_stop_movement()
	_storage_reservation.clear_without_release()
	if remaining <= 0:
		_debug("Haul：%s 已把 %s ×%d 存入 %s" % [
			creature.get_display_name(), carried_item_data.display_name, delivered_quantity,
			str(delivered_storage.get_parent().name),
		])
		_clear_cargo()
		current_storage = null
		haul_scan_remaining = 0.0
		haul_target_changed.emit(null, null)
		_set_flow_state(FlowState.IDLE)
		_finish_activity(CreatureActivityStopReason.Reason.COMPLETED, false)
		return Result.DEPOSITING
	carried_quantity = remaining
	cargo_changed.emit(carried_item_data, carried_quantity)
	current_storage = null
	_set_flow_state(FlowState.WAITING_WITH_CARGO)
	return Result.WAITING_WITH_CARGO


func _is_unpicked_task_valid(home_center: Vector2, home_radius: float) -> bool:
	if current_pickup != null:
		return _is_pickup_task_valid(home_center, home_radius)
	if current_production_source != null:
		return _is_production_task_valid(home_center, home_radius)
	return false


func _is_pickup_task_valid(home_center: Vector2, home_radius: float) -> bool:
	return _endpoint_resolver.is_pickup_task_valid(
		current_pickup,
		current_storage,
		_get_worker_instance_id(),
		home_center,
		home_radius
	)


func _is_production_task_valid(home_center: Vector2, home_radius: float) -> bool:
	return _endpoint_resolver.is_production_task_valid(
		current_production_source,
		current_production_item_data,
		current_storage,
		_get_worker_instance_id(),
		home_center,
		home_radius
	)


func _cancel_unpicked_task(
	stop_movement: bool = true,
	stop_reason: CreatureActivityStopReason.Reason = (
		CreatureActivityStopReason.Reason.TARGET_INVALID
	)
) -> void:
	_release_pickup_reservation()
	_release_production_source_reservation()
	_release_storage_reservation()
	current_pickup = null
	current_production_source = null
	current_production_item_data = null
	current_storage = null
	planned_pickup_quantity = 0
	haul_scan_remaining = 0.0
	haul_target_changed.emit(null, null)
	_finish_activity(stop_reason, stop_movement)
	_set_flow_state(FlowState.IDLE)


func _release_pickup_reservation() -> void:
	if _pickup_reservation.is_active():
		_pickup_reservation.release()
	else:
		_transfer_executor.release_pickup(_get_worker_instance_id(), current_pickup)
		_pickup_reservation.clear_without_release()


func _release_production_source_reservation() -> void:
	if _production_reservation.is_active():
		_production_reservation.release()
	else:
		_transfer_executor.release_production_source(
			_get_worker_instance_id(), current_production_source
		)
		_production_reservation.clear_without_release()


func _release_storage_reservation() -> void:
	if _storage_reservation.is_active():
		_storage_reservation.release()
	else:
		_transfer_executor.release_storage(_get_worker_instance_id(), current_storage)
		_storage_reservation.clear_without_release()


func _hold_pickup_reservation(pickup: ItemPickup) -> void:
	if pickup == null:
		return
	var worker_id: StringName = _get_worker_instance_id()
	_pickup_reservation.hold(
		pickup,
		Callable(_transfer_executor, &"release_pickup").bind(worker_id, pickup)
	)


func _hold_production_reservation(source: Node) -> void:
	if source == null:
		return
	var worker_id: StringName = _get_worker_instance_id()
	_production_reservation.hold(
		source,
		Callable(_transfer_executor, &"release_production_source").bind(
			worker_id,
			source
		)
	)


func _hold_storage_reservation(storage: ItemStorageComponent) -> void:
	if storage == null:
		return
	var worker_id: StringName = _get_worker_instance_id()
	_storage_reservation.hold(
		storage,
		Callable(_transfer_executor, &"release_storage").bind(worker_id, storage)
	)


func _drop_cargo_to_world() -> void:
	if not has_cargo():
		return
	if item_pickup_scene == null:
		push_warning(
			"CreatureHaulBehavior 没有 ItemPickup Scene，无法在收回菲菈时重新掉落 Cargo。"
		)
		return
	if creature == null or not creature.get_parent() is Node2D:
		return
	var pickup := _transfer_executor.drop_cargo_to_world(
		item_pickup_scene,
		creature.get_parent() as Node2D,
		creature.global_position,
		carried_item_data,
		carried_quantity
	)
	if pickup == null:
		push_error("CreatureHaulBehavior 的 ItemPickup Scene 根节点必须是 ItemPickup。")
		return
	_debug("Haul：%s 被收回，重新掉落 %s ×%d" % [
		creature.get_display_name(), carried_item_data.display_name, carried_quantity,
	])


func _clear_cargo() -> void:
	carried_item_data = null
	carried_quantity = 0
	carried_source = null
	carried_required_storage = null
	carried_requires_logistics_storage = false
	cargo_changed.emit(null, 0)


func _find_storage_plan(
	item_data: ItemData,
	maximum_quantity: int,
	reference_position: Vector2,
	home_center: Vector2,
	home_radius: float,
	source_node: Node = null,
	required_storage: ItemStorageComponent = null,
	require_logistics_storage: bool = false
) -> Dictionary:
	return _endpoint_resolver.find_storage_plan(
		_get_worker_instance_id(),
		item_data,
		maximum_quantity,
		reference_position,
		home_center,
		home_radius,
		source_node,
		required_storage,
		require_logistics_storage
	)


func _shrink_storage_reservation_to_cargo(worker_id: StringName) -> void:
	if current_storage == null:
		return
	if not _transfer_executor.resize_storage_reservation(
		worker_id, current_storage, carried_item_data, carried_quantity
	):
		_transfer_executor.release_storage(worker_id, current_storage)
		_storage_reservation.clear_without_release()
		current_storage = null


func _move_toward(
	world_position: Vector2,
	arrival_distance: float = 8.0
) -> CreatureNavigationComponent.MoveResult:
	if creature == null:
		return CreatureNavigationComponent.MoveResult.BLOCKED
	return _action.approach_action_target(
		world_position,
		haul_move_speed_multiplier,
		arrival_distance
	)


func _stop_movement() -> void:
	_action.stop_navigation()


func _finish_activity(
	reason: CreatureActivityStopReason.Reason,
	stop_movement: bool = true
) -> void:
	_action.finish(reason, stop_movement)
	activity_stopped.emit(reason)


func _get_worker_instance_id() -> StringName:
	if creature == null:
		return &""
	return creature.get_creature_instance_id()


func _get_base_carry_limit() -> int:
	if not can_transport():
		return 0
	return maxi(floori(
		float(base_carry_quantity)
		* work_capability_component.get_work_speed_multiplier(WorkType.Type.TRANSPORTING)
	), 0)


func get_architecture_diagnostics() -> Dictionary:
	var diagnostics: Dictionary = _action.get_diagnostics()
	diagnostics.merge({
		"flow_state": current_flow_state,
		"endpoint_query_count": _endpoint_resolver.query_count,
		"has_cargo": has_cargo(),
		"has_source_task": current_pickup != null or current_production_source != null,
		"has_storage": current_storage != null,
		"pickup_reserved": _pickup_reservation.is_active(),
		"production_reserved": _production_reservation.is_active(),
		"storage_reserved": _storage_reservation.is_active(),
	}, true)
	return diagnostics


func reset_endpoint_query_count() -> void:
	_endpoint_resolver.reset_query_count()


func _set_flow_state(next_state: int) -> void:
	current_flow_state = next_state


func _debug(message: String) -> void:
	if print_haul_events:
		print(message)


func _resolve_references() -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	if creature == null and parent_node is Creature:
		creature = parent_node as Creature
	if work_capability_component == null:
		work_capability_component = parent_node.get_node_or_null(
			"WorkCapabilityComponent"
		) as WorkCapabilityComponent
