extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Main-menu single-player flow smoke failed: %s" % message)
		quit(1)


func _run() -> void:
	var packed := load("res://scenes/main_menu.tscn") as PackedScene
	_require(packed != null, "the main-menu scene must load")
	var menu := packed.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame

	menu.call("_start_single_player")
	for _frame in 12:
		await process_frame

	var campaign := current_scene
	_require(campaign != null and campaign != menu, "Single Player must change to the campaign scene")
	_require(campaign.get_node_or_null("SimulationController") != null, "the campaign simulation must be present")
	var map_render := campaign.get_node("Map")
	_require(not bool(map_render.call("debug_compute_resources_active")), "prebaked production maps must not retain an unused local rendering device")
	var selection := campaign.get_node_or_null("CountrySelectionScreen")
	_require(selection != null and selection.visible, "the country-selection screen must open after the scene change")
	_require(bool(selection.call("debug_campaign_presentation_hidden")), "campaign presentation must remain hidden while choosing a country")
	var labels := campaign.get_node("CountryLabelLayer")
	if "intel(r) uhd graphics 600" in RenderingServer.get_video_adapter_name().to_lower():
		_require(not labels.is_processing(), "the unsupported D3D12 country-label renderer must stay disabled on Intel UHD 600")
		_require(map_render.call("debug_intermediate_viewport_size") == Vector2i(2816, 1024), "Intel UHD 600 must use memory-safe intermediate map buffers")
	# Keep the rendered destination alive long enough for deferred map and font
	# resources to finish, since that work is part of the real menu transition.
	for _frame in 120:
		await process_frame
	print("Main-menu single-player flow smoke passed. campaign=loaded selection=visible")
	quit(0)
