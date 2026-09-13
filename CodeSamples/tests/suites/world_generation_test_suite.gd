class_name WorldGenerationTestSuite
extends "res://tests/suites/frontier_test_suite.gd"


const TERRAIN_PATCH_CASES: Array[Dictionary] = [
	{
		"source": "res://art/world/terrain/e1_plains_ground.png",
		"atlas": "res://art/world/terrain/e1_plains_ground_atlas.png",
	},
	{
		"source": "res://art/world/terrain/e1_forests_grou.png",
		"atlas": "res://art/world/terrain/e1_forests_ground_atlas.png",
	},
	{
		"source": "res://art/world/terrain/e2_forests_grou.png",
		"atlas": "res://art/world/terrain/e2_forests_ground_atlas.png",
	},
	{
		"source": "res://art/world/terrain/e2_rocks_grou.png",
		"atlas": "res://art/world/terrain/e2_rocks_ground_atlas.png",
	},
	{
		"source": "res://art/world/terrain/e3_volcano_grou.png",
		"atlas": "res://art/world/terrain/e3_volcano_ground_atlas.png",
	},
	{
		"source": "res://art/world/terrain/e4_snowfield_grou.png",
		"atlas": "res://art/world/terrain/e4_snowfield_ground_atlas.png",
	},
	{
		"source": "res://art/world/terrain/sea_grou.png",
		"atlas": "res://art/world/terrain/sea_ground_atlas.png",
	},
]


func run() -> void:
	_test_terrain_patch_atlases()
	_test_world_generation()


func _test_world_generation() -> void:
	var pipeline := WorldGenPipeline.new()
	var preset := WorldGenDefaultPreset.build()
	_test_formal_era_biomes(preset)
	var deterministic_result: WorldGenResult = null
	var spawn_tiles_by_seed: Dictionary = {}
	for generation_seed: int in [1, 42, 123456, 987654321, 2147483646]:
		var result := pipeline.generate(generation_seed, preset)
		_expect(result != null, "Seed %d 必须返回生成结果" % generation_seed)
		if result == null:
			continue
		_expect(result.has_renderable_map(), "Seed %d 必须生成可渲染地图" % generation_seed)
		_expect(result.is_valid(), "Seed %d 必须可供游戏使用" % generation_seed)
		_expect(result.validation != null, "Seed %d 必须保留世界特征诊断" % generation_seed)
		_expect(
			result.graph.era_flow_mode == &"chain",
			"Seed %d 的正式时代拓扑必须是严格顺序链" % generation_seed
		)
		_test_strict_era_chain(result, generation_seed)
		_test_task_biome_assignments(result, preset, generation_seed)
		_test_ground_3d_build_for_result(result, generation_seed)
		if generation_seed in [1, 42, 123456]:
			print(
				(
					"Closure Seed Signature | Seed=%d | TaskHash=%d | RoomHash=%d | "
					+ "SpawnTask=%d | SpawnRoom=%d | SpawnTile=%s | Tasks=%d | Rooms=%d"
				)
				% [
					generation_seed,
					hash(result.raster.task_index_map),
					hash(result.raster.room_index_map),
					result.spawn_task_index,
					result.spawn_room_index,
					result.spawn_tile,
					result.graph.tasks.size(),
					result.graph.rooms.size(),
				]
			)
		_expect(result.has_spawn_position(), "Seed %d 必须保存最终出生位置" % generation_seed)
		if result.has_spawn_position():
			_expect(
				result.spawn_task_index == result.graph.world_start_task,
				"Seed %d 必须出生在 World Start Task" % generation_seed
			)
			var start_rooms: Array = result.graph.task_rooms.get(
				result.graph.world_start_task, []
			) as Array
			_expect(
				not start_rooms.is_empty()
				and result.spawn_room_index == int(start_rooms[0]),
				"Seed %d 必须出生在 Era1 正式起始 Room" % generation_seed
			)
			_expect(
				result.get_task_index_at_tile(result.spawn_tile) == result.spawn_task_index,
				"Seed %d 的出生 Tile 必须是真实 Era1 陆地" % generation_seed
			)
			_expect(
				result.spawn_position.is_equal_approx(result.tile_to_local(result.spawn_tile)),
				"Seed %d 的出生坐标必须由最终出生 Tile 固化" % generation_seed
			)
			spawn_tiles_by_seed[result.spawn_tile] = true
		if generation_seed == 42:
			deterministic_result = result
	_expect(spawn_tiles_by_seed.size() > 1, "不同 Seed 必须使用各自地图的出生 Tile")

	var repeated_result := pipeline.generate(42, preset)
	_expect(repeated_result != null, "同一 Seed 的重复生成必须返回结果")
	if deterministic_result != null and repeated_result != null:
		_expect(
			repeated_result.generation_seed == deterministic_result.generation_seed,
			"重复生成必须保留相同 World Seed"
		)
		_expect(
			repeated_result.raster.task_index_map == deterministic_result.raster.task_index_map,
			"同一 Seed 必须生成相同 Task TileMap"
		)
		_expect(
			repeated_result.raster.room_index_map == deterministic_result.raster.room_index_map,
			"同一 Seed 必须生成相同 Room TileMap"
		)
		_expect(
			repeated_result.spawn_tile == deterministic_result.spawn_tile,
			"同一 Seed 必须生成相同 Era1 出生 Tile"
		)
		_expect(
			repeated_result.spawn_position.is_equal_approx(
				deterministic_result.spawn_position
			),
			"同一 Seed 必须生成相同 Era1 出生点"
		)
		_test_runtime_player_spawn(deterministic_result)
		_test_world_debug_map_tools(deterministic_result)


func _test_formal_era_biomes(preset: WorldGenPreset) -> void:
	var expected_eras: Dictionary = {
		&"E1_PLAINS": 1,
		&"E1_FOREST": 1,
		&"E2_MOUNTAIN": 2,
		&"E2_FOREST": 2,
		&"E3_VOLCANO": 3,
		&"E4_SNOWFIELD": 4,
	}
	_expect(preset.get_era_ids() == [1, 2, 3, 4], "正式时代编号必须保持 1/2/3/4")
	for biome_id_variant: Variant in expected_eras.keys():
		var biome_id: StringName = StringName(biome_id_variant)
		var biome: WorldGenBiomeDefinition = preset.get_biome(biome_id)
		_expect(biome != null, "正式 Preset 必须包含 Biome %s" % biome_id)
		if biome == null:
			continue
		_expect(
			biome.era == int(expected_eras[biome_id]),
			"Biome %s 必须归属 Era%d" % [biome_id, expected_eras[biome_id]]
		)
		_expect(
			biome.terrain_patch != null and biome.terrain_patch.is_valid(),
			"Biome %s 必须配置有效地皮 Patch" % biome_id
		)
	_expect(preset.get_biome(&"E3_SNOW") == null, "不得保留 Era3 雪地旧语义")
	_expect(preset.get_biome(&"E4_VOLCANO") == null, "不得保留 Era4 火山旧语义")
	_expect(
		preset.ocean_terrain_patch != null
		and preset.ocean_terrain_patch.is_valid()
		and preset.ocean_terrain_patch.grid_size == Vector2i(10, 10)
		and Vector2i(preset.ocean_terrain_patch.source_texture.get_size())
		== Vector2i(1280, 1280),
		"正式 Preset 必须配置 1280x1280 的 10x10 海洋 Patch"
	)
	_expect(
		preset.get_biome(&"E3_VOLCANO").display_name == "火山",
		"Era3 中文调试语义必须是火山"
	)
	_expect(
		preset.get_biome(&"E4_SNOWFIELD").display_name == "雪原 / 雪山",
		"Era4 中文调试语义必须是雪原 / 雪山"
	)
	for biome: WorldGenBiomeDefinition in preset.biomes:
		if biome == null or biome.terrain_patch == null:
			continue
		var expected_grid: Vector2i = Vector2i(10, 10)
		_expect(
			biome.terrain_patch.grid_size == expected_grid,
			"Biome %s 必须使用正确的 Patch Grid" % biome.id
		)
		_expect(
			Vector2i(biome.terrain_patch.source_texture.get_size())
			== expected_grid * biome.terrain_patch.tile_size,
			"Biome %s 的 Atlas 尺寸必须等于 Grid×128" % biome.id
		)


func _test_ground_3d_build_for_result(
	result: WorldGenResult,
	generation_seed: int
) -> void:
	var holder: Node = Node.new()
	var runtime: WorldGeneratorRuntime = WorldGeneratorRuntime.new()
	runtime.position = Vector2(200.0, -120.0)
	runtime.worldgen_result = result
	runtime.worldgen_preset = result.preset
	runtime.generation_seed = generation_seed
	var bridge: WorldVisualBridge = WorldVisualBridge.new()
	var builder: Ground3DVisualBuilder = Ground3DVisualBuilder.new()
	var chunks_root: Node3D = Node3D.new()
	chunks_root.name = "Chunks"
	var water_3d: MeshInstance3D = MeshInstance3D.new()
	water_3d.name = "Water3D"
	builder.add_child(chunks_root)
	builder.add_child(water_3d)
	builder.chunks_root = chunks_root
	builder.water_mesh_instance = water_3d
	builder.visual_bridge = bridge
	holder.add_child(runtime)
	holder.add_child(bridge)
	holder.add_child(builder)
	get_tree().root.add_child(holder)

	runtime.call("_build_ground_render_resources")
	builder.bind_world_runtime(runtime)
	_expect(builder.has_built_world(),
		"Seed %d 必须实际构建 Ground3D 与 Water3D" % generation_seed)
	if not builder.has_built_world():
		holder.free()
		return
	_test_runtime_terrain_patch_bindings(runtime, result, builder)
	_test_debug_map_biome_colors(runtime, result)

	var metrics: Dictionary = builder.get_metrics()
	var tile_quad_count: int = int(metrics.get("tile_quad_count", 0))
	_expect(
		int(metrics.get("chunk_size_tiles", 0)) == 32
		and int(metrics.get("chunk_count", 0)) > 0
		and int(metrics.get("chunk_count", 0)) == chunks_root.get_child_count(),
		"Seed %d 必须使用 32x32 Tile Chunk，且统计与节点一致" % generation_seed
	)
	_expect(
		tile_quad_count > 0
		and int(metrics.get("vertex_count", 0)) <= tile_quad_count * 4 + 4
		and int(metrics.get("triangle_count", 0)) == tile_quad_count * 2 + 2,
		"Seed %d 的 Ground3D 必须保持每 Tile 两个三角形，同时共享相邻 Tile 顶点"
		% generation_seed
	)
	_expect(
		int(metrics.get("shared_vertex_savings", 0)) > 0,
		"Seed %d 的连续 Ground3D Tile 必须实际减少重复顶点" % generation_seed
	)
	_expect(
		int(metrics.get("material_count", 0)) == 2
		and int(metrics.get("texture_count", 0)) == 16
		and int(metrics.get("road_path_count", 0)) > 0
		and bool(metrics.get("road_mask_enabled", false)),
		"Seed %d 必须保持 Ground/Water 两个共享材质，并复用道路 Mask/时代图与四张道路材质"
		% generation_seed
	)
	_expect(
		float(metrics.get("build_time_ms", 0.0)) > 0.0
		and float(metrics.get("build_time_ms", 0.0)) < 30000.0,
		"Seed %d 的 Ground3D 构建不得达到数量级恶化" % generation_seed
	)

	var ground_material: ShaderMaterial = builder.get_ground_material()
	var water_material: ShaderMaterial = builder.get_water_material()
	_expect(
		ground_material != null
		and int(ground_material.get_shader_parameter("terrain_patch_count")) == 6
		and is_equal_approx(float(ground_material.get_shader_parameter(
			"biome_boundary_amplitude_px"
		)), 12.0),
		"Seed %d 的 Ground3D 必须绑定六种正式 Biome 和 12px 边界扰动"
		% generation_seed
	)
	_expect(
		water_material != null
		and water_material.get_shader_parameter("ocean_texture") != null
		and water_3d.mesh is ArrayMesh
		and water_3d.get_child_count() == 0,
		"Seed %d 的 Water3D 必须是一张共享材质的单 ArrayMesh Plane"
		% generation_seed
	)
	_expect(
		builder.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"Ground3D/Water3D 只能是视觉，不得创建 Physics3D"
	)

	var terrain_patches: Array[WorldGenTerrainPatchDefinition] = (
		runtime.get_terrain_patches_for_visual()
	)
	var seen_slots: Dictionary = {}
	var world_width: int = result.get_world_size_tiles().x
	for map_index: int in range(result.raster.task_index_map.size()):
		var task_index: int = result.raster.task_index_map[map_index]
		if task_index < 0:
			continue
		var tile: Vector2i = Vector2i(
			map_index % world_width,
			floori(float(map_index) / float(world_width))
		)
		var terrain_slot: int = builder.get_task_terrain_slot_at(tile)
		if terrain_slot < 0 or seen_slots.has(terrain_slot):
			continue
		seen_slots[terrain_slot] = true
		var patch: WorldGenTerrainPatchDefinition = terrain_patches[terrain_slot]
		_expect(
			patch.get_atlas_coords(tile) == Vector2i(
				posmod(tile.x - patch.patch_origin_tiles.x, patch.grid_size.x),
				posmod(tile.y - patch.patch_origin_tiles.y, patch.grid_size.y)
			),
			"Seed %d 的 Biome Slot %d 必须按绝对世界 Tile 计算 10x10 Atlas"
			% [generation_seed, terrain_slot]
		)
		if seen_slots.size() == 6:
			break
	_expect(seen_slots.size() == 6,
		"Seed %d 的 Ground3D 必须实际覆盖六种正式 Biome" % generation_seed)

	for patch: WorldGenTerrainPatchDefinition in terrain_patches:
		var left_of_chunk: Vector2i = patch.get_atlas_coords(Vector2i(31, 47))
		var right_of_chunk: Vector2i = patch.get_atlas_coords(Vector2i(32, 47))
		_expect(
			left_of_chunk == Vector2i(1, 7)
			and right_of_chunk == Vector2i(2, 7),
			"Seed %d 的 Atlas 不得在 32 Tile Chunk 边界重新从 (0,0) 开始"
			% generation_seed
		)

	for chunk_node: Node in chunks_root.get_children():
		var chunk_instance: MeshInstance3D = chunk_node as MeshInstance3D
		var first_tile: Vector2i = chunk_instance.get_meta(
			"first_tile",
			Vector2i(-1, -1)
		)
		var arrays: Array = (chunk_instance.mesh as ArrayMesh).surface_get_arrays(0)
		var chunk_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		_expect(
			not chunk_uvs.is_empty()
			and chunk_uvs[0] == Vector2(first_tile),
			"Seed %d 的每个 Chunk UV 必须从其绝对世界 Tile 开始" % generation_seed
		)

	var water_arrays: Array = (water_3d.mesh as ArrayMesh).surface_get_arrays(0)
	var water_vertices: PackedVector3Array = water_arrays[Mesh.ARRAY_VERTEX]
	var water_uvs: PackedVector2Array = water_arrays[Mesh.ARRAY_TEX_UV]
	_expect(
		water_vertices.size() == 4
		and is_equal_approx(water_vertices[0].y, -1.0)
		and water_uvs[0] == Vector2.ZERO
		and water_uvs[2] == Vector2(result.get_world_size_tiles()),
		"Seed %d 的 Water3D 必须覆盖完整 Raster 且位于 Ground3D 下方"
		% generation_seed
	)

	holder.free()


func _test_task_biome_assignments(
	result: WorldGenResult,
	preset: WorldGenPreset,
	generation_seed: int
) -> void:
	for task: WorldGenTaskNode in result.graph.tasks:
		if task == null or task.biome_id.is_empty():
			continue
		var biome: WorldGenBiomeDefinition = preset.get_biome(task.biome_id)
		_expect(
			biome != null,
			"Seed %d 的 Task %s 必须引用正式 Biome" % [generation_seed, task.id]
		)
		if biome != null:
			_expect(
				task.era == biome.era
				and task.biome_display_name == biome.display_name,
				"Seed %d 的 Task %s 必须继承正式 Era/Biome 语义"
				% [generation_seed, task.id]
			)


func _test_strict_era_chain(result: WorldGenResult, generation_seed: int) -> void:
	var transition_pairs: Dictionary = {}
	for edge: WorldGenEdge in result.graph.task_edges:
		if edge == null or edge.kind != &"transition":
			continue
		var task_a: WorldGenTaskNode = result.graph.get_task(edge.a)
		var task_b: WorldGenTaskNode = result.graph.get_task(edge.b)
		if task_a == null or task_b == null:
			continue
		var earlier_era: int = mini(task_a.era, task_b.era)
		var later_era: int = maxi(task_a.era, task_b.era)
		transition_pairs["%d:%d" % [earlier_era, later_era]] = true
	_expect(
		transition_pairs.keys().size() == 3
		and transition_pairs.has("1:2")
		and transition_pairs.has("2:3")
		and transition_pairs.has("3:4"),
		"Seed %d 只允许 Era1→2→3→4，不得出现 Era2→4 分叉" % generation_seed
	)


func _test_terrain_patch_atlases() -> void:
	const SOURCE_SIZE: Vector2i = Vector2i(1254, 1254)
	const ATLAS_SIZE: Vector2i = Vector2i(1280, 1280)
	const GRID_SIZE: Vector2i = Vector2i(10, 10)
	const TILE_SIZE: int = 128
	for patch_case: Dictionary in TERRAIN_PATCH_CASES:
		var source_path: String = String(patch_case["source"])
		var atlas_path: String = String(patch_case["atlas"])
		var source_texture: Texture2D = load(source_path) as Texture2D
		var atlas_texture: Texture2D = load(atlas_path) as Texture2D
		var source: Image = source_texture.get_image() if source_texture != null else null
		var atlas: Image = atlas_texture.get_image() if atlas_texture != null else null
		_expect(
			source != null and source.get_size() == SOURCE_SIZE,
			"地皮源图必须是 1254x1254：%s" % source_path
		)
		_expect(
			atlas != null and atlas.get_size() == ATLAS_SIZE,
			"地皮 Atlas 必须是 1280x1280：%s" % atlas_path
		)
		if atlas == null or atlas.get_size() != ATLAS_SIZE:
			continue
		var reconstructed: Image = Image.create(
			ATLAS_SIZE.x,
			ATLAS_SIZE.y,
			false,
			atlas.get_format()
		)
		for atlas_y: int in range(GRID_SIZE.y):
			for atlas_x: int in range(GRID_SIZE.x):
				var region: Rect2i = Rect2i(
					atlas_x * TILE_SIZE,
					atlas_y * TILE_SIZE,
					TILE_SIZE,
					TILE_SIZE
				)
				reconstructed.blit_rect(
					atlas,
					region,
					Vector2i(atlas_x * TILE_SIZE, atlas_y * TILE_SIZE)
				)
		_expect(
			reconstructed.get_data() == atlas.get_data(),
			"10x10 Tile 按行重组后必须逐字节还原 Atlas：%s" % atlas_path
		)

	var patch: WorldGenTerrainPatchDefinition = WorldGenTerrainPatchDefinition.new()
	patch.grid_size = GRID_SIZE
	patch.tile_size = TILE_SIZE
	_expect(patch.get_atlas_coords(Vector2i(0, 0)) == Vector2i(0, 0),
		"世界左上 Tile 必须映射 Atlas(0,0)")
	_expect(patch.get_atlas_coords(Vector2i(9, 0)) == Vector2i(9, 0),
		"世界第一行右端必须映射 Atlas(9,0)")
	_expect(patch.get_atlas_coords(Vector2i(0, 1)) == Vector2i(0, 1),
		"世界第二行必须映射 Atlas 第二行，Y 不得翻转")
	_expect(patch.get_atlas_coords(Vector2i(9, 9)) == Vector2i(9, 9),
		"完整 Patch 右下必须映射 Atlas(9,9)")
	_expect(patch.get_atlas_coords(Vector2i(10, 10)) == Vector2i(0, 0),
		"超过 10x10 后必须以完整 Patch 为单位周期重复")
	_expect(patch.get_atlas_coords(Vector2i(-1, -1)) == Vector2i(9, 9),
		"Patch 原点偏移必须使用 positive modulo")


func _test_world_debug_map_tools(result: WorldGenResult) -> void:
	var map_canvas: WorldDebugMapCanvas = WorldDebugMapCanvas.new()
	map_canvas.size = Vector2(960.0, 640.0)
	map_canvas.set_world_data(null, result)
	var spawn_map_position: Vector2 = map_canvas.tile_to_map_local_position(
		Vector2(result.spawn_tile) + Vector2(0.5, 0.5)
	)
	_expect(
		map_canvas.map_local_position_to_tile(spawn_map_position) == result.spawn_tile,
		"调试地图 UI 坐标必须按实际显示 Rect 往返到 Raster Tile"
	)
	map_canvas.free()

	var resolver: WorldDebugTeleportResolver = WorldDebugTeleportResolver.new()
	_expect(
		resolver.find_nearest_land_tile(result, result.spawn_tile, 96) == result.spawn_tile,
		"点击合法陆地必须直接返回该 Tile"
	)
	var ocean_tile: Vector2i = _find_nearby_ocean_tile(result, result.spawn_tile, 96)
	_expect(ocean_tile.x >= 0, "Era1 出生区域附近应存在可测试的海洋 Tile")
	if ocean_tile.x >= 0:
		var resolved_land: Vector2i = resolver.find_nearest_land_tile(result, ocean_tile, 96)
		_expect(resolved_land.x >= 0, "点击海洋必须在有限半径内找到最近陆地")
		if resolved_land.x >= 0:
			_expect(
				result.get_task_index_at_tile(resolved_land) >= 0,
				"海洋点击解析结果必须是真实陆地"
			)
			_expect(
				result.is_inside_gameplay_boundary_tile(
					Vector2(resolved_land) + Vector2(0.5, 0.5)
				),
				"海洋点击解析结果必须位于 Gameplay Boundary 内"
			)


func _find_nearby_ocean_tile(
	result: WorldGenResult,
	origin: Vector2i,
	max_radius: int
) -> Vector2i:
	for radius: int in range(1, max_radius + 1):
		for offset_y: int in range(-radius, radius + 1):
			for offset_x: int in range(-radius, radius + 1):
				if absi(offset_x) != radius and absi(offset_y) != radius:
					continue
				var candidate: Vector2i = origin + Vector2i(offset_x, offset_y)
				if (
					result.is_tile_in_bounds(candidate)
					and result.get_task_index_at_tile(candidate) < 0
				):
					return candidate
	return Vector2i(-1, -1)


func _test_runtime_player_spawn(result: WorldGenResult) -> void:
	var holder: Node2D = Node2D.new()
	get_tree().root.add_child(holder)
	var world_runtime: WorldGeneratorRuntime = WorldGeneratorRuntime.new()
	world_runtime.position = Vector2(200.0, -120.0)
	holder.add_child(world_runtime)
	var player: Node2D = Node2D.new()
	player.name = "Player"
	player.position = Vector2(55.0, 25.0)
	holder.add_child(player)

	world_runtime.set_player(player)
	world_runtime.worldgen_result = result
	world_runtime.worldgen_preset = result.preset
	world_runtime.generation_seed = result.generation_seed
	world_runtime.call("_build_ground_render_resources")
	var terrain_slots: PackedInt32Array = world_runtime.call(
		"_build_task_terrain_slots"
	)
	var corner_displacement: Vector2 = world_runtime.call(
		"_get_corner_displacement", Vector2i(20, 30), terrain_slots
	)
	var repeated_displacement: Vector2 = world_runtime.call(
		"_get_corner_displacement", Vector2i(20, 30), terrain_slots
	)
	_expect(
		corner_displacement.is_equal_approx(repeated_displacement),
		"同一 Seed、共享顶点和周围地形必须得到同一拐角位移"
	)
	world_runtime.generation_seed = result.generation_seed + 1
	var other_seed_displacement: Vector2 = world_runtime.call(
		"_get_corner_displacement", Vector2i(20, 30), terrain_slots
	)
	world_runtime.generation_seed = result.generation_seed
	_expect(
		not corner_displacement.is_equal_approx(other_seed_displacement),
		"不同 World Seed 必须能够得到不同的地形拐角位移"
	)
	_expect(
		corner_displacement.length() <= world_runtime.biome_boundary_amplitude_px + 0.01,
		"地形拐角位移不得超过配置振幅"
	)
	var straight_edge_noise: float = float(world_runtime.call(
		"_get_boundary_edge_noise_offset",
		Vector2i(20, 30),
		0,
		Vector2i(1, 5),
		0.375
	))
	_expect(
		not is_zero_approx(straight_edge_noise)
		and absf(straight_edge_noise) <= world_runtime.biome_boundary_amplitude_px,
		"直线边段也必须获得不超过统一振幅的确定性扰动"
	)
	var swapped_pair_noise: float = float(world_runtime.call(
		"_get_boundary_edge_noise_offset",
		Vector2i(20, 30),
		0,
		Vector2i(5, 1),
		0.375
	))
	_expect(
		is_equal_approx(straight_edge_noise, swapped_pair_noise),
		"同一共享边两侧交换地形顺序后必须得到相同直线扰动"
	)
	_expect(
		is_zero_approx(float(world_runtime.call(
			"_get_boundary_edge_noise_offset",
			Vector2i(20, 30),
			0,
			Vector2i(1, 5),
			0.0
		)))
		and is_zero_approx(float(world_runtime.call(
			"_get_boundary_edge_noise_offset",
			Vector2i(20, 30),
			0,
			Vector2i(5, 1),
			1.0
		))),
		"直线扰动必须在共享 Tile 顶点连续归零"
	)
	_expect(
		is_zero_approx(float(world_runtime.call(
			"_compose_corner_edge_offset", 0.0, 0.0, 0.125
		))),
		"无拐角的直线边必须保持零位移"
	)
	_expect(
		is_zero_approx(float(world_runtime.call(
			"_compose_corner_edge_offset", 12.0, 0.0, 0.5
		)))
		and not is_zero_approx(float(world_runtime.call(
			"_compose_corner_edge_offset", 12.0, 0.0, 0.125
		))),
		"拐角附加位移必须只在拐角附近 32px 内衰减"
	)
	_expect(int(world_runtime.get("_curved_corner_count")) > 0,
		"Runtime 必须识别并缓存地形边界拐角")
	_expect(int(world_runtime.get("_coast_boundary_edge_count")) > 0,
		"海岸必须作为视觉地形共享边参与缓存")
	_expect(int(world_runtime.get("_coast_corner_count")) > 0,
		"海岸线拐角必须参与确定性扰动")
	var test_pair: Vector2i = Vector2i(0, 1)
	var straight_vertical_edges: Dictionary = {
		Vector2i(10, 9): test_pair,
		Vector2i(10, 10): test_pair,
		Vector2i(10, 11): test_pair,
	}
	var no_horizontal_edges: Dictionary = {}
	_expect(
		not bool(world_runtime.call(
			"_is_vertical_edge_corner",
			Vector2i(10, 10),
			test_pair,
			true,
			straight_vertical_edges,
			no_horizontal_edges
		))
		and not bool(world_runtime.call(
			"_is_vertical_edge_corner",
			Vector2i(10, 10),
			test_pair,
			false,
			straight_vertical_edges,
			no_horizontal_edges
		)),
		"同一地形对连续延伸的纵向直线不得被识别为拐角"
	)
	var turning_horizontal_edges: Dictionary = {
		Vector2i(10, 10): test_pair,
	}
	_expect(
		bool(world_runtime.call(
			"_is_vertical_edge_corner",
			Vector2i(10, 10),
			test_pair,
			true,
			straight_vertical_edges,
			turning_horizontal_edges
		)),
		"边界在共享顶点转向时必须被识别为拐角"
	)
	var coast_pair: Vector2i = Vector2i(0, 6)
	_expect(
		bool(world_runtime.call("_terrain_pair_has_ocean", coast_pair)),
		"海洋地形对必须进入与陆地 Biome 相同的拐角分类流程"
	)
	_expect(bool(world_runtime.call("_move_player_to_spawn")),
		"Runtime 必须完成逻辑 Tile 与 Ground Sprite 的联合出生验证")
	_expect(
		player.global_position.is_equal_approx(world_runtime.to_global(result.spawn_position)),
		"Player 必须只消费 WorldGenResult.spawn_position"
	)
	_expect(
		not player.position.is_equal_approx(Vector2(55.0, 25.0)),
		"Player 不得保留场景中的初始 position 作为出生点"
	)
	holder.free()


func _test_runtime_terrain_patch_bindings(
	world: WorldGeneratorRuntime,
	result: WorldGenResult,
	ground_3d: Ground3DVisualBuilder
) -> void:
	_expect(
		world.get_node_or_null("GeneratedWorldGround") == null,
		"Runtime 不得再创建旧2D Ground Sprite"
	)
	_expect(ground_3d != null and ground_3d.has_built_world(),
		"正式 Ground3D 必须完成地表构建")
	if ground_3d == null:
		return
	var ground_material: ShaderMaterial = ground_3d.get_ground_material()
	var water_material: ShaderMaterial = ground_3d.get_water_material()
	_expect(
		ground_material != null and water_material != null,
		"Ground3D/Water3D 必须分别绑定正式 ShaderMaterial"
	)
	if ground_material == null or water_material == null:
		return
	_expect(
		int(ground_material.get_shader_parameter("terrain_patch_count")) == 6,
		"Ground3D 必须绑定六种正式 Biome 地皮"
	)
	_expect(
		bool(ground_material.get_shader_parameter("road_enabled"))
		and bool(ground_material.get_shader_parameter("road_has_e1"))
		and bool(ground_material.get_shader_parameter("road_has_e2"))
		and bool(ground_material.get_shader_parameter("road_has_e3"))
		and bool(ground_material.get_shader_parameter("road_has_e4"))
		and ground_material.get_shader_parameter("road_texture_e1") != null
		and ground_material.get_shader_parameter("road_texture_e2") != null
		and ground_material.get_shader_parameter("road_texture_e3") != null
		and ground_material.get_shader_parameter("road_texture_e4") != null
		and ground_material.get_shader_parameter("road_mask_texture") != null
		and ground_material.get_shader_parameter("road_era_texture") != null,
		"Ground3D 必须复用 TerrainPatch 语义绑定 E1/E2/E3/E4 道路材质和程序道路 Mask"
	)
	_expect(
		water_material.get_shader_parameter("ocean_texture") != null
		and water_material.get_shader_parameter("ocean_grid") == Vector2(10.0, 10.0),
		"Water3D 必须绑定 10x10 海洋 Atlas"
	)
	_expect(
		bool(water_material.get_shader_parameter("ocean_flow_enabled")),
		"Water3D 海洋 Atlas 默认必须启用 Shader UV 流动"
	)
	_expect(
		Vector2(water_material.get_shader_parameter(
			"ocean_flow_speed_tiles_per_second"
		)).is_equal_approx(Vector2(0.016666666, 0.005555556))
		and is_equal_approx(
			float(water_material.get_shader_parameter("ocean_flow_wobble_tiles")),
			0.025
		),
		"海洋流动速度和轻微摆动必须由 Runtime 参数传给 Water3D Shader"
	)
	var vertical_edges: Texture2D = ground_material.get_shader_parameter(
		"vertical_biome_edges"
	) as Texture2D
	var horizontal_edges: Texture2D = ground_material.get_shader_parameter(
		"horizontal_biome_edges"
	) as Texture2D
	var world_size: Vector2i = result.get_world_size_tiles()
	_expect(
		vertical_edges != null
		and Vector2i(vertical_edges.get_size()) == Vector2i(
			world_size.x + 1,
			world_size.y * 8 + 1
		),
		"Runtime 必须缓存一张纵向共享边曲线纹理"
	)
	_expect(
		horizontal_edges != null
		and Vector2i(horizontal_edges.get_size()) == Vector2i(
			world_size.x * 8 + 1,
			world_size.y + 1
		),
		"Runtime 必须缓存一张横向共享边曲线纹理"
	)
	_expect(
		is_equal_approx(
			float(ground_material.get_shader_parameter("biome_boundary_amplitude_px")),
			12.0
		),
		"Biome 与海岸边界扰动振幅必须统一为 12px"
	)
	for patch_slot: int in range(6):
		_expect(
			ground_material.get_shader_parameter("terrain_texture_%d" % patch_slot) != null,
			"Ground3D 地皮 Shader Slot %d 必须绑定 Atlas" % patch_slot
		)

	var seen_biomes: Dictionary = {}
	var saw_ocean_marker: bool = false
	var width: int = result.get_world_size_tiles().x
	var marker_texture: Texture2D = world.get_ground_marker_texture_for_visual()
	_expect(marker_texture != null, "Runtime 必须保留仅供Ground3D消费的Raster标记纹理")
	if marker_texture == null:
		return
	var ground_image: Image = marker_texture.get_image()
	for map_index: int in range(result.raster.task_index_map.size()):
		var task_index: int = result.raster.task_index_map[map_index]
		if task_index < 0:
			var ocean_tile: Vector2i = Vector2i(
				map_index % width,
				floori(float(map_index) / float(width))
			)
			if (
				result.is_inside_visual_boundary_tile(
					Vector2(ocean_tile) + Vector2(0.5, 0.5)
				)
				and ground_image.get_pixelv(ocean_tile).to_rgba32()
				== Color.BLACK.to_rgba32()
			):
				saw_ocean_marker = true
			continue
		var task: WorldGenTaskNode = result.graph.get_task(task_index)
		if task == null or seen_biomes.has(task.biome_id):
			continue
		seen_biomes[task.biome_id] = true
		var tile: Vector2i = Vector2i(
			map_index % width,
			floori(float(map_index) / float(width))
		)
		var source_pixel: Color = ground_image.get_pixelv(tile)
		_expect(
			source_pixel.r < 0.02 or source_pixel.r > 0.98,
			"Biome %s 的 Ground3D Raster源必须使用精确Shader哨兵色" % task.biome_id
		)
	_expect(seen_biomes.size() == 6, "Runtime 地图必须实际包含六种正式 Biome")
	_expect(saw_ocean_marker, "Runtime必须为Water3D写入海洋Raster哨兵")


func _test_debug_map_biome_colors(
	world: WorldGeneratorRuntime,
	result: WorldGenResult
) -> void:
	var debug_texture: Texture2D = world.get_debug_map_texture()
	if debug_texture == null:
		return
	var debug_image: Image = debug_texture.get_image()
	var checked_biomes: Dictionary = {}
	var checked_ocean: bool = false
	var width: int = result.get_world_size_tiles().x
	for map_index: int in range(result.raster.task_index_map.size()):
		var task_index: int = result.raster.task_index_map[map_index]
		if task_index < 0:
			var ocean_tile: Vector2i = Vector2i(
				map_index % width,
				floori(float(map_index) / float(width))
			)
			if (
				not checked_ocean
				and result.is_inside_visual_boundary_tile(
					Vector2(ocean_tile) + Vector2(0.5, 0.5)
				)
			):
				checked_ocean = true
				_expect(
					debug_image.get_pixelv(ocean_tile).to_rgba32()
					== result.preset.ocean_color.to_rgba32(),
					"M 调试地图必须继续用正式海洋调试颜色"
				)
			continue
		var task: WorldGenTaskNode = result.graph.get_task(task_index)
		if task == null or checked_biomes.has(task.biome_id):
			continue
		checked_biomes[task.biome_id] = true
		var tile: Vector2i = Vector2i(
			map_index % width,
			floori(float(map_index) / float(width))
		)
		_expect(
			debug_image.get_pixelv(tile).to_rgba32()
			== task.placeholder_color.to_rgba32(),
			"M 调试地图必须读取 Biome 正式调试颜色：%s" % task.biome_id
		)
	_expect(checked_biomes.size() == 6, "M 调试地图必须覆盖六种正式 Biome")
	_expect(checked_ocean, "M 调试地图必须包含可视海洋区域")


func _find_distant_land_tile(
	result: WorldGenResult,
	origin: Vector2i
) -> Vector2i:
	var width: int = result.get_world_size_tiles().x
	var minimum_distance_squared: int = 100 * 100
	for map_index: int in range(result.raster.task_index_map.size()):
		if result.raster.task_index_map[map_index] < 0:
			continue
		var candidate: Vector2i = Vector2i(
			map_index % width,
			floori(float(map_index) / float(width))
		)
		if candidate.distance_squared_to(origin) < minimum_distance_squared:
			continue
		if result.is_inside_gameplay_boundary_tile(
			Vector2(candidate) + Vector2(0.5, 0.5)
		):
			return candidate
	return Vector2i(-1, -1)
