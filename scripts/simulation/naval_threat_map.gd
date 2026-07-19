class_name NavalThreatMap
extends RefCounted

## FL3.1: the deterministic threat/opportunity query naval_ai_system.gd's own
## _zone_threat() already partly built, now with the cache half the roadmap
## names ("Separate authoritative inputs from derived cache data... Define
## cache revision and invalidation") and three more of its seven named
## inputs (friendly support, recent battles, transport stakes - "ports" is
## folded into supply_days below rather than kept as a redundant separate
## field, a deliberate consolidation, not a missed one).
##
## Cache contract: an assessment is valid for exactly the game-day it was
## computed on, or until NavalThreatMap.invalidate() bumps
## world.global_counters["naval_zone_revision"] - whichever comes first.
## Day-boundary invalidation alone already covers every category the
## roadmap names (fleet, war, access, ownership, port changes): every
## command that could change one of those applies through
## SimulationScheduler.process_commands() before any given day's AI tick
## runs, so a cache that never survives past "the day it was built" can
## never see a stale command's effects - it only ever serves a value
## computed after that day's commands already landed. What day-boundary
## invalidation does NOT cover is a change made *by the AI itself*, mid-tick,
## that should invalidate a *different* zone's assessment before that same
## tick's later queries reach it - true event-triggered intra-day
## invalidation remains open, tracked as FL3.4 follow-on work, not built
## here. NavalThreatMap.invalidate() exists so a future caller that does
## learn about a genuinely urgent mid-day change (a battle starting, a fleet
## destroyed) can force an early rebuild without waiting for the day to
## roll over; nothing currently calls it, which is an honest statement of
## today's scope, not an oversight.
##
## Below the private _compute_*() line is the authoritative recompute -
## pure functions of world state, no cache awareness at all. Above it is
## pure cache bookkeeping that never itself decides anything. Swapping the
## recompute formulas later (FL3.2's richer posture, FL3.4's effective-power
## scoring) should never need to touch the caching contract.

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const ProvinceGraphScript = preload("res://scripts/simulation/province_graph.gd")

const BASIS_POINTS := 10000
# Direct-zone presence weighs full; a hostile fleet merely adjacent still
# matters (it can arrive next leg) but proportionally less - the same coarse
# one-hop falloff _zone_threat() already used before this packet.
const NEIGHBOR_ZONE_THREAT_WEIGHT_BP := 5000
# A battle that started here today weighs full; one RECENT_BATTLE_WINDOW_DAYS
# ago has decayed to zero, linearly in between - "recent battles" per the
# roadmap's own list, using naval_battle_registry's existing zone_id/
# start_day fields (no new instrumentation needed - N4's battle record
# already carries both).
const RECENT_BATTLE_WINDOW_DAYS := 30
const RECENT_BATTLE_WEIGHT_BP := 3000
# Matches FleetLogisticsSystem.SUPPLY_RANGE_DAYS - "how far is too far" is
# already an established naval concept; supply_days reuses that exact bound
# rather than inventing a second, uncalibrated distance scale.
const SUPPLY_RANGE_DAYS := 5

var _cache: Dictionary = {}


## FL3.6: a deterministic, checksummed count of cache rebuilds - not wall-
## clock elapsed time (which must never enter world.global_counters/checksum
## at all - see naval_ai_system.gd's own commands-submitted/decisions
## counters for the established "deterministic integer tallies only"
## precedent this follows). A stress/timing budget belongs at the test-
## harness level instead, the same "measure outside checksummed state"
## pattern naval_fleet_stress_smoke.gd already uses.
static func invalidate(world: CampaignWorldState) -> void:
	world.global_counters["naval_zone_revision"] = int(world.global_counters.get("naval_zone_revision", 0)) + 1


func assess(world: CampaignWorldState, tag: String, zone_id: int, graph: MaritimeGraph = null) -> Dictionary:
	var active_graph := graph if graph != null else MaritimeGraphScript.load_default()
	var key := "%s:%d" % [tag, zone_id]
	var revision := int(world.global_counters.get("naval_zone_revision", 0))
	var cached: Dictionary = _cache.get(key, {})
	if not cached.is_empty() and int(cached.get("day", -1)) == world.current_day and int(cached.get("revision", -1)) == revision:
		world.global_counters["naval_zone_cache_hits"] = int(world.global_counters.get("naval_zone_cache_hits", 0)) + 1
		return (cached["assessment"] as Dictionary).duplicate(true)
	var assessment := _compute(world, tag, zone_id, active_graph)
	_cache[key] = {"day": world.current_day, "revision": revision, "assessment": assessment}
	world.global_counters["naval_zone_cache_rebuilds"] = int(world.global_counters.get("naval_zone_cache_rebuilds", 0)) + 1
	return assessment.duplicate(true)


# ---- authoritative recompute (no cache awareness below this line) ----


func _compute(world: CampaignWorldState, tag: String, zone_id: int, graph: MaritimeGraph) -> Dictionary:
	var hostile_power := _hostile_power(world, tag, zone_id, graph)
	var friendly_power := _friendly_power(world, tag, zone_id)
	var recent_battle_bp := _recent_battle_bp(world, zone_id)
	var has_blockade_target := _has_blockade_target(world, tag, zone_id)
	var transport_stake := _transport_stake(world, tag, zone_id)
	var supply_days := _supply_days(world, tag, zone_id, graph)
	# First-slice combination, not an approved N3/N6 budget - later FL3.2/
	# FL3.4 work is free to recombine these same raw components differently
	# without touching how any of them is individually computed. Recent
	# battle activity amplifies a raw hostile-power reading (a zone fought
	# over recently reads scarier than the same fleet count alone would);
	# friendly power already present directly offsets it.
	var threat_score := maxi(0, hostile_power * (BASIS_POINTS + recent_battle_bp) / BASIS_POINTS - friendly_power)
	var opportunity_score := maxi(0, (BASIS_POINTS if has_blockade_target else 0) - threat_score)
	return {
		"hostile_power": hostile_power,
		"friendly_power": friendly_power,
		"recent_battle_bp": recent_battle_bp,
		"has_blockade_target": has_blockade_target,
		"transport_stake": transport_stake,
		"supply_days": supply_days,
		"threat_score": threat_score,
		"opportunity_score": opportunity_score,
	}


static func _hostile_power(world: CampaignWorldState, tag: String, zone_id: int, graph: MaritimeGraph) -> int:
	var total := 0
	var neighbor_ids := graph.sea_neighbor_ids(zone_id)
	for raw_fleet_id in world.fleet_registry:
		var fleet: Dictionary = world.fleet_registry[raw_fleet_id]
		var owner := String(fleet.get("owner_country_id", ""))
		if owner == tag or DiplomacySystemScript.active_war_between(world, tag, owner).is_empty():
			continue
		var location_id := int(fleet.get("location_id", -1))
		var weight := 0
		if location_id == zone_id:
			weight = BASIS_POINTS
		elif neighbor_ids.has(location_id):
			weight = NEIGHBOR_ZONE_THREAT_WEIGHT_BP
		else:
			continue
		total += int((fleet.get("aggregate", {}) as Dictionary).get("total_attack", 0)) * weight / BASIS_POINTS
	return total


## Own and allied fleets physically in this zone right now - direct presence
## only, not neighbour-weighted (support that hasn't arrived yet isn't
## support). "Friendly support" per the roadmap's own FL3.1 input list.
static func _friendly_power(world: CampaignWorldState, tag: String, zone_id: int) -> int:
	var total := 0
	for raw_fleet_id in world.fleet_registry:
		var fleet: Dictionary = world.fleet_registry[raw_fleet_id]
		if int(fleet.get("location_id", -1)) != zone_id:
			continue
		var owner := String(fleet.get("owner_country_id", ""))
		if owner != tag and not DiplomacySystemScript.are_allied(world, tag, owner):
			continue
		total += int((fleet.get("aggregate", {}) as Dictionary).get("total_attack", 0))
	return total


## Linear decay from full weight (a battle started here today) to zero at
## RECENT_BATTLE_WINDOW_DAYS ago - "recent battles" without inventing new
## persisted history, reusing naval_battle_registry's own zone_id/start_day
## fields directly. A zone can have hosted more than one recent battle;
## the strongest (most recent) signal wins rather than summing, since this
## is meant to answer "how hot is this zone lately," not "how many battles."
static func _recent_battle_bp(world: CampaignWorldState, zone_id: int) -> int:
	var strongest := 0
	for raw_battle_id in world.naval_battle_registry:
		var battle: Dictionary = world.naval_battle_registry[raw_battle_id]
		if int(battle.get("zone_id", -1)) != zone_id:
			continue
		var age := world.current_day - int(battle.get("start_day", -RECENT_BATTLE_WINDOW_DAYS - 1))
		if age < 0 or age > RECENT_BATTLE_WINDOW_DAYS:
			continue
		var weight := RECENT_BATTLE_WEIGHT_BP * (RECENT_BATTLE_WINDOW_DAYS - age) / RECENT_BATTLE_WINDOW_DAYS
		if weight > strongest:
			strongest = weight
	return strongest


## Reuses BlockadeSystem's own reciprocal land_neighbors() relationship
## (matching _zone_has_blockade_target()'s pre-existing logic exactly, moved
## here rather than duplicated) - true if any land neighbour of this sea
## zone is a hostile-owned coastal province worth blockading.
static func _has_blockade_target(world: CampaignWorldState, tag: String, zone_id: int) -> bool:
	for raw_province_id in ProvinceGraphScript.load_default().land_neighbors(zone_id):
		var province_id := int(raw_province_id)
		var target_owner := world.get_province_owner(province_id)
		if target_owner.is_empty() or target_owner == tag:
			continue
		if not DiplomacySystemScript.active_war_between(world, tag, target_owner).is_empty():
			return true
	return false


## The regiment-capacity value of this country's own transport operations
## physically sailing through this zone right now (current_location_id ==
## zone_id, the same field TransportSystem itself updates each day a
## carrier is mid-leg) - "transport stakes" per the roadmap's own input
## list: how much would be at risk here if this zone turned dangerous.
static func _transport_stake(world: CampaignWorldState, tag: String, zone_id: int) -> int:
	var total := 0
	for raw_operation_id in world.transport_operation_registry:
		var operation: Dictionary = world.transport_operation_registry[raw_operation_id]
		if String(operation.get("country_tag", "")) != tag:
			continue
		if int(operation.get("current_location_id", -1)) != zone_id:
			continue
		total += int(operation.get("reserved_capacity", 0))
	return total


## Days from this zone to the nearest port this country may legally base
## at, bounded by SUPPLY_RANGE_DAYS - -1 if none is reachable within that
## range. Folds the roadmap's separate "ports" input into one distance
## signal rather than a second, redundant "is a port nearby" boolean -
## supply_days already answers that more usefully.
static func _supply_days(world: CampaignWorldState, tag: String, zone_id: int, graph: MaritimeGraph) -> int:
	var query := NavalAccessPolicyScript.supply_range_query(graph, world, tag, zone_id, SUPPLY_RANGE_DAYS)
	return int(query["range_cost"]) if bool(query["supplied"]) else -1
