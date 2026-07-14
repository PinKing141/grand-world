extends SceneTree

const CountryLabelLayerScript = preload("res://scripts/ui/country_label_layer.gd")

var _labels: CountryLabelLayer
var _camera_controller: StrategyCameraController
var _output_directory := ""


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("Country label render capture failed: %s" % message)
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
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("main scene must load")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	_labels = scene.get_node("CountryLabelLayer") as CountryLabelLayerScript
	_camera_controller = scene.get_node("CameraController") as StrategyCameraController
	var wait_frames := 0
	while _labels.debug_pending_count() > 0 and wait_frames < 300:
		await process_frame
		wait_frames += 1
	if _labels.debug_pending_count() > 0:
		_fail("label layouts did not finish")
		return

	await _capture("default_1700x960.png", Vector2i(1700, 960), "", 0.0)
	await _capture("dense_europe_1700x960.png", Vector2i(1700, 960), "FRA", 1.4)
	await _capture("island_southeast_asia_1152x648.png", Vector2i(1152, 648), "MAJ", 1.0)
	await _capture("scandinavia_shape_1152x648.png", Vector2i(1152, 648), "SWE", 1.2)
	await _capture("italian_peninsula_shape_1152x648.png", Vector2i(1152, 648), "NAP", 1.0)
	print("Country label rendered captures completed. output=%s" % _output_directory)
	quit(0)


func _capture(file_name: String, viewport_size: Vector2i, focus_tag: String, camera_height: float) -> void:
	root.size = viewport_size
	Input.warp_mouse(Vector2(5.0, 5.0))
	_camera_controller.reset_camera()
	await process_frame
	if camera_height > 0.0:
		_camera_controller.global_position.y += camera_height - _camera_controller.camera.global_position.y
	if not focus_tag.is_empty():
		var layout := _labels.debug_layout(focus_tag)
		if layout.is_empty():
			_fail("focus country %s has no layout" % focus_tag)
			return
		_camera_controller.focus_world_position(layout["position"])
	await process_frame
	await process_frame
	var node_wait_frames := 0
	while _labels.debug_pending_count() > 0 and node_wait_frames < 60:
		await process_frame
		node_wait_frames += 1
	if _labels.debug_pending_count() > 0:
		_fail("visible label allocation did not finish for %s" % file_name)
		return
	# Allow swapchain resize, compute-map textures, and font atlases to settle
	# before reading the viewport. This keeps cross-run captures deterministic.
	for _settle_frame in 6:
		var map_hud := current_scene.get_node_or_null("MapHUD") as MapHUD
		if map_hud != null and map_hud.tooltip != null:
			map_hud.tooltip.hide()
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("rendered viewport image is empty for %s" % file_name)
		return
	var path := _output_directory.path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		_fail("could not save %s: %s" % [path, error_string(error)])
