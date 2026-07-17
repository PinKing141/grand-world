extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")
const CancelTransportOperationCommandScript = preload("res://scripts/simulation/commands/cancel_transport_operation_command.gd")
const MoveArmyCommandScript = preload("res://scripts/simulation/commands/move_army_command.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval transport operation test failed: %s" % message)
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
	world.army_registry[army_id] = army


func _add_fleet(world: CampaignWorldState, fleet_id: String, ship_id: String, owner: String, port_id: int, definition_id: String) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, port_id)
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, definition_id, 0)
	var fleet := world.get_fleet(fleet_id)
	fleet["ship_ids"] = [ship_id]
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _make_scheduler(world: CampaignWorldState, events: SimulationEventBus) -> SimulationScheduler:
	var scheduler := SimulationSchedulerScript.new(world, events)
	# Mirrors simulation_controller.gd's registration order exactly: fleet
	# movement is a daily_system (before the day counter increments),
	# transport is a start_of_day_system (after it) - see that file's
	# scheduler wiring and transport_system.gd's process_day() doc comment.
	scheduler.daily_systems.append(
		func(day_world) -> void: FleetMovementSystemScript.advance_day(day_world, events)
	)
	scheduler.start_of_day_systems.append(
		func(day_world) -> void: TransportSystemScript.process_day(day_world, events)
	)
	return scheduler


func _find_non_coastal_province(world: CampaignWorldState) -> int:
	var graph := ProvinceGraph.load_default()
	for candidate_id in range(1, 3000):
		if graph.has_province(candidate_id) and graph.is_land(candidate_id) and graph.sea_neighbors(candidate_id).is_empty():
			return candidate_id
	return -1


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)

	_add_army(world, "army_1", "ENG", CALAIS, 1)
	_add_fleet(world, "fleet_1", "s1", "ENG", CALAIS, "transport_cog")

	# Rejections that do not depend on the happy-path fixtures below.
	_require(not CreateTransportOperationCommandScript.new("ENG", "army_missing", "fleet_1", KENT).validate(world).is_empty(), "an unknown army must be rejected")
	_require(not CreateTransportOperationCommandScript.new("ENG", "army_1", "fleet_missing", KENT).validate(world).is_empty(), "an unknown fleet must be rejected")
	_require(not CreateTransportOperationCommandScript.new("BUR", "army_1", "fleet_1", KENT).validate(world).is_empty(), "a country that does not own the army must be rejected")
	_require(not CreateTransportOperationCommandScript.new("ENG", "army_1", "fleet_1", CALAIS).validate(world).is_empty(), "a destination equal to the origin must be rejected")
	_require(not CreateTransportOperationCommandScript.new("ENG", "army_1", "fleet_1", PICARDIE).validate(world).is_empty(), "a foreign port with no access relation must be rejected (no legal sea route)")

	var non_coastal := _find_non_coastal_province(world)
	if non_coastal >= 0:
		_require(not CreateTransportOperationCommandScript.new("ENG", "army_1", "fleet_1", non_coastal).validate(world).is_empty(), "a non-port destination must be rejected")

	_add_army(world, "army_far", "ENG", KENT, 1)
	_require(not CreateTransportOperationCommandScript.new("ENG", "army_far", "fleet_1", CALAIS).validate(world).is_empty(), "a fleet not docked in the army's own province must be rejected")

	_add_army(world, "army_no_capacity", "ENG", CALAIS, 1)
	_add_fleet(world, "fleet_no_capacity", "s_galley", "ENG", CALAIS, "war_galley")
	_require(not CreateTransportOperationCommandScript.new("ENG", "army_no_capacity", "fleet_no_capacity", KENT).validate(world).is_empty(), "a fleet with zero transport capacity must be rejected")

	# Embarkation: create() only reaches "embarking" - army stays land-present
	# and locked until the embark-timing formula's completion_day.
	var usable_before := TransportSystemScript.usable_capacity(world, "fleet_1")
	var create := CreateTransportOperationCommandScript.new("ENG", "army_1", "fleet_1", KENT)
	_require(create.validate(world).is_empty(), "a legal transport operation must be accepted: %s" % create.validate(world))
	create.apply(world, events)
	var army := world.get_army("army_1")
	var operation_id := String(army["transport_operation_id"])
	_require(not operation_id.is_empty(), "embarking must record the operation on the army")
	_require(String(army["status"]) == CampaignWorldStateScript.ARMY_STATUS_EMBARKING, "a freshly created operation must only reach the embarking status")
	_require(bool(army["movement_locked"]), "an embarking army must be movement-locked")
	_require(world.armies_in_province(CALAIS).has("army_1"), "an embarking army must still be land-present until the embark timer completes")
	var operation := world.get_transport_operation(operation_id)
	_require(String(operation["state"]) == CampaignWorldStateScript.TRANSPORT_STATE_EMBARKING, "a freshly created operation must be in the embarking state")
	_require(int(operation["reserved_capacity"]) == 1, "reserved capacity must equal the army's authoritative regiment count")
	_require((world.get_fleet("fleet_1")["transport_operation_ids"] as Array) == [operation_id], "the fleet must record the reverse reference")
	_require(TransportSystemScript.available_capacity(world, "fleet_1") == usable_before - 1, "available capacity must drop by exactly the reserved amount immediately, before embarking even finishes")
	_require(not MoveFleetCommandScript.new("fleet_1", PICARDIE, "ENG").validate(world).is_empty(), "a fleet carrying a transport operation must reject independent movement orders")

	# An already-embarking army cannot be embarked again, and cancellation
	# while embarking is a clean, penalty-free return.
	_require(not CreateTransportOperationCommandScript.new("ENG", "army_1", "fleet_1", KENT).validate(world).is_empty(), "an already-embarking army must be rejected")
	var cancel := CancelTransportOperationCommandScript.new("ENG", operation_id)
	_require(cancel.validate(world).is_empty(), "cancelling an embarking operation must be accepted: %s" % cancel.validate(world))
	cancel.apply(world, events)
	army = world.get_army("army_1")
	_require(String(army["transport_operation_id"]).is_empty(), "cancellation must clear the army's operation reference")
	_require(String(army["status"]) == CampaignWorldStateScript.ARMY_STATUS_IDLE, "a cancelled army must return to idle")
	_require(not bool(army["movement_locked"]), "a cancelled army must no longer be movement-locked")
	_require(world.get_transport_operation(operation_id).is_empty(), "cancellation must remove the operation record")
	_require((world.get_fleet("fleet_1")["transport_operation_ids"] as Array).is_empty(), "cancellation must clear the fleet's reverse reference")
	_require(TransportSystemScript.available_capacity(world, "fleet_1") == usable_before, "cancellation must fully release reserved capacity")
	_require(world.armies_in_province(CALAIS).has("army_1"), "a cancelled army must reappear in land-presence queries")
	_require(not CancelTransportOperationCommandScript.new("ENG", operation_id).validate(world).is_empty(), "cancelling an operation that no longer exists must be rejected")

	# Full journey: Calais -> embark -> sail via the Straits of Dover -> dock
	# at Kent -> disembark -> the army lands, exactly as MoveFleetCommand's
	# own Channel fixture already proves for bare fleets (N2.3).
	var scheduler := _make_scheduler(world, events)
	var journey := CreateTransportOperationCommandScript.new("ENG", "army_1", "fleet_1", KENT)
	_require(journey.validate(world).is_empty(), "the journey's create must be accepted: %s" % journey.validate(world))
	journey.apply(world, events)
	var journey_operation_id := String(world.get_army("army_1")["transport_operation_id"])
	var embark_days := TransportSystemScript.embark_days(world, "army_1", "fleet_1")
	_require(embark_days == 3, "one regiment, an undamaged fleet, and no commander must cost exactly the base embark days")

	for i in range(embark_days):
		scheduler.advance_one_day()
	army = world.get_army("army_1")
	_require(String(army["status"]) == CampaignWorldStateScript.ARMY_STATUS_EMBARKED, "the embark timer must have expired and put the army aboard")
	_require(not world.armies_in_province(CALAIS).has("army_1"), "an embarked (aboard) army must not be land-present")
	operation = world.get_transport_operation(journey_operation_id)
	_require(String(operation["state"]) == CampaignWorldStateScript.TRANSPORT_STATE_SAILING, "the operation must now be sailing")
	_require(String(world.get_fleet("fleet_1")["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_MOVING, "embark completion must have ordered the fleet to sail")

	# The fleet's own Calais->Kent crossing takes two one-day legs, observable
	# after three ticks given FleetMovementSystem's check-before-increment
	# timing (N2.3's naval_fleet_movement_test.gd established this exact
	# pattern) - then one more tick for the fixed one-day disembark delay.
	for i in range(4):
		scheduler.advance_one_day()
	army = world.get_army("army_1")
	_require(int(army["current_province_id"]) == KENT, "the army must have disembarked at Kent")
	_require(String(army["status"]) == CampaignWorldStateScript.ARMY_STATUS_IDLE, "a completed transport must leave the army idle")
	_require(not bool(army["movement_locked"]), "a completed transport must release the movement lock")
	_require(String(army["transport_operation_id"]).is_empty(), "a completed transport must clear the army's operation reference")
	_require(world.armies_in_province(KENT).has("army_1"), "the army must be land-present at its new province")
	_require(world.get_transport_operation(journey_operation_id).is_empty(), "a completed operation must be removed from the registry")
	_require((world.get_fleet("fleet_1")["transport_operation_ids"] as Array).is_empty(), "a completed operation must clear the fleet's reverse reference")
	_require(TransportSystemScript.available_capacity(world, "fleet_1") == usable_before, "capacity must be fully released on completion")

	# Ordinary army orders reject an embarked (aboard) army with the exact
	# documented reason - re-verified against a real mid-journey army, not
	# just the instantaneous N3.1 fixture.
	var world2 := _make_world()
	var events2 := SimulationEventBusScript.new()
	root.add_child(events2)
	_add_army(world2, "army_2", "ENG", CALAIS, 1)
	_add_fleet(world2, "fleet_2", "s2", "ENG", CALAIS, "transport_cog")
	var scheduler2 := _make_scheduler(world2, events2)
	var op2 := CreateTransportOperationCommandScript.new("ENG", "army_2", "fleet_2", KENT)
	op2.apply(world2, events2)
	for i in range(3):
		scheduler2.advance_one_day()
	var move_failure := MoveArmyCommandScript.new("army_2", PICARDIE, "ENG").validate(world2)
	_require(move_failure == "The army is embarked.", "an embarked army must reject movement with the exact documented reason, got: %s" % move_failure)

	# Save/load: a fresh world, mid-embark (not yet aboard), round trips.
	var save_world := _make_world()
	var save_events := SimulationEventBusScript.new()
	root.add_child(save_events)
	_add_army(save_world, "army_1", "ENG", CALAIS, 1)
	_add_fleet(save_world, "fleet_1", "s1", "ENG", CALAIS, "transport_cog")
	_add_army(save_world, "army_far", "ENG", KENT, 1)
	var scheduler3 := SimulationSchedulerScript.new(save_world, save_events)
	scheduler3.submit(CreateTransportOperationCommandScript.new("ENG", "army_1", "fleet_1", KENT))
	scheduler3.process_commands()
	_require(save_world.transport_operation_registry.size() == 1, "the fixture must actually create an operation before saving")
	var checksum_before := save_world.checksum()
	var saved := save_world.to_save_dict("test")
	var reloaded := _make_world()
	_add_army(reloaded, "army_1", "ENG", CALAIS, 1)
	_add_fleet(reloaded, "fleet_1", "s1", "ENG", CALAIS, "transport_cog")
	var apply_error := reloaded.apply_save_dict(saved)
	_require(apply_error.is_empty(), "a valid transport save must apply cleanly: %s" % apply_error)
	_require(reloaded.checksum() == checksum_before, "reloading a save must reproduce an identical checksum")
	_require(reloaded.transport_operation_registry.size() == 1, "the reloaded world must keep the one active operation")

	# Corruption rejection: a transport operation whose army reference is dangling.
	var broken_operations: Dictionary = (saved["transport_operation_registry"] as Dictionary).duplicate(true)
	for raw_id in broken_operations:
		var broken: Dictionary = broken_operations[raw_id]
		broken["army_id"] = "army_does_not_exist"
		broken_operations[raw_id] = broken
	var corrupted_save := saved.duplicate(true)
	corrupted_save["transport_operation_registry"] = broken_operations
	_require(not _make_world().apply_save_dict(corrupted_save).is_empty(), "a transport operation referencing an unknown army must be rejected")

	# Corruption rejection: an army claims an operation the operation registry
	# does not have.
	var dangling_army_save := saved.duplicate(true)
	var dangling_armies: Dictionary = (dangling_army_save["army_registry"] as Dictionary).duplicate(true)
	var stray_army: Dictionary = (dangling_armies["army_far"] as Dictionary).duplicate(true)
	stray_army["transport_operation_id"] = "transport_does_not_exist"
	dangling_armies["army_far"] = stray_army
	dangling_army_save["army_registry"] = dangling_armies
	_require(not _make_world().apply_save_dict(dangling_army_save).is_empty(), "an army referencing an unknown transport operation must be rejected")

	# Schema migration: a pre-transport (schema 6) save must migrate cleanly.
	var legacy := saved.duplicate(true)
	legacy["schema_version"] = 6
	legacy.erase("transport_operation_registry")
	var migrated := CampaignWorldStateScript.migrate_save_data(legacy)
	_require(int(migrated["schema_version"]) == CampaignWorldStateScript.SAVE_SCHEMA_VERSION, "schema 6 saves must migrate to the current schema")
	_require((migrated["transport_operation_registry"] as Dictionary).is_empty(), "migrated pre-transport saves must start with no operations")

	print("Naval transport operation test passed. schema=%d embark_days=%d" % [CampaignWorldStateScript.SAVE_SCHEMA_VERSION, embark_days])
	quit(0)
