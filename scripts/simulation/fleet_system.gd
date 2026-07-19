class_name FleetSystem
extends RefCounted

## N2.3 fleet organisation primitives shared by CreateFleetCommand,
## MergeFleetsCommand, SplitFleetCommand, and TransferShipsCommand, plus the
## aggregate recompute from 02_N2_FLEET_LOGISTICS.md "Fleet and Ship Model":
## "no authoritative aggregate may disagree with the underlying ships;
## aggregates are recomputed in stable ship-ID order when membership...
## changes."
##
## Organisation is restricted to fleets that are docked at the same port for
## this first slice - a fleet mid-transit, in battle, or retreating has no
## single stable "location" two fleets could safely share membership at yet.
## Movement/battle will need their own rules later; this is a deliberate,
## documented simplification, not an oversight.

const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")

## Reference speed for the 10000bp (baseline) MaritimeGraph leg-cost
## multiplier - see maritime_graph.gd "N2 fleets pass their slowest-ship
## speed instead of the default." A fleet's speed is its slowest ship's
## speed (already the aggregate's "speed" field); this converts that integer
## ship-speed value into the basis-points multiplier MaritimeGraph expects.
const BASELINE_SHIP_SPEED := 4


static func speed_multiplier_bp(fleet: Dictionary) -> int:
	var speed := int((fleet.get("aggregate", {}) as Dictionary).get("speed", BASELINE_SHIP_SPEED))
	if speed <= 0:
		speed = BASELINE_SHIP_SPEED
	return speed * 10000 / BASELINE_SHIP_SPEED


## FL2.1 closure: family_counts and crew_readiness_bp are part of the
## authoritative aggregate, not UI-computed, so the fleet summary panel and
## the FL2.2 organisation preview (class_counts_for_ships() below) share one
## source of truth for "what kind of ships does this fleet have."
## family_counts always has one entry per ShipDefinitions.ship_families(), in
## that deterministic order, even at zero - callers never need to guard a
## missing key. crew_readiness_bp is a sailor_cost-weighted average of
## per-ship crew_bp, not a flat average: a fully-crewed war galley (150
## sailors) says more about a fleet's readiness than a fully-crewed cog (60
## sailors), so an undercrewed galley should move the fleet number more than
## an equally-undercrewed cog would.
static func recompute_aggregate(world: CampaignWorldState, fleet_id: String, ship_definitions = null) -> void:
	if ship_definitions == null:
		ship_definitions = ShipDefinitionsScript.load_default()
	if not world.fleet_registry.has(fleet_id):
		return
	var fleet: Dictionary = world.fleet_registry[fleet_id]
	var member_ids := world.fleet_ships(fleet_id)
	var total_hull := 0
	var total_maximum_hull := 0
	var total_attack := 0
	var total_defence := 0
	var total_blockade_power := 0
	var total_transport_capacity := 0
	var slowest_speed := -1
	var family_counts := {}
	for family in ship_definitions.ship_families():
		family_counts[String(family)] = 0
	var total_sailor_cost := 0
	var weighted_crew_bp := 0
	for ship_id in member_ids:
		var ship := world.get_ship(ship_id)
		var definition: Dictionary = ship_definitions.ship(String(ship.get("definition_id", "")))
		var maximum_hull := int(definition.get("maximum_hull", 0))
		total_maximum_hull += maximum_hull
		total_hull += maximum_hull * int(ship.get("hull_bp", 10000)) / 10000
		total_attack += int(definition.get("attack", 0))
		total_defence += int(definition.get("defence", 0))
		total_blockade_power += int(definition.get("blockade_power", 0))
		total_transport_capacity += int(definition.get("transport_capacity", 0))
		var speed := int(definition.get("speed", 1))
		if slowest_speed < 0 or speed < slowest_speed:
			slowest_speed = speed
		var family := String(definition.get("family", ""))
		if family_counts.has(family):
			family_counts[family] += 1
		var sailor_cost := int(definition.get("sailor_cost", 0))
		total_sailor_cost += sailor_cost
		weighted_crew_bp += sailor_cost * int(ship.get("crew_bp", 10000))
	fleet["aggregate"] = {
		"ship_count": member_ids.size(),
		"total_hull": total_hull,
		"total_maximum_hull": total_maximum_hull,
		"total_attack": total_attack,
		"total_defence": total_defence,
		"total_blockade_power": total_blockade_power,
		"total_transport_capacity": total_transport_capacity,
		"speed": slowest_speed if slowest_speed > 0 else 1,
		"family_counts": family_counts,
		"crew_readiness_bp": weighted_crew_bp / total_sailor_cost if total_sailor_cost > 0 else 10000,
	}
	world.fleet_registry[fleet_id] = fleet


## FL2.2 organisation preview: the same family-count shape recompute_aggregate()
## puts on the fleet aggregate, but for an arbitrary candidate ship_ids list
## (e.g. the ships currently selected to split or transfer) rather than a
## fleet's full membership - the two operate over different populations, so
## this is a separate small loop rather than a wrapper around the aggregate.
static func class_counts_for_ships(world: CampaignWorldState, ship_ids: Array, ship_definitions = null) -> Dictionary:
	if ship_definitions == null:
		ship_definitions = ShipDefinitionsScript.load_default()
	var counts := {}
	for family in ship_definitions.ship_families():
		counts[String(family)] = 0
	for raw_ship_id in ship_ids:
		var ship := world.get_ship(String(raw_ship_id))
		var definition: Dictionary = ship_definitions.ship(String(ship.get("definition_id", "")))
		var family := String(definition.get("family", ""))
		if counts.has(family):
			counts[family] += 1
	return counts


## Renders a family_counts (or class_counts_for_ships) dictionary as
## "2 heavy, 1 transport" - zero-count families are omitted, and order
## follows the dictionary's own insertion order, which both producers above
## always set to ShipDefinitions.ship_families()'s deterministic order.
static func format_class_counts(counts: Dictionary) -> String:
	var parts: Array[String] = []
	for family in counts:
		var count := int(counts[family])
		if count > 0:
			parts.append("%d %s" % [count, String(family)])
	return ", ".join(parts) if not parts.is_empty() else "no ships"


## FL2.1 closure: the fleet panel previously showed no route or arrival text
## at all. next_arrival_day (stored on the fleet) is only the *next waypoint's*
## arrival - not the final destination's - so this sums the remaining known
## legs on top of it to give a real final ETA, using the same
## MaritimeGraph.leg_cost_days()/speed_multiplier_bp() FleetMovementSystem
## itself advances by. Returns -1 if the fleet isn't currently moving/
## retreating or has no pending route left to sum (matches
## FleetMovementSystem.advance_day()'s own "nothing left" case).
static func route_completion_day(world: CampaignWorldState, fleet_id: String, graph: MaritimeGraph = null) -> int:
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return -1
	var status := String(fleet.get("location_status", ""))
	if status != CampaignWorldState.FLEET_LOCATION_MOVING and status != CampaignWorldState.FLEET_LOCATION_RETREATING:
		return -1
	var remaining: Array = fleet.get("remaining_path", [])
	var path_index := int(fleet.get("path_index", 0))
	if path_index >= remaining.size():
		return -1
	var arrival_day := int(fleet.get("next_arrival_day", -1))
	if arrival_day < 0:
		return -1
	var active_graph := graph if graph != null else MaritimeGraphScript.load_default()
	var speed_bp := speed_multiplier_bp(fleet)
	var day := arrival_day
	for index in range(path_index + 1, remaining.size()):
		var leg_days := active_graph.leg_cost_days(int(remaining[index - 1]), int(remaining[index]), speed_bp)
		if leg_days < 0:
			return -1
		day += leg_days
	return day


static func is_docked_and_organisable(world: CampaignWorldState, fleet_id: String, country_tag: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return false
	if String(fleet.get("owner_country_id", "")) != country_tag:
		return false
	if bool(fleet.get("movement_locked", false)):
		return false
	# Ship membership cannot change while transport operations reserve this
	# fleet's capacity. Moving even one carrier can invalidate the operation's
	# fleet/army reverse references or silently reduce usable capacity outside
	# TransportSystem's deterministic loss policy.
	if not (fleet.get("transport_operation_ids", []) as Array).is_empty():
		return false
	return String(fleet.get("location_status", "")) == CampaignWorldState.FLEET_LOCATION_DOCKED


## Every ship_id must currently belong to a fleet satisfying
## is_docked_and_organisable for country_tag, and every one of those source
## fleets must be docked at the same port. Returns the shared port ID, or -1
## if the ships are not eligible/co-located.
static func shared_organisable_port(world: CampaignWorldState, ship_ids: Array, country_tag: String) -> int:
	if ship_ids.is_empty():
		return -1
	var port_id := -1
	var seen := {}
	for raw_ship_id in ship_ids:
		var ship_id := String(raw_ship_id)
		if seen.has(ship_id):
			return -1
		seen[ship_id] = true
		var ship := world.get_ship(ship_id)
		if ship.is_empty() or String(ship.get("owner_country_id", "")) != country_tag:
			return -1
		var fleet_id := String(ship.get("fleet_id", ""))
		if not is_docked_and_organisable(world, fleet_id, country_tag):
			return -1
		var fleet_port := int(world.get_fleet(fleet_id).get("location_id", -1))
		if port_id < 0:
			port_id = fleet_port
		elif port_id != fleet_port:
			return -1
	return port_id


## Moves every ship in ship_ids into target_fleet_id, erasing any source
## fleet left with no ships, and recomputes aggregates for every fleet
## touched (sources and target) in stable ID order. Callers are responsible
## for validating eligibility first - this performs no checks itself, since
## SimulationCommand.apply() must never reject; the corresponding validate()
## already confirmed everything shared_organisable_port checks.
static func move_ships(world: CampaignWorldState, ship_ids: Array, target_fleet_id: String, ship_definitions = null) -> void:
	if ship_definitions == null:
		ship_definitions = ShipDefinitionsScript.load_default()
	var touched_fleets := {target_fleet_id: true}
	var sorted_ship_ids: Array = ship_ids.duplicate()
	sorted_ship_ids.sort()
	for raw_ship_id in sorted_ship_ids:
		var ship_id := String(raw_ship_id)
		var ship := world.get_ship(ship_id)
		var source_fleet_id := String(ship.get("fleet_id", ""))
		if source_fleet_id == target_fleet_id:
			continue
		touched_fleets[source_fleet_id] = true
		var source_fleet := world.get_fleet(source_fleet_id)
		var source_members: Array = source_fleet.get("ship_ids", [])
		source_members.erase(ship_id)
		source_fleet["ship_ids"] = source_members
		world.fleet_registry[source_fleet_id] = source_fleet
		ship["fleet_id"] = target_fleet_id
		world.ship_registry[ship_id] = ship
		var target_fleet := world.get_fleet(target_fleet_id)
		var target_members: Array = target_fleet.get("ship_ids", [])
		target_members.append(ship_id)
		target_members.sort()
		target_fleet["ship_ids"] = target_members
		world.fleet_registry[target_fleet_id] = target_fleet
	var fleet_ids := touched_fleets.keys()
	fleet_ids.sort()
	for fleet_id in fleet_ids:
		if world.fleet_registry.has(fleet_id) and (world.fleet_registry[fleet_id] as Dictionary).get("ship_ids", []).is_empty():
			world.fleet_registry.erase(fleet_id)
		elif world.fleet_registry.has(fleet_id):
			recompute_aggregate(world, fleet_id, ship_definitions)
