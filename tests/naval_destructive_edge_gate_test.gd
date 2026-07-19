extends SceneTree

## Destructive lifecycle audit for G1. Unlike focused unit tests, this keeps
## collecting independent failures so one broken cleanup path cannot hide the
## rest of the release-gate evidence.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")
const CancelTransportOperationCommandScript = preload("res://scripts/simulation/commands/cancel_transport_operation_command.gd")
const SplitFleetCommandScript = preload("res://scripts/simulation/commands/split_fleet_command.gd")
const MergeFleetsCommandScript = preload("res://scripts/simulation/commands/merge_fleets_command.gd")
const SetFleetMissionCommandScript = preload("res://scripts/simulation/commands/set_fleet_mission_command.gd")

const CALAIS := 87
const PICARDIE := 89
const KENT := 235
const STRAITS_OF_DOVER := 1271

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_world(owners := {CALAIS: "ENG", PICARDIE: "FRA", KENT: "ENG", STRAITS_OF_DOVER: ""}, names := {"ENG": "England", "FRA": "France"}) -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(owners, names, "naval_destructive_edge_gate", 14449999)
	EconomySystemScript.initialize_world(world)
	world.army_registry.clear()
	return world


func _make_fully_claimed_channel_world() -> CampaignWorldState:
	var owners := {STRAITS_OF_DOVER: ""}
	for port_id in MaritimeGraphScript.load_default().port_province_ids():
		owners[int(port_id)] = "FRA"
	owners[KENT] = "ENG"
	owners[CALAIS] = "ENG"
	owners[PICARDIE] = "FRA"
	return _make_world(owners, {"ENG": "England", "FRA": "France"})


func _add_army(world: CampaignWorldState, army_id: String, owner: String, province_id: int, regiments: int) -> void:
	var army := CampaignWorldStateScript.make_army_record(army_id, owner, province_id)
	army["regiment_count"] = regiments
	army["strength"] = regiments * 1000
	army["maximum_strength"] = regiments * 1000
	world.army_registry[army_id] = army


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, port_id: int, definitions: Array) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, port_id)
	var ship_ids: Array = []
	for index in range(definitions.size()):
		var ship_id := "%s_ship_%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, String(definitions[index]), world.current_day)
		ship_ids.append(ship_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _make_transport_scheduler(world: CampaignWorldState, events: SimulationEventBus) -> SimulationScheduler:
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world) -> void: FleetMovementSystemScript.advance_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world) -> void: TransportSystemScript.process_day(day_world, events))
	return scheduler


func _create_transport(world: CampaignWorldState, events: SimulationEventBus, army_id: String, fleet_id: String, destination: int) -> String:
	var command := CreateTransportOperationCommandScript.new("ENG", army_id, fleet_id, destination)
	_check(command.validate(world).is_empty(), "EDGE_FIXTURE_TRANSPORT_REJECTED", command.validate(world))
	if not command.validate(world).is_empty():
		return ""
	command.apply(world, events)
	return String(world.get_army(army_id).get("transport_operation_id", ""))


func _advance_to_state(scheduler: SimulationScheduler, world: CampaignWorldState, operation_id: String, state: String, maximum_days := 15) -> bool:
	for day in range(maximum_days + 1):
		if String(world.get_transport_operation(operation_id).get("state", "")) == state:
			return true
		if day < maximum_days:
			scheduler.advance_one_day()
	return false


func _test_total_carrier_loss() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_army(world, "army_loss", "ENG", KENT, 1)
	_add_fleet(world, "fleet_loss", "ENG", KENT, ["transport_cog"])
	var scheduler := _make_transport_scheduler(world, events)
	var operation_id := _create_transport(world, events, "army_loss", "fleet_loss", CALAIS)
	if operation_id.is_empty() or not _advance_to_state(scheduler, world, operation_id, CampaignWorldStateScript.TRANSPORT_STATE_SAILING):
		_check(false, "CARRIER_LOSS_FIXTURE", "operation never reached sailing")
		return
	for ship_id in world.fleet_ships("fleet_loss"):
		world.ship_registry.erase(ship_id)
	world.fleet_registry.erase("fleet_loss")
	TransportSystemScript.process_day(world, events)
	_check(not world.transport_operation_registry.has(operation_id), "TOTAL_CARRIER_LOSS_OPERATION_LEAK", "destroyed fleet left %s active" % operation_id)
	if world.army_registry.has("army_loss"):
		var army := world.get_army("army_loss")
		_check(String(army.get("transport_operation_id", "")).is_empty() and String(army.get("status", "")) != CampaignWorldStateScript.ARMY_STATUS_EMBARKED, "TOTAL_CARRIER_LOSS_ARMY_STRANDED", "army remains embarked and references destroyed carrier")


func _test_partial_capacity_and_organisation_lock() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	# Each cog carries 1000 authoritative regiment-capacity units. Reserving
	# 1500 against two cogs and disabling one produces a real 500-unit deficit.
	_add_army(world, "army_capacity", "ENG", KENT, 1500)
	_add_fleet(world, "fleet_capacity", "ENG", KENT, ["transport_cog", "transport_cog"])
	_add_fleet(world, "fleet_other", "ENG", KENT, ["war_galley"])
	var operation_id := _create_transport(world, events, "army_capacity", "fleet_capacity", CALAIS)
	if operation_id.is_empty():
		return
	var split := SplitFleetCommandScript.new("ENG", "fleet_capacity", ["fleet_capacity_ship_0"])
	var merge := MergeFleetsCommandScript.new("ENG", ["fleet_capacity", "fleet_other"])
	_check(not split.validate(world).is_empty(), "ACTIVE_TRANSPORT_SPLIT_ALLOWED", "split validation accepted a carrier with a reservation")
	_check(not merge.validate(world).is_empty(), "ACTIVE_TRANSPORT_MERGE_ALLOWED", "merge validation accepted a carrier with a reservation")
	var damaged := world.get_ship("fleet_capacity_ship_0")
	damaged["hull_bp"] = 4000
	world.ship_registry["fleet_capacity_ship_0"] = damaged
	TransportSystemScript.process_day(world, events)
	_check(world.army_registry.has("army_capacity"), "PARTIAL_CAPACITY_DESTROYED_ARMY", "a recoverable shortfall erased the army")
	if world.army_registry.has("army_capacity"):
		_check(int(world.get_army("army_capacity").get("regiment_count", 0)) == 1000, "PARTIAL_CAPACITY_WRONG_LOSS", "expected 1000 surviving regiments, got %d" % int(world.get_army("army_capacity").get("regiment_count", 0)))
	_check(int(world.get_transport_operation(operation_id).get("reserved_capacity", -1)) == 1000, "PARTIAL_CAPACITY_BAD_RESERVATION", "reservation did not shrink to surviving capacity")


func _test_destination_capture_and_cancellation() -> void:
	var world := _make_fully_claimed_channel_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_army(world, "army_capture", "ENG", KENT, 1)
	_add_fleet(world, "fleet_capture", "ENG", KENT, ["transport_cog"])
	var scheduler := _make_transport_scheduler(world, events)
	var operation_id := _create_transport(world, events, "army_capture", "fleet_capture", CALAIS)
	if operation_id.is_empty() or not _advance_to_state(scheduler, world, operation_id, CampaignWorldStateScript.TRANSPORT_STATE_SAILING):
		_check(false, "CAPTURE_FIXTURE", "operation never reached sailing")
		return
	world.set_province_owner(CALAIS, "FRA")
	world.set_province_controller(CALAIS, "FRA")
	for day in range(12):
		scheduler.advance_one_day()
	_check(not world.transport_operation_registry.has(operation_id), "CAPTURED_DESTINATION_OPERATION_LEAK", "operation did not recover after access/ownership loss")
	_check(world.army_registry.has("army_capture") and int(world.get_army("army_capture").get("current_province_id", -1)) == KENT, "CAPTURED_DESTINATION_BAD_RECOVERY", "army did not recover to Kent")

	var cancel_world := _make_world()
	var cancel_events := SimulationEventBusScript.new()
	root.add_child(cancel_events)
	_add_army(cancel_world, "army_cancel", "ENG", KENT, 1)
	_add_fleet(cancel_world, "fleet_cancel", "ENG", KENT, ["transport_cog"])
	var cancel_id := _create_transport(cancel_world, cancel_events, "army_cancel", "fleet_cancel", CALAIS)
	var cancel := CancelTransportOperationCommandScript.new("ENG", cancel_id)
	_check(cancel.validate(cancel_world).is_empty(), "EMBARK_CANCEL_REJECTED", cancel.validate(cancel_world))
	if cancel.validate(cancel_world).is_empty():
		cancel.apply(cancel_world, cancel_events)
	_check(cancel_world.transport_operation_registry.is_empty() and String(cancel_world.get_army("army_cancel").get("transport_operation_id", "")).is_empty(), "EMBARK_CANCEL_LEAK", "embark cancellation left references")

	var disembark_world := _make_world()
	var disembark_events := SimulationEventBusScript.new()
	root.add_child(disembark_events)
	_add_army(disembark_world, "army_disembark", "ENG", KENT, 1)
	_add_fleet(disembark_world, "fleet_disembark", "ENG", KENT, ["transport_cog"])
	var disembark_scheduler := _make_transport_scheduler(disembark_world, disembark_events)
	var disembark_id := _create_transport(disembark_world, disembark_events, "army_disembark", "fleet_disembark", CALAIS)
	_advance_to_state(disembark_scheduler, disembark_world, disembark_id, CampaignWorldStateScript.TRANSPORT_STATE_DISEMBARKING, 15)
	var cancel_disembark := CancelTransportOperationCommandScript.new("ENG", disembark_id)
	_check(cancel_disembark.validate(disembark_world).is_empty(), "DISEMBARK_CANCEL_UNSUPPORTED", cancel_disembark.validate(disembark_world))


func _test_retreat_and_save() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_retreat", "ENG", CALAIS, ["war_galley"])
	var fleet := world.get_fleet("fleet_retreat")
	fleet["location_id"] = STRAITS_OF_DOVER
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	world.fleet_registry["fleet_retreat"] = fleet
	NavalCombatSystemScript._begin_retreat(world, events, "fleet_retreat", STRAITS_OF_DOVER)
	_check(world.fleet_registry.has("fleet_retreat") and String(world.get_fleet("fleet_retreat").get("location_status", "")) == CampaignWorldStateScript.FLEET_LOCATION_RETREATING, "RETREAT_NOT_STARTED", "legal Calais retreat was not scheduled")
	var checksum := world.checksum()
	var saved := world.to_save_dict("naval_edge_gate")
	var reloaded := _make_world()
	var load_error := reloaded.apply_save_dict(saved)
	_check(load_error.is_empty(), "RETREAT_SAVE_REJECTED", load_error)
	_check(load_error.is_empty() and reloaded.checksum() == checksum, "RETREAT_SAVE_DRIFT", "retreat checksum changed after load")

	var graph := MaritimeGraphScript.load_default()
	var hostile_owners := {STRAITS_OF_DOVER: ""}
	for port_id in graph.port_province_ids():
		hostile_owners[int(port_id)] = "FRA"
	var isolated := _make_world(hostile_owners, {"ENG": "England", "FRA": "France"})
	var isolated_events := SimulationEventBusScript.new()
	root.add_child(isolated_events)
	_add_fleet(isolated, "fleet_isolated", "ENG", STRAITS_OF_DOVER, ["war_galley"])
	var isolated_fleet := isolated.get_fleet("fleet_isolated")
	isolated_fleet["location_id"] = STRAITS_OF_DOVER
	isolated_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	isolated.fleet_registry["fleet_isolated"] = isolated_fleet
	NavalCombatSystemScript._begin_retreat(isolated, isolated_events, "fleet_isolated", STRAITS_OF_DOVER)
	_check(not isolated.fleet_registry.has("fleet_isolated"), "NO_PORT_RETREAT_STRANDED", "fleet survived with no legal retreat port")


func _test_extinction_and_legacy_saves() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var definitions := CountryDepthDefinitionsScript.load_default()
	CountryDepthSystemScript.initialize_world(world, definitions)
	_add_fleet(world, "fleet_annexed", "FRA", PICARDIE, ["war_galley"])
	world.set_province_owner(PICARDIE, "ENG")
	world.set_province_controller(PICARDIE, "ENG")
	CountryDepthSystemScript.process_month(world, events, definitions)
	_check(String(world.country_runtime("FRA").get("country_status", "")) == "extinct", "ANNEX_FIXTURE_NOT_EXTINCT", "France did not become extinct")
	_check(world.country_fleets("FRA").is_empty(), "ANNEXED_COUNTRY_FLEET_LEAK", "extinct France still owns fleets")

	var current := _make_world().to_save_dict("legacy_gate")
	for schema in [5, 6, 7, 8]:
		var legacy := current.duplicate(true)
		legacy["schema_version"] = schema
		if schema <= 5:
			legacy.erase("fleet_registry")
			legacy.erase("ship_registry")
			legacy.erase("naval_construction_registry")
		if schema <= 6:
			legacy.erase("transport_operation_registry")
		if schema <= 7:
			legacy.erase("naval_battle_registry")
		if schema <= 8:
			legacy.erase("blockaded_provinces")
		var migrated := CampaignWorldStateScript.migrate_save_data(legacy)
		var target := _make_world()
		var error := target.apply_save_dict(migrated)
		_check(error.is_empty(), "LEGACY_SCHEMA_%d_REJECTED" % schema, error)
		_check(target.fleet_registry.is_empty() and target.transport_operation_registry.is_empty() and target.naval_battle_registry.is_empty(), "LEGACY_SCHEMA_%d_NAVAL_GHOSTS" % schema, "old save produced naval records")


func _test_ai_contract() -> void:
	var required_missions := ["none", "patrol", "intercept", "protect_transport", "transport", "blockade", "protect_coast", "return_to_port", "repair", "trade_protection"]
	for mission in required_missions:
		_check(SetFleetMissionCommandScript.VALID_MISSIONS.has(mission), "NAVAL_AI_MISSION_MISSING", "mission '%s' is unavailable to both AI and player" % mission)


func _run() -> void:
	_test_total_carrier_loss()
	_test_partial_capacity_and_organisation_lock()
	_test_destination_capture_and_cancellation()
	_test_retreat_and_save()
	_test_extinction_and_legacy_saves()
	_test_ai_contract()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval destructive edge gate failed: %s" % failure)
		print("Naval destructive edge gate FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval destructive edge gate passed. cases=carrier_loss,partial_capacity,organisation,capture,access,cancel,retreat,annex,migration,ai")
	quit(0)
