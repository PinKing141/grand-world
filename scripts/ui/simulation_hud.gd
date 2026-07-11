class_name SimulationHUD
extends Control

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")
const SimulationDate = preload("res://scripts/simulation/simulation_date.gd")

@export var simulation_controller: GrandWorldSimulationController
@export var province_selector: ProvinceSelector
@export var country_data: CountryData

@onready var player_label: Label = %PlayerLabel
@onready var date_label: Label = %DateLabel
@onready var pause_button: Button = %PauseButton
@onready var speed_1: Button = %Speed1
@onready var speed_2: Button = %Speed2
@onready var speed_3: Button = %Speed3
@onready var speed_4: Button = %Speed4
@onready var speed_5: Button = %Speed5
@onready var step_button: Button = %StepButton
@onready var month_button: Button = %MonthButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var status_label: Label = %StatusLabel
@onready var status_panel: PanelContainer = %StatusPanel
@onready var status_timer: Timer = %StatusTimer
@onready var play_as_button: Button = %PlayAsButton
@onready var transfer_button: Button = %TransferButton
@onready var selection_actions: PanelContainer = %SelectionActions
@onready var checksum_label: Label = %ChecksumLabel
@onready var tick_label: Label = %TickLabel
@onready var debug_panel: PanelContainer = %DebugPanel

var _speed_buttons: Array[Button] = []
var _selected_province_id := -1
var _selected_country := ""
var _debug_refresh_accumulator := 0.0


func _ready() -> void:
	_speed_buttons = [speed_1, speed_2, speed_3, speed_4, speed_5]
	pause_button.pressed.connect(func() -> void: simulation_controller.toggle_pause())
	for index in _speed_buttons.size():
		var speed := index + 1
		_speed_buttons[index].pressed.connect(func() -> void: simulation_controller.set_game_speed(speed))
	step_button.pressed.connect(simulation_controller.debug_step_one_day)
	month_button.pressed.connect(simulation_controller.debug_jump_to_next_month)
	save_button.pressed.connect(simulation_controller.quick_save)
	load_button.pressed.connect(simulation_controller.quick_load)
	play_as_button.pressed.connect(_choose_selected_country)
	transfer_button.pressed.connect(_transfer_selected_province)
	status_timer.timeout.connect(status_panel.hide)
	province_selector.province_selected.connect(_on_province_selected)
	province_selector.selection_cleared.connect(_on_selection_cleared)
	simulation_controller.save_completed.connect(_on_save_completed)
	simulation_controller.load_completed.connect(_on_load_completed)
	_connect_event_bus()
	_refresh_all()
	selection_actions.hide()


func _process(delta: float) -> void:
	_debug_refresh_accumulator += delta
	if _debug_refresh_accumulator < 1.0 or not simulation_controller.initialized:
		return
	_debug_refresh_accumulator = 0.0
	tick_label.text = "Tick  %.2f ms" % (simulation_controller.last_tick_cost_usec / 1000.0)
	var checksum := simulation_controller.world_checksum()
	checksum_label.text = "State  %s" % checksum.left(10)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_SPACE:
		simulation_controller.toggle_pause()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F10:
		debug_panel.visible = not debug_panel.visible
		get_viewport().set_input_as_handled()


func _connect_event_bus() -> void:
	var events := simulation_controller.event_bus
	if events == null:
		return
	events.date_changed.connect(_on_date_changed)
	events.player_country_changed.connect(_on_player_country_changed)
	events.pause_changed.connect(_on_pause_changed)
	events.speed_changed.connect(_on_speed_changed)
	events.command_rejected.connect(_on_command_rejected)
	events.world_reloaded.connect(func(_checksum: String) -> void: _refresh_all())


func _refresh_all() -> void:
	if not simulation_controller.initialized:
		date_label.text = "Loading campaign…"
		return
	var world := simulation_controller.world
	_on_date_changed(world.current_day, SimulationDate.day_to_date(world.current_day))
	_on_player_country_changed("", world.player_country)
	_on_pause_changed(world.paused)
	_on_speed_changed(world.game_speed)
	_refresh_selection_actions()


func _on_date_changed(day_count: int, _date: Dictionary) -> void:
	date_label.text = SimulationDate.format_day(day_count)


func _on_player_country_changed(_old_country: String, new_country: String) -> void:
	if new_country.is_empty():
		player_label.text = "Observer"
	else:
		var country_name: String = country_data.country_id_to_country_name.get(new_country, new_country)
		player_label.text = "%s  ·  %s" % [country_name, new_country]
	_refresh_selection_actions()


func _on_pause_changed(is_paused: bool) -> void:
	pause_button.text = "▶" if is_paused else "Ⅱ"
	pause_button.tooltip_text = "Resume campaign (Space)" if is_paused else "Pause campaign (Space)"
	_on_speed_changed(simulation_controller.world.game_speed)


func _on_speed_changed(speed: int) -> void:
	for index in _speed_buttons.size():
		_speed_buttons[index].disabled = index + 1 == speed and not simulation_controller.world.paused


func _on_command_rejected(_command_id: int, command_type: String, reason: String) -> void:
	_show_status("%s rejected: %s" % [command_type, reason])


func _on_save_completed(success: bool, message: String) -> void:
	_show_status(("✓ " if success else "⚠ ") + message)


func _on_load_completed(success: bool, message: String) -> void:
	_show_status(("✓ " if success else "⚠ ") + message)


func _show_status(message: String) -> void:
	status_label.text = message
	status_panel.show()
	status_timer.start()


func _on_province_selected(info: Dictionary) -> void:
	_selected_province_id = int(info.get("province_id", -1))
	_selected_country = String(info.get("owner_tag", "")) if info.get("is_playable", false) else ""
	_refresh_selection_actions()


func _on_selection_cleared() -> void:
	_selected_province_id = -1
	_selected_country = ""
	selection_actions.hide()


func _refresh_selection_actions() -> void:
	if _selected_province_id < 0:
		selection_actions.hide()
		return
	var player_country := simulation_controller.world.player_country if simulation_controller.initialized else ""
	var can_choose_country := not _selected_country.is_empty() and _selected_country != player_country
	play_as_button.visible = can_choose_country
	if can_choose_country:
		var country_name: String = country_data.country_id_to_country_name.get(_selected_country, _selected_country)
		play_as_button.text = "Play as %s" % country_name
	transfer_button.visible = not player_country.is_empty() and _selected_country != player_country
	if transfer_button.visible:
		transfer_button.text = "Test transfer to %s" % player_country
	selection_actions.visible = play_as_button.visible or transfer_button.visible


func _choose_selected_country() -> void:
	if not _selected_country.is_empty():
		simulation_controller.choose_player_country(_selected_country)


func _transfer_selected_province() -> void:
	var player_country := simulation_controller.world.player_country
	if _selected_province_id >= 0 and not player_country.is_empty():
		simulation_controller.change_province_owner_for_testing(_selected_province_id, player_country)
