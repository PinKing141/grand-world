extends SceneTree

const CountryLabelLayerScript = preload("res://scripts/ui/country_label_layer.gd")
const BASELINE_PATH := "res://tests/baselines/country_label_layouts.json"
const POSITION_TOLERANCE_PX := 2.0

var _labels: CountryLabelLayer
var _camera_controller: StrategyCameraController


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("Country label visual regression failed: %s" % message)
	quit(1)


func _run() -> void:
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

	var snapshots := {}
	snapshots["default_1700x960"] = await _capture_view(Vector2i(1700, 960), "", 0.0)
	snapshots["dense_europe_1700x960"] = await _capture_view(Vector2i(1700, 960), "FRA", 1.4)
	snapshots["island_southeast_asia_1152x648"] = await _capture_view(Vector2i(1152, 648), "MAJ", 1.0)
	snapshots["scandinavia_shape_1152x648"] = await _capture_view(Vector2i(1152, 648), "SWE", 1.2)
	snapshots["italian_peninsula_shape_1152x648"] = await _capture_view(Vector2i(1152, 648), "NAP", 1.0)

	if OS.get_cmdline_user_args().has("--update-label-baseline"):
		var output := FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
		if output == null:
			_fail("could not write %s" % BASELINE_PATH)
			return
		output.store_string(JSON.stringify({"schema_version": 1, "snapshots": snapshots}, "  ") + "\n")
		print("Country label visual baseline updated: %s" % BASELINE_PATH)
		quit(0)
		return

	var baseline_file := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	if baseline_file == null:
		_fail("baseline is missing; run with -- --update-label-baseline")
		return
	var baseline_json := JSON.new()
	if baseline_json.parse(baseline_file.get_as_text()) != OK or not baseline_json.data is Dictionary:
		_fail("baseline JSON is invalid")
		return
	var expected_snapshots: Dictionary = (baseline_json.data as Dictionary).get("snapshots", {})
	for snapshot_name in snapshots:
		if not expected_snapshots.has(snapshot_name):
			_fail("baseline is missing snapshot %s" % snapshot_name)
			return
		if not _compare_snapshot(snapshot_name, expected_snapshots[snapshot_name], snapshots[snapshot_name]):
			return
	print("Country label visual regression passed. snapshots=%d" % snapshots.size())
	quit(0)


func _capture_view(viewport_size: Vector2i, focus_tag: String, camera_height: float) -> Dictionary:
	root.size = viewport_size
	_camera_controller.reset_camera()
	await process_frame
	if camera_height > 0.0:
		var height_delta := camera_height - _camera_controller.camera.global_position.y
		_camera_controller.global_position.y += height_delta
	if not focus_tag.is_empty():
		var layout := _labels.debug_layout(focus_tag)
		if layout.is_empty():
			_fail("focus country %s has no label layout" % focus_tag)
			return {}
		_camera_controller.focus_world_position(layout["position"])
	await process_frame
	await process_frame
	var serialized_rects := {}
	var rects := _labels.debug_screen_rects()
	var tags := rects.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		var rect: Rect2 = rects[raw_tag]
		serialized_rects[tag] = [
			snappedf(rect.position.x, 0.1),
			snappedf(rect.position.y, 0.1),
			snappedf(rect.size.x, 0.1),
			snappedf(rect.size.y, 0.1),
			String(_labels.debug_layout(tag).get("text", "")),
		]
	return {
		"viewport": [viewport_size.x, viewport_size.y],
		"focus_tag": focus_tag,
		"camera_height": snappedf(_camera_controller.camera.global_position.y, 0.001),
		"visible_count": serialized_rects.size(),
		"labels": serialized_rects,
	}


func _compare_snapshot(snapshot_name: String, expected_value, actual_value) -> bool:
	var expected: Dictionary = expected_value
	var actual: Dictionary = actual_value
	var expected_labels: Dictionary = expected.get("labels", {})
	var actual_labels: Dictionary = actual.get("labels", {})
	var expected_tags := expected_labels.keys()
	var actual_tags := actual_labels.keys()
	expected_tags.sort()
	actual_tags.sort()
	if expected_tags != actual_tags:
		_fail("%s visible tags changed: expected %s, actual %s" % [snapshot_name, expected_tags, actual_tags])
		return false
	for raw_tag in expected_tags:
		var tag := String(raw_tag)
		var expected_rect: Array = expected_labels[tag]
		var actual_rect: Array = actual_labels[tag]
		if String(expected_rect[4]) != String(actual_rect[4]):
			_fail("%s label text changed for %s: %s -> %s" % [snapshot_name, tag, expected_rect[4], actual_rect[4]])
			return false
		for component in 4:
			if absf(float(expected_rect[component]) - float(actual_rect[component])) > POSITION_TOLERANCE_PX:
				_fail("%s projected bounds changed for %s: expected %s, actual %s" % [snapshot_name, tag, expected_rect, actual_rect])
				return false
	return true
