class_name WorldGenRoadNetworkGenerator
extends RefCounted


const CONNECTOR_CONTACT_SEARCH_RADIUS_TILES: int = 24
const ROAD_CURVE_MAX_OFFSET_TILES: float = 8.0
const ROAD_CURVE_MIN_LENGTH_TILES: float = 10.0
const ROAD_CURVE_ITERATIONS: int = 2


var _result: WorldGenResult = null
var _queue: PackedInt32Array = PackedInt32Array()
var _previous: PackedInt32Array = PackedInt32Array()
var _visit_stamp: PackedInt32Array = PackedInt32Array()
var _stamp: int = 0


func generate(result: WorldGenResult) -> Array[WorldGenRoadPath]:
	var roads: Array[WorldGenRoadPath] = []
	_result = result
	if (
		result == null
		or result.preset == null
		or result.graph == null
		or result.layout == null
		or result.raster == null
		or not result.raster.is_complete()
	):
		return roads

	var tile_count: int = result.raster.tile_count()
	_queue.resize(tile_count)
	_previous.resize(tile_count)
	_visit_stamp.resize(tile_count)
	_visit_stamp.fill(0)
	_stamp = 0

	# Room Graph 的 chain 是每个 Task 的连通骨架。道路只沿骨架生成，
	# 不把 loop/crosslink 全部铺成路，避免首版路网过密。
	for edge: WorldGenEdge in result.graph.room_edges:
		if edge == null or edge.kind != &"chain":
			continue
		var room_a: WorldGenRoomNode = result.graph.get_room(edge.a)
		var room_b: WorldGenRoomNode = result.graph.get_room(edge.b)
		if (
			room_a == null
			or room_b == null
			or room_a.task_index != room_b.task_index
			or not _supports_road_era(room_a.era)
			or not result.layout.room_positions.has(room_a.index)
			or not result.layout.room_positions.has(room_b.index)
		):
			continue
		var points: PackedVector2Array = _route_inside_task(
			result.layout.room_positions[room_a.index] as Vector2,
			result.layout.room_positions[room_b.index] as Vector2,
			room_a.task_index,
			edge.a,
			edge.b
		)
		_append_road(roads, room_a.task_index, room_a.era, &"room_chain", points)

	# Task Graph 连接点已经是正式地形拓扑的真实锚点。这里把各 Task 内部路网
	# 接到真实接触边界，跨 Task / 跨时代时道路自然在同一连接处会合。
	var task_count: int = maxi(1, result.graph.tasks.size())
	for edge: WorldGenEdge in result.graph.task_edges:
		if edge == null:
			continue
		var task_a: WorldGenTaskNode = result.graph.get_task(edge.a)
		var task_b: WorldGenTaskNode = result.graph.get_task(edge.b)
		if task_a == null or task_b == null:
			continue
		var pair_key: int = WorldGenPairUtils.pair_key_int(edge.a, edge.b, task_count)
		if not result.layout.task_edge_anchors.has(pair_key):
			continue
		var anchor: Vector2 = result.layout.task_edge_anchors[pair_key] as Vector2
		var contact: Dictionary = _find_task_contact_pair(edge.a, edge.b, anchor)
		if contact.is_empty():
			continue
		_append_task_connector(roads, task_a, contact["a"] as Vector2i)
		_append_task_connector(roads, task_b, contact["b"] as Vector2i)

	_result = null
	_queue = PackedInt32Array()
	_previous = PackedInt32Array()
	_visit_stamp = PackedInt32Array()
	return roads


func _supports_road_era(era: int) -> bool:
	return _result.preset.get_road_terrain_patch_for_era(era) != null


func _append_task_connector(
	roads: Array[WorldGenRoadPath],
	task: WorldGenTaskNode,
	contact_tile: Vector2i
) -> void:
	if task == null or not _supports_road_era(task.era):
		return
	var contact_position: Vector2 = Vector2(contact_tile) + Vector2(0.5, 0.5)
	var room_index: int = _nearest_room_in_task(task.index, contact_position)
	if room_index < 0 or not _result.layout.room_positions.has(room_index):
		return
	var points: PackedVector2Array = _route_inside_task(
		_result.layout.room_positions[room_index] as Vector2,
		contact_position,
		task.index,
		room_index,
		contact_tile.x * 4099 + contact_tile.y
	)
	_append_road(roads, task.index, task.era, &"task_connector", points)


func _append_road(
	roads: Array[WorldGenRoadPath],
	task_index: int,
	era: int,
	kind: StringName,
	points: PackedVector2Array
) -> void:
	if points.size() < 2:
		return
	var road: WorldGenRoadPath = WorldGenRoadPath.new()
	road.task_index = task_index
	road.era = era
	road.kind = kind
	road.points = points
	roads.append(road)


func _route_inside_task(
	start_position: Vector2,
	goal_position: Vector2,
	task_index: int,
	key_a: int,
	key_b: int
) -> PackedVector2Array:
	var start_index: int = _nearest_task_tile(start_position, task_index)
	var goal_index: int = _nearest_task_tile(goal_position, task_index)
	if start_index < 0 or goal_index < 0:
		return PackedVector2Array()

	var direct_delta: Vector2 = goal_position - start_position
	var raster_path: PackedInt32Array = PackedInt32Array()
	if direct_delta.length() >= ROAD_CURVE_MIN_LENGTH_TILES:
		var perpendicular: Vector2 = Vector2(-direct_delta.y, direct_delta.x).normalized()
		var signed_curve: float = _stable_signed_noise(key_a, key_b)
		var curve_offset: float = minf(
			direct_delta.length() * 0.15,
			ROAD_CURVE_MAX_OFFSET_TILES
		) * signed_curve
		var waypoint_position: Vector2 = (
			(start_position + goal_position) * 0.5
			+ perpendicular * curve_offset
		)
		var waypoint_index: int = _nearest_task_tile(waypoint_position, task_index)
		if waypoint_index >= 0 and waypoint_index != start_index and waypoint_index != goal_index:
			var first_half: PackedInt32Array = _find_task_path_bfs(
				start_index, waypoint_index, task_index
			)
			var second_half: PackedInt32Array = _find_task_path_bfs(
				waypoint_index, goal_index, task_index
			)
			if not first_half.is_empty() and not second_half.is_empty():
				raster_path = first_half
				for i: int in range(1, second_half.size()):
					raster_path.append(second_half[i])
	if raster_path.is_empty():
		raster_path = _find_task_path_bfs(start_index, goal_index, task_index)
	if raster_path.is_empty():
		return PackedVector2Array()

	var points: PackedVector2Array = _raster_path_to_points(raster_path)
	points = _simplify_collinear(points)
	for _iteration: int in range(ROAD_CURVE_ITERATIONS):
		points = _chaikin(points)
	return points


func _find_task_path_bfs(
	start_index: int,
	goal_index: int,
	task_index: int
) -> PackedInt32Array:
	_stamp += 1
	if _stamp >= 0x7FFFFFF0:
		_visit_stamp.fill(0)
		_stamp = 1
	var width: int = _result.raster.size_tiles.x
	var tile_count: int = _result.raster.tile_count()
	var head: int = 0
	var tail: int = 1
	_queue[0] = start_index
	_visit_stamp[start_index] = _stamp
	_previous[start_index] = -1
	var found: bool = start_index == goal_index

	while head < tail and not found:
		var current: int = _queue[head]
		head += 1
		var current_y: int = floori(float(current) / float(width))
		var current_x: int = current - current_y * width
		var neighbors: PackedInt32Array = PackedInt32Array([
			current - 1,
			current + 1,
			current - width,
			current + width,
		])
		for next_index: int in neighbors:
			if next_index < 0 or next_index >= tile_count:
				continue
			if _visit_stamp[next_index] == _stamp:
				continue
			var next_y: int = floori(float(next_index) / float(width))
			var next_x: int = next_index - next_y * width
			if absi(next_x - current_x) + absi(next_y - current_y) != 1:
				continue
			if _result.raster.task_index_map[next_index] != task_index:
				continue
			_visit_stamp[next_index] = _stamp
			_previous[next_index] = current
			_queue[tail] = next_index
			tail += 1
			if next_index == goal_index:
				found = true
				break

	if not found:
		return PackedInt32Array()
	var reverse_path: PackedInt32Array = PackedInt32Array()
	var cursor: int = goal_index
	while cursor >= 0:
		reverse_path.append(cursor)
		if cursor == start_index:
			break
		cursor = _previous[cursor]
	var result: PackedInt32Array = PackedInt32Array()
	for i: int in range(reverse_path.size() - 1, -1, -1):
		result.append(reverse_path[i])
	return result


func _nearest_task_tile(position: Vector2, task_index: int) -> int:
	var tile: Vector2i = Vector2i(floori(position.x), floori(position.y))
	if _result.raster.is_in_bounds(tile):
		var direct_index: int = _result.raster.index_of(tile)
		if _result.raster.task_index_map[direct_index] == task_index:
			return direct_index
	if task_index < 0 or task_index >= _result.raster.task_bounds.size():
		return -1
	var bounds: Rect2i = _result.raster.task_bounds[task_index]
	var best_index: int = -1
	var best_distance_squared: float = INF
	var width: int = _result.raster.size_tiles.x
	for y: int in range(maxi(0, bounds.position.y), mini(bounds.end.y, _result.raster.size_tiles.y)):
		var row: int = y * width
		for x: int in range(maxi(0, bounds.position.x), mini(bounds.end.x, _result.raster.size_tiles.x)):
			var map_index: int = row + x
			if _result.raster.task_index_map[map_index] != task_index:
				continue
			var point: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var distance_squared: float = point.distance_squared_to(position)
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_index = map_index
	return best_index


func _nearest_room_in_task(task_index: int, position: Vector2) -> int:
	var room_indices: Array = _result.graph.task_rooms.get(task_index, []) as Array
	var best_room: int = -1
	var best_distance_squared: float = INF
	for room_variant: Variant in room_indices:
		var room_index: int = int(room_variant)
		if not _result.layout.room_positions.has(room_index):
			continue
		var room_position: Vector2 = _result.layout.room_positions[room_index] as Vector2
		var distance_squared: float = room_position.distance_squared_to(position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_room = room_index
	return best_room


func _find_task_contact_pair(
	task_a: int,
	task_b: int,
	anchor: Vector2
) -> Dictionary:
	var local_result: Dictionary = _scan_task_contact_pair(
		task_a,
		task_b,
		anchor,
		CONNECTOR_CONTACT_SEARCH_RADIUS_TILES
	)
	if not local_result.is_empty():
		return local_result
	# 极端布局回退：只在局部锚点扫描失败时才扫描整张图。
	return _scan_task_contact_pair(task_a, task_b, anchor, -1)


func _scan_task_contact_pair(
	task_a: int,
	task_b: int,
	anchor: Vector2,
	radius: int
) -> Dictionary:
	var size: Vector2i = _result.raster.size_tiles
	var min_x: int = 0
	var min_y: int = 0
	var max_x: int = size.x
	var max_y: int = size.y
	if radius >= 0:
		min_x = maxi(0, floori(anchor.x) - radius)
		min_y = maxi(0, floori(anchor.y) - radius)
		max_x = mini(size.x, floori(anchor.x) + radius + 1)
		max_y = mini(size.y, floori(anchor.y) + radius + 1)
	var best_a: Vector2i = Vector2i(-1, -1)
	var best_b: Vector2i = Vector2i(-1, -1)
	var best_distance_squared: float = INF
	for y: int in range(min_y, max_y):
		for x: int in range(min_x, max_x):
			var tile_a: Vector2i = Vector2i(x, y)
			if _result.raster.get_task_at(tile_a) != task_a:
				continue
			for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
				var tile_b: Vector2i = tile_a + direction
				if not _result.raster.is_in_bounds(tile_b):
					continue
				if _result.raster.get_task_at(tile_b) != task_b:
					continue
				var midpoint: Vector2 = (Vector2(tile_a) + Vector2(tile_b)) * 0.5 + Vector2(0.5, 0.5)
				var distance_squared: float = midpoint.distance_squared_to(anchor)
				if distance_squared < best_distance_squared:
					best_distance_squared = distance_squared
					best_a = tile_a
					best_b = tile_b
	if best_a.x < 0:
		return {}
	return {"a": best_a, "b": best_b}


func _raster_path_to_points(path: PackedInt32Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var width: int = _result.raster.size_tiles.x
	for map_index: int in path:
		var y: int = floori(float(map_index) / float(width))
		var x: int = map_index - y * width
		result.append(Vector2(float(x) + 0.5, float(y) + 0.5))
	return result


func _simplify_collinear(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 2:
		return points
	var result: PackedVector2Array = PackedVector2Array([points[0]])
	for i: int in range(1, points.size() - 1):
		var previous_direction: Vector2 = (points[i] - points[i - 1]).normalized()
		var next_direction: Vector2 = (points[i + 1] - points[i]).normalized()
		if previous_direction.is_equal_approx(next_direction):
			continue
		result.append(points[i])
	result.append(points[points.size() - 1])
	return result


func _chaikin(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 2:
		return points
	var result: PackedVector2Array = PackedVector2Array([points[0]])
	for i: int in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		result.append(a.lerp(b, 0.25))
		result.append(a.lerp(b, 0.75))
	result.append(points[points.size() - 1])
	return result


func _stable_signed_noise(key_a: int, key_b: int) -> float:
	var low: int = mini(key_a, key_b)
	var high: int = maxi(key_a, key_b)
	var value: int = int(_result.generation_seed) ^ (low * 92837111) ^ (high * 689287499)
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	var normalized: float = float(absi(value) % 20001) / 10000.0 - 1.0
	if absf(normalized) < 0.28:
		normalized = 0.28 if normalized >= 0.0 else -0.28
	return normalized
