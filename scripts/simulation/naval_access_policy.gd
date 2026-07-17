class_name NavalAccessPolicy
extends RefCounted

## N1.3 centralised naval access/basing permission queries and the supply
## range query. MaritimeGraph stays free of mutable campaign state (pure
## baked topology); this class is where ownership/diplomacy/war lookups
## happen, mirroring the split ProvincePathfinder already uses for land
## movement (ProvincePathfinder.can_enter). See
## docs/roadmap/naval/01_N1_MARITIME_GRAPH_AUTHORITY.md "Access and Basing
## Rules" and docs/roadmap/naval/00_SCOPE_AND_ARCHITECTURE_LOCK.md.
##
## Three separate questions, never conflated:
##   1. can_sail  - may a fleet transit this sea zone at all?
##   2. can_dock  - may it enter/dock at this port?
##   3. can_base  - does this port provide supply/repair/home-port use?

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")


## Question 1. Closed water is already excluded from MaritimeGraph's
## navigable zone set; every other sea zone is open transit. No closed
## straits are authored yet - a future explicit restriction extends this
## function, not its callers.
static func can_sail(graph: MaritimeGraph, zone_id: int) -> bool:
	return graph.is_sea_zone(zone_id)


static func _port_host(world: CampaignWorldState, port_id: int) -> String:
	var controller := world.get_province_controller(port_id)
	return controller if not controller.is_empty() else world.get_province_owner(port_id)


## Question 2: transit/docking. Deliberately NOT auto-granted by being at war
## with the host - unlike ProvincePathfinder.can_enter's land-invasion rule,
## sailing into a hostile harbour is not the same act as marching an army
## into hostile territory. A captured port's controller becomes its host, so
## occupation is already covered by the ownership check below without a
## separate war branch.
static func can_dock(graph: MaritimeGraph, world: CampaignWorldState, country: String, port_id: int) -> bool:
	if not graph.is_port_province(port_id) or not graph.is_port_enabled(port_id):
		return false
	var host := _port_host(world, port_id)
	if host.is_empty() or host == country:
		return true
	if DiplomacySystemScript.are_allied(world, country, host):
		return true
	if DiplomacySystemScript.overlord_of(world, country) == host or DiplomacySystemScript.overlord_of(world, host) == country:
		return true
	# "Explicit naval access" reuses the existing general military_access
	# relation until a dedicated naval grant exists - see 00_SCOPE "Required
	# relationship concepts: naval_access."
	return DiplomacySystemScript.has_access(world, country, host)


## N1.4 access explanation: names the exact relationship or restriction that
## decided the result, not just whether it was allowed. Console/test-trace
## form of "Access explanation showing the exact relationship or restriction
## used" from 01_N1_MARITIME_GRAPH_AUTHORITY.md.
static func explain_dock(graph: MaritimeGraph, world: CampaignWorldState, country: String, port_id: int) -> String:
	if not graph.is_port_province(port_id):
		return "%d is not a port province." % port_id
	if not graph.is_port_enabled(port_id):
		return "Port %d is disabled." % port_id
	var host := _port_host(world, port_id)
	if host.is_empty():
		return "%s may dock at %d: allowed - port is unclaimed." % [country, port_id]
	if host == country:
		return "%s may dock at %d: allowed - %s owns/controls this port." % [country, port_id, country]
	if DiplomacySystemScript.are_allied(world, country, host):
		return "%s may dock at %d: allowed - %s is allied with %s." % [country, port_id, country, host]
	if DiplomacySystemScript.overlord_of(world, country) == host:
		return "%s may dock at %d: allowed - %s is a subject of %s." % [country, port_id, country, host]
	if DiplomacySystemScript.overlord_of(world, host) == country:
		return "%s may dock at %d: allowed - %s is %s's overlord." % [country, port_id, country, host]
	if DiplomacySystemScript.has_access(world, country, host):
		return "%s may dock at %d: allowed - %s has explicit naval access from %s." % [country, port_id, country, host]
	return "%s may NOT dock at %d: denied - %s owns/controls it and has granted %s no relationship." % [country, port_id, host, country]


static func dock_failure_reason(graph: MaritimeGraph, world: CampaignWorldState, country: String, port_id: int) -> String:
	if not graph.is_port_province(port_id):
		return "Unknown port."
	if not graph.is_port_enabled(port_id):
		return "Port is disabled."
	if can_dock(graph, world, country, port_id):
		return ""
	return "Naval access from %s is required." % _port_host(world, port_id)


## Question 3: fleet_basing_rights is a stricter right than docking - per
## 00_SCOPE it "permits supply, repair, and home-port use, normally with
## diplomatic/economic cost later." No basing-rights grant mechanism exists
## yet (that is N2+ content once fleets/commands exist to request or pay for
## it), so the only right recognised today is direct ownership/control.
## Extend this function, not its callers, when a real grant registry lands.
static func can_base(graph: MaritimeGraph, world: CampaignWorldState, country: String, port_id: int) -> bool:
	if not graph.is_port_province(port_id) or not graph.is_port_enabled(port_id):
		return false
	var host := _port_host(world, port_id)
	return host.is_empty() or host == country


## N2.3: a fleet-usable route, not just a topologically possible one - any
## port the route would pass through or arrive at must be dockable by
## `country`. Sea-zone transit needs no such check (question 1 is trivial;
## see can_sail). This is the naval analogue of ProvincePathfinder.find_route
## wrapping ProvinceGraph with access, and it is what MoveFleetCommand and
## FleetMovementSystem's per-leg revalidation both call - so a command can
## never accept a route that revalidation would immediately reject.
static func find_legal_route(graph: MaritimeGraph, world: CampaignWorldState, country: String, from_id: int, to_id: int, speed_multiplier_bp: int = 10000) -> Dictionary:
	return graph.find_route(from_id, to_id, speed_multiplier_bp, func(port_id): return can_dock(graph, world, country, port_id))


## N1 provides the query; N2 applies the resulting attrition/repair rules.
## Owned/controlled ports are evaluated in Dijkstra cost order (lowest first,
## tie-broken by lowest stable port ID), matching 01_N1's "must be evaluated
## in sorted order" requirement without recomputing a route per candidate.
##
## `zone_id` may be a sea zone OR a port (N2.4: a fleet's current location is
## whichever kind it happens to occupy, mid-route or docked). Note that
## `nearest_matching` only matches candidates strictly downstream of the
## origin - if the fleet is already docked at a basing-right port, calling
## this directly would search past that port for another one. Callers that
## need "is my current position good enough" (FleetLogisticsSystem) must
## check `can_base` at the origin themselves before falling back to this.
static func supply_range_query(
	graph: MaritimeGraph,
	world: CampaignWorldState,
	country: String,
	zone_id: int,
	max_range_days: int,
	speed_multiplier_bp: int = 10000
) -> Dictionary:
	var result := {
		"supplied": false,
		"nearest_port_id": -1,
		"range_cost": -1,
		"range_limit": max_range_days,
		"route": [],
		"failure_reason": "",
	}
	if not can_sail(graph, zone_id) and not graph.is_port_province(zone_id):
		result["failure_reason"] = "Unknown or non-navigable location."
		return result
	var nearest := graph.nearest_matching(
		zone_id,
		func(candidate_id): return can_base(graph, world, country, candidate_id),
		speed_multiplier_bp
	)
	if not bool(nearest["found"]):
		result["failure_reason"] = "No basing-right port is reachable from this sea zone."
		return result
	result["nearest_port_id"] = int(nearest["id"])
	result["range_cost"] = int(nearest["total_days"])
	result["route"] = nearest["path"]
	if int(nearest["total_days"]) > max_range_days:
		result["failure_reason"] = "The nearest basing-right port is beyond supply range."
		return result
	result["supplied"] = true
	return result
