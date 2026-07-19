class_name FleetLogisticsSystem
extends RefCounted

## N2.4: supply status, attrition, and repair for fleets. Mirrors the
## "walk every registry entry once a day/month" shape ArmyMovementSystem,
## FleetMovementSystem, and EconomySystem already use - no new processing
## model invented. See docs/roadmap/naval/02_N2_FLEET_LOGISTICS.md "Basing,
## Supply, Attrition, and Repair".

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBus = preload("res://scripts/simulation/simulation_event_bus.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")

const BASIS_POINTS := 10000

# Placeholder first-slice constants - not approved N0 budgets, the same
# "simple explainable formula now, balance later" precedent N2.2 already set
# for SAILORS_PER_OWNED_PORT/SAILOR_RECOVERY_MONTHS.
const SUPPLY_RANGE_DAYS := 5
const ATTRITION_HULL_LOSS_BP := 500
const ATTRITION_CREW_LOSS_BP := 500
const MIN_HULL_BP := 1000
const MIN_CREW_BP := 1000
const REPAIR_COST_FRACTION_BP := 500

# 05_N5 "Province and Port Effects": "Reduced port repair/construction
# effectiveness at high blockade." Reuses the same threshold shape
# BlockadeSystem.SIEGE_ASSIST_THRESHOLD_BP already established (a blockade
# must clear half effectiveness before it counts for anything downstream) -
# not the same constant, since repair and siege assist are unrelated
# consumers that could reasonably be tuned independently later, but the same
# placeholder magnitude for consistency until real balance exists.
const BLOCKADE_EFFECTIVENESS_THRESHOLD_BP := 5000
const BLOCKADE_REPAIR_PENALTY_BP := 5000


## A docked fleet at its own (or an allied/subject) basing-right port is
## trivially supplied; NavalAccessPolicy.supply_range_query cannot answer
## that directly because nearest_matching excludes the origin from its own
## search (see that function's doc comment) - so the origin is checked here
## first, and the range query only runs when the fleet needs to reach
## somewhere else for supply.
static func recompute_supply(world: CampaignWorldState, events: SimulationEventBus, fleet_id: String, graph: MaritimeGraph = null) -> void:
	var fleet: Dictionary = world.fleet_registry[fleet_id]
	var owner := String(fleet.get("owner_country_id", ""))
	var location_id := int(fleet.get("location_id", -1))
	var active_graph := graph if graph != null else MaritimeGraphScript.load_default()
	var supplied := false
	var reason := ""
	if NavalAccessPolicyScript.can_base(active_graph, world, owner, location_id):
		supplied = true
	else:
		var query := NavalAccessPolicyScript.supply_range_query(active_graph, world, owner, location_id, SUPPLY_RANGE_DAYS)
		supplied = bool(query["supplied"])
		reason = String(query["failure_reason"])
	var previous := bool(fleet.get("supplied", true))
	fleet["supplied"] = supplied
	fleet["supply_reason"] = reason
	world.fleet_registry[fleet_id] = fleet
	if previous != supplied:
		events.fleet_supply_changed.emit(fleet_id, supplied, reason)


## FL2.1 closure: the fleet panel only ever inferred repair activity from the
## mission == "repair" tag, so a fleet passively healing without that mission
## set (attrition sets per-ship "repairing" independently of any mission,
## see _repair_one_ship()/_apply_attrition() below) showed nothing. This
## reads the same authoritative per-ship flag those functions already
## maintain, rather than the UI re-deriving it from hull/crew thresholds
## itself.
static func repairing_ship_count(world: CampaignWorldState, fleet_id: String) -> int:
	var count := 0
	for ship_id in world.fleet_ships(fleet_id):
		if bool(world.get_ship(ship_id).get("repairing", false)):
			count += 1
	return count


static func process_day(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var graph := MaritimeGraphScript.load_default()
	var ship_definitions := ShipDefinitionsScript.load_default()
	# A port's blockade value is identical for every friendly fleet repairing
	# there during this tick. Computing it once per fleet made the common
	# many-fleets-in-one-port case quadratic because BlockadeSystem must scan
	# the fleet registry to find contributors.
	var blockade_by_port := {}
	var fleet_ids := world.fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		recompute_supply(world, events, fleet_id, graph)
		_process_repair(world, events, fleet_id, ship_definitions, graph, blockade_by_port)


## Repair requires a *legal repair port*, a stricter bar than "supplied" (an
## at-sea fleet can be supplied by a port days away without being able to
## repair there) - 02_N2_FLEET_LOGISTICS.md "Requires a legal repair port and
## a docked fleet." Allocation walks ships in stable sorted-ID order so a
## treasury shortfall always favours the same ships first, run to run.
static func _process_repair(
	world: CampaignWorldState,
	events: SimulationEventBus,
	fleet_id: String,
	ship_definitions: ShipDefinitions,
	graph: MaritimeGraph,
	blockade_by_port: Dictionary = {}
) -> void:
	var fleet: Dictionary = world.fleet_registry[fleet_id]
	if String(fleet.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_DOCKED:
		return
	var owner := String(fleet.get("owner_country_id", ""))
	var location_id := int(fleet.get("location_id", -1))
	if not NavalAccessPolicyScript.can_base(graph, world, owner, location_id):
		return
	var ship_ids := (fleet.get("ship_ids", []) as Array).duplicate()
	ship_ids.sort()
	var needs_repair := false
	for raw_ship_id in ship_ids:
		var ship_id := String(raw_ship_id)
		if not world.ship_registry.has(ship_id):
			continue
		var condition: Dictionary = world.ship_registry[ship_id]
		if int(condition.get("hull_bp", 10000)) < BASIS_POINTS or int(condition.get("crew_bp", 10000)) < BASIS_POINTS:
			needs_repair = true
			break
	if not needs_repair:
		return
	# A docked fleet's location_id is the port's own province_id (a land
	# province), so it is directly queryable as a blockade target - no
	# sea-zone translation needed.
	var rate_scale_bp := BASIS_POINTS
	if not blockade_by_port.has(location_id):
		blockade_by_port[location_id] = BlockadeSystemScript.province_blockade_bp(world, location_id)
	if int(blockade_by_port[location_id]) >= BLOCKADE_EFFECTIVENESS_THRESHOLD_BP:
		rate_scale_bp = BASIS_POINTS - BLOCKADE_REPAIR_PENALTY_BP
	var touched := false
	for raw_ship_id in ship_ids:
		var ship_id := String(raw_ship_id)
		if not world.ship_registry.has(ship_id):
			continue
		if _repair_one_ship(world, ship_id, owner, ship_definitions, rate_scale_bp):
			touched = true
			if int((world.ship_registry[ship_id] as Dictionary).get("hull_bp", 0)) >= 10000 and int((world.ship_registry[ship_id] as Dictionary).get("crew_bp", 0)) >= 10000:
				events.fleet_repair_completed.emit(fleet_id, ship_id)
	if touched:
		FleetSystemScript.recompute_aggregate(world, fleet_id, ship_definitions)
		events.fleet_repair_progressed.emit(fleet_id)


static func _repair_one_ship(world: CampaignWorldState, ship_id: String, owner: String, ship_definitions: ShipDefinitions, rate_scale_bp: int = BASIS_POINTS) -> bool:
	var ship: Dictionary = world.ship_registry[ship_id]
	var hull_bp := int(ship.get("hull_bp", 10000))
	var crew_bp := int(ship.get("crew_bp", 10000))
	if hull_bp >= 10000 and crew_bp >= 10000:
		if bool(ship.get("repairing", false)):
			ship["repairing"] = false
			world.ship_registry[ship_id] = ship
		return false
	if not ship_definitions.has_ship(String(ship.get("definition_id", ""))):
		return false
	var definition := ship_definitions.ship(String(ship.get("definition_id", "")))
	var daily_rate_bp := int(definition.get("repair_rate_bp", 0)) * rate_scale_bp / BASIS_POINTS
	var hull_gain_bp: int = mini(daily_rate_bp, 10000 - hull_bp)
	var full_repair_cost: int = int(definition.get("cost", 0)) * REPAIR_COST_FRACTION_BP / 10000
	var money_cost: int = full_repair_cost * hull_gain_bp / 10000
	var crew_gain_bp: int = mini(daily_rate_bp, 10000 - crew_bp)
	var sailor_cost: int = int(definition.get("sailor_cost", 0)) * crew_gain_bp / 10000
	var runtime := world.country_runtime(owner)
	if hull_gain_bp > 0 and int(runtime.get("treasury", 0)) < money_cost:
		hull_gain_bp = 0
	if crew_gain_bp > 0 and int(runtime.get("sailors", 0)) < sailor_cost:
		crew_gain_bp = 0
	if hull_gain_bp <= 0 and crew_gain_bp <= 0:
		return false
	if hull_gain_bp > 0:
		runtime["treasury"] = int(runtime.get("treasury", 0)) - money_cost
		hull_bp = mini(10000, hull_bp + hull_gain_bp)
	if crew_gain_bp > 0:
		runtime["sailors"] = int(runtime.get("sailors", 0)) - sailor_cost
		crew_bp = mini(10000, crew_bp + crew_gain_bp)
	world.set_country_runtime(owner, runtime)
	ship["hull_bp"] = hull_bp
	ship["crew_bp"] = crew_bp
	ship["repairing"] = hull_bp < 10000 or crew_bp < 10000
	world.ship_registry[ship_id] = ship
	return true


static func process_month(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var fleet_ids := world.fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		_apply_attrition(world, events, String(raw_fleet_id))


## Attrition never destroys a ship (floor at MIN_HULL_BP/MIN_CREW_BP) and
## only fires for fleets currently reporting unsupplied - 02_N2's "cannot
## reduce hull or sailors below defined bounds" and "depends on... supply
## status." No RNG stream: the first slice keeps this deterministic, matching
## 02_N2's "only where variance is approved" (none has been approved yet).
static func _apply_attrition(world: CampaignWorldState, events: SimulationEventBus, fleet_id: String) -> void:
	var fleet: Dictionary = world.fleet_registry[fleet_id]
	if bool(fleet.get("supplied", true)):
		return
	var ship_ids := (fleet.get("ship_ids", []) as Array).duplicate()
	ship_ids.sort()
	var total_hull_lost := 0
	var total_crew_lost := 0
	for raw_ship_id in ship_ids:
		var ship_id := String(raw_ship_id)
		if not world.ship_registry.has(ship_id):
			continue
		var ship: Dictionary = world.ship_registry[ship_id]
		var hull_bp := int(ship.get("hull_bp", 10000))
		var crew_bp := int(ship.get("crew_bp", 10000))
		var new_hull: int = maxi(MIN_HULL_BP, hull_bp - ATTRITION_HULL_LOSS_BP)
		var new_crew: int = maxi(MIN_CREW_BP, crew_bp - ATTRITION_CREW_LOSS_BP)
		if new_hull == hull_bp and new_crew == crew_bp:
			continue
		total_hull_lost += hull_bp - new_hull
		total_crew_lost += crew_bp - new_crew
		ship["hull_bp"] = new_hull
		ship["crew_bp"] = new_crew
		ship["repairing"] = new_hull < 10000 or new_crew < 10000
		world.ship_registry[ship_id] = ship
	if total_hull_lost > 0 or total_crew_lost > 0:
		FleetSystemScript.recompute_aggregate(world, fleet_id)
		events.fleet_attrition_applied.emit(fleet_id, total_hull_lost, total_crew_lost)
