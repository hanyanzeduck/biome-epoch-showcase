class_name FeraIdleAnimator
extends Sprite2D
## Runtime-only presentation. Shared SpriteFrames are immutable; never save
## playback time/facing in CreatureData or CreatureInstanceData.

var idle_frames: SpriteFrames = null
var current_view: StringName = &"front"
var current_frame: int = 0
var facing_logic: Vector2 = Vector2.DOWN
var _elapsed: float = 0.0
var _visual_height: float = 128.0
var _view_scales: Dictionary = {}
var _creature: CharacterBody2D = null
var _bridge: WorldVisualBridge = null
var _previous_position: Vector2 = Vector2.ZERO
var _has_previous_position: bool = false


func configure_idle(data: CreatureData) -> bool:
	set_process(false)
	_view_scales.clear()
	if data == null:
		idle_frames = null
		remove_meta(&"fera_idle_pivot")
		return false
	idle_frames = FeraVisualRegistry.get_idle_frames(data.dex_number)
	remove_meta(&"fera_idle_pivot")
	if idle_frames == null or not idle_frames.has_animation(&"front"):
		return false
	_visual_height = FeraVisualRegistry.get_world_visual_height(data)
	for view: StringName in [&"front", &"right", &"back"]:
		var content_height := float(idle_frames.get_meta(String(view) + "_content_height", 1.0))
		_view_scales[view] = FeraVisualRegistry.get_world_sprite_scale(data, view, content_height)
	_elapsed = 0.0
	current_frame = 0
	current_view = &"front"
	facing_logic = Vector2.DOWN
	_has_previous_position = false
	_creature = get_parent().get_parent() as CharacterBody2D if get_parent() != null else null
	set_meta(&"fera_idle_pivot", true)
	centered = false
	offset = Vector2.ZERO
	region_enabled = false
	hframes = 1
	vframes = 1
	frame = 0
	flip_h = false
	flip_v = false
	# Atlas frames have 4px padding. Linear sampling avoids deep mip levels
	# bleeding neighbouring cells into these small screen-space billboards.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	visible = true
	_apply_frame()
	set_process(true)
	return true


func _process(delta: float) -> void:
	if idle_frames == null:
		return
	if is_instance_valid(_creature):
		if _creature is Creature and (_creature as Creature).is_dead:
			return
		var direction := _creature.velocity
		var actual_position := _creature.global_position
		if direction.length_squared() < 1.0 and _has_previous_position and delta > 0.0:
			var displacement := actual_position - _previous_position
			# Replicated clients may receive positions without a local velocity.
			# Ignore teleports; motion is only observed, never written back.
			if displacement.length_squared() < 16384.0:
				direction = displacement / delta
		_previous_position = actual_position
		_has_previous_position = true
		if direction.length_squared() >= 1.0:
			facing_logic = direction.normalized()
	var camera_right := Vector2.RIGHT
	var camera_forward := Vector2.UP
	if not is_instance_valid(_bridge) and is_inside_tree():
		_bridge = get_tree().get_first_node_in_group(WorldVisualBridge.BRIDGE_GROUP) as WorldVisualBridge
	if is_instance_valid(_bridge):
		camera_right = _bridge.get_camera_logic_right()
		camera_forward = _bridge.get_camera_logic_forward()
	set_screen_facing(Vector2(facing_logic.dot(camera_right), -facing_logic.dot(camera_forward)))
	advance_idle(delta)


func set_screen_facing(direction: Vector2) -> void:
	if idle_frames == null or direction.is_zero_approx():
		return
	var next_view: StringName = &"front"
	var next_flip := false
	if absf(direction.x) > absf(direction.y):
		next_view = &"right"
		next_flip = direction.x < 0.0
	elif direction.y < 0.0:
		next_view = &"back"
	if not idle_frames.has_animation(next_view):
		return
	if next_view != current_view or next_flip != flip_h:
		current_view = next_view
		flip_h = next_flip
		_apply_frame()


func advance_idle(delta: float) -> void:
	if idle_frames == null:
		return
	var count := idle_frames.get_frame_count(current_view)
	var fps := idle_frames.get_animation_speed(current_view)
	if count <= 0 or fps <= 0.0:
		return
	_elapsed = fposmod(_elapsed + maxf(delta, 0.0), float(count) / fps)
	var next_frame := mini(int(floor(_elapsed * fps + 0.000001)), count - 1)
	if next_frame != current_frame:
		current_frame = next_frame
		_apply_frame()


func _apply_frame() -> void:
	texture = idle_frames.get_frame_texture(current_view, current_frame)
	if texture == null:
		return
	var view_prefix := String(current_view)
	var pivot: Vector2 = idle_frames.get_meta(view_prefix + "_pivot", Vector2(texture.get_width() * 0.5, texture.get_height()))
	var content_height: float = float(idle_frames.get_meta(view_prefix + "_content_height", texture.get_height()))
	var ratio: float = float(_view_scales.get(current_view, _visual_height / maxf(content_height, 1.0)))
	scale = Vector2.ONE * ratio
	if flip_h:
		pivot.x = float(texture.get_width()) - pivot.x
	position = -pivot * ratio
