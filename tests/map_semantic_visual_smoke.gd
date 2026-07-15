extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Map semantic visual smoke failed: %s" % message)
		quit(1)


func _run() -> void:
	var capture_path := ""
	var war_goal_capture_path := ""
	var accessibility_capture_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--capture-war-goal="):
			war_goal_capture_path = argument.trim_prefix("--capture-war-goal=")
		elif argument.begins_with("--capture-accessibility="):
			accessibility_capture_path = argument.trim_prefix("--capture-accessibility=")
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var map_render = scene.get_node("Map")
	var army_layer := scene.get_node("ArmyLayer") as ArmyLayer
	var camera_controller := scene.get_node("CameraController") as StrategyCameraController
	var map_hud := scene.get_node("MapHUD") as MapHUD
	var simulation = scene.get_node("SimulationController")
	_require(map_render.final_material != null, "final map material must be available")
	_require(army_layer.debug_uses_flag_atlas(), "army markers must use the generated country-shield atlas shader")
	_require(army_layer.debug_troop_label_count() == simulation.world.army_registry.size(), "every authoritative army marker must pair its country emblem with one troop-strength label")
	_require(army_layer.debug_uses_batched_troop_counters(), "troop counters must remain one GPU batch rather than one Label3D node per army")
	var marker_sizes := army_layer.debug_marker_sizes()
	_require(marker_sizes.x <= 0.10 and marker_sizes.y <= 0.11, "army flags must keep the compact map-counter footprint")
	_require(marker_sizes.z <= 0.19 and marker_sizes.w <= 0.09, "troop counters must remain much smaller than the original oversized markers")
	_require(army_layer.debug_marker_stack_spacing() <= 0.03, "armies sharing a province need compact stack spacing")
	var marker_visibility_band := army_layer.debug_marker_visibility_band()
	_require(marker_visibility_band.x <= 3.201 and marker_visibility_band.y <= 4.601, "ordinary armies must fade before they overwhelm the regional and world views")
	_require(army_layer.debug_country_flag_index("ENG") >= 0 and army_layer.debug_country_flag_index("FRA") >= 0, "priority historical countries must resolve to shield atlas slots")
	_require(army_layer.debug_country_flag_index("ENG") != army_layer.debug_country_flag_index("FRA"), "different countries must never share an accidental flag slot")
	var strategic_border_width = map_render.final_material.get_shader_parameter("province_border_strategic_width")
	var close_border_width = map_render.final_material.get_shader_parameter("province_border_close_width")
	var province_border_opacity = map_render.final_material.get_shader_parameter("province_border_opacity")
	_require(strategic_border_width != null and is_equal_approx(float(strategic_border_width), 0.80), "strategic province borders must retain their restrained screen-space width")
	_require(close_border_width != null and is_equal_approx(float(close_border_width), 1.45), "close province borders must grow with camera zoom")
	_require(province_border_opacity != null and is_equal_approx(float(province_border_opacity), 1.0), "ordinary province borders need an opaque solid core")
	var lake_texture := map_render.final_material.get_shader_parameter("lake_mask") as Texture2D
	_require(lake_texture != null, "canonical lake mask must be bound to the final shader")
	var lake_image := lake_texture.get_image()
	var graph := ProvinceGraph.load_default()
	var edge_texture := map_render.final_material.get_shader_parameter("province_edge_lattice") as Texture2D
	var lookup_texture := map_render.final_material.get_shader_parameter("lookup_map") as Texture2D
	_require(edge_texture != null and lookup_texture != null, "canonical province edge lattice and exact ID lookup must be bound")
	if DisplayServer.get_name() != "headless":
		var edge_image := edge_texture.get_image()
		var lookup_image := lookup_texture.get_image()
		_require(edge_image != null and lookup_image != null and edge_image.get_size() == lookup_image.get_size(), "edge lattice must preserve exact province-map resolution")
		var lattice_anchor := graph.anchor(222)
		var vertical_edges := 0
		var horizontal_edges := 0
		var lattice_mismatches := 0
		for y in range(maxi(lattice_anchor.y - 96, 1), mini(lattice_anchor.y + 97, lookup_image.get_height())):
			for x in range(maxi(lattice_anchor.x - 96, 1), mini(lattice_anchor.x + 97, lookup_image.get_width())):
				var current_id := lookup_image.get_pixel(x, y)
				var left_id := lookup_image.get_pixel(x - 1, y)
				var upper_id := lookup_image.get_pixel(x, y - 1)
				var expected_vertical := absf(current_id.r - left_id.r) > 0.5 / 255.0 or absf(current_id.g - left_id.g) > 0.5 / 255.0
				var expected_horizontal := absf(current_id.r - upper_id.r) > 0.5 / 255.0 or absf(current_id.g - upper_id.g) > 0.5 / 255.0
				var stored_edge := edge_image.get_pixel(x, y)
				vertical_edges += int(expected_vertical)
				horizontal_edges += int(expected_horizontal)
				lattice_mismatches += int(expected_vertical != (stored_edge.r > 0.5))
				lattice_mismatches += int(expected_horizontal != (stored_edge.g > 0.5))
		_require(vertical_edges > 0 and horizontal_edges > 0, "edge-lattice fixture must cross both vertical and horizontal province adjacencies")
		_require(lattice_mismatches == 0, "every edge-lattice channel must match its one authoritative province adjacency")
	var geneva := graph.anchor(1889)
	var stockholm := graph.anchor(1)
	_require(lake_image.get_pixel(geneva.x, geneva.y).r > 0.9, "Lake Geneva must use inland-water presentation")
	_require(lake_image.get_pixel(stockholm.x, stockholm.y).r < 0.1, "ordinary land must not enter the lake mask")
	_require(map_hud.colour_vision_option.item_count == 4, "the player must be able to choose every supported colour-vision profile")
	for profile in range(4):
		map_hud.set_colour_vision_profile(profile, false)
		_require(map_hud.get_colour_vision_profile() == profile and map_render.debug_accessibility_profile() == profile, "colour-vision profile %d must reach the final map material" % profile)
	map_hud.set_colour_vision_profile(0, false)
	_require(army_layer.debug_route_style() == "none" and army_layer.debug_route_surface_count() == 0, "a fresh campaign must not render a command path")
	_require(not army_layer.debug_destination_visible() and army_layer.debug_selected_army().is_empty(), "a fresh campaign must not render a destination marker")

	army_layer.set_preview_path(PackedInt32Array([226, 1751]))
	army_layer._process(0.0)
	_require(army_layer.debug_route_style() == "preview", "a route preview must use the dashed preview style")
	_require(army_layer.debug_route_surface_count() == 1, "a route preview must generate one batched inner surface")
	var widths := army_layer.debug_route_widths()
	_require(widths.y > widths.x and widths.x > 0.0, "command paths need a wider dark outline than their inner stroke")
	var viewport_height := root.get_visible_rect().size.y
	var inner_pixels := widths.x / camera_controller.camera.size * viewport_height
	var outline_pixels := widths.y / camera_controller.camera.size * viewport_height
	_require(absf(inner_pixels - 3.0) < 0.2, "orthographic route inner width must remain approximately three screen pixels")
	_require(absf(outline_pixels - 5.5) < 0.25, "orthographic route outline must remain approximately 5.5 screen pixels")
	if not capture_path.is_empty():
		root.size = Vector2i(1152, 648)
		camera_controller.global_position.y += 1.0 - camera_controller.camera.global_position.y
		camera_controller._sync_projection_to_height(true)
		var route_center := (army_layer.anchor_world_position(226) + army_layer.anchor_world_position(1751)) * 0.5
		camera_controller.focus_world_position(route_center)
		for hud_name in ["MapHUD", "SimulationHUD", "EconomyHUD", "WarHUD", "AIDebugHUD", "CharacterHUD", "CountryDepthHUD"]:
			var hud := scene.get_node_or_null(hud_name) as Control
			if hud != null:
				hud.visible = false
		for _frame in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		_require(capture != null and capture.save_png(capture_path) == OK, "semantic route capture must save")

	var previous_world_width := widths.x
	camera_controller._zoom_at_screen(root.get_visible_rect().size * 0.5, -1.0, 1.0)
	army_layer._process(0.0)
	widths = army_layer.debug_route_widths()
	_require(widths.x < previous_world_width, "zooming in must reduce route world width to preserve screen width")
	inner_pixels = widths.x / camera_controller.camera.size * viewport_height
	_require(absf(inner_pixels - 3.0) < 0.2, "route width must remain screen-stable after zoom")
	army_layer.set_preview_path(PackedInt32Array([4937, 4934]))
	army_layer._process(0.0)
	_require(army_layer.debug_route_wrap_splits() == 1, "a Fiji-to-Hawaii route must split once at the wrapped world seam")
	_require(army_layer.debug_route_surface_count() == 1, "world-seam route pieces must stay inside one bounded batch")
	var wrapped_bounds := army_layer.debug_route_aabb()
	_require(wrapped_bounds.position.x >= -28.18 and wrapped_bounds.end.x <= 28.18, "world-seam route geometry must remain inside map bounds: %s" % wrapped_bounds)

	army_layer.clear_preview_path()
	army_layer._process(0.0)
	_require(army_layer.debug_route_style() == "none", "clearing a preview without a selected moving army must remove the route")
	army_layer.set_invalid_destination(1889)
	army_layer._process(0.0)
	_require(army_layer.debug_route_style() == "invalid", "an unreachable destination needs an explicit invalid shape state")
	_require(army_layer.debug_route_surface_count() == 0, "invalid destinations must not imply a traversable route")
	_require(not army_layer.debug_destination_visible() and army_layer.debug_invalid_destination_visible(), "invalid orders need an X marker instead of the valid destination cone")
	army_layer.clear_preview_path()
	army_layer._process(0.0)
	_require(not army_layer.debug_invalid_destination_visible(), "clearing targeting must remove invalid feedback")
	map_render.set_war_goal_province(222)
	_require(map_render.debug_war_goal_province() == 222, "the semantic war-goal target must retain its canonical province ID")
	_require(bool(map_render.final_material.get_shader_parameter("war_goal_enabled")), "the final shader must enable the war-goal double border")
	var overlap_owner: String = simulation.world.get_province_owner(222)
	map_render.update_province_control(222, overlap_owner, "FRA" if overlap_owner != "FRA" else "CAS", simulation.world.player_country)
	map_render._on_province_hovered({"province_id": 222}, Vector2.ZERO)
	map_render._on_province_selected({"province_id": 222, "owner_tag": overlap_owner})
	_require(map_render.debug_control_cue(222).r > 0.5, "dense overlap fixture must include occupation")
	_require(bool(map_render.final_material.get_shader_parameter("hover_enabled")) and bool(map_render.final_material.get_shader_parameter("selection_enabled")), "dense overlap fixture must keep hover and selection above the war goal")
	_require(map_render.debug_semantic_priority() == ["passive_borders", "occupation", "war_goal", "hover", "selection"], "semantic overlay priority must remain deterministic")
	map_render.update_province_control(222, overlap_owner, overlap_owner, simulation.world.player_country)
	map_render._on_province_hover_cleared()
	map_render._on_selection_cleared()
	if not war_goal_capture_path.is_empty():
		root.size = Vector2i(1152, 648)
		camera_controller.global_position.y += 1.0 - camera_controller.camera.global_position.y
		camera_controller._sync_projection_to_height(true)
		camera_controller.focus_world_position(army_layer.anchor_world_position(222))
		for hud_name in ["MapHUD", "SimulationHUD", "EconomyHUD", "WarHUD", "AIDebugHUD", "CharacterHUD", "CountryDepthHUD"]:
			var hud := scene.get_node_or_null(hud_name) as Control
			if hud != null:
				hud.visible = false
		for _frame in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		var war_goal_capture := root.get_texture().get_image()
		_require(war_goal_capture != null and war_goal_capture.save_png(war_goal_capture_path) == OK, "war-goal semantic capture must save")
	map_render.restore_political_map()
	_require(map_render.debug_war_goal_province() == -1 and not bool(map_render.final_material.get_shader_parameter("war_goal_enabled")), "restoring the normal political map must clear stale war-goal semantics")

	camera_controller.global_position.y += 13.0 - camera_controller.camera.global_position.y
	camera_controller._sync_projection_to_height(true)
	army_layer._process(0.0)
	_require(not army_layer.debug_markers_visible(), "the unselected army batch must be hidden at world zoom")
	if not accessibility_capture_path.is_empty():
		root.size = Vector2i(1152, 648)
		map_hud.set_colour_vision_profile(1, false)
		camera_controller.global_position.y += 1.0 - camera_controller.camera.global_position.y
		camera_controller._sync_projection_to_height(true)
		camera_controller.focus_world_position(army_layer.anchor_world_position(222))
		for hud_name in ["MapHUD", "SimulationHUD", "EconomyHUD", "WarHUD", "AIDebugHUD", "CharacterHUD", "CountryDepthHUD"]:
			var hud := scene.get_node_or_null(hud_name) as Control
			if hud != null:
				hud.visible = false
		for _frame in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		var accessibility_capture := root.get_texture().get_image()
		_require(accessibility_capture != null and accessibility_capture.save_png(accessibility_capture_path) == OK, "colour-vision profile capture must save")
		map_hud.set_colour_vision_profile(0, false)

	print("Map semantic visual smoke passed. lakes=bound route_px=%.2f/%.2f world_markers=hidden" % [inner_pixels, outline_pixels])
	quit(0)
