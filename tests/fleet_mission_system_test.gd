extends SceneTree

## N6A: FleetMissionSystem's mission state machine - "return_to_port" and
## "repair" are the only two missions this slice added to
## SetFleetMissionCommand.VALID_MISSIONS (patrol/intercept/protect_transport/
## protect_coast need a threat map that doesn't exist yet; trade_protection
## has nothing to protect). Both are meant to be self-completing: assign the
## mission, and the fleet either already qualifies or drives itself there,
## then clears back to "idle" without further orders.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const FleetMissionSystemScript = preload("res://scripts/simulation/fleet_mission_system.gd")
const SetFleetMissionCommandScript = preload("res://scripts/simulation/commands/set_fleet_mission_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Fleet mission system test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize({CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR", STRAITS_OF_DOVER: ""}, {"ENG": "England", "BUR": "Burgundy"})
	return world


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, home_port_id: int, location_id: int, location_status: String, hull_bp: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, home_port_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = location_status
	var ship_id := "%s_s0" % fleet_id
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "war_galley", 0)
	world.ship_registry[ship_id]["hull_bp"] = hull_bp
	fleet["ship_ids"] = [ship_id]
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _run() -> void:
	# --- Repair mission: a fully healed fleet on the "repair" mission clears
	# to idle immediately; a still-damaged one is left alone. ---
	var world_a := _make_world()
	var events_a := SimulationEventBusScript.new()
	root.add_child(events_a)
	_add_fleet(world_a, "fleet_healed", "ENG", CALAIS, CALAIS, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 10000)
	_add_fleet(world_a, "fleet_damaged", "ENG", CALAIS, CALAIS, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 4000)
	world_a.fleet_registry["fleet_healed"]["mission"] = "repair"
	world_a.fleet_registry["fleet_damaged"]["mission"] = "repair"
	var mission_changes_a: Array = []
	events_a.fleet_mission_changed.connect(func(fleet_id, mission): mission_changes_a.append([fleet_id, mission]))
	FleetMissionSystemScript.process_day(world_a, events_a)
	_require(String(world_a.get_fleet("fleet_healed")["mission"]) == "idle", "a fully healed fleet on the repair mission must clear to idle")
	_require(String(world_a.get_fleet("fleet_damaged")["mission"]) == "repair", "a still-damaged fleet must remain on the repair mission")
	_require(mission_changes_a.size() == 1 and mission_changes_a[0][0] == "fleet_healed", "only the healed fleet's mission change must be reported")

	# --- Return-to-port mission: a fleet already docked at a port legal for
	# it clears to idle immediately, with no move order needed. ---
	var world_b := _make_world()
	var events_b := SimulationEventBusScript.new()
	root.add_child(events_b)
	_add_fleet(world_b, "fleet_home", "ENG", CALAIS, CALAIS, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 10000)
	world_b.fleet_registry["fleet_home"]["mission"] = "return_to_port"
	FleetMissionSystemScript.process_day(world_b, events_b)
	_require(String(world_b.get_fleet("fleet_home")["mission"]) == "idle", "a fleet already at a legal port must clear return_to_port immediately")

	# --- Return-to-port mission: a fleet stranded at sea with no orders gets
	# routed to its own nearest legal port, then clears to idle on arrival -
	# the same bounded-recovery shape N3.3/N4.3 already established, reused
	# a third time here. ---
	var world_c := _make_world()
	var events_c := SimulationEventBusScript.new()
	root.add_child(events_c)
	_add_fleet(world_c, "fleet_stranded", "ENG", CALAIS, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 10000)
	world_c.fleet_registry["fleet_stranded"]["mission"] = "return_to_port"
	var scheduler_c := SimulationSchedulerScript.new(world_c, events_c)
	scheduler_c.daily_systems.append(func(day_world): FleetMovementSystemScript.advance_day(day_world, events_c))
	scheduler_c.start_of_day_systems.append(func(day_world): FleetMissionSystemScript.process_day(day_world, events_c))
	for i in range(10):
		scheduler_c.advance_one_day()
		if String(world_c.get_fleet("fleet_stranded")["mission"]) == "idle":
			break
	_require(String(world_c.get_fleet("fleet_stranded")["mission"]) == "idle", "a stranded fleet on return_to_port must eventually reach a legal port and clear its mission")
	_require(String(world_c.get_fleet("fleet_stranded")["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_DOCKED, "the fleet must actually be docked once its mission clears")
	_require(int(world_c.get_fleet("fleet_stranded")["location_id"]) == CALAIS, "England's own fleet must return to an England-owned port")

	# --- The command itself: return_to_port and repair must now be legal
	# SetFleetMissionCommand targets, exactly like blockade/idle already are. ---
	var world_d := _make_world()
	_add_fleet(world_d, "fleet_cmd", "ENG", CALAIS, CALAIS, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 10000)
	for mission in ["repair", "return_to_port"]:
		var command := SetFleetMissionCommandScript.new("ENG", "fleet_cmd", mission)
		_require(command.validate(world_d).is_empty(), "%s must be a valid fleet mission: %s" % [mission, command.validate(world_d)])

	print("Fleet mission system test passed.")
	quit(0)
