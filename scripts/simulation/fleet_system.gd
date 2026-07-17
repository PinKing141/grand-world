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
	fleet["aggregate"] = {
		"ship_count": member_ids.size(),
		"total_hull": total_hull,
		"total_maximum_hull": total_maximum_hull,
		"total_attack": total_attack,
		"total_defence": total_defence,
		"total_blockade_power": total_blockade_power,
		"total_transport_capacity": total_transport_capacity,
		"speed": slowest_speed if slowest_speed > 0 else 1,
	}
	world.fleet_registry[fleet_id] = fleet


static func is_docked_and_organisable(world: CampaignWorldState, fleet_id: String, country_tag: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return false
	if String(fleet.get("owner_country_id", "")) != country_tag:
		return false
	if bool(fleet.get("movement_locked", false)):
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
