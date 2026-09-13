class_name WorldVisualBridge
extends Node


const BRIDGE_GROUP: StringName = &"world_visual_bridge"
const GROUND_RAY_EPSILON: float = 0.000001
const DEBUG_MARKER_VISUAL_HEIGHT: float = 24.0
const DEBUG_LOGIC_POINTS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(256.0, 0.0),
	Vector2(0.0, 256.0),
	Vector2(256.0, 256.0),
]
const DEBUG_MARKER_COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.15),
	Color(0.2, 1.0, 0.25),
	Color(0.2, 0.45, 1.0),
	Color(1.0, 0.85, 0.15),
]


@export_group("Bridge References")
@export var camera_3d: Camera3D = null
@export var debug_ground_3d: MeshInstance3D = null
@export var debug_marker_root: Node3D = null
@export_group("Logic Ground")
@export var logic_ground_visual_height: float = 0.0
@export_group("Debug Markers")
@export_range(4.0, 64.0, 1.0)
var debug_marker_radius: float = 18.0


func _enter_tree() -> void:
	add_to_group(BRIDGE_GROUP)


func _ready() -> void:
	_build_debug_markers()
	var debug_settings: Node = _get_debug_settings()
	if (
		debug_settings != null
		and debug_settings.has_signal("show_visual_bridge_debug_changed")
		and not debug_settings.show_visual_bridge_debug_changed.is_connected(
			_on_show_visual_bridge_debug_changed
		)
	):
		debug_settings.show_visual_bridge_debug_changed.connect(
			_on_show_visual_bridge_debug_changed
		)
	_apply_debug_visibility(
		debug_settings != null
		and bool(debug_settings.get("show_visual_bridge_debug"))
	)


func logic_to_visual(
	logic_pos: Vector2,
	visual_height: float = 0.0
) -> Vector3:
	return Vector3(logic_pos.x, visual_height, logic_pos.y)


func visual_to_logic(visual_pos: Vector3) -> Vector2:
	return Vector2(visual_pos.x, visual_pos.z)


func logic_direction_to_visual(logic_direction: Vector2) -> Vector3:
	return Vector3(logic_direction.x, 0.0, logic_direction.y)


func visual_direction_to_logic(visual_direction: Vector3) -> Vector2:
	return Vector2(visual_direction.x, visual_direction.z)


func screen_to_logic_ground(screen_pos: Vector2) -> Variant:
	if camera_3d == null or not camera_3d.is_inside_tree():
		return null
	var ray_origin: Vector3 = camera_3d.project_ray_origin(screen_pos)
	var ray_direction: Vector3 = camera_3d.project_ray_normal(screen_pos)
	if absf(ray_direction.y) <= GROUND_RAY_EPSILON:
		return null
	var ray_distance: float = (
		logic_ground_visual_height - ray_origin.y
	) / ray_direction.y
	if ray_distance < 0.0:
		return null
	var ground_hit: Vector3 = ray_origin + ray_direction * ray_distance
	return visual_to_logic(ground_hit)


func logic_to_screen(
	logic_pos: Vector2,
	visual_height: float = 0.0
) -> Vector2:
	if camera_3d == null or not camera_3d.is_inside_tree():
		return Vector2(INF, INF)
	return camera_3d.unproject_position(
		logic_to_visual(logic_pos, visual_height)
	)


func get_visual_camera() -> Camera3D:
	return camera_3d


func is_3d_projection_active() -> bool:
	return (
		camera_3d != null
		and camera_3d.is_inside_tree()
		and camera_3d.current
		and camera_3d.get_viewport().get_camera_3d() == camera_3d
	)


func get_camera_logic_right() -> Vector2:
	if camera_3d == null or not camera_3d.is_inside_tree():
		return Vector2.RIGHT
	var camera_right: Vector3 = camera_3d.global_transform.basis.x
	var logic_right: Vector2 = visual_direction_to_logic(camera_right)
	if logic_right.length_squared() <= GROUND_RAY_EPSILON:
		return Vector2.RIGHT
	return logic_right.normalized()


func get_camera_logic_forward() -> Vector2:
	if camera_3d == null or not camera_3d.is_inside_tree():
		return Vector2.UP
	var camera_forward: Vector3 = -camera_3d.global_transform.basis.z
	var logic_forward: Vector2 = visual_direction_to_logic(camera_forward)
	if logic_forward.length_squared() <= GROUND_RAY_EPSILON:
		return Vector2.UP
	return logic_forward.normalized()


func screen_input_to_logic_direction(screen_input: Vector2) -> Vector2:
	if screen_input.is_zero_approx():
		return Vector2.ZERO
	var logic_direction: Vector2 = (
		get_camera_logic_right() * screen_input.x
		+ get_camera_logic_forward() * -screen_input.y
	)
	return logic_direction.limit_length(1.0)


func is_logic_position_visible(
	logic_pos: Vector2,
	visual_height: float = 0.0,
	viewport_margin: float = 0.0
) -> bool:
	if camera_3d == null or not camera_3d.is_inside_tree():
		return false
	var visual_position: Vector3 = logic_to_visual(logic_pos, visual_height)
	if camera_3d.is_position_behind(visual_position):
		return false
	var screen_position: Vector2 = camera_3d.unproject_position(visual_position)
	var viewport_rect: Rect2 = Rect2(
		Vector2.ZERO,
		camera_3d.get_viewport().get_visible_rect().size
	).grow(viewport_margin)
	return viewport_rect.has_point(screen_position)


func _build_debug_markers() -> void:
	if debug_marker_root == null or debug_marker_root.get_child_count() > 0:
		return
	for marker_index: int in range(DEBUG_LOGIC_POINTS.size()):
		var marker: MeshInstance3D = MeshInstance3D.new()
		marker.name = "LogicPoint_%d" % marker_index
		marker.position = logic_to_visual(
			DEBUG_LOGIC_POINTS[marker_index],
			DEBUG_MARKER_VISUAL_HEIGHT
		)
		marker.set_meta("logic_position", DEBUG_LOGIC_POINTS[marker_index])
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = debug_marker_radius
		sphere.height = debug_marker_radius * 2.0
		marker.mesh = sphere

		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = DEBUG_MARKER_COLORS[marker_index]
		marker.material_override = material
		debug_marker_root.add_child(marker)


func _apply_debug_visibility(enabled: bool) -> void:
	if debug_ground_3d != null:
		debug_ground_3d.visible = enabled
	if debug_marker_root == null:
		return
	for child: Node in debug_marker_root.get_children():
		var visual_instance: VisualInstance3D = child as VisualInstance3D
		if visual_instance != null:
			visual_instance.visible = enabled


func _on_show_visual_bridge_debug_changed(enabled: bool) -> void:
	_apply_debug_visibility(enabled)


func _get_debug_settings() -> Node:
	return get_node_or_null("/root/DebugSettings")
