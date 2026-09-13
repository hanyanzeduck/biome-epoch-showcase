extends Node


class FakeStorage:
	extends ItemStorageComponent

	var test_capacity: int = 100
	var stored_quantity: int = 0
	var destination_priority: int = 0
	var logistics_enabled: bool = false
	var deposit_limit: int = -1
	var reservations: Dictionary = {}

	func _ready() -> void:
		pass

	func get_storage_world_position() -> Vector2:
		return (get_parent() as Node2D).global_position

	func has_logistics_upgrade() -> bool:
		return logistics_enabled

	func get_haul_destination_priority_for_source(
		_item_data: ItemData,
		_source: Node
	) -> int:
		return destination_priority

	func get_reservable_quantity(
		worker_instance_id: StringName,
		_item_data: ItemData,
		maximum_quantity: int
	) -> int:
		var other_reserved: int = 0
		for key: Variant in reservations:
			if StringName(key) != worker_instance_id:
				other_reserved += int(reservations[key])
		return mini(maximum_quantity, maxi(test_capacity - stored_quantity - other_reserved, 0))

	func reserve_capacity(
		worker_instance_id: StringName,
		item_data: ItemData,
		quantity: int
	) -> bool:
		if item_data == null or quantity <= 0:
			return false
		if get_reservable_quantity(worker_instance_id, item_data, quantity) < quantity:
			return false
		reservations[worker_instance_id] = quantity
		return true

	func has_capacity_reservation(
		worker_instance_id: StringName,
		_item_data: ItemData = null
	) -> bool:
		return reservations.has(worker_instance_id)

	func get_reserved_quantity(worker_instance_id: StringName) -> int:
		return int(reservations.get(worker_instance_id, 0))

	func release_capacity(worker_instance_id: StringName) -> void:
		reservations.erase(worker_instance_id)

	func deposit_reserved(
		worker_instance_id: StringName,
		_item_data: ItemData,
		quantity: int
	) -> int:
		if not reservations.has(worker_instance_id):
			return quantity
		var accepted: int = mini(
			mini(quantity, int(reservations[worker_instance_id])),
			maxi(test_capacity - stored_quantity, 0)
		)
		if deposit_limit >= 0:
			accepted = mini(accepted, deposit_limit)
		stored_quantity += accepted
		reservations.erase(worker_instance_id)
		return quantity - accepted

	func reserved_total() -> int:
		var total: int = 0
		for value: Variant in reservations.values():
			total += int(value)
		return total


class FakeProductionSource:
	extends Node2D

	var items: Array[ItemData] = []
	var quantity: int = 0
	var source_priority: int = 0
	var stock_maintenance: bool = false
	var reservations: Dictionary = {}

	func _exit_tree() -> void:
		WorldEntityRegistry.unregister_entity(self)

	func has_haul_output() -> bool:
		return quantity > 0 and not items.is_empty()

	func get_haul_output_item_data() -> ItemData:
		return items[0] if not items.is_empty() else null

	func get_haul_output_item_candidates() -> Array[ItemData]:
		return items

	func get_haul_output_world_position() -> Vector2:
		return global_position

	func get_haul_output_arrival_distance() -> float:
		return 96.0

	func get_haul_source_priority() -> int:
		return source_priority

	func is_stock_maintenance_order() -> bool:
		return stock_maintenance

	func get_reservable_haul_output_quantity(
		worker_instance_id: StringName,
		item_data: ItemData,
		maximum_quantity: int
	) -> int:
		if item_data == null or not items.has(item_data):
			return 0
		var reserved_by_others: int = 0
		for key: Variant in reservations:
			if StringName(key) != worker_instance_id:
				reserved_by_others += int((reservations[key] as Dictionary).get("quantity", 0))
		return mini(maximum_quantity, maxi(quantity - reserved_by_others, 0))

	func reserve_haul_output(
		worker_instance_id: StringName,
		item_data: ItemData,
		requested_quantity: int
	) -> bool:
		if get_reservable_haul_output_quantity(
			worker_instance_id, item_data, requested_quantity
		) < requested_quantity:
			return false
		reservations[worker_instance_id] = {
			"item_data": item_data,
			"quantity": requested_quantity,
		}
		return true

	func has_haul_output_reservation(
		worker_instance_id: StringName,
		item_data: ItemData
	) -> bool:
		if not reservations.has(worker_instance_id):
			return false
		return (reservations[worker_instance_id] as Dictionary).get("item_data") == item_data

	func release_haul_output_reservation(worker_instance_id: StringName) -> void:
		reservations.erase(worker_instance_id)

	func take_reserved_haul_output(
		worker_instance_id: StringName,
		item_data: ItemData,
		requested_quantity: int
	) -> int:
		if not has_haul_output_reservation(worker_instance_id, item_data):
			return 0
		var reserved: int = int((reservations[worker_instance_id] as Dictionary).get(
			"quantity", 0
		))
		var taken: int = mini(mini(requested_quantity, reserved), quantity)
		quantity -= taken
		reservations.erase(worker_instance_id)
		return taken


var _failures: PackedStringArray = []
var _assertions: int = 0
var _scenario_failures_before: int = 0
var _world: Node2D
var _actors: Array[Creature] = []
var _performance_results: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node2D.new()
	_world.name = "HaulTestWorld"
	add_child(_world)
	if OS.get_cmdline_user_args().has("--haul-benchmark-only"):
		_benchmark(20)
		_benchmark(50)
		_print_performance_results()
		get_tree().quit(0)
		return
	print("[TEST] Creature Haul architecture regression")
	_test_single_source_destination()
	_test_multiple_sources()
	_test_multiple_destinations()
	_test_source_insufficient()
	_test_destination_insufficient()
	_test_partial_transfer()
	_test_source_depleted_en_route()
	_test_destination_filled_en_route()
	_test_source_removed()
	_test_destination_removed()
	_test_interruption()
	_test_unreachable_path()
	_test_reselect_destination()
	_test_multi_fera_same_item()
	_test_warehouse_transfer()
	_test_workstation_input()
	_test_workstation_output()
	_test_automated_farm()
	_test_material_configuration()
	_test_player_inventory_change()
	_test_concurrency(5)
	_test_concurrency(10)
	_test_concurrency(20)
	_test_state_leaks()
	if not OS.get_cmdline_user_args().has("--haul-scenarios-only"):
		_benchmark(20)
		_benchmark(50)
	_reset_world()
	_print_performance_results()
	if _failures.is_empty():
		print("[PASS] Haul scenarios=20 concurrency=5/10/20 state_cycles=8 assertions=%d" % _assertions)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] %s" % failure)
	print("[FAILED] failures=%d assertions=%d" % [_failures.size(), _assertions])
	get_tree().quit(1)


func _print_performance_results() -> void:
	for result: Dictionary in _performance_results:
		print("Haul Performance | workers=%d | batch_ms=%.3f | ms_per_worker=%.4f | endpoint_queries=%d" % [
			int(result.workers), float(result.batch_ms), float(result.ms_per_worker),
			int(result.endpoint_queries),
		])


func _begin_scenario(name: String) -> void:
	_reset_world()
	_scenario_failures_before = _failures.size()
	print("[SCENARIO] %s" % name)


func _end_scenario(name: String) -> void:
	if _failures.size() == _scenario_failures_before:
		print("[SCENARIO PASS] %s" % name)


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(message)


func _reset_world() -> void:
	for actor: Creature in _actors:
		if is_instance_valid(actor):
			actor.free()
	_actors.clear()
	if _world != null:
		for child: Node in _world.get_children():
			if is_instance_valid(child):
				child.free()


func _item(id: StringName = &"test_item") -> ItemData:
	var item := ItemData.new()
	item.item_id = id
	item.display_name = String(id)
	item.max_stack = 99
	return item


func _behavior(worker_id: StringName, position: Vector2) -> CreatureHaulBehavior:
	var actor := Creature.new()
	actor.name = String(worker_id)
	var instance := CreatureInstanceData.new()
	instance.instance_id = worker_id
	actor.set_instance_data(instance)
	actor.global_position = position
	var capability := WorkCapabilityComponent.new()
	capability.name = "WorkCapabilityComponent"
	capability.transporting_level = 1
	actor.add_child(capability)
	var behavior := CreatureHaulBehavior.new()
	behavior.creature = actor
	behavior.work_capability_component = capability
	actor.add_child(behavior)
	behavior._ready()
	_actors.append(actor)
	return behavior


func _pickup(item: ItemData, quantity: int, position: Vector2) -> ItemPickup:
	var pickup := ItemPickup.new()
	pickup.item_data = item
	pickup.quantity = quantity
	pickup.global_position = position
	_world.add_child(pickup)
	WorldEntityRegistry.register_entity(
		WorldEntityRegistry.KIND_ITEM_PICKUP, pickup, position
	)
	return pickup


func _storage(
	capacity: int,
	position: Vector2,
	priority: int = 0,
	logistics: bool = false
) -> FakeStorage:
	var host := Node2D.new()
	host.name = "StorageHost"
	host.global_position = position
	_world.add_child(host)
	var storage := FakeStorage.new()
	storage.test_capacity = capacity
	storage.destination_priority = priority
	storage.logistics_enabled = logistics
	host.add_child(storage)
	WorldEntityRegistry.register_entity(
		WorldEntityRegistry.KIND_ITEM_STORAGE, storage, position
	)
	return storage


func _source(
	item: ItemData,
	quantity: int,
	position: Vector2,
	priority: int = 0
) -> FakeProductionSource:
	var source := FakeProductionSource.new()
	source.items = [item]
	source.quantity = quantity
	source.source_priority = priority
	source.global_position = position
	_world.add_child(source)
	WorldEntityRegistry.register_entity(
		WorldEntityRegistry.KIND_PRODUCTION_SOURCE, source, position
	)
	return source


func _take_now(behavior: CreatureHaulBehavior) -> int:
	return behavior.process_new_haul(1.0, Vector2.ZERO, 10000.0)


func _deliver_now(behavior: CreatureHaulBehavior) -> int:
	behavior.creature.global_position = behavior.current_storage.get_storage_world_position()
	return behavior.process_existing_cargo(1.0, Vector2.ZERO, 10000.0)


func _test_single_source_destination() -> void:
	var label := "01 单一Source→单一Destination"
	_begin_scenario(label)
	var item := _item()
	_pickup(item, 5, Vector2.ZERO)
	var storage := _storage(20, Vector2.ZERO)
	var behavior := _behavior(&"single", Vector2.ZERO)
	_expect(_take_now(behavior) == CreatureHaulBehavior.Result.MOVING_TO_STORAGE, "单源取货结果")
	_expect(behavior.carried_quantity == 5, "单源应携带5")
	_expect(_deliver_now(behavior) == CreatureHaulBehavior.Result.DEPOSITING, "单源交货结果")
	_expect(storage.stored_quantity == 5 and not behavior.has_cargo(), "单源完整交付")
	_end_scenario(label)


func _test_multiple_sources() -> void:
	var label := "02 多Source按既有距离选择"
	_begin_scenario(label)
	var item := _item()
	var near := _pickup(item, 1, Vector2(10, 0))
	var far := _pickup(item, 1, Vector2(200, 0))
	_storage(20, Vector2.ZERO)
	var behavior := _behavior(&"multi_source", Vector2.ZERO)
	_take_now(behavior)
	_expect(near.quantity == 0, "多Source应选择同优先级最近货源")
	_expect(far.quantity == 1, "较远Source不应被领取")
	_end_scenario(label)


func _test_multiple_destinations() -> void:
	var label := "03 多Destination按既有距离选择"
	_begin_scenario(label)
	var item := _item()
	_pickup(item, 1, Vector2.ZERO)
	var far := _storage(20, Vector2(300, 0))
	var near := _storage(20, Vector2(20, 0))
	var behavior := _behavior(&"multi_dest", Vector2.ZERO)
	_take_now(behavior)
	_expect(behavior.current_storage == near, "应选择最近完整容量Destination")
	_expect(behavior.current_storage != far, "不应选择较远同优先级Destination")
	_end_scenario(label)


func _test_source_insufficient() -> void:
	var label := "04 Source库存不足"
	_begin_scenario(label)
	var item := _item()
	_pickup(item, 3, Vector2.ZERO)
	_storage(20, Vector2.ZERO)
	var behavior := _behavior(&"source_short", Vector2.ZERO)
	_take_now(behavior)
	_expect(behavior.carried_quantity == 3, "Source不足时数量应裁剪到3")
	_expect(behavior.current_storage.get_reserved_quantity(&"source_short") == 3, "目的预约应收缩到真实数量")
	_end_scenario(label)


func _test_destination_insufficient() -> void:
	var label := "05 Destination容量不足"
	_begin_scenario(label)
	var item := _item()
	var pickup := _pickup(item, 10, Vector2.ZERO)
	var storage := _storage(4, Vector2.ZERO)
	var behavior := _behavior(&"dest_short", Vector2.ZERO)
	_take_now(behavior)
	_expect(behavior.carried_quantity == 4 and pickup.quantity == 6, "容量不足时本趟只能取4")
	_expect(storage.get_reserved_quantity(&"dest_short") == 4, "容量预约必须等于4")
	_end_scenario(label)


func _test_partial_transfer() -> void:
	var label := "06 Partial transfer"
	_begin_scenario(label)
	var item := _item()
	var source := _source(item, 10, Vector2(200, 0))
	var storage := _storage(20, Vector2.ZERO)
	var behavior := _behavior(&"partial", Vector2.ZERO)
	behavior._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	source.quantity = 3
	behavior.creature.global_position = source.global_position
	_take_now(behavior)
	_expect(behavior.carried_quantity == 3, "途中变化后只取真实剩余3")
	_expect(storage.get_reserved_quantity(&"partial") == 3, "Partial后预约收缩到3")
	_end_scenario(label)


func _test_source_depleted_en_route() -> void:
	var label := "07 Source路上被清空"
	_begin_scenario(label)
	var item := _item()
	var pickup := _pickup(item, 5, Vector2(200, 0))
	var storage := _storage(20, Vector2.ZERO)
	var behavior := _behavior(&"depleted", Vector2.ZERO)
	behavior._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	pickup.quantity = 0
	behavior.creature.global_position = pickup.global_position
	_take_now(behavior)
	_expect(not behavior.has_cargo(), "清空Source不能产生Cargo")
	_expect(not storage.has_capacity_reservation(&"depleted"), "清空Source必须释放Destination预约")
	_end_scenario(label)


func _test_destination_filled_en_route() -> void:
	var label := "08 Destination路上被填满"
	_begin_scenario(label)
	var item := _item()
	var pickup := _pickup(item, 5, Vector2(200, 0))
	var full_storage := _storage(5, Vector2.ZERO)
	var behavior := _behavior(&"filled", Vector2.ZERO)
	behavior._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	full_storage.stored_quantity = 5
	behavior.creature.global_position = pickup.global_position
	_take_now(behavior)
	_expect(behavior.has_cargo() and behavior.current_storage == null, "仓库突满后应保留Cargo并释放失效目的")
	var replacement := _storage(20, Vector2(300, 0))
	behavior.creature.global_position = replacement.get_storage_world_position()
	_expect(behavior.process_existing_cargo(1.0, Vector2.ZERO, 10000.0) == CreatureHaulBehavior.Result.DEPOSITING, "仓库突满后应可改投新目的")
	_end_scenario(label)


func _test_source_removed() -> void:
	var label := "09 Source建筑被拆除"
	_begin_scenario(label)
	var item := _item()
	var source := _source(item, 5, Vector2(200, 0))
	var storage := _storage(20, Vector2.ZERO)
	var behavior := _behavior(&"source_removed", Vector2.ZERO)
	behavior._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	source.free()
	_take_now(behavior)
	_expect(not behavior.has_cargo(), "Source拆除不能生成Cargo")
	_expect(not storage.has_capacity_reservation(&"source_removed"), "Source拆除释放容量预约")
	_end_scenario(label)


func _test_destination_removed() -> void:
	var label := "10 Destination建筑被拆除"
	_begin_scenario(label)
	var item := _item()
	var pickup := _pickup(item, 5, Vector2(200, 0))
	var storage := _storage(20, Vector2.ZERO)
	var behavior := _behavior(&"dest_removed", Vector2.ZERO)
	behavior._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	storage.get_parent().free()
	behavior.creature.global_position = pickup.global_position
	_take_now(behavior)
	_expect(not behavior.has_cargo(), "Destination拆除应取消未取货任务")
	_expect(pickup.haul_reserved_by_instance_id.is_empty(), "Destination拆除释放Source claim")
	_end_scenario(label)


func _test_interruption() -> void:
	var label := "11 Creature途中被中断"
	_begin_scenario(label)
	var item := _item()
	var pickup := _pickup(item, 5, Vector2(200, 0))
	var storage := _storage(20, Vector2.ZERO)
	var behavior := _behavior(&"interrupt", Vector2.ZERO)
	behavior._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	behavior.interrupt_for_combat()
	_expect(pickup.haul_reserved_by_instance_id.is_empty(), "中断应释放未取Source")
	_expect(not storage.has_capacity_reservation(&"interrupt"), "中断应释放未取Destination")
	_expect(behavior.current_pickup == null and behavior.current_storage == null, "中断清理任务状态")
	_end_scenario(label)


func _test_unreachable_path() -> void:
	var label := "12 找不到路径"
	_begin_scenario(label)
	var item := _item()
	var pickup := _pickup(item, 5, Vector2.ZERO)
	_storage(20, Vector2.ZERO)
	var behavior := _behavior(&"blocked", Vector2.ZERO)
	var action: int = behavior._recovery_policy.mark_pickup_unreachable(pickup, 4.0)
	behavior._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	_expect(action == HaulRecoveryPolicy.Action.RESELECT_TASK, "不可达应返回重选任务策略")
	_expect(behavior.current_pickup == null, "冷却期间不得立刻重新领取不可达Source")
	_end_scenario(label)


func _test_reselect_destination() -> void:
	var label := "13 重新选择目标"
	_begin_scenario(label)
	var item := _item()
	_pickup(item, 5, Vector2.ZERO)
	var first := _storage(20, Vector2.ZERO)
	var behavior := _behavior(&"reselect", Vector2.ZERO)
	_take_now(behavior)
	first.get_parent().free()
	var second := _storage(20, Vector2(100, 0))
	behavior.creature.global_position = second.get_storage_world_position()
	_expect(behavior.process_existing_cargo(1.0, Vector2.ZERO, 10000.0) == CreatureHaulBehavior.Result.DEPOSITING, "Cargo应重新选择有效Destination")
	_expect(second.stored_quantity == 5, "重选目的应完整接收Cargo")
	_end_scenario(label)


func _test_multi_fera_same_item() -> void:
	var label := "14 多只Fira同时搬同一种物品"
	_begin_scenario(label)
	var item := _item()
	var pickup := _pickup(item, 5, Vector2(500, 0))
	_storage(20, Vector2.ZERO)
	var first := _behavior(&"fera_a", Vector2.ZERO)
	var second := _behavior(&"fera_b", Vector2.ZERO)
	first._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	second._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	var claim_count: int = int(first.current_pickup == pickup) + int(second.current_pickup == pickup)
	_expect(claim_count == 1, "同一Pickup只能被一只Fira claim")
	_expect(not pickup.haul_reserved_by_instance_id.is_empty(), "Pickup应保存稳定worker claim")
	_end_scenario(label)


func _test_warehouse_transfer() -> void:
	var label := "15 Warehouse之间物流"
	_begin_scenario(label)
	var item := _item()
	_source(item, 4, Vector2.ZERO)
	var destination := _storage(20, Vector2.ZERO)
	var behavior := _behavior(&"warehouse", Vector2.ZERO)
	_take_now(behavior)
	_expect(behavior.carried_quantity == 4 and behavior.carried_source != null, "Warehouse Source通过正式输出API取货")
	_deliver_now(behavior)
	_expect(destination.stored_quantity == 4, "Warehouse Destination收到4")
	_end_scenario(label)


func _test_workstation_input() -> void:
	var label := "16 Workstation输入物料"
	_begin_scenario(label)
	var item := _item()
	_pickup(item, 2, Vector2.ZERO)
	var ordinary := _storage(20, Vector2(10, 0), 0)
	var workstation := _storage(20, Vector2(300, 0), 100)
	var behavior := _behavior(&"workstation_input", Vector2.ZERO)
	_take_now(behavior)
	_expect(behavior.current_storage == workstation, "Workstation高优先级输入必须胜过近仓库")
	_expect(behavior.current_storage != ordinary, "普通仓库不得抢走Workstation输入")
	_end_scenario(label)


func _test_workstation_output() -> void:
	var label := "17 Workstation产物输出"
	_begin_scenario(label)
	var item := _item()
	var pickup := _pickup(item, 1, Vector2.ZERO)
	var source := _source(item, 2, Vector2.ZERO, 100)
	_storage(20, Vector2.ZERO)
	var behavior := _behavior(&"workstation_output", Vector2.ZERO)
	_take_now(behavior)
	_expect(behavior.carried_source == source and behavior.carried_quantity == 2, "高优先生产成品应先于地面物")
	_expect(pickup.quantity == 1, "生产成品优先时地面物保持不变")
	_expect_source_contract(ProductionComponent.new(), "ProductionComponent")
	_end_scenario(label)


func _test_automated_farm() -> void:
	var label := "18 Automated Farm相关搬运"
	_begin_scenario(label)
	var crop := _item(&"test_crop")
	var source := _source(crop, 7, Vector2.ZERO)
	_storage(20, Vector2.ZERO)
	var behavior := _behavior(&"farm", Vector2.ZERO)
	_take_now(behavior)
	_expect(behavior.carried_source == source, "Farm兼容通用production haul source契约")
	_expect(behavior.carried_quantity == 7, "Farm产物数量保持")
	_expect_source_contract(AutomatedFarmCropModule.new(), "AutomatedFarmCropModule")
	_end_scenario(label)


func _test_material_configuration() -> void:
	var label := "19 Material Configuration相关搬运"
	_begin_scenario(label)
	var item := _item()
	var source := _source(item, 6, Vector2.ZERO, 20)
	source.stock_maintenance = true
	var logistics := _storage(20, Vector2.ZERO, 50, true)
	var behavior := _behavior(&"material_config", Vector2.ZERO)
	_take_now(behavior)
	_expect(behavior.current_storage == logistics, "物资配置输出进入物流仓")
	_expect(behavior.carried_requires_logistics_storage, "取货后固化物流仓约束")
	var production := ProductionComponent.new()
	_expect(production.has_method(&"is_stock_maintenance_order"), "Material Configuration正式Source应公开订单来源")
	production.free()
	_end_scenario(label)


func _test_player_inventory_change() -> void:
	var label := "20 玩家手动改变库存后的搬运恢复"
	_begin_scenario(label)
	var item := _item()
	_pickup(item, 5, Vector2.ZERO)
	var storage := _storage(20, Vector2.ZERO)
	storage.deposit_limit = 2
	var behavior := _behavior(&"player_change", Vector2.ZERO)
	_take_now(behavior)
	_expect(_deliver_now(behavior) == CreatureHaulBehavior.Result.WAITING_WITH_CARGO, "交付期容量变化产生partial failure")
	_expect(behavior.carried_quantity == 3 and storage.stored_quantity == 2, "Partial保留剩余3")
	storage.deposit_limit = -1
	behavior.creature.global_position = storage.get_storage_world_position()
	_expect(behavior.process_existing_cargo(1.0, Vector2.ZERO, 10000.0) == CreatureHaulBehavior.Result.DEPOSITING, "剩余Cargo下一轮恢复交付")
	_expect(storage.stored_quantity == 5 and not behavior.has_cargo(), "库存变化后总量守恒")
	_end_scenario(label)


func _test_concurrency(worker_count: int) -> void:
	var label := "并发搬运 %d只" % worker_count
	_begin_scenario(label)
	var item := _item()
	var storage := _storage(worker_count, Vector2.ZERO)
	var behaviors: Array[CreatureHaulBehavior] = []
	for index: int in worker_count:
		_pickup(item, 1, Vector2(500 + index * 4, 0))
		behaviors.append(_behavior(StringName("concurrent_%d_%d" % [worker_count, index]), Vector2.ZERO))
	for behavior: CreatureHaulBehavior in behaviors:
		behavior._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	var claimed_ids: Dictionary = {}
	for behavior: CreatureHaulBehavior in behaviors:
		_expect(behavior.current_pickup != null, "%d并发每只应取得不同任务" % worker_count)
		if behavior.current_pickup != null:
			claimed_ids[behavior.current_pickup.get_instance_id()] = true
	_expect(claimed_ids.size() == worker_count, "%d并发不能重复领取" % worker_count)
	_expect(storage.reserved_total() == worker_count, "%d并发容量预约总量准确" % worker_count)
	for behavior: CreatureHaulBehavior in behaviors:
		behavior.creature.global_position = behavior.current_pickup.global_position
		_take_now(behavior)
		_expect(behavior.carried_quantity == 1, "%d并发每只实际取1" % worker_count)
	for behavior: CreatureHaulBehavior in behaviors:
		behavior.creature.global_position = storage.get_storage_world_position()
		behavior.process_existing_cargo(1.0, Vector2.ZERO, 10000.0)
	_expect(storage.stored_quantity == worker_count, "%d并发不能负库存或超容量" % worker_count)
	_expect(storage.reserved_total() == 0, "%d并发结束后无残留预约" % worker_count)
	_end_scenario(label)


func _test_state_leaks() -> void:
	var label := "状态泄漏 8个完整周期"
	_begin_scenario(label)
	var item := _item()
	var storage := _storage(100, Vector2.ZERO)
	var behavior := _behavior(&"cycles", Vector2.ZERO)
	for cycle: int in 8:
		var pickup := _pickup(item, 1, Vector2.ZERO)
		_take_now(behavior)
		_deliver_now(behavior)
		_expect(not behavior.has_cargo(), "周期%d Cargo清空" % cycle)
		_expect(behavior.current_pickup == null, "周期%d Source清空" % cycle)
		_expect(behavior.current_production_source == null, "周期%d Production Source清空" % cycle)
		_expect(behavior.current_storage == null, "周期%d Destination清空" % cycle)
		_expect(behavior.planned_pickup_quantity == 0, "周期%d requested amount清空" % cycle)
		_expect(not storage.has_capacity_reservation(&"cycles"), "周期%d reservation清空" % cycle)
		_expect(behavior.creature.velocity == Vector2.ZERO, "周期%d navigation velocity清空" % cycle)
		if is_instance_valid(pickup):
			pickup.free()
	_expect(storage.stored_quantity == 8, "8周期物品总量守恒")
	_end_scenario(label)


func _benchmark(worker_count: int) -> void:
	_reset_world()
	var item := _item(StringName("benchmark_%d" % worker_count))
	_storage(worker_count * 2, Vector2.ZERO)
	var behaviors: Array[CreatureHaulBehavior] = []
	for index: int in worker_count:
		_pickup(item, 1, Vector2(1000 + index * 3, 0))
		var behavior := _behavior(
			StringName("benchmark_%d_%d" % [worker_count, index]),
			Vector2.ZERO
		)
		behavior.reset_endpoint_query_count()
		behaviors.append(behavior)
	var started_usec: int = Time.get_ticks_usec()
	for behavior: CreatureHaulBehavior in behaviors:
		behavior._try_acquire_nearest_haul_task(Vector2.ZERO, 10000.0)
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	var query_count: int = 0
	for behavior: CreatureHaulBehavior in behaviors:
		query_count += int(behavior.get_architecture_diagnostics().endpoint_query_count)
	_performance_results.append({
		"workers": worker_count,
		"batch_ms": elapsed_ms,
		"ms_per_worker": elapsed_ms / float(worker_count),
		"endpoint_queries": query_count,
	})


func _expect_source_contract(source: Node, label: String) -> void:
	for method_name: StringName in [
		&"has_haul_output",
		&"get_haul_output_item_data",
		&"get_haul_output_world_position",
		&"get_haul_output_arrival_distance",
		&"get_reservable_haul_output_quantity",
		&"reserve_haul_output",
		&"has_haul_output_reservation",
		&"release_haul_output_reservation",
		&"take_reserved_haul_output",
	]:
		_expect(source.has_method(method_name), "%s缺少%s" % [label, method_name])
	source.free()
