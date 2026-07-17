extends SceneTree

## N3.4 gate coverage: save/load at every reachable transport state boundary
## (embarking was already covered by naval_transport_operation_test.gd;
## sailing, disembarking, and post-completion are new here), plus repeated
## Channel crossings proving zero orphan/duplicate/stranded state - 03_N3's
## own "England-France Channel operation repeats deterministically... " and
## "No army appears both on land and aboard" / "No capacity goes negative or
## remains reserved after terminal state" required tests. Frame-rate
## determinism for the same Channel operation is covered separately in
## simulation_frame_rate_determinism_test.gd (N3.4); seed-determinism is
## trivial here since embark timing and capacity math use no RNG.

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


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval transport gate test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "ENG"},
		{"ENG": "England"}
	)
	EconomySystemScript.initialize_world(world)
	return world


func _add_army(world: CampaignWorldState, army_id: String, province_id: int) -> void:
	world.army_registry[army_id] = CampaignWorldStateScript.make_army_record(army_id, "ENG", province_id)


func _add_fleet(world: CampaignWorldState, fleet_id: String, ship_id: String, port_id: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, "ENG", port_id)
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, "ENG", fleet_id, "transport_cog", 0)
	var fleet := world.get_fleet(fleet_id)
	fleet["ship_ids"] = [ship_id]
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _make_scheduler(world: CampaignWorldState, events: SimulationEventBus) -> SimulationScheduler:
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(
		func(day_world) -> void: FleetMovementSystemScript.advance_day(day_world, events)
	)
	scheduler.start_of_day_systems.append(
		func(day_world) -> void: TransportSystemScript.process_day(day_world, events)
	)
	return scheduler


## Runs one full Channel crossing on a fresh world and returns the (world,
## operation_id, army_id) tuple at each state boundary via callback, so the
## caller can save/load-verify without duplicating the journey's timing.
func _run_journey_to_each_boundary(check_at_embarking: Callable, check_at_sailing: Callable, check_at_disembarking: Callable, check_at_completed: Callable) -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_army(world, "army_1", CALAIS)
	_add_fleet(world, "fleet_1", "s1", CALAIS)
	var scheduler := _make_scheduler(world, events)
	var create := CreateTransportOperationCommandScript.new("ENG", "army_1", "fleet_1", KENT)
	_require(create.validate(world).is_empty(), "the journey fixture's embarkation must be legal: %s" % create.validate(world))
	create.apply(world, events)
	var operation_id := String(world.get_army("army_1")["transport_operation_id"])
	check_at_embarking.call(world, operation_id)

	var embark_days := TransportSystemScript.embark_days(world, "army_1", "fleet_1")
	for i in range(embark_days):
		scheduler.advance_one_day()
	_require(String(world.get_transport_operation(operation_id).get("state", "")) == CampaignWorldStateScript.TRANSPORT_STATE_SAILING, "fixture assumption: the operation must be sailing after the embark timer")
	check_at_sailing.call(world, operation_id)

	for i in range(3):
		scheduler.advance_one_day()
	_require(String(world.get_transport_operation(operation_id).get("state", "")) == CampaignWorldStateScript.TRANSPORT_STATE_DISEMBARKING, "fixture assumption: the operation must be disembarking after the Channel crossing")
	check_at_disembarking.call(world, operation_id)

	scheduler.advance_one_day()
	_require(world.get_transport_operation(operation_id).is_empty(), "fixture assumption: the operation must have completed")
	check_at_completed.call(world, operation_id)


func _assert_round_trips(world: CampaignWorldState, label: String) -> void:
	var checksum_before := world.checksum()
	var saved := world.to_save_dict("test")
	var reloaded := _make_world()
	_add_army(reloaded, "army_1", CALAIS)
	_add_fleet(reloaded, "fleet_1", "s1", CALAIS)
	var apply_error := reloaded.apply_save_dict(saved)
	_require(apply_error.is_empty(), "%s: save must apply cleanly: %s" % [label, apply_error])
	_require(reloaded.checksum() == checksum_before, "%s: reload must reproduce an identical checksum" % label)


func _run() -> void:
	# --- Save/load at every reachable state boundary. ---
	_run_journey_to_each_boundary(
		func(world, _op): _assert_round_trips(world, "embarking"),
		func(world, _op): _assert_round_trips(world, "sailing"),
		func(world, _op): _assert_round_trips(world, "disembarking"),
		func(world, _op): _assert_round_trips(world, "completed"),
	)

	# --- Repeated Channel crossings: zero orphan/duplicate/stranded state,
	# every time, in fresh worlds. ---
	for repetition in range(5):
		var world := _make_world()
		var events := SimulationEventBusScript.new()
		root.add_child(events)
		_add_army(world, "army_1", CALAIS)
		_add_fleet(world, "fleet_1", "s1", CALAIS)
		var scheduler := _make_scheduler(world, events)
		var create := CreateTransportOperationCommandScript.new("ENG", "army_1", "fleet_1", KENT)
		create.apply(world, events)
		for day in range(10):
			scheduler.advance_one_day()
		_require(world.army_registry.has("army_1"), "repetition %d: the army must never be lost on a clean crossing" % repetition)
		var army := world.get_army("army_1")
		_require(int(army["current_province_id"]) == KENT, "repetition %d: the army must land at Kent" % repetition)
		_require(String(army["status"]) == CampaignWorldStateScript.ARMY_STATUS_IDLE, "repetition %d: the army must be idle after landing" % repetition)
		_require(not bool(army["movement_locked"]), "repetition %d: the army must be unlocked after landing" % repetition)
		_require(String(army["transport_operation_id"]).is_empty(), "repetition %d: the army must have no dangling operation reference" % repetition)
		_require(world.transport_operation_registry.is_empty(), "repetition %d: no operation record may remain after completion" % repetition)
		_require((world.get_fleet("fleet_1")["transport_operation_ids"] as Array).is_empty(), "repetition %d: the fleet must have no dangling operation reference" % repetition)
		_require(TransportSystemScript.reserved_capacity(world, "fleet_1") == 0, "repetition %d: no capacity may remain reserved after a terminal state" % repetition)
		var armies_at_calais := world.armies_in_province(CALAIS)
		var armies_at_kent := world.armies_in_province(KENT)
		_require(not armies_at_calais.has("army_1"), "repetition %d: the army must not appear at its old province" % repetition)
		_require(armies_at_kent.has("army_1"), "repetition %d: the army must appear at its new province exactly once" % repetition)
		_require(armies_at_kent.count("army_1") == 1, "repetition %d: the army must not be duplicated in land-presence queries" % repetition)

	print("Naval transport gate test passed. boundaries=4 repetitions=5")
	quit(0)
