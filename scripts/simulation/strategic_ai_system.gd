class_name StrategicAISystem
extends RefCounted

## Deterministic utility AI for the Phase 6 Iberian vertical slice.
##
## The AI observes authoritative WorldState, scores stable candidate lists, and
## submits the same commands exposed to the player. It never mutates gameplay
## state directly. Persistent goals/plans live in country runtime values so
## save/load and checksums preserve future decisions exactly.

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const PeaceSystemScript = preload("res://scripts/simulation/peace_system.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const ProvincePathfinderScript = preload("res://scripts/simulation/province_pathfinder.gd")
const DeterministicRngScript = preload("res://scripts/simulation/deterministic_rng.gd")
const ConstructBuildingCommandScript = preload("res://scripts/simulation/commands/construct_building_command.gd")
const RecruitUnitCommandScript = preload("res://scripts/simulation/commands/recruit_unit_command.gd")
const SetArmyMaintenanceCommandScript = preload("res://scripts/simulation/commands/set_army_maintenance_command.gd")
const TakeLoanCommandScript = preload("res://scripts/simulation/commands/take_loan_command.gd")
const RepayLoanCommandScript = preload("res://scripts/simulation/commands/repay_loan_command.gd")
const ImproveRelationsCommandScript = preload("res://scripts/simulation/commands/improve_relations_command.gd")
const FormAllianceCommandScript = preload("res://scripts/simulation/commands/form_alliance_command.gd")
const RequestMilitaryAccessCommandScript = preload("res://scripts/simulation/commands/request_military_access_command.gd")
const GrantMilitaryAccessCommandScript = preload("res://scripts/simulation/commands/grant_military_access_command.gd")
const DeclareWarCommandScript = preload("res://scripts/simulation/commands/declare_war_command.gd")
const OfferPeaceCommandScript = preload("res://scripts/simulation/commands/offer_peace_command.gd")
const AcceptPeaceCommandScript = preload("res://scripts/simulation/commands/accept_peace_command.gd")
const MoveArmyCommandScript = preload("res://scripts/simulation/commands/move_army_command.gd")

const ECONOMY_INTERVAL := 30
const DIPLOMACY_INTERVAL := 15
const MILITARY_INTERVAL := 7
const TACTICAL_INTERVAL := 3
const STRATEGY_INTERVAL := 90
const MAX_DECISION_HISTORY := 16

var scheduler: SimulationScheduler
var events: SimulationEventBus
var definitions: AIDefinitions
var graph: ProvinceGraph
var economy_definitions
var decision_cost_usec: Dictionary = {}


func _init(p_scheduler: SimulationScheduler, p_events: SimulationEventBus, p_definitions: AIDefinitions) -> void:
	scheduler = p_scheduler
	events = p_events
	definitions = p_definitions
	graph = ProvinceGraph.load_default()
	economy_definitions = EconomyDefinitionsScript.load_default()


func initialize_world(world: CampaignWorldState) -> void:
	world.global_flags["ai_enabled"] = true
	world.global_flags["ai_slice_id"] = definitions.slice_id()
	for relation_data in definitions.initial_relationships():
		var relation_definition: Dictionary = relation_data
		var country_a := String(relation_definition.get("a", ""))
		var country_b := String(relation_definition.get("b", ""))
		if not world.has_country(country_a) or not world.has_country(country_b):
			continue
		var key := DiplomacySystemScript.relation_key(country_a, country_b)
		if not world.diplomatic_relations.has(key):
			var relation := DiplomacySystemScript.relation(world, country_a, country_b)
			var opinions: Dictionary = relation["opinions"]
			opinions[country_a] = int(relation_definition.get("opinion_a", 0))
			opinions[country_b] = int(relation_definition.get("opinion_b", 0))
			relation["opinions"] = opinions
			relation["alliance"] = bool(relation_definition.get("alliance", false))
			relation["rivalry"] = bool(relation_definition.get("rivalry", false))
			DiplomacySystemScript.set_relation(world, country_a, country_b, relation)
	for tag in definitions.country_tags():
		if not world.has_country(tag):
			continue
		var runtime := world.country_runtime(tag)
		if not runtime.has("ai"):
			runtime["ai"] = _new_ai_state(tag, world)
			world.set_country_runtime(tag, runtime)


func ensure_world(world: CampaignWorldState) -> void:
	if String(world.global_flags.get("ai_slice_id", "")) != definitions.slice_id():
		initialize_world(world)
		return
	for tag in definitions.country_tags():
		if not world.has_country(tag):
			continue
		var runtime := world.country_runtime(tag)
		if not runtime.has("ai"):
			runtime["ai"] = _new_ai_state(tag, world)
			world.set_country_runtime(tag, runtime)


func process_day(world: CampaignWorldState) -> void:
	if not bool(world.global_flags.get("ai_enabled", true)):
		return
	if String(world.global_flags.get("campaign_status", "running")) != "running":
		return
	ensure_world(world)
	for tag in definitions.country_tags():
		if not world.has_country(tag) or tag == world.player_country or world.get_country_provinces(tag).is_empty():
			continue
		var started := Time.get_ticks_usec()
		var profile := definitions.profile(tag)
		var slot := int(profile.get("slot", 0))
		if _due(world.current_day, STRATEGY_INTERVAL, slot):
			_review_strategy(world, tag, profile)
		if _due(world.current_day, ECONOMY_INTERVAL, slot):
			_plan_economy(world, tag, profile)
		if _due(world.current_day, DIPLOMACY_INTERVAL, slot):
			_plan_diplomacy(world, tag, profile)
		if _due(world.current_day, MILITARY_INTERVAL, slot):
			_plan_military(world, tag, profile, false)
		elif _due(world.current_day, TACTICAL_INTERVAL, slot):
			_plan_military(world, tag, profile, true)
		decision_cost_usec[tag] = Time.get_ticks_usec() - started


func debug_snapshot(world: CampaignWorldState, country_tag: String) -> Dictionary:
	if not world.has_country(country_tag):
		return {}
	var state := _ai_state(world, country_tag)
	var threat := _highest_threat(world, country_tag)
	var profile := definitions.profile(country_tag)
	return {
		"country_tag": country_tag,
		"government": String(profile.get("government", "Unknown government")),
		"ruler": String(profile.get("ruler", "Unknown ruler")),
		"enabled": bool(state.get("enabled", false)),
		"goal": String(state.get("goal", "")),
		"posture": String(state.get("posture", "")),
		"target_country": String(state.get("target_country", "")),
		"target_province_id": int(state.get("target_province_id", -1)),
		"plan": String(state.get("plan", "")),
		"reserve_target": int(state.get("reserve_target", 0)),
		"desired_army_strength": int(state.get("desired_army_strength", 0)),
		"current_army_strength": _country_strength(world, country_tag),
		"highest_threat": threat,
		"last_decision": (state.get("last_decision", {}) as Dictionary).duplicate(true),
		"decision_history": (state.get("decision_history", []) as Array).duplicate(true),
		"decision_counts": (state.get("decision_counts", {}) as Dictionary).duplicate(true),
		"rejected_candidates": (state.get("rejected_candidates", []) as Array).duplicate(true),
		"decision_cost_usec": int(decision_cost_usec.get(country_tag, 0)),
		"campaign_seed": world.campaign_seed,
		"country_seed": DeterministicRngScript.stream_seed(world.campaign_seed, "ai:%s" % country_tag),
		"next_economy_day": _next_due_day(world.current_day, ECONOMY_INTERVAL, int(profile.get("slot", 0))),
		"next_diplomacy_day": _next_due_day(world.current_day, DIPLOMACY_INTERVAL, int(profile.get("slot", 0))),
		"next_military_day": _next_due_day(world.current_day, MILITARY_INTERVAL, int(profile.get("slot", 0))),
	}


func objective_map_values(world: CampaignWorldState, country_tag: String) -> Dictionary:
	var values := {}
	if not world.has_country(country_tag):
		return values
	var state := _ai_state(world, country_tag)
	var capital := _capital(world, country_tag, definitions.profile(country_tag))
	if capital >= 0:
		values[capital] = Color(0.2, 0.75, 0.95)
	var target := int(state.get("target_province_id", -1))
	if target >= 0:
		values[target] = Color(0.95, 0.7, 0.16)
	for army_id in world.country_armies(country_tag):
		var army := world.get_army(army_id)
		var destination := int(army.get("destination_province_id", -1))
		if destination >= 0:
			values[destination] = Color(0.72, 0.3, 0.9)
	return values


func _new_ai_state(tag: String, world: CampaignWorldState) -> Dictionary:
	var profile := definitions.profile(tag)
	return {
		"enabled": true,
		"profile_id": tag,
		"goal": String(profile.get("strategy", "survive")),
		"posture": "peaceful",
		"target_country": "",
		"target_province_id": -1,
		"plan": "Observe the regional situation.",
		"reserve_target": int(profile.get("minimum_reserve", 50000)),
		"desired_army_strength": int(profile.get("minimum_army_strength", 1000)),
		"recent_orders": {},
		"last_decision": {},
		"decision_history": [],
		"decision_counts": {},
		"rejected_candidates": [],
		"initialized_day": world.current_day,
	}


func _review_strategy(world: CampaignWorldState, tag: String, profile: Dictionary) -> void:
	var state := _ai_state(world, tag)
	var runtime := world.country_runtime(tag)
	var wars := DiplomacySystemScript.country_wars(world, tag)
	var threat := _highest_threat(world, tag)
	var provinces := world.get_country_provinces(tag).size()
	var desired := maxi(int(profile.get("minimum_army_strength", 1000)), provinces * int(profile.get("army_strength_per_province", 200)))
	state["desired_army_strength"] = desired
	if not wars.is_empty():
		state["goal"] = "win_current_war"
		state["posture"] = "defensive" if int(threat.get("score", 0)) > 100 else "offensive"
		state["plan"] = "Protect critical territory and pursue the active war goal."
	elif int(runtime.get("debt", 0)) > 0 or int((runtime.get("ledger", {}) as Dictionary).get("balance", 0)) < 0:
		state["goal"] = "economic_recovery"
		state["posture"] = "recovering"
		state["plan"] = "Restore a positive balance and repay debt before expansion."
	elif int(threat.get("score", 0)) >= 100:
		state["goal"] = "deter_threat"
		state["posture"] = "defensive"
		state["plan"] = "Build strength and protect the capital from %s." % String(threat.get("country", ""))
	else:
		state["goal"] = String(profile.get("strategy", "regional_security"))
		state["posture"] = "peaceful"
		state["plan"] = "Develop the country while monitoring regional opportunities."
	_set_ai_state(world, tag, state)
	_record_decision(world, tag, "strategy", "review_strategy", 100, String(state["plan"]), [])
	events.ai_goal_changed.emit(tag, String(state["goal"]), String(state["posture"]))


func _plan_economy(world: CampaignWorldState, tag: String, profile: Dictionary) -> void:
	var runtime := world.country_runtime(tag)
	var ledger: Dictionary = runtime.get("ledger", {})
	var expenses := int(ledger.get("total_expenses", 0))
	var reserve := maxi(int(profile.get("minimum_reserve", 50000)), expenses * int(profile.get("reserve_months", 6)))
	var state := _ai_state(world, tag)
	state["reserve_target"] = reserve
	_set_ai_state(world, tag, state)
	var at_war := not DiplomacySystemScript.country_wars(world, tag).is_empty()
	var desired_maintenance := 10000 if at_war else int(profile.get("peace_maintenance_bp", 5000))
	if int(runtime.get("army_maintenance_bp", 10000)) != desired_maintenance:
		_submit(world, tag, "economy", SetArmyMaintenanceCommandScript.new(tag, desired_maintenance), 80, "Adjust maintenance for the current war posture.", [])

	# Debt repayment takes precedence over optional development.
	if int(runtime.get("debt", 0)) > 0 and int(runtime.get("treasury", 0)) >= reserve + EconomySystemScript.LOAN_PRINCIPAL:
		var loan_ids := world.loan_registry.keys()
		loan_ids.sort()
		for raw_loan_id in loan_ids:
			if String(world.loan_registry[raw_loan_id].get("country_tag", "")) == tag:
				_submit(world, tag, "economy", RepayLoanCommandScript.new(tag, String(raw_loan_id)), 95, "Repay debt while retaining the strategic reserve.", [])
				return

	var strength := _country_strength(world, tag)
	var desired_strength := int(state.get("desired_army_strength", int(profile.get("minimum_army_strength", 1000))))
	var pending_recruits := 0
	for recruitment in world.recruitment_registry.values():
		if String((recruitment as Dictionary).get("country_tag", "")) == tag:
			pending_recruits += 1
	var unit: Dictionary = economy_definitions.unit("infantry_regiment")
	if strength + pending_recruits * 1000 < desired_strength:
		var recruit_province := _best_recruitment_province(world, tag, profile)
		var recruit_cost := int(unit.get("cost", 0))
		if recruit_province >= 0 and (at_war or int(runtime.get("treasury", 0)) - recruit_cost >= reserve):
			var recruit := RecruitUnitCommandScript.new(tag, recruit_province)
			if recruit.validate(world).is_empty():
				_submit(world, tag, "economy", recruit, 90 if at_war else 70, "Recruit toward desired strength %d." % desired_strength, [])
				return
		elif at_war and int(runtime.get("treasury", 0)) < recruit_cost and int(runtime.get("debt", 0)) < EconomySystemScript.MAXIMUM_DEBT:
			_submit(world, tag, "economy", TakeLoanCommandScript.new(tag), 60, "Emergency wartime borrowing for recruitment.", [])
			return

	if not at_war and int(runtime.get("treasury", 0)) > reserve:
		var candidates := _building_candidates(world, tag, reserve)
		if not candidates.is_empty():
			var selected: Dictionary = candidates[0]
			_submit(world, tag, "economy", selected["command"], int(selected["score"]), String(selected["reason"]), _candidate_debug(candidates))
			return
	_record_decision(world, tag, "economy", "hold_reserve", 50, "No affordable action improves the current position without breaking reserve.", [])


func _plan_diplomacy(world: CampaignWorldState, tag: String, profile: Dictionary) -> void:
	if _respond_to_access_requests(world, tag):
		return
	if _respond_to_peace_offers(world, tag):
		return
	var wars := DiplomacySystemScript.country_wars(world, tag)
	if not wars.is_empty():
		if _consider_outgoing_peace(world, tag, wars[0]):
			return
		_record_decision(world, tag, "diplomacy", "continue_war", 55, "No valid peace improves the current war position.", [])
		return

	for raw_ally in profile.get("preferred_allies", []):
		var ally := String(raw_ally)
		if not world.has_country(ally) or ally == tag:
			continue
		if DiplomacySystemScript.are_allied(world, tag, ally):
			if not DiplomacySystemScript.has_access(world, tag, ally):
				var access := RequestMilitaryAccessCommandScript.new(tag, ally)
				if access.validate(world).is_empty():
					_submit(world, tag, "diplomacy", access, 60, "Secure access through an allied country.", [])
					return
			continue
		if DiplomacySystemScript.opinion(world, tag, ally) >= 25:
			var alliance := FormAllianceCommandScript.new(tag, ally)
			if alliance.validate(world).is_empty():
				_submit(world, tag, "diplomacy", alliance, 80, "Preferred ally improves regional security.", [])
				return
		else:
			var improve := ImproveRelationsCommandScript.new(tag, ally)
			if improve.validate(world).is_empty():
				_submit(world, tag, "diplomacy", improve, 55, "Build opinion toward a preferred alliance.", [])
				return

	if world.current_day >= 180 and int(profile.get("aggression", 0)) >= 50:
		for raw_target in profile.get("preferred_targets", []):
			var target := String(raw_target)
			var war_goal := _valid_desired_province(world, target, profile)
			if war_goal < 0 or DiplomacySystemScript.has_active_truce(world, tag, target):
				continue
			var friendly_strength := _coalition_strength(world, tag)
			var hostile_strength := _coalition_strength(world, target)
			var required_bp := int(profile.get("risk_tolerance_bp", 13000))
			if friendly_strength * 10000 < maxi(hostile_strength, 1) * required_bp:
				continue
			var declaration := DeclareWarCommandScript.new(tag, target, war_goal)
			if declaration.validate(world).is_empty():
				_submit(world, tag, "diplomacy", declaration, 100, "Preferred conquest target is reachable at an acceptable strength ratio.", [])
				return
	_record_decision(world, tag, "diplomacy", "preserve_relations", 40, "No alliance, access, war, or peace action currently passes policy.", [])


func _plan_military(world: CampaignWorldState, tag: String, profile: Dictionary, tactical_only: bool) -> void:
	var wars := DiplomacySystemScript.country_wars(world, tag)
	var state := _ai_state(world, tag)
	if wars.is_empty():
		if tactical_only:
			return
		var capital := _capital(world, tag, profile)
		state["target_country"] = ""
		state["target_province_id"] = capital
		state["plan"] = "Rally available forces near the capital."
		_set_ai_state(world, tag, state)
		_issue_army_orders(world, tag, capital, "rally_capital", 45)
		return
	var war_id := wars[0]
	var war: Dictionary = world.war_registry[war_id]
	var objective := _select_war_objective(world, tag, profile, war)
	var target := int(objective.get("province_id", -1))
	state["target_country"] = String(objective.get("target_country", ""))
	state["target_province_id"] = target
	state["plan"] = String(objective.get("reason", "Pursue the active war objective."))
	state["posture"] = String(objective.get("posture", "offensive"))
	_set_ai_state(world, tag, state)
	if target >= 0:
		_issue_army_orders(world, tag, target, String(objective.get("action", "war_objective")), int(objective.get("score", 70)))


func _select_war_objective(world: CampaignWorldState, tag: String, profile: Dictionary, war: Dictionary) -> Dictionary:
	var side := DiplomacySystemScript.side_in_war(war, tag)
	var capital := _capital(world, tag, profile)
	# Capital defence always outranks expansion.
	for enemy_id in _enemy_armies(world, war, side):
		var enemy := world.get_army(enemy_id)
		if int(enemy.get("current_province_id", -1)) == capital:
			return {"province_id": capital, "target_country": String(enemy.get("owner_country_id", "")), "action": "defend_capital", "score": 120, "posture": "defensive", "reason": "Enemy forces threaten the capital."}
	# Liberate owned occupied provinces before starting a new siege.
	for occupation in (war.get("occupied_provinces", {}) as Dictionary).values():
		var province_id := int((occupation as Dictionary).get("province_id", -1))
		if world.get_province_owner(province_id) == tag and world.get_province_controller(province_id) != tag:
			return {"province_id": province_id, "target_country": world.get_province_controller(province_id), "action": "liberate_province", "score": 110, "posture": "defensive", "reason": "Liberate occupied home territory."}
	var goal_id := int((war.get("war_goal", {}) as Dictionary).get("province_id", -1))
	var enemy_strength_total := 0
	for enemy_id in _enemy_armies(world, war, side):
		enemy_strength_total += int(world.get_army(enemy_id).get("strength", 0))
	if side > 0 and _country_strength(world, tag) * 100 < enemy_strength_total * 75:
		return {"province_id": capital, "target_country": "", "action": "avoid_losing_battle", "score": 108, "posture": "defensive", "reason": "Enemy field strength is overwhelming; regroup at the capital."}
	if side > 0 and goal_id >= 0 and world.get_province_controller(goal_id) != tag:
		return {"province_id": goal_id, "target_country": world.get_province_owner(goal_id), "action": "take_war_goal", "score": 100, "posture": "offensive", "reason": "Capture and hold the declared war goal."}
	if side < 0 and goal_id >= 0 and world.get_province_owner(goal_id) == tag:
		return {"province_id": goal_id, "target_country": String(war.get("attacker_leader", "")), "action": "defend_war_goal", "score": 105, "posture": "defensive", "reason": "Protect the enemy's declared war goal."}
	var own_strength := _country_strength(world, tag)
	var weakest := {}
	for enemy_id in _enemy_armies(world, war, side):
		var enemy := world.get_army(enemy_id)
		var enemy_strength := int(enemy.get("strength", 0))
		if own_strength * 100 >= enemy_strength * 130 and (weakest.is_empty() or enemy_strength < int(weakest.get("strength", 0))):
			weakest = {"province_id": int(enemy.get("current_province_id", -1)), "target_country": String(enemy.get("owner_country_id", "")), "strength": enemy_strength}
	if not weakest.is_empty():
		return {"province_id": int(weakest["province_id"]), "target_country": String(weakest["target_country"]), "action": "engage_weaker_army", "score": 85, "posture": "offensive", "reason": "Engage an enemy force with a favourable strength estimate."}
	return {"province_id": capital, "target_country": "", "action": "defend_capital", "score": 60, "posture": "defensive", "reason": "No safe offensive objective; preserve the army near the capital."}


func _issue_army_orders(world: CampaignWorldState, tag: String, target: int, action: String, score: int) -> void:
	if target < 0 or not world.has_province(target):
		return
	var alternatives := [{"action_id": action, "score": score, "province_id": target}]
	var issued := false
	for army_id in world.country_armies(tag):
		var army := world.get_army(army_id)
		if String(army.get("status", CampaignWorldState.ARMY_STATUS_IDLE)) != CampaignWorldState.ARMY_STATUS_IDLE:
			continue
		var current := int(army.get("current_province_id", -1))
		if current == target or _order_recently_repeated(world, tag, army_id, current, target):
			continue
		var command := MoveArmyCommandScript.new(army_id, target, tag, "ai")
		var failure := command.validate(world)
		if not failure.is_empty():
			_record_rejected_candidate(world, tag, action, failure)
			continue
		_submit(world, tag, "military", command, score, "Order %s toward province %d." % [army_id, target], alternatives)
		_remember_order(world, tag, army_id, current, target)
		issued = true
	if not issued:
		_record_decision(world, tag, "military", "hold_position", 35, "No idle army has a new valid route to the selected objective.", alternatives)


func _respond_to_access_requests(world: CampaignWorldState, tag: String) -> bool:
	for other in definitions.country_tags():
		if other == tag or not world.has_country(other):
			continue
		var relation := DiplomacySystemScript.relation(world, tag, other)
		if bool((relation.get("access_requests", {}) as Dictionary).get(other, false)) and (DiplomacySystemScript.are_allied(world, tag, other) or DiplomacySystemScript.opinion(world, tag, other) >= 0):
			var grant := GrantMilitaryAccessCommandScript.new(tag, other)
			if grant.validate(world).is_empty():
				_submit(world, tag, "diplomacy", grant, 65, "Grant useful access to a friendly requester.", [])
				return true
	return false


func _respond_to_peace_offers(world: CampaignWorldState, tag: String) -> bool:
	for war_id in DiplomacySystemScript.country_wars(world, tag):
		var war: Dictionary = world.war_registry[war_id]
		var offer_ids := (war.get("peace_offers", {}) as Dictionary).keys()
		offer_ids.sort()
		for raw_offer_id in offer_ids:
			var offer: Dictionary = war["peace_offers"][raw_offer_id]
			if String(offer.get("receiver", "")) != tag or world.current_day > int(offer.get("expires_day", -1)):
				continue
			var offerer := String(offer.get("offerer", ""))
			var offerer_side := DiplomacySystemScript.side_in_war(war, offerer)
			var advantage := int(war.get("total_war_score", 0)) * offerer_side
			var cost := int(offer.get("war_score_cost", 0))
			var terms: Array = offer.get("terms", [])
			var white_peace := terms.size() == 1 and String((terms[0] as Dictionary).get("type", "")) == "white_peace"
			var duration := world.current_day - int(war.get("start_day", world.current_day))
			if (white_peace and (advantage >= 8 or duration >= 365)) or (not white_peace and advantage >= cost) or _country_strength(world, tag) <= 500:
				var accept := AcceptPeaceCommandScript.new(war_id, String(raw_offer_id), tag)
				if accept.validate(world).is_empty():
					_submit(world, tag, "diplomacy", accept, 100, "Accept peace because the terms match the military position.", [])
					return true
	return false


func _consider_outgoing_peace(world: CampaignWorldState, tag: String, war_id: String) -> bool:
	var war: Dictionary = world.war_registry[war_id]
	var leader := String(war.get("attacker_leader", "")) if DiplomacySystemScript.side_in_war(war, tag) > 0 else String(war.get("defender_leader", ""))
	if leader != tag or _has_live_offer_from(war, tag, world.current_day):
		return false
	var side := DiplomacySystemScript.side_in_war(war, tag)
	var side_score := int(war.get("total_war_score", 0)) * side
	var opponent := String(war.get("defender_leader", "")) if side > 0 else String(war.get("attacker_leader", ""))
	var war_goal: Dictionary = war.get("war_goal", {})
	var goal_id := int(war_goal.get("province_id", -1))
	var is_claim_war := String(war_goal.get("type", "")) == "press_claim"
	var required_score := 35 if is_claim_war else 15
	if side > 0 and side_score >= required_score and goal_id >= 0 and DiplomacySystemScript.side_in_war(war, world.get_province_owner(goal_id)) == -side:
		var terms: Array = [{"type": "press_claim", "claim_id": String(war_goal.get("claim_id", ""))}] if is_claim_war else [{"type": "transfer_province", "province_id": goal_id, "to": tag}]
		var demand := OfferPeaceCommandScript.new(war_id, tag, opponent, terms)
		if demand.validate(world).is_empty():
			_submit(world, tag, "diplomacy", demand, 95, "Demand the occupied war goal at sufficient war score.", [])
			return true
	if side_score <= -12 or _country_strength(world, tag) <= 500:
		var white := OfferPeaceCommandScript.new(war_id, tag, opponent, [{"type": "white_peace"}])
		if white.validate(world).is_empty():
			_submit(world, tag, "diplomacy", white, 85, "Seek white peace to prevent further losses.", [])
			return true
	return false


func _building_candidates(world: CampaignWorldState, tag: String, reserve: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var building_ids: Array = economy_definitions.buildings.keys()
	building_ids.sort()
	var provinces := world.get_country_provinces(tag)
	provinces.sort()
	for raw_province_id in provinces:
		var province_id := int(raw_province_id)
		if world.get_province_controller(province_id) != tag:
			continue
		var economy: Dictionary = world.province_states[province_id].get("economy", {})
		for raw_building_id in building_ids:
			var building_id := String(raw_building_id)
			var definition: Dictionary = economy_definitions.building(building_id)
			var cost := int(definition.get("cost", 0))
			if int(world.country_runtime(tag).get("treasury", 0)) - cost < reserve:
				continue
			var command := ConstructBuildingCommandScript.new(tag, province_id, building_id)
			if not command.validate(world).is_empty():
				continue
			var score := int(economy.get("development", 0)) * 2 - cost / 10000
			score += int(definition.get("tax_modifier_bp", 0)) / 500
			score += int(definition.get("production_modifier_bp", 0)) / 500
			score += int(definition.get("manpower_modifier_bp", 0)) / 500
			candidates.append({"action_id": "build:%s:%d" % [building_id, province_id], "score": score, "command": command, "reason": "Best affordable building return while preserving reserve."})
	candidates.sort_custom(_candidate_precedes)
	return candidates


func _best_recruitment_province(world: CampaignWorldState, tag: String, profile: Dictionary) -> int:
	var capital := _capital(world, tag, profile)
	if capital >= 0 and world.get_province_owner(capital) == tag and world.get_province_controller(capital) == tag:
		return capital
	var best := -1
	var best_development := -1
	for raw_id in world.get_country_provinces(tag):
		var province_id := int(raw_id)
		if world.get_province_controller(province_id) != tag:
			continue
		var development := int((world.province_states[province_id].get("economy", {}) as Dictionary).get("development", 0))
		if development > best_development:
			best = province_id
			best_development = development
	return best


func _highest_threat(world: CampaignWorldState, tag: String) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for other in definitions.country_tags():
		if other == tag or not world.has_country(other) or world.get_country_provinces(other).is_empty():
			continue
		var border_count := _shared_border_count(world, tag, other)
		var relative_strength := _country_strength(world, other) * 100 / maxi(_country_strength(world, tag), 1)
		var opinion_penalty := maxi(0, -DiplomacySystemScript.opinion(world, tag, other))
		var score := border_count * 25 + relative_strength / 2 + opinion_penalty
		if DiplomacySystemScript.are_at_war(world, tag, other):
			score += 100
		if DiplomacySystemScript.are_allied(world, tag, other):
			score -= 80
		candidates.append({"country": other, "score": score, "border_count": border_count, "relative_strength_percent": relative_strength})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]) if int(a["score"]) != int(b["score"]) else String(a["country"]) < String(b["country"]))
	return candidates[0] if not candidates.is_empty() else {"country": "", "score": 0}


func _shared_border_count(world: CampaignWorldState, country_a: String, country_b: String) -> int:
	var borders := 0
	for raw_id in world.get_country_provinces(country_a):
		for neighbor in graph.land_neighbors(int(raw_id)):
			if world.get_province_owner(neighbor) == country_b:
				borders += 1
	return borders


func _valid_desired_province(world: CampaignWorldState, target: String, profile: Dictionary) -> int:
	for raw_id in profile.get("desired_provinces", []):
		var province_id := int(raw_id)
		if world.has_province(province_id) and world.get_province_owner(province_id) == target:
			return province_id
	var provinces := world.get_country_provinces(target)
	provinces.sort()
	return int(provinces[0]) if not provinces.is_empty() else -1


func _enemy_armies(world: CampaignWorldState, war: Dictionary, side: int) -> Array[String]:
	var armies: Array[String] = []
	var countries: Array = war.get("defenders", []) if side > 0 else war.get("attackers", [])
	for raw_country in countries:
		armies.append_array(world.country_armies(String(raw_country)))
	armies.sort()
	return armies


func _country_strength(world: CampaignWorldState, tag: String) -> int:
	var strength := 0
	for army_id in world.country_armies(tag):
		strength += maxi(0, int(world.get_army(army_id).get("strength", 0)))
	return strength


func _coalition_strength(world: CampaignWorldState, tag: String) -> int:
	var strength := _country_strength(world, tag)
	for other in definitions.country_tags():
		if other != tag and world.has_country(other) and DiplomacySystemScript.are_allied(world, tag, other):
			strength += _country_strength(world, other)
	return strength


func _capital(world: CampaignWorldState, tag: String, profile: Dictionary) -> int:
	var capital := int(profile.get("capital_province_id", -1))
	if world.has_province(capital) and world.get_province_owner(capital) == tag:
		return capital
	var provinces := world.get_country_provinces(tag)
	provinces.sort()
	return int(provinces[0]) if not provinces.is_empty() else -1


func _has_live_offer_from(war: Dictionary, tag: String, day: int) -> bool:
	for offer in (war.get("peace_offers", {}) as Dictionary).values():
		if String((offer as Dictionary).get("offerer", "")) == tag and day <= int((offer as Dictionary).get("expires_day", -1)):
			return true
	return false


func _submit(world: CampaignWorldState, tag: String, category: String, command: SimulationCommand, score: int, reason: String, alternatives: Array) -> bool:
	var failure := command.validate(world)
	if not failure.is_empty():
		_record_rejected_candidate(world, tag, command.command_type(), failure)
		return false
	command.issuer = tag
	scheduler.submit(command)
	world.global_counters["ai_commands_submitted"] = int(world.global_counters.get("ai_commands_submitted", 0)) + 1
	_record_decision(world, tag, category, command.command_type(), score, reason, alternatives)
	return true


func _record_decision(world: CampaignWorldState, tag: String, category: String, action: String, score: int, reason: String, alternatives: Array) -> void:
	var state := _ai_state(world, tag)
	var record := {
		"day": world.current_day,
		"category": category,
		"action": action,
		"score": score,
		"reason": reason,
		"alternatives": alternatives.duplicate(true),
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
	world.global_counters["ai_decisions"] = int(world.global_counters.get("ai_decisions", 0)) + 1
	events.ai_decision_made.emit(tag, category, action, score, reason)


func _record_rejected_candidate(world: CampaignWorldState, tag: String, action: String, reason: String) -> void:
	var state := _ai_state(world, tag)
	var rejected: Array = state.get("rejected_candidates", [])
	rejected.append({"day": world.current_day, "action": action, "reason": reason})
	while rejected.size() > 8:
		rejected.pop_front()
	state["rejected_candidates"] = rejected
	_set_ai_state(world, tag, state)


func _order_recently_repeated(world: CampaignWorldState, tag: String, army_id: String, current: int, target: int) -> bool:
	var recent: Dictionary = _ai_state(world, tag).get("recent_orders", {})
	if not recent.has(army_id):
		return false
	var order: Dictionary = recent[army_id]
	if world.current_day - int(order.get("day", -999)) > 14:
		return false
	return int(order.get("destination", -1)) == target or (int(order.get("from", -1)) == target and int(order.get("destination", -1)) == current)


func _remember_order(world: CampaignWorldState, tag: String, army_id: String, from_id: int, target: int) -> void:
	var state := _ai_state(world, tag)
	var recent: Dictionary = state.get("recent_orders", {})
	recent[army_id] = {"day": world.current_day, "from": from_id, "destination": target}
	state["recent_orders"] = recent
	_set_ai_state(world, tag, state)


func _ai_state(world: CampaignWorldState, tag: String) -> Dictionary:
	return (world.country_runtime(tag).get("ai", {}) as Dictionary).duplicate(true)


func _set_ai_state(world: CampaignWorldState, tag: String, state: Dictionary) -> void:
	var runtime := world.country_runtime(tag)
	runtime["ai"] = state
	world.set_country_runtime(tag, runtime)


func _due(day: int, interval: int, slot: int) -> bool:
	return day >= slot and (day - slot) % interval == 0


func _next_due_day(day: int, interval: int, slot: int) -> int:
	if day <= slot:
		return slot
	var elapsed := day - slot
	return day + (interval - elapsed % interval) % interval


func _candidate_debug(candidates: Array[Dictionary]) -> Array:
	var debug: Array = []
	for candidate in candidates.slice(0, mini(5, candidates.size())):
		debug.append({"action_id": String(candidate.get("action_id", "")), "score": int(candidate.get("score", 0))})
	return debug


func _candidate_precedes(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("score", 0)) != int(b.get("score", 0)):
		return int(a.get("score", 0)) > int(b.get("score", 0))
	return String(a.get("action_id", "")) < String(b.get("action_id", ""))
