extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval transport recovery test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR"},
		{"ENG": "England", "BUR": "Burgundy"}
	)
	EconomySystemScript.initialize_world(world)
	return world


func _add_army(world: CampaignWorldState, army_id: String, owner: String, province_id: int, regiment_count: int) -> void:
	var army := CampaignWorldStateScript.make_army_record(army_id, owner, province_id)
	army["regiment_count"] = regiment_count
	army["strength"] = regiment_count
	army["maximum_strength"] = regiment_count
	world.army_registry[army_id] = army


func _add_fleet(world: CampaignWorldState, fleet_id: String, ship_ids: Array, owner: String, port_id: int, definition_id: String) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, port_id)
	for ship_id in ship_ids:
		world.ship_registry[String(ship_id)] = CampaignWorldStateScript.make_ship_record(String(ship_id), owner, fleet_id, definition_id, 0)
	var fleet := world.get_fleet(fleet_id)
	fleet["ship_ids"] = ship_ids.duplicate()
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _damage_ship(world: CampaignWorldState, ship_id: String) -> void:
	var ship := world.get_ship(ship_id)
	ship["hull_bp"] = TransportSystemScript.DAMAGED_CAPACITY_THRESHOLD_BP - 1
	world.ship_registry[ship_id] = ship


func _make_scheduler(world: CampaignWorldState, events: SimulationEventBus) -> SimulationScheduler:
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(
		func(day_world) -> void: FleetMovementSystemScript.advance_day(day_world, events)
	)
	scheduler.start_of_day_systems.append(
		func(day_world) -> void: TransportSystemScript.process_day(day_world, events)
	)
	return scheduler


func _run() -> void:
	# --- Capacity shortfall: partial loss, then total loss, stable order. ---
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)

	_add_army(world, "army_a", "ENG", CALAIS, 1200)
	_add_army(world, "army_b", "ENG", CALAIS, 800)
	_add_fleet(world, "fleet_1", ["s1", "s2"], "ENG", CALAIS, "transport_cog")
	_require(TransportSystemScript.usable_capacity(world, "fleet_1") == 2000, "two transport_cog ships must provide 2000 capacity")

	var create_a := CreateTransportOperationCommandScript.new("ENG", "army_a", "fleet_1", KENT)
	_require(create_a.validate(world).is_empty(), "army_a's embarkation must fit within capacity: %s" % create_a.validate(world))
	create_a.apply(world, events)
	var create_b := CreateTransportOperationCommandScript.new("ENG", "army_b", "fleet_1", KENT)
	_require(create_b.validate(world).is_empty(), "army_b's embarkation must exactly fill remaining capacity: %s" % create_b.validate(world))
	create_b.apply(world, events)
	_require(TransportSystemScript.available_capacity(world, "fleet_1") == 0, "both reservations together must exactly exhaust usable capacity")

	var operation_a_id := String(world.get_army("army_a")["transport_operation_id"])
	var operation_b_id := String(world.get_army("army_b")["transport_operation_id"])
	_require(operation_a_id < operation_b_id, "fixture assumption: army_a's operation must sort before army_b's for stable-order processing")

	# Damage one of two ships: usable capacity halves to 1000, a 1000-unit
	# deficit against 2000 reserved. The lower-sorted operation (army_a)
	# absorbs it first, up to its own reservation.
	_damage_ship(world, "s1")
	TransportSystemScript.process_day(world, events)
	var army_a := world.get_army("army_a")
	var army_b := world.get_army("army_b")
	_require(int(army_a["regiment_count"]) == 200, "army_a must lose exactly the deficit it can absorb (1200 - 1000)")
	_require(int(army_a["strength"]) == 200, "strength must scale down proportionally with regiment losses")
	_require(int(army_b["regiment_count"]) == 800, "army_b must be untouched while army_a alone can absorb the deficit")
	_require(int(world.get_transport_operation(operation_a_id)["reserved_capacity"]) == 200, "army_a's operation must trim its own reservation to match its survivors")
	_require(TransportSystemScript.reserved_capacity(world, "fleet_1") == TransportSystemScript.usable_capacity(world, "fleet_1"), "reserved capacity must never exceed usable capacity after resolution")

	# Damage the second ship too: usable capacity drops to 0. army_a (200
	# regiments left) is wiped out and destroyed outright; the remaining
	# 800-unit deficit then consumes army_b completely too.
	_damage_ship(world, "s2")
	TransportSystemScript.process_day(world, events)
	_require(not world.army_registry.has("army_a"), "an army reduced to zero regiments must be destroyed, not left at zero")
	_require(not world.army_registry.has("army_b"), "the remaining deficit must continue into the next operation in stable order")
	_require(world.get_transport_operation(operation_a_id).is_empty(), "a destroyed army's operation record must be removed")
	_require(world.get_transport_operation(operation_b_id).is_empty(), "a destroyed army's operation record must be removed")
	_require((world.get_fleet("fleet_1")["transport_operation_ids"] as Array).is_empty(), "the fleet must have no dangling operation references after both armies are lost")

	# --- Blocked-fleet recovery: destination captured mid-sail, reroutes to
	# the nearest port the country can still legally dock at (its own
	# Calais), then completes there instead of vanishing or hanging forever. ---
	var world2 := _make_world()
	var events2 := SimulationEventBusScript.new()
	root.add_child(events2)
	_add_army(world2, "army_c", "ENG", CALAIS, 1)
	_add_fleet(world2, "fleet_2", ["s3"], "ENG", CALAIS, "transport_cog")
	var scheduler2 := _make_scheduler(world2, events2)
	var create_c := CreateTransportOperationCommandScript.new("ENG", "army_c", "fleet_2", KENT)
	_require(create_c.validate(world2).is_empty(), "army_c's embarkation must be accepted: %s" % create_c.validate(world2))
	create_c.apply(world2, events2)
	var operation_c_id := String(world2.get_army("army_c")["transport_operation_id"])
	var embark_days := TransportSystemScript.embark_days(world2, "army_c", "fleet_2")

	for i in range(embark_days + 1):
		scheduler2.advance_one_day()
	_require(String(world2.get_transport_operation(operation_c_id)["state"]) == CampaignWorldStateScript.TRANSPORT_STATE_SAILING, "fixture assumption: the operation must be sailing before Kent is captured")
	_require(int(world2.get_fleet("fleet_2")["location_id"]) != KENT, "fixture assumption: the fleet must still be mid-crossing, not already at Kent")

	# Burgundy captures Kent mid-crossing - both owner and controller, since
	# NavalAccessPolicy prefers controller (the exact gotcha N2.3 already
	# documented for this identical fixture).
	world2.set_province_owner(KENT, "BUR")
	world2.set_province_controller(KENT, "BUR")

	for i in range(10):
		scheduler2.advance_one_day()
		if not world2.transport_operation_registry.has(operation_c_id) or not world2.army_registry.has("army_c"):
			break
	_require(world2.army_registry.has("army_c"), "the army must survive a blocked crossing via recovery, not be lost")
	var army_c := world2.get_army("army_c")
	_require(int(army_c["current_province_id"]) == CALAIS, "recovery must land the army at the nearest port it can still legally use - its own Calais")
	_require(String(army_c["status"]) == CampaignWorldStateScript.ARMY_STATUS_IDLE, "a recovered army must be idle again")
	_require(String(army_c["transport_operation_id"]).is_empty(), "a recovered army must have its operation reference cleared")
	_require(world2.get_transport_operation(operation_c_id).is_empty(), "recovery must remove the completed operation record")

	# --- Destruction path: an operation with no legal recovery anywhere is
	# explicitly destroyed rather than left dangling. Exercised directly
	# (constructing a real "no port anywhere is reachable" scenario on the
	# full baked world map is impractical - see the evidence doc). ---
	var world3 := _make_world()
	var events3 := SimulationEventBusScript.new()
	root.add_child(events3)
	_add_army(world3, "army_d", "ENG", CALAIS, 1)
	_add_fleet(world3, "fleet_3", ["s4"], "ENG", CALAIS, "transport_cog")
	var create_d := CreateTransportOperationCommandScript.new("ENG", "army_d", "fleet_3", KENT)
	create_d.apply(world3, events3)
	var operation_d_id := String(world3.get_army("army_d")["transport_operation_id"])
	TransportSystemScript._destroy_stranded_operation(world3, events3, operation_d_id, "test-forced destruction")
	_require(not world3.army_registry.has("army_d"), "a destroyed operation's army must be fully erased, never left at zero in an unqueryable state")
	_require(world3.get_transport_operation(operation_d_id).is_empty(), "a destroyed operation's record must be removed")
	_require((world3.get_fleet("fleet_3")["transport_operation_ids"] as Array).is_empty(), "a destroyed operation must clear the fleet's reverse reference")

	print("Naval transport recovery test passed. shortfall_stable_order=ok recovery_landing=%d" % CALAIS)
	quit(0)
