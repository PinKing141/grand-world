extends SceneTree

const SimulationHUDScript = preload("res://scripts/ui/simulation_hud.gd")
const WarHUDScript = preload("res://scripts/ui/war_hud.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("UI layout smoke test failed: %s" % message)
		quit(1)


func _disjoint(first: Control, second: Control, label: String) -> void:
	_require(not first.get_global_rect().intersects(second.get_global_rect()), "%s overlap: %s / %s" % [
		label,
		first.get_global_rect(),
		second.get_global_rect(),
	])


func _check_layout(scene: Node, viewport_size: Vector2i) -> void:
	root.size = viewport_size
	await process_frame
	await process_frame
	var top_bar := scene.get_node("SimulationHUD/TopBar") as Control
	var status_panel := scene.get_node("SimulationHUD/StatusPanel") as Control
	var selection_actions := scene.get_node("SimulationHUD/SelectionActions") as Control
	var debug_panel := scene.get_node("SimulationHUD/DebugPanel") as Control
	var map_modes := scene.get_node("MapHUD/MapModeBar") as Control
	var search := scene.get_node("MapHUD/SearchBox") as Control
	var hint_bar := scene.get_node("MapHUD/HintBar") as Control
	var province_panel := scene.get_node("MapHUD/ProvincePanel") as Control
	var province_content := scene.get_node("MapHUD/ProvincePanel/Margin/Content") as Control
	var tooltip := scene.get_node("MapHUD/ProvinceTooltip") as Control
	var resource_bar := scene.get_node("EconomyHUD/ResourceBar") as Control
	var economy_panel := scene.get_node("EconomyHUD/EconomyPanel") as Control
	var province_economy := scene.get_node("EconomyHUD/ProvinceEconomyPanel") as Control
	var diplomacy_panel := scene.get_node("WarHUD/DiplomacyPanel") as Control
	_disjoint(top_bar, map_modes, "campaign bar and map modes at %s" % viewport_size)
	_disjoint(top_bar, search, "campaign bar and search at %s" % viewport_size)
	_disjoint(map_modes, search, "map modes and search at %s" % viewport_size)
	_disjoint(debug_panel, hint_bar, "debug metrics and help bar at %s" % viewport_size)
	if selection_actions.visible:
		_disjoint(selection_actions, hint_bar, "selection actions and help bar at %s" % viewport_size)
		_disjoint(selection_actions, debug_panel, "selection actions and debug metrics at %s" % viewport_size)
	if status_panel.visible:
		_disjoint(status_panel, selection_actions, "notification and selection actions at %s" % viewport_size)
	if province_panel.visible:
		_disjoint(province_panel, search, "province panel and search at %s" % viewport_size)
		_disjoint(province_panel, resource_bar, "province panel and economy resources at %s" % viewport_size)
		if province_economy.visible:
			_disjoint(province_panel, province_economy, "province panel and province economy at %s" % viewport_size)
		_require(province_panel.get_global_rect().encloses(province_content.get_global_rect()), "province content escapes its panel at %s: %s / %s" % [
			viewport_size,
			province_panel.get_global_rect(),
			province_content.get_global_rect(),
		])
	if tooltip.visible:
		_disjoint(tooltip, top_bar, "province tooltip and campaign bar at %s" % viewport_size)
		_disjoint(tooltip, map_modes, "province tooltip and map modes at %s" % viewport_size)
		_disjoint(tooltip, search, "province tooltip and search at %s" % viewport_size)
	if resource_bar.visible:
		_disjoint(resource_bar, top_bar, "economy resources and campaign bar at %s" % viewport_size)
		_disjoint(resource_bar, map_modes, "economy resources and map modes at %s" % viewport_size)
		_disjoint(resource_bar, search, "economy resources and search at %s" % viewport_size)
	if province_economy.visible:
		_disjoint(province_economy, map_modes, "province economy and map modes at %s" % viewport_size)
		_disjoint(province_economy, search, "province economy and search at %s" % viewport_size)
	if economy_panel.visible:
		# The stretch canvas keeps the 1920x1080 design size regardless of the
		# window size, so panels must be measured against the canvas rect.
		var canvas_rect := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
		_require(canvas_rect.encloses(economy_panel.get_global_rect()), "economy window escapes canvas at %s" % viewport_size)
	if diplomacy_panel.visible:
		var diplomacy_canvas := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
		_require(diplomacy_canvas.encloses(diplomacy_panel.get_global_rect()), "diplomacy window escapes canvas at %s" % viewport_size)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var simulation_hud := scene.get_node("SimulationHUD") as SimulationHUDScript
	var map_hud := scene.get_node("MapHUD") as MapHUD
	var economy_hud := scene.get_node("EconomyHUD") as EconomyHUD
	var simulation := scene.get_node("SimulationController") as GrandWorldSimulationController
	var war_hud := scene.get_node("WarHUD") as WarHUDScript
	var info := {
		"province_id": 1,
		"province_name": "Stockholm",
		"owner_tag": "SWE",
		"owner_name": "Sweden",
		"is_playable": true,
	}
	simulation_hud._on_province_selected(info)
	map_hud._on_province_selected(info)
	_require(simulation_hud.selection_actions.visible, "selecting a playable province must show country-selection actions")
	_require(simulation_hud.play_as_button.visible, "selecting a playable province must show the Play as button")
	_require(simulation_hud.play_as_button.text == "Play as Sweden", "Play as button must name the selected country")
	map_hud._on_province_hovered(info, Vector2(30.0, 74.0))
	map_hud._process(0.0)
	simulation_hud._show_status("Layout test notification")
	simulation.choose_player_country("SWE")
	simulation.scheduler.process_commands()
	economy_hud._on_province_selected(info)
	economy_hud.economy_panel.show()
	war_hud.diplomacy_panel.show()
	economy_hud._refresh_all()
	await _check_layout(scene, Vector2i(1700, 960))
	await _check_layout(scene, Vector2i(1152, 648))
	print("UI layout smoke test passed at 1700x960 and 1152x648.")
	quit(0)
