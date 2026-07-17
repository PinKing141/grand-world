class_name NavalHUD
extends Control

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")
const ConstructShipCommandScript = preload("res://scripts/simulation/commands/construct_ship_command.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")
const AssignAdmiralCommandScript = preload("res://scripts/simulation/commands/assign_admiral_command.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")
const CancelTransportOperationCommandScript = preload("res://scripts/simulation/commands/cancel_transport_operation_command.gd")

@export var simulation_controller: GrandWorldSimulationController
@export var province_selector: ProvinceSelector
@export var notification_hud: SimulationHUD

@onready var naval_toggle_button: Button = %NavalToggleButton
@onready var naval_panel: PanelContainer = %NavalPanel
@onready var close_naval_button: Button = %CloseNavalButton
@onready var fleet_summary_label: Label = %FleetSummaryLabel
@onready var fleet_option: OptionButton = %FleetOption
@onready var fleet_details_label: Label = %FleetDetailsLabel
@onready var move_fleet_button: Button = %MoveFleetButton
@onready var cancel_movement_button: Button = %CancelMovementButton
@onready var admiral_option: OptionButton = %AdmiralOption
@onready var assign_admiral_button: Button = %AssignAdmiralButton
@onready var port_construction_label: Label = %PortConstructionLabel
@onready var ship_option: OptionButton = %ShipOption
@onready var construct_ship_button: Button = %ConstructShipButton
@onready var construction_queue_label: Label = %ConstructionQueueLabel
@onready var cancel_naval_construction_button: Button = %CancelNavalConstructionButton
@onready var transport_label: Label = %TransportLabel
@onready var army_option: OptionButton = %ArmyOption
@onready var embark_button: Button = %EmbarkButton
@onready var cancel_transport_button: Button = %CancelTransportButton

var _selected_province_id := -1
var _selected_owner := ""


func _ready() -> void:
	naval_panel.hide()
	naval_toggle_button.pressed.connect(toggle_naval_panel)
	close_naval_button.pressed.connect(naval_panel.hide)
	fleet_option.item_selected.connect(func(_index: int) -> void: _refresh_fleet_details())
	move_fleet_button.pressed.connect(_move_selected_fleet)
	cancel_movement_button.pressed.connect(_cancel_selected_fleet_movement)
	admiral_option.item_selected.connect(func(_index: int) -> void: _refresh_admiral_validation())
	assign_admiral_button.pressed.connect(_assign_selected_admiral)
	ship_option.item_selected.connect(func(_index: int) -> void: _refresh_construction_validation())
	construct_ship_button.pressed.connect(_construct_selected_ship)
	cancel_naval_construction_button.pressed.connect(_cancel_selected_construction)
	army_option.item_selected.connect(func(_index: int) -> void: _refresh_embark_validation())
	embark_button.pressed.connect(_embark_selected_army)
	cancel_transport_button.pressed.connect(_cancel_selected_transport)
	province_selector.province_selected.connect(_on_province_selected)
	province_selector.selection_cleared.connect(func() -> void:
		_selected_province_id = -1
		_refresh_port_panel())
	_populate_ship_options()
	_connect_events()
	_refresh_all()


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	events.player_country_changed.connect(func(_old: String, _new: String) -> void: _refresh_all())
	events.world_reloaded.connect(func(_checksum: String) -> void: _refresh_all())
	events.naval_construction_started.connect(func(_id: String, _port: int, _def: String) -> void:
		_notify("Ship construction started.")
		_refresh_all())
	events.naval_construction_cancelled.connect(func(_id: String, _port: int, _refund: int) -> void:
		_notify("Ship construction cancelled.")
		_refresh_all())
	events.naval_construction_completed.connect(func(_id: String, _ship: String, _fleet: String, _port: int) -> void:
		_notify("Ship construction completed.")
		_refresh_all())
	events.fleet_created.connect(func(_id: String, _country: String, _port: int) -> void: _refresh_all())
	events.fleets_merged.connect(func(_target: String, _sources: Array) -> void: _refresh_all())
	events.fleet_ships_transferred.connect(func(_target: String, _count: int) -> void: _refresh_all())
	events.fleet_movement_ordered.connect(func(_id: String, _path: Array, _day: int) -> void: _refresh_all())
	events.fleet_moved.connect(func(_id: String, _from: int, _to: int) -> void: _refresh_all())
	events.fleet_movement_completed.connect(func(_id: String, _loc: int) -> void:
		_notify("A fleet completed its move.")
		_refresh_all())
	events.fleet_movement_blocked.connect(func(_id: String, _loc: int, reason: String) -> void:
		_notify("Fleet movement blocked: %s" % reason)
		_refresh_all())
	events.fleet_movement_cancelled.connect(func(_id: String) -> void: _refresh_all())
	events.fleet_supply_changed.connect(func(_id: String, supplied: bool, _reason: String) -> void:
		_notify("A fleet became %s." % ("supplied" if supplied else "unsupplied"))
		_refresh_all())
	events.fleet_attrition_applied.connect(func(_id: String, _hull: int, _crew: int) -> void: _refresh_all())
	events.fleet_repair_completed.connect(func(_fleet: String, _ship: String) -> void: _refresh_all())
	events.admiral_assigned.connect(func(_fleet: String, _character: String) -> void: _refresh_all())
	events.transport_operation_created.connect(func(_op: String, _army: String, _fleet: String, _dest: int) -> void:
		_notify("Embarkation started.")
		_refresh_all())
	events.transport_operation_cancelled.connect(func(_op: String, _army: String, _fleet: String) -> void:
		_notify("Transport operation cancelled.")
		_refresh_all())
	events.transport_operation_state_changed.connect(func(_op: String, _state: String) -> void: _refresh_all())
	events.transport_operation_completed.connect(func(_op: String, _army: String, _dest: int) -> void:
		_notify("An army disembarked.")
		_refresh_all())
	events.transport_operation_failed.connect(func(_op: String, _army: String, _loc: int, reason: String) -> void:
		_notify("Transport operation failed: %s" % reason)
		_refresh_all())
	events.transport_capacity_shortfall.connect(func(_op: String, _army: String, regiments_lost: int) -> void:
		_notify("A transported army lost %d regiments to a capacity shortfall." % regiments_lost)
		_refresh_all())
	events.transport_operation_rerouted.connect(func(_op: String, _dest: int) -> void:
		_notify("A transport operation was rerouted.")
		_refresh_all())
	events.transport_operation_army_lost.connect(func(_op: String, _army: String, reason: String) -> void:
		_notify("An army was lost at sea: %s" % reason)
		_refresh_all())


func _notify(message: String) -> void:
	if notification_hud != null:
		notification_hud._show_status(message)


func _player_country() -> String:
	return simulation_controller.world.player_country if simulation_controller.initialized else ""


func toggle_naval_panel() -> void:
	naval_panel.visible = not naval_panel.visible
	if naval_panel.visible:
		_refresh_all()


func open_naval_panel() -> void:
	naval_panel.show()
	_refresh_all()


func select_fleet(fleet_id: String) -> void:
	open_naval_panel()
	for index in fleet_option.item_count:
		if String(fleet_option.get_item_metadata(index)) == fleet_id:
			fleet_option.select(index)
			_refresh_fleet_details()
			break


func _refresh_all() -> void:
	var tag := _player_country()
	naval_toggle_button.visible = not tag.is_empty()
	if tag.is_empty():
		naval_panel.hide()
		return
	_refresh_fleet_options()
	_refresh_fleet_details()
	_refresh_port_panel()


func _country_fleets() -> Array[String]:
	return simulation_controller.world.country_fleets(_player_country())


func _refresh_fleet_options() -> void:
	var previous := _selected_fleet_id()
	fleet_option.clear()
	var fleet_ids := _country_fleets()
	var unsupplied := 0
	var damaged := 0
	for fleet_id in fleet_ids:
		var fleet := simulation_controller.world.get_fleet(fleet_id)
		if not bool(fleet.get("supplied", true)):
			unsupplied += 1
		var aggregate: Dictionary = fleet.get("aggregate", {})
		if int(aggregate.get("total_maximum_hull", 0)) > 0 and int(aggregate.get("total_hull", 0)) < int(aggregate.get("total_maximum_hull", 0)):
			damaged += 1
		fleet_option.add_item("%s (%d ships)" % [fleet_id, int(aggregate.get("ship_count", 0))])
		fleet_option.set_item_metadata(fleet_option.item_count - 1, fleet_id)
	fleet_summary_label.text = "Fleets %d · Unsupplied %d · Damaged %d" % [fleet_ids.size(), unsupplied, damaged]
	for index in fleet_option.item_count:
		if String(fleet_option.get_item_metadata(index)) == previous:
			fleet_option.select(index)
			break


func _selected_fleet_id() -> String:
	if fleet_option.item_count == 0 or fleet_option.selected < 0:
		return ""
	return String(fleet_option.get_item_metadata(fleet_option.selected))


func _refresh_fleet_details() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty():
		fleet_details_label.text = "No fleets."
		move_fleet_button.disabled = true
		cancel_movement_button.disabled = true
		assign_admiral_button.disabled = true
		return
	var fleet := simulation_controller.world.get_fleet(fleet_id)
	var aggregate: Dictionary = fleet.get("aggregate", {})
	var max_hull := int(aggregate.get("total_maximum_hull", 0))
	var hull_pct := 100 if max_hull <= 0 else int(aggregate.get("total_hull", 0)) * 100 / max_hull
	var admiral_id := String(fleet.get("admiral_id", ""))
	var supplied := bool(fleet.get("supplied", true))
	fleet_details_label.text = "Location %d · %s\nShips %d · Hull %d%% · Speed %d\nSupplied %s%s\nAdmiral %s" % [
		int(fleet.get("location_id", -1)), String(fleet.get("location_status", "")).capitalize(),
		int(aggregate.get("ship_count", 0)), hull_pct, int(aggregate.get("speed", 0)),
		"yes" if supplied else "no",
		"" if supplied else " (%s)" % String(fleet.get("supply_reason", "")),
		admiral_id if not admiral_id.is_empty() else "none",
	]
	cancel_movement_button.disabled = String(fleet.get("location_status", "")) != CampaignWorldStateScript.FLEET_LOCATION_MOVING
	_refresh_move_validation()
	_populate_admiral_options()
	_refresh_admiral_validation()
	_refresh_transport_panel()


func _refresh_move_validation() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or _selected_province_id < 0:
		move_fleet_button.disabled = true
		move_fleet_button.tooltip_text = ""
		return
	var failure := MoveFleetCommandScript.new(fleet_id, _selected_province_id, _player_country()).validate(simulation_controller.world)
	move_fleet_button.disabled = not failure.is_empty()
	move_fleet_button.text = "Move to selected province" if failure.is_empty() else "Move · blocked"
	move_fleet_button.tooltip_text = failure


## Eligible admirals: alive, employed by the player's country, not already
## commanding a different fleet or any army - mirrors AssignAdmiralCommand's
## own exclusivity checks so the list never offers a choice validate() would
## reject.
func _populate_admiral_options() -> void:
	admiral_option.clear()
	var tag := _player_country()
	var fleet_id := _selected_fleet_id()
	var current_admiral := String(simulation_controller.world.get_fleet(fleet_id).get("admiral_id", "")) if not fleet_id.is_empty() else ""
	var ids := simulation_controller.world.character_registry.keys()
	ids.sort()
	for raw_id in ids:
		var character_id := String(raw_id)
		var character: Dictionary = simulation_controller.world.character_registry[character_id]
		if not bool(character.get("alive", false)) or String(character.get("employer_country", "")) != tag:
			continue
		var existing_fleet := String(character.get("admiral_fleet_id", ""))
		if not existing_fleet.is_empty() and existing_fleet != fleet_id:
			continue
		if not String(character.get("commander_army_id", "")).is_empty():
			continue
		admiral_option.add_item(String(character.get("name", character_id)))
		admiral_option.set_item_metadata(admiral_option.item_count - 1, character_id)
		if character_id == current_admiral:
			admiral_option.select(admiral_option.item_count - 1)


func _refresh_admiral_validation() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or admiral_option.item_count == 0:
		assign_admiral_button.disabled = true
		return
	var character_id := String(admiral_option.get_item_metadata(admiral_option.selected))
	var failure := AssignAdmiralCommandScript.new(_player_country(), fleet_id, character_id).validate(simulation_controller.world)
	assign_admiral_button.disabled = not failure.is_empty()
	assign_admiral_button.tooltip_text = failure


func _on_province_selected(info: Dictionary) -> void:
	_selected_province_id = int(info.get("province_id", -1))
	_selected_owner = String(info.get("owner_tag", ""))
	_refresh_move_validation()
	_refresh_port_panel()
	_refresh_embark_validation()


## Active operations tracked here are keyed by fleet, mirroring
## CampaignWorldState.get_fleet()["transport_operation_ids"] - the same
## reverse index the backend already maintains, not a duplicate UI-side one.
func _active_operations_for_fleet(fleet_id: String) -> Array[String]:
	var found: Array[String] = []
	if fleet_id.is_empty():
		return found
	for raw_operation_id in (simulation_controller.world.get_fleet(fleet_id).get("transport_operation_ids", []) as Array):
		found.append(String(raw_operation_id))
	return found


func _refresh_transport_panel() -> void:
	var fleet_id := _selected_fleet_id()
	var operation_ids := _active_operations_for_fleet(fleet_id)
	if operation_ids.is_empty():
		transport_label.text = "No active transport for the selected fleet."
		cancel_transport_button.visible = false
	else:
		var lines: Array[String] = []
		var cancellable_id := ""
		for operation_id in operation_ids:
			var operation := simulation_controller.world.get_transport_operation(operation_id)
			var state := String(operation.get("state", ""))
			lines.append("%s: %s bound for province %d" % [
				String(operation.get("army_id", "")), state.capitalize(), int(operation.get("destination_province_id", -1)),
			])
			if state == CampaignWorldStateScript.TRANSPORT_STATE_EMBARKING:
				cancellable_id = operation_id
		transport_label.text = "\n".join(lines)
		cancel_transport_button.visible = not cancellable_id.is_empty()
		cancel_transport_button.set_meta("operation_id", cancellable_id)
	_populate_army_options()
	_refresh_embark_validation()


## Eligible armies: owned by the player, docked in the same province as the
## selected fleet, not already embarking/embarked - mirrors
## CreateTransportOperationCommand's own co-location and status checks so the
## list never offers a choice validate() would reject.
func _populate_army_options() -> void:
	army_option.clear()
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty():
		return
	var fleet := simulation_controller.world.get_fleet(fleet_id)
	var fleet_province_id := int(fleet.get("location_id", -1))
	var tag := _player_country()
	for army_id in simulation_controller.world.country_armies(tag):
		var army := simulation_controller.world.get_army(army_id)
		if int(army.get("current_province_id", -1)) != fleet_province_id:
			continue
		if String(army.get("status", "")) in [CampaignWorldStateScript.ARMY_STATUS_EMBARKING, CampaignWorldStateScript.ARMY_STATUS_EMBARKED]:
			continue
		army_option.add_item("%s (%d regiments)" % [army_id, int(army.get("regiment_count", 0))])
		army_option.set_item_metadata(army_option.item_count - 1, army_id)


func _refresh_embark_validation() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or army_option.item_count == 0 or _selected_province_id < 0:
		embark_button.disabled = true
		embark_button.tooltip_text = ""
		return
	var army_id := String(army_option.get_item_metadata(army_option.selected))
	var failure := CreateTransportOperationCommandScript.new(_player_country(), army_id, fleet_id, _selected_province_id).validate(simulation_controller.world)
	embark_button.disabled = not failure.is_empty()
	embark_button.text = "Embark to selected province" if failure.is_empty() else "Embark · blocked"
	embark_button.tooltip_text = failure


func _embark_selected_army() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or army_option.item_count == 0 or _selected_province_id < 0:
		return
	simulation_controller.create_transport_operation(_player_country(), String(army_option.get_item_metadata(army_option.selected)), fleet_id, _selected_province_id)


func _cancel_selected_transport() -> void:
	var operation_id := String(cancel_transport_button.get_meta("operation_id", ""))
	if not operation_id.is_empty():
		simulation_controller.cancel_transport_operation(_player_country(), operation_id)


func _refresh_port_panel() -> void:
	var tag := _player_country()
	var graph := MaritimeGraphScript.load_default()
	var is_owned_port := _selected_province_id >= 0 and _selected_owner == tag and graph.is_port_province(_selected_province_id)
	construct_ship_button.disabled = not is_owned_port
	if not is_owned_port:
		port_construction_label.text = "Select an owned port province to construct ships."
		construction_queue_label.text = "No active naval construction."
		cancel_naval_construction_button.visible = false
		return
	port_construction_label.text = "Port construction · province %d" % _selected_province_id
	_refresh_construction_validation()
	var construction_id := _construction_in_selected_port()
	cancel_naval_construction_button.visible = not construction_id.is_empty()
	if not construction_id.is_empty():
		var record: Dictionary = simulation_controller.world.naval_construction_registry[construction_id]
		construction_queue_label.text = "%s completes %s" % [
			String(record["definition_id"]).replace("_", " ").capitalize(),
			SimulationDateScript.format_day(int(record["completion_day"])),
		]
	else:
		construction_queue_label.text = "No active naval construction."


func _construction_in_selected_port() -> String:
	var ids := simulation_controller.world.naval_construction_registry.keys()
	ids.sort()
	for raw_id in ids:
		if int(simulation_controller.world.naval_construction_registry[raw_id].get("port_id", -1)) == _selected_province_id:
			return String(raw_id)
	return ""


func _populate_ship_options() -> void:
	ship_option.clear()
	var definitions := ShipDefinitionsScript.load_default()
	var ship_ids := definitions.ship_ids()
	ship_ids.sort()
	for raw_id in ship_ids:
		var id := String(raw_id)
		var definition: Dictionary = definitions.ship(id)
		ship_option.add_item(String(definition.get("name", id)))
		ship_option.set_item_metadata(ship_option.item_count - 1, id)


func _refresh_construction_validation() -> void:
	if _selected_province_id < 0 or ship_option.item_count == 0:
		construct_ship_button.disabled = true
		return
	var definition_id := String(ship_option.get_item_metadata(ship_option.selected))
	var failure := ConstructShipCommandScript.new(_player_country(), _selected_province_id, definition_id).validate(simulation_controller.world)
	construct_ship_button.disabled = not failure.is_empty()
	construct_ship_button.text = "Build selected" if failure.is_empty() else "Build · locked"
	construct_ship_button.tooltip_text = failure


func _construct_selected_ship() -> void:
	if ship_option.item_count > 0:
		simulation_controller.construct_ship(_player_country(), _selected_province_id, String(ship_option.get_item_metadata(ship_option.selected)))


func _cancel_selected_construction() -> void:
	var construction_id := _construction_in_selected_port()
	if not construction_id.is_empty():
		simulation_controller.cancel_ship_construction(_player_country(), construction_id)


func _move_selected_fleet() -> void:
	var fleet_id := _selected_fleet_id()
	if not fleet_id.is_empty() and _selected_province_id >= 0:
		simulation_controller.order_fleet_move(fleet_id, _selected_province_id, _player_country())


func _cancel_selected_fleet_movement() -> void:
	var fleet_id := _selected_fleet_id()
	if not fleet_id.is_empty():
		simulation_controller.cancel_fleet_movement(fleet_id, _player_country())


func _assign_selected_admiral() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or admiral_option.item_count == 0:
		return
	simulation_controller.assign_admiral(_player_country(), fleet_id, String(admiral_option.get_item_metadata(admiral_option.selected)))
