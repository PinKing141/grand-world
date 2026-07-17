extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const AssignAdmiralCommandScript = preload("res://scripts/simulation/commands/assign_admiral_command.gd")
const AssignCommanderCommandScript = preload("res://scripts/simulation/commands/assign_commander_command.gd")

const CALAIS := 87
const KENT := 235


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval admiral test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "ENG"},
		{"ENG": "England", "BUR": "Burgundy"}
	)
	return world


func _add_character(world: CampaignWorldState, character_id: String, employer: String, birth_year: int) -> void:
	world.character_registry[character_id] = {
		"character_id": character_id, "name": character_id, "sex": "male",
		"birth": {"year": birth_year, "month": 1, "day": 1},
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


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, port_id: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, port_id)


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)

	_add_fleet(world, "fleet_1", "ENG", CALAIS)
	_add_character(world, "ch_adult", "ENG", 1400)
	_add_character(world, "ch_minor", "ENG", 1440)
	_add_character(world, "ch_foreign", "BUR", 1400)

	# Rejections.
	_require(not AssignAdmiralCommandScript.new("ENG", "fleet_missing", "ch_adult").validate(world).is_empty(), "an unknown fleet must be rejected")
	_require(not AssignAdmiralCommandScript.new("BUR", "fleet_1", "ch_foreign").validate(world).is_empty(), "a country that does not own the fleet must be rejected")
	_require(not AssignAdmiralCommandScript.new("ENG", "fleet_1", "ch_missing").validate(world).is_empty(), "an unknown character must be rejected")
	_require(not AssignAdmiralCommandScript.new("ENG", "fleet_1", "ch_foreign").validate(world).is_empty(), "a character not employed by the issuing country must be rejected")
	_require(not AssignAdmiralCommandScript.new("ENG", "fleet_1", "ch_minor").validate(world).is_empty(), "a character under the adult age must be rejected")

	# Happy path.
	var assign := AssignAdmiralCommandScript.new("ENG", "fleet_1", "ch_adult")
	_require(assign.validate(world).is_empty(), "a valid admiral assignment must be accepted: %s" % assign.validate(world))
	assign.apply(world, events)
	_require(String(world.get_fleet("fleet_1")["admiral_id"]) == "ch_adult", "the fleet must record its new admiral")
	_require(String(world.character_registry["ch_adult"]["admiral_fleet_id"]) == "fleet_1", "the character must record its fleet assignment")

	# Exclusivity: an admiral cannot also command an army, in either
	# assignment order.
	world.army_registry["army_1"] = CampaignWorldStateScript.make_army_record("army_1", "ENG", CALAIS)
	_require(not AssignCommanderCommandScript.new("ENG", "army_1", "ch_adult").validate(world).is_empty(), "a fleet's admiral must not be assignable as an army commander")

	_add_character(world, "ch_commander", "ENG", 1400)
	var assign_commander := AssignCommanderCommandScript.new("ENG", "army_1", "ch_commander")
	_require(assign_commander.validate(world).is_empty(), "assigning a fresh character as army commander must be accepted: %s" % assign_commander.validate(world))
	assign_commander.apply(world, events)
	_require(not AssignAdmiralCommandScript.new("ENG", "fleet_1", "ch_commander").validate(world).is_empty(), "an army's commander must not be assignable as a fleet's admiral")

	# Reassignment: the same admiral can be re-confirmed to the same fleet,
	# but not stolen onto a second fleet while still assigned to the first.
	_require(AssignAdmiralCommandScript.new("ENG", "fleet_1", "ch_adult").validate(world).is_empty(), "re-assigning the same admiral to the same fleet must be accepted")
	_add_fleet(world, "fleet_2", "ENG", KENT)
	_require(not AssignAdmiralCommandScript.new("ENG", "fleet_2", "ch_adult").validate(world).is_empty(), "an admiral already commanding another fleet must be rejected")

	# Death clears both sides of the assignment.
	CharacterSystemScript.kill_character(world, events, "ch_adult", "test")
	_require(String(world.get_fleet("fleet_1")["admiral_id"]).is_empty(), "a dead admiral must be cleared from their fleet")

	# Save validation: a fleet whose admiral is unknown or dead must be
	# rejected, mirroring the existing army/commander corruption check.
	var assign_2 := AssignAdmiralCommandScript.new("ENG", "fleet_2", "ch_commander")
	world.army_registry.erase("army_1")
	world.character_registry["ch_commander"]["commander_army_id"] = ""
	_require(assign_2.validate(world).is_empty(), "assigning a freed character as a second fleet's admiral must be accepted: %s" % assign_2.validate(world))
	assign_2.apply(world, events)
	var saved := world.to_save_dict("test")
	var broken_fleet: Dictionary = (saved["fleet_registry"] as Dictionary)["fleet_2"]
	broken_fleet["admiral_id"] = "ch_does_not_exist"
	(saved["fleet_registry"] as Dictionary)["fleet_2"] = broken_fleet
	_require(not _make_world().apply_save_dict(saved).is_empty(), "a fleet admiral referencing an unknown character must be rejected")

	print("Naval admiral test passed. admiral=%s fleet=%s" % [String(world.get_fleet("fleet_2")["admiral_id"]), "fleet_2"])
	quit(0)
