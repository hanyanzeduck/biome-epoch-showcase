class_name SaveGameServiceClass
extends Node


signal save_started(slot_id: StringName)
signal save_completed(slot_id: StringName, save_path: String)
signal save_failed(slot_id: StringName, error_code: int, message: String)
signal load_completed(slot_id: StringName)
signal load_failed(slot_id: StringName, error_code: int, message: String)


const SAVE_SCHEMA_VERSION: int = 2
const WORLD_GEN_VERSION: int = 1
const SAVE_ROOT: String = "user://saves"
const WORLD_FILE_NAME: String = "world.json"
const MANIFEST_FILE_NAME: String = "manifest.json"
const BACKUP_SUFFIX: String = ".bak"
const TEMP_SUFFIX: String = ".tmp"
const DEFAULT_SLOT_ID: StringName = &"autosave"
const AUTOSAVE_INTERVAL_SECONDS: float = 180.0
# Legacy brand compatibility: before the rename, Godot stored user:// under this sibling folder.
const LEGACY_PROJECT_USER_DIR_NAME: String = "ProjectFrontier"


var _gameplay_active: bool = false
var _autosave_elapsed: float = 0.0
var _save_in_progress: bool = false


func _ready() -> void:
	_migrate_legacy_project_saves_if_needed()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_unhandled_key_input(true)
	# Window-close must pass through the synchronous save hook first.
	get_tree().auto_accept_quit = false


func _process(delta: float) -> void:
	if not _gameplay_active or _save_in_progress or not can_local_save_current_game() or delta <= 0.0:
		return
	_autosave_elapsed += delta
	if _autosave_elapsed >= AUTOSAVE_INTERVAL_SECONDS:
		_autosave_elapsed = 0.0
		save_current_game(DEFAULT_SLOT_ID)


func _unhandled_key_input(event: InputEvent) -> void:
	if not _gameplay_active or _save_in_progress or not can_local_save_current_game():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F5 or key.physical_keycode == KEY_F5:
		if save_current_game(DEFAULT_SLOT_ID) == OK:
			print("Quick save completed.")
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if _gameplay_active and not _save_in_progress and can_local_save_current_game():
		save_current_game(DEFAULT_SLOT_ID)
	var lan_service := get_node_or_null("/root/LanMultiplayerService")
	if lan_service != null and lan_service.has_method(&"shutdown_network"):
		lan_service.call(&"shutdown_network")
	get_tree().quit()


func set_gameplay_active(active: bool) -> void:
	_gameplay_active = active
	_autosave_elapsed = 0.0


func is_gameplay_active() -> bool:
	return _gameplay_active


func can_local_save_current_game() -> bool:
	var lan_service := get_node_or_null("/root/LanMultiplayerService")
	if lan_service == null or not lan_service.has_method(&"is_client"):
		return true
	return not bool(lan_service.call(&"is_client"))


func has_slot(slot_id: StringName = DEFAULT_SLOT_ID) -> bool:
	return not load_manifest(slot_id).is_empty()


func save_current_game(slot_id: StringName = DEFAULT_SLOT_ID) -> int:
	if not can_local_save_current_game():
		return ERR_UNAVAILABLE
	if _save_in_progress:
		return ERR_BUSY
	var main_root := get_tree().current_scene
	if main_root == null:
		return ERR_UNCONFIGURED
	var payload := GameplaySaveAdapter.capture_current_game(main_root)
	if payload.is_empty() or not WorldSeedGenerator.is_valid_world_seed(int(payload.get("world_seed", 0))):
		return _fail_save(slot_id, ERR_INVALID_DATA, "当前游戏没有可保存的有效世界。")
	_save_in_progress = true
	var manifest := GameplaySaveAdapter.get_manifest_summary(main_root, payload)
	var result := save_slot(slot_id, payload, manifest)
	_save_in_progress = false
	if result == OK:
		_autosave_elapsed = 0.0
	return result


func load_current_game_payload(slot_id: StringName = DEFAULT_SLOT_ID) -> Dictionary:
	return load_slot(slot_id)


func save_slot(
	slot_id: StringName,
	payload: Dictionary,
	manifest_overrides: Dictionary = {}
) -> int:
	if not _is_valid_slot_id(slot_id):
		return _fail_save(slot_id, ERR_INVALID_PARAMETER, "无效存档槽 ID。")

	var slot_path := _get_slot_path(slot_id)
	var directory_error := _ensure_directory(slot_path)
	if directory_error != OK:
		return _fail_save(slot_id, directory_error, "无法创建存档目录。")

	save_started.emit(slot_id)
	var timestamp := int(Time.get_unix_time_from_system())
	var envelope := {
		"save_schema_version": SAVE_SCHEMA_VERSION,
		"world_gen_version": WORLD_GEN_VERSION,
		"game_version": String(ProjectSettings.get_setting("application/config/version", "dev")),
		"saved_at_unix": timestamp,
		"world_seed": _get_active_world_seed(),
		"payload": SaveValueCodec.encode(payload),
	}
	var world_path := "%s/%s" % [slot_path, WORLD_FILE_NAME]
	var world_error := _atomic_write_json(world_path, envelope)
	if world_error != OK:
		return _fail_save(slot_id, world_error, "写入世界存档失败。")

	var manifest := {
		"slot_id": String(slot_id),
		"save_schema_version": SAVE_SCHEMA_VERSION,
		"world_gen_version": WORLD_GEN_VERSION,
		"game_version": envelope["game_version"],
		"saved_at_unix": timestamp,
		"world_seed": envelope["world_seed"],
	}
	for key: Variant in manifest_overrides.keys():
		manifest[key] = manifest_overrides[key]

	var manifest_path := "%s/%s" % [slot_path, MANIFEST_FILE_NAME]
	var manifest_error := _atomic_write_json(
		manifest_path,
		SaveValueCodec.encode(manifest)
	)
	if manifest_error != OK:
		return _fail_save(slot_id, manifest_error, "写入存档 Manifest 失败。")

	save_completed.emit(slot_id, world_path)
	return OK


func load_slot(slot_id: StringName) -> Dictionary:
	if not _is_valid_slot_id(slot_id):
		_fail_load(slot_id, ERR_INVALID_PARAMETER, "无效存档槽 ID。")
		return {}

	var world_path := "%s/%s" % [_get_slot_path(slot_id), WORLD_FILE_NAME]
	var loaded := _read_json_with_backup(world_path)
	if loaded.is_empty():
		_fail_load(slot_id, ERR_FILE_CANT_READ, "无法读取世界存档或备份。")
		return {}

	var schema_version := int(loaded.get("save_schema_version", 0))
	if schema_version <= 0 or schema_version > SAVE_SCHEMA_VERSION:
		_fail_load(
			slot_id,
			ERR_INVALID_DATA,
			"不支持的存档版本：%d" % schema_version
		)
		return {}

	var saved_world_gen_version := int(loaded.get("world_gen_version", 0))
	# The project does not yet ship historical WorldGen implementations. Loading
	# an older seed with the newest generator could place saved bases into a
	# completely different terrain layout, so fail closed until an explicit
	# WorldGen migration/replay path exists.
	if saved_world_gen_version != WORLD_GEN_VERSION:
		_fail_load(
			slot_id,
			ERR_INVALID_DATA,
			"不支持的世界生成版本：%d（当前：%d）"
			% [saved_world_gen_version, WORLD_GEN_VERSION]
		)
		return {}

	var payload_encoded: Variant = loaded.get("payload", {})
	var decoded: Variant = SaveValueCodec.decode(payload_encoded)
	if decoded is not Dictionary:
		_fail_load(slot_id, ERR_INVALID_DATA, "存档 Payload 不是 Dictionary。")
		return {}

	load_completed.emit(slot_id)
	return decoded as Dictionary


func load_manifest(slot_id: StringName) -> Dictionary:
	if not _is_valid_slot_id(slot_id):
		return {}
	var path := "%s/%s" % [_get_slot_path(slot_id), MANIFEST_FILE_NAME]
	var encoded := _read_json_with_backup(path)
	if encoded.is_empty():
		return {}
	var decoded: Variant = SaveValueCodec.decode(encoded)
	return decoded as Dictionary if decoded is Dictionary else {}


func list_slots() -> Array[StringName]:
	var result: Array[StringName] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SAVE_ROOT)):
		return result
	var directory := DirAccess.open(SAVE_ROOT)
	if directory == null:
		return result
	for entry: String in directory.get_directories():
		var slot_id := StringName(entry)
		if _is_valid_slot_id(slot_id) and not load_manifest(slot_id).is_empty():
			result.append(slot_id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result


func delete_slot(slot_id: StringName) -> int:
	if not _is_valid_slot_id(slot_id):
		return ERR_INVALID_PARAMETER
	var slot_path := _get_slot_path(slot_id)
	var absolute := ProjectSettings.globalize_path(slot_path)
	if not DirAccess.dir_exists_absolute(absolute):
		return OK
	return _remove_directory_recursive(slot_path)


func get_save_schema_version() -> int:
	return SAVE_SCHEMA_VERSION


func get_world_gen_version() -> int:
	return WORLD_GEN_VERSION


func _get_active_world_seed() -> int:
	var game_session := get_node_or_null("/root/GameSession")
	if game_session == null:
		return 0
	return int(game_session.get("world_seed"))


func _get_slot_path(slot_id: StringName) -> String:
	return "%s/%s" % [SAVE_ROOT, String(slot_id)]


func _is_valid_slot_id(slot_id: StringName) -> bool:
	var text := String(slot_id)
	if text.is_empty() or text.length() > 64:
		return false
	var expression := RegEx.new()
	if expression.compile("^[A-Za-z0-9_-]+$") != OK:
		return false
	return expression.search(text) != null


func _ensure_directory(path: String) -> int:
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		return OK
	return DirAccess.make_dir_recursive_absolute(absolute)


func _atomic_write_json(path: String, value: Variant) -> int:
	var text := JSON.stringify(value, "\t", false)
	var temp_path := path + TEMP_SUFFIX
	var backup_path := path + BACKUP_SUFFIX
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	file.close()

	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.rename_absolute(absolute_path, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temp)
			return backup_error
	var rename_error := DirAccess.rename_absolute(absolute_temp, absolute_path)
	if rename_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		return rename_error
	return OK


func _read_json_with_backup(path: String) -> Dictionary:
	var primary := _read_json(path)
	if not primary.is_empty():
		return primary
	return _read_json(path + BACKUP_SUFFIX)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _remove_directory_recursive(path: String) -> int:
	var directory := DirAccess.open(path)
	if directory == null:
		return ERR_CANT_OPEN
	for file_name: String in directory.get_files():
		var error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path("%s/%s" % [path, file_name])
		)
		if error != OK:
			return error
	for directory_name: String in directory.get_directories():
		var child_path := "%s/%s" % [path, directory_name]
		var child_error := _remove_directory_recursive(child_path)
		if child_error != OK:
			return child_error
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _migrate_legacy_project_saves_if_needed() -> void:
	# Changing application/config/name changes the default user:// folder on desktop.
	# Keep old ProjectFrontier saves available without deleting or overwriting them.
	var current_save_root := ProjectSettings.globalize_path(SAVE_ROOT)
	if _absolute_directory_has_entries(current_save_root):
		return
	var current_user_root := ProjectSettings.globalize_path("user://").trim_suffix("/")
	var legacy_user_root := current_user_root.get_base_dir().path_join(LEGACY_PROJECT_USER_DIR_NAME)
	var legacy_save_root := legacy_user_root.path_join("saves")
	if not DirAccess.dir_exists_absolute(legacy_save_root):
		return
	var make_error := DirAccess.make_dir_recursive_absolute(current_save_root)
	if make_error != OK:
		push_warning("SaveGameService: 无法创建 Biome Epoch 存档目录，跳过旧存档迁移。")
		return
	var copy_error := _copy_absolute_directory_contents(legacy_save_root, current_save_root)
	if copy_error == OK:
		print("SaveGameService: 已从旧 ProjectFrontier 用户目录复制存档到 Biome Epoch；旧存档仍保留。")
	else:
		push_warning("SaveGameService: 旧 ProjectFrontier 存档迁移失败（错误码 %d），旧文件未删除。" % copy_error)


func _absolute_directory_has_entries(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return false
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	return not directory.get_files().is_empty() or not directory.get_directories().is_empty()


func _copy_absolute_directory_contents(source_path: String, destination_path: String) -> int:
	var source := DirAccess.open(source_path)
	if source == null:
		return ERR_CANT_OPEN
	for directory_name: String in source.get_directories():
		var source_child := source_path.path_join(directory_name)
		var destination_child := destination_path.path_join(directory_name)
		var make_error := DirAccess.make_dir_recursive_absolute(destination_child)
		if make_error != OK:
			return make_error
		var child_error := _copy_absolute_directory_contents(source_child, destination_child)
		if child_error != OK:
			return child_error
	for file_name: String in source.get_files():
		var source_file_path := source_path.path_join(file_name)
		var destination_file_path := destination_path.path_join(file_name)
		var input_file := FileAccess.open(source_file_path, FileAccess.READ)
		if input_file == null:
			return FileAccess.get_open_error()
		var bytes := input_file.get_buffer(input_file.get_length())
		input_file.close()
		var output_file := FileAccess.open(destination_file_path, FileAccess.WRITE)
		if output_file == null:
			return FileAccess.get_open_error()
		output_file.store_buffer(bytes)
		output_file.flush()
		output_file.close()
	return OK


func _fail_save(slot_id: StringName, error_code: int, message: String) -> int:
	push_error("SaveGameService: %s (%d)" % [message, error_code])
	save_failed.emit(slot_id, error_code, message)
	return error_code


func _fail_load(slot_id: StringName, error_code: int, message: String) -> void:
	push_error("SaveGameService: %s (%d)" % [message, error_code])
	load_failed.emit(slot_id, error_code, message)
