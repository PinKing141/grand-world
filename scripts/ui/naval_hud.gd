class_name NavalHUD
extends Control

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalDefinitionsScript = preload("res://scripts/simulation/naval_definitions.gd")
const ProvinceGraphScript = preload("res://scripts/simulation/province_graph.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")
const NavalTradeProtectionScript = preload("res://scripts/simulation/naval_trade_protection.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const FleetLogisticsSystemScript = preload("res://scripts/simulation/fleet_logistics_system.gd")
const ConstructShipCommandScript = preload("res://scripts/simulation/commands/construct_ship_command.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")
const AssignAdmiralCommandScript = preload("res://scripts/simulation/commands/assign_admiral_command.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")
const CancelTransportOperationCommandScript = preload("res://scripts/simulation/commands/cancel_transport_operation_command.gd")
const RequestFleetRetreatCommandScript = preload("res://scripts/simulation/commands/request_fleet_retreat_command.gd")
const SetFleetMissionCommandScript = preload("res://scripts/simulation/commands/set_fleet_mission_command.gd")
const SplitFleetCommandScript = preload("res://scripts/simulation/commands/split_fleet_command.gd")
const TransferShipsCommandScript = preload("res://scripts/simulation/commands/transfer_ships_command.gd")
const MergeFleetsCommandScript = preload("res://scripts/simulation/commands/merge_fleets_command.gd")
const SetFleetHomePortCommandScript = preload("res://scripts/simulation/commands/set_fleet_home_port_command.gd")
const ScuttleFleetCommandScript = preload("res://scripts/simulation/commands/scuttle_fleet_command.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

const BLOCKADE_TIER_NAMES := ["None", "Light", "Moderate", "Heavy", "Severe", "Full"]

@export var simulation_controller: GrandWorldSimulationController
@export var province_selector: ProvinceSelector
@export var notification_hud: SimulationHUD
@export var map_hud: MapHUD
@export var army_layer: ArmyLayer
## FL1.5 closure: HUD-driven reverse sync. FleetMarkerLayer already pushes
## map clicks into this panel (select_fleet()); without this reference
## nothing pushed a HUD-driven selection change (dropdown pick, or the
## fallback reselection _refresh_fleet_options() performs when the
## previously selected fleet is gone) back out to the map, so the drawn
## route could silently point at a fleet the panel no longer shows.
@export var fleet_marker_layer: FleetMarkerLayer

@onready var naval_toggle_button: Button = %NavalToggleButton
@onready var naval_panel: PanelContainer = %NavalPanel
@onready var close_naval_button: Button = %CloseNavalButton
@onready var fleet_summary_label: Label = %FleetSummaryLabel
@onready var fleet_option: OptionButton = %FleetOption
@onready var fleet_details_label: Label = %FleetDetailsLabel
@onready var move_fleet_button: Button = %MoveFleetButton
@onready var cancel_movement_button: Button = %CancelMovementButton
@onready var retreat_button: Button = %RetreatButton
@onready var set_home_port_button: Button = %SetHomePortButton
@onready var scuttle_fleet_button: Button = %ScuttleFleetButton
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
@onready var focus_carried_army_button: Button = %FocusCarriedArmyButton
@onready var battle_summary_label: Label = %BattleSummaryLabel
@onready var battle_option: OptionButton = %BattleOption
@onready var battle_details_label: Label = %BattleDetailsLabel
@onready var battle_report_label: Label = %BattleReportLabel
@onready var blockade_label: Label = %BlockadeLabel
@onready var organisation_label: Label = %OrganisationLabel
@onready var ship_transfer_list: ItemList = %ShipTransferList
@onready var target_fleet_option: OptionButton = %TargetFleetOption
@onready var split_fleet_button: Button = %SplitFleetButton
@onready var transfer_ships_button: Button = %TransferShipsButton
@onready var merge_fleets_button: Button = %MergeFleetsButton
@onready var mission_option: OptionButton = %MissionOption
@onready var set_mission_button: Button = %SetMissionButton
@onready var show_blockade_map_button: Button = %ShowBlockadeMapButton

var _selected_province_id := -1
var _selected_owner := ""
## FL2.5 rule 8: which fleet's Scuttle button is currently armed for a
## second confirming press. Cleared whenever the selected fleet changes.
var _scuttle_armed_fleet_id := ""


func _ready() -> void:
	naval_panel.hide()
	naval_toggle_button.pressed.connect(toggle_naval_panel)
	close_naval_button.pressed.connect(naval_panel.hide)
	fleet_option.item_selected.connect(func(_index: int) -> void: _refresh_fleet_details())
	move_fleet_button.pressed.connect(_move_selected_fleet)
	cancel_movement_button.pressed.connect(_cancel_selected_fleet_movement)
	retreat_button.pressed.connect(_retreat_selected_fleet)
	set_home_port_button.pressed.connect(_set_selected_fleet_home_port)
	scuttle_fleet_button.pressed.connect(_scuttle_selected_fleet)
	admiral_option.item_selected.connect(func(_index: int) -> void: _refresh_admiral_validation())
	assign_admiral_button.pressed.connect(_assign_selected_admiral)
	ship_transfer_list.multi_selected.connect(func(_index: int, _selected: bool) -> void: _refresh_organisation_validation())
	target_fleet_option.item_selected.connect(func(_index: int) -> void: _refresh_organisation_validation())
	split_fleet_button.pressed.connect(_split_selected_ships)
	transfer_ships_button.pressed.connect(_transfer_selected_ships)
	merge_fleets_button.pressed.connect(_merge_selected_fleets)
	ship_option.item_selected.connect(func(_index: int) -> void: _refresh_construction_validation())
	construct_ship_button.pressed.connect(_construct_selected_ship)
	cancel_naval_construction_button.pressed.connect(_cancel_selected_construction)
	army_option.item_selected.connect(func(_index: int) -> void: _refresh_embark_validation())
	embark_button.pressed.connect(_embark_selected_army)
	cancel_transport_button.pressed.connect(_cancel_selected_transport)
	focus_carried_army_button.pressed.connect(_focus_carried_army)
	battle_option.item_selected.connect(func(_index: int) -> void: _refresh_battle_details())
	mission_option.item_selected.connect(func(_index: int) -> void: _refresh_mission_validation())
	set_mission_button.pressed.connect(_set_selected_fleet_mission)
	show_blockade_map_button.pressed.connect(_show_blockade_map)
	province_selector.province_selected.connect(_on_province_selected)
	province_selector.selection_cleared.connect(func() -> void:
		_selected_province_id = -1
		_refresh_port_panel())
	_populate_ship_options()
	_populate_mission_options()
	_connect_events()
	_refresh_all()


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	events.player_country_changed.connect(func(_old: String, _new: String) -> void: _refresh_all())
	events.world_reloaded.connect(func(_checksum: String) -> void: _refresh_all())
	# FL2.6 closure: war/peace/access changes can silently invalidate basing,
	# route, and transport legality shown in this panel (a captured or
	# access-revoked port mid-transport) without any naval-specific event
	# firing first. Matches war_hud.gd's own exact hookup for the same three
	# events, not a new pattern.
	events.war_declared.connect(func(_war: String, _attacker: String, _defender: String, _target: int) -> void: _refresh_all())
	events.peace_signed.connect(func(_war: String, _attacker: String, _defender: String, _truce_day: int) -> void: _refresh_all())
	events.military_access_changed.connect(func(_country: String, _host: String, _granted: bool) -> void: _refresh_all())
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
	events.fleets_merged.connect(func(target: String, sources: Array) -> void:
		var selected_before_merge := _selected_fleet_id()
		_refresh_all()
		# FL1.2: preserve the semantic selection across a merge. If the
		# selected record was folded into the deterministic survivor, select
		# that survivor rather than the unrelated sorted-first fallback.
		if selected_before_merge != target and sources.has(selected_before_merge) and simulation_controller.world.fleet_registry.has(target):
			select_fleet(target))
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
	events.naval_battle_started.connect(func(_war: String, _battle: String, zone_id: int) -> void:
		_notify("Naval battle started at %s." % _province_name(zone_id))
		_refresh_all())
	events.naval_battle_reinforced.connect(func(_battle: String, _fleet: String, _side: String) -> void: _refresh_all())
	events.naval_battle_round_resolved.connect(func(_battle: String, _round: int, _a: int, _d: int) -> void: _refresh_all())
	events.naval_battle_ended.connect(func(_war: String, _battle: String, winner_side: String) -> void:
		_notify("Naval battle ended · %s side won." % winner_side.capitalize())
		_refresh_all())
	events.fleet_retreat_started.connect(func(fleet_id: String, destination_id: int) -> void:
		_notify("%s is retreating to %s." % [fleet_id, _province_name(destination_id)])
		_refresh_all())
	events.fleet_destroyed.connect(func(_fleet: String, _reason: String) -> void: _refresh_all())
	# FL1.5 closure: scuttling (this panel's own Scuttle button) removes a
	# fleet exactly like fleet_destroyed does, but emits its own distinct
	# event - nothing previously listened for it, so the panel kept showing
	# the scuttled fleet's stale details until an unrelated event refreshed it.
	events.fleet_scuttled.connect(func(_fleet: String, _country: String, _ships: int) -> void: _refresh_all())
	events.ship_sunk.connect(func(_ship: String, _battle: String) -> void: _refresh_all())
	events.fleet_mission_changed.connect(func(_fleet: String, _mission: String) -> void: _refresh_all())
	events.blockade_started.connect(func(province_id: int) -> void:
		if simulation_controller.world.get_province_owner(province_id) == _player_country():
			_notify("%s is now blockaded." % _province_name(province_id))
		_refresh_all())
	events.blockade_ended.connect(func(province_id: int) -> void:
		if simulation_controller.world.get_province_owner(province_id) == _player_country():
			_notify("The blockade of %s has ended." % _province_name(province_id))
		_refresh_all())
	events.port_fully_blockaded.connect(func(province_id: int) -> void:
		if simulation_controller.world.get_province_owner(province_id) == _player_country():
			_notify("%s is fully blockaded." % _province_name(province_id))
		_refresh_all())
	events.port_unblocked.connect(func(province_id: int) -> void:
		if simulation_controller.world.get_province_owner(province_id) == _player_country():
			_notify("%s is no longer fully blockaded." % _province_name(province_id))
		_refresh_all())
	events.coastal_siege_support_changed.connect(func(_war: String, _province: int, _assisted: bool) -> void: _refresh_all())


func _notify(message: String) -> void:
	if notification_hud != null:
		notification_hud._show_status(message)


func _player_country() -> String:
	return simulation_controller.world.player_country if simulation_controller.initialized else ""


func _province_name(province_id: int) -> String:
	var graph := ProvinceGraphScript.load_default()
	var name := graph.province_name(province_id)
	return name if not name.is_empty() else "province %d" % province_id


## FL2.1 closure: the fleet panel previously showed the admiral's raw
## character ID. Matches the exact "name, falling back to the ID" resolution
## _populate_admiral_options() already uses for the admiral picker itself, so
## the summary and the picker never disagree on what to call the same person.
func _admiral_display_name(admiral_id: String) -> String:
	if admiral_id.is_empty():
		return "none"
	if not simulation_controller.world.character_registry.has(admiral_id):
		return admiral_id
	var character: Dictionary = simulation_controller.world.character_registry[admiral_id]
	return String(character.get("name", admiral_id))


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


## Battle-marker click-to-focus, mirroring select_fleet() and
## WarHUD.focus_conflict_marker() - the naval counterpart ConflictMarkerLayer
## calls when the player clicks a naval battle marker on the map.
func select_battle(battle_id: String) -> void:
	open_naval_panel()
	_refresh_battle_options()
	for index in battle_option.item_count:
		if String(battle_option.get_item_metadata(index)) == battle_id:
			battle_option.select(index)
			_refresh_battle_details()
			break


## FL1.4 blockade-marker click-to-focus: reuses the exact same province
## selection path the real province selector already drives
## (_on_province_selected -> _refresh_port_panel -> _refresh_blockade_label),
## so a marker click and a real click on the port produce identical results.
func select_blockaded_province(province_id: int) -> void:
	open_naval_panel()
	_on_province_selected({"province_id": province_id, "owner_tag": simulation_controller.world.get_province_owner(province_id)})


func _refresh_all() -> void:
	var tag := _player_country()
	naval_toggle_button.visible = not tag.is_empty()
	if tag.is_empty():
		naval_panel.hide()
		return
	_refresh_fleet_options()
	_refresh_fleet_details()
	_refresh_port_panel()
	_refresh_battle_options()
	_refresh_battle_report()


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
	var previous_still_exists := false
	for index in fleet_option.item_count:
		if String(fleet_option.get_item_metadata(index)) == previous:
			fleet_option.select(index)
			previous_still_exists = true
			break
	# FL2.1 closure: previously, if the selected fleet was destroyed/merged
	# away, nothing here called select() at all - which fleet ended up shown
	# was whatever Godot's OptionButton happens to default to after clear()
	# and repeated add_item() calls, not a decision this code made. Falls
	# back explicitly to fleet_ids[0] - _country_fleets()'s own sorted order,
	# the same "lowest sorted ID" convention MergeFleetsCommand's survivor
	# pick already established - so which fleet becomes selected is
	# deterministic and testable, not an engine implementation detail.
	if not previous_still_exists and fleet_option.item_count > 0:
		fleet_option.select(0)


func _selected_fleet_id() -> String:
	if fleet_option.item_count == 0 or fleet_option.selected < 0:
		return ""
	return String(fleet_option.get_item_metadata(fleet_option.selected))


func _refresh_fleet_details() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_marker_layer != null:
		fleet_marker_layer.set_selected_fleet(fleet_id)
	if fleet_id != _scuttle_armed_fleet_id:
		_scuttle_armed_fleet_id = ""
	if fleet_id.is_empty():
		fleet_details_label.text = "No fleets."
		move_fleet_button.disabled = true
		cancel_movement_button.disabled = true
		assign_admiral_button.disabled = true
		set_home_port_button.disabled = true
		scuttle_fleet_button.disabled = true
		scuttle_fleet_button.text = "Scuttle"
		focus_carried_army_button.disabled = true
		focus_carried_army_button.tooltip_text = ""
		ship_transfer_list.clear()
		target_fleet_option.clear()
		split_fleet_button.disabled = true
		transfer_ships_button.disabled = true
		merge_fleets_button.disabled = true
		return
	var world := simulation_controller.world
	var fleet := world.get_fleet(fleet_id)
	var aggregate: Dictionary = fleet.get("aggregate", {})
	var max_hull := int(aggregate.get("total_maximum_hull", 0))
	var hull_pct := 100 if max_hull <= 0 else int(aggregate.get("total_hull", 0)) * 100 / max_hull
	var crew_pct := int(aggregate.get("crew_readiness_bp", 10000)) / 100
	var admiral_id := String(fleet.get("admiral_id", ""))
	var supplied := bool(fleet.get("supplied", true))
	var mission := String(fleet.get("mission", "idle"))
	var mission_text := mission.replace("_", " ").capitalize()
	if mission == "blockade":
		mission_text += " · power %d" % BlockadeSystemScript.effective_power(world, fleet_id)
	elif mission == "repair":
		mission_text += " · completes at full hull (%d%% now)" % hull_pct
	elif mission == "return_to_port":
		var mission_targets := (fleet.get("mission_target_ids", []) as Array)
		mission_text += " · target %s" % (_province_name(int(mission_targets[0])) if not mission_targets.is_empty() else "nearest legal port")
	# FL5.1/FL2.4: the same "power N" pattern blockade already shows above -
	# this fleet's own contribution, not NavalTradeProtection.assess()'s
	# country-wide sum for the zone (which could include other fleets).
	elif mission == "trade_protection":
		mission_text += " · power %d" % NavalTradeProtectionScript.effective_power(world, fleet_id)
	# FL2 closure audit: this must be the same damage-aware query
	# CreateTransportOperationCommand validates against, not the raw
	# aggregate total - a disabled or badly damaged ship still counts toward
	# total_transport_capacity but contributes zero usable capacity.
	var capacity := TransportSystemScript.usable_capacity(world, fleet_id)
	var reserved := TransportSystemScript.reserved_capacity(world, fleet_id)
	var display_name := String(fleet.get("display_name", ""))
	fleet_details_label.text = "Name %s · Owner %s\nLocation %s · %s · Home port %s\nShips %d (%s) · Hull %d%% · Crew %d%% · Morale %d%% · Speed %d\nSupplied %s%s · Maintenance %d%%\nTransport %d/%d reserved · Admiral %s\nMission %s" % [
		display_name if not display_name.is_empty() else fleet_id,
		simulation_controller.country_registry.display_name(String(fleet.get("owner_country_id", ""))),
		_province_name(int(fleet.get("location_id", -1))), String(fleet.get("location_status", "")).capitalize(), _province_name(int(fleet.get("home_port_id", -1))),
		int(aggregate.get("ship_count", 0)), FleetSystemScript.format_class_counts(aggregate.get("family_counts", {})), hull_pct, crew_pct, int(fleet.get("morale_bp", 10000)) / 100, int(aggregate.get("speed", 0)),
		"yes" if supplied else "no",
		"" if supplied else " (%s)" % String(fleet.get("supply_reason", "")),
		int(fleet.get("maintenance_posture_bp", 10000)) / 100,
		reserved,
		capacity,
		_admiral_display_name(admiral_id),
		mission_text,
	]
	var repairing_count := FleetLogisticsSystemScript.repairing_ship_count(world, fleet_id)
	if repairing_count > 0:
		fleet_details_label.text += "\nRepairing %d/%d ships" % [repairing_count, int(aggregate.get("ship_count", 0))]
	var final_eta := FleetSystemScript.route_completion_day(world, fleet_id)
	if final_eta >= 0:
		var remaining_path := (fleet.get("remaining_path", []) as Array).slice(int(fleet.get("path_index", 0)))
		var waypoint_names: Array[String] = []
		for raw_node_id in remaining_path:
			waypoint_names.append(_province_name(int(raw_node_id)))
		fleet_details_label.text += "\nRoute %s · next waypoint arrival %s · final ETA %s" % [
			" -> ".join(waypoint_names),
			SimulationDateScript.format_day(int(fleet.get("next_arrival_day", -1))),
			SimulationDateScript.format_day(final_eta),
		]
	var battle_id := String(fleet.get("battle_id", ""))
	if not battle_id.is_empty():
		var battle := world.get_naval_battle(battle_id)
		fleet_details_label.text += "\nIn battle at %s · round %d" % [_province_name(int(battle.get("zone_id", -1))), int(battle.get("round", 0))]
	cancel_movement_button.disabled = String(fleet.get("location_status", "")) != CampaignWorldStateScript.FLEET_LOCATION_MOVING
	_refresh_move_validation()
	_refresh_retreat_validation()
	_refresh_home_port_validation()
	_refresh_scuttle_validation()
	_populate_admiral_options()
	_refresh_admiral_validation()
	_refresh_transport_panel()
	_refresh_ship_transfer_list()
	_refresh_target_fleet_options()
	_refresh_organisation_validation()
	_sync_mission_selection()
	_refresh_mission_validation()


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


## FL2.3: "Add home-port selection filtered by legal basing rights" - reuses
## the same selected-province concept Move/Embark already share rather than
## a separate port-picker dropdown, matching this panel's own established
## "select on the map, then act" pattern. SetFleetHomePortCommand.validate()
## -> NavalAccessPolicy.dock_failure_reason() already distinguishes range,
## supply, blockade and access failures in its returned text.
func _refresh_home_port_validation() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or _selected_province_id < 0:
		set_home_port_button.disabled = true
		set_home_port_button.tooltip_text = ""
		return
	var failure := SetFleetHomePortCommandScript.new(_player_country(), fleet_id, _selected_province_id).validate(simulation_controller.world)
	set_home_port_button.disabled = not failure.is_empty()
	set_home_port_button.tooltip_text = failure if not failure.is_empty() else "Set home port to %s" % _province_name(_selected_province_id)


## FL2.5 rule 8: pressing Scuttle the first time only arms the button - the
## text renames to name the fleet and ship count and a second press is
## required before ScuttleFleetCommand is actually submitted. Re-validates
## every refresh so an armed fleet that becomes illegal to scuttle (e.g. it
## starts moving) is disabled again rather than leaving a stale armed state
## the player could still confirm.
func _refresh_scuttle_validation() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty():
		scuttle_fleet_button.disabled = true
		scuttle_fleet_button.text = "Scuttle"
		scuttle_fleet_button.tooltip_text = ""
		return
	var failure := ScuttleFleetCommandScript.new(_player_country(), fleet_id).validate(simulation_controller.world)
	scuttle_fleet_button.disabled = not failure.is_empty()
	if not failure.is_empty():
		scuttle_fleet_button.text = "Scuttle"
		scuttle_fleet_button.tooltip_text = failure
		return
	if _scuttle_armed_fleet_id == fleet_id:
		var ship_count := int(simulation_controller.world.get_fleet(fleet_id).get("aggregate", {}).get("ship_count", 0))
		scuttle_fleet_button.text = "Scuttle %d ships? Confirm" % ship_count
		scuttle_fleet_button.tooltip_text = "Press again to permanently scuttle %s. This cannot be undone and gives no refund." % fleet_id
	else:
		scuttle_fleet_button.text = "Scuttle"
		scuttle_fleet_button.tooltip_text = "Permanently disband this fleet at its dock with no refund."


## "Retreat control" (04_N4 "Player Feedback") - RequestFleetRetreatCommand
## already carries every rule this needs (ownership, in-battle, minimum
## round count); the button is only enabled once validate() actually
## accepts, so its tooltip doubles as the "why not yet" explanation the
## roadmap's "earliest legal date" language asks for.
func _refresh_retreat_validation() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty():
		retreat_button.disabled = true
		retreat_button.tooltip_text = ""
		return
	var failure := RequestFleetRetreatCommandScript.new(_player_country(), fleet_id).validate(simulation_controller.world)
	retreat_button.disabled = not failure.is_empty()
	retreat_button.tooltip_text = failure if not failure.is_empty() else "Withdraw this fleet from its current battle"


func _retreat_selected_fleet() -> void:
	var fleet_id := _selected_fleet_id()
	if not fleet_id.is_empty():
		simulation_controller.request_fleet_retreat(_player_country(), fleet_id)


func _populate_mission_options() -> void:
	mission_option.clear()
	for mission in SetFleetMissionCommandScript.VALID_MISSIONS:
		mission_option.add_item(String(mission).capitalize())
		mission_option.set_item_metadata(mission_option.item_count - 1, mission)


## Sets the dropdown to match the selected fleet's actual current mission -
## only called when the fleet selection itself changes (from
## _refresh_fleet_details()), mirroring _populate_admiral_options()'s own
## "sync once, on fleet switch" role. _refresh_mission_validation() must
## never re-run this: it also fires on the dropdown's own item_selected, and
## overwriting the player's just-made choice back to the old mission every
## time would make the control unusable.
func _sync_mission_selection() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or mission_option.item_count == 0:
		return
	var current := String(simulation_controller.world.get_fleet(fleet_id).get("mission", "idle"))
	for index in mission_option.item_count:
		if String(mission_option.get_item_metadata(index)) == current:
			mission_option.select(index)
			break


func _refresh_mission_validation() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or mission_option.item_count == 0 or mission_option.selected < 0:
		set_mission_button.disabled = true
		return
	var mission := String(mission_option.get_item_metadata(mission_option.selected))
	var failure := SetFleetMissionCommandScript.new(_player_country(), fleet_id, mission).validate(simulation_controller.world)
	set_mission_button.disabled = not failure.is_empty()
	if not failure.is_empty():
		set_mission_button.tooltip_text = failure
	elif mission == "return_to_port" and _selected_province_id >= 0:
		set_mission_button.tooltip_text = "Target: %s (falls back to the nearest legal port if this becomes illegal)" % _province_name(_selected_province_id)
	elif mission == "return_to_port":
		set_mission_button.tooltip_text = "No province selected - will return to the nearest legal port automatically."
	elif mission == "repair":
		set_mission_button.tooltip_text = "Completes automatically once the fleet's hull is fully repaired."
	elif mission == "blockade":
		set_mission_button.tooltip_text = "Blockades hostile coastal provinces this fleet's zone reaches, reducing their income and repair/construction rate while eligible."
	# FL3.4/FL2.4: honest, mission-specific text for the tactical missions
	# FL3.4 gave real assignment logic to - but only for AI-controlled
	# fleets. NavalAISystem.process_day() explicitly skips world.player_country
	# (naval_ai_system.gd), so _consider_mission_completion()'s automatic
	# stand-down never runs for a player-set mission - a player fleet keeps
	# whatever mission it's given until manually changed. NavalCombatSystem's
	# flat combat modifier (naval_combat_system.gd) does apply regardless of
	# who set the tag, for patrol/intercept/protect_transport - but not for
	# protect_coast, which currently has no modifier entry at all and is
	# purely a position/label with no mechanical effect for either side.
	elif mission == "patrol":
		set_mission_button.tooltip_text = "A combat bonus while this fleet holds a safe zone. AI fleets reassign this automatically once it stops being useful; a player fleet keeps it until changed."
	elif mission == "intercept":
		set_mission_button.tooltip_text = "A combat bonus for positioning against a hostile fleet in this zone. AI fleets reassign this automatically once no hostile fleet remains here; a player fleet keeps it until changed."
	elif mission == "protect_transport":
		set_mission_button.tooltip_text = "A combat bonus for escorting a friendly transport operation in this zone. AI fleets reassign this automatically once no transport here needs escort; a player fleet keeps it until changed."
	elif mission == "protect_coast":
		set_mission_button.tooltip_text = "Drives AI fleet positioning toward a threatened coastline. No combat bonus and no automatic reassignment when set on a player fleet - currently a label only."
	elif mission == "trade_protection":
		set_mission_button.tooltip_text = "Contributes protective naval power at this zone for a future trade system - no gameplay effect yet."
	elif mission == "transport":
		set_mission_button.tooltip_text = "This label alone has no effect - use Embark/the transport workflow to actually carry an army."
	else:
		set_mission_button.tooltip_text = ""


## FL2.3: a "return_to_port" mission reuses the same selected-province concept
## Move/Embark/Home-port already share - if a province is selected when the
## mission is set, it becomes the mission's target (FleetMissionSystem then
## prefers it over auto-picking the nearest legal port; see
## fleet_mission_system.gd). No other mission in this list currently
## consumes a target, so this is scoped narrowly rather than always attaching
## whatever happens to be selected.
func _set_selected_fleet_mission() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or mission_option.item_count == 0:
		return
	var mission := String(mission_option.get_item_metadata(mission_option.selected))
	var target_ids: Array = [_selected_province_id] if mission == "return_to_port" and _selected_province_id >= 0 else []
	simulation_controller.set_fleet_mission(_player_country(), fleet_id, mission, target_ids)


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


## FL2.2 split/transfer: lists the selected fleet's own ships so the player
## can pick which ones move. Selection is preserved by ship ID across a
## rebuild (mirroring _refresh_fleet_options()'s "keep previous selection"
## pattern), not by list index, since membership can change between refreshes.
func _refresh_ship_transfer_list() -> void:
	var fleet_id := _selected_fleet_id()
	var previous := _selected_transfer_ship_ids()
	ship_transfer_list.clear()
	if fleet_id.is_empty():
		return
	var fleet := simulation_controller.world.get_fleet(fleet_id)
	var ship_ids: Array = (fleet.get("ship_ids", []) as Array).duplicate()
	ship_ids.sort()
	for raw_ship_id in ship_ids:
		var ship_id := String(raw_ship_id)
		var ship := simulation_controller.world.get_ship(ship_id)
		var hull_pct := int(ship.get("hull_bp", 10000)) / 100
		ship_transfer_list.add_item("%s (%s, hull %d%%)" % [ship_id, String(ship.get("definition_id", "")), hull_pct])
		ship_transfer_list.set_item_metadata(ship_transfer_list.item_count - 1, ship_id)
		if previous.has(ship_id):
			ship_transfer_list.select(ship_transfer_list.item_count - 1, false)


func _selected_transfer_ship_ids() -> Array:
	var ids: Array = []
	for index in ship_transfer_list.get_selected_items():
		ids.append(String(ship_transfer_list.get_item_metadata(index)))
	return ids


## Merge/transfer both need an "other fleet at the same port" target -
## FleetSystem.is_docked_and_organisable() mirrors the exact eligibility
## MergeFleetsCommand/TransferShipsCommand themselves check, so this list
## never offers a choice validate() would go on to reject.
func _refresh_target_fleet_options() -> void:
	var fleet_id := _selected_fleet_id()
	var previous := ""
	if target_fleet_option.item_count > 0 and target_fleet_option.selected >= 0:
		previous = String(target_fleet_option.get_item_metadata(target_fleet_option.selected))
	target_fleet_option.clear()
	if fleet_id.is_empty():
		return
	var tag := _player_country()
	var world := simulation_controller.world
	var source_port := int(world.get_fleet(fleet_id).get("location_id", -1))
	for other_fleet_id in _country_fleets():
		if other_fleet_id == fleet_id:
			continue
		if not FleetSystemScript.is_docked_and_organisable(world, other_fleet_id, tag):
			continue
		if int(world.get_fleet(other_fleet_id).get("location_id", -1)) != source_port:
			continue
		var aggregate: Dictionary = world.get_fleet(other_fleet_id).get("aggregate", {})
		target_fleet_option.add_item("%s (%d ships)" % [other_fleet_id, int(aggregate.get("ship_count", 0))])
		target_fleet_option.set_item_metadata(target_fleet_option.item_count - 1, other_fleet_id)
		if other_fleet_id == previous:
			target_fleet_option.select(target_fleet_option.item_count - 1)


## FL2.2's own aggregate-preview bullet ("resulting class mix, speed,
## capacity and mission impact") is still open - a *resulting fleet's* full
## stats needs the same class-breakdown data FL2.1's fleet-summary packet
## just added to recompute_aggregate(), plus work this packet doesn't do
## (simulating a fleet that doesn't exist yet). This reuses that same
## class-count query for a smaller, immediately gradable thing instead: what
## you are about to peel off, before you commit to splitting or transferring it.
func _refresh_organisation_validation() -> void:
	var fleet_id := _selected_fleet_id()
	var tag := _player_country()
	var ship_ids := _selected_transfer_ship_ids()
	if ship_ids.is_empty():
		organisation_label.text = "Select ships (below) to split into a new fleet or transfer to the target fleet."
	else:
		var counts := FleetSystemScript.class_counts_for_ships(simulation_controller.world, ship_ids)
		organisation_label.text = "Selected %d ships (%s) - split into a new fleet or transfer to the target fleet." % [ship_ids.size(), FleetSystemScript.format_class_counts(counts)]
	if fleet_id.is_empty() or ship_ids.is_empty():
		split_fleet_button.disabled = true
		split_fleet_button.tooltip_text = "Select at least one ship to split into a new fleet."
		transfer_ships_button.disabled = true
		transfer_ships_button.tooltip_text = "Select at least one ship to transfer."
	else:
		var split_failure := SplitFleetCommandScript.new(tag, fleet_id, ship_ids).validate(simulation_controller.world)
		split_fleet_button.disabled = not split_failure.is_empty()
		split_fleet_button.tooltip_text = split_failure
		if target_fleet_option.item_count == 0 or target_fleet_option.selected < 0:
			transfer_ships_button.disabled = true
			transfer_ships_button.tooltip_text = "No eligible target fleet at this port."
		else:
			var target_fleet_id := String(target_fleet_option.get_item_metadata(target_fleet_option.selected))
			var transfer_failure := TransferShipsCommandScript.new(tag, ship_ids, target_fleet_id).validate(simulation_controller.world)
			transfer_ships_button.disabled = not transfer_failure.is_empty()
			transfer_ships_button.tooltip_text = transfer_failure
	if fleet_id.is_empty() or target_fleet_option.item_count == 0 or target_fleet_option.selected < 0:
		merge_fleets_button.disabled = true
		merge_fleets_button.tooltip_text = "No eligible target fleet at this port."
	else:
		var merge_target := String(target_fleet_option.get_item_metadata(target_fleet_option.selected))
		var merge_failure := MergeFleetsCommandScript.new(tag, [fleet_id, merge_target]).validate(simulation_controller.world)
		merge_fleets_button.disabled = not merge_failure.is_empty()
		merge_fleets_button.tooltip_text = merge_failure


func _on_province_selected(info: Dictionary) -> void:
	_selected_province_id = int(info.get("province_id", -1))
	_selected_owner = String(info.get("owner_tag", ""))
	_refresh_move_validation()
	_refresh_port_panel()
	_refresh_embark_validation()
	_refresh_home_port_validation()
	_refresh_mission_validation()


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


## FL2.6 closure: destination now resolves to a name (was a raw province ID);
## each line shows its own reserved capacity persistently rather than only
## inside a rejection tooltip at the moment of a shortfall; a sailing
## operation shows its real, already-authoritative planned_path resolved to
## names (TransportSystem.process_day() populates it on the embark->sailing
## transition - it was already there, just never surfaced). "Danger" (the
## roadmap's other named gap) is deliberately not built here: the only
## existing per-zone risk heuristic is NavalAISystem's private _zone_threat(),
## an AI-internal scoring function never designed for player-facing display
## or per-route aggregation - reusing it would be new, unproven simulation
## surface area, not a UI fix. Left open, not silently dropped.
##
## Cancellability also now matches CancelTransportOperationCommand.validate()
## exactly - it accepts both embarking AND disembarking, but this function
## previously only ever offered the button for embarking, silently hiding a
## legal cancellation the whole time disembarking was reachable.
func _refresh_transport_panel() -> void:
	var world := simulation_controller.world
	var fleet_id := _selected_fleet_id()
	var operation_ids := _active_operations_for_fleet(fleet_id)
	# FL2.6 closure: "link the fleet, army and operation views" - scoped to
	# the common single-operation case, since transport_label is one Label
	# rendering every active operation as plain text, not a per-row list with
	# per-row actions. With more than one army embarked on the same carrier
	# fleet at once, which one "focus" should mean is ambiguous, so the
	# button is disabled with an explanatory tooltip rather than guessing.
	if operation_ids.size() == 1:
		focus_carried_army_button.disabled = false
		focus_carried_army_button.tooltip_text = ""
		focus_carried_army_button.set_meta("army_id", String(world.get_transport_operation(operation_ids[0]).get("army_id", "")))
	else:
		focus_carried_army_button.disabled = true
		focus_carried_army_button.tooltip_text = "No single carried army to focus." if operation_ids.is_empty() else "Multiple armies are embarked on this fleet - select one on the map directly."
		focus_carried_army_button.set_meta("army_id", "")
	if operation_ids.is_empty():
		transport_label.text = "No active transport for the selected fleet."
		cancel_transport_button.visible = false
	else:
		var lines: Array[String] = []
		var cancellable_id := ""
		var cancellable_state := ""
		for operation_id in operation_ids:
			var operation := world.get_transport_operation(operation_id)
			var state := String(operation.get("state", ""))
			lines.append("%s: %s bound for %s · %d capacity reserved" % [
				String(operation.get("army_id", "")), state.capitalize(), _province_name(int(operation.get("destination_province_id", -1))), int(operation.get("reserved_capacity", 0)),
			])
			var planned_path := (operation.get("planned_path", []) as Array)
			if state == CampaignWorldStateScript.TRANSPORT_STATE_SAILING and not planned_path.is_empty():
				var waypoint_names: Array[String] = []
				for raw_node_id in planned_path:
					waypoint_names.append(_province_name(int((raw_node_id as Dictionary).get("id", -1))))
				lines.append("  Route %s" % " -> ".join(waypoint_names))
			if state in [CampaignWorldStateScript.TRANSPORT_STATE_EMBARKING, CampaignWorldStateScript.TRANSPORT_STATE_DISEMBARKING]:
				cancellable_id = operation_id
				cancellable_state = state
		transport_label.text = "\n".join(lines)
		cancel_transport_button.visible = not cancellable_id.is_empty()
		cancel_transport_button.set_meta("operation_id", cancellable_id)
		if cancellable_state == CampaignWorldStateScript.TRANSPORT_STATE_DISEMBARKING:
			cancel_transport_button.tooltip_text = "Cancels the transport and lands the army immediately at its current location."
		elif cancellable_state == CampaignWorldStateScript.TRANSPORT_STATE_EMBARKING:
			cancel_transport_button.tooltip_text = "Cancels the transport and returns the army to its origin, unembarked."
		else:
			cancel_transport_button.tooltip_text = ""
	_populate_army_options()
	# A persistent required/available capacity preview for whichever army is
	# currently selected to embark - previously these numbers only ever
	# appeared inside embark_button's tooltip, and only once validation had
	# already failed for a capacity reason specifically.
	if army_option.item_count > 0 and army_option.selected >= 0 and not fleet_id.is_empty():
		var selected_army_id := String(army_option.get_item_metadata(army_option.selected))
		var required := TransportSystemScript.required_capacity(world, selected_army_id)
		var available := TransportSystemScript.available_capacity(world, fleet_id)
		transport_label.text += "\nSelected army requires %d capacity · %d available" % [required, available]
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


## FL2.6 closure: "link the fleet, army and operation views" - selects the
## carried army on the map's ArmyLayer, mirroring CampaignInterfaceShell's own
## _focus_army() (its own selection half; this panel has no camera_controller
## reference to also pan the view, so it deliberately only selects/highlights).
func _focus_carried_army() -> void:
	var army_id := String(focus_carried_army_button.get_meta("army_id", ""))
	if not army_id.is_empty() and army_layer != null:
		army_layer.set_selected_army(army_id)


## Active naval battles the player has a stake in right now - "any fleet
## currently on either side is mine," the same live-membership test
## ConflictMarkerLayer's own naval markers use, so the list and the map
## marker the player just clicked always agree on what counts as "active."
func _player_active_battles() -> Array[String]:
	var tag := _player_country()
	var found: Array[String] = []
	var ids := simulation_controller.world.naval_battle_registry.keys()
	ids.sort()
	for raw_id in ids:
		var battle: Dictionary = simulation_controller.world.naval_battle_registry[raw_id]
		if String(battle.get("status", "")) != "active":
			continue
		var relevant := false
		for raw_fleet_id in (battle.get("attacker_fleets", []) as Array) + (battle.get("defender_fleets", []) as Array):
			if String(simulation_controller.world.get_fleet(String(raw_fleet_id)).get("owner_country_id", "")) == tag:
				relevant = true
				break
		if relevant:
			found.append(String(raw_id))
	return found


func _refresh_battle_options() -> void:
	var previous := _selected_battle_id()
	battle_option.clear()
	var battle_ids := _player_active_battles()
	for battle_id in battle_ids:
		var battle := simulation_controller.world.get_naval_battle(battle_id)
		battle_option.add_item("%s · round %d" % [_province_name(int(battle.get("zone_id", -1))), int(battle.get("round", 0))])
		battle_option.set_item_metadata(battle_option.item_count - 1, battle_id)
	battle_summary_label.text = "Naval battles %d active" % battle_ids.size()
	if battle_ids.is_empty():
		battle_details_label.text = "No active naval battles."
	for index in battle_option.item_count:
		if String(battle_option.get_item_metadata(index)) == previous:
			battle_option.select(index)
			break
	_refresh_battle_details()


func _selected_battle_id() -> String:
	if battle_option.item_count == 0 or battle_option.selected < 0:
		return ""
	return String(battle_option.get_item_metadata(battle_option.selected))


func _refresh_battle_details() -> void:
	var battle_id := _selected_battle_id()
	if battle_id.is_empty():
		return
	var battle := simulation_controller.world.get_naval_battle(battle_id)
	var attacker_fleets := (battle.get("attacker_fleets", []) as Array)
	var defender_fleets := (battle.get("defender_fleets", []) as Array)
	battle_details_label.text = "%s · round %d\nAttackers %d fleets · position %d%% · morale %d%% · %d hull lost · %d sunk · %d captured\nDefenders %d fleets · position %d%% · morale %d%% · %d hull lost · %d sunk · %d captured" % [
		_province_name(int(battle.get("zone_id", -1))), int(battle.get("round", 0)),
		attacker_fleets.size(), int(battle.get("attacker_positioning_bp", 10000)) / 100, int(battle.get("attacker_morale_bp", 10000)) / 100,
		int(battle.get("attacker_hull_lost", 0)), int(battle.get("attacker_ships_sunk", 0)), (battle.get("attacker_captured_ship_ids", []) as Array).size(),
		defender_fleets.size(), int(battle.get("defender_positioning_bp", 10000)) / 100, int(battle.get("defender_morale_bp", 10000)) / 100,
		int(battle.get("defender_hull_lost", 0)), int(battle.get("defender_ships_sunk", 0)), (battle.get("defender_captured_ship_ids", []) as Array).size(),
	]


## Final report (04_N4 "Player Feedback") - the most recently completed
## battle either side of a war the player actually belongs to fought.
## Completed battle records are a permanent history snapshot (see
## _validate_naval_battle_data's own doc comment), so this reads straight
## from naval_battle_registry rather than needing any new persisted state.
func _refresh_battle_report() -> void:
	var tag := _player_country()
	var best_id := ""
	var best_end_day := -1
	var ids := simulation_controller.world.naval_battle_registry.keys()
	ids.sort()
	for raw_id in ids:
		var battle: Dictionary = simulation_controller.world.naval_battle_registry[raw_id]
		if String(battle.get("status", "")) != "completed":
			continue
		var war: Dictionary = simulation_controller.world.war_registry.get(String(battle.get("war_id", "")), {})
		if DiplomacySystemScript.side_in_war(war, tag) == 0:
			continue
		if int(battle.get("end_day", -1)) > best_end_day:
			best_end_day = int(battle.get("end_day", -1))
			best_id = String(raw_id)
	if best_id.is_empty():
		battle_report_label.text = ""
		return
	var battle: Dictionary = simulation_controller.world.naval_battle_registry[best_id]
	var reason := String(battle.get("end_reason", ""))
	battle_report_label.text = "Latest result at %s: %s side won on %s%s\nHull lost %d/%d · ships sunk %d/%d · captured %d/%d · pursuit damage %d" % [
		_province_name(int(battle.get("zone_id", -1))), String(battle.get("winner_side", "unknown")).capitalize(),
		SimulationDateScript.format_day(best_end_day),
		" (%s)" % reason.replace("_", " ") if not reason.is_empty() else "",
		int(battle.get("attacker_hull_lost", 0)), int(battle.get("defender_hull_lost", 0)),
		int(battle.get("attacker_ships_sunk", 0)), int(battle.get("defender_ships_sunk", 0)),
		(battle.get("attacker_captured_ship_ids", []) as Array).size(), (battle.get("defender_captured_ship_ids", []) as Array).size(),
		int(battle.get("pursuit_hull_lost", 0)),
	]


## "Province/port tooltip with required versus supplied power" (05_N5 "UI
## and Map Feedback") - shows for any selected coastal province, not only
## the player's own, since a blockade the player is imposing on someone
## else is just as relevant to see.
func _refresh_blockade_label() -> void:
	if _selected_province_id < 0:
		blockade_label.text = ""
		return
	var world := simulation_controller.world
	var bp := BlockadeSystemScript.province_blockade_bp(world, _selected_province_id)
	var required := BlockadeSystemScript.required_power(world, _selected_province_id, NavalDefinitionsScript.load_default())
	if bp <= 0:
		blockade_label.text = "%s · not blockaded (required power %d)" % [_province_name(_selected_province_id), required]
		return
	var tier := BlockadeSystemScript.blockade_tier(bp)
	var attacker_names: Array[String] = []
	for contributor in BlockadeSystemScript.blockade_contributors(world, _selected_province_id):
		var country_id := String(contributor.get("country_id", ""))
		attacker_names.append("%s (%d power)" % [simulation_controller.country_registry.display_name(country_id), int(contributor.get("effective_power", 0))])
	blockade_label.text = "%s · %s blockade (%d%%) · attacker%s %s · required power %d" % [
		_province_name(_selected_province_id), BLOCKADE_TIER_NAMES[tier], bp / 100,
		"s" if attacker_names.size() != 1 else "", ", ".join(attacker_names), required,
	]


func _show_blockade_map() -> void:
	if map_hud == null:
		return
	var world := simulation_controller.world
	var colors := {}
	var ids := world.province_states.keys()
	ids.sort()
	for raw_id in ids:
		var province_id := int(raw_id)
		var bp := BlockadeSystemScript.province_blockade_bp(world, province_id)
		if bp <= 0:
			continue
		colors[province_id] = Color(0.95, 0.78, 0.2).lerp(Color(0.85, 0.12, 0.1), float(bp) / 10000.0)
	map_hud.set_strategy_map_overlay("blockade", "Blockade: yellow light, red full - unblockaded coasts keep their normal colour.", colors)


func _refresh_port_panel() -> void:
	var tag := _player_country()
	var graph := MaritimeGraphScript.load_default()
	_refresh_blockade_label()
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


func _set_selected_fleet_home_port() -> void:
	var fleet_id := _selected_fleet_id()
	if not fleet_id.is_empty() and _selected_province_id >= 0:
		simulation_controller.set_fleet_home_port(_player_country(), fleet_id, _selected_province_id)


## FL2.5 rule 8: first press arms (see _refresh_scuttle_validation()), second
## press while already armed for this exact fleet submits the command.
func _scuttle_selected_fleet() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty():
		return
	if _scuttle_armed_fleet_id != fleet_id:
		_scuttle_armed_fleet_id = fleet_id
		_refresh_scuttle_validation()
		return
	_scuttle_armed_fleet_id = ""
	simulation_controller.scuttle_fleet(_player_country(), fleet_id)


func _cancel_selected_fleet_movement() -> void:
	var fleet_id := _selected_fleet_id()
	if not fleet_id.is_empty():
		simulation_controller.cancel_fleet_movement(fleet_id, _player_country())


func _assign_selected_admiral() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or admiral_option.item_count == 0:
		return
	simulation_controller.assign_admiral(_player_country(), fleet_id, String(admiral_option.get_item_metadata(admiral_option.selected)))


func _split_selected_ships() -> void:
	var fleet_id := _selected_fleet_id()
	var ship_ids := _selected_transfer_ship_ids()
	if fleet_id.is_empty() or ship_ids.is_empty():
		return
	simulation_controller.split_fleet(_player_country(), fleet_id, ship_ids)


func _transfer_selected_ships() -> void:
	var ship_ids := _selected_transfer_ship_ids()
	if ship_ids.is_empty() or target_fleet_option.item_count == 0 or target_fleet_option.selected < 0:
		return
	var target_fleet_id := String(target_fleet_option.get_item_metadata(target_fleet_option.selected))
	simulation_controller.transfer_ships(_player_country(), ship_ids, target_fleet_id)


func _merge_selected_fleets() -> void:
	var fleet_id := _selected_fleet_id()
	if fleet_id.is_empty() or target_fleet_option.item_count == 0 or target_fleet_option.selected < 0:
		return
	var target_fleet_id := String(target_fleet_option.get_item_metadata(target_fleet_option.selected))
	simulation_controller.merge_fleets(_player_country(), [fleet_id, target_fleet_id])
