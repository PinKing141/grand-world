class_name NavalTradeProtection
extends RefCounted

## FL5.1: a stable, derived naval output for a future trade system that
## does not exist yet (docs/roadmap/naval/g1_finish_line/05_FL5_STRATEGIC_
## CONTRACT_CLOSEOUT.md). This computes ONLY the naval half - "how much
## protective naval capability does this country have at this zone or
## port" - never a currency/income value, since that needs a trade/market
## system (routes, nodes, goods) this slice must explicitly not fabricate
## ("do not fabricate income, routes, markets or trade nodes"). Trade
## income calculation itself stays entirely outside this file, in whatever
## future economy system consumes this output - nothing here writes to
## country_runtime, EconomySystem, or any ledger field. Until a real
## consumer exists, this has zero behavioural effect on the game by
## construction: it is a pure query nothing currently calls.
##
## Mirrors BlockadeSystem's own eligibility/effective-power shape exactly
## (is_fleet_eligible()/effective_power() below) rather than inventing a
## second model - "eligible fleet mission, effective power, supply and
## contested-zone rules" is almost verbatim BlockadeSystem's own "Blockade
## Assignment"/"Contested Zones" rules, just gated on the trade_protection
## mission instead of blockade. Reuses BlockadeSystem.zone_is_contested()
## directly for the contested-zone check rather than a third duplicate of
## that logic - both systems cite the same 05_N5 "Contested Zones" source
## for an identical definition of "contested," not just a similar one.

const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")

const BASIS_POINTS := 10000


## "It is at sea in a zone... mission permits [trade protection]...
## supply... above defined minimum effectiveness... not contested" -
## BlockadeSystem.is_fleet_eligible()'s own rules, mission substituted.
static func is_fleet_eligible(world: CampaignWorldState, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return false
	if String(fleet.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_AT_SEA:
		return false
	if String(fleet.get("mission", "idle")) != "trade_protection":
		return false
	if not bool(fleet.get("supplied", true)):
		return false
	if BlockadeSystemScript.zone_is_contested(world, fleet_id):
		return false
	return true


## Damaged fleets contribute proportionally less, using the fleet
## aggregate's own hull ratio, below a hard cutoff below which a badly
## damaged fleet contributes nothing at all - the exact same
## DAMAGED_EFFECTIVENESS_THRESHOLD_BP shape BlockadeSystem.effective_power()
## already uses, reused here rather than a second formula or a second
## threshold constant.
static func effective_power(world: CampaignWorldState, fleet_id: String) -> int:
	if not is_fleet_eligible(world, fleet_id):
		return 0
	var aggregate: Dictionary = world.get_fleet(fleet_id).get("aggregate", {})
	var max_hull := int(aggregate.get("total_maximum_hull", 0))
	if max_hull <= 0:
		return 0
	var hull_bp := int(aggregate.get("total_hull", 0)) * BASIS_POINTS / max_hull
	if hull_bp < BlockadeSystemScript.DAMAGED_EFFECTIVENESS_THRESHOLD_BP:
		return 0
	return int(aggregate.get("total_attack", 0)) * hull_bp / BASIS_POINTS


## The naval trade-protection output for one country at one sea zone or
## port: the summed effective power of every eligible trade_protection
## fleet this country has physically present there right now, contested-
## aware and zero-safe throughout. Deterministic (sorted fleet iteration,
## plain integer sum) and bounded (one country's own fleet count at one
## location, never the whole map). Returns a structured result rather than
## a bare int specifically so "zero because nothing is eligible" and "zero
## because the zone is contested" remain distinguishable to a future
## consumer, matching the roadmap's own "return zero with an explanation"
## requirement.
static func assess(world: CampaignWorldState, tag: String, location_id: int) -> Dictionary:
	var eligible_fleet_ids: Array[String] = []
	var protection_score := 0
	var fleet_ids := world.country_fleets(tag)
	fleet_ids.sort()
	var any_present_on_mission := false
	var contested := false
	for fleet_id in fleet_ids:
		var fleet := world.get_fleet(fleet_id)
		if int(fleet.get("location_id", -1)) != location_id:
			continue
		if String(fleet.get("mission", "idle")) != "trade_protection":
			continue
		any_present_on_mission = true
		if BlockadeSystemScript.zone_is_contested(world, fleet_id):
			contested = true
			continue
		var power := effective_power(world, fleet_id)
		if power <= 0:
			continue
		eligible_fleet_ids.append(fleet_id)
		protection_score += power
	var reason: String
	if not eligible_fleet_ids.is_empty():
		reason = "Protected by %d trade_protection fleet(s) with %d total effective power." % [eligible_fleet_ids.size(), protection_score]
	elif contested:
		reason = "A trade_protection fleet is present but the zone is contested by hostile naval power."
	elif any_present_on_mission:
		reason = "A trade_protection fleet is present but not currently eligible (unsupplied or otherwise inactive)."
	else:
		reason = "No fleet is assigned to trade protection at this location."
	return {
		"protection_score": protection_score,
		"eligible_fleet_ids": eligible_fleet_ids,
		"contested": contested,
		"reason": reason,
	}
