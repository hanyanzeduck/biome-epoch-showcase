class_name WorldGenPipeline
extends RefCounted


const WorldGenBoundaryBuilderScript = preload("res://scripts/worldgen/generation/worldgen_boundary_builder.gd")
const SPAWN_SAFETY_RADIUS_TILES: int = 4


var _graph_generator: WorldGenGraphGenerator = WorldGenGraphGenerator.new()
var _spatializer: WorldGenSpatializer = WorldGenSpatializer.new()
var _workspace_builder: WorldGenWorkspaceBuilder = WorldGenWorkspaceBuilder.new()
var _rasterizer: WorldGenTileRasterizer = WorldGenTileRasterizer.new()
var _room_spatializer: WorldGenRoomSpatializer = WorldGenRoomSpatializer.new()
var _topology_enforcer: WorldGenTopologyEnforcer = WorldGenTopologyEnforcer.new()
var _road_network_generator: WorldGenRoadNetworkGenerator = WorldGenRoadNetworkGenerator.new()
var _validator: WorldGenValidator = WorldGenValidator.new()
var _boundary_builder = WorldGenBoundaryBuilderScript.new()


func generate(generation_seed: int, preset: WorldGenPreset) -> WorldGenResult:
	var generation_start_usec: int = Time.get_ticks_usec()
	var stage_start_usec: int = generation_start_usec
	var result: WorldGenResult = WorldGenResult.new()
	result.generation_seed = generation_seed
	result.preset = preset

	result.graph = _graph_generator.generate(generation_seed, preset)
	_record_stage(result, &"graph", stage_start_usec)

	stage_start_usec = Time.get_ticks_usec()
	var graph_check: Dictionary = _validator.evaluate_graph_structure(result.graph, preset)
	_record_stage(result, &"graph_check", stage_start_usec)
	if not bool(graph_check.get("valid", false)):
		result.validation = _graph_failure_validation(result.graph, graph_check)
		_finish_generation_timing(result, generation_start_usec)
		return result

	var best_layout: WorldGenLayout = null
	var best_layout_score: float = -INF
	var chosen_attempt_seed: int = generation_seed
	var attempts_used: int = 0

	stage_start_usec = Time.get_ticks_usec()
	# 只允许廉价 Task 布局重试。失败候选不会进入 Room/Tile/Validator。
	for attempt_index: int in range(maxi(1, preset.max_task_layout_attempts)):
		var attempt_seed: int = generation_seed + attempt_index * 104729
		var layout: WorldGenLayout = _spatializer.layout_tasks(
			attempt_seed,
			result.graph,
			preset
		)
		attempts_used = attempt_index + 1
		var early_check: Dictionary = _validator.evaluate_task_layout(
			attempt_seed,
			result.graph,
			layout,
			preset
		)
		var score: float = float(early_check.get("score", -INF))
		if best_layout == null or score > best_layout_score:
			best_layout = layout
			best_layout_score = score
			chosen_attempt_seed = attempt_seed
		if bool(early_check.get("valid", false)):
			best_layout = layout
			chosen_attempt_seed = attempt_seed
			break
	_record_stage(result, &"task_layout", stage_start_usec)

	result.layout = best_layout if best_layout != null else WorldGenLayout.new()
	result.task_layout_attempts = attempts_used

	# 廉价布局检查只用于选择更合适的候选，不是生成门禁。
	# 长宽比与中心偏移会保留为世界特征诊断；只有真正没有布局数据才提前返回。
	if not result.layout.task_layout_succeeded:
		result.validation = _layout_failure_validation(
			result.graph, preset, result.layout, chosen_attempt_seed
		)
		_finish_generation_timing(result, generation_start_usec)
		return result

	stage_start_usec = Time.get_ticks_usec()
	_workspace_builder.fit_task_layout_to_workspace(result.graph, preset, result.layout)
	_record_stage(result, &"workspace", stage_start_usec)

	# V2.8：先锁定 Task Ownership。Room 以后只能在 task_index_map 内部分区。
	stage_start_usec = Time.get_ticks_usec()
	result.raster = _rasterizer.rasterize_tasks(
		_derive_stage_seed(chosen_attempt_seed, 3),
		result.graph,
		result.layout,
		preset
	)
	result.full_rasterization_count = 1
	_record_stage(result, &"task_raster", stage_start_usec)

	stage_start_usec = Time.get_ticks_usec()
	_room_spatializer.layout_rooms(
		_derive_stage_seed(chosen_attempt_seed, 4),
		result.graph,
		preset,
		result.layout,
		result.raster
	)
	_record_stage(result, &"room_layout", stage_start_usec)

	stage_start_usec = Time.get_ticks_usec()
	_rasterizer.partition_rooms(result.graph, result.layout, result.raster)
	_record_stage(result, &"room_raster", stage_start_usec)

	stage_start_usec = Time.get_ticks_usec()
	var enforcement: Dictionary = _topology_enforcer.enforce(
		result.raster, result.graph, result.layout, preset
	)
	_record_stage(result, &"topology", stage_start_usec)

	stage_start_usec = Time.get_ticks_usec()
	result.validation = _validator.validate(
		result.raster,
		result.graph,
		result.layout,
		preset,
		int(enforcement.get("protected_conflicts", 0)),
		int(enforcement.get("removed_illegal_tiles", 0))
	)
	_record_stage(result, &"validation", stage_start_usec)

	stage_start_usec = Time.get_ticks_usec()
	result.boundary = _boundary_builder.build(
		result.raster.task_index_map,
		result.raster.size_tiles,
		preset
	)
	result.validation.boundary_fits_workspace = _boundary_fits_workspace(
		result.boundary, result.raster.size_tiles
	)
	_record_stage(result, &"boundary", stage_start_usec)

	stage_start_usec = Time.get_ticks_usec()
	result.road_paths = _road_network_generator.generate(result)
	_record_stage(result, &"roads", stage_start_usec)

	stage_start_usec = Time.get_ticks_usec()
	_resolve_final_spawn(result)
	_record_stage(result, &"spawn", stage_start_usec)

	_finish_generation_timing(result, generation_start_usec)
	return result


func _resolve_final_spawn(result: WorldGenResult) -> void:
	if result.graph == null or result.layout == null or result.raster == null:
		return

	var spawn_task_index: int = result.graph.world_start_task
	var spawn_rooms: Array = result.graph.task_rooms.get(spawn_task_index, []) as Array
	if spawn_rooms.is_empty():
		return

	# RoomGraph 的首个 Room 是可达性验证使用的正式起始 Room。
	var spawn_room_index: int = int(spawn_rooms[0])
	var target_position: Vector2 = Vector2(result.get_world_size_tiles()) * 0.5
	if result.layout.room_positions.has(spawn_room_index):
		target_position = result.layout.room_positions[spawn_room_index] as Vector2

	var best_tile: Vector2i = Vector2i(-1, -1)
	var best_clearance: int = -1
	var best_distance: float = INF
	var width: int = result.raster.size_tiles.x
	for map_index: int in range(result.raster.room_index_map.size()):
		if result.raster.task_index_map[map_index] != spawn_task_index:
			continue
		if result.raster.room_index_map[map_index] != spawn_room_index:
			continue

		var tile: Vector2i = Vector2i(
			map_index % width,
			floori(float(map_index) / float(width))
		)
		if not result.is_inside_gameplay_boundary_tile(
			Vector2(tile) + Vector2(0.5, 0.5)
		):
			continue

		var clearance: int = _measure_spawn_clearance(result, tile)
		var tile_center: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
		var distance: float = tile_center.distance_squared_to(target_position)
		if (
			clearance > best_clearance
			or (
				clearance == best_clearance
				and distance < best_distance
			)
		):
			best_clearance = clearance
			best_distance = distance
			best_tile = tile

	if best_tile.x >= 0:
		result.set_spawn(spawn_task_index, spawn_room_index, best_tile)


func _measure_spawn_clearance(result: WorldGenResult, tile: Vector2i) -> int:
	for radius: int in range(1, SPAWN_SAFETY_RADIUS_TILES + 1):
		for offset_y: int in range(-radius, radius + 1):
			for offset_x: int in range(-radius, radius + 1):
				if absi(offset_x) != radius and absi(offset_y) != radius:
					continue
				var neighbor: Vector2i = tile + Vector2i(offset_x, offset_y)
				if not result.is_tile_in_bounds(neighbor):
					return radius - 1
				if result.get_task_index_at_tile(neighbor) < 0:
					return radius - 1
				if not result.is_inside_gameplay_boundary_tile(
					Vector2(neighbor) + Vector2(0.5, 0.5)
				):
					return radius - 1
	return SPAWN_SAFETY_RADIUS_TILES



func _derive_stage_seed(base_seed: int, stream_id: int) -> int:
	# 各阶段使用独立确定性随机流；未来某阶段新增一次 rand 调用不会拖动后续阶段的 Seed。
	var value: int = base_seed ^ (stream_id * 0x45D9F3B)
	value = (value ^ (value >> 16)) * 0x45D9F3B
	value = value ^ (value >> 16)
	return value

func _record_stage(result: WorldGenResult, stage_name: StringName, start_usec: int) -> void:
	result.set_stage_timing(
		stage_name,
		float(Time.get_ticks_usec() - start_usec) / 1000.0
	)


func _finish_generation_timing(result: WorldGenResult, start_usec: int) -> void:
	result.generation_elapsed_ms = float(Time.get_ticks_usec() - start_usec) / 1000.0


func _graph_failure_validation(
	graph: WorldGenGraph,
	graph_check: Dictionary
) -> WorldGenValidationResult:
	var validation: WorldGenValidationResult = WorldGenValidationResult.new()
	validation.total_rooms = graph.rooms.size()
	validation.required_task_edges_total = graph.task_edges.size()
	validation.required_room_edges_total = graph.room_edges.size()
	validation.task_average_degree = float(graph_check.get("average_degree", 0.0))
	validation.task_degree_overflow_count = int(graph_check.get("overflow", 0))
	validation.task_degree_density_ok = bool(graph_check.get("degree_ok", false))
	validation.era_flow_valid = bool(graph_check.get("era_ok", false))
	validation.task_layout_shape_ok = false
	validation.topology_safe = false
	validation.valid = false
	return validation


func _layout_failure_validation(
	graph: WorldGenGraph,
	preset: WorldGenPreset,
	layout: WorldGenLayout,
	attempt_seed: int
) -> WorldGenValidationResult:
	var validation: WorldGenValidationResult = WorldGenValidationResult.new()
	validation.total_rooms = graph.rooms.size()
	validation.required_task_edges_total = graph.task_edges.size()
	validation.required_room_edges_total = graph.room_edges.size()
	var graph_check: Dictionary = _validator.evaluate_graph_structure(graph, preset)
	validation.task_average_degree = float(graph_check.get("average_degree", 0.0))
	validation.task_degree_overflow_count = int(graph_check.get("overflow", 0))
	validation.task_degree_density_ok = bool(graph_check.get("degree_ok", false))
	validation.era_flow_valid = bool(graph_check.get("era_ok", false))
	var layout_check: Dictionary = _validator.evaluate_task_layout(
		attempt_seed, graph, layout, preset
	)
	validation.overlong_task_edges = int(layout_check.get("overlong", 0))
	validation.task_layout_aspect_ratio = float(layout_check.get("aspect_ratio", INF))
	validation.spawn_center_offset_ratio = float(layout_check.get("spawn_offset_ratio", INF))
	validation.task_layout_shape_ok = false
	validation.topology_safe = false
	validation.valid = false
	return validation


func _boundary_fits_workspace(
	boundary: Variant,
	world_size_tiles: Vector2i
) -> bool:
	if boundary == null or boundary.visual_vertices_tiles.size() != 6:
		return false
	for vertex: Vector2 in boundary.visual_vertices_tiles:
		if (
			vertex.x < 0.0
			or vertex.y < 0.0
			or vertex.x > float(world_size_tiles.x)
			or vertex.y > float(world_size_tiles.y)
		):
			return false
	return true
