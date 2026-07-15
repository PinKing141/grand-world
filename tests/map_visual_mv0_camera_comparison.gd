extends SceneTree

const CountryLabelLayerScript = preload("res://scripts/ui/country_label_layer.gd")
const CAPTURE_SIZE := Vector2i(1920, 1080)
const MOTION_FRAMES := 120
const HUD_NODE_NAMES := ["MapHUD", "SimulationHUD", "EconomyHUD", "WarHUD", "AIDebugHUD", "CharacterHUD", "CountryDepthHUD"]

var _output_directory := ""
var _scene: Node
var _labels: CountryLabelLayer
var _controller: StrategyCameraController
var _camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("MV-0 camera comparison failed: %s" % message)
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
	root.size = CAPTURE_SIZE
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
	_controller = _scene.get_node("CameraController") as StrategyCameraController
	_camera = _controller.camera
	if _labels == null or _controller == null or _camera == null:
		_fail("camera and labels must exist")
		return
	_hide_hud()
	if not await _wait_for_labels(360):
		_fail("initial labels did not settle")
		return
	await _focus_france()

	var report := {
		"schema_version": 1,
		"purpose": "MV-0 apples-to-apples perspective versus orthographic France comparison",
		"captured_utc": Time.get_datetime_string_from_system(true, true),
		"engine": Engine.get_version_info(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"views": [],
	}
	var target_span := _visible_map_vertical_span()
	report["views"].append(await _capture_and_profile("france_perspective_75deg.png", "perspective", target_span))

	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = maxf(target_span, 0.1)
	for _iteration in 5:
		await process_frame
		var measured := _visible_map_vertical_span()
		if measured > 0.0001:
			_camera.size *= target_span / measured
	await _settle()
	report["views"].append(await _capture_and_profile("france_orthographic_matched.png", "orthographic", target_span))

	var report_path := _output_directory.path_join("camera_comparison.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_fail("could not write camera comparison report")
		return
	file.store_string(JSON.stringify(report, "\t", false) + "\n")
	file.close()
	print("MV-0 camera comparison completed. output=%s" % _output_directory)
	quit(0)


func _hide_hud() -> void:
	for node_name in HUD_NODE_NAMES:
		var control := _scene.get_node_or_null(node_name) as Control
		if control != null:
			control.visible = false


func _focus_france() -> void:
	_controller.reset_camera()
	await process_frame
	_controller.global_position.y += 1.4 - _camera.global_position.y
	var target := Vector3(0.3, 0.0, -5.3)
	var layout := _labels.debug_layout("FRA")
	if not layout.is_empty():
		target = layout["position"]
	_controller.focus_world_position(target)
	await _settle()


func _settle() -> void:
	for _frame in 20:
		await process_frame
	await _wait_for_labels(180)


func _wait_for_labels(frame_limit: int) -> bool:
	var waited := 0
	while _labels.debug_pending_count() > 0 and waited < frame_limit:
		await process_frame
		waited += 1
	return _labels.debug_pending_count() == 0


func _map_intersection(screen_position: Vector2) -> Vector3:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.00001:
		return Vector3(INF, INF, INF)
	var distance := (0.0 - origin.y) / direction.y
	return origin + direction * distance


func _visible_map_vertical_span() -> float:
	var center_x := float(root.size.x) * 0.5
	var top := _map_intersection(Vector2(center_x, 0.0))
	var bottom := _map_intersection(Vector2(center_x, float(root.size.y)))
	if not top.is_finite() or not bottom.is_finite():
		return 0.0
	return Vector2(top.x, top.z).distance_to(Vector2(bottom.x, bottom.z))


func _capture_and_profile(file_name: String, projection_name: String, target_span: float) -> Dictionary:
	await _settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(_output_directory.path_join(file_name)) != OK:
		_fail("could not save %s" % file_name)
		return {}
	var samples: Array[float] = []
	for frame_index in MOTION_FRAMES:
		var direction := 1.0 if frame_index < MOTION_FRAMES / 2 else -1.0
		_controller.global_position.x += 0.008 * direction
		var started := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	return {
		"file": file_name,
		"projection": projection_name,
		"fov_degrees": _camera.fov,
		"orthographic_size": _camera.size,
		"target_map_vertical_span": target_span,
		"measured_map_vertical_span": _visible_map_vertical_span(),
		"camera_position": [_camera.global_position.x, _camera.global_position.y, _camera.global_position.z],
		"camera_rotation_degrees": [_camera.global_rotation_degrees.x, _camera.global_rotation_degrees.y, _camera.global_rotation_degrees.z],
		"visible_labels": _labels.debug_visible_tags(),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"frame_interval_p50_ms": _percentile(samples, 0.50),
		"frame_interval_p95_ms": _percentile(samples, 0.95),
		"frame_interval_max_ms": _maximum(samples),
	}


func _percentile(values: Array[float], fraction: float) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[clampi(int(ceil((ordered.size() - 1) * fraction)), 0, ordered.size() - 1)] if not ordered.is_empty() else 0.0


func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result
