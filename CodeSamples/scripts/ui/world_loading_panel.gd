extends Control
## Startup-only presentation. Progress is supplied by the generation flow;
## animation never advances the reported completion ratio or the world RNG.


@onready var _panel: PanelContainer = %LoadingCard
@onready var _companion_box: Control = %CompanionBox
@onready var _companion: AnimatedSprite2D = %Companion
@onready var _companion_name: Label = %CompanionName
@onready var _fallback: Label = %CompanionFallback
@onready var _status: Label = %LoadingStatus
@onready var _progress: ProgressBar = %LoadingProgress
@onready var _percentage: Label = %LoadingPercentage
@onready var _busy_sweep: ColorRect = %BusySweep

var _active: bool = false
var _actual_ratio: float = 0.0
var _indeterminate: bool = true
var _dex_number: int = 0
var _sweep_elapsed: float = 0.0
var _frame_size: Vector2 = Vector2.ONE
var _frame_pivot: Vector2 = Vector2.ZERO
var _cosmetic_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cosmetic_rng.randomize()
	resized.connect(_layout_content)
	_companion_box.resized.connect(_layout_companion)
	reset_loading()
	_layout_content()


func begin_loading(label: String = "正在生成大陆……", dex_number: int = 0) -> void:
	# Repeated phase/retry notifications keep the same companion and clock.
	if not _active:
		_active = true
		_actual_ratio = 0.0
		_sweep_elapsed = 0.0
		_dex_number = dex_number if FeraVisualRegistry.is_valid_dex_number(dex_number) else _cosmetic_rng.randi_range(FeraVisualRegistry.MIN_DEX_NUMBER, FeraVisualRegistry.MAX_DEX_NUMBER)
		_configure_companion()
	visible = true
	set_process(true)
	set_progress(_actual_ratio, label, true)


func set_progress(actual_ratio: float, label: String, indeterminate: bool = false) -> void:
	if not _active:
		begin_loading(label)
	_actual_ratio = clampf(actual_ratio, 0.0, 1.0) if is_finite(actual_ratio) else 0.0
	_indeterminate = indeterminate
	_status.text = label
	_progress.value = _actual_ratio
	_percentage.text = "" if _indeterminate else "%d%%" % int(floor(_actual_ratio * 100.0))
	_busy_sweep.visible = _indeterminate


func finish_loading() -> void:
	if _active:
		set_progress(1.0, "世界已准备就绪", false)
	# The flow may enter immediately; no minimum display time or outro delay.


func reset_loading() -> void:
	_active = false
	_actual_ratio = 0.0
	_indeterminate = true
	_dex_number = 0
	_sweep_elapsed = 0.0
	visible = false
	set_process(false)
	if is_instance_valid(_companion):
		_release_companion()
	if is_instance_valid(_progress):
		_progress.value = 0.0
		_percentage.text = ""
		_busy_sweep.visible = false


func get_loading_state() -> Dictionary:
	return {
		"active": _active,
		"ratio": _actual_ratio,
		"indeterminate": _indeterminate,
		"label": _status.text if is_instance_valid(_status) else "",
		"dex_number": _dex_number,
		"frame": _companion.frame if is_instance_valid(_companion) else 0,
		"has_animation": is_instance_valid(_companion) and _companion.sprite_frames != null,
		"sweep_elapsed": _sweep_elapsed,
	}


func _process(delta: float) -> void:
	if not _active or not _indeterminate:
		return
	_sweep_elapsed += maxf(delta, 0.0)
	var sweep_width: float = minf(96.0, _progress.size.x * 0.24)
	_busy_sweep.size = Vector2(sweep_width, _progress.size.y)
	_busy_sweep.position = Vector2(fposmod(_sweep_elapsed * 140.0, _progress.size.x + sweep_width) - sweep_width, 0.0)


func _configure_companion() -> void:
	_release_companion()
	# Registry loads one species (not all 60), sharing its bounded resource
	# cache with the existing world. Do not clear other animators' cache here.
	var frames: SpriteFrames = FeraVisualRegistry.get_idle_frames(_dex_number)
	_companion_name.text = _find_species_name(_dex_number)
	if frames == null or not frames.has_animation(&"front") or frames.get_frame_count(&"front") <= 0:
		_fallback.visible = true
		return
	var texture: Texture2D = frames.get_frame_texture(&"front", 0)
	if texture == null:
		_fallback.visible = true
		return
	_frame_size = Vector2(frames.get_meta("front_size", texture.get_size()))
	_frame_pivot = Vector2(frames.get_meta("front_pivot", _frame_size * 0.5))
	_companion.sprite_frames = frames
	_companion.centered = false
	_companion.offset = -_frame_pivot
	_companion.visible = true
	_fallback.visible = false
	_layout_companion()
	_companion.play(&"front")


func _release_companion() -> void:
	_companion.stop()
	_companion.sprite_frames = null
	_companion.visible = false
	# Only this panel's strong reference is released. Live world animations
	# and the Registry's bounded LRU remain untouched.


func _find_species_name(dex_number: int) -> String:
	# Read the existing lightweight naming truth; do not instantiate the
	# ecology catalog (which would also build drop/item resource profiles).
	var records: Variant = JSON.parse_string(FileAccess.get_file_as_string(WildEcologyCatalog.SPECIES_PATH))
	if records is Array:
		for record: Variant in records:
			if record is Dictionary and int(record.get("dex_number", 0)) == dex_number:
				return String(record.get("display_name", "菲菈"))
	return "菲菈 %03d" % dex_number


func _layout_content() -> void:
	if not is_instance_valid(_panel):
		return
	_panel.custom_minimum_size.x = clampf(size.x - 48.0, 250.0, 640.0)
	_companion_box.custom_minimum_size.y = clampf(size.y * 0.28, 96.0, 230.0)
	_layout_companion()


func _layout_companion() -> void:
	if not is_instance_valid(_companion) or _companion.sprite_frames == null:
		return
	# Use one fixed full-canvas size and pivot for the complete loop. Never
	# inspect alpha bounds per frame, which would introduce breathing jitter.
	var available: Vector2 = (_companion_box.size - Vector2(32.0, 16.0)).max(Vector2.ONE)
	var ratio: float = minf(available.x / maxf(_frame_size.x, 1.0), available.y / maxf(_frame_size.y, 1.0))
	_companion.scale = Vector2.ONE * ratio
	_companion.position = (_companion_box.size - _frame_size * ratio) * 0.5 + _frame_pivot * ratio


func _exit_tree() -> void:
	if is_instance_valid(_companion):
		_release_companion()
