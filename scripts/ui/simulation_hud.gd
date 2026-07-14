class_name SimulationHUD
extends Control

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")
const SimulationDate = preload("res://scripts/simulation/simulation_date.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")

@export var simulation_controller: GrandWorldSimulationController
@export var province_selector: ProvinceSelector
@export var country_data: CountryData
@export var army_layer: ArmyLayer

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
@onready var select_army_button: Button = %SelectArmyButton
@onready var army_panel: PanelContainer = %ArmyPanel
@onready var army_title: Label = %ArmyTitle
@onready var army_status: Label = %ArmyStatus
@onready var army_route_info: Label = %ArmyRouteInfo
@onready var army_economy_info: Label = %ArmyEconomyInfo
@onready var army_move_button: Button = %ArmyMoveButton
@onready var army_cancel_button: Button = %ArmyCancelButton
@onready var army_close_button: Button = %ArmyCloseButton
@onready var army_disband_button: Button = %ArmyDisbandButton

var _speed_buttons: Array[Button] = []
var _selected_province_id := -1
var _selected_country := ""
var _debug_refresh_accumulator := 0.0
var _selected_army_id := ""
var _move_targeting := false


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
	province_selector.province_hovered.connect(_on_province_hovered_for_army)
	simulation_controller.save_completed.connect(_on_save_completed)
	simulation_controller.load_completed.connect(_on_load_completed)
	select_army_button.pressed.connect(_select_army_in_province)
	army_move_button.pressed.connect(_toggle_move_targeting)
	army_cancel_button.pressed.connect(_cancel_selected_army_movement)
	army_close_button.pressed.connect(_deselect_army)
	army_disband_button.pressed.connect(_disband_selected_army)
	_connect_event_bus()
	_refresh_all()
	selection_actions.hide()
	army_panel.hide()


func _process(delta: float) -> void:
	# A complete global checksum serializes every authoritative registry and is
	# intentionally expensive. The old one-second refresh paid that cost even
	# while this developer-only panel was hidden, causing periodic 600–800 ms
	# presentation stalls. Normal gameplay performs no checksum work here.
	if not debug_panel.visible or not simulation_controller.initialized:
		_debug_refresh_accumulator = 0.0
		return
	_debug_refresh_accumulator += delta
	if _debug_refresh_accumulator < 0.25:
		return
	_debug_refresh_accumulator = 0.0
	tick_label.text = "Tick  %.2f ms" % (simulation_controller.last_tick_cost_usec / 1000.0)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_SPACE:
		simulation_controller.toggle_pause()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_F10:
		debug_panel.visible = not debug_panel.visible
		if debug_panel.visible:
			_refresh_debug_checksum()
		get_viewport().set_input_as_handled()


func _refresh_debug_checksum() -> void:
	if not simulation_controller.initialized:
		checksum_label.text = "State  loading"
		return
	var checksum := simulation_controller.world_checksum()
	checksum_label.text = "State  %s" % checksum.left(10)


func _connect_event_bus() -> void:
	var events := simulation_controller.event_bus
	if events == null:
		return
	events.date_changed.connect(_on_date_changed)
	events.player_country_changed.connect(_on_player_country_changed)
	events.pause_changed.connect(_on_pause_changed)
	events.speed_changed.connect(_on_speed_changed)
	events.command_rejected.connect(_on_command_rejected)
	events.world_reloaded.connect(func(checksum: String) -> void:
		checksum_label.text = "State  %s" % checksum.left(10)
		_deselect_army()
		_refresh_all())
	events.army_movement_ordered.connect(func(army_id: String, _path: PackedInt32Array, arrival_day: int) -> void:
		if army_id == _selected_army_id:
			_show_status("Movement ordered · arrives %s" % SimulationDate.format_day(arrival_day))
		_refresh_army_panel())
	events.army_moved.connect(func(_army_id: String, _from: int, _to: int) -> void: _refresh_army_panel())
	events.army_movement_completed.connect(func(army_id: String, _province: int) -> void:
		if army_id == _selected_army_id:
			_show_status("Army arrived.")
		_refresh_army_panel())
	events.army_movement_blocked.connect(func(army_id: String, _province: int, reason: String) -> void:
		if army_id == _selected_army_id:
			_show_status(reason)
		_refresh_army_panel())
	events.army_movement_cancelled.connect(func(_army_id: String) -> void: _refresh_army_panel())
	events.army_disbanded.connect(func(army_id: String) -> void:
		if army_id == _selected_army_id:
			_show_status("Army disbanded; part of its manpower returned.")
			_deselect_army())


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
		var country_name: String = country_data.country_id_to_country_name.get(new_country, "Unknown country")
		player_label.text = country_name
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
	status_label.text = _replace_country_tags(message)
	status_panel.show()
	status_timer.start()


func _replace_country_tags(value: String) -> String:
	var result := ""
	var token := ""
	for index in value.length():
		var code := value.unicode_at(index)
		var is_ascii_alphanumeric := (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
		)
		if is_ascii_alphanumeric:
			token += value.substr(index, 1)
			continue
		result += String(country_data.country_id_to_country_name.get(token, token))
		token = ""
		result += value.substr(index, 1)
	result += String(country_data.country_id_to_country_name.get(token, token))
	return result


func _on_province_selected(info: Dictionary) -> void:
	var province_id := int(info.get("province_id", -1))
	if _move_targeting and not _selected_army_id.is_empty():
		_issue_move_order(province_id)
		return
	_selected_province_id = province_id
	_selected_country = String(info.get("owner_tag", "")) if info.get("is_playable", false) else ""
	_refresh_selection_actions()


func _on_selection_cleared() -> void:
	_selected_province_id = -1
	_selected_country = ""
	selection_actions.hide()
	if _move_targeting:
		_set_move_targeting(false)


# --- Army selection and movement orders -------------------------------------

func _army_issuing_country(army: Dictionary) -> String:
	# The observer may command any army during Phase 3 testing; a chosen
	# player country may only command its own.
	var player_country := simulation_controller.world.player_country
	var owner_tag := String(army.get("owner_country_id", ""))
	return owner_tag if player_country.is_empty() else player_country


func _select_army_in_province() -> void:
	if _selected_province_id < 0 or not simulation_controller.initialized:
		return
	var armies := simulation_controller.world.armies_in_province(_selected_province_id)
	if armies.is_empty():
		return
	_selected_army_id = armies[0]
	if army_layer != null:
		army_layer.set_selected_army(_selected_army_id)
	_refresh_army_panel()


func _deselect_army() -> void:
	_selected_army_id = ""
	_set_move_targeting(false)
	if army_layer != null:
		army_layer.set_selected_army("")
	army_panel.hide()


func _toggle_move_targeting() -> void:
	_set_move_targeting(not _move_targeting)


func _set_move_targeting(enabled: bool) -> void:
	_move_targeting = enabled
	army_move_button.text = "Click a destination…" if enabled else "Set destination"
	if not enabled and army_layer != null:
		army_layer.clear_preview_path()


func _issue_move_order(destination_province_id: int) -> void:
	_set_move_targeting(false)
	if army_layer != null:
		army_layer.clear_preview_path()
	var army := simulation_controller.world.get_army(_selected_army_id)
	if army.is_empty():
		return
	simulation_controller.order_army_move(
		_selected_army_id, destination_province_id, _army_issuing_country(army)
	)


func _cancel_selected_army_movement() -> void:
	var army := simulation_controller.world.get_army(_selected_army_id)
	if army.is_empty():
		return
	simulation_controller.cancel_army_movement(_selected_army_id, _army_issuing_country(army))


func _disband_selected_army() -> void:
	var army := simulation_controller.world.get_army(_selected_army_id)
	if army.is_empty():
		return
	simulation_controller.disband_army(_army_issuing_country(army), _selected_army_id)


func _on_province_hovered_for_army(info: Dictionary, _screen_position: Vector2) -> void:
	if not _move_targeting or _selected_army_id.is_empty() or army_layer == null:
		return
	var route := simulation_controller.preview_army_route(_selected_army_id, int(info.get("province_id", -1)))
	if bool(route.get("exists", false)):
		army_layer.set_preview_path(route["path"])
		var strait_note := "  ·  crosses a strait" if bool(route.get("uses_strait", false)) else ""
		army_route_info.text = "Arrives %s (%d days)%s" % [
			String(route.get("arrival_text", "")), int(route.get("total_cost_days", 0)), strait_note,
		]
	else:
		army_layer.clear_preview_path()
		army_route_info.text = _replace_country_tags(String(route.get("failure_reason", "")))


func _refresh_army_panel() -> void:
	if _selected_army_id.is_empty() or not simulation_controller.initialized:
		army_panel.hide()
		return
	var army := simulation_controller.world.get_army(_selected_army_id)
	if army.is_empty():
		_deselect_army()
		return
	var owner_tag := String(army.get("owner_country_id", ""))
	var owner_name: String = country_data.country_id_to_country_name.get(owner_tag, "Unknown country")
	army_title.text = "%s army" % owner_name
	var status := String(army.get("status", "idle"))
	army_economy_info.text = "%d regiment  ·  strength %d  ·  morale %d%%  ·  maintenance %s/month" % [
		int(army.get("regiment_count", 1)), int(army.get("strength", 1000)),
		int(army.get("morale_bp", 10000)) / 100,
		EconomySystemScript.format_money(int(army.get("base_monthly_maintenance", 500))),
	]
	var graph := ProvinceGraph.load_default()
	var current := int(army.get("current_province_id", -1))
	match status:
		"moving":
			var arrival := int(army.get("next_arrival_day", -1))
			var destination := int(army.get("destination_province_id", -1))
			army_status.text = "Moving from %s" % graph.province_name(current)
			army_route_info.text = "To %s  ·  next leg %s" % [
				graph.province_name(destination), SimulationDate.format_day(arrival),
			]
			army_cancel_button.visible = true
		"blocked":
			army_status.text = "Blocked in %s" % graph.province_name(current)
			army_route_info.text = "Movement was interrupted."
			army_cancel_button.visible = false
		"battle":
			army_status.text = "In battle at %s" % graph.province_name(current)
			army_route_info.text = "Combat resolves on deterministic daily rounds."
			army_cancel_button.visible = false
		"retreating":
			var destination := int(army.get("destination_province_id", -1))
			army_status.text = "Retreating from %s" % graph.province_name(current)
			army_route_info.text = "Falling back to %s." % graph.province_name(destination)
			army_cancel_button.visible = false
		"recovering":
			army_status.text = "Recovering in %s" % graph.province_name(current)
			army_route_info.text = "Orders unlock after morale recovery."
			army_cancel_button.visible = false
		_:
			army_status.text = "Idle in %s" % graph.province_name(current)
			army_route_info.text = "Ready for orders."
			army_cancel_button.visible = false
	var can_order := status in ["idle", "moving", "blocked"] and String(army.get("owner_country_id", "")) == _army_issuing_country(army)
	army_move_button.disabled = not can_order
	army_disband_button.disabled = status != "idle" or String(army.get("owner_country_id", "")) != _army_issuing_country(army)
	army_panel.show()


func _refresh_selection_actions() -> void:
	if _selected_province_id < 0:
		selection_actions.hide()
		return
	var player_country := simulation_controller.world.player_country if simulation_controller.initialized else ""
	var can_choose_country := not _selected_country.is_empty() and _selected_country != player_country
	play_as_button.visible = can_choose_country
	if can_choose_country:
		var country_name: String = country_data.country_id_to_country_name.get(_selected_country, "Unknown country")
		play_as_button.text = "Play as %s" % country_name
	transfer_button.visible = not player_country.is_empty() and _selected_country != player_country
	if transfer_button.visible:
		transfer_button.text = "Test transfer to %s" % country_data.country_id_to_country_name.get(player_country, "Unknown country")
	var armies := simulation_controller.world.armies_in_province(_selected_province_id) if simulation_controller.initialized else []
	select_army_button.visible = not armies.is_empty()
	if select_army_button.visible:
		select_army_button.text = "Select army" if armies.size() == 1 else "Select army (%d here)" % armies.size()
	selection_actions.visible = play_as_button.visible or transfer_button.visible or select_army_button.visible


func _choose_selected_country() -> void:
	if not _selected_country.is_empty():
		simulation_controller.choose_player_country(_selected_country)


func _transfer_selected_province() -> void:
	var player_country := simulation_controller.world.player_country
	if _selected_province_id >= 0 and not player_country.is_empty():
		simulation_controller.change_province_owner_for_testing(_selected_province_id, player_country)
