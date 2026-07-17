extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")
const CancelFleetMovementCommandScript = preload("res://scripts/simulation/commands/cancel_fleet_movement_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval fleet movement test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR"},
		{"ENG": "England", "BUR": "Burgundy"}
	)
	EconomySystemScript.initialize_world(world)
	return world


func _add_ship(world: CampaignWorldState, fleet_id: String, ship_id: String, owner: String, port_id: int, definition_id: String) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, port_id)
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, definition_id, 0)
	var fleet := world.get_fleet(fleet_id)
	fleet["ship_ids"] = [ship_id]
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _make_scheduler(world: CampaignWorldState, events: SimulationEventBus) -> SimulationScheduler:
	var scheduler := SimulationSchedulerScript.new(world, events)
	# Mirrors ArmyMovementSystem's registration point exactly (daily_systems,
	# before the day counter increments) - see simulation_controller.gd.
	scheduler.daily_systems.append(
		func(day_world) -> void: FleetMovementSystemScript.advance_day(day_world, events)
	)
	return scheduler


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := _make_scheduler(world, events)
	_add_ship(world, "fleet_1", "s1", "ENG", CALAIS, "war_galley")

	# Rejections.
	_require(not MoveFleetCommandScript.new("fleet_1", CALAIS, "ENG").validate(world).is_empty(), "moving to the current location must be rejected")
	_require(not MoveFleetCommandScript.new("fleet_1", PICARDIE, "ENG").validate(world).is_empty(), "moving to a foreign, unrelated port must be rejected")
	_require(not MoveFleetCommandScript.new("fleet_1", KENT, "BUR").validate(world).is_empty(), "a country that does not own the fleet must be rejected")

	# Happy path: Calais to Kent via the Straits of Dover, two one-day legs.
	# FleetMovementSystem checks next_arrival_day against current_day BEFORE
	# the scheduler increments the day counter (mirrors ArmyMovementSystem
	# exactly), so a 1-day leg only becomes visible on the SECOND
	# advance_one_day() call after it was queued.
	var move := MoveFleetCommandScript.new("fleet_1", KENT, "ENG")
	_require(move.validate(world).is_empty(), "a legal Channel crossing must be accepted: %s" % move.validate(world))
	scheduler.submit(move)
	scheduler.process_commands()
	var fleet := world.get_fleet("fleet_1")
	_require(String(fleet["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_MOVING, "the fleet must start moving immediately")
	_require((fleet["remaining_path"] as Array) == [STRAITS_OF_DOVER, KENT], "the route must cross the Straits of Dover")

	scheduler.advance_one_day()
	fleet = world.get_fleet("fleet_1")
	_require(int(fleet["location_id"]) == CALAIS, "the first tick only advances the day counter to the leg's arrival day, it does not yet resolve the leg")
	_require(String(fleet["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_MOVING, "the fleet must still be moving toward the Straits of Dover")

	scheduler.advance_one_day()
	fleet = world.get_fleet("fleet_1")
	_require(int(fleet["location_id"]) == STRAITS_OF_DOVER, "the second tick must resolve the leg into the Straits of Dover")
	_require(String(fleet["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_MOVING, "the fleet must still be moving toward Kent")

	# Access changes mid-route: Kent is captured by Burgundy before the fleet
	# arrives. NavalAccessPolicy prefers controller over owner, so both must
	# change to simulate a real capture.
	world.set_province_owner(KENT, "BUR")
	world.set_province_controller(KENT, "BUR")
	scheduler.advance_one_day()
	fleet = world.get_fleet("fleet_1")
	_require(int(fleet["location_id"]) == STRAITS_OF_DOVER, "a blocked fleet must halt at its last legal node, not teleport")
	_require(String(fleet["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, "a fleet halted mid-sea-zone must be at_sea, not docked")
	_require(int(fleet["next_arrival_day"]) == -1, "a blocked fleet must have no pending arrival")
	world.set_province_owner(KENT, "ENG")
	world.set_province_controller(KENT, "ENG")

	# CancelFleetMovementCommand mid-route.
	var world2 := _make_world()
	var events2 := SimulationEventBusScript.new()
	root.add_child(events2)
	var scheduler2 := _make_scheduler(world2, events2)
	_add_ship(world2, "fleet_2", "s2", "ENG", CALAIS, "war_galley")
	scheduler2.submit(MoveFleetCommandScript.new("fleet_2", KENT, "ENG"))
	scheduler2.process_commands()
	scheduler2.advance_one_day()
	scheduler2.advance_one_day()
	var mid_route_fleet := world2.get_fleet("fleet_2")
	_require(int(mid_route_fleet["location_id"]) == STRAITS_OF_DOVER, "fixture assumption: the fleet must be mid-route at the Straits of Dover")
	var cancel := CancelFleetMovementCommandScript.new("fleet_2", "ENG")
	_require(cancel.validate(world2).is_empty(), "cancelling a moving fleet must be accepted")
	scheduler2.submit(cancel)
	scheduler2.process_commands()
	var cancelled_fleet := world2.get_fleet("fleet_2")
	_require(String(cancelled_fleet["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, "a cancelled fleet must remain where it currently is")
	_require((cancelled_fleet["remaining_path"] as Array).is_empty(), "cancellation must discard the rest of the route")
	_require(not CancelFleetMovementCommandScript.new("fleet_2", "ENG").validate(world2).is_empty(), "cancelling an already-stationary fleet must be rejected")

	# Determinism: an identical order in a fresh world must resolve identically.
	var world3 := _make_world()
	var events3 := SimulationEventBusScript.new()
	root.add_child(events3)
	var scheduler3 := _make_scheduler(world3, events3)
	_add_ship(world3, "fleet_3", "s3", "ENG", CALAIS, "war_galley")
	scheduler3.submit(MoveFleetCommandScript.new("fleet_3", KENT, "ENG"))
	scheduler3.process_commands()
	for i in range(3):
		scheduler3.advance_one_day()
	var determinism_fleet := world3.get_fleet("fleet_3")
	_require(int(determinism_fleet["location_id"]) == KENT, "the identical order must complete to Kent in the identical number of ticks")
	_require(String(determinism_fleet["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_DOCKED, "arrival at a port must dock the fleet")

	print("Naval fleet movement test passed. calais_to_kent_days=2")
	quit(0)
