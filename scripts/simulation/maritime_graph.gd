class_name MaritimeGraph
extends RefCounted

## N1.2 runtime maritime topology: sorted sea zones/ports/exits/anchors,
## stable movement costs, and deterministic structured route finding.
##
## Built once from ProvinceGraph (raw topology) and NavalDefinitions (baked
## classification/port candidates) - it owns no state of its own and derives
## nothing from rendered map pixels. See docs/roadmap/naval/01_N1_MARITIME_GRAPH_AUTHORITY.md.
##
## Out of scope here (N1.3+): naval access/basing-right permission checks,
## supply range, and "legal" nearest-port queries - this class answers "does a
## navigable route exist and how long does it take," not "is this fleet
## allowed to use it." Route Result Contract fields tied to access/supply
## (supplied_at_destination, range_cost, range_limit) are intentionally
## omitted until that logic exists, rather than stubbed with fake values.

const ProvinceGraphScript = preload("res://scripts/simulation/province_graph.gd")
const NavalDefinitionsScript = preload("res://scripts/simulation/naval_definitions.gd")

## Abstract baseline days per sea-zone-to-sea-zone leg, keyed by the
## destination zone's classification. This is the N1 fleet-speed-neutral
## profile; N2 multiplies by a fleet's slowest-ship speed without changing
## this graph, per 01_N1_MARITIME_GRAPH_AUTHORITY.md "Movement Costs".
const SEA_ZONE_LEG_COST_DAYS := {
	"coastal_sea": 3,
	"inland_sea": 3,
	"open_ocean": 5,
}
const PORT_LEG_COST_DAYS := 1
const CLOSED_WATER_CLASSIFICATION := "closed_water"

# Heap entries pack (cost << 13) | id, matching ProvincePathfinder's scheme.
# Project province IDs stay under 8192 (highest observed ID is in the 4900s
# out of 3,924 total records), so ordering by the packed value orders by cost
# then lowest ID - the same determinism guarantee land pathfinding relies on.
const _ID_BITS := 13
const _ID_MASK := (1 << _ID_BITS) - 1

static var _default_instance: MaritimeGraph

var _province_graph: ProvinceGraph
var _naval: NavalDefinitions
var _navigable_zone_ids: Dictionary = {}
var _zone_neighbor_cache: Dictionary = {}
var _port_exit_cache: Dictionary = {}
var _zone_ports: Dictionary = {}
# Full combined-neighbour lists (sea zones + ports) are read on every node a
# Dijkstra run visits, so they are memoized once per graph instance rather
# than rebuilt and re-sorted on every call - see _neighbors_of().
var _combined_neighbor_cache: Dictionary = {}


static func load_default() -> MaritimeGraph:
	if _default_instance == null:
		_default_instance = MaritimeGraph.new()
		_default_instance._build(ProvinceGraphScript.load_default(), NavalDefinitionsScript.load_default())
	return _default_instance


static func from_sources(province_graph: ProvinceGraph, naval_definitions: NavalDefinitions) -> MaritimeGraph:
	var graph := MaritimeGraph.new()
	graph._build(province_graph, naval_definitions)
	return graph


func _build(province_graph: ProvinceGraph, naval_definitions: NavalDefinitions) -> void:
	_province_graph = province_graph
	_naval = naval_definitions
	for zone_id in _naval.sea_zone_ids():
		if String(_naval.sea_zone(zone_id).get("classification", "")) != CLOSED_WATER_CLASSIFICATION:
			_navigable_zone_ids[zone_id] = true
	_zone_ports.clear()
	# Build the zone->ports reverse index with plain (reference-typed) Arrays,
	# not PackedInt32Array: retrieving a PackedInt32Array from a Dictionary
	# yields a copy in this Godot build, so mutating it in place here would
	# silently discard every append. Convert to PackedInt32Array once at the
	# end, via direct assignment rather than in-place mutation.
	var zone_ports_builder: Dictionary = {}
	for port_id in _naval.port_ids():
		var exits := PackedInt32Array()
		for raw_exit in (_naval.port(port_id).get("sea_exits", []) as Array):
			var exit_id := int(raw_exit)
			if _navigable_zone_ids.has(exit_id):
				exits.append(exit_id)
		exits.sort()
		_port_exit_cache[port_id] = exits
		for exit_id in exits:
			if not zone_ports_builder.has(exit_id):
				zone_ports_builder[exit_id] = []
			(zone_ports_builder[exit_id] as Array).append(port_id)
	for zone_id in zone_ports_builder:
		var ports_list: Array = zone_ports_builder[zone_id]
		ports_list.sort()
		var packed := PackedInt32Array()
		for port_id in ports_list:
			packed.append(port_id)
		_zone_ports[zone_id] = packed


## --- Sorted topology accessors ---

func is_sea_zone(province_id: int) -> bool:
	return _navigable_zone_ids.has(province_id)


func sea_zone_ids() -> Array[int]:
	var ids: Array[int] = []
	for zone_id in _navigable_zone_ids:
		ids.append(zone_id)
	ids.sort()
	return ids


func sea_zone_classification(province_id: int) -> String:
	return String(_naval.sea_zone(province_id).get("classification", ""))


func sea_neighbor_ids(zone_id: int) -> PackedInt32Array:
	if _zone_neighbor_cache.has(zone_id):
		return _zone_neighbor_cache[zone_id]
	var neighbors := PackedInt32Array()
	if _navigable_zone_ids.has(zone_id):
		for candidate in _province_graph.sea_neighbors(zone_id):
			if _navigable_zone_ids.has(candidate):
				neighbors.append(candidate)
	neighbors.sort()
	_zone_neighbor_cache[zone_id] = neighbors
	return neighbors


func is_port_province(province_id: int) -> bool:
	return _port_exit_cache.has(province_id)


func port_province_ids() -> Array[int]:
	var ids: Array[int] = []
	for port_id in _port_exit_cache:
		ids.append(port_id)
	ids.sort()
	return ids


func is_port_enabled(port_id: int) -> bool:
	return bool(_naval.port(port_id).get("enabled", false))


func port_exits(port_id: int) -> PackedInt32Array:
	return _port_exit_cache.get(port_id, PackedInt32Array())


func sea_zone_ports(zone_id: int) -> PackedInt32Array:
	return _zone_ports.get(zone_id, PackedInt32Array())


func is_coastal_land(province_id: int) -> bool:
	return _province_graph.is_land(province_id) and _province_graph.is_coastal(province_id)


func anchor(province_id: int) -> Vector2i:
	return _province_graph.anchor(province_id)


func is_strait(from_id: int, to_id: int) -> bool:
	return _province_graph.is_strait(from_id, to_id)


## --- Movement costs ---

## Returns -1 if `from_id` and `to_id` are not directly connected in the
## navigable maritime graph (adjacent sea zones, or a port and one of its
## own exits). `speed_multiplier_bp` is basis points (10000 = baseline);
## N2 fleets pass their slowest-ship speed instead of the default.
func leg_cost_days(from_id: int, to_id: int, speed_multiplier_bp: int = 10000) -> int:
	var base_cost := _base_leg_cost_days(from_id, to_id)
	if base_cost < 0:
		return -1
	var safe_multiplier_bp := speed_multiplier_bp if speed_multiplier_bp > 0 else 1
	var scaled: int = (base_cost * 10000) / safe_multiplier_bp
	return 1 if scaled < 1 else scaled


func _base_leg_cost_days(from_id: int, to_id: int) -> int:
	if is_port_province(from_id) and is_sea_zone(to_id) and port_exits(from_id).has(to_id):
		return PORT_LEG_COST_DAYS
	if is_sea_zone(from_id) and is_port_province(to_id) and port_exits(to_id).has(from_id):
		return PORT_LEG_COST_DAYS
	if is_sea_zone(from_id) and is_sea_zone(to_id) and sea_neighbor_ids(from_id).has(to_id):
		return int(SEA_ZONE_LEG_COST_DAYS.get(sea_zone_classification(to_id), 5))
	return -1


## --- Structured route finding ---

## Deterministic Dijkstra over the combined port/sea-zone graph. Origin and
## destination may each be a port province ID or a sea-zone ID. Ties resolve
## to the lowest stable province ID at every step (packed-heap ordering plus
## a lowest-predecessor-ID rule), matching ProvincePathfinder's guarantee.
##
## `port_filter`, if valid, is called with a port ID whenever the route would
## pass through or arrive at that port, and must return true to allow it.
## MaritimeGraph itself has no notion of ownership/access (see the class
## comment) - this is how NavalAccessPolicy layers "may this fleet actually
## use that port" on top of pure topology without MaritimeGraph depending on
## CampaignWorldState, mirroring the ProvinceGraph/ProvincePathfinder split.
func find_route(from_id: int, to_id: int, speed_multiplier_bp: int = 10000, port_filter: Callable = Callable()) -> Dictionary:
	var result := {
		"exists": false,
		"path": [],
		"total_days": 0,
		"origin_kind": _node_kind(from_id),
		"destination_kind": _node_kind(to_id),
		"uses_port_exit": false,
		"uses_port_entry": false,
		"blocked_reason_code": "",
		"failure_reason": "",
	}
	if result["origin_kind"] == "":
		result["blocked_reason_code"] = "unknown_origin"
		result["failure_reason"] = "Origin %d is not a known port or sea zone." % from_id
		return result
	if result["destination_kind"] == "":
		result["blocked_reason_code"] = "unknown_destination"
		result["failure_reason"] = "Destination %d is not a known port or sea zone." % to_id
		return result
	if port_filter.is_valid() and is_port_province(to_id) and not port_filter.call(to_id):
		result["blocked_reason_code"] = "port_access_denied"
		result["failure_reason"] = "Access to destination port %d is denied." % to_id
		return result

	if from_id == to_id:
		result["exists"] = true
		result["path"] = [{"id": from_id, "kind": result["origin_kind"]}]
		return result

	var run := _dijkstra_from(from_id, speed_multiplier_bp, to_id, Callable(), port_filter)
	var best_cost: Dictionary = run["best_cost"]
	var came_from: Dictionary = run["came_from"]

	if not best_cost.has(to_id):
		result["blocked_reason_code"] = "no_route"
		result["failure_reason"] = "No navigable maritime route to the destination."
		return result

	var path := _reconstruct_path(from_id, to_id, came_from)
	var uses_port_exit := path.size() > 1 and String(path[0]["kind"]) == "port"
	var uses_port_entry := path.size() > 1 and String(path[path.size() - 1]["kind"]) == "port"

	result["exists"] = true
	result["path"] = path
	result["total_days"] = int(best_cost[to_id])
	result["uses_port_exit"] = uses_port_exit
	result["uses_port_entry"] = uses_port_entry
	return result


## Runs a full single-source Dijkstra from `from_id` and returns the lowest-
## cost node reachable that satisfies `matches(id) -> bool`, breaking ties by
## the lowest stable ID (same guarantee as find_route). Used for "nearest
## legal port" style N1.3 queries without recomputing a full route per
## candidate port.
## Dijkstra pops nodes in non-decreasing final-cost order (lowest ID first on
## ties, from the packed heap), so the first popped node satisfying `matches`
## is provably the lowest-cost, lowest-ID-tie-broken match - no need to
## finish the full traversal or post-sort candidates.
func nearest_matching(from_id: int, matches: Callable, speed_multiplier_bp: int = 10000) -> Dictionary:
	var result := {"found": false, "id": -1, "total_days": 0, "path": []}
	if _node_kind(from_id) == "":
		return result
	var run := _dijkstra_from(from_id, speed_multiplier_bp, -1, matches)
	var found_id := int(run["found_id"])
	if found_id < 0:
		return result
	var best_cost: Dictionary = run["best_cost"]
	var came_from: Dictionary = run["came_from"]
	result["found"] = true
	result["id"] = found_id
	result["total_days"] = int(best_cost[found_id])
	result["path"] = _reconstruct_path(from_id, found_id, came_from)
	return result


## Single-source Dijkstra that stops as soon as either early-exit condition is
## satisfied at pop time (a node's cost is only final once popped, so this
## preserves correctness): `target_id` for a specific destination (find_route),
## or `matches` for the first node satisfying an arbitrary predicate
## (nearest_matching). Passing neither runs the full traversal. `port_filter`
## excludes any port neighbor it rejects from the relaxation entirely - see
## find_route's doc comment.
func _dijkstra_from(from_id: int, speed_multiplier_bp: int, target_id: int = -1, matches: Callable = Callable(), port_filter: Callable = Callable()) -> Dictionary:
	var best_cost := {from_id: 0}
	var came_from := {}
	var heap := PackedInt64Array()
	var found_id := -1
	_heap_push(heap, from_id)
	while heap.size() > 0:
		var packed := _heap_pop(heap)
		var cost := int(packed >> _ID_BITS)
		var current := int(packed & _ID_MASK)
		if cost > int(best_cost.get(current, 0x7FFFFFFF)):
			continue
		if current == target_id:
			found_id = current
			break
		if matches.is_valid() and current != from_id and matches.call(current):
			found_id = current
			break
		for neighbor in _neighbors_of(current):
			if port_filter.is_valid() and is_port_province(neighbor) and not port_filter.call(neighbor):
				continue
			var step_cost := leg_cost_days(current, neighbor, speed_multiplier_bp)
			if step_cost < 0:
				continue
			var new_cost := cost + step_cost
			var known := int(best_cost.get(neighbor, 0x7FFFFFFF))
			if new_cost < known or (new_cost == known and current < int(came_from.get(neighbor, 0x7FFFFFFF))):
				best_cost[neighbor] = new_cost
				came_from[neighbor] = current
				_heap_push(heap, neighbor, new_cost)
	return {"best_cost": best_cost, "came_from": came_from, "found_id": found_id}


func _reconstruct_path(from_id: int, to_id: int, came_from: Dictionary) -> Array:
	var path: Array = []
	var walk := to_id
	while walk != from_id:
		path.append({"id": walk, "kind": _node_kind(walk)})
		walk = int(came_from[walk])
	path.append({"id": from_id, "kind": _node_kind(from_id)})
	path.reverse()
	return path


## --- N1.4 debug/explanation tools ---
## Console/test-trace form of the "debug overlay and route/access
## explanation" requirement - see docs/roadmap/naval/01_N1_MARITIME_GRAPH_AUTHORITY.md
## "Debug and Presentation Tools" ("final art is not required for N1").

func describe_node(province_id: int) -> String:
	var kind := _node_kind(province_id)
	var name := _province_graph.province_name(province_id)
	if kind == "sea_zone":
		return "%d %s [sea_zone:%s]" % [province_id, name, sea_zone_classification(province_id)]
	if kind == "port":
		return "%d %s [port]" % [province_id, name]
	return "%d [unknown]" % province_id


func explain_route(from_id: int, to_id: int, speed_multiplier_bp: int = 10000) -> String:
	var route := find_route(from_id, to_id, speed_multiplier_bp)
	if not bool(route["exists"]):
		return "No route from %s to %s: %s (%s)" % [
			describe_node(from_id), describe_node(to_id), String(route["failure_reason"]), String(route["blocked_reason_code"])
		]
	var path: Array = route["path"]
	var text := "Route %d -> %d: %d leg(s), %d day(s) total." % [from_id, to_id, path.size() - 1, int(route["total_days"])]
	for i in range(path.size() - 1):
		var leg_from := int((path[i] as Dictionary)["id"])
		var leg_to := int((path[i + 1] as Dictionary)["id"])
		var leg_cost := leg_cost_days(leg_from, leg_to, speed_multiplier_bp)
		text += "\n  %d. %s -> %s (%d day%s)" % [
			i + 1, describe_node(leg_from), describe_node(leg_to), leg_cost, "" if leg_cost == 1 else "s"
		]
	return text


func _node_kind(province_id: int) -> String:
	if is_sea_zone(province_id):
		return "sea_zone"
	if is_port_province(province_id):
		return "port"
	return ""


func _neighbors_of(province_id: int) -> PackedInt32Array:
	if _combined_neighbor_cache.has(province_id):
		return _combined_neighbor_cache[province_id]
	var neighbors := PackedInt32Array()
	if is_sea_zone(province_id):
		neighbors = PackedInt32Array(sea_neighbor_ids(province_id))
		for port_id in sea_zone_ports(province_id):
			neighbors.append(port_id)
		neighbors.sort()
	elif is_port_province(province_id):
		neighbors = port_exits(province_id)
	_combined_neighbor_cache[province_id] = neighbors
	return neighbors


func _heap_push(heap: PackedInt64Array, province_id: int, cost: int = 0) -> void:
	heap.append((cost << _ID_BITS) | province_id)
	_sift_up(heap, heap.size() - 1)


func _heap_pop(heap: PackedInt64Array) -> int:
	var top := heap[0]
	var last := heap[heap.size() - 1]
	heap.remove_at(heap.size() - 1)
	if heap.size() > 0:
		heap[0] = last
		_sift_down(heap, 0)
	return top


func _sift_up(heap: PackedInt64Array, index: int) -> void:
	while index > 0:
		var parent := (index - 1) >> 1
		if heap[index] >= heap[parent]:
			break
		var swap := heap[index]
		heap[index] = heap[parent]
		heap[parent] = swap
		index = parent


func _sift_down(heap: PackedInt64Array, index: int) -> void:
	var size := heap.size()
	while true:
		var smallest := index
		var left := index * 2 + 1
		var right := index * 2 + 2
		if left < size and heap[left] < heap[smallest]:
			smallest = left
		if right < size and heap[right] < heap[smallest]:
			smallest = right
		if smallest == index:
			return
		var swap := heap[index]
		heap[index] = heap[smallest]
		heap[smallest] = swap
		index = smallest
