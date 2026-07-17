extends SceneTree

const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")

# N0.3 Channel fixture.
const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271
const THE_CHANNEL := 1272
const DOGGER_BANK := 1270

# N0.3 Iberian fixture.
const ALGARVE := 230
const CADIZ := 1749
const STRAITS_OF_GIBRALTAR := 1293

# A closed_water (non-navigable) sea zone per docs/data/naval_graph_validation.md.
const CLOSED_WATER_SAMPLE := 1250

const UNKNOWN_PROVINCE_ID := 99999999


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Maritime graph test failed: %s" % message)
		quit(1)


func _run() -> void:
	var graph := MaritimeGraphScript.load_default()

	# Sorted topology accessors.
	_require(graph.is_sea_zone(STRAITS_OF_DOVER), "Straits of Dover must be a sea zone")
	_require(not graph.is_sea_zone(CLOSED_WATER_SAMPLE), "closed_water zones must not appear as navigable sea zones")
	_require(graph.is_port_province(CALAIS), "Calais must be a port province")
	_require(not graph.is_port_province(STRAITS_OF_DOVER), "a sea zone must not also be a port province")

	var zone_ids := graph.sea_zone_ids()
	_require(zone_ids.size() == 566 - 84, "navigable sea zones must exclude the 84 closed_water zones")
	for i in range(1, zone_ids.size()):
		_require(zone_ids[i - 1] < zone_ids[i], "sea_zone_ids must be strictly ascending")

	var port_ids := graph.port_province_ids()
	for i in range(1, port_ids.size()):
		_require(port_ids[i - 1] < port_ids[i], "port_province_ids must be strictly ascending")

	_require(graph.is_port_enabled(CALAIS), "Calais fixture port must be enabled")

	# Reciprocal port/sea-zone exit index.
	var calais_exits := graph.port_exits(CALAIS)
	_require(calais_exits.size() > 0, "Calais must have at least one sea exit")
	for exit_id in calais_exits:
		_require(graph.sea_zone_ports(exit_id).has(CALAIS), "sea_zone_ports must reciprocate every port_exits entry")

	_require(graph.is_coastal_land(CALAIS), "Calais must be coastal land")
	_require(not graph.is_coastal_land(STRAITS_OF_DOVER), "a sea zone must not be coastal land")

	_require(graph.anchor(CALAIS) != Vector2i(-1, -1), "Calais must have a valid anchor")
	_require(graph.anchor(STRAITS_OF_DOVER) != Vector2i(-1, -1), "Straits of Dover must have a valid anchor")

	# Movement costs.
	_require(graph.leg_cost_days(CALAIS, STRAITS_OF_DOVER + 999999) == -1, "an unconnected leg must cost -1")
	var dover_to_channel := graph.leg_cost_days(STRAITS_OF_DOVER, THE_CHANNEL)
	_require(dover_to_channel > 0, "Straits of Dover to The Channel must have a positive baseline cost")
	var half_speed := graph.leg_cost_days(STRAITS_OF_DOVER, THE_CHANNEL, 5000)
	_require(half_speed == dover_to_channel * 2, "halving speed (5000bp) must double the leg cost")
	var double_speed := graph.leg_cost_days(STRAITS_OF_DOVER, THE_CHANNEL, 20000)
	_require(double_speed == max(1, dover_to_channel / 2), "doubling speed (20000bp) must roughly halve the leg cost")

	# Structured route finding: Calais -> Kent, a two-port one-hop-zone Channel crossing.
	var route := graph.find_route(CALAIS, KENT)
	_require(bool(route["exists"]), "Calais to Kent must have a navigable route")
	_require(String(route["origin_kind"]) == "port", "Calais must resolve as a port origin")
	_require(String(route["destination_kind"]) == "port", "Kent must resolve as a port destination")
	_require(bool(route["uses_port_exit"]), "the route must record leaving a port")
	_require(bool(route["uses_port_entry"]), "the route must record arriving at a port")
	_require(int(route["total_days"]) > 0, "the route must have a positive total cost")
	var path: Array = route["path"]
	_require(path.size() >= 3, "Calais to Kent must cross at least one sea zone")
	_require(int((path[0] as Dictionary)["id"]) == CALAIS, "the path must start at Calais")
	_require(int((path[path.size() - 1] as Dictionary)["id"]) == KENT, "the path must end at Kent")

	# Repeated-call determinism (N1E requirement).
	var route_again := graph.find_route(CALAIS, KENT)
	_require(route_again["total_days"] == route["total_days"], "repeated route queries must return the same cost")
	_require((route_again["path"] as Array).size() == path.size(), "repeated route queries must return the same path length")
	for i in range(path.size()):
		_require(
			int((route_again["path"][i] as Dictionary)["id"]) == int((path[i] as Dictionary)["id"]),
			"repeated route queries must return an identical path"
		)

	# Gibraltar fixture: Algarve -> Cadiz.
	var gibraltar_route := graph.find_route(ALGARVE, CADIZ)
	_require(bool(gibraltar_route["exists"]), "Algarve to Cadiz must have a navigable Gibraltar-crossing route")

	# Same-node trivial route.
	var trivial := graph.find_route(CALAIS, CALAIS)
	_require(bool(trivial["exists"]) and int(trivial["total_days"]) == 0, "a route to the same node must be trivially free")

	# Unknown IDs and closed water must reject safely, not crash (N1E requirement).
	var unknown_route := graph.find_route(UNKNOWN_PROVINCE_ID, KENT)
	_require(not bool(unknown_route["exists"]), "an unknown origin must not produce a route")
	_require(String(unknown_route["blocked_reason_code"]) == "unknown_origin", "an unknown origin must report unknown_origin")

	var closed_water_route := graph.find_route(CALAIS, CLOSED_WATER_SAMPLE)
	_require(not bool(closed_water_route["exists"]), "closed water must never appear as a reachable destination")
	_require(
		String(closed_water_route["blocked_reason_code"]) == "unknown_destination",
		"a closed_water destination must be reported as unknown, since it is excluded from the navigable graph"
	)

	print("Maritime graph test passed. sea_zones=%d ports=%d calais_kent_days=%d" % [zone_ids.size(), port_ids.size(), int(route["total_days"])])
	quit(0)
