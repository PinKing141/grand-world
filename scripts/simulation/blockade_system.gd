class_name BlockadeSystem
extends RefCounted

## N5A: blockade eligibility and power queries. See
## docs/roadmap/naval/05_N5_STRATEGIC_EFFECTS.md "Blockade Assignment" and
## "Blockade Power". Deliberately a pure query layer, not a persistent
## registry - "Blockade is calculated from fleet/zone/target state, not
## written directly by UI" (05_N5). Nothing here is cached; every call
## recomputes from current world state, the same "scan and filter" pattern
## armies_in_province()/country_fleets() already use rather than maintaining
## a parallel reverse index that could drift out of sync. War-score
## accumulation, economy/siege effects, and threshold-change events are N5B/
## C/D, once there is a persistent value to accumulate against.

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const NavalDefinitionsScript = preload("res://scripts/simulation/naval_definitions.gd")

const BASIS_POINTS := 10000
const MAX_PROVINCE_BLOCKADE_BP := 10000

# "Province blockade level changed across meaningful thresholds" (05_N5
# "Events and Queries") - "Thresholded events avoid daily notification
# spam." Five quartile-ish buckets, not approved balance, chosen only to be
# few enough that a slowly-building or -fading blockade crosses a boundary
# occasionally rather than every day. NONE is not stored in
# blockaded_provinces at all (a bp<=0 province is simply absent), included
# here only so blockade_tier() has a defined value for "not blockaded."
const BLOCKADE_TIER_NONE := 0
const BLOCKADE_TIER_LIGHT := 1
const BLOCKADE_TIER_MODERATE := 2
const BLOCKADE_TIER_HEAVY := 3
const BLOCKADE_TIER_SEVERE := 4
const BLOCKADE_TIER_FULL := 5

# Target-resistance placeholder constants (05_N5 "Blockade Power" - "Target
# resistance may include: Coastal development/port importance. Harbour/
# fort/shipyard level..."). Every real province has some baseline resistance
# (BASE_REQUIRED_POWER) even if undeveloped and not a registered port, so a
# single ship can never fully blockade anywhere. Development reuses the raw
# base_tax/base_production fields already on every province's economy dict -
# not the fully modified province_outputs() value, which would pull in
# EconomyDefinitions/trade-good lookups and, worse, create a preload cycle
# with economy_system.gd (which already preloads this script). Harbour level
# reuses NavalDefinitions' existing per-port harbour_level field (until now
# only consumed by ship-construction gating) rather than inventing a second
# port-tier concept. None of this is approved balance - it is the simplest
# formula that makes required power scale with a province's real, already-
# authored data instead of being a fixed floor.
const BASE_REQUIRED_POWER := 5
const HARBOUR_LEVEL_REQUIRED_POWER := 5

# Placeholder first-slice effectiveness floor, not an approved N0 budget -
# mirrors TransportSystem.DAMAGED_CAPACITY_THRESHOLD_BP's binary-threshold
## precedent: a fleet below half hull contributes no blockade power at all,
# "the simplest rule that is genuinely explicit and cannot fluctuate
# unpredictably from presentation values."
const DAMAGED_EFFECTIVENESS_THRESHOLD_BP := 5000


## Buckets a raw blockade bp value into one of the BLOCKADE_TIER_* constants
## above - the granularity "meaningful threshold" change detection compares,
## instead of firing on every single bp fluctuation.
static func blockade_tier(bp: int) -> int:
	if bp <= 0:
		return BLOCKADE_TIER_NONE
	if bp >= BASIS_POINTS:
		return BLOCKADE_TIER_FULL
	if bp >= 7500:
		return BLOCKADE_TIER_SEVERE
	if bp >= 5000:
		return BLOCKADE_TIER_HEAVY
	if bp >= 2500:
		return BLOCKADE_TIER_MODERATE
	return BLOCKADE_TIER_LIGHT


## "It is at sea in a zone... Its mission permits blockade... at war with the
## target owner... not retreating, in port, destroyed, or otherwise
## inactive... Supply... above defined minimum effectiveness" (05_N5
## "Blockade Assignment"). A fleet in active battle is also excluded - "an
## active naval battle pauses/contests power" (05_N5 "Contested Zones") - and
## so is a fleet sharing its zone with an opposing at-sea fleet that hasn't
## (yet) triggered a battle (see _zone_is_contested()): without that check,
## the one-tick lag between an enemy fleet arriving in a zone and
## NavalCombatSystem starting a battle the following day would let a
## blockade briefly persist as if uncontested.
static func is_fleet_eligible(world: CampaignWorldState, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return false
	if String(fleet.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_AT_SEA:
		return false
	if String(fleet.get("mission", "idle")) != "blockade":
		return false
	if not bool(fleet.get("supplied", true)):
		return false
	if _zone_is_contested(world, fleet_id):
		return false
	return true


## True if an opposing (hostile, at-war) fleet is also AT_SEA in the same
## zone as `fleet_id` - "Opposing eligible fleets reduce or eliminate
## blockade contribution" (05_N5 "Contested Zones"). Eliminating (not merely
## reducing) contribution when contested is this slice's simplification -
## the same binary-threshold shape "in active battle = ineligible" already
## uses, not the proportional/diminishing-return contest 05_N5 also allows
## for. A docked opposing fleet does not contest - it is not actually
## present in the zone, mirroring is_fleet_eligible()'s own AT_SEA
## requirement for the blockading fleet itself.
static func _zone_is_contested(world: CampaignWorldState, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	var owner := String(fleet.get("owner_country_id", ""))
	var zone_id := int(fleet.get("location_id", -1))
	var other_ids := world.fleet_registry.keys()
	other_ids.sort()
	for raw_other_id in other_ids:
		var other_id := String(raw_other_id)
		if other_id == fleet_id:
			continue
		var other := world.get_fleet(other_id)
		if int(other.get("location_id", -1)) != zone_id:
			continue
		if String(other.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_AT_SEA:
			continue
		var other_owner := String(other.get("owner_country_id", ""))
		if DiplomacySystemScript.active_war_between(world, owner, other_owner).is_empty():
			continue
		return true
	return false


## Damaged fleets contribute proportionally less, using the fleet aggregate's
## own hull ratio - the same damage-scaling shape NavalCombatSystem already
## applies to combat power, reused here rather than a second formula.
static func effective_power(world: CampaignWorldState, fleet_id: String) -> int:
	if not is_fleet_eligible(world, fleet_id):
		return 0
	var aggregate: Dictionary = world.get_fleet(fleet_id).get("aggregate", {})
	var max_hull := int(aggregate.get("total_maximum_hull", 0))
	if max_hull <= 0:
		return 0
	var hull_bp := int(aggregate.get("total_hull", 0)) * BASIS_POINTS / max_hull
	if hull_bp < DAMAGED_EFFECTIVENESS_THRESHOLD_BP:
		return 0
	return int(aggregate.get("total_blockade_power", 0)) * hull_bp / BASIS_POINTS


## Every coastal land province adjacent to the fleet's current sea zone that
## the fleet's country is at war with the owner of - "A fleet may affect
## multiple adjacent provinces" (05_N5 "Blockade Assignment"). A fleet
## docked at a port contributes to nothing (is_fleet_eligible already
## excludes non-AT_SEA fleets), so this only ever runs from a genuine sea
## zone, where ProvinceGraph.land_neighbors() returns the zone's coastal
## land provinces (the reciprocal of each land province's own sea exits).
static func blockaded_provinces_for_fleet(world: CampaignWorldState, fleet_id: String) -> Array[int]:
	var found: Array[int] = []
	if not is_fleet_eligible(world, fleet_id):
		return found
	var fleet := world.get_fleet(fleet_id)
	var owner := String(fleet.get("owner_country_id", ""))
	var zone_id := int(fleet.get("location_id", -1))
	var graph := ProvinceGraph.load_default()
	for raw_province_id in graph.land_neighbors(zone_id):
		var province_id := int(raw_province_id)
		var target_owner := world.get_province_owner(province_id)
		if target_owner.is_empty() or target_owner == owner:
			continue
		if not DiplomacySystemScript.active_war_between(world, owner, target_owner).is_empty():
			found.append(province_id)
	found.sort()
	return found


## How much attacker power a province's own development and port defences
## demand before it counts as fully (10000 bp) blockaded - "Target resistance
## may include: Coastal development/port importance. Harbour/fort/shipyard
## level..." (05_N5 "Blockade Power"). A non-port, undeveloped coastal
## province still has the BASE_REQUIRED_POWER floor; an established, well-
## harboured port needs proportionally more attacker power to fully choke.
static func _required_power(world: CampaignWorldState, province_id: int, naval_definitions: NavalDefinitions) -> int:
	var economy: Dictionary = (world.province_states.get(province_id, {}) as Dictionary).get("economy", {})
	var development := int(economy.get("base_tax", 0)) + int(economy.get("base_production", 0))
	var harbour_level := 0
	if naval_definitions.is_port(province_id):
		harbour_level = int(naval_definitions.port(province_id).get("harbour_level", 0))
	return BASE_REQUIRED_POWER + development + harbour_level * HARBOUR_LEVEL_REQUIRED_POWER


## Sums effective power from every eligible fleet contributing to this
## province, in stable fleet-ID order, optionally restricted to owners in
## `countries_filter` (an empty array means "any hostile fleet"). Shared by
## province_blockade_bp() (unfiltered - the whole-world query) and
## blockade_bp_by_side() (filtered - the specific-coalition query coastal
## siege assist needs, since not every hostile fleet blockading a province
## is necessarily on the besieging army's own side of the war).
static func _sum_eligible_power(world: CampaignWorldState, province_id: int, countries_filter: Array) -> int:
	var total := 0
	var fleet_ids := world.fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		if not countries_filter.is_empty():
			var owner := String(world.get_fleet(fleet_id).get("owner_country_id", ""))
			if not countries_filter.has(owner):
				continue
		if not is_fleet_eligible(world, fleet_id):
			continue
		if not blockaded_provinces_for_fleet(world, fleet_id).has(province_id):
			continue
		total += effective_power(world, fleet_id)
	return total


## Sums effective power from every eligible hostile fleet contributing to
## this province, in stable fleet-ID order, then expresses that power as a
## basis-point fraction of the target's own required power (see
## _required_power()), clamped to [0, 10000] - "the result is an integer
## blockade basis-point value... clamped" (05_N5 "Blockade Power"). Summing
## attacker power (rather than a diminishing-return curve) is this slice's
## placeholder combination rule, not approved balance.
static func province_blockade_bp(world: CampaignWorldState, province_id: int) -> int:
	var total := _sum_eligible_power(world, province_id, [])
	if total <= 0:
		return 0
	var required := _required_power(world, province_id, NavalDefinitionsScript.load_default())
	return clampi(total * BASIS_POINTS / maxi(required, 1), 0, MAX_PROVINCE_BLOCKADE_BP)


## The same resistance-adjusted bp calculation as province_blockade_bp(), but
## counting only fleets owned by a specific coalition (`contributing_countries`)
## - a war may have hostile fleets from an unrelated third war, or from an
## ally not actually besieging this particular province, also blockading the
## same target; coastal siege assist should only credit the besieging side's
## own contribution, not the world's total hostile presence.
static func blockade_bp_by_side(world: CampaignWorldState, contributing_countries: Array, province_id: int) -> int:
	var total := _sum_eligible_power(world, province_id, contributing_countries)
	if total <= 0:
		return 0
	var required := _required_power(world, province_id, NavalDefinitionsScript.load_default())
	return clampi(total * BASIS_POINTS / maxi(required, 1), 0, MAX_PROVINCE_BLOCKADE_BP)


# Placeholder first-slice siege-assist constants (05_N5 "Coastal Siege
# Support"): a blockade must reach at least half effectiveness before it
# meaningfully hinders a coastal siege, and even a fully choked port only
# speeds land siege progress by a flat fraction, not a multiple - land
# armies, not naval blockade, remain "siege authority" per that section.
const SIEGE_ASSIST_THRESHOLD_BP := 5000
const SIEGE_ASSIST_BONUS_BP := 2500


## "A coastal siege receives blockade assistance only when: the province is
## genuinely coastal and linked to the blockading zone... the fleet and
## besieger are on compatible war sides... effective blockade meets the
## configured threshold... the port is not already controlled in a way that
## makes blockade irrelevant" (05_N5 "Coastal Siege Support"). The province-
## already-controlled-by-besieger case is the caller's (WarfareSystem's)
## responsibility, same as it already is for starting a siege at all - this
## query only answers "coastal, on-side, above-threshold blockade bp, or
## zero." "The land warfare system remains siege authority. Naval publishes
## a blockade contribution query; it does not directly complete or occupy
## provinces" - this function returns a query result, nothing more.
static func siege_assist_bp(world: CampaignWorldState, besieging_side_countries: Array, province_id: int) -> int:
	if not NavalDefinitionsScript.load_default().is_port(province_id):
		return 0
	var bp := blockade_bp_by_side(world, besieging_side_countries, province_id)
	if bp < SIEGE_ASSIST_THRESHOLD_BP:
		return 0
	return bp


## Every province at least one currently eligible fleet contributes to,
## across the whole world - the query a future war-score/economy/siege pass
## (N5B/C/D) will walk once those exist to accumulate against.
static func all_blockaded_provinces(world: CampaignWorldState) -> Array[int]:
	var found := {}
	var fleet_ids := world.fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		for province_id in blockaded_provinces_for_fleet(world, fleet_id):
			found[province_id] = true
	var result: Array[int] = []
	for province_id in found:
		result.append(int(province_id))
	result.sort()
	return result


const DAILY_BLOCKADE_SCORE_STEP := 1
const BLOCKADE_SCORE_MIN := -25
const BLOCKADE_SCORE_MAX := 25


## True if at least one eligible fleet owned by a `blockading_side` country
## currently achieves a genuine (resistance-adjusted, non-zero bp) blockade
## of a province owned by a `blockaded_side` country - the per-war "is there
## an active blockade advantage" fact update_war_blockade_score() accumulates
## against. Checks province_blockade_bp() rather than mere candidate
## presence in blockaded_provinces_for_fleet() so a fleet too weak to
## overcome a well-defended target's required power does not count as
## "blockading" for war-score purposes either.
static func _side_blockades_other(world: CampaignWorldState, blockading_side: Array, blockaded_side: Array) -> bool:
	var blockaded_owners := {}
	for raw_tag in blockaded_side:
		blockaded_owners[String(raw_tag)] = true
	var fleet_ids := world.fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		var owner := String(world.get_fleet(fleet_id).get("owner_country_id", ""))
		if not blockading_side.has(owner):
			continue
		if not is_fleet_eligible(world, fleet_id):
			continue
		for province_id in blockaded_provinces_for_fleet(world, fleet_id):
			if blockaded_owners.has(world.get_province_owner(province_id)) and province_blockade_bp(world, province_id) > 0:
				return true
	return false


## War blockade score is a bounded daily accumulator, not a fresh-recompute
## like occupation_score_attacker - 05_N5 "Blockade War Score" requires it to
## grow "without an active eligible blockade" being impossible and to decay
## on release rather than reset. Whichever side currently has an
## uncontested blockade advantage (blockading the other side and not
## simultaneously being blockaded back) gains one point per day; with no
## advantage either way the score decays one point per day toward zero.
## Both sides blockading each other simultaneously holds the score steady -
## the simplest explicit rule for an otherwise-ambiguous case.
static func update_war_blockade_score(world: CampaignWorldState, war: Dictionary) -> int:
	var attackers: Array = war.get("attackers", [])
	var defenders: Array = war.get("defenders", [])
	var attacker_blockading := _side_blockades_other(world, attackers, defenders)
	var defender_blockading := _side_blockades_other(world, defenders, attackers)
	var current := int(war.get("blockade_score_attacker", 0))
	if attacker_blockading and not defender_blockading:
		current = mini(current + DAILY_BLOCKADE_SCORE_STEP, BLOCKADE_SCORE_MAX)
	elif defender_blockading and not attacker_blockading:
		current = maxi(current - DAILY_BLOCKADE_SCORE_STEP, BLOCKADE_SCORE_MIN)
	elif not attacker_blockading and not defender_blockading:
		if current > 0:
			current = maxi(0, current - DAILY_BLOCKADE_SCORE_STEP)
		elif current < 0:
			current = mini(0, current + DAILY_BLOCKADE_SCORE_STEP)
	return current


## "Blockade started/ended," "Port fully blockaded/unblocked," and "Province
## blockade level changed across meaningful thresholds" (05_N5 "Events and
## Queries"). The only piece of state this pure query layer persists: each
## genuinely (resistance-adjusted, non-zero bp) blockaded province's actual
## bp value as of the last daily check, so all three transitions can be
## detected from the same stored values - a bare query has nothing to
## compare "now" against. Run once per day, after NavalCombatSystem has had
## a chance to start any battle a newly-arrived contesting fleet triggers,
## so the recorded state reflects the day's settled outcome rather than a
## mid-day intermediate one. "Port fully blockaded/unblocked" only fires
## for registered ports (NavalDefinitions.is_port()) - "blockade started/
## ended" and the tier-change signal apply to any blockaded coastal
## province, matching blockaded_provinces_for_fleet()'s own broader
## targeting, but a fully-choked *port* specifically is what 05_N5 names
## for that second signal.
static func process_day(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var previous: Dictionary = world.blockaded_provinces
	var current := {}
	for province_id in all_blockaded_provinces(world):
		var bp := province_blockade_bp(world, province_id)
		if bp > 0:
			current[str(province_id)] = bp
	var naval_definitions := NavalDefinitionsScript.load_default()
	var all_ids := {}
	for raw_id in previous:
		all_ids[raw_id] = true
	for raw_id in current:
		all_ids[raw_id] = true
	var ids := all_ids.keys()
	ids.sort()
	for raw_id in ids:
		var province_id := int(raw_id)
		var key := str(province_id)
		var was_blockaded := previous.has(key)
		var is_blockaded := current.has(key)
		if is_blockaded and not was_blockaded:
			events.blockade_started.emit(province_id)
		elif was_blockaded and not is_blockaded:
			events.blockade_ended.emit(province_id)
		if naval_definitions.is_port(province_id):
			var was_full := int(previous.get(key, 0)) >= BASIS_POINTS
			var is_full := int(current.get(key, 0)) >= BASIS_POINTS
			if is_full and not was_full:
				events.port_fully_blockaded.emit(province_id)
			elif was_full and not is_full:
				events.port_unblocked.emit(province_id)
		var previous_tier := blockade_tier(int(previous.get(key, 0)))
		var current_tier := blockade_tier(int(current.get(key, 0)))
		if current_tier != previous_tier:
			events.blockade_level_changed.emit(province_id, current_tier)
	world.blockaded_provinces = current
