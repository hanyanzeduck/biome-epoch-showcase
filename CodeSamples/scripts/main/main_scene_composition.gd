class_name MainSceneComposition
extends Node


func _enter_tree() -> void:
	var world := get_node_or_null("World") as Node2D
	var player := get_node_or_null("Player") as Node2D
	var gameplay_systems := get_node_or_null("GameplaySystems")
	var ui_shell := get_node_or_null("UIShell")
	var prototype_fixtures := get_node_or_null("PrototypeFixtures")
	if world == null or player == null or gameplay_systems == null or ui_shell == null:
		push_error("MainSceneComposition 无法找到主场景装配节点。")
		return

	var dependencies := _collect_player_dependencies(player)
	_bind_world_runtime(world, player)
	_bind_visual_world(world, player)
	_bind_gameplay_systems(gameplay_systems, world, player, dependencies)
	_bind_player_controllers(player, world, gameplay_systems)
	dependencies[&"building_placement"] = gameplay_systems.get_node_or_null(
		"BuildingPlacement"
	)
	_inject_known_dependencies(ui_shell, dependencies)
	if prototype_fixtures != null:
		_inject_property(prototype_fixtures, &"world_parent", world)


func _collect_player_dependencies(player: Node2D) -> Dictionary:
	return {
		&"inventory_component": player.get_node_or_null("InventoryComponent"),
		&"player_inventory": player.get_node_or_null("InventoryComponent"),
		&"crafting_component": player.get_node_or_null("CraftingComponent"),
		&"technology_component": player.get_node_or_null("TechnologyComponent"),
		&"work_capability_component": player.get_node_or_null("WorkCapabilityComponent"),
		&"party_component": player.get_node_or_null("PartyComponent"),
		&"health_component": player.get_node_or_null("HealthComponent"),
		&"progression_component": player.get_node_or_null("PlayerProgressionComponent"),
		&"combat_stats_component": player.get_node_or_null("CombatStatsComponent"),
		&"hunger_component": player.get_node_or_null("HungerComponent"),
		&"equipment_component": player.get_node_or_null("PlayerEquipmentComponent"),
		&"environment_exposure_component": player.get_node_or_null("PlayerEnvironmentExposureComponent"),
		&"fera_storage_component": player.get_node_or_null("FeraStorageComponent"),
		&"player_input_controller": player.get_node_or_null("PlayerInputController"),
	}


func _bind_world_runtime(world: Node2D, player: Node2D) -> void:
	var world_runtime: WorldGeneratorRuntime = world as WorldGeneratorRuntime
	if world_runtime == null:
		push_error("MainSceneComposition 的 World 不是 WorldGeneratorRuntime。")
		return
	world_runtime.set_player(player)


func _bind_visual_world(world: Node2D, player: Node2D) -> void:
	var visual_world: Node = get_node_or_null("VisualWorld")
	if visual_world == null:
		push_error("MainSceneComposition 找不到 VisualWorld。")
		return

	var visual_bridge: WorldVisualBridge = visual_world.get_node_or_null(
		"WorldVisualBridge"
	) as WorldVisualBridge
	var ground_3d: Ground3DVisualBuilder = visual_world.get_node_or_null(
		"Ground3D"
	) as Ground3DVisualBuilder
	var camera_rig: VisualCameraRig = visual_world.get_node_or_null(
		"CameraRig"
	) as VisualCameraRig
	var object_visual_manager: WorldObjectVisual3DManager = visual_world.get_node_or_null(
		"ObjectVisuals"
	) as WorldObjectVisual3DManager
	var world_sprite_renderer: WorldSpriteRenderer = visual_world.get_node_or_null(
		"WorldSpriteRenderer"
	) as WorldSpriteRenderer
	var dynamic_visual_manager: DynamicVisual3DManager = visual_world.get_node_or_null(
		"DynamicVisuals"
	) as DynamicVisual3DManager
	var world_runtime: WorldGeneratorRuntime = world as WorldGeneratorRuntime

	# These two presentation routes form one unit: screen-space billboards are
	# handled by WorldSpriteRenderer, while ground/world-oriented objects are
	# delegated to ObjectVisuals. Build and wire them here so serialized NodePath
	# ordering cannot leave half of the visual pipeline unavailable.
	if object_visual_manager == null:
		object_visual_manager = WorldObjectVisual3DManager.new()
		object_visual_manager.name = "ObjectVisuals"
		visual_world.add_child(object_visual_manager)
	object_visual_manager.visual_bridge = visual_bridge
	object_visual_manager.camera_rig = camera_rig

	if world_sprite_renderer == null:
		world_sprite_renderer = WorldSpriteRenderer.new()
		world_sprite_renderer.name = "WorldSpriteRenderer"
		visual_world.add_child(world_sprite_renderer)
	world_sprite_renderer.visual_bridge = visual_bridge
	world_sprite_renderer.camera_rig = camera_rig
	world_sprite_renderer.ground_object_visual_manager = object_visual_manager

	# Player presentation remains an explicit special case because CameraRig
	# follows the player at the viewport centre.
	var player_screen_presenter: PlayerScreenPresenter = visual_world.get_node_or_null(
		"PlayerScreenPresenter"
	) as PlayerScreenPresenter
	if player_screen_presenter == null:
		player_screen_presenter = PlayerScreenPresenter.new()
		player_screen_presenter.name = "PlayerScreenPresenter"
		visual_world.add_child(player_screen_presenter)
	player_screen_presenter.world_sprite_renderer = world_sprite_renderer
	player_screen_presenter.set_player(player)

	# Do not use one all-or-nothing skeleton check. Report the exact missing part,
	# then bind every subsystem that is actually available.
	var missing: Array[String] = []
	if visual_bridge == null:
		missing.append("WorldVisualBridge")
	if ground_3d == null:
		missing.append("Ground3D")
	if camera_rig == null:
		missing.append("CameraRig")
	if dynamic_visual_manager == null:
		missing.append("DynamicVisuals")
	if not missing.is_empty():
		push_warning(
			"MainSceneComposition 的 VisualWorld 缺少: %s；可用子系统继续启动。"
			% ", ".join(missing)
		)

	if world_runtime != null and ground_3d != null:
		ground_3d.bind_world_runtime(world_runtime)
	if camera_rig != null and visual_bridge != null:
		camera_rig.set_follow_target(player, visual_bridge)

	var input_controller: Node = player.get_node_or_null("PlayerInputController")
	if input_controller != null:
		if camera_rig != null:
			_set_property_if_present(input_controller, &"visual_camera_rig", camera_rig)
		if visual_bridge != null:
			_set_property_if_present(input_controller, &"world_visual_bridge", visual_bridge)


func _bind_gameplay_systems(
	gameplay_systems: Node,
	world: Node2D,
	player: Node2D,
	dependencies: Dictionary
) -> void:
	var placement := gameplay_systems.get_node_or_null("BuildingPlacement")
	if placement != null:
		_set_property_if_present(
			placement, &"inventory_component", dependencies.get(&"inventory_component")
		)
		_set_property_if_present(
			placement, &"technology_component", dependencies.get(&"technology_component")
		)
		_set_property_if_present(placement, &"world_parent", world)
		_set_property_if_present(
			placement,
			&"world_object_visual_manager",
			get_node_or_null("VisualWorld/WorldSpriteRenderer")
		)
		var alignment_overlay: BuildingAlignmentGridOverlay = get_node_or_null(
			"VisualWorld/BuildingPlacementOverlay3D"
		) as BuildingAlignmentGridOverlay
		var visual_bridge: WorldVisualBridge = get_node_or_null(
			"VisualWorld/WorldVisualBridge"
		) as WorldVisualBridge
		if alignment_overlay != null:
			alignment_overlay.configure_bridge(visual_bridge)
			placement.call(&"set_alignment_grid_overlay", alignment_overlay)

	var deployment := gameplay_systems.get_node_or_null("PartyDeploymentController")
	if deployment != null:
		_set_property_if_present(
			deployment, &"party_component", dependencies.get(&"party_component")
		)
		_set_property_if_present(deployment, &"party_owner", player)
		_set_property_if_present(
			deployment, &"deploy_point", player.get_node_or_null("PartyDeployPoint")
		)
		_set_property_if_present(deployment, &"world_parent", world)

	var wild_runtime := gameplay_systems.get_node_or_null(
		"WildPopulationRuntime"
	) as WildPopulationRuntime
	if wild_runtime != null:
		wild_runtime.bind_runtime(
			world as WorldGeneratorRuntime,
			player,
			get_node_or_null("VisualWorld/WorldVisualBridge") as WorldVisualBridge,
			gameplay_systems.get_node_or_null("WorldTimeManager") as WorldTimeManagerClass
		)


func _bind_player_controllers(
	player: Node2D,
	world: Node2D,
	gameplay_systems: Node
) -> void:
	var input_controller := player.get_node_or_null("PlayerInputController")
	if input_controller != null:
		_set_property_if_present(
			input_controller,
			&"party_deployment_controller",
			gameplay_systems.get_node_or_null("PartyDeploymentController")
		)
		_set_property_if_present(
			input_controller,
			&"building_placement",
			gameplay_systems.get_node_or_null("BuildingPlacement")
		)

	var held_item_controller := player.get_node_or_null("PlayerHeldItemController")
	if held_item_controller != null:
		_set_property_if_present(held_item_controller, &"world_parent", world)


func _inject_known_dependencies(branch: Node, dependencies: Dictionary) -> void:
	for property_variant: Variant in dependencies.keys():
		var property_name := StringName(property_variant)
		_set_property_if_present(branch, property_name, dependencies[property_name])
	for child: Node in branch.get_children():
		_inject_known_dependencies(child, dependencies)


func _inject_property(branch: Node, property_name: StringName, value: Variant) -> void:
	_set_property_if_present(branch, property_name, value)
	for child: Node in branch.get_children():
		_inject_property(child, property_name, value)


func _set_property_if_present(
	target: Object,
	property_name: StringName,
	value: Variant
) -> void:
	if value == null:
		return
	for property_data: Dictionary in target.get_property_list():
		if StringName(property_data.get("name", &"")) == property_name:
			target.set(property_name, value)
			return
