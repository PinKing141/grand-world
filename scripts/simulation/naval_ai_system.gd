class_name NavalAISystem
extends RefCounted

## N6A: the first naval-AI planning layer (docs/roadmap/naval/
## 06_N6_AI_AND_UX.md "AI Planning Layers"), built to StrategicAISystem's own
## established shape exactly - deterministic utility scoring, staggered
## per-country schedules keyed off the same AIDefinitions "slot" land AI
## already uses, persistent decision state in country runtime, and bounded
## explainable-decision history. It observes authoritative WorldState and
## submits the same commands a player would (ConstructShipCommand,
## AssignAdmiralCommand, SetFleetMissionCommand, RequestFleetRetreatCommand);
## it never mutates naval state directly.
##
## Scope is deliberately narrower than 06_N6's full "AI Planning Layers"
## section and FL3's own g1_finish_line exit gate - see
## docs/roadmap/naval/g1_finish_line/evidence/FL3_CLOSURE_AUDIT.md for the
## full per-bullet accounting, and each _plan_*() function's own doc comment
## for exactly what it does and does not attempt. FL3.1's cached, multi-
## input threat/opportunity query (naval_threat_map.gd) backs proactive
## evasion and blockade-duty assignment via _zone_threat()/
## _zone_has_blockade_target(), both now thin adapters over it.
## _plan_transport() reads land AI's own existing war objective and ferries
## an army to it when a ship, not a march order, is what's actually needed -
## the reachable slice of atomic transport-objective planning and land-AI
## handoff; _plan_organisation() also consolidates separate idle fleets
## sharing a port into one task fleet. Splitting a fleet for a smaller
## mission remains explicit follow-on work, not attempted here.

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const NavalDefinitionsScript = preload("res://scripts/simulation/naval_definitions.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const ConstructShipCommandScript = preload("res://scripts/simulation/commands/construct_ship_command.gd")
const AssignAdmiralCommandScript = preload("res://scripts/simulation/commands/assign_admiral_command.gd")
const SetNavyMaintenanceCommandScript = preload("res://scripts/simulation/commands/set_navy_maintenance_command.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")
const MergeFleetsCommandScript = preload("res://scripts/simulation/commands/merge_fleets_command.gd")
const SplitFleetCommandScript = preload("res://scripts/simulation/commands/split_fleet_command.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const SetFleetMissionCommandScript = preload("res://scripts/simulation/commands/set_fleet_mission_command.gd")
const RequestFleetRetreatCommandScript = preload("res://scripts/simulation/commands/request_fleet_retreat_command.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const ProvincePathfinderScript = preload("res://scripts/simulation/province_pathfinder.gd")
const NavalThreatMapScript = preload("res://scripts/simulation/naval_threat_map.gd")
const SetFleetHomePortCommandScript = preload("res://scripts/simulation/commands/set_fleet_home_port_command.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")

const POSTURE_INTERVAL := 60
const CONSTRUCTION_INTERVAL := 20
const ORGANISATION_INTERVAL := 15
const TACTICAL_INTERVAL := 5
const TRANSPORT_INTERVAL := 10
const MAX_DECISION_HISTORY := 16

# Placeholder first-slice thresholds, not approved N0/N6 budgets - the same
# "simplest rule that is genuinely explicit" precedent every earlier
# placeholder in this pillar (TransportSystem.DAMAGED_CAPACITY_THRESHOLD_BP,
# BlockadeSystem.DAMAGED_EFFECTIVENESS_THRESHOLD_BP, ...) already used.
const DAMAGED_HULL_THRESHOLD_BP := 8000
const RETREAT_POWER_RATIO_BP := 5000
const EVADE_POWER_RATIO_BP := 8000
const MINIMUM_SHIPS_FOR_ADMIRAL := 2
const RESERVE_MONTHS := 3
const BASIS_POINTS := 10000
# FL3.2 placeholder thresholds, not approved N0/N6 budgets - same
# "simplest rule that is genuinely explicit" precedent as DAMAGED_HULL_
# THRESHOLD_BP above. A worst-zone threat_score above this (roughly one to
# two enemy ships' worth of power near an owned port) is "worth building up
# for" even without an active war. A treasury at or above twice the
# construction reserve is "comfortably funded enough to expand."
const THREATENED_ZONE_THREAT_THRESHOLD := 50
const EXPANSION_TREASURY_RESERVE_MULTIPLIER := 2
# FL3.3/FL3.5 placeholder thresholds, same "simplest rule that is genuinely
# explicit" precedent as above. A fleet more than this many days from an
# active battle is reinforcing a war, not a battle - not worth committing a
# fleet's whole position for. A route through a zone this threatening is
# "too dangerous" for an unescorted transport to sail through unwarned.
const REINFORCEMENT_MAX_ARRIVAL_DAYS := 10
# FL3.5: an escort more than this many days from its escorted transport's
# current position is not worth ordering to catch up - the same
# "reinforcing a war, not a battle" reasoning REINFORCEMENT_MAX_ARRIVAL_DAYS
# already applies, reused rather than a second arbitrary bound.
const ESCORT_FOLLOW_MAX_ARRIVAL_DAYS := 10

var scheduler: SimulationScheduler
var events: SimulationEventBus
var definitions: AIDefinitions
var graph: MaritimeGraph
var country_tags: Array[String] = []
var profiles: Dictionary = {}
var threat_map: NavalThreatMap

# FL3.4: "avoid daily full replanning; use staggered schedules and
# event-triggered invalidation." Staggered schedules were already real
# (_due()); this is the other half. naval_battle_started and fleet_moved
# both queue the zone they concern rather than resolving "which country is
# affected" inside the signal handler itself - resolving that needs live
# world state (fleet ownership/location), which the handler does not
# receive, only process_day() does. A Dictionary-as-set, not an Array:
# a busy day can report the same zone from several fleet_moved signals
# (or a battle start plus an arrival in the same zone), and only the
# distinct zone set matters for which countries get reconsidered.
var _pending_replan_zones: Dictionary = {}


func _init(p_scheduler: SimulationScheduler, p_events: SimulationEventBus, p_definitions: AIDefinitions) -> void:
	scheduler = p_scheduler
	events = p_events
	definitions = p_definitions
	graph = MaritimeGraphScript.load_default()
	country_tags = definitions.country_tags()
	for tag in country_tags:
		profiles[tag] = definitions.profile(tag)
	threat_map = NavalThreatMapScript.new()
	events.naval_battle_started.connect(_on_naval_battle_started)
	events.fleet_moved.connect(_on_fleet_moved)


## A fresh battle demands the same immediate tactical reconsideration a
## fleet arriving there does - both are "this zone just became urgent,"
## the same underlying trigger the roadmap names both examples of.
func _on_naval_battle_started(_war_id: String, _battle_id: String, zone_id: int) -> void:
	_pending_replan_zones[zone_id] = true


## Every fleet_moved is queued, friendly or hostile - the real "is this
## actually a hostile arrival next to one of my own fleets" filter can only
## be answered with live world state, which happens in process_day(),
## not here.
func _on_fleet_moved(_fleet_id: String, _from_id: int, to_id: int) -> void:
	_pending_replan_zones[to_id] = true


## True if any of this country's own fleets currently sits in a zone this
## tick's pending-replan set names - the live-state half of event-triggered
## invalidation, resolved once per country per day rather than per event.
func _country_touched_by_replan_trigger(world: CampaignWorldState, tag: String, zones: Dictionary) -> bool:
	if zones.is_empty():
		return false
	for fleet_id in world.country_fleets(tag):
		if zones.has(int(world.get_fleet(fleet_id).get("location_id", -1))):
			return true
	return false


func process_day(world: CampaignWorldState) -> void:
	if not bool(world.global_flags.get("ai_enabled", true)):
		return
	if String(world.global_flags.get("campaign_status", "running")) != "running":
		return
	# Snapshot and clear immediately - a command this same tick (e.g. an
	# earlier country's own tactical order starting a new battle) must not
	# retroactively re-trigger countries already checked this call, and
	# must not leak into tomorrow's otherwise-unrelated triggers either.
	var replan_zones := _pending_replan_zones
	_pending_replan_zones = {}
	for tag in country_tags:
		if not world.has_country(tag) or tag == world.player_country or world.get_country_provinces(tag).is_empty():
			continue
		if not _is_maritime_capable(world, tag):
			continue
		var profile: Dictionary = profiles[tag]
		var slot := int(profile.get("slot", 0))
		var posture_due := _due(world.current_day, POSTURE_INTERVAL, slot)
		var construction_due := _due(world.current_day, CONSTRUCTION_INTERVAL, slot)
		var organisation_due := _due(world.current_day, ORGANISATION_INTERVAL, slot)
		var tactical_due := _due(world.current_day, TACTICAL_INTERVAL, slot)
		var transport_due := _due(world.current_day, TRANSPORT_INTERVAL, slot)
		if not tactical_due and _country_touched_by_replan_trigger(world, tag, replan_zones):
			tactical_due = true
			world.global_counters["naval_ai_event_replans"] = int(world.global_counters.get("naval_ai_event_replans", 0)) + 1
		if not posture_due and not construction_due and not organisation_due and not tactical_due and not transport_due:
			continue
		# FL3.6: "countries planned" - a deterministic per-tick tally,
		# distinct from decisions/commands, of how many maritime countries
		# were actually visited today (past the maritime-capable and
		# nothing-due skips) versus the full country_tags roster.
		world.global_counters["naval_ai_countries_planned"] = int(world.global_counters.get("naval_ai_countries_planned", 0)) + 1
		if posture_due:
			_review_posture(world, tag, profile)
		if construction_due:
			_plan_construction(world, tag, profile)
		if organisation_due:
			_plan_organisation(world, tag)
		if tactical_due:
			_plan_tactical(world, tag)
		if transport_due:
			_plan_transport(world, tag)


func debug_snapshot(world: CampaignWorldState, country_tag: String) -> Dictionary:
	if not world.has_country(country_tag):
		return {}
	var state := _ai_state(world, country_tag)
	return {
		"country_tag": country_tag,
		"maritime_capable": _is_maritime_capable(world, country_tag),
		"posture": String(state.get("posture", "")),
		"plan": String(state.get("plan", "")),
		"desired_ship_count": int(state.get("desired_ship_count", 0)),
		"current_ship_count": world.country_ships(country_tag).size(),
		"last_decision": (state.get("last_decision", {}) as Dictionary).duplicate(true),
		"decision_history": (state.get("decision_history", []) as Array).duplicate(true),
		"decision_counts": (state.get("decision_counts", {}) as Dictionary).duplicate(true),
		"rejected_candidates": (state.get("rejected_candidates", []) as Array).duplicate(true),
		"next_posture_day": _next_due_day(world.current_day, POSTURE_INTERVAL, int(profiles.get(country_tag, {}).get("slot", 0))),
		"next_construction_day": _next_due_day(world.current_day, CONSTRUCTION_INTERVAL, int(profiles.get(country_tag, {}).get("slot", 0))),
		"next_tactical_day": _next_due_day(world.current_day, TACTICAL_INTERVAL, int(profiles.get(country_tag, {}).get("slot", 0))),
		"next_transport_day": _next_due_day(world.current_day, TRANSPORT_INTERVAL, int(profiles.get(country_tag, {}).get("slot", 0))),
	}


func _new_ai_state() -> Dictionary:
	return {
		"posture": "peace",
		"plan": "Observe maritime approaches.",
		"desired_ship_count": 0,
		"last_decision": {},
		"decision_history": [],
		"decision_counts": {},
		"rejected_candidates": [],
	}


## Owned, land-owned-province-registered ports - the same "port" concept
## NavalDefinitions/MaritimeGraph already authority over, just filtered to
## this country's own ownership. Not cached: a country's port set changes
## rarely enough (conquest/loss) that a fresh scan each call is simpler and
## cheaper than an invalidation-tracked cache would be at this AI's own
## staggered call frequency.
static func _country_ports(world: CampaignWorldState, tag: String) -> Array[int]:
	var found: Array[int] = []
	var graph_instance := MaritimeGraphScript.load_default()
	for raw_id in world.get_country_provinces(tag):
		var province_id := int(raw_id)
		if graph_instance.is_port_province(province_id) and graph_instance.is_port_enabled(province_id):
			found.append(province_id)
	found.sort()
	return found


func _is_maritime_capable(world: CampaignWorldState, tag: String) -> bool:
	return not _country_ports(world, tag).is_empty()


## FL3.2: the full six-posture spectrum (06_N6 "Strategic naval posture"),
## mirroring StrategicAISystem._review_strategy()'s own precedence-chain
## shape (war beats debt beats threat beats default) rather than copying its
## exact four category names, since land AI's own peaceful/defensive/
## offensive/recovering set doesn't map one-to-one onto the roadmap's naval-
## specific six. Precedence, most urgent first: an active overseas transport
## objective while at war is "invasion" (the navy's job has shifted to
## enabling it) ahead of generic "wartime"; debt/negative balance is
## "recovery" regardless of war, matching land AI's own "debt overrides
## ambition" rule; a rival power's fleet staged near an owned port (pre-war
## tension, not NavalThreatMap's own war-gated hostile_power - see
## _country_rival_power()'s own doc comment) is "threatened" even at peace;
## a treasury comfortably above reserve
## with no war or debt is "expansion"; otherwise "peace." desired_ship_count
## still scales with port count, now also with posture (frozen at the
## peacetime multiplier during recovery, doubled everywhere ambitious).
func _review_posture(world: CampaignWorldState, tag: String, profile: Dictionary) -> void:
	var state := _ai_state(world, tag)
	var ports := _country_ports(world, tag)
	var at_war := not DiplomacySystemScript.country_wars(world, tag).is_empty()
	var runtime := world.country_runtime(tag)
	var ledger: Dictionary = runtime.get("ledger", {})
	var in_debt := int(runtime.get("debt", 0)) > 0 or int(ledger.get("balance", 0)) < 0
	var reserve := _construction_reserve(profile, ledger)
	var posture: String
	var multiplier: int
	if at_war and _overseas_objective_landing(world, tag) >= 0:
		posture = "invasion"
		multiplier = 2
	elif at_war:
		posture = "wartime"
		multiplier = 2
	elif in_debt:
		posture = "recovery"
		multiplier = 1
	elif _country_rival_power(world, tag, ports) > THREATENED_ZONE_THREAT_THRESHOLD:
		posture = "threatened"
		multiplier = 2
	elif int(runtime.get("treasury", 0)) >= reserve * EXPANSION_TREASURY_RESERVE_MULTIPLIER:
		posture = "expansion"
		multiplier = 2
	else:
		posture = "peace"
		multiplier = 1
	var desired := ports.size() * multiplier
	state["posture"] = posture
	state["desired_ship_count"] = desired
	state["plan"] = "Maintain a %d-ship navy across %d port(s) - posture %s." % [desired, ports.size(), posture]
	_set_ai_state(world, tag, state)
	# Maintenance is adjusted before the posture review's own decision is
	# recorded (not after) specifically so debug_snapshot()'s last_decision
	# always reflects the posture review itself - the country's own primary,
	# always-present summary for this tick - rather than being silently
	# overwritten by a conditional secondary action. The maintenance change
	# still applies via _submit() and still appears in decision_history
	# either way; only which one debug_snapshot() surfaces as "last" differs.
	_consider_navy_maintenance(world, tag, profile, runtime, at_war)
	_record_decision(world, tag, "posture", "review_posture", 100, String(state["plan"]), [], [], {"treasury": int(runtime.get("treasury", 0)), "reserve": reserve, "at_war": at_war, "in_debt": in_debt})


## FL3.2 closure: "respect... maintenance..." - the one FL3.2 bullet the
## closure audit found genuinely unaddressed, and deeper than a missing
## command turned out to be: country_runtime's own "navy_maintenance_bp"
## field was already fully wired into EconomySystem's navy_maintenance
## ledger line (economy_system.gd) - the economic connection was never
## missing, only a command to actually change it, and naval AI logic to
## use it. Mirrors StrategicAISystem._plan_economy()'s own army-maintenance
## adjustment exactly, down to reusing the identical shared AIDefinitions
## profile field ("peace_maintenance_bp") rather than a second, naval-only
## one: full maintenance during any war, a reduced peacetime rate
## otherwise, submitted only when it would actually change the current
## value - not resubmitted every posture tick once already correct. A
## separate, per-fleet "maintenance_posture_bp" combat-readiness field
## also exists (naval_combat_system.gd) but has no economic connection at
## all and is not what this bullet's "respect... maintenance..." refers
## to - confirmed by checking how land's own army_maintenance_bp works
## (a pure economic lever, never read by combat), not assumed; left open
## as its own, separate, deliberately out-of-scope item.
func _consider_navy_maintenance(world: CampaignWorldState, tag: String, profile: Dictionary, runtime: Dictionary, at_war: bool) -> void:
	var desired_maintenance := 10000 if at_war else int(profile.get("peace_maintenance_bp", 5000))
	if int(runtime.get("navy_maintenance_bp", 10000)) == desired_maintenance:
		return
	var command := SetNavyMaintenanceCommandScript.new(tag, desired_maintenance)
	_submit(world, tag, "posture", command, 75, "Adjust navy maintenance for the current war posture.", [], [], {"desired_maintenance_bp": desired_maintenance})


static func _construction_reserve(profile: Dictionary, ledger: Dictionary) -> int:
	return maxi(int(profile.get("minimum_reserve", 50000)) / 2, int(ledger.get("total_expenses", 0)) * RESERVE_MONTHS)


## True if this country's own land AI currently has a live war objective
## that needs sea transport to reach, factored out of _plan_transport()'s
## own identical opening check so _review_posture()'s "invasion" detection
## and the real transport planner never disagree about what counts as an
## active overseas objective.
func _overseas_objective_landing(world: CampaignWorldState, tag: String) -> int:
	var land_state: Dictionary = world.country_runtime(tag).get("ai", {})
	var target := int(land_state.get("target_province_id", -1))
	if target < 0 or not world.has_province(target) or world.get_province_controller(target) == tag:
		return -1
	return _find_legal_landing(world, tag, target, ProvinceGraph.load_default())


## "Threatened" needs a pre-war warning signal, but NavalThreatMap's own
## hostile_power is deliberately gated on an *active war* (correct for the
## tactical evade/retreat decisions it backs - you cannot be attacked by a
## fleet you are not at war with, so counting it as tactical danger would be
## wrong). Discovered while building this posture branch, not assumed: this
## means hostile_power can never itself trigger "threatened," since any
## country with nonzero hostile_power is, by definition, already at war,
## and the wartime/invasion branches above already claim that case first.
## Rivalry (DiplomacySystemScript's own existing relation field, no war
## required) is the real pre-war tension signal instead - a rival power's
## fleet staged near an owned port, without either side having declared
## anything yet.
func _country_rival_power(world: CampaignWorldState, tag: String, ports: Array[int]) -> int:
	var zone_ids := {}
	for port_id in ports:
		for raw_zone_id in graph.port_exits(port_id):
			zone_ids[int(raw_zone_id)] = true
	var worst := 0
	for raw_fleet_id in world.fleet_registry:
		var fleet: Dictionary = world.fleet_registry[raw_fleet_id]
		var owner := String(fleet.get("owner_country_id", ""))
		if owner == tag or not zone_ids.has(int(fleet.get("location_id", -1))):
			continue
		if not bool(DiplomacySystemScript.relation(world, tag, owner).get("rivalry", false)):
			continue
		worst = maxi(worst, int((fleet.get("aggregate", {}) as Dictionary).get("total_attack", 0)))
	return worst


## FL3.2: a real heavy/light/galley/transport mix, keyed by posture - a
## first-slice combination, not an approved N0/N6 budget, same caveat every
## other placeholder table in this pillar carries. "invasion" leans hard
## into transport (the whole point of that posture); "threatened"/"wartime"
## lean into heavy combat power; "peace"/"recovery" stay galley-heavy (the
## cheapest capable all-rounder); "expansion" invests a bit further into
## heavy ships while still favouring the affordable baseline. Every row
## sums to BASIS_POINTS.
const POSTURE_SHIP_MIX_BP := {
	"peace": {"heavy": 1000, "light": 2000, "galley": 6000, "transport": 1000},
	"expansion": {"heavy": 1500, "light": 2000, "galley": 5500, "transport": 1000},
	"threatened": {"heavy": 3500, "light": 1500, "galley": 4000, "transport": 1000},
	"wartime": {"heavy": 4500, "light": 1500, "galley": 3000, "transport": 1000},
	"invasion": {"heavy": 3500, "light": 1000, "galley": 2000, "transport": 3500},
	"recovery": {"heavy": 1000, "light": 1000, "galley": 6000, "transport": 2000},
}


## "Compare existing/queued ships with desired composition... respect
## treasury reserve, sailors... avoid queue spam through cooldowns and
## stable construction slots" (06_N6 "Force construction"). Reserve/budget
## logic mirrors StrategicAISystem._plan_economy()'s own shape. Builds
## toward POSTURE_SHIP_MIX_BP's target family counts (largest current
## deficit wins, tie-broken by ShipDefinitions.ship_families()'s own fixed
## order for determinism), picking the cheapest eligible ship in that
## family - the AI prefers affordability within a family over "the best
## ship," matching its own conservative treasury-reserve philosophy
## elsewhere. Sailor sufficiency is now checked proactively here, not just
## inherited from ConstructShipCommand.validate() rejecting silently. One
## ship, one eligible port, per call - "stable construction slots" without
## inventing a cooldown field, since CONSTRUCTION_INTERVAL already spaces
## calls out; unchanged from before this packet.
##
## "Port capacity" is already respected (desired_ship_count scales with
## _country_ports().size(), and one eligible free port is required per
## construction). "Land-war needs" are respected by sharing the exact same
## ledger-based reserve formula land AI's own _plan_economy() uses, so
## naval construction never competes past what land AI would also consider
## affordable - not a new cross-system arbitration mechanism, just the same
## number. "Technology" gating is now respected: ConstructShipCommand.
## validate() gained the same country_depth_enabled/required_technology
## check RecruitUnitCommand already had (see that command's own doc
## comment), closing the correctness gap FL3_2_STRATEGIC_POSTURE.md
## recorded but did not fix. _cheapest_eligible_ship_in_family() mirrors
## that exact check so the AI treats a technology-locked design as not
## existing yet, the same way an unreleased (future unlock_date) ship
## already does, rather than repeatedly proposing a candidate the command
## would reject every single tick. Families are now tried in ranked
## deficit order (ties broken by ShipDefinitions.ship_families()'s own
## fixed order, same as before) until one has an eligible design, instead
## of giving up the moment the single largest-deficit family's cheapest
## ship happens to be locked.
func _plan_construction(world: CampaignWorldState, tag: String, profile: Dictionary) -> void:
	var state := _ai_state(world, tag)
	var desired := int(state.get("desired_ship_count", 0))
	if desired <= 0:
		return
	var posture := String(state.get("posture", "peace"))
	var runtime := world.country_runtime(tag)
	var ledger: Dictionary = runtime.get("ledger", {})
	var reserve := _construction_reserve(profile, ledger)
	var current_by_family := FleetSystemScript.class_counts_for_ships(world, world.country_ships(tag))
	var ship_definitions := ShipDefinitionsScript.load_default()
	var pending_by_family := {}
	for family in ship_definitions.ship_families():
		pending_by_family[String(family)] = 0
	var pending := 0
	for raw_id in world.naval_construction_registry:
		var record: Dictionary = world.naval_construction_registry[raw_id]
		if String(record.get("country_tag", "")) != tag:
			continue
		pending += 1
		var family := String(ship_definitions.ship(String(record.get("definition_id", ""))).get("family", ""))
		if pending_by_family.has(family):
			pending_by_family[family] = int(pending_by_family[family]) + 1
	var current := world.country_ships(tag).size()
	if current + pending >= desired:
		_record_decision(world, tag, "construction", "fleet_sufficient", 50, "Current and queued ships already meet the desired count.", [], [], {"current": current, "pending": pending, "desired": desired})
		return
	var mix: Dictionary = POSTURE_SHIP_MIX_BP.get(posture, POSTURE_SHIP_MIX_BP["peace"])
	var families := ship_definitions.ship_families()
	var ranked: Array = []
	for index in families.size():
		var family_name := String(families[index])
		var target_count := int(mix.get(family_name, 0)) * desired / BASIS_POINTS
		var owned := int(current_by_family.get(family_name, 0)) + int(pending_by_family.get(family_name, 0))
		ranked.append({"family": family_name, "deficit": target_count - owned, "order": index})
	ranked.sort_custom(func(a, b) -> bool:
		if int(a["deficit"]) != int(b["deficit"]):
			return int(a["deficit"]) > int(b["deficit"])
		return int(a["order"]) < int(b["order"]))
	# No family shows a genuine positive deficit under the posture mix (a
	# rounding edge case where every family's own target_count already
	# rounds down to at-or-below what is owned, even though the total count
	# is short) - fall back to trying "galley" first, the same default this
	# function has always used before considering any other family, since
	# it is the cheapest capable all-rounder every POSTURE_SHIP_MIX_BP row
	# still weights heavily.
	if int(ranked[0]["deficit"]) <= 0:
		ranked.sort_custom(func(a, b) -> bool:
			var a_is_galley := String(a["family"]) == "galley"
			var b_is_galley := String(b["family"]) == "galley"
			if a_is_galley != b_is_galley:
				return a_is_galley
			return int(a["order"]) < int(b["order"]))
	var target_family := ""
	var target_deficit := 0
	var definition_id := ""
	for entry in ranked:
		var candidate_family := String(entry["family"])
		var candidate_definition_id := _cheapest_eligible_ship_in_family(world, tag, ship_definitions, candidate_family, world.current_day)
		if not candidate_definition_id.is_empty():
			target_family = candidate_family
			target_deficit = int(entry["deficit"])
			definition_id = candidate_definition_id
			break
	if definition_id.is_empty():
		_record_rejected_candidate(world, tag, "construct_ship", "No unlocked, technology-eligible ship exists in any target family.", [])
		return
	var port_id := _best_construction_port(world, tag)
	if port_id < 0:
		_record_rejected_candidate(world, tag, "construct_ship", "No eligible port is free of an existing construction order.", [])
		return
	var definition := ship_definitions.ship(definition_id)
	if int(runtime.get("sailors", 0)) < int(definition.get("sailor_cost", 0)):
		_record_decision(world, tag, "construction", "insufficient_sailors", 45, "Construction would need more sailors than are currently available.", [], [port_id], {"sailor_cost": int(definition.get("sailor_cost", 0)), "available_sailors": int(runtime.get("sailors", 0))})
		return
	if int(runtime.get("treasury", 0)) - int(definition.get("cost", 0)) < reserve:
		_record_decision(world, tag, "construction", "preserve_reserve", 45, "Construction would drop the treasury below its reserve.", [], [port_id], {"cost": int(definition.get("cost", 0)), "treasury": int(runtime.get("treasury", 0)), "reserve": reserve})
		return
	var command := ConstructShipCommandScript.new(tag, port_id, definition_id)
	_submit(world, tag, "construction", command, 80, "Build a %s toward the desired %d-ship, %s-posture navy." % [target_family, desired, posture], [], [port_id], {"target_family": target_family, "desired": desired, "deficit": target_deficit})


## Cheapest unlocked, technology-eligible ship in the given family - the AI
## prefers affordability within a family over capability, matching its own
## conservative reserve philosophy. Technology gating mirrors
## ConstructShipCommand.validate()'s own check exactly (same
## country_depth_enabled guard, same country_runtime "technology" dict), so
## the AI treats a locked design as not existing yet, the same way an
## unreleased (future unlock_date) ship already does, rather than
## repeatedly proposing a candidate the command would reject every tick.
## Ties broken by ship_id, for determinism.
static func _cheapest_eligible_ship_in_family(world: CampaignWorldState, tag: String, ship_definitions: ShipDefinitions, family: String, current_day: int) -> String:
	var current_date := SimulationDateScript.day_to_date(current_day)
	var unlocked := ship_definitions.unlocked_ship_ids(current_date)
	var country_depth_enabled := bool(world.global_flags.get("country_depth_enabled", false))
	var technology: Dictionary = world.country_runtime(tag).get("technology", {})
	var best := ""
	var best_cost := -1
	for ship_id in unlocked:
		var definition := ship_definitions.ship(ship_id)
		if String(definition.get("family", "")) != family:
			continue
		if country_depth_enabled:
			var requirement: Dictionary = definition.get("required_technology", {})
			if int(technology.get(String(requirement.get("track", "military")), 0)) < int(requirement.get("level", 0)):
				continue
		var cost := int(definition.get("cost", 0))
		if best.is_empty() or cost < best_cost:
			best = ship_id
			best_cost = cost
	return best


## Highest-harbour-level owned port with no naval construction already
## queued there - mirrors StrategicAISystem._best_recruitment_province()'s
## own "best development, break ties by lowest ID" shape for determinism.
func _best_construction_port(world: CampaignWorldState, tag: String) -> int:
	var busy_ports := {}
	for raw_id in world.naval_construction_registry:
		var record: Dictionary = world.naval_construction_registry[raw_id]
		if String(record.get("country_tag", "")) == tag:
			busy_ports[int(record.get("port_id", -1))] = true
	var naval_definitions := NavalDefinitionsScript.load_default()
	var best := -1
	var best_level := -1
	for port_id in _country_ports(world, tag):
		if busy_ports.has(port_id):
			continue
		var level := int(naval_definitions.port(port_id).get("harbour_level", 0))
		if level > best_level:
			best = port_id
			best_level = level
	return best


## "Assign missions based on ports, war goals, blockades, transport
## operations, and threat. Maintain escorts and repair reserves" (06_N6
## "Operational allocation"). Mission assignment by port/war-goal proximity
## and escort assignment now happen in _plan_tactical() instead (FL3.4); this
## function covers admiral assignment, fleet consolidation, fleet splitting
## to prepare a pending transport run, and (FL3.3) home port reassignment
## when the current one has lost basing rights outright.
func _plan_organisation(world: CampaignWorldState, tag: String) -> void:
	var fleet_ids := world.country_fleets(tag)
	fleet_ids.sort()
	for fleet_id in fleet_ids:
		var fleet := world.get_fleet(fleet_id)
		if not String(fleet.get("admiral_id", "")).is_empty():
			continue
		if (fleet.get("ship_ids", []) as Array).size() < MINIMUM_SHIPS_FOR_ADMIRAL:
			continue
		var admiral_id := _best_available_admiral(world, tag)
		if admiral_id.is_empty():
			continue
		var command := AssignAdmiralCommandScript.new(tag, fleet_id, admiral_id)
		if _submit(world, tag, "organisation", command, 70, "Assign a free admiral to an unled multi-ship fleet.", [], [fleet_id, admiral_id]):
			return
	if _consider_fleet_merge(world, tag, fleet_ids):
		return
	if _consider_transport_ship_separation(world, tag, fleet_ids):
		return
	for fleet_id in fleet_ids:
		if _consider_home_port(world, tag, fleet_id):
			return
	_record_decision(world, tag, "organisation", "no_organisation_action", 40, "No unled fleet has a free admiral available, no port has separate fleets worth consolidating, no fleet needs splitting for a pending transport run, and no home port needs reassignment.", [])


## FL3.3: "choose and change home ports based on access, repair, supply,
## threat and objective distance" - narrowed to the one case with a clear,
## unambiguous trigger. Discovered while scoping this bullet, not assumed:
## home_port_id has no downstream mechanical effect anywhere in the
## simulation today - repair/supply eligibility already key off a fleet's
## *current* location via NavalAccessPolicy.can_base(), not its declared
## home port (confirmed by grep: no repair/supply/morale system reads
## home_port_id at all). Building the richer repair/supply/threat/
## objective-distance selection model the roadmap describes would be tuning
## a field nothing downstream actually reads yet. What is real: a fleet's
## home port record can go stale (captured, access revoked) and then stay
## silently wrong forever, since nothing previously reassigned it. This
## keeps the record honest - a fleet's own home port must remain a real,
## currently legal base - the concrete, real-value slice of this bullet.
func _consider_home_port(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	var home_port_id := int(fleet.get("home_port_id", -1))
	if NavalAccessPolicyScript.can_base(graph, world, tag, home_port_id):
		return false
	var ports := _country_ports(world, tag)
	if ports.is_empty():
		_record_rejected_candidate(world, tag, "set_fleet_home_port", "No owned port remains to reassign a lost home port to.", [fleet_id])
		return false
	var command := SetFleetHomePortCommandScript.new(tag, fleet_id, ports[0])
	return _submit(world, tag, "organisation", command, 55, "Reassign home port after losing basing rights at the previous one.", [], [fleet_id, ports[0]], {"previous_home_port": home_port_id})


## "Group compatible ships into task fleets" (06_N6 "Operational
## allocation"). The first port (lowest ID, for determinism - not
## necessarily the most valuable one) with two or more of this country's own
## docked, organisable fleets that are not carrying a transport operation
## merges into one - the same FleetSystem.is_docked_and_organisable() gate
## MergeFleetsCommand.validate() itself already enforces, plus a transport
## exclusion of this function's own choosing: MergeFleetsCommand.apply()
## only moves ships between fleet_registry entries, it does not carry a
## source fleet's transport_operation_ids along, so merging a fleet mid-
## transport would strand that operation's own fleet reference - avoided
## here rather than fixing the command for a case naval AI itself need never
## trigger. Splitting a fleet for a smaller *mission* is not attempted;
## splitting to separate a mixed fleet's transport-family ships ahead of a
## pending transport run is - see _consider_transport_ship_separation()
## below, the other direction of "group ships into task fleets."
func _consider_fleet_merge(world: CampaignWorldState, tag: String, fleet_ids: Array) -> bool:
	var by_port: Dictionary = {}
	for fleet_id in fleet_ids:
		var fleet := world.get_fleet(fleet_id)
		if not FleetSystemScript.is_docked_and_organisable(world, fleet_id, tag):
			continue
		if not (fleet.get("transport_operation_ids", []) as Array).is_empty():
			continue
		var port_id := int(fleet.get("location_id", -1))
		var group: Array = by_port.get(port_id, [])
		group.append(fleet_id)
		by_port[port_id] = group
	var port_ids := by_port.keys()
	port_ids.sort()
	for port_id in port_ids:
		var group: Array = by_port[port_id]
		if group.size() < 2:
			continue
		var command := MergeFleetsCommandScript.new(tag, group)
		return _submit(world, tag, "organisation", command, 65, "Consolidate %d separate fleets sharing a port into one task fleet." % group.size(), [], group, {"port_id": port_id})
	return false


## FL3.3: "group ships into task fleets" also covers preparing a dedicated
## transport fleet before departure, not just consolidating idle combat
## fleets above. A docked fleet mixing "transport"-family ships with any
## other family, while this country has a live overseas objective that
## genuinely needs sea transport (_overseas_objective_landing() - the same
## query _review_posture()'s invasion detection and _plan_transport()
## itself already share, so this never splits speculatively when nothing
## is waiting to sail), has its non-transport ships split off - freeing
## them for combat/blockade/patrol duty instead of sailing along on a
## voyage they contribute nothing to, and leaving a transport-only fleet
## _plan_transport() can then select cleanly. Deliberately multi-tick:
## split lands this tick, _plan_transport() picks the now-pure fleet up on
## its own next due tick - the same "a command takes effect over
## subsequent ticks" pattern construction and movement already use, since
## a same-tick split-then-transport pair would validate the transport half
## against the fleet's pre-split composition.
func _consider_transport_ship_separation(world: CampaignWorldState, tag: String, fleet_ids: Array) -> bool:
	if _overseas_objective_landing(world, tag) < 0:
		return false
	var ship_definitions := ShipDefinitionsScript.load_default()
	for fleet_id in fleet_ids:
		if not FleetSystemScript.is_docked_and_organisable(world, fleet_id, tag):
			continue
		var fleet := world.get_fleet(fleet_id)
		var has_transport := false
		var non_transport_ships: Array = []
		for raw_ship_id in (fleet.get("ship_ids", []) as Array):
			var ship_id := String(raw_ship_id)
			var family := String(ship_definitions.ship(String(world.get_ship(ship_id).get("definition_id", ""))).get("family", ""))
			if family == "transport":
				has_transport = true
			else:
				non_transport_ships.append(ship_id)
		if not has_transport or non_transport_ships.is_empty():
			continue
		var command := SplitFleetCommandScript.new(tag, fleet_id, non_transport_ships)
		return _submit(world, tag, "organisation", command, 60, "Split combat ships out of a mixed fleet ahead of a pending overseas transport run.", [], [fleet_id])
	return false


## Alive, employed by the country, not already commanding an army or fleet -
## mirrors NavalHUD._populate_admiral_options()'s own eligibility filter so
## the AI never proposes an assignment AssignAdmiralCommand.validate() would
## reject. Lowest character ID wins ties, for determinism.
func _best_available_admiral(world: CampaignWorldState, tag: String) -> String:
	var ids := world.character_registry.keys()
	ids.sort()
	for raw_id in ids:
		var character_id := String(raw_id)
		var character: Dictionary = world.character_registry[character_id]
		if not bool(character.get("alive", false)) or String(character.get("employer_country", "")) != tag:
			continue
		if not String(character.get("commander_army_id", "")).is_empty() or not String(character.get("admiral_fleet_id", "")).is_empty():
			continue
		return character_id
	return ""


## "Continue, cancel, reinforce, evade, or retreat... protect carried
## armies... do not recompute full strategy every day" (06_N6 "Tactical
## daily decisions"), now scoring every roadmap-named idle-fleet candidate:
## retreat a fleet that is losing badly, send a damaged or unsupplied idle
## fleet toward repair/home, reinforce an active battle its own side is
## currently losing (_consider_reinforcement() - no explicit "join battle"
## command exists or is needed, since NavalCombatSystem._join_reinforcements()
## already auto-adds any fleet sharing a battle's zone regardless of how it
## got there; this only decides whether to order the fleet there), escort a
## friendly transport sharing this fleet's zone, intercept a reachable
## hostile transport, evade a dangerous zone or take up blockade duty in a
## safe one, defend threatened home coastline, and patrol a safe zone as the
## last resort before genuinely doing nothing - and stands a fleet down to
## idle once whatever justified its escort/intercept/protect_coast/patrol
## mission no longer holds (_consider_mission_completion()), since none of
## those four missions have any completion condition of their own in the
## simulation layer the way blockade/return_to_port/repair do; without this
## they would stay tagged forever. FL3.5: an escort no longer co-located
## with its transport now chases it instead of sitting still or being
## stood down (_consider_escort_follow()), and _plan_transport() itself now
## proactively reserves an idle same-port fleet as escort the moment a
## transport operation is created, not only reactively once both happen to
## already share a zone. Protecting carried armies beyond what
## TransportSystem already does unconditionally is still not attempted.
func _plan_tactical(world: CampaignWorldState, tag: String) -> void:
	var fleet_ids := world.country_fleets(tag)
	fleet_ids.sort()
	for fleet_id in fleet_ids:
		if _consider_retreat(world, tag, fleet_id):
			return
	for fleet_id in fleet_ids:
		if _consider_repair_or_return(world, tag, fleet_id):
			return
	for fleet_id in fleet_ids:
		if _consider_mission_completion(world, tag, fleet_id):
			return
	for fleet_id in fleet_ids:
		if _consider_escort_follow(world, tag, fleet_id):
			return
	for fleet_id in fleet_ids:
		if _consider_reinforcement(world, tag, fleet_id):
			return
	for fleet_id in fleet_ids:
		if _consider_escort(world, tag, fleet_id):
			return
	for fleet_id in fleet_ids:
		if _consider_intercept(world, tag, fleet_id):
			return
	for fleet_id in fleet_ids:
		if _consider_blockade_or_evade(world, tag, fleet_id):
			return
	for fleet_id in fleet_ids:
		if _consider_protect_coast(world, tag, fleet_id):
			return
	for fleet_id in fleet_ids:
		if _consider_patrol(world, tag, fleet_id):
			return
	_record_decision(world, tag, "tactical", "hold_stations", 35, "No fleet currently needs retreat, repair, return to port, reinforcement, escort, intercept, blockade duty, evasion, coastal defence, or patrol.", [])


## "AI must compare conservative effective power, not raw ship count" (06_N6
## "Engagement Safety"), narrowed to each side's summed aggregate attack
## rating - the same field NavalCombatSystem's own damage formula already
## keys off of, not a second parallel power model. A fleet below half the
## opposing side's power, past the command's own minimum-round gate,
## requests retreat; RequestFleetRetreatCommand.validate() remains the
## actual authority - this only decides when it is worth trying.
func _consider_retreat(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	var battle_id := String(fleet.get("battle_id", ""))
	if battle_id.is_empty():
		return false
	var battle := world.get_naval_battle(battle_id)
	if String(battle.get("status", "")) != "active":
		return false
	var is_attacker := (battle.get("attacker_fleets", []) as Array).has(fleet_id)
	var own_side: Array = battle.get("attacker_fleets", []) if is_attacker else battle.get("defender_fleets", [])
	var enemy_side: Array = battle.get("defender_fleets", []) if is_attacker else battle.get("attacker_fleets", [])
	var own_power := _side_power(world, own_side)
	var enemy_power := _side_power(world, enemy_side)
	if enemy_power <= 0 or own_power * 10000 >= enemy_power * RETREAT_POWER_RATIO_BP:
		return false
	var command := RequestFleetRetreatCommandScript.new(tag, fleet_id)
	return _submit(world, tag, "tactical", command, 90, "Withdraw an outmatched fleet before it is destroyed.", [], [fleet_id, battle_id], {"own_power": own_power, "enemy_power": enemy_power, "retreat_ratio_bp": RETREAT_POWER_RATIO_BP})


static func _side_power(world: CampaignWorldState, fleet_ids: Array) -> int:
	var total := 0
	for raw_fleet_id in fleet_ids:
		total += int((world.get_fleet(String(raw_fleet_id)).get("aggregate", {}) as Dictionary).get("total_attack", 0))
	return total


## FL3.3: "compare reinforcement arrival time and value before joining a
## battle" (06_N6). No explicit "join battle" command exists or is needed -
## NavalCombatSystem._join_reinforcements() (naval_combat_system.gd) already
## automatically adds any fleet that shares an active battle's zone to that
## battle's side every day, regardless of whether it arrived by coincidence
## or by order. This function's only job is the order itself: send an idle,
## uncommitted fleet toward an active battle its own country has a side in,
## but only when that side is currently the *weaker* one (the "value" half -
## reinforcing a side already winning comfortably is not worth committing a
## fleet for) and only when the fleet can arrive within
## REINFORCEMENT_MAX_ARRIVAL_DAYS (the "arrival time" half - a fleet weeks
## away is fighting a different war by the time it gets there). A docked
## fleet may reinforce too, not just one already at sea - unlike the
## tactical-positioning missions above, sailing out to help an active battle
## is worth leaving port for.
func _consider_reinforcement(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if String(fleet.get("mission", "idle")) != "idle":
		return false
	if String(fleet.get("location_status", "")) not in [CampaignWorldState.FLEET_LOCATION_DOCKED, CampaignWorldState.FLEET_LOCATION_AT_SEA]:
		return false
	if not (fleet.get("transport_operation_ids", []) as Array).is_empty():
		return false
	var origin := int(fleet.get("location_id", -1))
	var battle_ids := world.naval_battle_registry.keys()
	battle_ids.sort()
	for raw_battle_id in battle_ids:
		var battle_id := String(raw_battle_id)
		var battle: Dictionary = world.naval_battle_registry[battle_id]
		if String(battle.get("status", "")) != "active":
			continue
		var zone_id := int(battle.get("zone_id", -1))
		if zone_id == origin:
			continue
		var war: Dictionary = world.war_registry.get(String(battle.get("war_id", "")), {})
		var side := DiplomacySystemScript.side_in_war(war, tag)
		if side == 0:
			continue
		var own_side_fleets: Array = battle.get("attacker_fleets", []) if side > 0 else battle.get("defender_fleets", [])
		var enemy_side_fleets: Array = battle.get("defender_fleets", []) if side > 0 else battle.get("attacker_fleets", [])
		if _side_power(world, own_side_fleets) >= _side_power(world, enemy_side_fleets):
			continue
		var route := NavalAccessPolicyScript.find_legal_route(graph, world, tag, origin, zone_id)
		if not bool(route.get("exists", false)) or int(route.get("total_days", 999)) > REINFORCEMENT_MAX_ARRIVAL_DAYS:
			continue
		var command := MoveFleetCommandScript.new(fleet_id, zone_id, tag)
		return _submit(world, tag, "tactical", command, 82, "Reinforce an active naval battle %d day(s) away where this side is currently weaker." % int(route["total_days"]), [], [fleet_id, battle_id], {"arrival_days": int(route["total_days"]), "max_arrival_days": REINFORCEMENT_MAX_ARRIVAL_DAYS})
	return false


## Damaged and docked -> repair; damaged or unsupplied and not docked at a
## legal repair port -> return_to_port, letting FleetMissionSystem's own
## state machine drive the actual routing/completion. Only ever touches an
## idle fleet - a fleet already on a mission, in transit, or carrying a
## transport operation is left alone rather than second-guessed daily.
func _consider_repair_or_return(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if String(fleet.get("mission", "idle")) != "idle":
		return false
	if not (fleet.get("transport_operation_ids", []) as Array).is_empty():
		return false
	var aggregate: Dictionary = fleet.get("aggregate", {})
	var max_hull := int(aggregate.get("total_maximum_hull", 0))
	var hull_bp := 10000 if max_hull <= 0 else int(aggregate.get("total_hull", 0)) * 10000 / max_hull
	var damaged := hull_bp < DAMAGED_HULL_THRESHOLD_BP
	var unsupplied := not bool(fleet.get("supplied", true))
	if not damaged and not unsupplied:
		return false
	var location_status := String(fleet.get("location_status", ""))
	var owner := String(fleet.get("owner_country_id", ""))
	var location_id := int(fleet.get("location_id", -1))
	var mission := "repair" if (damaged and location_status == CampaignWorldState.FLEET_LOCATION_DOCKED and NavalAccessPolicyScript.can_base(graph, world, owner, location_id)) else "return_to_port"
	var command := SetFleetMissionCommandScript.new(tag, fleet_id, mission)
	var reason := "Return a damaged fleet to a repair-capable port." if mission == "return_to_port" and damaged else ("Repair a damaged fleet already at a legal port." if mission == "repair" else "Return an unsupplied fleet to port.")
	return _submit(world, tag, "tactical", command, 75, reason, [], [fleet_id], {"hull_bp": hull_bp, "damaged_threshold_bp": DAMAGED_HULL_THRESHOLD_BP, "unsupplied": unsupplied})


## Shared eligibility for every tactical positioning mission below
## (escort/intercept/blockade/evade/protect_coast/patrol) - idle, at sea,
## not mid-transport. A docked fleet is already safe at home and needs none
## of these; _consider_repair_or_return() is the one tactical rule that
## intentionally also considers docked fleets, so it does not use this.
static func _is_idle_at_sea(fleet: Dictionary) -> bool:
	return String(fleet.get("mission", "idle")) == "idle" \
		and String(fleet.get("location_status", "")) == CampaignWorldState.FLEET_LOCATION_AT_SEA \
		and (fleet.get("transport_operation_ids", []) as Array).is_empty()


## Escort/intercept/protect_coast/patrol/blockade have no completion
## condition of their own anywhere in the simulation layer - FleetMissionSystem
## only ever resolves return_to_port/repair (confirmed by the FL2 closure
## audit's own "fully inert" finding for these mission tags; "blockade" is
## deliberately absent from FleetMissionSystem too - see that file's own doc
## comment - "a blockade never finishes, only stops being eligible," which
## BlockadeSystem's own live, always-recomputed queries already handle
## correctly with zero naval-AI involvement). Left alone, a fleet the AI
## assigns one of these five would carry it forever, drifting further from
## whatever actually justified it as the world moves on. This is the other
## half: re-check the specific condition that justified the mission, and
## stand the fleet down to idle the moment it no longer holds, so the fleet
## becomes eligible for fresh reconsideration on its country's next tactical
## tick rather than sitting stuck.
##
## "blockade" was added while verifying FL3's own "AI recovers from... peace"
## claim (FL3_VERIFICATION_2_RECOVERY_MATRIX.md): BlockadeSystem's queries
## already correctly zero out the instant a war ends, but nothing previously
## reset the fleet's own mission tag back to idle - and every other tactical
## consider function requires mission == "idle" to even look at a fleet, so a
## post-peace blockading fleet was invisible to reinforcement/escort/
## intercept/protect_coast/patrol forever, not just ineffective at blockading.
## return_to_port/repair remain untouched - those already have their own real
## completion conditions this function does not need to duplicate.
##
## FL3.5: "protect_transport"'s own justification widened from "co-located
## with a sailing operation right now" to "this country has any sailing
## operation left at all" - the escort-follows-the-voyage fix
## (_consider_escort_follow() below) needs the mission to survive the gap
## between "the transport just left my zone" and "I have caught up with
## it," not be stood down the instant they are no longer co-located. Only
## once every one of this country's transport operations has genuinely
## completed or been cancelled does the escort stand down.
func _consider_mission_completion(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	var mission := String(fleet.get("mission", "idle"))
	if mission not in ["protect_transport", "intercept", "protect_coast", "patrol", "blockade"]:
		return false
	if String(fleet.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_AT_SEA:
		return false
	var zone_id := int(fleet.get("location_id", -1))
	var still_justified := false
	match mission:
		"protect_transport":
			for raw_operation_id in world.transport_operation_registry:
				var operation: Dictionary = world.transport_operation_registry[raw_operation_id]
				if String(operation.get("country_tag", "")) == tag and String(operation.get("state", "")) == CampaignWorldState.TRANSPORT_STATE_SAILING:
					still_justified = true
					break
		"intercept":
			for raw_operation_id in world.transport_operation_registry:
				var operation: Dictionary = world.transport_operation_registry[raw_operation_id]
				var operation_owner := String(operation.get("country_tag", ""))
				if operation_owner != tag and int(operation.get("current_location_id", -1)) == zone_id and not DiplomacySystemScript.active_war_between(world, tag, operation_owner).is_empty():
					still_justified = true
					break
		"protect_coast":
			still_justified = int(threat_map.assess(world, tag, zone_id, graph)["threat_score"]) > 0
		"patrol":
			still_justified = int(threat_map.assess(world, tag, zone_id, graph)["threat_score"]) <= 0
		"blockade":
			still_justified = not DiplomacySystemScript.country_wars(world, tag).is_empty() and _zone_has_blockade_target(world, zone_id, tag)
	if still_justified:
		return false
	var command := SetFleetMissionCommandScript.new(tag, fleet_id, "idle")
	return _submit(world, tag, "tactical", command, 70, "Stand down from %s - the original reason no longer applies." % mission, [], [fleet_id], {"previous_mission": mission})


## FL3.5: "escort does not follow the voyage" - a real, distinct gap from
## proactive reservation, found while scoping this bullet
## (FL3_3_FL3_5_REINFORCEMENT_HOMEPORT_DANGER.md): an escort fleet
## previously had no way to move with the transport it was guarding once
## the transport sailed on to its next leg. _consider_mission_completion()
## no longer stands a protect_transport fleet down the moment they part
## zones (its own FL3.5 note above widened "still justified" to "this
## country has any sailing operation left at all"), but that alone only
## stopped the fleet being *abandoned* - nothing gave it fresh orders
## either, so it would simply sit still, still tagged protect_transport,
## escorting nothing. This closes that gap: a fleet already on
## protect_transport duty, not currently co-located with any of this
## country's sailing transport operations, is ordered to the lowest-
## numbered such operation's current zone (deterministic tie-break; real
## distance-based prioritisation across multiple simultaneous convoys is
## not attempted, matching this pillar's existing "legal and deterministic
## beats optimal" precedent), within the same ESCORT_FOLLOW_MAX_ARRIVAL_DAYS
## bound reinforcement uses for the identical "not worth chasing something
## too far away" reasoning. Docked escorts are included, not just at-sea
## ones - an escort reserved proactively before its convoy has even sailed
## (_consider_proactive_escort_reservation() below) must still be able to
## leave port once the transport gets underway.
func _consider_escort_follow(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if String(fleet.get("mission", "idle")) != "protect_transport":
		return false
	if String(fleet.get("location_status", "")) not in [CampaignWorldState.FLEET_LOCATION_DOCKED, CampaignWorldState.FLEET_LOCATION_AT_SEA]:
		return false
	if not (fleet.get("transport_operation_ids", []) as Array).is_empty():
		return false
	var origin := int(fleet.get("location_id", -1))
	var operation_ids := world.transport_operation_registry.keys()
	operation_ids.sort()
	var sailing_zones := {}
	for raw_operation_id in operation_ids:
		var operation: Dictionary = world.transport_operation_registry[raw_operation_id]
		if String(operation.get("country_tag", "")) == tag and String(operation.get("state", "")) == CampaignWorldState.TRANSPORT_STATE_SAILING:
			sailing_zones[int(operation.get("current_location_id", -1))] = true
	if sailing_zones.is_empty() or sailing_zones.has(origin):
		return false
	for raw_operation_id in operation_ids:
		var operation_id := String(raw_operation_id)
		var operation: Dictionary = world.transport_operation_registry[operation_id]
		if String(operation.get("country_tag", "")) != tag or String(operation.get("state", "")) != CampaignWorldState.TRANSPORT_STATE_SAILING:
			continue
		var target_zone := int(operation.get("current_location_id", -1))
		var route := NavalAccessPolicyScript.find_legal_route(graph, world, tag, origin, target_zone)
		if not bool(route.get("exists", false)) or int(route.get("total_days", 999)) > ESCORT_FOLLOW_MAX_ARRIVAL_DAYS:
			continue
		var command := MoveFleetCommandScript.new(fleet_id, target_zone, tag)
		return _submit(world, tag, "tactical", command, 78, "Follow the escorted transport operation to its current zone.", [], [fleet_id, operation_id, target_zone], {"arrival_days": int(route.get("total_days", -1)), "max_arrival_days": ESCORT_FOLLOW_MAX_ARRIVAL_DAYS})
	return false


## FL3.4: "escort" per the roadmap's own tactical-candidate list, mapped to
## the existing protect_transport mission (SetFleetMissionCommand's own
## name for it - no new mission was invented). An idle warship sharing a
## zone with one of this country's own actively sailing transport
## operations takes up escort duty there - the most valuable use of an idle
## fleet this function considers, checked ahead of intercept/blockade so a
## fleet does not go hunting while its own convoy sails unescorted through
## the same water.
func _consider_escort(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if not _is_idle_at_sea(fleet):
		return false
	var zone_id := int(fleet.get("location_id", -1))
	for raw_operation_id in world.transport_operation_registry:
		var operation: Dictionary = world.transport_operation_registry[raw_operation_id]
		if String(operation.get("country_tag", "")) != tag:
			continue
		if String(operation.get("state", "")) != CampaignWorldState.TRANSPORT_STATE_SAILING:
			continue
		if int(operation.get("current_location_id", -1)) != zone_id:
			continue
		var command := SetFleetMissionCommandScript.new(tag, fleet_id, "protect_transport")
		return _submit(world, tag, "tactical", command, 88, "Escort a friendly transport operation sailing through the same zone.", [], [fleet_id, String(raw_operation_id), zone_id])
	return false


## FL3.4: "interception" per the roadmap's own tactical-candidate list. An
## idle warship shares a zone with an enemy transport operation actually
## sailing through it right now - a real, valuable, reachable target, not a
## speculative hunt. Deliberately does not chase hostile *combat* fleets
## (that is what blockade/evade's own power comparison already governs);
## this is specifically about catching enemy shipping in the act, the
## roadmap's own distinction between "interception" and "blockade."
func _consider_intercept(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if not _is_idle_at_sea(fleet):
		return false
	if DiplomacySystemScript.country_wars(world, tag).is_empty():
		return false
	var zone_id := int(fleet.get("location_id", -1))
	for raw_operation_id in world.transport_operation_registry:
		var operation: Dictionary = world.transport_operation_registry[raw_operation_id]
		var operation_owner := String(operation.get("country_tag", ""))
		if operation_owner == tag or int(operation.get("current_location_id", -1)) != zone_id:
			continue
		if DiplomacySystemScript.active_war_between(world, tag, operation_owner).is_empty():
			continue
		var command := SetFleetMissionCommandScript.new(tag, fleet_id, "intercept")
		return _submit(world, tag, "tactical", command, 80, "Intercept a hostile transport operation sailing through the same zone.", [], [fleet_id, String(raw_operation_id), zone_id])
	return false


## FL3.1: now a thin adapter over NavalThreatMap.assess() - the cached,
## multi-input threat/opportunity query (hostile power, friendly support,
## recent battles, blockade targets, transport stakes, supply distance; see
## naval_threat_map.gd). Kept as a same-signature wrapper rather than
## inlined at every call site so _consider_retreat()/
## _consider_blockade_or_evade() need no changes, and so
## tests/naval_ai_threat_test.gd's existing direct calls keep working
## unchanged.
func _zone_threat(world: CampaignWorldState, tag: String, zone_id: int) -> int:
	return int(threat_map.assess(world, tag, zone_id, graph)["threat_score"])


## FL3.1: thin adapter over NavalThreatMap.assess()'s has_blockade_target
## component - see that function's own doc comment for the underlying
## reciprocal land_neighbors() logic (unchanged, only moved). Parameter
## order (zone_id before tag) is preserved from before this packet for the
## same "no existing caller needs to change" reason _zone_threat() keeps its
## own signature.
func _zone_has_blockade_target(world: CampaignWorldState, zone_id: int, tag: String) -> bool:
	return bool(threat_map.assess(world, tag, zone_id, graph)["has_blockade_target"])


## The other half of "Engagement Safety" (06_N6): deciding not to be
## somewhere, not just how to leave once outnumbered mid-battle. An idle,
## unassigned, at-sea fleet in a zone this country's own summed power
## cannot safely cover evades toward port (return_to_port, reusing
## FleetMissionSystem's own routing rather than a second movement path);
## otherwise, if the zone is safe and has a live war target within reach,
## it takes up blockade duty there. Only ever touches a fleet with no
## mission and no transport burden, the same restraint
## _consider_repair_or_return() already applies.
func _consider_blockade_or_evade(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if String(fleet.get("mission", "idle")) != "idle":
		return false
	if String(fleet.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_AT_SEA:
		return false
	if not (fleet.get("transport_operation_ids", []) as Array).is_empty():
		return false
	var zone_id := int(fleet.get("location_id", -1))
	var threat := _zone_threat(world, tag, zone_id)
	var own_power := int((fleet.get("aggregate", {}) as Dictionary).get("total_attack", 0))
	if threat > 0 and own_power * BASIS_POINTS < threat * EVADE_POWER_RATIO_BP:
		var evade := SetFleetMissionCommandScript.new(tag, fleet_id, "return_to_port")
		return _submit(world, tag, "tactical", evade, 85, "Evade a dangerous sea zone (threat %d vs own power %d)." % [threat, own_power], [], [fleet_id, zone_id], {"threat": threat, "own_power": own_power, "evade_ratio_bp": EVADE_POWER_RATIO_BP})
	if not DiplomacySystemScript.country_wars(world, tag).is_empty() and _zone_has_blockade_target(world, zone_id, tag):
		var blockade := SetFleetMissionCommandScript.new(tag, fleet_id, "blockade")
		return _submit(world, tag, "tactical", blockade, 65, "Assign blockade duty against a reachable war target from a currently safe zone.", [], [fleet_id, zone_id])
	return false


## FL3.4: "coast protection" per the roadmap's own tactical-candidate list.
## Broader than blockade's own port-specific war target: any owned land
## neighbour of this zone counts (not just a hostile-owned one blockade
## would target), so a fleet can be assigned to defend home coastline that
## is under threat even when there is nothing of the enemy's to blockade
## here. Checked after blockade/evade - a fleet capable of striking at the
## enemy directly (blockade) or that must flee outright (evade) has a more
## urgent job than static coastal defence.
func _consider_protect_coast(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if not _is_idle_at_sea(fleet):
		return false
	var zone_id := int(fleet.get("location_id", -1))
	var assessment := threat_map.assess(world, tag, zone_id, graph)
	if int(assessment["threat_score"]) <= 0:
		return false
	var owns_neighbouring_coast := false
	for raw_province_id in ProvinceGraph.load_default().land_neighbors(zone_id):
		if world.get_province_owner(int(raw_province_id)) == tag:
			owns_neighbouring_coast = true
			break
	if not owns_neighbouring_coast:
		return false
	var command := SetFleetMissionCommandScript.new(tag, fleet_id, "protect_coast")
	return _submit(world, tag, "tactical", command, 60, "Defend threatened home coastline that has no reachable blockade target of its own.", [], [fleet_id, zone_id], {"threat_score": int(assessment["threat_score"])})


## FL3.4: "patrol" per the roadmap's own tactical-candidate list - the
## lowest-priority positioning mission, the last real assignment considered
## before a fleet is simply left to hold its station. A fleet with nothing
## more urgent to do keeps some presence in a currently safe zone rather
## than sitting fully idle, matching this pillar's own "an idle fleet
## should still be doing something explicable" philosophy.
func _consider_patrol(world: CampaignWorldState, tag: String, fleet_id: String) -> bool:
	var fleet := world.get_fleet(fleet_id)
	if not _is_idle_at_sea(fleet):
		return false
	var zone_id := int(fleet.get("location_id", -1))
	if int(threat_map.assess(world, tag, zone_id, graph)["threat_score"]) > 0:
		return false
	var command := SetFleetMissionCommandScript.new(tag, fleet_id, "patrol")
	return _submit(world, tag, "tactical", command, 40, "Patrol a currently safe zone with nothing more urgent to do.", [], [fleet_id, zone_id])


## "Atomic transport-objective planning" (06_N6 "Transport Planning"),
## narrowed to the reachable slice of the seven-step chain that doesn't need
## new AI infrastructure: land AI (StrategicAISystem) already picks a
## "target_province_id" for the active war and drives idle armies toward it
## every MILITARY_INTERVAL - it just has no notion that some targets need a
## ship, not a march order. This reads that same target (no new "objective"
## concept invented). "Confirm strategic value" is inherited for free - land
## AI already decided the target is worth pursuing; this does not
## re-evaluate it.
##
## The legal transport destination is *not* always the target itself:
## NavalAccessPolicy.can_dock() deliberately never auto-grants docking
## rights merely from being at war (01_N1's own "sailing into a hostile
## harbour is not the same act as marching an army into hostile territory"),
## so a war target that is itself a hostile-held port is not a legal landing
## site at all yet - discovered by this slice's own test, not assumed.
## _find_legal_landing() picks the target directly when it *is* legally
## dockable (unclaimed, allied, or already the country's own), and otherwise
## the country's own nearest port with a real land route onward to the
## target - a beachhead, landing where ships are actually welcome and
## letting the army march the last leg once ashore. FL3.5: the route is now
## also checked for "acceptable danger" - if any sea zone along it reads
## above THREATENED_ZONE_THREAT_THRESHOLD on NavalThreatMap, the candidate
## is rejected and recorded rather than sailed through blind
## (_route_too_dangerous()). Proactively *reserving* an escort fleet ahead
## of departure is still not attempted - FL3.4's own _consider_escort()
## reactively picks up escort duty for a fleet that happens to already share
## a zone with a sailing transport, but nothing here goes looking for one in
## advance, and an escort assigned this way does not follow the transport's
## route once it moves on (_consider_mission_completion() stands it down
## the moment the transport leaves its zone) - a real, distinct limitation
## from proactive reservation, not the same gap. Monitoring an operation
## once under way (TransportSystem's own N3.3 failure-recovery already
## covers interruption/loss deterministically) is not attempted either.
## "Land-AI handoff" needs no explicit handoff code at all: once
## TransportSystem completes the operation, the army is simply
## ARMY_STATUS_IDLE again at a real province, exactly like any army that
## just finished marching - StrategicAISystem._issue_army_orders() already
## scans every idle army generically and will pick it up, land route and
## all, on its own next tactical tick.
func _plan_transport(world: CampaignWorldState, tag: String) -> void:
	var land_state: Dictionary = world.country_runtime(tag).get("ai", {})
	var target := int(land_state.get("target_province_id", -1))
	if target < 0 or not world.has_province(target) or world.get_province_controller(target) == tag:
		_record_decision(world, tag, "transport", "no_overseas_objective", 30, "No active land objective currently needs sea transport.", [])
		return
	# Shares its actual pathfinding with _overseas_objective_landing(), the
	# same query _review_posture()'s "invasion" detection now also calls -
	# one authoritative "is there a live, reachable overseas objective"
	# answer, not two that could quietly disagree.
	var landing_id := _overseas_objective_landing(world, tag)
	if landing_id < 0:
		_record_decision(world, tag, "transport", "no_legal_landing", 35, "No port this country may legally dock at offers a path to the objective.", [], [target])
		return
	var province_graph := ProvinceGraph.load_default()
	var army_ids := world.country_armies(tag)
	army_ids.sort()
	for army_id in army_ids:
		var army := world.get_army(army_id)
		if String(army.get("status", "")) != CampaignWorldState.ARMY_STATUS_IDLE:
			continue
		var origin := int(army.get("current_province_id", -1))
		if origin == landing_id or world.get_province_owner(origin) != tag or not graph.is_port_province(origin):
			continue
		if bool(ProvincePathfinderScript.find_route(province_graph, world, tag, origin, landing_id).get("exists", false)):
			continue
		var sea_route := NavalAccessPolicyScript.find_legal_route(graph, world, tag, origin, landing_id)
		if not bool(sea_route.get("exists", false)):
			continue
		if _route_too_dangerous(world, tag, sea_route.get("path", [])):
			_record_rejected_candidate(world, tag, "create_transport_operation", "The only legal route to the landing site passes through a zone too dangerous to risk unescorted.", [army_id, origin, landing_id])
			continue
		var required := TransportSystemScript.required_capacity(world, army_id)
		var fleet_ids := world.country_fleets(tag)
		fleet_ids.sort()
		for fleet_id in fleet_ids:
			var fleet := world.get_fleet(fleet_id)
			if String(fleet.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_DOCKED or int(fleet.get("location_id", -1)) != origin:
				continue
			if TransportSystemScript.available_capacity(world, fleet_id) < required:
				continue
			var command := CreateTransportOperationCommandScript.new(tag, army_id, fleet_id, landing_id)
			var reason := "Ferry an army directly to the active land objective across water." if landing_id == target else "Ferry an army to the nearest legal beachhead, then march the rest of the way."
			if _submit(world, tag, "transport", command, 88, reason, [], [army_id, fleet_id, landing_id], {"required_capacity": required}):
				_consider_proactive_escort_reservation(world, tag, fleet_id, origin)
				return
	_record_decision(world, tag, "transport", "no_transport_capacity", 40, "No idle army and docked fleet share a port with enough capacity to reach the landing site.", [], [landing_id])


## FL3.5: "proactive escort reservation" - the other half of escort
## lifecycle alongside _consider_escort_follow() above. Previously nothing
## went looking for an escort ahead of departure; _consider_escort()
## (FL3.4) only reactively picks up escort duty for a fleet that happens
## to already share a zone with a sailing transport. Called the instant a
## transport operation is actually created (not before - reserving an
## escort for a transport candidate that then fails validation would be a
## wasted, unexplained order), this looks for one other idle, docked
## fleet still at the same departure port and tags it protect_transport
## immediately, so it is ready to depart with (or shortly after) its
## convoy rather than only noticing the convoy by coincidence once both
## happen to already be at sea together. A no-op, not an error, when no
## second fleet is available - proactive escort is a bonus, not a
## requirement, for the transport operation itself.
func _consider_proactive_escort_reservation(world: CampaignWorldState, tag: String, transport_fleet_id: String, origin: int) -> void:
	var fleet_ids := world.country_fleets(tag)
	fleet_ids.sort()
	for fleet_id in fleet_ids:
		if fleet_id == transport_fleet_id:
			continue
		var fleet := world.get_fleet(fleet_id)
		if String(fleet.get("mission", "idle")) != "idle":
			continue
		if String(fleet.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_DOCKED or int(fleet.get("location_id", -1)) != origin:
			continue
		if not (fleet.get("transport_operation_ids", []) as Array).is_empty():
			continue
		var command := SetFleetMissionCommandScript.new(tag, fleet_id, "protect_transport")
		_submit(world, tag, "tactical", command, 55, "Reserve an idle fleet at the same port to escort the transport operation just created.", [], [fleet_id, transport_fleet_id])
		return


## FL3.5: "confirm... acceptable danger before reserving." An unescorted,
## unarmed transport should not be routed through a sea zone this country's
## own NavalThreatMap already considers dangerous enough to make a warship
## evade - ports are always excluded (already dockable/safe by definition;
## danger here means open water). Reuses THREATENED_ZONE_THREAT_THRESHOLD,
## the same bound _review_posture() already uses for "worth taking
## seriously," rather than inventing a second danger scale.
func _route_too_dangerous(world: CampaignWorldState, tag: String, path: Array) -> bool:
	for raw_node in path:
		var node_id := int((raw_node as Dictionary).get("id", -1))
		if graph.is_port_province(node_id):
			continue
		if int(threat_map.assess(world, tag, node_id, graph)["threat_score"]) > THREATENED_ZONE_THREAT_THRESHOLD:
			return true
	return false


## The target itself if this country may legally dock there; otherwise the
## lowest-ID owned port with a genuine land route onward to the target (not
## nearest-by-distance - the same "legal and deterministic beats optimal"
## simplification _best_construction_port() already uses). -1 if neither
## exists, meaning the objective is not reachable by sea at all under
## current access rules.
func _find_legal_landing(world: CampaignWorldState, tag: String, target: int, province_graph: ProvinceGraph) -> int:
	if graph.is_port_province(target) and NavalAccessPolicyScript.can_dock(graph, world, tag, target):
		return target
	for port_id in _country_ports(world, tag):
		if bool(ProvincePathfinderScript.find_route(province_graph, world, tag, port_id, target).get("exists", false)):
			return port_id
	return -1


# FL3.6: category -> the interval its own tick uses, so _record_decision()
# can compute a per-decision "next planning day" without every call site
# needing to pass its own profile/slot through. Kept as one lookup table
# rather than a parameter thread, since the mapping is fixed and already
# fully described by process_day()'s own five *_due checks above.
const CATEGORY_INTERVAL := {
	"posture": POSTURE_INTERVAL,
	"construction": CONSTRUCTION_INTERVAL,
	"organisation": ORGANISATION_INTERVAL,
	"tactical": TACTICAL_INTERVAL,
	"transport": TRANSPORT_INTERVAL,
}


func _submit(world: CampaignWorldState, tag: String, category: String, command: SimulationCommand, score: int, reason: String, alternatives: Array, targets: Array = [], constraints: Dictionary = {}) -> bool:
	var failure := command.validate(world)
	if not failure.is_empty():
		_record_rejected_candidate(world, tag, command.command_type(), failure, targets)
		return false
	command.issuer = tag
	scheduler.submit(command)
	world.global_counters["naval_ai_commands_submitted"] = int(world.global_counters.get("naval_ai_commands_submitted", 0)) + 1
	world.global_counters["naval_ai_candidates_evaluated"] = int(world.global_counters.get("naval_ai_candidates_evaluated", 0)) + 1
	_record_decision(world, tag, category, command.command_type(), score, reason, alternatives, targets, constraints)
	return true


## FL3.6: "record country, day, posture, action, targets, selected score,
## major rejected candidates, constraints and next planning day" (06_N6).
## `country` stays implicit (the record already lives inside that country's
## own runtime state - restating it in every entry would be redundant, the
## same reasoning the FL3 closure audit already accepted). Every other named
## field is now a real, structured entry: `targets` is the list of entity
## IDs (fleet/ship/province/zone/battle/army/admiral, whichever apply) this
## specific decision concerned, not just free text buried in `reason`;
## `constraints` is the actual bound/threshold/ratio value that gated the
## branch taken, by name; `posture` is copied from the country's own current
## state rather than left to a separate, uncorrelated field; `next_planning_day`
## is computed from CATEGORY_INTERVAL/_next_due_day() - the same function
## debug_snapshot() already used, now also stamped onto the decision record
## itself rather than only available as a live, separately-queried value.
##
## Verification: "trace" content (last_decision/decision_history/
## decision_counts/rejected_candidates) is gated on world.global_flags
## "naval_ai_tracing_enabled" (default true, so every existing caller's
## behaviour is unchanged) - see FL3_VERIFICATION_3_TRACE_NEUTRALITY.md.
## The checksummed global_counters (naval_ai_decisions/
## naval_ai_commands_submitted/naval_ai_candidates_evaluated) always
## increment regardless of the flag - those are authoritative deterministic
## tallies the roadmap tracks as a separate "Add counters for..." bullet
## from "Confirm trace production does not change authoritative results,"
## not trace content themselves.
func _record_decision(world: CampaignWorldState, tag: String, category: String, action: String, score: int, reason: String, alternatives: Array, targets: Array = [], constraints: Dictionary = {}) -> void:
	world.global_counters["naval_ai_decisions"] = int(world.global_counters.get("naval_ai_decisions", 0)) + 1
	if not bool(world.global_flags.get("naval_ai_tracing_enabled", true)):
		return
	var state := _ai_state(world, tag)
	var slot := int(profiles.get(tag, {}).get("slot", 0))
	var interval := int(CATEGORY_INTERVAL.get(category, TACTICAL_INTERVAL))
	var record := {
		"day": world.current_day,
		"category": category,
		"action": action,
		"score": score,
		"reason": reason,
		"alternatives": alternatives.duplicate(true),
		"targets": targets.duplicate(true),
		"constraints": constraints.duplicate(true),
		"posture": String(state.get("posture", "")),
		"next_planning_day": _next_due_day(world.current_day, interval, slot),
	}
	state["last_decision"] = record
	var history: Array = state.get("decision_history", [])
	history.append(record)
	while history.size() > MAX_DECISION_HISTORY:
		history.pop_front()
	state["decision_history"] = history
	var counts: Dictionary = state.get("decision_counts", {})
	counts[category] = int(counts.get(category, 0)) + 1
	state["decision_counts"] = counts
	_set_ai_state(world, tag, state)


func _record_rejected_candidate(world: CampaignWorldState, tag: String, action: String, reason: String, targets: Array = []) -> void:
	# FL3.6: "candidates evaluated," distinct from naval_ai_decisions (which
	# also counts non-candidate bookkeeping records like "fleet_sufficient"
	# or "hold_stations" - there was nothing to evaluate in those cases, only
	# nothing to do). A candidate is "evaluated" the moment a concrete action
	# was actually assessed and either accepted (_submit's success path,
	# right alongside naval_ai_commands_submitted) or rejected (here) - the
	# two together are the complete accepted-plus-rejected tally. Always
	# counted regardless of the tracing flag below - see _record_decision()'s
	# own doc comment for why the checksummed counters are not "trace."
	world.global_counters["naval_ai_candidates_evaluated"] = int(world.global_counters.get("naval_ai_candidates_evaluated", 0)) + 1
	if not bool(world.global_flags.get("naval_ai_tracing_enabled", true)):
		return
	var state := _ai_state(world, tag)
	var rejected: Array = state.get("rejected_candidates", [])
	rejected.append({"day": world.current_day, "action": action, "reason": reason, "targets": targets.duplicate(true)})
	while rejected.size() > 8:
		rejected.pop_front()
	state["rejected_candidates"] = rejected
	_set_ai_state(world, tag, state)


func _ai_state(world: CampaignWorldState, tag: String) -> Dictionary:
	var runtime := world.country_runtime(tag)
	if not runtime.has("naval_ai"):
		return _new_ai_state()
	return (runtime.get("naval_ai", {}) as Dictionary).duplicate(true)


func _set_ai_state(world: CampaignWorldState, tag: String, state: Dictionary) -> void:
	var runtime := world.country_runtime(tag)
	runtime["naval_ai"] = state
	world.set_country_runtime(tag, runtime)


static func _due(day: int, interval: int, slot: int) -> bool:
	return day >= slot and (day - slot) % interval == 0


static func _next_due_day(day: int, interval: int, slot: int) -> int:
	if day <= slot:
		return slot
	var elapsed := day - slot
	return day + (interval - elapsed % interval) % interval
