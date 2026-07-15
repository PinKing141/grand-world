extends SceneTree

const CountrySelectionScript = preload("res://scripts/ui/country_selection_screen.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Country selection screen smoke failed: %s" % message)
		quit(1)


func _run() -> void:
	var capture_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
	root.set_meta("grand_world_country_selection", true)
	root.set_meta("grand_world_continue_campaign", false)
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "the campaign scene must include the country-selection interface")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in 4:
		await process_frame
	var selection = scene.get_node("CountrySelectionScreen")
	var simulation = scene.get_node("SimulationController")
	_require(selection.visible, "Single Player must open the country-selection overlay")
	_require(selection.debug_recommended_count() == 8, "the historical start needs eight researched recommended realms")
	_require(selection.debug_selected_country() == "CAS", "the historical start should open with Castile as the first recommendation")
	_require(selection.debug_campaign_presentation_hidden(), "campaign-only HUD and army markers must stay hidden before Play")
	_require((selection.get_node("RightPanel/Margin/Content/ShieldRow/CountryHeading/CountryNameLabel") as Label).text == "Castile", "country details must use the full display name")
	var recommended_row := selection.get_node("RecommendedPanel/Margin/Content/RecommendedRow")
	var england_button := recommended_row.get_node("ENGRecommendation") as Button
	_require(england_button != null and england_button.icon != null, "recommended England must use its researched historical shield")
	england_button.pressed.emit()
	await process_frame
	_require(selection.debug_selected_country() == "ENG", "recommended shields must select and focus their country")
	_require((selection.get_node("RightPanel/Margin/Content/ShieldRow/CountryHeading/CountryNameLabel") as Label).text == "England", "recommended selection must never expose a country tag as its name")
	var identity_text := (selection.get_node("RightPanel/Margin/Content/IdentityLabel") as Label).text
	_require("English" in identity_text and "Catholic" in identity_text and "Unknown" not in identity_text, "country-history fallback must replace unfinished runtime identity fields: %s" % identity_text)
	if not capture_path.is_empty():
		# The first Forward+ run may still be compiling the large political-map
		# shader and shaping the interface font atlas. Capture only after both
		# presentation batches have had enough real frames to settle.
		for _frame in 90:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		_require(capture != null and capture.save_png(capture_path) == OK, "the country-selection visual capture must save")
	selection.call("_play_selected_country")
	await process_frame
	_require(simulation.world.player_country == "ENG", "Play must commit the authoritative player-country command")
	_require(not selection.visible, "the selection overlay must close after Play")
	_require(scene.get_node("MapHUD").visible and scene.get_node("SimulationHUD").visible, "the normal campaign HUD must return after Play")
	print("Country selection screen smoke passed. recommended=8 selected=England hud=restored")
	quit(0)
