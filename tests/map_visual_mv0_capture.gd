extends SceneTree

const CountryLabelLayerScript = preload("res://scripts/ui/country_label_layer.gd")

const VIEW_DEFINITIONS := [
	{
		"name": "current_world_political_1920x1080.png",
		"size": Vector2i(1920, 1080),
		"mode": 0,
		"mode_name": "political",
		"focus_tag": "",
		"fallback": Vector3.ZERO,
		"focus_fallback": true,
		"height": 13.0,
	},
	{
		"name": "current_france_low_countries_political_1920x1080.png",
		"size": Vector2i(1920, 1080),
		"mode": 0,
		"mode_name": "political",
		"focus_tag": "FRA",
		"fallback": Vector3(0.3, 0.0, -5.3),
		"height": 1.4,
	},
	{
		"name": "current_france_low_countries_terrain_1920x1080.png",
		"size": Vector2i(1920, 1080),
		"mode": 1,
		"mode_name": "terrain",
		"focus_tag": "FRA",
		"fallback": Vector3(0.3, 0.0, -5.3),
		"height": 1.4,
	},
	{
		"name": "current_france_low_countries_ids_1920x1080.png",
		"size": Vector2i(1920, 1080),
		"mode": 2,
		"mode_name": "province_ids",
		"focus_tag": "FRA",
		"fallback": Vector3(0.3, 0.0, -5.3),
		"height": 1.4,
	},
	{
		"name": "current_italy_alps_political_1152x648.png",
		"size": Vector2i(1152, 648),
		"mode": 0,
		"mode_name": "political",
		"focus_tag": "NAP",
		"fallback": Vector3(2.0, 0.0, -4.8),
		"height": 1.0,
	},
	{
		"name": "current_scandinavia_baltic_terrain_1152x648.png",
		"size": Vector2i(1152, 648),
		"mode": 1,
		"mode_name": "terrain",
		"focus_tag": "SWE",
		"fallback": Vector3(2.7, 0.0, -7.0),
		"height": 1.2,
	},
	{
		"name": "current_sahara_nile_terrain_1700x960.png",
		"size": Vector2i(1700, 960),
		"mode": 1,
		"mode_name": "terrain",
		"focus_tag": "MAM",
		"fallback": Vector3(4.7, 0.0, -2.7),
		"height": 1.7,
	},
	{
		"name": "current_maritime_southeast_asia_political_1152x648.png",
		"size": Vector2i(1152, 648),
		"mode": 0,
		"mode_name": "political",
		"focus_tag": "MAJ",
		"fallback": Vector3(17.0, 0.0, 0.5),
		"height": 1.1,
	},
	{
		"name": "current_andes_terrain_1152x648.png",
		"size": Vector2i(1152, 648),
		"mode": 1,
		"mode_name": "terrain",
		"focus_tag": "INC",
		"fallback": Vector3(-11.3, 0.0, 1.7),
		"height": 1.3,
	},
	{
		"name": "current_north_america_political_1152x648.png",
		"size": Vector2i(1152, 648),
		"mode": 0,
		"mode_name": "political",
		"focus_tag": "CAD",
		"fallback": Vector3(-15.0, 0.0, -3.8),
		"height": 1.6,
	},
]

const HUD_NODE_NAMES := [
	"MapHUD",
	"SimulationHUD",
	"EconomyHUD",
	"WarHUD",
	"AIDebugHUD",
	"CharacterHUD",
	"CountryDepthHUD",
]

var _output_directory := ""
var _scene: Node
var _labels: CountryLabelLayer
var _camera_controller: StrategyCameraController
var _map_hud: MapHUD


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("MV-0 map visual capture failed: %s" % message)
	quit(1)


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			_output_directory = argument.trim_prefix("--output-dir=")
	if _output_directory.is_empty():
		_fail("pass --output-dir=<absolute directory>")
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(_output_directory)
	if directory_error != OK:
		_fail("could not create output directory: %s" % error_string(directory_error))
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
	_camera_controller = _scene.get_node("CameraController") as StrategyCameraController
	_map_hud = _scene.get_node("MapHUD") as MapHUD
	if _labels == null or _camera_controller == null or _map_hud == null:
		_fail("required map, label, camera, and HUD nodes must exist")
		return
	_hide_hud()
	if not await _wait_for_labels(360):
		_fail("initial country label layouts did not finish")
		return

	var report := {
		"schema_version": 1,
		"purpose": "MV-0 current-state map visual capture baseline",
		"captured_utc": Time.get_datetime_string_from_system(true, true),
		"engine": Engine.get_version_info(),
		"platform": {
			"os": OS.get_name(),
			"distribution": OS.get_distribution_name(),
			"version": OS.get_version(),
			"processor": OS.get_processor_name(),
			"logical_processors": OS.get_processor_count(),
			"video_adapter": RenderingServer.get_video_adapter_name(),
			"video_vendor": RenderingServer.get_video_adapter_vendor(),
			"video_api": RenderingServer.get_video_adapter_api_version(),
		},
		"views": [],
		"camera_motion_profile": {},
		"label_metrics": _labels.debug_metrics(),
	}

	for view in VIEW_DEFINITIONS:
		var capture_result := await _capture_view(view)
		if capture_result.is_empty():
			return
		report["views"].append(capture_result)

	report["camera_motion_profile"] = await _profile_camera_motion()
	var report_path := _output_directory.path_join("mv0_capture_manifest.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_fail("could not write %s" % report_path)
		return
	report_file.store_string(JSON.stringify(report, "\t", false) + "\n")
	report_file.close()
	print("MV-0 map visual captures completed. output=%s" % _output_directory)
	quit(0)


func _hide_hud() -> void:
	for node_name in HUD_NODE_NAMES:
		var control := _scene.get_node_or_null(node_name) as Control
		if control != null:
			control.visible = false


func _wait_for_labels(frame_limit: int) -> bool:
	var waited := 0
	while _labels.debug_pending_count() > 0 and waited < frame_limit:
		await process_frame
		waited += 1
	return _labels.debug_pending_count() == 0


func _focus_view(view: Dictionary) -> void:
	_camera_controller.reset_camera()
	await process_frame
	var target_height := float(view["height"])
	if target_height > 0.0:
		_camera_controller.global_position.y += target_height - _camera_controller.camera.global_position.y
	var focus_tag := String(view["focus_tag"])
	if not focus_tag.is_empty():
		var position: Vector3 = view["fallback"]
		var layout := _labels.debug_layout(focus_tag)
		if not layout.is_empty():
			position = layout["position"]
		_camera_controller.focus_world_position(position)
	elif bool(view.get("focus_fallback", false)):
		_camera_controller.focus_world_position(view["fallback"])


func _capture_view(view: Dictionary) -> Dictionary:
	root.size = view["size"]
	Input.warp_mouse(Vector2(4.0, 4.0))
	_map_hud.set_map_mode(int(view["mode"]))
	_hide_hud()
	await _focus_view(view)
	for _settle_frame in 10:
		await process_frame
	if not await _wait_for_labels(120):
		_fail("label allocation did not settle for %s" % view["name"])
		return {}
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("rendered viewport image is empty for %s" % view["name"])
		return {}
	var path := _output_directory.path_join(String(view["name"]))
	var error := image.save_png(path)
	if error != OK:
		_fail("could not save %s: %s" % [path, error_string(error)])
		return {}
	return {
		"file": view["name"],
		"width": image.get_width(),
		"height": image.get_height(),
		"map_mode": view["mode_name"],
		"focus_tag": view["focus_tag"],
		"target_camera_height": view["height"],
		"render_objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"render_primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"video_memory_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"texture_memory_bytes": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"buffer_memory_bytes": int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
	}


func _profile_camera_motion() -> Dictionary:
	root.size = Vector2i(1920, 1080)
	_map_hud.set_map_mode(0)
	_hide_hud()
	await _focus_view({"height": 1.4, "focus_tag": "FRA", "fallback": Vector3(0.3, 0.0, -5.3)})
	# The last capture changes resolution and map mode. Give resource allocation,
	# label visibility, and shader work a separate warm-up window so the profile
	# records steady camera motion rather than the benchmark transition itself.
	for _settle_frame in 60:
		await process_frame
	if not await _wait_for_labels(120):
		_fail("label allocation did not settle for camera-motion profile")
		return {}
	var frame_interval_ms: Array[float] = []
	var fps_samples: Array[float] = []
	var draw_calls: Array[float] = []
	for frame_index in 180:
		var direction := 1.0 if frame_index < 90 else -1.0
		_camera_controller.global_position.x += 0.012 * direction
		var frame_started := Time.get_ticks_usec()
		await process_frame
		frame_interval_ms.append(float(Time.get_ticks_usec() - frame_started) / 1000.0)
		fps_samples.append(float(Performance.get_monitor(Performance.TIME_FPS)))
		draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var slow_frames: Array[Dictionary] = []
	for frame_index in frame_interval_ms.size():
		if frame_interval_ms[frame_index] > 50.0:
			slow_frames.append({"frame": frame_index, "interval_ms": frame_interval_ms[frame_index]})
	return {
		"frames": frame_interval_ms.size(),
		"frame_interval_ms_p50": _percentile(frame_interval_ms, 0.50),
		"frame_interval_ms_p95": _percentile(frame_interval_ms, 0.95),
		"frame_interval_ms_p99": _percentile(frame_interval_ms, 0.99),
		"frame_interval_ms_max": _maximum(frame_interval_ms),
		"fps_p05": _percentile(fps_samples, 0.05),
		"fps_p50": _percentile(fps_samples, 0.50),
		"draw_calls_p95": _percentile(draw_calls, 0.95),
		"frames_over_33_3_ms": _count_over(frame_interval_ms, 33.3),
		"frames_over_50_ms": _count_over(frame_interval_ms, 50.0),
		"frames_over_100_ms": _count_over(frame_interval_ms, 100.0),
		"slow_frames": slow_frames,
		"note": "Wall-clock rendered-frame intervals during scripted camera motion; obtain an external GPU pass breakdown separately.",
	}


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	var index := clampi(int(ceil((ordered.size() - 1) * fraction)), 0, ordered.size() - 1)
	return ordered[index]


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
