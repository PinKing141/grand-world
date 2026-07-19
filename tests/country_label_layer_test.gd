extends SceneTree

const CountryLabelLayerScript = preload("res://scripts/ui/country_label_layer.gd")
const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")
const MAX_INITIAL_LAYOUT_MS := 1000.0
const MAX_LAYOUT_BATCH_MS := 30.0
const MAX_INCREMENTAL_LAYOUT_MS := 20.0
const MAX_VISIBILITY_MS := 30.0
const MAX_NODE_BATCH_MS := 20.0


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Country label layer test failed: %s" % message)
		quit(1)


func _require_no_overlaps(rects: Dictionary, context: String) -> void:
	var tags := rects.keys()
	tags.sort()
	for first_index in tags.size():
		for second_index in range(first_index + 1, tags.size()):
			var first := String(tags[first_index])
			var second := String(tags[second_index])
			_require(
				not (rects[first] as Rect2).intersects(rects[second] as Rect2),
				"%s labels %s and %s overlap" % [context, first, second]
			)


func _require_bounded_rects(rects: Dictionary, viewport_size: Vector2, context: String) -> void:
	var bounds := Rect2(Vector2.ZERO, viewport_size).grow(64.0)
	const EPSILON := 0.25
	for raw_tag in rects:
		var tag := String(raw_tag)
		var rect := rects[raw_tag] as Rect2
		var bounded := (
			rect.position.x >= bounds.position.x - EPSILON
			and rect.position.y >= bounds.position.y - EPSILON
			and rect.end.x <= bounds.end.x + EPSILON
			and rect.end.y <= bounds.end.y + EPSILON
		)
		_require(bounded, "%s label %s escaped the bounded collision grid: %s" % [context, tag, rect])


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	await process_frame

	var simulation := scene.get_node("SimulationController") as GrandWorldSimulationController
	var labels := scene.get_node("CountryLabelLayer") as CountryLabelLayerScript
	var map_hud := scene.get_node("MapHUD") as MapHUD
	var camera_controller := scene.get_node("CameraController") as StrategyCameraController
	_require(simulation != null and simulation.initialized, "simulation must initialize")
	_require(labels != null, "CountryLabelLayer must exist")
	# The wait cap must scale with the incremental batcher's own pace
	# (MAX_INCREMENTAL_TAGS_PER_FRAME tags/frame) rather than a fixed frame
	# count - a fixed 300-frame cap silently stopped waiting before the queue
	# actually drained once the batch size shrank, and every assertion below
	# then ran against a partially-populated `_layouts` map, producing
	# misleading failures for whichever countries simply hadn't been
	# processed yet (not a real per-country defect).
	var expected_tag_count := simulation.world.country_to_provinces.keys().size()
	var batch_size := maxi(1, CountryLabelLayerScript.MAX_INCREMENTAL_TAGS_PER_FRAME)
	var wait_cap := ceili(float(expected_tag_count) / float(batch_size)) + 60
	var initial_wait_frames := 0
	while labels.debug_pending_count() > 0 and initial_wait_frames < wait_cap:
		await process_frame
		initial_wait_frames += 1
	if labels.debug_pending_count() > 0:
		push_error("Country label layer test failed: initial label queue did not drain after %d frames (batch_size=%d expected_tag_count=%d pending=%d layout_count=%d)" % [wait_cap, batch_size, expected_tag_count, labels.debug_pending_count(), labels.debug_layout_count()])
		quit(1)
		return
	_require(labels.debug_layout_count() >= 650, "starting world must create layouts for active territorial countries")
	_require(labels.debug_font_path() == "res://assets/fonts/LibreBaskerville-Variable.ttf", "bundled font must be authoritative")
	_require(FileAccess.file_exists(labels.debug_font_path()), "bundled font must exist")

	var metrics := labels.debug_metrics()
	_require(float(metrics["initial_layout_ms"]) <= MAX_INITIAL_LAYOUT_MS, "initial layout exceeded %.0f ms: %s" % [MAX_INITIAL_LAYOUT_MS, metrics])
	_require(float(metrics["max_layout_batch_ms"]) <= MAX_LAYOUT_BATCH_MS, "layout frame budget exceeded %.0f ms: %s" % [MAX_LAYOUT_BATCH_MS, metrics])
	_require(float(metrics["last_visibility_ms"]) <= MAX_VISIBILITY_MS, "visibility pass exceeded %.0f ms: %s" % [MAX_VISIBILITY_MS, metrics])
	_require(float(metrics["max_node_batch_ms"]) <= MAX_NODE_BATCH_MS, "label allocation batch exceeded %.0f ms: %s" % [MAX_NODE_BATCH_MS, metrics])
	_require(String(metrics.get("renderer", "")) == "screen_space_msdf_multimesh", "country labels must use the batched MSDF renderer: %s" % metrics)
	_require(int(metrics.get("label3d_node_count", -1)) == 0, "batched mode must not allocate Label3D fallbacks: %s" % metrics)
	_require(int(metrics.get("batch_draw_count", 99)) <= 8, "country labels exceeded the atlas-page draw budget: %s" % metrics)
	_require(int(metrics.get("batch_glyph_count", 0)) > int(metrics.get("visible_count", 0)), "visible country names must produce batched glyph instances: %s" % metrics)
	var label_style := labels.debug_label_style()
	_require(not bool(label_style.get("background_enabled", true)), "country labels must not render highlight/background plates: %s" % label_style)
	_require(int(label_style.get("outline_size", -1)) == 0, "country labels must not use the former pale glow outline: %s" % label_style)
	_require(float(label_style.get("minimum_screen_height", 0.0)) >= 11.0, "illegibly small labels must cull before becoming blurred bars: %s" % label_style)
	_require(int(metrics.get("full_name_count", 0)) == labels.debug_layout_count(), "every country layout must use a full name")
	_require(not metrics.has("tag_fallback_count"), "tag fallback metrics must not return after full-name enforcement")
	_require(int(metrics.get("shape_aligned_count", 0)) >= 500, "most territorial countries should use shape-aware alignment")
	_require(labels.debug_node_count() < labels.debug_layout_count(), "hidden labels must remain uninstantiated")
	_require(labels.debug_node_count() <= 250, "default-view label nodes exceeded the P1 budget")
	_require(not labels.debug_visible_tags().is_empty(), "default view must show some country labels")

	for tag in labels.debug_layout_tags():
		var layout := labels.debug_layout(tag)
		_require(not String(layout.get("text", "")).is_empty(), "%s has empty text" % tag)
		_require(String(layout.get("text", "")) == simulation.country_registry.display_name(tag), "%s must render its canonical full name, not its tag" % tag)
		_require(String(layout.get("text", "")) != tag, "%s must never use a country tag as visible label text" % tag)
		_require(float(layout.get("pixel_size", 0.0)) > 0.0, "%s has invalid size" % tag)
		var fit_mode := String(layout.get("fit_mode", ""))
		_require(fit_mode in ["territory", "shape_aligned", "screen_fallback"], "%s has unknown fit mode %s" % [tag, fit_mode])
		if fit_mode != "screen_fallback":
			_require(bool(layout.get("fits_territory", false)), "%s should fit its conservative territory" % tag)
			if fit_mode == "territory":
				_require((layout.get("territory_rect_cells", Rect2i()) as Rect2i).has_area(), "%s lacks a safe territory rectangle" % tag)
		if fit_mode == "shape_aligned":
			_require(int(layout.get("shape_cell_count", 0)) >= 8, "%s lacks enough raster samples for shape alignment" % tag)
			_require(absf(float(layout.get("angle_degrees", 0.0))) <= 72.01, "%s exceeds the readable angle limit" % tag)
			_require((layout.get("fit_world_size", Vector2.ZERO) as Vector2).x > 0.0, "%s lacks a shape-fit extent" % tag)

	_require(labels.debug_layout("MUN").get("full_name", "") == "Münster", "German Münster must be disambiguated")
	_require(labels.debug_layout("MNS").get("full_name", "") == "Munster", "Irish Munster must retain its name")
	_require(simulation.country_registry.display_name("SOF") == "Segu", "SOF must use the historically contextual Segu name")
	_require(labels.debug_layout("SFA").get("full_name", "") == "Sofala", "SFA must retain Sofala")
	_require(float(labels.debug_layout("SWE").get("angle_degrees", 0.0)) < -30.0, "Sweden must follow its diagonal territorial axis")
	_require(float(labels.debug_layout("ENG").get("angle_degrees", 0.0)) > 55.0, "England must follow its north-south island shape")
	_require(float(labels.debug_layout("NAP").get("angle_degrees", 0.0)) > 30.0, "Naples must follow the Italian peninsula's southeast axis")
	_require(float(labels.debug_layout("SWE").get("pixel_size", 0.0)) >= 0.006, "Sweden must retain a prominent world-map label")
	var naples_pixel_size := float(labels.debug_layout("NAP").get("pixel_size", 0.0))
	_require(naples_pixel_size >= 0.0015, "Naples must retain a readable peninsula label: %.6f" % naples_pixel_size)
	_require(labels.debug_render_scale() > 0.99, "default world view must use the full label scale")
	_require_no_overlaps(labels.debug_screen_rects(), "default-view")
	_require_bounded_rects(labels.debug_screen_rects(), labels.debug_viewport_size(), "default-view")

	var visibility_revision := labels.debug_visibility_revision()
	camera_controller.global_position.x += 0.5
	await process_frame
	_require(labels.debug_visibility_revision() > visibility_revision, "horizontal camera pan must invalidate screen-space layout")
	_require_no_overlaps(labels.debug_screen_rects(), "panned-view")
	_require_bounded_rects(labels.debug_screen_rects(), labels.debug_viewport_size(), "panned-view")

	visibility_revision = labels.debug_visibility_revision()
	root.size = Vector2i(1152, 648)
	await process_frame
	_require(labels.debug_visibility_revision() > visibility_revision, "viewport resize must invalidate screen-space layout")
	_require_no_overlaps(labels.debug_screen_rects(), "resized-view")
	_require_bounded_rects(labels.debug_screen_rects(), labels.debug_viewport_size(), "resized-view")

	map_hud.set_map_mode(MapHUD.MODE_DEBUG)
	await process_frame
	_require(labels.debug_visible_tags().is_empty(), "province-ID debug mode must hide country names")
	map_hud.set_map_mode(MapHUD.MODE_POLITICAL)
	await process_frame
	_require(not labels.debug_visible_tags().is_empty(), "political mode must restore country names")
	map_hud.set_map_mode(MapHUD.MODE_TERRAIN)
	await process_frame
	_require(not labels.debug_visible_tags().is_empty(), "terrain mode must retain country names")
	map_hud.set_economy_map_mode("economy", "Test economy overlay", {})
	await process_frame
	_require(not labels.debug_visible_tags().is_empty(), "thematic overlays must retain country names")
	map_hud.set_map_mode(MapHUD.MODE_POLITICAL)

	var french_provinces := simulation.world.get_country_provinces("FRA")
	_require(not french_provinces.is_empty(), "France must have a province for incremental testing")
	var transferred_province := int(french_provinces[0])
	simulation.change_province_owner_for_testing(transferred_province, "ENG")
	simulation.scheduler.process_commands()
	await process_frame
	var rebuilt := labels.debug_last_rebuilt_tags()
	_require(rebuilt == ["ENG", "FRA"], "ownership transfer rebuilt unexpected countries: %s" % [rebuilt])
	metrics = labels.debug_metrics()
	_require(float(metrics["last_incremental_ms"]) <= MAX_INCREMENTAL_LAYOUT_MS, "incremental layout exceeded %.0f ms: %s" % [MAX_INCREMENTAL_LAYOUT_MS, metrics])
	_require(float(metrics["last_visibility_ms"]) <= MAX_VISIBILITY_MS, "post-transfer visibility exceeded %.0f ms: %s" % [MAX_VISIBILITY_MS, metrics])

	var munster_provinces := simulation.world.get_country_provinces("MNS")
	_require(munster_provinces.size() == 1, "Irish Munster must be a one-province annexation fixture")
	var munster_layout := labels.debug_layout("MNS")
	camera_controller.global_position.y += 1.0 - camera_controller.camera.global_position.y
	camera_controller.focus_world_position(munster_layout["position"])
	var node_wait_frames := 0
	while not labels.debug_has_node("MNS") and node_wait_frames < 30:
		await process_frame
		node_wait_frames += 1
	_require(labels.debug_visible_tags().has("MNS"), "close view must instantiate the Munster label")
	_require(labels.debug_has_node("MNS"), "visible Munster must own one lazy label node")
	_require(labels.debug_render_scale() < 0.75, "close zoom must temper label size without changing its authored layout")
	metrics = labels.debug_metrics()
	_require(float(metrics["last_visibility_ms"]) <= MAX_VISIBILITY_MS, "maximum-zoom visibility exceeded %.0f ms: %s" % [MAX_VISIBILITY_MS, metrics])
	_require(float(metrics["max_node_batch_ms"]) <= MAX_NODE_BATCH_MS, "maximum-zoom allocation batch exceeded %.0f ms: %s" % [MAX_NODE_BATCH_MS, metrics])
	_require(labels.debug_node_count() <= 450, "maximum-zoom label nodes exceeded the P1 budget")
	simulation.change_province_owner_for_testing(int(munster_provinces[0]), "ENG")
	simulation.scheduler.process_commands()
	await process_frame
	_require(labels.debug_layout("MNS").is_empty(), "annexed country layout must be removed")
	_require(not labels.debug_has_node("MNS"), "annexed country label node must be reclaimed")
	_require(labels.debug_last_rebuilt_tags() == ["ENG", "MNS"], "annexation must rebuild only old/new countries")

	simulation.event_bus.country_formed.emit("FRA", "ENG")
	simulation.event_bus.country_released.emit("ENG", "FRA", [transferred_province])
	simulation.event_bus.country_extinct.emit("FRA")
	await process_frame
	_require(labels.debug_last_rebuilt_tags() == ["ENG", "FRA"], "formation/release/extinction signals must schedule affected countries")

	var saved := simulation.quick_save()
	_require(saved.get("ok", false), "quick save must succeed")
	simulation.change_province_owner_for_testing(transferred_province, "FRA")
	simulation.scheduler.process_commands()
	var loaded := simulation.quick_load()
	_require(loaded.get("ok", false), "quick load must succeed")
	var reload_wait_frames := 0
	while labels.debug_pending_count() > 0 and reload_wait_frames < 300:
		await process_frame
		reload_wait_frames += 1
	_require(labels.debug_pending_count() == 0, "world reload must complete a full label refresh")
	_require(simulation.world.get_province_owner(transferred_province) == "ENG", "quick load must restore transferred ownership")
	_require_no_overlaps(labels.debug_screen_rects(), "reloaded-view")
	_require_bounded_rects(labels.debug_screen_rects(), labels.debug_viewport_size(), "reloaded-view")

	var quick_save_absolute := ProjectSettings.globalize_path(GrandWorldSimulationController.QUICK_SAVE_PATH)
	if FileAccess.file_exists(quick_save_absolute):
		DirAccess.remove_absolute(quick_save_absolute)
	print("Country label layer P1 test passed. metrics=%s" % [labels.debug_metrics()])
	quit(0)
