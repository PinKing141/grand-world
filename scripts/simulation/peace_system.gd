class_name PeaceSystem
extends RefCounted

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const WarfareSystemScript = preload("res://scripts/simulation/warfare_system.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")


static func term_cost(war: Dictionary, term: Dictionary) -> int:
	match String(term.get("type", "")):
		"white_peace":
			return 0
		"transfer_province":
			var province_id := int(term.get("province_id", -1))
			var goal_id := int((war.get("war_goal", {}) as Dictionary).get("province_id", -2))
			return int((war.get("war_goal", {}) as Dictionary).get("peace_cost", 15)) if province_id == goal_id else 20
		"money":
			return clampi(int(term.get("amount", 0)) / 10000, 1, 25)
		"press_claim":
			return 35
	return 999


static func ai_term_value(war: Dictionary, term: Dictionary, evaluating_side: int) -> int:
	# Phase 6 AI can replace or extend this stable hook. Positive values favour
	# the side receiving the term; negative values represent concessions.
	return term_cost(war, term) * clampi(evaluating_side, -1, 1)


static func validate_terms(world: CampaignWorldState, war_id: String, offerer: String, receiver: String, terms: Array) -> String:
	if not world.war_registry.has(war_id):
		return "The war no longer exists."
	var war: Dictionary = world.war_registry[war_id]
	if String(war.get("status", "active")) != "active":
		return "The war has already ended."
	var offerer_side := DiplomacySystemScript.side_in_war(war, offerer)
	var receiver_side := DiplomacySystemScript.side_in_war(war, receiver)
	if offerer_side == 0 or receiver_side == 0 or offerer_side == receiver_side:
		return "Peace must be negotiated between opposing war participants."
	var leaders := [String(war.get("attacker_leader", "")), String(war.get("defender_leader", ""))]
	if not leaders.has(offerer) or not leaders.has(receiver):
		return "The initial war loop supports leader-to-leader peace only."
	if terms.is_empty():
		return "A peace offer needs at least one term."
	var contains_white_peace := false
	var cost := 0
	var seen_provinces := {}
	for raw_term in terms:
		if not raw_term is Dictionary:
			return "The peace offer contains a malformed term."
		var term: Dictionary = raw_term
		var type := String(term.get("type", ""))
		match type:
			"white_peace":
				contains_white_peace = true
			"transfer_province":
				var province_id := int(term.get("province_id", -1))
				var recipient := String(term.get("to", offerer))
				if not world.has_province(province_id) or seen_provinces.has(province_id):
					return "A transferred province is invalid or duplicated."
				seen_provinces[province_id] = true
				if DiplomacySystemScript.side_in_war(war, recipient) != offerer_side:
					return "A province can only be transferred to the offering side."
				var owner := world.get_province_owner(province_id)
				if DiplomacySystemScript.side_in_war(war, owner) != receiver_side:
					return "The opposing side does not own province %d." % province_id
				var controller := world.get_province_controller(province_id)
				var goal_id := int((war.get("war_goal", {}) as Dictionary).get("province_id", -2))
				if DiplomacySystemScript.side_in_war(war, controller) != offerer_side and province_id != goal_id:
					return "Province %d must be occupied before it can be demanded." % province_id
			"money":
				var payer := String(term.get("from", receiver))
				var recipient := String(term.get("to", offerer))
				var amount := int(term.get("amount", 0))
				if amount <= 0 or DiplomacySystemScript.side_in_war(war, payer) != receiver_side or DiplomacySystemScript.side_in_war(war, recipient) != offerer_side:
					return "The money term has invalid countries or amount."
				if int(world.country_runtime(payer).get("treasury", 0)) < amount:
					return "%s cannot afford that payment." % payer
			"press_claim":
				var goal: Dictionary = war.get("war_goal", {})
				var claim_id := String(term.get("claim_id", ""))
				if String(goal.get("type", "")) != "press_claim" or claim_id != String(goal.get("claim_id", "")):
					return "This war cannot enforce that claim."
				if offerer_side != 1 or not world.claim_registry.has(claim_id):
					return "Only the attacking side can enforce its valid claim."
				var claim: Dictionary = world.claim_registry[claim_id]
				var claimant := String(claim.get("claimant_id", ""))
				var title_id := String(claim.get("title_id", ""))
				if not world.character_registry.has(claimant) or not bool((world.character_registry[claimant] as Dictionary).get("alive", false)) or not world.title_registry.has(title_id):
					return "The claimant or claimed title is no longer valid."
			_:
				return "Unsupported peace term: %s." % type
		cost += term_cost(war, term)
	if contains_white_peace and terms.size() != 1:
		return "White peace cannot be combined with demands."
	var available_score := int(war.get("total_war_score", 0)) * offerer_side
	if not contains_white_peace and cost > maxi(available_score, 0):
		return "The offer costs %d war score, but only %d is available." % [cost, maxi(available_score, 0)]
	return ""


static func apply_offer(world: CampaignWorldState, events: SimulationEventBus, war_id: String, offer_id: String) -> String:
	if not world.war_registry.has(war_id):
		return "The war no longer exists."
	var war: Dictionary = world.war_registry[war_id]
	var offers: Dictionary = war.get("peace_offers", {})
	if not offers.has(offer_id):
		return "The peace offer no longer exists."
	var offer: Dictionary = offers[offer_id]
	var offerer := String(offer.get("offerer", ""))
	var receiver := String(offer.get("receiver", ""))
	var terms: Array = offer.get("terms", [])
	var failure := validate_terms(world, war_id, offerer, receiver, terms)
	if not failure.is_empty():
		return failure

	# Terms are fully validated before the first mutation, making acceptance an
	# atomic deterministic state transition.
	for raw_term in terms:
		var term: Dictionary = raw_term
		match String(term["type"]):
			"transfer_province":
				var province_id := int(term["province_id"])
				var recipient := String(term.get("to", offerer))
				var old_controller := world.get_province_controller(province_id)
				var old_owner := world.set_province_owner(province_id, recipient)
				world.set_province_controller(province_id, recipient)
				var state: Dictionary = world.province_states[province_id]
				var economy: Dictionary = state.get("economy", {})
				economy["recently_conquered_until_day"] = world.current_day + 1825
				economy["separatism_bp"] = 0 if (economy.get("cores", []) as Array).has(recipient) else 2500
				state["economy"] = economy
				world.province_states[province_id] = state
				var dynamic: Array = world.global_flags.get("country_depth_dynamic_provinces", [])
				if not dynamic.has(province_id):
					dynamic.append(province_id)
					dynamic.sort()
					world.global_flags["country_depth_dynamic_provinces"] = dynamic
				events.publish_owner_change(province_id, old_owner, recipient)
				events.province_controller_changed.emit(province_id, old_controller, recipient)
			"money":
				var payer := String(term.get("from", receiver))
				var recipient := String(term.get("to", offerer))
				var amount := int(term["amount"])
				var payer_runtime := world.country_runtime(payer)
				var recipient_runtime := world.country_runtime(recipient)
				payer_runtime["treasury"] = int(payer_runtime.get("treasury", 0)) - amount
				recipient_runtime["treasury"] = int(recipient_runtime.get("treasury", 0)) + amount
				world.set_country_runtime(payer, payer_runtime)
				world.set_country_runtime(recipient, recipient_runtime)
			"press_claim":
				var claim_id := String(term["claim_id"])
				var claim: Dictionary = world.claim_registry[claim_id]
				var claimant := String(claim["claimant_id"])
				var title_id := String(claim["title_id"])
				CharacterSystemScript.grant_title(world, events, title_id, claimant)
				claim["pressed"] = true
				world.claim_registry[claim_id] = claim
				var target_country := String((world.title_registry[title_id] as Dictionary).get("country_tag", ""))
				if world.has_country(target_country):
					var target_runtime := world.country_runtime(target_country)
					target_runtime["ruler_character_id"] = claimant
					target_runtime["personal_union_senior"] = offerer
					target_runtime["reign_start_day"] = world.current_day
					target_runtime["short_reign_until_day"] = world.current_day + CharacterSystemScript.SHORT_REIGN_DAYS
					world.set_country_runtime(target_country, target_runtime)
					CharacterSystemScript.refresh_country_heir(world, target_country)
					CharacterSystemScript.recalculate_ruler_modifiers(world, target_country)
				events.claim_pressed.emit(claim_id, title_id, claimant)

	WarfareSystemScript.clear_war_occupations(world, events, war)
	_cleanup_armies(world, war)
	var truce_until := -1
	for raw_attacker in war.get("attackers", []):
		for raw_defender in war.get("defenders", []):
			truce_until = DiplomacySystemScript.create_truce(world, String(raw_attacker), String(raw_defender))
	war["status"] = "ended"
	war["end_day"] = world.current_day
	war["accepted_offer"] = offer.duplicate(true)
	var history: Array = war.get("history", [])
	history.append({"day": world.current_day, "type": "peace_signed", "offer_id": offer_id})
	war["history"] = history
	# Completed wars remain as history rather than being erased. Queries only
	# consider active records, preventing stale hostility while preserving logs.
	world.war_registry[war_id] = war
	for tag in [offerer, receiver]:
		if world.has_country(tag):
			EconomySystemScript.recalculate_country(world, tag)
	events.peace_signed.emit(war_id, String(war["attacker_leader"]), String(war["defender_leader"]), truce_until)
	return ""


static func _cleanup_armies(world: CampaignWorldState, war: Dictionary) -> void:
	var participants: Array = (war.get("attackers", []) as Array) + (war.get("defenders", []) as Array)
	var army_ids := world.army_registry.keys()
	army_ids.sort()
	for raw_army_id in army_ids:
		var army: Dictionary = world.army_registry[raw_army_id]
		if not participants.has(String(army.get("owner_country_id", ""))):
			continue
		army["battle_id"] = ""
		if String(army.get("status", "")) == CampaignWorldState.ARMY_STATUS_BATTLE:
			army["status"] = CampaignWorldState.ARMY_STATUS_IDLE
			army["movement_locked"] = false
		world.army_registry[raw_army_id] = army
