extends SceneTree

## FL5.1: NavalTradeProtection - a stable, derived, zero-fabrication naval
## output for a future trade system that does not exist yet. Mirrors
## naval_blockade_test.gd's own fixture and eligibility-test shape closely,
## since NavalTradeProtection deliberately mirrors BlockadeSystem's own
## eligibility/effective-power rules (mission substituted).

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const NavalTradeProtectionScript = preload("res://scripts/simulation/naval_trade_protection.gd")
const SetFleetMissionCommandScript = preload("res://scripts/simulation/commands/set_fleet_mission_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR", STRAITS_OF_DOVER: ""},
		{"ENG": "England", "BUR": "Burgundy"}
	)
	EconomySystemScript.initialize_world(world)
	world.war_registry["war_1"] = {
		"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "BUR",
		"attackers": ["ENG"], "defenders": ["BUR"], "battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": CALAIS, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
	}
	return world


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, location_id: int, ship_count: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, location_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	var ship_ids: Array = []
	for index in ship_count:
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "war_galley", 0)
		ship_ids.append(ship_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _test_eligibility() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng", "ENG", STRAITS_OF_DOVER, 3)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng", "trade_protection").apply(world, events)
	_check(NavalTradeProtectionScript.is_fleet_eligible(world, "fleet_eng"), "BASELINE_NOT_ELIGIBLE", "an at-sea, trade_protection-mission, supplied, uncontested fleet must be eligible")

	var fleet := world.get_fleet("fleet_eng")
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	world.fleet_registry["fleet_eng"] = fleet
	_check(not NavalTradeProtectionScript.is_fleet_eligible(world, "fleet_eng"), "DOCKED_ELIGIBLE", "a docked fleet must not be eligible")
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	fleet["mission"] = "idle"
	world.fleet_registry["fleet_eng"] = fleet
	_check(not NavalTradeProtectionScript.is_fleet_eligible(world, "fleet_eng"), "WRONG_MISSION_ELIGIBLE", "a fleet not on trade_protection mission must not be eligible")
	fleet["mission"] = "trade_protection"
	fleet["supplied"] = false
	world.fleet_registry["fleet_eng"] = fleet
	_check(not NavalTradeProtectionScript.is_fleet_eligible(world, "fleet_eng"), "UNSUPPLIED_ELIGIBLE", "an unsupplied fleet must not be eligible")
	fleet["supplied"] = true
	world.fleet_registry["fleet_eng"] = fleet
	_check(NavalTradeProtectionScript.is_fleet_eligible(world, "fleet_eng"), "RESTORE_FIXTURE_FAILED", "fixture must be restored to eligible before continuing")

	_add_fleet(world, "fleet_bur_contest", "BUR", STRAITS_OF_DOVER, 1)
	_check(not NavalTradeProtectionScript.is_fleet_eligible(world, "fleet_eng"), "CONTESTED_ELIGIBLE", "an opposing at-sea fleet sharing the zone must eliminate eligibility, matching BlockadeSystem's own contested-zone rule")


func _test_effective_power_damage_scaling() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng", "ENG", STRAITS_OF_DOVER, 3)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng", "trade_protection").apply(world, events)
	var full_power := int(world.get_fleet("fleet_eng")["aggregate"]["total_attack"])
	_check(full_power > 0, "FIXTURE_ZERO_POWER", "fixture assumption: three war galleys must have positive total_attack")
	_check(NavalTradeProtectionScript.effective_power(world, "fleet_eng") == full_power, "UNDAMAGED_NOT_FULL_POWER", "an undamaged fleet must contribute its full attack power")

	for ship_id in world.fleet_ships("fleet_eng"):
		var ship := world.get_ship(ship_id)
		ship["hull_bp"] = 4999
		world.ship_registry[ship_id] = ship
	FleetSystemScript.recompute_aggregate(world, "fleet_eng")
	_check(NavalTradeProtectionScript.effective_power(world, "fleet_eng") == 0, "BELOW_THRESHOLD_NONZERO", "a fleet below the damage effectiveness threshold must contribute zero power")


func _test_assess_no_fleet() -> void:
	var world := _make_world()
	var result := NavalTradeProtectionScript.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(result["protection_score"]) == 0, "NO_FLEET_NONZERO_SCORE", "no fleet present must score zero")
	_check((result["eligible_fleet_ids"] as Array).is_empty(), "NO_FLEET_HAS_ELIGIBLE", "no fleet present must list no eligible fleets")
	_check(not bool(result["contested"]), "NO_FLEET_MARKED_CONTESTED", "no fleet present must not be marked contested")
	_check(String(result["reason"]).contains("No fleet"), "NO_FLEET_WRONG_REASON", "the reason must explain no fleet is assigned: %s" % result["reason"])


func _test_assess_eligible_and_summed() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng_a", "ENG", STRAITS_OF_DOVER, 2)
	_add_fleet(world, "fleet_eng_b", "ENG", STRAITS_OF_DOVER, 1)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_a", "trade_protection").apply(world, events)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_b", "trade_protection").apply(world, events)
	var power_a := NavalTradeProtectionScript.effective_power(world, "fleet_eng_a")
	var power_b := NavalTradeProtectionScript.effective_power(world, "fleet_eng_b")
	var result := NavalTradeProtectionScript.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(result["protection_score"]) == power_a + power_b, "SUM_WRONG", "protection_score must sum every eligible fleet's effective power, expected %d got %d" % [power_a + power_b, result["protection_score"]])
	_check((result["eligible_fleet_ids"] as Array).size() == 2, "ELIGIBLE_LIST_WRONG", "both fleets must be listed as eligible")
	_check(String(result["reason"]).contains("Protected by 2"), "SUM_REASON_WRONG", "the reason must name the count of protecting fleets: %s" % result["reason"])

	# A fleet at a different location must never contribute.
	_add_fleet(world, "fleet_eng_elsewhere", "ENG", CALAIS, 5)
	var fleet_elsewhere := world.get_fleet("fleet_eng_elsewhere")
	fleet_elsewhere["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	world.fleet_registry["fleet_eng_elsewhere"] = fleet_elsewhere
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_elsewhere", "trade_protection").apply(world, events)
	var result_after := NavalTradeProtectionScript.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(result_after["protection_score"]) == int(result["protection_score"]), "OTHER_LOCATION_LEAKED", "a fleet at a different location must not contribute to this zone's score")


func _test_assess_contested_and_unsupplied() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng", "ENG", STRAITS_OF_DOVER, 3)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng", "trade_protection").apply(world, events)
	_add_fleet(world, "fleet_bur_contest", "BUR", STRAITS_OF_DOVER, 1)
	var result := NavalTradeProtectionScript.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(result["protection_score"]) == 0, "CONTESTED_NONZERO_SCORE", "a contested zone must score zero, not merely reduced")
	_check(bool(result["contested"]), "CONTESTED_NOT_MARKED", "a contested zone must be marked contested")
	_check(String(result["reason"]).contains("contested"), "CONTESTED_WRONG_REASON", "the reason must explain the zone is contested: %s" % result["reason"])

	var world_b := _make_world()
	var events_b := SimulationEventBusScript.new()
	root.add_child(events_b)
	_add_fleet(world_b, "fleet_eng_b", "ENG", STRAITS_OF_DOVER, 3)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_b", "trade_protection").apply(world_b, events_b)
	var fleet_b := world_b.get_fleet("fleet_eng_b")
	fleet_b["supplied"] = false
	world_b.fleet_registry["fleet_eng_b"] = fleet_b
	var result_b := NavalTradeProtectionScript.assess(world_b, "ENG", STRAITS_OF_DOVER)
	_check(int(result_b["protection_score"]) == 0, "UNSUPPLIED_NONZERO_SCORE", "an unsupplied fleet must not contribute")
	_check(not bool(result_b["contested"]), "UNSUPPLIED_MARKED_CONTESTED", "an unsupplied fleet must not be reported as a contested-zone reason")
	_check(String(result_b["reason"]).contains("not currently eligible"), "UNSUPPLIED_WRONG_REASON", "the reason must explain the present fleet is not currently eligible: %s" % result_b["reason"])


func _test_pure_query_no_side_effects() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng", "ENG", STRAITS_OF_DOVER, 3)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng", "trade_protection").apply(world, events)
	var checksum_before := world.checksum()
	NavalTradeProtectionScript.assess(world, "ENG", STRAITS_OF_DOVER)
	NavalTradeProtectionScript.assess(world, "ENG", STRAITS_OF_DOVER)
	NavalTradeProtectionScript.effective_power(world, "fleet_eng")
	_check(world.checksum() == checksum_before, "ASSESS_MUTATED_STATE", "assess()/effective_power() must be pure queries - calling them repeatedly must never change world state, matching FL5.1's 'do not fabricate income' requirement")


func _run() -> void:
	_test_eligibility()
	_test_effective_power_damage_scaling()
	_test_assess_no_fleet()
	_test_assess_eligible_and_summed()
	_test_assess_contested_and_unsupplied()
	_test_pure_query_no_side_effects()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval trade protection test failed: %s" % failure)
		print("Naval trade protection test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval trade protection test passed. cases=eligibility,damage_scaling,no_fleet,summed,contested_unsupplied,pure_query")
	quit(0)
