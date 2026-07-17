extends Node

const EXPORT_FOLDER_NAME := "Grand World Logs"
const ENGINE_LOG_SETTING := "debug/file_logging/log_path"
const DEFAULT_ENGINE_LOG_PATH := "user://logs/grand_world.log"
const SYNC_INTERVAL_SECONDS := 0.25

var _engine_log_path := DEFAULT_ENGINE_LOG_PATH
var _export_log_path := ""
var _engine_log_offset := 0
var _sync_elapsed := 0.0
var _export_file: FileAccess
var _disabled := false


func _ready() -> void:
	_engine_log_path = String(ProjectSettings.get_setting(ENGINE_LOG_SETTING, DEFAULT_ENGINE_LOG_PATH))
	var documents_path := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if documents_path.is_empty():
		_disable_with_warning("The operating system did not provide a Documents folder.")
		return
	var export_folder := documents_path.path_join(EXPORT_FOLDER_NAME)
	var directory_error := DirAccess.make_dir_recursive_absolute(export_folder)
	if directory_error != OK:
		_disable_with_warning("Could not create debug-log folder: %s" % export_folder)
		return
	_export_log_path = export_folder.path_join(_build_session_filename())
	_export_file = FileAccess.open(_export_log_path, FileAccess.WRITE)
	if _export_file == null:
		_disable_with_warning("Could not create debug log: %s" % _export_log_path)
		return
	_export_file.store_string(_build_session_header())
	_export_file.flush()
	_sync_engine_log()
	print("Session debug log: %s" % _export_log_path)


func _process(delta: float) -> void:
	if _disabled:
		return
	_sync_elapsed += delta
	if _sync_elapsed < SYNC_INTERVAL_SECONDS:
		return
	_sync_elapsed = 0.0
	_sync_engine_log()


func _exit_tree() -> void:
	_sync_engine_log()
	if _export_file != null:
		_export_file.flush()
		_export_file = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_sync_engine_log()


func get_export_log_path() -> String:
	return _export_log_path


func _sync_engine_log() -> void:
	if _disabled or _export_file == null:
		return
	var source := FileAccess.open(_engine_log_path, FileAccess.READ)
	if source == null:
		return
	var source_length := source.get_length()
	if source_length < _engine_log_offset:
		_engine_log_offset = 0
	if source_length == _engine_log_offset:
		return
	source.seek(_engine_log_offset)
	var bytes_to_copy := source_length - _engine_log_offset
	var log_bytes := source.get_buffer(bytes_to_copy)
	if log_bytes.is_empty():
		return
	_export_file.store_buffer(log_bytes)
	_export_file.flush()
	_engine_log_offset += log_bytes.size()


func _build_session_filename() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "grand_world_%04d-%02d-%02d_%02d-%02d-%02d_%d.txt" % [
		int(now.year),
		int(now.month),
		int(now.day),
		int(now.hour),
		int(now.minute),
		int(now.second),
		OS.get_process_id(),
	]


func _build_session_header() -> String:
	var version_info := Engine.get_version_info()
	var renderer := RenderingServer.get_current_rendering_method()
	var adapter := RenderingServer.get_video_adapter_name()
	return "\n".join([
		"Grand World V2 - Session Debug Log",
		"Started: %s" % Time.get_datetime_string_from_system(false, true),
		"Game version: %s" % String(ProjectSettings.get_setting("application/config/version", "Development")),
		"Godot: %s" % String(version_info.get("string", "Unknown")),
		"Operating system: %s %s" % [OS.get_name(), OS.get_version()],
		"Renderer: %s" % (renderer if not renderer.is_empty() else "Unavailable"),
		"Graphics adapter: %s" % (adapter if not adapter.is_empty() else "Unavailable"),
		"Executable: %s" % OS.get_executable_path(),
		"Project: %s" % ProjectSettings.globalize_path("res://"),
		"Engine log source: %s" % ProjectSettings.globalize_path(_engine_log_path),
		"",
		"--- Godot output, warnings, errors, and stack traces ---",
		"",
	])


func _disable_with_warning(message: String) -> void:
	_disabled = true
	push_warning("Session log export disabled. %s Engine logging remains available at %s" % [
		message,
		ProjectSettings.globalize_path(_engine_log_path),
	])
