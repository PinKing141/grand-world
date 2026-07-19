extends SceneTree

## FL3.1: focused transition tests for NavalThreatMap - the cache half of
## the threat/opportunity query (revision/day-boundary invalidation, cache
## hit/rebuild counters) and the four newly added raw inputs
## (friendly_power, recent_battle_bp, transport_stake, supply_days) that
## _zone_threat()/_zone_has_blockade_target() alone never computed before
## this packet. tests/naval_ai_threat_test.gd already covers the two
## tactical decisions (evade/blockade) those adapters back; this file proves
## the query and its cache in isolation, on the same lightweight Channel
## fixture (CALAIS/KENT/PICARDIE/STRAITS_OF_DOVER) that file and
## naval_combat_test.gd already establish as this pillar's shared precision
## fixture.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalThreatMapScript = preload("res://scripts/simulation/naval_threat_map.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271
# A real sea-zone neighbour of the Straits (confirmed against the live
# maritime graph) - MaritimeGraph.sea_neighbor_ids() only connects sea zone
# to sea zone, not port to sea zone, so a "neighbouring" hostile fleet for
# the half-weighted case must sit at another sea zone, not a port.
const STRAITS_NEIGHBOR_ZONE := 1269

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize({CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR", STRAITS_OF_DOVER: ""}, {"ENG": "England", "BUR": "Burgundy", "SCO": "Scotland"})
	world.war_registry["war_1"] = {
		"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "BUR",
		"attackers": ["ENG"], "defenders": ["BUR"], "battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": PICARDIE, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
	}
	return world


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, home_port_id: int, location_id: int, ship_count: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, home_port_id)
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


func _test_cache_hit_and_rebuild() -> void:
	var world := _make_world()
	_add_fleet(world, "fleet_bur", "BUR", PICARDIE, STRAITS_OF_DOVER, 3)
	var threat_map := NavalThreatMapScript.new()

	var first := threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(world.global_counters.get("naval_zone_cache_rebuilds", 0)) == 1, "CACHE_FIRST_CALL_NOT_REBUILD", "the first call for a given key must be a rebuild")
	_check(int(world.global_counters.get("naval_zone_cache_hits", 0)) == 0, "CACHE_FIRST_CALL_COUNTED_AS_HIT", "the first call must not be counted as a hit")

	var second := threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(world.global_counters.get("naval_zone_cache_rebuilds", 0)) == 1, "CACHE_SAME_DAY_REBUILT", "an identical same-day query must not trigger a second rebuild")
	_check(int(world.global_counters.get("naval_zone_cache_hits", 0)) == 1, "CACHE_SAME_DAY_NOT_HIT", "an identical same-day query must register as a cache hit")
	_check(second == first, "CACHE_HIT_RETURNED_DIFFERENT_VALUE", "a cache hit must return an identical assessment to the original")

	# A different zone or a different country is a different cache key, not
	# a hit against the first entry.
	threat_map.assess(world, "ENG", CALAIS)
	_check(int(world.global_counters.get("naval_zone_cache_rebuilds", 0)) == 2, "CACHE_DIFFERENT_ZONE_REUSED_ENTRY", "a different zone must be its own cache entry")
	threat_map.assess(world, "BUR", STRAITS_OF_DOVER)
	_check(int(world.global_counters.get("naval_zone_cache_rebuilds", 0)) == 3, "CACHE_DIFFERENT_COUNTRY_REUSED_ENTRY", "a different country must be its own cache entry")


func _test_day_boundary_invalidation() -> void:
	var world := _make_world()
	_add_fleet(world, "fleet_bur", "BUR", PICARDIE, STRAITS_OF_DOVER, 3)
	var threat_map := NavalThreatMapScript.new()
	threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(world.global_counters.get("naval_zone_cache_rebuilds", 0)) == 1, "DAY_BOUNDARY_FIXTURE_BAD", "fixture assumption: the first query must rebuild")

	world.current_day += 1
	threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(world.global_counters.get("naval_zone_cache_rebuilds", 0)) == 2, "DAY_BOUNDARY_NOT_INVALIDATED", "a new game day must invalidate every cached entry, even with no other world change")


func _test_explicit_invalidation() -> void:
	var world := _make_world()
	_add_fleet(world, "fleet_bur", "BUR", PICARDIE, STRAITS_OF_DOVER, 3)
	var threat_map := NavalThreatMapScript.new()
	threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(world.global_counters.get("naval_zone_cache_rebuilds", 0)) == 1, "EXPLICIT_INVALIDATION_FIXTURE_BAD", "fixture assumption: two same-day identical queries must rebuild once")

	NavalThreatMapScript.invalidate(world)
	threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(world.global_counters.get("naval_zone_cache_rebuilds", 0)) == 2, "EXPLICIT_INVALIDATION_IGNORED", "NavalThreatMap.invalidate() must force a rebuild on the very same day")


func _test_hostile_and_friendly_power() -> void:
	var world := _make_world()
	_add_fleet(world, "fleet_bur_direct", "BUR", PICARDIE, STRAITS_OF_DOVER, 4)
	_add_fleet(world, "fleet_bur_neighbor", "BUR", PICARDIE, STRAITS_NEIGHBOR_ZONE, 4)
	_add_fleet(world, "fleet_eng_own", "ENG", CALAIS, STRAITS_OF_DOVER, 2)
	var threat_map := NavalThreatMapScript.new()
	var assessment := threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	var direct_power := int((world.get_fleet("fleet_bur_direct")["aggregate"] as Dictionary)["total_attack"])
	var neighbor_power := int((world.get_fleet("fleet_bur_neighbor")["aggregate"] as Dictionary)["total_attack"])
	var own_power := int((world.get_fleet("fleet_eng_own")["aggregate"] as Dictionary)["total_attack"])
	var expected_hostile := direct_power + neighbor_power / 2
	_check(int(assessment["hostile_power"]) == expected_hostile, "HOSTILE_POWER_WRONG", "expected %d (direct + half-weighted neighbour), got %d" % [expected_hostile, assessment["hostile_power"]])
	_check(int(assessment["friendly_power"]) == own_power, "FRIENDLY_POWER_WRONG", "friendly_power must count this country's own directly-present fleet, got %d expected %d" % [assessment["friendly_power"], own_power])

	# An allied third country's fleet in the same zone must also count as
	# friendly support - a hostile or unrelated one must not.
	DiplomacySystemScript.set_relation(world, "ENG", "SCO", {"alliance": true})
	_add_fleet(world, "fleet_sco_ally", "SCO", KENT, STRAITS_OF_DOVER, 1)
	var ally_power := int((world.get_fleet("fleet_sco_ally")["aggregate"] as Dictionary)["total_attack"])
	NavalThreatMapScript.invalidate(world)
	var with_ally := threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(with_ally["friendly_power"]) == own_power + ally_power, "ALLIED_FLEET_NOT_COUNTED_AS_FRIENDLY", "an allied fleet in the same zone must count toward friendly_power")


func _test_recent_battle_decay() -> void:
	var world := _make_world()
	var threat_map := NavalThreatMapScript.new()
	world.current_day = 100

	var no_battle := threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(no_battle["recent_battle_bp"]) == 0, "NO_BATTLE_NONZERO", "a zone with no battle history must read zero recent-battle weight")

	world.naval_battle_registry["battle_recent"] = CampaignWorldStateScript.make_naval_battle_record("battle_recent", "war_1", STRAITS_OF_DOVER, 100)
	NavalThreatMapScript.invalidate(world)
	var fresh := threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(fresh["recent_battle_bp"]) == NavalThreatMapScript.RECENT_BATTLE_WEIGHT_BP, "FRESH_BATTLE_NOT_FULL_WEIGHT", "a battle that started today must read full recent-battle weight, got %d" % fresh["recent_battle_bp"])

	world.naval_battle_registry.clear()
	world.naval_battle_registry["battle_old"] = CampaignWorldStateScript.make_naval_battle_record("battle_old", "war_1", STRAITS_OF_DOVER, 100 - NavalThreatMapScript.RECENT_BATTLE_WINDOW_DAYS - 1)
	NavalThreatMapScript.invalidate(world)
	var stale := threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(stale["recent_battle_bp"]) == 0, "STALE_BATTLE_STILL_WEIGHTED", "a battle older than the recent-battle window must decay to zero, got %d" % stale["recent_battle_bp"])


func _test_transport_stake() -> void:
	var world := _make_world()
	var threat_map := NavalThreatMapScript.new()
	var before := threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(before["transport_stake"]) == 0, "NO_OPERATION_NONZERO_STAKE", "no active transport operation must read zero stake")

	world.transport_operation_registry["op_1"] = CampaignWorldStateScript.make_transport_operation_record("op_1", "ENG", "army_1", "fleet_1", CALAIS, KENT, 500, world.current_day, world.current_day + 2)
	var operation := world.get_transport_operation("op_1")
	operation["current_location_id"] = STRAITS_OF_DOVER
	world.transport_operation_registry["op_1"] = operation
	NavalThreatMapScript.invalidate(world)
	var with_op := threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(with_op["transport_stake"]) == 500, "TRANSPORT_STAKE_WRONG", "an operation sailing through this zone must contribute its reserved capacity, got %d" % with_op["transport_stake"])

	NavalThreatMapScript.invalidate(world)
	var elsewhere := threat_map.assess(world, "ENG", CALAIS)
	_check(int(elsewhere["transport_stake"]) == 0, "TRANSPORT_STAKE_LEAKED_TO_OTHER_ZONE", "an operation's stake must only count in its own current zone")


func _test_supply_days() -> void:
	var world := _make_world()
	var threat_map := NavalThreatMapScript.new()
	var assessment := threat_map.assess(world, "ENG", STRAITS_OF_DOVER)
	_check(int(assessment["supply_days"]) >= 0, "SUPPLY_DAYS_UNREACHABLE", "England owns Calais, one leg from the Straits - supply_days must be non-negative, got %d" % assessment["supply_days"])
	var far_assessment := threat_map.assess(world, "BUR", STRAITS_OF_DOVER)
	_check(int(far_assessment["supply_days"]) >= 0, "SUPPLY_DAYS_BUR_UNREACHABLE", "Burgundy owns Picardie, also one leg from the Straits - supply_days must be non-negative")


func _test_determinism() -> void:
	var world_a := _make_world()
	var world_b := _make_world()
	_add_fleet(world_a, "fleet_bur", "BUR", PICARDIE, STRAITS_OF_DOVER, 5)
	_add_fleet(world_b, "fleet_bur", "BUR", PICARDIE, STRAITS_OF_DOVER, 5)
	world_a.naval_battle_registry["battle_1"] = CampaignWorldStateScript.make_naval_battle_record("battle_1", "war_1", STRAITS_OF_DOVER, world_a.current_day)
	world_b.naval_battle_registry["battle_1"] = CampaignWorldStateScript.make_naval_battle_record("battle_1", "war_1", STRAITS_OF_DOVER, world_b.current_day)
	var map_a := NavalThreatMapScript.new()
	var map_b := NavalThreatMapScript.new()
	var assessment_a := map_a.assess(world_a, "ENG", STRAITS_OF_DOVER)
	var assessment_b := map_b.assess(world_b, "ENG", STRAITS_OF_DOVER)
	_check(assessment_a == assessment_b, "NOT_DETERMINISTIC", "two independent NavalThreatMap instances against identically-constructed worlds must produce identical assessments")


func _run() -> void:
	_test_cache_hit_and_rebuild()
	_test_day_boundary_invalidation()
	_test_explicit_invalidation()
	_test_hostile_and_friendly_power()
	_test_recent_battle_decay()
	_test_transport_stake()
	_test_supply_days()
	_test_determinism()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval threat map test failed: %s" % failure)
		print("Naval threat map test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval threat map test passed. cases=cache_hit_rebuild,day_boundary,explicit_invalidation,hostile_friendly_power,recent_battle_decay,transport_stake,supply_days,determinism")
	quit(0)
