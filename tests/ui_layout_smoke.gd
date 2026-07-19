extends SceneTree

const SimulationHUDScript = preload("res://scripts/ui/simulation_hud.gd")
const WarHUDScript = preload("res://scripts/ui/war_hud.gd")
const AIDebugHUDScript = preload("res://scripts/ui/ai_debug_hud.gd")
const CharacterHUDScript = preload("res://scripts/ui/character_hud.gd")
const CountryDepthHUDScript = preload("res://scripts/ui/country_depth_hud.gd")
const NavalHUDScript = preload("res://scripts/ui/naval_hud.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("UI layout smoke test failed: %s" % message)
		quit(1)


func _disjoint(first: Control, second: Control, label: String) -> void:
	if not first.is_visible_in_tree() or not second.is_visible_in_tree():
		return
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
	var province_content := scene.get_node("MapHUD/ProvincePanel").find_child("CampaignScroll", true, false) as Control
	if province_content == null:
		province_content = scene.get_node("MapHUD/ProvincePanel").find_child("Content", true, false) as Control
	var tooltip := scene.get_node("MapHUD/ProvinceTooltip") as Control
	var resource_bar := scene.get_node("EconomyHUD/ResourceBar") as Control
	var economy_panel := scene.get_node("EconomyHUD/EconomyPanel") as Control
	var province_economy := scene.get_node("EconomyHUD/ProvinceEconomyPanel") as Control
	var diplomacy_panel := scene.get_node("WarHUD/DiplomacyPanel") as Control
	var ai_panel := scene.get_node("AIDebugHUD/AIPanel") as Control
	var character_panel := scene.get_node("CharacterHUD/CharacterPanel") as Control
	var country_depth_panel := scene.get_node("CountryDepthHUD/CountryStatePanel") as Control
	var naval_panel := scene.get_node("NavalHUD/NavalPanel") as Control
	_require(resource_bar.get_global_rect().position.x <= 10.0 and resource_bar.get_global_rect().position.y <= 10.0, "country HUD must remain anchored at the top-left at %s: %s" % [viewport_size, resource_bar.get_global_rect()])
	_require(top_bar.get_global_rect().end.x >= root.get_visible_rect().size.x - 10.0 and top_bar.get_global_rect().position.y <= 10.0, "compact campaign clock must remain anchored at the top-right at %s: %s" % [viewport_size, top_bar.get_global_rect()])
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
	if ai_panel.visible:
		var ai_canvas := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
		_require(ai_canvas.encloses(ai_panel.get_global_rect()), "AI inspector escapes canvas at %s: %s / %s" % [viewport_size, ai_panel.get_global_rect(), ai_canvas])
	if character_panel.visible:
		var character_canvas := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
		_require(character_canvas.encloses(character_panel.get_global_rect()), "character window escapes canvas at %s: %s / %s" % [viewport_size, character_panel.get_global_rect(), character_canvas])
	if country_depth_panel.visible:
		var depth_canvas := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
		_require(depth_canvas.encloses(country_depth_panel.get_global_rect()), "country-depth window escapes canvas at %s: %s / %s" % [viewport_size, country_depth_panel.get_global_rect(), depth_canvas])
	if naval_panel.visible:
		# FL6.1: the naval panel must stay fully on-screen and never overlap
		# the always-on-top campaign bar, map-mode switcher, or search box at
		# any of the roadmap's required resolutions.
		var naval_canvas := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
		_require(naval_canvas.encloses(naval_panel.get_global_rect()), "naval panel escapes canvas at %s: %s / %s" % [viewport_size, naval_panel.get_global_rect(), naval_canvas])
		_disjoint(naval_panel, top_bar, "naval panel and campaign bar at %s" % viewport_size)
		_disjoint(naval_panel, map_modes, "naval panel and map modes at %s" % viewport_size)
		_disjoint(naval_panel, search, "naval panel and search at %s" % viewport_size)


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
	var ai_hud := scene.get_node("AIDebugHUD") as AIDebugHUDScript
	var character_hud := scene.get_node("CharacterHUD") as CharacterHUDScript
	var country_depth_hud := scene.get_node("CountryDepthHUD") as CountryDepthHUDScript
	var naval_hud := scene.get_node("NavalHUD") as NavalHUDScript
	var info := {
		"province_id": 1,
		"province_name": "Stockholm",
		"owner_tag": "SWE",
		"owner_name": "Sweden",
		"is_playable": true,
	}
	simulation_hud._on_province_selected(info)
	map_hud._on_province_selected(info)
	_require(map_hud.capital_value.text == "Stockholm", "province capital must come from the generated runtime history profile")
	_require(map_hud.culture_value.text == "Swedish", "province culture must come from the generated runtime history profile")
	_require(map_hud.religion_value.text == "Catholic", "province religion must come from the generated runtime history profile")
	_require(map_hud.trade_goods_value.text == "Grain", "province trade goods must come from the generated runtime history profile")
	_require(simulation_hud.selection_actions.visible, "selecting a playable province must show country-selection actions")
	_require(simulation_hud.play_as_button.visible, "selecting a playable province must show the Play as button")
	_require(simulation_hud.play_as_button.text == "Play as Sweden", "Play as button must name the selected country")
	map_hud._on_province_hovered(info, Vector2(30.0, 74.0))
	map_hud._process(0.0)
	simulation_hud._show_status("Layout test notification")
	simulation.choose_player_country("SWE")
	simulation.scheduler.process_commands()
	_require(economy_hud.resource_bar.visible, "choosing a country must reveal the top-left country HUD")
	_require(economy_hud.government_button.text == "Gov" and economy_hud.economy_button.text == "Eco", "country HUD must expose the government and economy navigation slots")
	_require(economy_hud.military_button.text == "Mil" and economy_hud.diplomacy_button.text == "Dip" and economy_hud.religion_button.text == "Rel", "country HUD must expose military, diplomacy, and religion navigation slots")
	_require(not war_hud.diplomacy_button.visible and not character_hud.court_button.visible and not country_depth_hud.open_button.visible, "legacy floating system buttons must stay hidden after HUD consolidation")
	economy_hud.shield_button.pressed.emit()
	await process_frame
	_require(character_hud.panel.visible, "the country shield must preserve access to Court & Dynasty")
	economy_hud._on_province_selected(info)
	economy_hud.economy_panel.show()
	war_hud.diplomacy_panel.show()
	ai_hud.panel.show()
	ai_hud._refresh_all()
	character_hud.panel.show()
	character_hud._refresh_all()
	country_depth_hud.panel.show()
	country_depth_hud._refresh_all()
	economy_hud._refresh_all()
	naval_hud.open_naval_panel()
	_require(naval_hud.naval_panel.visible, "FL6.1 fixture assumption: the naval panel must open for the layout checks")
	await _check_layout(scene, Vector2i(1700, 960))
	await _check_layout(scene, Vector2i(1152, 648))
	# FL6.1's own named required resolutions.
	await _check_layout(scene, Vector2i(1366, 768))
	await _check_layout(scene, Vector2i(1920, 1080))
	print("UI layout smoke test passed at 1700x960, 1152x648, 1366x768, and 1920x1080.")
	quit(0)
