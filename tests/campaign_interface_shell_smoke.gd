extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Campaign interface shell smoke failed: %s" % message)
		quit(1)


func _run() -> void:
	var capture_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
	root.set_meta("grand_world_country_selection", true)
	root.set_meta("grand_world_continue_campaign", false)
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in 4:
		await process_frame

	var selection := scene.get_node("CountrySelectionScreen")
	var shell := scene.get_node("CampaignInterfaceShell") as CampaignInterfaceShell
	var map_hud := scene.get_node("MapHUD") as MapHUD
	_require(selection.visible and not shell.visible, "country selection must own the screen before Play")
	var england := selection.get_node("RecommendedPanel/Margin/Content/RecommendedRow/ENGRecommendation") as Button
	england.pressed.emit()
	await process_frame
	selection.call("_play_selected_country")
	for _frame in 4:
		await process_frame

	_require(shell.visible, "the campaign shell must appear after selecting a country")
	_require(shell.debug_country_name() == "England", "the shell must show a full country name, never ENG")
	_require(not scene.get_node("EconomyHUD/ResourceBar").visible, "the legacy resource strip must be replaced")
	_require(not scene.get_node("SimulationHUD/TopBar").visible, "the legacy clock strip must be replaced")
	_require(not scene.get_node("MapHUD/MapModeBar").visible, "the legacy map-mode strip must be replaced")
	_require(not scene.get_node("MapHUD/HintBar").visible, "the permanent help ribbon must be removed")
	_require(shell.debug_outliner_entry_count() >= 8, "the outliner must contain strategic sections and a player army")

	var mini_size := shell.minimap.size
	var centre_world := shell.debug_minimap_world(mini_size * 0.5)
	_require(absf(centre_world.x) < 0.01 and absf(centre_world.z) < 0.01, "the minimap centre must resolve to the world-map centre")
	var corner_world := shell.debug_minimap_world(Vector2.ZERO)
	_require(is_equal_approx(corner_world.x, -28.16) and is_equal_approx(corner_world.z, -10.24), "the minimap corner must resolve to the canonical world bounds")

	var terrain_button := shell.navigation_panel.find_child("TerrainMapMode", true, false) as Button
	_require(terrain_button != null, "the navigation dock must expose terrain map mode")
	terrain_button.pressed.emit()
	_require(map_hud.get_map_mode() == 1, "shell map-mode navigation must retain the MapHUD authority")
	map_hud.set_map_mode(0)

	var province_panel := scene.get_node("MapHUD/ProvincePanel") as Control
	_require(province_panel.offset_left <= 10.0 and province_panel.offset_top >= 150.0, "province details must dock beneath the country bar on the left: rect=%s min=%s anchors=%s/%s offsets=%s/%s/%s/%s" % [province_panel.get_rect(), province_panel.get_combined_minimum_size(), province_panel.anchor_left, province_panel.anchor_top, province_panel.offset_left, province_panel.offset_top, province_panel.offset_right, province_panel.offset_bottom])
	if not capture_path.is_empty():
		for _frame in 90:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		_require(capture != null and capture.save_png(capture_path) == OK, "the campaign-shell visual capture must save")
	print("Campaign interface shell smoke passed. country=England outliner=%d minimap=canonical" % shell.debug_outliner_entry_count())
	quit(0)
