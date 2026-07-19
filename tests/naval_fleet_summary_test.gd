extends SceneTree

## FL2.1 closure (fleet-summary panel packet): the new authoritative queries
## the panel is built on - FleetSystem.recompute_aggregate()'s family_counts
## and crew_readiness_bp, FleetSystem.class_counts_for_ships()/
## format_class_counts(), FleetSystem.route_completion_day(), and
## FleetLogisticsSystem.repairing_ship_count() - tested independently of the
## UI that reads them, per this project's "UI and AI must not mutate
## registries directly" / "focused automated tests for state-changing
## behaviour" rules. Covers a mixed-family fleet, sailor-cost-weighted crew
## readiness, a partially traversed multi-leg route, passive repair with no
## repair mission set, and the empty/default-aggregate edge case.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetLogisticsSystemScript = preload("res://scripts/simulation/fleet_logistics_system.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
# A real three-leg synthetic route (CALAIS -> STRAITS_OF_DOVER -> two more
# sea zones) used to test route_completion_day() summing more than just the
# immediate next waypoint. Leg costs confirmed against the live maritime
# graph: CALAIS->1271 = 1 day, 1271->1269 = 3 days, 1269->1270 = 3 days.
const STRAITS_OF_DOVER := 1271
const ROUTE_NODE_B := 1269
const ROUTE_NODE_C := 1270

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


func _add_fleet(world: CampaignWorldState, fleet_id: String, port_id: int, definitions: Array) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, "ENG", port_id)
	var ship_ids: Array = []
	for index in range(definitions.size()):
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, "ENG", fleet_id, String(definitions[index]), 0)
		ship_ids.append(ship_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _test_mixed_family_counts() -> void:
	var world := _make_world()
	_add_fleet(world, "fleet_mixed", CALAIS, ["heavy_galleon", "light_caravel", "war_galley", "transport_cog"])
	var aggregate: Dictionary = world.get_fleet("fleet_mixed")["aggregate"]
	var counts: Dictionary = aggregate["family_counts"]
	_check(int(counts.get("heavy", -1)) == 1 and int(counts.get("light", -1)) == 1 and int(counts.get("galley", -1)) == 1 and int(counts.get("transport", -1)) == 1, "MIXED_FAMILY_COUNTS_WRONG", "expected exactly one ship per family, got %s" % counts)
	_check(FleetSystemScript.format_class_counts(counts) == "1 heavy, 1 light, 1 galley, 1 transport", "MIXED_FAMILY_FORMAT_WRONG", "unexpected formatting: %s" % FleetSystemScript.format_class_counts(counts))

	# class_counts_for_ships() must agree with recompute_aggregate() for the
	# same ship set - the FL2.2 organisation preview and the fleet-summary
	# panel must never disagree about what a given set of ships contains.
	var all_ship_ids := world.fleet_ships("fleet_mixed")
	var arbitrary_counts := FleetSystemScript.class_counts_for_ships(world, all_ship_ids)
	_check(arbitrary_counts == counts, "CLASS_COUNTS_FOR_SHIPS_DISAGREES", "class_counts_for_ships() must match recompute_aggregate()'s family_counts for the same ships")
	_check(FleetSystemScript.format_class_counts({}) == "no ships", "EMPTY_CLASS_COUNTS_FORMAT_WRONG", "an empty/zero counts dict must format as 'no ships'")


func _test_crew_readiness_weighting() -> void:
	var world := _make_world()
	_add_fleet(world, "fleet_crew", CALAIS, ["war_galley", "transport_cog"])
	var ship_a := world.get_ship("fleet_crew_s0")
	ship_a["crew_bp"] = 10000
	world.ship_registry["fleet_crew_s0"] = ship_a
	var ship_b := world.get_ship("fleet_crew_s1")
	ship_b["crew_bp"] = 5000
	world.ship_registry["fleet_crew_s1"] = ship_b
	FleetSystemScript.recompute_aggregate(world, "fleet_crew")
	# war_galley sailor_cost=150, transport_cog sailor_cost=60:
	# (150*10000 + 60*5000) / (150+60) = 1800000 / 210 = 8571 (int division).
	var readiness := int(world.get_fleet("fleet_crew")["aggregate"]["crew_readiness_bp"])
	_check(readiness == 8571, "CREW_READINESS_NOT_WEIGHTED", "expected a sailor-cost-weighted 8571bp, got %d - a flat average would give 7500" % readiness)

	# A fleet with no ships (the placeholder pre-recompute aggregate never
	# actually reaches a player, but the function itself must not divide by
	# zero) must default to full readiness, matching hull_pct's own "100 if
	# empty" convention.
	var world2 := _make_world()
	world2.fleet_registry["fleet_empty"] = CampaignWorldStateScript.make_fleet_record("fleet_empty", "ENG", CALAIS)
	FleetSystemScript.recompute_aggregate(world2, "fleet_empty")
	var empty_aggregate: Dictionary = world2.get_fleet("fleet_empty")["aggregate"]
	_check(int(empty_aggregate["crew_readiness_bp"]) == 10000, "EMPTY_FLEET_CREW_READINESS_WRONG", "an empty fleet must default to full crew readiness, not divide by zero")
	_check(int(empty_aggregate["family_counts"]["heavy"]) == 0 and int(empty_aggregate["family_counts"]["transport"]) == 0, "EMPTY_FLEET_FAMILY_COUNTS_WRONG", "an empty fleet must report zero for every family, not omit the keys")


func _test_repairing_ship_count() -> void:
	var world := _make_world()
	_add_fleet(world, "fleet_repair", CALAIS, ["war_galley", "war_galley", "war_galley"])
	var damaged_a := world.get_ship("fleet_repair_s0")
	damaged_a["repairing"] = true
	world.ship_registry["fleet_repair_s0"] = damaged_a
	var damaged_b := world.get_ship("fleet_repair_s1")
	damaged_b["repairing"] = true
	world.ship_registry["fleet_repair_s1"] = damaged_b
	# The fleet's mission stays "idle" throughout - repairing_ship_count()
	# must reflect the real per-ship flag regardless of the mission tag, the
	# exact gap the FL2 closure audit found ("a fleet passively healing
	# without the repair mission set gives no indication anything is
	# happening").
	_check(String(world.get_fleet("fleet_repair").get("mission", "")) == "idle", "REPAIR_FIXTURE_MISSION_WRONG", "fixture assumption: the fleet must not be on the repair mission")
	_check(FleetLogisticsSystemScript.repairing_ship_count(world, "fleet_repair") == 2, "REPAIRING_SHIP_COUNT_WRONG", "expected exactly 2 of 3 ships flagged repairing")


func _test_route_completion_day_partial_traversal() -> void:
	var world := _make_world()
	_add_fleet(world, "fleet_route", CALAIS, ["war_galley"])
	var graph := MaritimeGraphScript.load_default()
	var start_day := world.current_day

	# Snapshot 1: order just submitted, still at the origin. remaining_path
	# has two full legs ahead of the one already scheduled as next_arrival_day.
	var fleet := world.get_fleet("fleet_route")
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_MOVING
	fleet["location_id"] = CALAIS
	fleet["remaining_path"] = [STRAITS_OF_DOVER, ROUTE_NODE_B, ROUTE_NODE_C]
	fleet["path_index"] = 0
	fleet["next_arrival_day"] = start_day + 1
	world.fleet_registry["fleet_route"] = fleet
	var final_day := FleetSystemScript.route_completion_day(world, "fleet_route", graph)
	# 1 (Calais->Straits) + 3 (Straits->B) + 3 (B->C) = 7 days after order day.
	_check(final_day == start_day + 7, "ROUTE_COMPLETION_AT_ORDER_TIME_WRONG", "expected final ETA %d, got %d" % [start_day + 7, final_day])
	var untraversed: Array = (fleet["remaining_path"] as Array).slice(int(fleet["path_index"]))
	_check(untraversed == [STRAITS_OF_DOVER, ROUTE_NODE_B, ROUTE_NODE_C], "UNTRAVERSED_ROUTE_AT_ORDER_TIME_WRONG", "the full route must be untraversed at order time")

	# Snapshot 2: the first leg has resolved - the fleet is now at the
	# Straits of Dover, en route to node B. The final ETA must be unchanged:
	# it does not matter how far along the fleet is, only how much route is
	# actually left.
	fleet["location_id"] = STRAITS_OF_DOVER
	fleet["path_index"] = 1
	fleet["next_arrival_day"] = start_day + 1 + 3
	world.fleet_registry["fleet_route"] = fleet
	final_day = FleetSystemScript.route_completion_day(world, "fleet_route", graph)
	_check(final_day == start_day + 7, "ROUTE_COMPLETION_MID_TRAVERSAL_WRONG", "the final ETA must not drift as the fleet progresses along an unblocked route, got %d" % final_day)
	untraversed = (fleet["remaining_path"] as Array).slice(int(fleet["path_index"]))
	_check(untraversed == [ROUTE_NODE_B, ROUTE_NODE_C], "UNTRAVERSED_ROUTE_MID_TRAVERSAL_WRONG", "only the two remaining waypoints must be reported as untraversed, not the whole original route")

	# Snapshot 3: only the final leg remains - route_completion_day() must
	# collapse to exactly next_arrival_day, with nothing left to sum.
	fleet["location_id"] = ROUTE_NODE_B
	fleet["path_index"] = 2
	fleet["next_arrival_day"] = start_day + 7
	world.fleet_registry["fleet_route"] = fleet
	final_day = FleetSystemScript.route_completion_day(world, "fleet_route", graph)
	_check(final_day == start_day + 7, "ROUTE_COMPLETION_FINAL_LEG_WRONG", "on the final leg, the completion day must equal next_arrival_day exactly, got %d" % final_day)

	# A docked (non-moving) fleet has no pending route to complete.
	var docked_fleet := world.get_fleet("fleet_route")
	docked_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	docked_fleet["remaining_path"] = []
	docked_fleet["path_index"] = 0
	docked_fleet["next_arrival_day"] = -1
	world.fleet_registry["fleet_route"] = docked_fleet
	_check(FleetSystemScript.route_completion_day(world, "fleet_route", graph) == -1, "DOCKED_FLEET_HAS_ROUTE_COMPLETION", "a docked fleet must report no pending route completion")


func _run() -> void:
	_test_mixed_family_counts()
	_test_crew_readiness_weighting()
	_test_repairing_ship_count()
	_test_route_completion_day_partial_traversal()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval fleet summary test failed: %s" % failure)
		print("Naval fleet summary test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval fleet summary test passed. cases=mixed_family,crew_readiness,repairing_count,route_completion")
	quit(0)
