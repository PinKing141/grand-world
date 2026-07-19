extends SceneTree

## FL2.5 rule 9: validate-rejection matrix, admiral/mission cleanup, no
## refund, deterministic ship removal, the fleet_scuttled event, duplicate
## command safety, final national fleet composition, and save/load checksum
## determinism. See docs/roadmap/naval/g1_finish_line/evidence/FL2_5_SCUTTLE_COMMAND.md.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const AssignAdmiralCommandScript = preload("res://scripts/simulation/commands/assign_admiral_command.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")
const ScuttleFleetCommandScript = preload("res://scripts/simulation/commands/scuttle_fleet_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR"},
		{"ENG": "England", "BUR": "Burgundy"}
	)
	EconomySystemScript.initialize_world(world)
	return world


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


func _add_character(world: CampaignWorldState, character_id: String, employer: String) -> void:
	# Save validation requires every character's dynasty_id to resolve in
	# dynasty_registry, including the empty-string "no dynasty" sentinel this
	# minimal fixture uses.
	if not world.dynasty_registry.has(""):
		world.dynasty_registry[""] = {}
	world.character_registry[character_id] = {
		"character_id": character_id, "name": character_id, "sex": "male",
		"birth": {"year": 1400, "month": 1, "day": 1},
		"alive": true, "death_day": -1, "death_cause": "",
		"culture": "Test", "religion": "Test", "dynasty_id": "",
		"father_id": "", "mother_id": "", "spouse_id": "", "former_spouses": [], "children": [],
		"employer_country": employer,
		"skills": {"diplomacy": 1, "martial": 1, "stewardship": 1, "intrigue": 1, "learning": 1},
		"traits": [], "health_bp": 8000, "fertility_bp": 5000, "stress_bp": 0,
		"titles": [], "claims": [], "event_cooldowns": {}, "last_birth_day": -9999,
		"commander_army_id": "", "admiral_fleet_id": "",
		"illness": "", "illness_until_day": -1, "opinion_modifiers": [],
	}


func _test_validate_rejection_matrix() -> void:
	var world := _make_world()
	_add_fleet(world, "fleet_docked", "ENG", CALAIS, ["war_galley"])

	_check(not ScuttleFleetCommandScript.new("ENG", "fleet_missing").validate(world).is_empty(), "SCUTTLE_UNKNOWN_FLEET_ALLOWED", "an unknown fleet must be rejected")
	_check(not ScuttleFleetCommandScript.new("BUR", "fleet_docked").validate(world).is_empty(), "SCUTTLE_NON_OWNER_ALLOWED", "a country that does not own the fleet must be rejected")

	for status in [CampaignWorldStateScript.FLEET_LOCATION_MOVING, CampaignWorldStateScript.FLEET_LOCATION_BATTLE, CampaignWorldStateScript.FLEET_LOCATION_RETREATING, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA]:
		var status_fleet_id := "fleet_status_%s" % status
		_add_fleet(world, status_fleet_id, "ENG", CALAIS, ["war_galley"])
		var fleet := world.get_fleet(status_fleet_id)
		fleet["location_status"] = status
		world.fleet_registry[status_fleet_id] = fleet
		_check(not ScuttleFleetCommandScript.new("ENG", status_fleet_id).validate(world).is_empty(), "SCUTTLE_STATUS_%s_ALLOWED" % status, "a fleet with location_status '%s' must be rejected" % status)

	_add_fleet(world, "fleet_intercept", "ENG", CALAIS, ["war_galley"])
	var intercepting := world.get_fleet("fleet_intercept")
	intercepting["mission"] = "intercept"
	world.fleet_registry["fleet_intercept"] = intercepting
	_check(not ScuttleFleetCommandScript.new("ENG", "fleet_intercept").validate(world).is_empty(), "SCUTTLE_INTERCEPT_ALLOWED", "an intercepting fleet must be rejected even while docked")

	var events := SimulationEventBusScript.new()
	root.add_child(events)
	world.army_registry["army_transport"] = CampaignWorldStateScript.make_army_record("army_transport", "ENG", KENT)
	_add_fleet(world, "fleet_transport", "ENG", KENT, ["transport_cog"])
	var create_transport := CreateTransportOperationCommandScript.new("ENG", "army_transport", "fleet_transport", CALAIS)
	_check(create_transport.validate(world).is_empty(), "SCUTTLE_TRANSPORT_FIXTURE_REJECTED", create_transport.validate(world))
	create_transport.apply(world, events)
	_check(not ScuttleFleetCommandScript.new("ENG", "fleet_transport").validate(world).is_empty(), "SCUTTLE_ACTIVE_TRANSPORT_ALLOWED", "a fleet holding a transport reservation must be rejected")

	_check(ScuttleFleetCommandScript.new("ENG", "fleet_docked").validate(world).is_empty(), "SCUTTLE_LEGAL_FLEET_REJECTED", "a docked, idle, unencumbered fleet must be accepted")


func _test_apply_cleanup_and_event() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_a", "ENG", CALAIS, ["war_galley", "light_caravel"])
	_add_fleet(world, "fleet_kent", "ENG", KENT, ["war_galley"])
	_add_character(world, "ch_admiral", "ENG")
	var assign := AssignAdmiralCommandScript.new("ENG", "fleet_a", "ch_admiral")
	_check(assign.validate(world).is_empty(), "SCUTTLE_ADMIRAL_FIXTURE_REJECTED", assign.validate(world))
	assign.apply(world, events)
	_check(String(world.character_registry["ch_admiral"]["admiral_fleet_id"]) == "fleet_a", "SCUTTLE_ADMIRAL_FIXTURE_BAD", "admiral was not assigned to fleet_a")

	var ships_before := world.country_ships("ENG").size()
	var treasury_before := int(world.country_runtime("ENG").get("treasury", 0))

	var scuttle_signals: Array = []
	events.fleet_scuttled.connect(func(fleet_id: String, country_tag: String, ship_count: int) -> void:
		scuttle_signals.append([fleet_id, country_tag, ship_count]))

	var scuttle := ScuttleFleetCommandScript.new("ENG", "fleet_a")
	_check(scuttle.validate(world).is_empty(), "SCUTTLE_HAPPY_PATH_REJECTED", scuttle.validate(world))
	scuttle.apply(world, events)

	_check(not world.fleet_registry.has("fleet_a"), "SCUTTLE_FLEET_NOT_ERASED", "fleet_a must be removed from the fleet registry")
	_check(not world.ship_registry.has("fleet_a_ship_0") and not world.ship_registry.has("fleet_a_ship_1"), "SCUTTLE_SHIPS_NOT_ERASED", "fleet_a's ships must be removed from the ship registry")
	_check(String(world.character_registry["ch_admiral"]["admiral_fleet_id"]).is_empty(), "SCUTTLE_ADMIRAL_NOT_CLEARED", "the admiral's admiral_fleet_id must be cleared")
	_check(int(world.country_runtime("ENG").get("treasury", -1)) == treasury_before, "SCUTTLE_REFUND_GRANTED", "scuttling must not credit any treasury refund")
	_check(scuttle_signals.size() == 1 and scuttle_signals[0][0] == "fleet_a" and scuttle_signals[0][1] == "ENG" and scuttle_signals[0][2] == 2, "SCUTTLE_EVENT_WRONG", "fleet_scuttled must fire exactly once with the fleet, owner, and ship count")
	_check(world.country_ships("ENG").size() == ships_before - 2, "SCUTTLE_NATIONAL_FLEET_WRONG", "England's national ship count must drop by exactly the scuttled fleet's ship count")
	_check(world.country_fleets("ENG") == ["fleet_kent"], "SCUTTLE_NATIONAL_FLEET_LEAK", "England's remaining fleet list must contain only the untouched fleet")


func _test_duplicate_command_rejected() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_dupe", "ENG", CALAIS, ["war_galley"])
	var scheduler := SimulationSchedulerScript.new(world, events)

	var rejections: Array = []
	events.command_rejected.connect(func(_command_id: int, command_type: String, reason: String) -> void:
		if command_type == "ScuttleFleetCommand":
			rejections.append(reason))

	scheduler.submit(ScuttleFleetCommandScript.new("ENG", "fleet_dupe"))
	scheduler.submit(ScuttleFleetCommandScript.new("ENG", "fleet_dupe"))
	var processed := scheduler.process_commands()

	_check(processed == 2, "SCUTTLE_DUPLICATE_FIXTURE_BAD", "expected both submitted commands to be processed, got %d" % processed)
	_check(not world.fleet_registry.has("fleet_dupe"), "SCUTTLE_DUPLICATE_FLEET_SURVIVED", "the fleet must be gone after the first scuttle applies")
	_check(rejections.size() == 1, "SCUTTLE_DUPLICATE_NOT_REJECTED", "the second, redundant scuttle must be rejected, not silently ignored or double-applied")


func _test_save_load_checksum() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_save", "ENG", CALAIS, ["war_galley"])
	_add_fleet(world, "fleet_kent", "ENG", KENT, ["war_galley"])
	_add_character(world, "ch_admiral_save", "ENG")
	var assign := AssignAdmiralCommandScript.new("ENG", "fleet_save", "ch_admiral_save")
	assign.apply(world, events)

	var scuttle := ScuttleFleetCommandScript.new("ENG", "fleet_save")
	_check(scuttle.validate(world).is_empty(), "SCUTTLE_SAVE_FIXTURE_REJECTED", scuttle.validate(world))
	scuttle.apply(world, events)

	var checksum := world.checksum()
	var saved := world.to_save_dict("naval_fleet_scuttle")
	var reloaded := _make_world()
	var load_error := reloaded.apply_save_dict(saved)
	_check(load_error.is_empty(), "SCUTTLE_SAVE_REJECTED", load_error)
	_check(load_error.is_empty() and reloaded.checksum() == checksum, "SCUTTLE_SAVE_CHECKSUM_DRIFT", "checksum changed after a scuttle-affected save round trip")
	_check(load_error.is_empty() and not reloaded.fleet_registry.has("fleet_save"), "SCUTTLE_SAVE_FLEET_RESURRECTED", "the scuttled fleet must not reappear after reload")
	_check(load_error.is_empty() and String(reloaded.character_registry["ch_admiral_save"]["admiral_fleet_id"]).is_empty(), "SCUTTLE_SAVE_ADMIRAL_DANGLING", "the admiral's cleared assignment must survive the save round trip")


func _run() -> void:
	_test_validate_rejection_matrix()
	_test_apply_cleanup_and_event()
	_test_duplicate_command_rejected()
	_test_save_load_checksum()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval fleet scuttle test failed: %s" % failure)
		print("Naval fleet scuttle test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval fleet scuttle test passed. cases=rejection_matrix,apply_cleanup,duplicate_command,save_load_checksum")
	quit(0)
