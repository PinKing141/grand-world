class_name CampaignInterfaceShell
extends Control

## One authoritative campaign HUD shell. Existing Phase 4–8 windows remain the
## feature owners; this node gives them a consistent navigation hierarchy and
## replaces their overlapping top bars, map-mode strip, hints and debug chrome.

const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const ProvinceGraphScript = preload("res://scripts/simulation/province_graph.gd")
const StrategyMinimapScript = preload("res://scripts/ui/strategy_minimap.gd")
const UI_FONT := preload("res://assets/fonts/LibreBaskerville-Variable.ttf")
const FLAG_DIRECTORY := "res://assets/marker_art/source_flags"

const INK := Color("0b1119")
const PANEL := Color(0.035, 0.055, 0.078, 0.96)
const PANEL_SOFT := Color(0.055, 0.078, 0.104, 0.94)
const GOLD := Color("d3aa5f")
const GOLD_BRIGHT := Color("f0d58c")
const TEXT := Color("e8e3d6")
const MUTED := Color("9aabbb")
const GOOD := Color("7fd393")
const BAD := Color("e98576")

@export var simulation_controller: GrandWorldSimulationController
@export var province_selector: ProvinceSelector
@export var country_data: CountryData
@export var camera_controller: StrategyCameraController
@export var map_hud: MapHUD
@export var economy_hud: EconomyHUD
@export var simulation_hud: SimulationHUD
@export var war_hud: Node
@export var ai_debug_hud: Node
@export var country_depth_hud: Node
@export var character_hud: Node
@export var army_layer: ArmyLayer
@export var naval_hud: Node
@export var country_selection_screen: Control

var top_left_panel: PanelContainer
var clock_panel: PanelContainer
var outliner_panel: PanelContainer
var navigation_panel: PanelContainer
var shield_button: Button
var country_name_label: Label
var treasury_label: Label
var balance_label: Label
var manpower_label: Label
var stability_label: Label
var technology_label: Label
var force_label: Label
var alert_row: HBoxContainer
var date_label: Label
var pause_button: Button
var outliner_content: VBoxContainer
var outliner_toggle: Button
var minimap: StrategyMinimap
var _refresh_accumulator := 0.0
var _search_open := false
var _last_alert_signature := ""
var _last_player_tag := ""


func _ready() -> void:
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ui_theme := Theme.new()
	ui_theme.default_font = UI_FONT
	ui_theme.default_font_size = 13
	theme = ui_theme
	_build_interface()
	_connect_events()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_refresh(true)


func _process(delta: float) -> void:
	_sync_visibility()
	if not visible:
		return
	_enforce_single_shell()
	var current_tag := simulation_controller.world.player_country
	if current_tag != _last_player_tag:
		_refresh(true)
	_refresh_accumulator += delta
	if _refresh_accumulator >= 0.4:
		_refresh_accumulator = 0.0
		_refresh(false)


func _build_interface() -> void:
	top_left_panel = _panel("TopLeftCountryBar", PANEL)
	top_left_panel.set_offsets_preset(Control.PRESET_TOP_LEFT)
	top_left_panel.offset_left = 8.0
	top_left_panel.offset_top = 8.0
	top_left_panel.offset_right = 748.0
	top_left_panel.offset_bottom = 151.0
	add_child(top_left_panel)

	var top_margin := _margin(10, 8, 10, 8)
	top_left_panel.add_child(top_margin)
	var country_row := HBoxContainer.new()
	country_row.add_theme_constant_override("separation", 10)
	top_margin.add_child(country_row)

	shield_button = _button("")
	shield_button.name = "CountryShieldButton"
	shield_button.custom_minimum_size = Vector2(88, 118)
	shield_button.expand_icon = true
	shield_button.tooltip_text = "Open the court and dynasty window"
	shield_button.pressed.connect(_open_characters)
	country_row.add_child(shield_button)

	var country_content := VBoxContainer.new()
	country_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	country_content.add_theme_constant_override("separation", 5)
	country_row.add_child(country_content)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	country_content.add_child(title_row)
	country_name_label = _label("Observer", 20, GOLD_BRIGHT)
	country_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(country_name_label)
	var era := _label("GRAND CAMPAIGN · 1444–1700", 10, MUTED)
	era.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(era)

	var resources := HBoxContainer.new()
	resources.name = "ResourceRow"
	resources.add_theme_constant_override("separation", 14)
	country_content.add_child(resources)
	treasury_label = _resource_label(resources, "Treasury", "¤ 0.00")
	balance_label = _resource_label(resources, "Balance", "+0.00/mo")
	manpower_label = _resource_label(resources, "Manpower", "0 / 0")
	stability_label = _resource_label(resources, "Stability", "+0")
	technology_label = _resource_label(resources, "Technology", "0 / 0 / 0")
	force_label = _resource_label(resources, "Armies", "0 · 0")

	alert_row = HBoxContainer.new()
	alert_row.name = "AlertRow"
	alert_row.custom_minimum_size.y = 28
	alert_row.add_theme_constant_override("separation", 5)
	country_content.add_child(alert_row)

	var tabs := HBoxContainer.new()
	tabs.name = "CountryTabs"
	tabs.add_theme_constant_override("separation", 4)
	country_content.add_child(tabs)
	_add_tab(tabs, "Government", _open_government, "Government, reforms, stability and decisions")
	_add_tab(tabs, "Economy", _open_economy, "Treasury, income, expenses, loans and maintenance")
	_add_tab(tabs, "Military", _open_military, "Armies and military orders")
	_add_tab(tabs, "Diplomacy", _open_diplomacy, "Relations, subjects, claims and warfare")
	_add_tab(tabs, "Religion", _open_religion, "Religion, culture and internal policy")
	_add_tab(tabs, "Court", _open_characters, "Ruler, heir, dynasty and court")

	clock_panel = _panel("ClockBar", PANEL)
	clock_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock_panel.offset_left = -486.0
	clock_panel.offset_top = 8.0
	clock_panel.offset_right = -8.0
	clock_panel.offset_bottom = 62.0
	add_child(clock_panel)
	var clock_margin := _margin(8, 6, 8, 6)
	clock_panel.add_child(clock_margin)
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation", 4)
	clock_margin.add_child(clock_row)
	date_label = _label("11 November 1444", 14, TEXT)
	date_label.custom_minimum_size.x = 154
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_row.add_child(date_label)
	pause_button = _button("▶")
	pause_button.custom_minimum_size.x = 38
	pause_button.pressed.connect(func() -> void: simulation_controller.toggle_pause())
	clock_row.add_child(pause_button)
	for speed in range(1, 6):
		var speed_button := _button(str(speed))
		speed_button.name = "Speed%d" % speed
		speed_button.custom_minimum_size.x = 30
		speed_button.tooltip_text = "Set game speed to %d" % speed
		speed_button.pressed.connect(func() -> void: simulation_controller.set_game_speed(speed))
		clock_row.add_child(speed_button)
	var save_button := _button("Save")
	save_button.pressed.connect(func() -> void: simulation_controller.quick_save())
	clock_row.add_child(save_button)
	var load_button := _button("Load")
	load_button.pressed.connect(func() -> void: simulation_controller.quick_load())
	clock_row.add_child(load_button)

	outliner_panel = _panel("Outliner", PANEL)
	outliner_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	outliner_panel.offset_left = -294.0
	outliner_panel.offset_top = 72.0
	outliner_panel.offset_right = -8.0
	outliner_panel.offset_bottom = -230.0
	add_child(outliner_panel)
	var outliner_margin := _margin(10, 8, 10, 8)
	outliner_panel.add_child(outliner_margin)
	var outliner_stack := VBoxContainer.new()
	outliner_stack.add_theme_constant_override("separation", 5)
	outliner_margin.add_child(outliner_stack)
	var outliner_header := HBoxContainer.new()
	outliner_stack.add_child(outliner_header)
	var outliner_title := _label("OUTLINER", 14, GOLD_BRIGHT)
	outliner_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outliner_header.add_child(outliner_title)
	var plans_button := _button("Plans")
	plans_button.tooltip_text = "Open campaign objectives and AI review"
	plans_button.pressed.connect(_open_campaign_plans)
	outliner_header.add_child(plans_button)
	outliner_toggle = _button("−")
	outliner_toggle.custom_minimum_size = Vector2(28, 26)
	outliner_toggle.tooltip_text = "Collapse the outliner"
	outliner_toggle.pressed.connect(_toggle_outliner)
	outliner_header.add_child(outliner_toggle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outliner_stack.add_child(scroll)
	outliner_content = VBoxContainer.new()
	outliner_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outliner_content.add_theme_constant_override("separation", 4)
	scroll.add_child(outliner_content)

	navigation_panel = _panel("MapNavigation", PANEL)
	navigation_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	navigation_panel.offset_left = -326.0
	navigation_panel.offset_top = -218.0
	navigation_panel.offset_right = -8.0
	navigation_panel.offset_bottom = -8.0
	add_child(navigation_panel)
	var nav_margin := _margin(8, 8, 8, 8)
	navigation_panel.add_child(nav_margin)
	var nav_stack := VBoxContainer.new()
	nav_stack.add_theme_constant_override("separation", 5)
	nav_margin.add_child(nav_stack)
	minimap = StrategyMinimapScript.new()
	minimap.name = "StrategyMinimap"
	minimap.camera_controller = camera_controller
	minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_stack.add_child(minimap)
	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 4)
	nav_stack.add_child(mode_row)
	_add_mode_button(mode_row, "Political", 0, "Political map mode (1)")
	_add_mode_button(mode_row, "Terrain", 1, "Terrain map mode (2)")
	_add_mode_button(mode_row, "Provinces", 2, "Province ID map mode (3)")
	var search_button := _button("Search")
	search_button.tooltip_text = "Search countries and provinces (/)"
	search_button.pressed.connect(_toggle_search)
	mode_row.add_child(search_button)


func _connect_events() -> void:
	if simulation_controller == null or simulation_controller.event_bus == null:
		return
	var events := simulation_controller.event_bus
	events.player_country_changed.connect(func(_old: String, _new: String) -> void: _refresh(true))
	events.date_changed.connect(func(_day: int, _date: Dictionary) -> void: _refresh(false))
	events.pause_changed.connect(func(_paused: bool) -> void: _refresh_clock())
	events.speed_changed.connect(func(_speed: int) -> void: _refresh_clock())
	events.world_reloaded.connect(func(_checksum: String) -> void: _refresh(true))


func _sync_visibility() -> void:
	var active := simulation_controller != null and simulation_controller.initialized and not simulation_controller.world.player_country.is_empty()
	if country_selection_screen != null and country_selection_screen.visible:
		active = false
	visible = active


func _enforce_single_shell() -> void:
	if economy_hud != null and economy_hud.resource_bar != null:
		economy_hud.resource_bar.hide()
	if simulation_hud != null:
		var old_top := simulation_hud.get_node_or_null("TopBar") as Control
		if old_top != null:
			old_top.hide()
	if map_hud != null:
		if map_hud.map_mode_bar != null:
			map_hud.map_mode_bar.hide()
		var hint_bar := map_hud.get_node_or_null("HintBar") as Control
		if hint_bar != null:
			hint_bar.hide()
		if map_hud.search_box != null and not _search_open:
			map_hud.search_box.hide()
	if ai_debug_hud != null and ai_debug_hud.get("campaign_button") != null:
		(ai_debug_hud.get("campaign_button") as Control).hide()


func _refresh(force_rebuild: bool) -> void:
	_sync_visibility()
	if not visible:
		return
	var tag := simulation_controller.world.player_country
	_last_player_tag = tag
	var runtime := simulation_controller.country_economy(tag)
	var ledger: Dictionary = runtime.get("ledger", {})
	var technology: Dictionary = runtime.get("technology", {})
	var armies := simulation_controller.world.country_armies(tag)
	var total_strength := 0
	for army_id in armies:
		total_strength += int((simulation_controller.world.army_registry[army_id] as Dictionary).get("strength", 0))
	country_name_label.text = _country_name(tag)
	treasury_label.text = "¤ %s" % EconomySystemScript.format_money(int(runtime.get("treasury", 0)))
	var balance := int(ledger.get("balance", 0))
	balance_label.text = "%s%s/mo" % ["+" if balance >= 0 else "", EconomySystemScript.format_money(balance)]
	balance_label.modulate = GOOD if balance >= 0 else BAD
	manpower_label.text = "%d / %d" % [int(runtime.get("manpower", 0)), int(runtime.get("maximum_manpower", 0))]
	stability_label.text = "%+d" % int(runtime.get("stability", 0))
	stability_label.modulate = GOOD if int(runtime.get("stability", 0)) >= 0 else BAD
	technology_label.text = "%d / %d / %d" % [int(technology.get("administrative", 0)), int(technology.get("diplomatic", 0)), int(technology.get("military", 0))]
	force_label.text = "%d armies · %d" % [armies.size(), total_strength]
	_refresh_shield(tag)
	_refresh_clock()
	_refresh_alerts(tag, runtime)
	_refresh_outliner(tag, force_rebuild)
	_style_and_place_legacy_panels()


func _refresh_clock() -> void:
	if simulation_controller == null or not simulation_controller.initialized:
		return
	var world := simulation_controller.world
	date_label.text = SimulationDateScript.format_day(world.current_day)
	pause_button.text = "▶" if world.paused else "Ⅱ"
	pause_button.tooltip_text = "Resume campaign (Space)" if world.paused else "Pause campaign (Space)"
	for speed in range(1, 6):
		var speed_button := clock_panel.get_node_or_null("MarginContainer/HBoxContainer/Speed%d" % speed) as Button
		if speed_button != null:
			speed_button.disabled = not world.paused and world.game_speed == speed


func _refresh_shield(tag: String) -> void:
	var path := "%s/%s.png" % [FLAG_DIRECTORY, tag]
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	shield_button.icon = texture
	shield_button.text = "" if texture != null else "Crest\npending"
	shield_button.disabled = false
	shield_button.tooltip_text = "Open %s's court" % _country_name(tag) if texture != null else "%s has no approved historical crest yet. Click to open the court." % _country_name(tag)


func _refresh_alerts(tag: String, runtime: Dictionary) -> void:
	var alert_specs: Array[Dictionary] = []
	var wars := _player_wars(tag)
	if not wars.is_empty():
		alert_specs.append({"text": "At war (%d)" % wars.size(), "tip": "Open diplomacy and warfare", "action": _open_diplomacy})
	var balance := int((runtime.get("ledger", {}) as Dictionary).get("balance", 0))
	if balance < 0:
		alert_specs.append({"text": "Deficit", "tip": "Monthly expenses exceed income", "action": _open_economy})
	if int(runtime.get("debt", 0)) > 0:
		alert_specs.append({"text": "Debt", "tip": "The country has outstanding loans", "action": _open_economy})
	var max_manpower := maxi(int(runtime.get("maximum_manpower", 0)), 1)
	if int(runtime.get("manpower", 0)) < max_manpower / 5:
		alert_specs.append({"text": "Low manpower", "tip": "Manpower is below 20 percent", "action": _open_military})
	if int(runtime.get("stability", 0)) < 0:
		alert_specs.append({"text": "Unstable realm", "tip": "National stability is negative", "action": _open_government})
	var snapshot := simulation_controller.country_depth_snapshot(tag)
	if not (snapshot.get("pending_event", {}) as Dictionary).is_empty():
		alert_specs.append({"text": "Decision required", "tip": "A country event awaits a response", "action": _open_government})
	if not (snapshot.get("rebel_factions", []) as Array).is_empty():
		alert_specs.append({"text": "Rebel activity", "tip": "Internal factions are organizing", "action": _open_religion})
	var unsupplied_fleets := 0
	for fleet_id in simulation_controller.world.country_fleets(tag):
		if not bool((simulation_controller.world.fleet_registry[fleet_id] as Dictionary).get("supplied", true)):
			unsupplied_fleets += 1
	if unsupplied_fleets > 0:
		alert_specs.append({"text": "Unsupplied fleets (%d)" % unsupplied_fleets, "tip": "Fleets out of supply range are taking attrition", "action": _open_naval})
	var transport_count := 0
	for raw_operation_id in simulation_controller.world.transport_operation_registry:
		if String((simulation_controller.world.transport_operation_registry[raw_operation_id] as Dictionary).get("country_tag", "")) == tag:
			transport_count += 1
	if transport_count > 0:
		alert_specs.append({"text": "Transport operations (%d)" % transport_count, "tip": "Armies are embarking, sailing, or disembarking", "action": _open_naval})
	if alert_specs.is_empty():
		alert_specs.append({"text": "No urgent alerts", "tip": "The realm has no immediate warnings", "action": Callable()})
	var signature := "|".join(alert_specs.map(func(spec: Dictionary) -> String: return String(spec["text"])))
	if signature == _last_alert_signature:
		return
	_last_alert_signature = signature
	_clear_children(alert_row)
	for spec in alert_specs:
		var alert := _button(String(spec["text"]))
		alert.add_theme_color_override("font_color", BAD if String(spec["text"]) != "No urgent alerts" else MUTED)
		alert.tooltip_text = String(spec["tip"])
		var action: Callable = spec["action"]
		if action.is_valid():
			alert.pressed.connect(action)
		else:
			alert.disabled = true
		alert_row.add_child(alert)


func _refresh_outliner(tag: String, _force_rebuild: bool) -> void:
	if not outliner_content.visible:
		return
	_clear_children(outliner_content)
	var graph := ProvinceGraphScript.load_default()
	_add_outliner_heading("ARMIES")
	var army_ids := simulation_controller.world.country_armies(tag)
	if army_ids.is_empty():
		_add_outliner_empty("No standing armies")
	else:
		for army_id in army_ids.slice(0, 12):
			var army: Dictionary = simulation_controller.world.army_registry[army_id]
			var province_id := int(army.get("current_province_id", -1))
			var province_name := graph.province_name(province_id)
			var army_button := _outliner_button("%s · %d · %s" % [province_name if not province_name.is_empty() else "Province %d" % province_id, int(army.get("strength", 0)), String(army.get("status", "idle")).capitalize()])
			army_button.tooltip_text = "Select and focus this army"
			army_button.pressed.connect(func() -> void: _focus_army(String(army_id)))
			outliner_content.add_child(army_button)
		if army_ids.size() > 12:
			_add_outliner_empty("+%d additional armies" % (army_ids.size() - 12))

	_add_outliner_heading("FLEETS")
	var fleet_ids := simulation_controller.world.country_fleets(tag)
	if fleet_ids.is_empty():
		_add_outliner_empty("No fleets")
	else:
		for fleet_id in fleet_ids.slice(0, 12):
			var fleet: Dictionary = simulation_controller.world.fleet_registry[fleet_id]
			var aggregate: Dictionary = fleet.get("aggregate", {})
			var status_text := String(fleet.get("location_status", "")).capitalize()
			if not bool(fleet.get("supplied", true)):
				status_text += " · unsupplied"
			var max_hull := int(aggregate.get("total_maximum_hull", 0))
			if max_hull > 0 and int(aggregate.get("total_hull", 0)) < max_hull:
				status_text += " · damaged"
			var carried := (fleet.get("transport_operation_ids", []) as Array).size()
			if carried > 0:
				status_text += " · carrying %d" % carried
			var fleet_button := _outliner_button("%s · %d ships · %s" % [fleet_id, int(aggregate.get("ship_count", 0)), status_text])
			fleet_button.tooltip_text = "Select and focus this fleet"
			fleet_button.pressed.connect(func() -> void: _focus_fleet(String(fleet_id)))
			outliner_content.add_child(fleet_button)
		if fleet_ids.size() > 12:
			_add_outliner_empty("+%d additional fleets" % (fleet_ids.size() - 12))

	_add_outliner_heading("WARS")
	var wars := _player_wars(tag)
	if wars.is_empty():
		_add_outliner_empty("The realm is at peace")
	else:
		for war in wars:
			var attacker := _country_name(String(war.get("attacker_leader", "")))
			var defender := _country_name(String(war.get("defender_leader", "")))
			var war_button := _outliner_button("%s–%s · score %+d" % [attacker, defender, int(war.get("total_war_score", 0))])
			war_button.pressed.connect(_open_diplomacy)
			outliner_content.add_child(war_button)

	_add_outliner_heading("CONSTRUCTION & RECRUITMENT")
	var queue_count := 0
	for record in simulation_controller.world.construction_registry.values():
		if String(record.get("country_tag", "")) != tag:
			continue
		queue_count += 1
		_add_queue_entry(String(record.get("building_id", "Building")).replace("_", " ").capitalize(), int(record.get("province_id", -1)), int(record.get("completion_day", 0)), _open_economy)
	for record in simulation_controller.world.recruitment_registry.values():
		if String(record.get("country_tag", "")) != tag:
			continue
		queue_count += 1
		_add_queue_entry(String(record.get("unit_id", "Unit")).replace("_", " ").capitalize(), int(record.get("province_id", -1)), int(record.get("completion_day", 0)), _open_military)
	if queue_count == 0:
		_add_outliner_empty("No active queues")

	_add_outliner_heading("SUBJECTS")
	var subject_count := 0
	for record in simulation_controller.world.subject_registry.values():
		if String(record.get("overlord", "")) != tag or String(record.get("status", "active")) != "active":
			continue
		subject_count += 1
		var subject_button := _outliner_button("%s · %s · liberty %.0f%%" % [_country_name(String(record.get("subject", ""))), String(record.get("type", "subject")).capitalize(), int(record.get("liberty_desire_bp", 0)) / 100.0])
		subject_button.pressed.connect(_open_diplomacy)
		outliner_content.add_child(subject_button)
	if subject_count == 0:
		_add_outliner_empty("No subject states")


func _style_and_place_legacy_panels() -> void:
	if map_hud == null:
		return
	var province_panel := map_hud.province_panel
	if province_panel != null:
		_ensure_province_scroll(province_panel)
		province_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		province_panel.offset_left = 8.0
		province_panel.offset_top = 162.0
		province_panel.offset_right = 358.0
		province_panel.offset_bottom = 646.0
		province_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, GOLD, 2))
	var panels: Array[Control] = []
	if economy_hud != null:
		panels.append_array([economy_hud.economy_panel, economy_hud.province_economy_panel])
	if simulation_hud != null:
		panels.append(simulation_hud.army_panel)
	for path in ["DiplomacyPanel", "AIPanel", "CharacterPanel", "CountryStatePanel"]:
		for owner in [war_hud, ai_debug_hud, character_hud, country_depth_hud]:
			if owner == null:
				continue
			var panel := owner.get_node_or_null(path) as Control
			if panel != null:
				panels.append(panel)
	for panel in panels:
		if panel != null:
			panel.add_theme_stylebox_override("panel", _panel_style(PANEL, GOLD, 2))


func _ensure_province_scroll(province_panel: Control) -> void:
	var margin := province_panel.get_node_or_null("Margin") as MarginContainer
	if margin == null or margin.get_node_or_null("CampaignScroll") != null:
		return
	var content := margin.get_node_or_null("Content") as Control
	if content == null:
		return
	margin.remove_child(content)
	var scroll := ScrollContainer.new()
	scroll.name = "CampaignScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	scroll.add_child(content)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _apply_responsive_layout() -> void:
	if top_left_panel == null:
		return
	var width := get_viewport_rect().size.x
	top_left_panel.offset_right = 670.0 if width < 1300.0 else 748.0
	clock_panel.offset_left = -474.0 if width < 1300.0 else -486.0
	if width < 1050.0:
		outliner_panel.hide()
		navigation_panel.offset_left = -286.0
	else:
		outliner_panel.show()
		navigation_panel.offset_left = -326.0


func _toggle_outliner() -> void:
	outliner_content.visible = not outliner_content.visible
	outliner_toggle.text = "−" if outliner_content.visible else "+"
	outliner_toggle.tooltip_text = "Collapse the outliner" if outliner_content.visible else "Expand the outliner"
	if outliner_content.visible:
		outliner_panel.anchor_bottom = 1.0
		outliner_panel.offset_bottom = -230.0
		_refresh_outliner(simulation_controller.world.player_country, true)
	else:
		outliner_panel.anchor_bottom = 0.0
		outliner_panel.offset_bottom = 114.0


func _toggle_search() -> void:
	if map_hud == null or map_hud.search_box == null:
		return
	_search_open = not _search_open
	map_hud.search_box.visible = _search_open
	if _search_open:
		map_hud.search_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		map_hud.search_box.offset_left = -610.0
		map_hud.search_box.offset_top = -208.0
		map_hud.search_box.offset_right = -336.0
		map_hud.search_box.offset_bottom = -18.0
		map_hud.search_field.grab_focus()
	else:
		map_hud.search_field.release_focus()


func _focus_army(army_id: String) -> void:
	var army: Dictionary = simulation_controller.world.army_registry.get(army_id, {})
	if army.is_empty():
		return
	if army_layer != null:
		army_layer.set_selected_army(army_id)
	var anchor := ProvinceGraphScript.load_default().anchor(int(army.get("current_province_id", -1)))
	if anchor.x >= 0 and camera_controller != null:
		camera_controller.focus_world_position(Vector3(anchor.x * 0.01 - 28.16, 0.0, anchor.y * 0.01 - 10.24))


func _focus_fleet(fleet_id: String) -> void:
	var fleet: Dictionary = simulation_controller.world.fleet_registry.get(fleet_id, {})
	if fleet.is_empty():
		return
	if naval_hud != null and naval_hud.has_method("select_fleet"):
		naval_hud.call("select_fleet", fleet_id)
	var anchor := ProvinceGraphScript.load_default().anchor(int(fleet.get("location_id", -1)))
	if anchor.x >= 0 and camera_controller != null:
		camera_controller.focus_world_position(Vector3(anchor.x * 0.01 - 28.16, 0.0, anchor.y * 0.01 - 10.24))


func _player_wars(tag: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_war in simulation_controller.world.war_registry.values():
		var war: Dictionary = raw_war
		var attackers: Array = war.get("attackers", [])
		var defenders: Array = war.get("defenders", [])
		if tag in attackers or tag in defenders or tag == String(war.get("attacker_leader", "")) or tag == String(war.get("defender_leader", "")):
			result.append(war)
	return result


func _add_queue_entry(title: String, province_id: int, completion_day: int, action: Callable) -> void:
	var province_name := ProvinceGraphScript.load_default().province_name(province_id)
	var entry := _outliner_button("%s · %s · %s" % [title, province_name if not province_name.is_empty() else "Province %d" % province_id, SimulationDateScript.format_day(completion_day)])
	entry.pressed.connect(action)
	outliner_content.add_child(entry)


func _add_outliner_heading(text_value: String) -> void:
	var heading := _label(text_value, 10, GOLD)
	heading.add_theme_constant_override("outline_size", 2)
	outliner_content.add_child(heading)


func _add_outliner_empty(text_value: String) -> void:
	var empty := _label("  %s" % text_value, 11, MUTED)
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outliner_content.add_child(empty)


func _outliner_button(text_value: String) -> Button:
	var button := _button(text_value)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size.y = 28
	return button


func _add_mode_button(parent: Control, title: String, mode: int, tooltip: String) -> void:
	var button := _button(title)
	button.name = "%sMapMode" % title
	button.tooltip_text = tooltip
	button.pressed.connect(func() -> void: map_hud.set_map_mode(mode))
	parent.add_child(button)


func _add_tab(parent: Control, title: String, action: Callable, tooltip: String) -> void:
	var button := _button(title)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	parent.add_child(button)


func _open_government() -> void:
	if country_depth_hud != null and country_depth_hud.has_method("open_country_state"):
		country_depth_hud.call("open_country_state", 0)


func _open_economy() -> void:
	if economy_hud != null:
		economy_hud.open_economy_panel()


func _open_military() -> void:
	if simulation_hud != null:
		simulation_hud.open_military_panel()


func _open_naval() -> void:
	if naval_hud != null and naval_hud.has_method("open_naval_panel"):
		naval_hud.call("open_naval_panel")


func _open_diplomacy() -> void:
	if war_hud != null and war_hud.has_method("open_diplomacy_panel"):
		war_hud.call("open_diplomacy_panel")


func _open_religion() -> void:
	if country_depth_hud != null and country_depth_hud.has_method("open_country_state"):
		country_depth_hud.call("open_country_state", 1)


func _open_characters() -> void:
	if character_hud != null and character_hud.has_method("open_character_panel"):
		character_hud.call("open_character_panel")


func _open_campaign_plans() -> void:
	if ai_debug_hud == null:
		return
	var panel := ai_debug_hud.get("panel") as Control
	if panel != null:
		panel.visible = not panel.visible
		if panel.visible and ai_debug_hud.has_method("_refresh_all"):
			ai_debug_hud.call("_refresh_all")


func _country_name(tag: String) -> String:
	if tag.is_empty():
		return "Unknown country"
	return String(country_data.country_id_to_country_name.get(tag, "Unknown country"))


func _resource_label(parent: Control, tooltip: String, initial_text: String) -> Label:
	var label := _label(initial_text, 12, TEXT)
	label.tooltip_text = tooltip
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _panel(node_name: String, background: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style(background, GOLD, 2))
	return panel


func _panel_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 5
	return style


func _button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", GOLD_BRIGHT)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", _panel_style(PANEL_SOFT, Color(0.27, 0.24, 0.18, 1), 1))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.10, 0.13, 0.16, 0.98), GOLD, 1))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.13, 0.10, 0.055, 0.98), GOLD_BRIGHT, 1))
	button.add_theme_stylebox_override("disabled", _panel_style(INK, Color(0.16, 0.17, 0.18, 1), 1))
	return button


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()


func debug_country_name() -> String:
	return country_name_label.text if country_name_label != null else ""


func debug_minimap_world(local_position: Vector2) -> Vector3:
	return minimap.world_from_local(local_position) if minimap != null else Vector3.ZERO


func debug_outliner_entry_count() -> int:
	return outliner_content.get_child_count() if outliner_content != null else 0
