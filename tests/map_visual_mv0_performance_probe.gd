extends SceneTree

const CountryLabelLayerScript = preload("res://scripts/ui/country_label_layer.gd")

const OUTPUT_FILE := "mv0_performance_probe.json"
const PROFILE_FRAMES := 180
const WARMUP_FRAMES := 75

var _output_directory := ""
var _scene: Node
var _labels: CountryLabelLayer
var _army_layer: Node3D
var _camera_controller: StrategyCameraController
var _map_hud: MapHUD


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("MV-0 performance probe failed: %s" % message)
	quit(1)


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			_output_directory = argument.trim_prefix("--output-dir=")
	if _output_directory.is_empty():
		_fail("pass --output-dir=<absolute directory>")
		return
	if DirAccess.make_dir_recursive_absolute(_output_directory) != OK:
		_fail("could not create output directory")
		return

	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("main scene must load")
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	await process_frame
	_labels = _scene.get_node("CountryLabelLayer") as CountryLabelLayerScript
	_army_layer = _scene.get_node("ArmyLayer") as Node3D
	_camera_controller = _scene.get_node("CameraController") as StrategyCameraController
	_map_hud = _scene.get_node("MapHUD") as MapHUD
	if _labels == null or _army_layer == null or _camera_controller == null or _map_hud == null:
		_fail("required map presentation nodes must exist")
		return
	_hide_hud()
	if not await _wait_for_labels(480):
		_fail("initial label layouts did not finish")
		return

	var profiles: Array[Dictionary] = []
	profiles.append(await _run_profile("all_layers_motion", true, true, true, true, true))
	profiles.append(await _run_profile("no_country_labels_motion", false, true, true, true, true))
	profiles.append(await _run_profile("no_army_markers_motion", true, false, true, true, true))
	profiles.append(await _run_profile("base_map_motion", false, false, true, true, true))
	profiles.append(await _run_profile("base_map_static", false, false, false, true, true))
	profiles.append(await _run_profile("base_map_static_no_hud_processing", false, false, false, true, false))
	profiles.append(await _run_profile("base_map_static_no_simulation", false, false, false, false, true))
	profiles.append(await _run_profile("base_map_static_no_simulation_ui", false, false, false, false, false))
	for hud_name in ["MapHUD", "SimulationHUD", "EconomyHUD", "WarHUD", "AIDebugHUD", "CharacterHUD", "CountryDepthHUD"]:
		profiles.append(await _run_profile("base_map_static_%s_only" % hud_name.to_snake_case(), false, false, false, true, true, hud_name))

	var report := {
		"schema_version": 1,
		"purpose": "MV-0 layer-isolation performance probe",
		"captured_utc": Time.get_datetime_string_from_system(true, true),
		"engine": Engine.get_version_info(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"resolution": [root.size.x, root.size.y],
		"profile_frames": PROFILE_FRAMES,
		"warmup_frames": WARMUP_FRAMES,
		"profiles": profiles,
	}
	var path := _output_directory.path_join(OUTPUT_FILE)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write %s" % path)
		return
	file.store_string(JSON.stringify(report, "\t", false) + "\n")
	file.close()
	print("MV-0 layer performance probe completed. output=%s" % path)
	quit(0)


func _hide_hud() -> void:
	for node_name in ["MapHUD", "SimulationHUD", "EconomyHUD", "WarHUD", "AIDebugHUD", "CharacterHUD", "CountryDepthHUD"]:
		var control := _scene.get_node_or_null(node_name) as Control
		if control != null:
			control.visible = false


func _set_simulation_enabled(enabled: bool) -> void:
	var mode := Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	var simulation := _scene.get_node_or_null("SimulationController")
	if simulation != null:
		simulation.process_mode = mode


func _set_hud_processing_enabled(enabled: bool, only_node_name: String = "") -> void:
	for node_name in ["MapHUD", "SimulationHUD", "EconomyHUD", "WarHUD", "AIDebugHUD", "CharacterHUD", "CountryDepthHUD"]:
		var control := _scene.get_node_or_null(node_name)
		if control != null:
			var node_enabled: bool = enabled and (only_node_name.is_empty() or node_name == only_node_name)
			control.process_mode = Node.PROCESS_MODE_INHERIT if node_enabled else Node.PROCESS_MODE_DISABLED


func _wait_for_labels(frame_limit: int) -> bool:
	var waited := 0
	while _labels.debug_pending_count() > 0 and waited < frame_limit:
		await process_frame
		waited += 1
	return _labels.debug_pending_count() == 0


func _prepare_camera() -> void:
	_camera_controller.reset_camera()
	await process_frame
	_camera_controller.global_position.y += 1.4 - _camera_controller.camera.global_position.y
	var layout := _labels.debug_layout("FRA")
	var focus := Vector3(0.3, 0.0, -5.3)
	if not layout.is_empty():
		focus = layout["position"]
	_camera_controller.focus_world_position(focus)


func _run_profile(profile_name: String, labels_enabled: bool, armies_enabled: bool, camera_motion: bool, simulation_enabled: bool, hud_processing_enabled: bool, hud_only: String = "") -> Dictionary:
	_labels.visible = labels_enabled
	_labels.process_mode = Node.PROCESS_MODE_INHERIT if labels_enabled else Node.PROCESS_MODE_DISABLED
	_army_layer.visible = armies_enabled
	_army_layer.process_mode = Node.PROCESS_MODE_INHERIT if armies_enabled else Node.PROCESS_MODE_DISABLED
	_set_simulation_enabled(simulation_enabled)
	_set_hud_processing_enabled(hud_processing_enabled, hud_only)
	_map_hud.set_map_mode(0)
	_hide_hud()
	await _prepare_camera()
	for _warmup in WARMUP_FRAMES:
		await process_frame
	if labels_enabled and not await _wait_for_labels(180):
		_fail("labels did not settle for %s" % profile_name)
		return {}

	var intervals: Array[float] = []
	var fps_samples: Array[float] = []
	var draw_samples: Array[float] = []
	for frame_index in PROFILE_FRAMES:
		if camera_motion:
			var direction := 1.0 if frame_index < PROFILE_FRAMES / 2 else -1.0
			_camera_controller.global_position.x += 0.012 * direction
		var started := Time.get_ticks_usec()
		await process_frame
		intervals.append(float(Time.get_ticks_usec() - started) / 1000.0)
		fps_samples.append(float(Performance.get_monitor(Performance.TIME_FPS)))
		draw_samples.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var slow_frames: Array[Dictionary] = []
	for frame_index in intervals.size():
		if intervals[frame_index] > 50.0:
			slow_frames.append({"frame": frame_index, "interval_ms": intervals[frame_index]})
	return {
		"name": profile_name,
		"labels_enabled": labels_enabled,
		"armies_enabled": armies_enabled,
		"camera_motion": camera_motion,
		"simulation_enabled": simulation_enabled,
		"hud_processing_enabled": hud_processing_enabled,
		"hud_only": hud_only,
		"frame_interval_ms_p50": _percentile(intervals, 0.50),
		"frame_interval_ms_p95": _percentile(intervals, 0.95),
		"frame_interval_ms_p99": _percentile(intervals, 0.99),
		"frame_interval_ms_max": _maximum(intervals),
		"fps_p05": _percentile(fps_samples, 0.05),
		"fps_p50": _percentile(fps_samples, 0.50),
		"draw_calls_p50": _percentile(draw_samples, 0.50),
		"draw_calls_p95": _percentile(draw_samples, 0.95),
		"frames_over_33_3_ms": _count_over(intervals, 33.3),
		"frames_over_50_ms": _count_over(intervals, 50.0),
		"frames_over_100_ms": _count_over(intervals, 100.0),
		"slow_frames": slow_frames,
	}


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[clampi(int(ceil((ordered.size() - 1) * fraction)), 0, ordered.size() - 1)]


func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result


func _count_over(values: Array[float], threshold: float) -> int:
	var result := 0
	for value in values:
		if value > threshold:
			result += 1
	return result
