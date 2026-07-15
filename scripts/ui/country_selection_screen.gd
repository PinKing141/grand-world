class_name CountrySelectionScreen
extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const CAMPAIGN_SCENE := "res://scenes/main.tscn"
const QUICK_SAVE_PATH := "user://saves/quick_save.json"
const FLAG_DIRECTORY := "res://assets/marker_art/source_flags"
const ProvinceGraphScript = preload("res://scripts/simulation/province_graph.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")

const RECOMMENDED_COUNTRIES := [
	{"tag": "CAS", "name": "Castile", "summary": "Unite Iberia, strengthen the crown, and prepare for Atlantic expansion."},
	{"tag": "ENG", "name": "England", "summary": "Defend the realm, resolve the French war, and dominate the seas."},
	{"tag": "FRA", "name": "France", "summary": "Reassert royal authority and draw the French appanages into a stronger realm."},
	{"tag": "HAB", "name": "Austria", "summary": "Use dynastic diplomacy and imperial leadership to shape Central Europe."},
	{"tag": "POL", "name": "Poland", "summary": "Balance powerful neighbours and the Lithuanian partnership in Eastern Europe."},
	{"tag": "POR", "name": "Portugal", "summary": "Build a maritime state and pursue trade beyond Europe."},
	{"tag": "MOS", "name": "Muscovy", "summary": "Consolidate the Russian principalities and withstand steppe pressure."},
	{"tag": "VEN", "name": "Venice", "summary": "Protect the republic's sea lanes, wealth, and Mediterranean possessions."},
]

const CAMPAIGN_PRESENTATION_NODES := [
	"MapHUD", "SimulationHUD", "EconomyHUD", "WarHUD", "AIDebugHUD",
	"CharacterHUD", "CountryDepthHUD", "ArmyLayer", "ConflictMarkerLayer",
	"CampaignInterfaceShell",
]

@export var simulation_controller: GrandWorldSimulationController
@export var province_selector: ProvinceSelector
@export var country_data: CountryData
@export var camera_controller: StrategyCameraController
@export var map_render: Node

@onready var left_panel: PanelContainer = %LeftPanel
@onready var right_panel: PanelContainer = %RightPanel
@onready var recommended_panel: PanelContainer = %RecommendedPanel
@onready var history_content: VBoxContainer = %HistoryContent
@onready var saved_content: VBoxContainer = %SavedContent
@onready var history_tab: Button = %HistoryTab
@onready var saved_tab: Button = %SavedTab
@onready var recommended_row: HBoxContainer = %RecommendedRow
@onready var synopsis_label: Label = %SynopsisLabel
@onready var country_name_label: Label = %CountryNameLabel
@onready var country_subtitle_label: Label = %CountrySubtitleLabel
@onready var shield_texture: TextureRect = %ShieldTexture
@onready var missing_shield_label: Label = %MissingShieldLabel
@onready var country_tint: ColorRect = %CountryTint
@onready var ruler_label: Label = %RulerLabel
@onready var realm_label: Label = %RealmLabel
@onready var identity_label: Label = %IdentityLabel
@onready var economy_label: Label = %EconomyLabel
@onready var technology_label: Label = %TechnologyLabel
@onready var difficulty_label: Label = %DifficultyLabel
@onready var play_button: Button = %PlayButton
@onready var selection_status: Label = %SelectionStatus
@onready var saved_summary: Label = %SavedSummary
@onready var load_saved_button: Button = %LoadSavedButton
@onready var options_panel: PanelContainer = %SelectionOptionsPanel

var _selected_country := ""
var _graph: ProvinceGraph
var _recommended_buttons: Dictionary = {}
var _country_history_paths: Dictionary = {}
var _country_history_profiles: Dictionary = {}


func _ready() -> void:
	hide()
	history_tab.pressed.connect(_show_history_tab)
	saved_tab.pressed.connect(_show_saved_tab)
	%BackButton.pressed.connect(_return_to_main_menu)
	%OptionsButton.pressed.connect(options_panel.show)
	%OptionsCloseButton.pressed.connect(options_panel.hide)
	%FullscreenToggle.toggled.connect(_set_fullscreen)
	%VolumeSlider.value_changed.connect(_set_master_volume)
	play_button.pressed.connect(_play_selected_country)
	load_saved_button.pressed.connect(_load_saved_campaign)
	province_selector.province_selected.connect(_on_province_selected)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_graph = ProvinceGraphScript.load_default()
	_index_country_history_paths()
	_build_recommended_countries()
	_configure_saved_campaign()
	_configure_options()
	var requested := bool(get_tree().root.get_meta("grand_world_country_selection", false))
	get_tree().root.set_meta("grand_world_country_selection", false)
	if requested and simulation_controller != null and simulation_controller.initialized and simulation_controller.world.player_country.is_empty():
		call_deferred("_begin_country_selection")


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
		return
	if options_panel.visible:
		options_panel.hide()
	else:
		_return_to_main_menu()


func _begin_country_selection() -> void:
	_set_campaign_presentation_visible(false)
	show()
	_show_history_tab()
	_select_country("CAS", true)
	_apply_responsive_layout()


func _build_recommended_countries() -> void:
	for child in recommended_row.get_children():
		child.queue_free()
	_recommended_buttons.clear()
	for definition in RECOMMENDED_COUNTRIES:
		var tag := String(definition["tag"])
		var button := Button.new()
		button.name = "%sRecommendation" % tag
		button.custom_minimum_size = Vector2(86.0, 58.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = String(definition["name"])
		button.tooltip_text = String(definition["summary"])
		button.toggle_mode = true
		button.add_theme_constant_override("icon_max_width", 34)
		button.expand_icon = true
		var flag_path := "%s/%s.png" % [FLAG_DIRECTORY, tag]
		if ResourceLoader.exists(flag_path):
			button.icon = load(flag_path) as Texture2D
		button.pressed.connect(_on_recommended_country_pressed.bind(tag))
		recommended_row.add_child(button)
		_recommended_buttons[tag] = button


func _on_recommended_country_pressed(tag: String) -> void:
	_select_country(tag, true)


func _on_province_selected(info: Dictionary) -> void:
	if not visible or not bool(info.get("is_playable", false)):
		return
	_select_country(String(info.get("owner_tag", "")), false)


func _select_country(tag: String, focus_map: bool) -> void:
	if not simulation_controller.initialized or not simulation_controller.world.has_country(tag):
		return
	var provinces := simulation_controller.world.get_country_provinces(tag)
	if provinces.is_empty():
		return
	_selected_country = tag
	var country_name := String(country_data.country_id_to_country_name.get(tag, "Unknown country"))
	var runtime: Dictionary = simulation_controller.world.country_runtime(tag)
	var history_profile := _country_history_profile(tag)
	var government_id := String(runtime.get("government_id", "feudal_monarchy"))
	var government_definition := simulation_controller.country_depth_definition("government", government_id)
	var government_name := _humanize(government_id)
	var government_key := String(government_definition.get("name_key", ""))
	if not government_key.is_empty():
		government_name = simulation_controller.country_depth_localize(government_key)
	elif not String(history_profile.get("government", "")).is_empty():
		government_name = _humanize(String(history_profile["government"]))
	var development := 0
	for raw_province_id in provinces:
		var province_state: Dictionary = simulation_controller.world.province_states.get(int(raw_province_id), {})
		development += int((province_state.get("economy", {}) as Dictionary).get("development", 0))
	var realm_rank := _realm_rank(provinces.size(), development)
	var ruler_id := String(runtime.get("ruler_character_id", ""))
	var ruler: Dictionary = simulation_controller.world.character_registry.get(ruler_id, {})
	var ruler_name := String(ruler.get("name", "Council and local estates"))
	var skills: Dictionary = ruler.get("skills", {})
	var ruler_skills := ""
	if not skills.is_empty():
		ruler_skills = "  ·  Stewardship %d  Diplomacy %d  Martial %d" % [
			int(skills.get("stewardship", 0)), int(skills.get("diplomacy", 0)), int(skills.get("martial", 0)),
		]
	var technology: Dictionary = runtime.get("technology", {})
	var ledger: Dictionary = runtime.get("ledger", {})
	var colour: Color = country_data.country_id_to_color.get(tag, Color(0.35, 0.35, 0.35))
	country_name_label.text = country_name
	country_subtitle_label.text = "%s  ·  %s" % [realm_rank, government_name]
	country_tint.color = colour
	ruler_label.text = "Ruler\n%s%s" % [ruler_name, ruler_skills]
	realm_label.text = "Realm\n%d provinces  ·  %d development" % [provinces.size(), development]
	var culture_id := String(runtime.get("primary_culture", "unknown"))
	var religion_id := String(runtime.get("state_religion", "unknown"))
	if culture_id in ["", "unknown"]:
		culture_id = String(history_profile.get("primary_culture", "unknown"))
	if religion_id in ["", "unknown"]:
		religion_id = String(history_profile.get("religion", "unknown"))
	identity_label.text = "People and faith\n%s culture  ·  %s" % [
		_humanize(culture_id), _humanize(religion_id),
	]
	economy_label.text = "Starting resources\nTreasury %.2f  ·  Manpower %d/%d  ·  Income %.2f" % [
		float(int(runtime.get("treasury", 0))) / 100.0,
		int(runtime.get("manpower", 0)), int(runtime.get("maximum_manpower", 0)),
		float(int(ledger.get("total_income", 0))) / 100.0,
	]
	technology_label.text = "Technology\nAdministrative %d  ·  Diplomatic %d  ·  Military %d" % [
		int(technology.get("administrative", 0)), int(technology.get("diplomatic", 0)), int(technology.get("military", 0)),
	]
	difficulty_label.text = "Starting difficulty  ·  %s" % _starting_difficulty(provinces.size(), development)
	play_button.text = "PLAY AS %s" % country_name.to_upper()
	play_button.disabled = false
	selection_status.text = "Selected %s. Review the realm, then press Play." % country_name
	_update_shield(tag, country_name)
	_update_recommended_state(tag)
	_update_synopsis(tag)
	if focus_map:
		_focus_country(runtime, provinces)


func _update_shield(tag: String, country_name: String) -> void:
	var flag_path := "%s/%s.png" % [FLAG_DIRECTORY, tag]
	var has_researched_shield := ResourceLoader.exists(flag_path)
	shield_texture.visible = has_researched_shield
	missing_shield_label.visible = not has_researched_shield
	missing_shield_label.text = "%s\nShield research pending" % country_name
	shield_texture.texture = load(flag_path) as Texture2D if has_researched_shield else null


func _update_recommended_state(tag: String) -> void:
	for raw_tag in _recommended_buttons:
		var button := _recommended_buttons[raw_tag] as Button
		button.button_pressed = String(raw_tag) == tag


func _update_synopsis(tag: String) -> void:
	for definition in RECOMMENDED_COUNTRIES:
		if String(definition["tag"]) == tag:
			synopsis_label.text = String(definition["summary"])
			return
	synopsis_label.text = "Every playable country uses the same deterministic 11 November 1444 world state. Select any coloured realm on the map."


func _focus_country(runtime: Dictionary, provinces: Array) -> void:
	var province_id := int(runtime.get("capital_province_id", provinces[0]))
	if not simulation_controller.world.has_province(province_id):
		province_id = int(provinces[0])
	var anchor := _graph.anchor(province_id)
	var world_position := Vector3(float(anchor.x) * 0.01 - 28.16, 0.0, float(anchor.y) * 0.01 - 10.24)
	camera_controller.focus_world_position(world_position)
	if map_render != null and map_render.has_method("_on_province_selected"):
		map_render.call("_on_province_selected", {
			"province_id": province_id,
			"province_name": _graph.province_name(province_id),
			"owner_tag": _selected_country,
			"owner_name": country_name_label.text,
			"is_playable": true,
		})


func _play_selected_country() -> void:
	if _selected_country.is_empty() or play_button.disabled:
		return
	play_button.disabled = true
	selection_status.text = "Preparing the %s campaign…" % country_name_label.text
	var command_id := simulation_controller.choose_player_country(_selected_country)
	if command_id < 0:
		play_button.disabled = false
		selection_status.text = "The country selection command could not be submitted."
		return
	simulation_controller.scheduler.process_commands()
	if simulation_controller.world.player_country == _selected_country:
		_finish_country_selection()


func _finish_country_selection() -> void:
	hide()
	_set_campaign_presentation_visible(true)
	if map_render != null and map_render.has_method("_on_selection_cleared"):
		map_render.call("_on_selection_cleared")


func _set_campaign_presentation_visible(should_show: bool) -> void:
	var scene_root := get_parent()
	for node_name in CAMPAIGN_PRESENTATION_NODES:
		var presentation := scene_root.get_node_or_null(node_name)
		if presentation != null:
			presentation.visible = should_show


func _show_history_tab() -> void:
	history_content.show()
	saved_content.hide()
	history_tab.button_pressed = true
	saved_tab.button_pressed = false


func _show_saved_tab() -> void:
	history_content.hide()
	saved_content.show()
	history_tab.button_pressed = false
	saved_tab.button_pressed = true
	_configure_saved_campaign()


func _configure_saved_campaign() -> void:
	var exists := FileAccess.file_exists(QUICK_SAVE_PATH)
	load_saved_button.disabled = not exists
	saved_summary.text = "No quick save exists yet. Start a country and use Save in the campaign." if not exists else "A quick save is available. Loading it will replace the historical-start selection."


func _index_country_history_paths() -> void:
	_country_history_paths.clear()
	var directory := DirAccess.open("res://assets/countries")
	if directory == null:
		return
	for filename in directory.get_files():
		if not filename.ends_with(".txt") or filename.length() < 7:
			continue
		var tag := filename.substr(0, 3).to_upper()
		if filename.begins_with("%s - " % tag):
			_country_history_paths[tag] = "res://assets/countries/%s" % filename


func _country_history_profile(tag: String) -> Dictionary:
	if _country_history_profiles.has(tag):
		return (_country_history_profiles[tag] as Dictionary).duplicate()
	var profile := {}
	var path := String(_country_history_paths.get(tag, ""))
	var file := FileAccess.open(path, FileAccess.READ) if not path.is_empty() else null
	if file != null:
		# The inherited research corpus contains a mixture of legacy encodings.
		# The profile keys are ASCII and live near the header, so read only that
		# bounded prefix without attempting to decode the whole historical file.
		var header := file.get_buffer(mini(file.get_length(), 4096)).get_string_from_ascii()
		for raw_line in header.split("\n"):
			var line := String(raw_line).strip_edges()
			if line.is_empty() or line.begins_with("#"):
				continue
			var first := line.unicode_at(0)
			if first >= 48 and first <= 57:
				break
			for field in ["government", "primary_culture", "religion"]:
				var prefix := "%s =" % field
				if line.begins_with(prefix):
					profile[field] = line.trim_prefix(prefix).strip_edges().trim_prefix("\"").trim_suffix("\"")
	_country_history_profiles[tag] = profile
	return profile.duplicate()


func _load_saved_campaign() -> void:
	if not FileAccess.file_exists(QUICK_SAVE_PATH):
		_configure_saved_campaign()
		return
	get_tree().root.set_meta("grand_world_continue_campaign", true)
	get_tree().root.set_meta("grand_world_country_selection", false)
	get_tree().change_scene_to_file(CAMPAIGN_SCENE)


func _return_to_main_menu() -> void:
	get_tree().root.set_meta("grand_world_country_selection", false)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _configure_options() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		%VolumeSlider.value = db_to_linear(AudioServer.get_bus_volume_db(master_bus)) * 100.0
	%FullscreenToggle.button_pressed = DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]


func _set_master_volume(value: float) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(value / 100.0, 0.0001)))


func _set_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 1250.0
	left_panel.offset_right = 276.0 if compact else 316.0
	right_panel.offset_left = -306.0 if compact else -346.0
	recommended_panel.offset_left = -380.0 if compact else -470.0
	recommended_panel.offset_right = 380.0 if compact else 470.0
	left_panel.visible = viewport_size.x >= 900.0


func _humanize(identifier: String) -> String:
	return identifier.replace("_", " ").capitalize()


func _realm_rank(province_count: int, development: int) -> String:
	if province_count >= 45 or development >= 450:
		return "Empire"
	if province_count >= 12 or development >= 120:
		return "Kingdom"
	return "Duchy or regional state"


func _starting_difficulty(province_count: int, development: int) -> String:
	if province_count <= 2 or development < 25:
		return "Very challenging"
	if province_count <= 7 or development < 75:
		return "Challenging"
	if province_count >= 30 or development >= 300:
		return "Recommended"
	return "Standard"


func debug_selected_country() -> String:
	return _selected_country


func debug_recommended_count() -> int:
	return _recommended_buttons.size()


func debug_campaign_presentation_hidden() -> bool:
	for node_name in CAMPAIGN_PRESENTATION_NODES:
		var presentation := get_parent().get_node_or_null(node_name)
		if presentation != null and presentation.visible:
			return false
	return true


func debug_trigger_selection() -> void:
	_begin_country_selection()
