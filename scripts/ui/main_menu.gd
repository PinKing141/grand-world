class_name GrandWorldMainMenu
extends Control

const CAMPAIGN_SCENE := "res://scenes/main.tscn"
const QUICK_SAVE_PATH := "user://saves/quick_save.json"
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")
const CountryRegistryScript = preload("res://scripts/simulation/country_registry.gd")

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var main_dock: PanelContainer = %MainDock
@onready var continue_button: Button = %ContinueButton
@onready var continue_detail: Label = %ContinueDetail
@onready var single_player_button: Button = %SinglePlayerButton
@onready var multiplayer_button: Button = %MultiplayerButton
@onready var tutorial_button: Button = %TutorialButton
@onready var credits_button: Button = %CreditsButton
@onready var options_button: Button = %OptionsButton
@onready var exit_button: Button = %ExitButton
@onready var status_label: Label = %StatusLabel
@onready var version_label: Label = %VersionLabel
@onready var options_panel: PanelContainer = %OptionsPanel
@onready var credits_panel: PanelContainer = %CreditsPanel
@onready var master_volume: HSlider = %MasterVolume
@onready var fullscreen_toggle: CheckButton = %FullscreenToggle

var _transitioning := false


func _ready() -> void:
	continue_button.pressed.connect(_continue_campaign)
	single_player_button.pressed.connect(_start_single_player)
	multiplayer_button.pressed.connect(_show_unavailable.bind("Multiplayer is planned for a later production phase."))
	tutorial_button.pressed.connect(_show_unavailable.bind("The guided tutorial campaign is not available yet."))
	credits_button.pressed.connect(_show_credits)
	options_button.pressed.connect(_show_options)
	exit_button.pressed.connect(get_tree().quit)
	%OptionsCloseButton.pressed.connect(options_panel.hide)
	%CreditsCloseButton.pressed.connect(credits_panel.hide)
	master_volume.value_changed.connect(_set_master_volume)
	fullscreen_toggle.toggled.connect(_set_fullscreen)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_configure_version()
	_configure_continue()
	_configure_options()
	_apply_responsive_layout()
	single_player_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
		return
	if options_panel.visible:
		options_panel.hide()
	elif credits_panel.visible:
		credits_panel.hide()


func _start_single_player() -> void:
	_launch_campaign(false)


func _continue_campaign() -> void:
	if not FileAccess.file_exists(QUICK_SAVE_PATH):
		_show_unavailable("No valid campaign save is available.")
		return
	_launch_campaign(true)


func _launch_campaign(continue_existing: bool) -> void:
	if _transitioning:
		return
	_transitioning = true
	_set_menu_enabled(false)
	status_label.text = "Loading saved campaign…" if continue_existing else "Opening the 1444 country selection…"
	# The root viewport survives a scene change. This one-shot flag lets the
	# authoritative simulation decide whether it should consume the quick save
	# after every campaign node has entered the tree.
	get_tree().root.set_meta("grand_world_continue_campaign", continue_existing)
	get_tree().root.set_meta("grand_world_country_selection", not continue_existing)
	var error := get_tree().change_scene_to_file(CAMPAIGN_SCENE)
	if error != OK:
		_transitioning = false
		_set_menu_enabled(true)
		status_label.text = "Could not open the campaign: %s" % error_string(error)


func _set_menu_enabled(enabled: bool) -> void:
	for button in [continue_button, single_player_button, multiplayer_button, tutorial_button, credits_button, options_button, exit_button]:
		(button as Button).disabled = not enabled
	if enabled:
		_configure_continue()


func _configure_continue() -> void:
	continue_button.disabled = not FileAccess.file_exists(QUICK_SAVE_PATH)
	continue_button.text = "CONTINUE CAMPAIGN" if not continue_button.disabled else "NO SAVED CAMPAIGN"
	continue_detail.text = "Begin or select a country in the 11 November 1444 scenario"
	if continue_button.disabled:
		return
	var file := FileAccess.open(QUICK_SAVE_PATH, FileAccess.READ)
	if file == null:
		continue_button.disabled = true
		continue_detail.text = "The saved campaign could not be opened"
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		continue_button.disabled = true
		continue_detail.text = "The saved campaign is not valid JSON"
		return
	var save_data := parsed as Dictionary
	var country_tag := String(save_data.get("player_country", ""))
	var country_name := "Observer"
	if not country_tag.is_empty():
		var registry = CountryRegistryScript.new().load_registry()
		country_name = registry.display_name(country_tag) if registry.is_valid() else country_tag
	continue_detail.text = "%s  ·  %s" % [country_name, SimulationDateScript.format_day(int(save_data.get("current_day", 0)))]


func _configure_version() -> void:
	version_label.text = "GRAND WORLD V2\nVersion %s" % String(ProjectSettings.get_setting("application/config/version", "Development"))


func _configure_options() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		master_volume.value = db_to_linear(AudioServer.get_bus_volume_db(master_bus)) * 100.0
	fullscreen_toggle.button_pressed = DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]


func _set_master_volume(value: float) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(value / 100.0, 0.0001)))


func _set_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)


func _show_options() -> void:
	credits_panel.hide()
	options_panel.show()
	%OptionsCloseButton.grab_focus()


func _show_credits() -> void:
	options_panel.hide()
	credits_panel.show()
	%CreditsCloseButton.grab_focus()


func _show_unavailable(message: String) -> void:
	status_label.text = message


func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var dock_width := clampf(viewport_size.x - 32.0, 440.0, 720.0)
	var dock_height := clampf(viewport_size.y * 0.28, 196.0, 210.0)
	main_dock.offset_left = -dock_width * 0.5
	main_dock.offset_right = dock_width * 0.5
	main_dock.offset_top = -dock_height - 16.0
	main_dock.offset_bottom = -16.0
	var compact := viewport_size.y < 620.0 or viewport_size.x < 780.0
	title_label.add_theme_font_size_override("font_size", 38 if compact else 58)
	subtitle_label.add_theme_font_size_override("font_size", 14 if compact else 18)
	subtitle_label.visible = viewport_size.y >= 500.0
	%TitleBlock.offset_right = minf(viewport_size.x - 28.0, 600.0)
	%TitleBlock.offset_bottom = 115.0 if compact else 170.0


func debug_has_reference_branding() -> bool:
	return _node_contains_reference_branding(self)


func _node_contains_reference_branding(node: Node) -> bool:
	var searchable := node.name.to_lower()
	if node is Label or node is Button:
		searchable += " " + String(node.get("text")).to_lower()
	if "paradox" in searchable or "dlc" in searchable or "europa universalis" in searchable:
		return true
	for child in node.get_children():
		if _node_contains_reference_branding(child):
			return true
	return false


func debug_primary_actions() -> Array[String]:
	return [continue_button.text, single_player_button.text, multiplayer_button.text, tutorial_button.text, credits_button.text, options_button.text, exit_button.text]


func debug_target_dock_size(viewport_size: Vector2) -> Vector2:
	return Vector2(
		clampf(viewport_size.x - 32.0, 440.0, 720.0),
		clampf(viewport_size.y * 0.28, 196.0, 210.0)
	)
