extends SceneTree

## N1.4 gate coverage: representative long-haul fixture paths, full-graph
## reciprocity at the runtime MaritimeGraph API surface (not just the raw
## baked JSON, which N1.1 already checked), and a stress/performance smoke.
##
## The total-batch budget below is a conservative smoke-test guard, NOT an
## approved N0 numerical performance budget - that budget remains an open
## item (see docs/roadmap/naval/evidence/N0_BASELINE_INVENTORY.md). This
## catches an accidental correctness/complexity regression (e.g. an O(n^2)
## bug), it does not certify N1 meets a release-quality performance target.

const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")

# N0.3 fixture ports.
const CALAIS := 87
const KENT := 235
const LISBOA := 227
const ALGARVE := 230
const CADIZ := 1749
const BARCELONA := 213

const ALL_ROUTE_BATCH_BUDGET_MS := 20000.0
const FIXTURE_PORTS := [87, 89, 90, 167, 168, 197, 206, 207, 209, 212, 213, 220, 224, 227, 229, 230, 231, 233, 235, 333, 1749, 1751, 2988, 4371, 4373, 4374, 4385, 4548, 4556]


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Maritime graph stress smoke failed: %s" % message)
		quit(1)


func _run() -> void:
	var graph := MaritimeGraphScript.load_default()

	# Representative long-haul fixture paths (01_N1 "Required Tests").
	var portugal_channel := graph.find_route(LISBOA, KENT)
	_require(bool(portugal_channel["exists"]), "Portugal to Channel (Lisboa to Kent) must resolve")

	var gibraltar_mediterranean := graph.find_route(ALGARVE, CADIZ)
	_require(bool(gibraltar_mediterranean["exists"]), "Gibraltar-Mediterranean crossing (Algarve to Cadiz) must resolve")

	var long_atlantic := graph.find_route(KENT, BARCELONA)
	_require(bool(long_atlantic["exists"]), "representative long Atlantic-to-Mediterranean path (Kent to Barcelona) must resolve")
	_require(int(long_atlantic["total_days"]) >= int(gibraltar_mediterranean["total_days"]), "a longer haul must cost at least as much as a single strait crossing")

	# Explanation trace sanity (N1.4 "route/access explanation").
	var explanation := graph.explain_route(CALAIS, KENT)
	_require(explanation.find("Route %d -> %d" % [CALAIS, KENT]) == 0, "explain_route must open with a route header")
	_require(explanation.find("Straits of Dover") >= 0, "explain_route must name the intermediate sea zone by its province name")
	var blocked_explanation := graph.explain_route(CALAIS, 99999999)
	_require(blocked_explanation.begins_with("No route"), "explain_route must clearly report an impossible route")

	# Every enabled port reaches at least one navigable sea zone (01_N1 "Required Tests").
	for port_id in graph.port_province_ids():
		if graph.is_port_enabled(port_id):
			_require(graph.port_exits(port_id).size() > 0, "enabled port %d must have at least one navigable sea exit" % port_id)

	# No asymmetric navigable edge at the runtime API surface, not just the raw JSON.
	var zone_ids := graph.sea_zone_ids()
	var checked := 0
	for zone_id in zone_ids:
		for neighbor_id in graph.sea_neighbor_ids(zone_id):
			_require(graph.sea_neighbor_ids(neighbor_id).has(zone_id), "sea_neighbor_ids must be symmetric: %d -> %d" % [zone_id, neighbor_id])
			checked += 1
	_require(checked > 0, "the reciprocity check must actually examine edges, not vacuously pass")

	# Stress/performance smoke: every fixture port to every other fixture port.
	var started_usec := Time.get_ticks_usec()
	var route_count := 0
	for origin in FIXTURE_PORTS:
		for destination in FIXTURE_PORTS:
			if origin == destination:
				continue
			graph.find_route(origin, destination)
			route_count += 1
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	_require(
		elapsed_ms <= ALL_ROUTE_BATCH_BUDGET_MS,
		"%d fixture-port route queries must complete within %.1f ms; measured %.2f ms" % [route_count, ALL_ROUTE_BATCH_BUDGET_MS, elapsed_ms]
	)

	print("Maritime graph stress smoke passed. routes=%d elapsed_ms=%.2f zone_edges_checked=%d" % [route_count, elapsed_ms, checked])
	quit(0)
