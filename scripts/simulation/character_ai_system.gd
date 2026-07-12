class_name CharacterAISystem
extends RefCounted

const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const ArrangeMarriageCommandScript = preload("res://scripts/simulation/commands/arrange_marriage_command.gd")
const AssignCommanderCommandScript = preload("res://scripts/simulation/commands/assign_commander_command.gd")
const DeclareClaimWarCommandScript = preload("res://scripts/simulation/commands/declare_claim_war_command.gd")

const REVIEW_INTERVAL_DAYS := 30

var scheduler: SimulationScheduler
var events: SimulationEventBus
var _reserved_marriage_ids: Dictionary = {}


func _init(p_scheduler: SimulationScheduler, p_events: SimulationEventBus) -> void:
	scheduler = p_scheduler
	events = p_events


func process_month(world: CampaignWorldState) -> void:
	_reserved_marriage_ids.clear()
	var tags := world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		if tag == world.player_country or CharacterSystemScript.ruler_id(world, tag).is_empty() or world.get_country_provinces(tag).is_empty():
			continue
		_review_country(world, tag)


func debug_snapshot(world: CampaignWorldState, country_tag: String) -> Dictionary:
	return (world.country_runtime(country_tag).get("character_ai", {}) as Dictionary).duplicate(true) if world.has_country(country_tag) else {}


func _review_country(world: CampaignWorldState, country_tag: String) -> void:
	var runtime := world.country_runtime(country_tag)
	var state: Dictionary = runtime.get("character_ai", {"decisions": [], "last_action": "", "last_reason": ""})
	var ruler := CharacterSystemScript.ruler_id(world, country_tag)
	var heir := CharacterSystemScript.heir_id(world, country_tag)
	state["ruler_id"] = ruler
	state["heir_id"] = heir
	state["succession_secure"] = not heir.is_empty()
	state["last_review_day"] = world.current_day
	if _assign_best_commander(world, country_tag, state):
		_save_state(world, country_tag, state)
		return
	if _arrange_priority_marriage(world, country_tag, [ruler, heir], state):
		_save_state(world, country_tag, state)
		return
	if world.current_day >= 180 and _press_useful_claim(world, country_tag, state):
		_save_state(world, country_tag, state)
		return
	_record(state, world.current_day, "preserve_dynasty", "No valid marriage, commander, or claim action currently improves the succession position.")
	_save_state(world, country_tag, state)


func _assign_best_commander(world: CampaignWorldState, country_tag: String, state: Dictionary) -> bool:
	var candidates := CharacterSystemScript.valid_commanders(world, country_tag)
	if candidates.is_empty():
		return false
	for army_id in world.country_armies(country_tag):
		if not String(world.get_army(army_id).get("commander_id", "")).is_empty():
			continue
		for character_id in candidates:
			if String((world.character_registry[character_id] as Dictionary).get("commander_army_id", "")).is_empty():
				var command := AssignCommanderCommandScript.new(country_tag, army_id, character_id)
				if command.validate(world).is_empty():
					scheduler.submit(command)
					_record(state, world.current_day, "assign_commander", "Assigned the strongest available martial character to an uncommanded army.")
					return true
	return false


func _arrange_priority_marriage(world: CampaignWorldState, country_tag: String, priority_ids: Array, state: Dictionary) -> bool:
	for raw_priority in priority_ids:
		var character_id := String(raw_priority)
		if not world.character_registry.has(character_id):
			continue
		var character: Dictionary = world.character_registry[character_id]
		if _reserved_marriage_ids.has(character_id) or not String(character.get("spouse_id", "")).is_empty() or CharacterSystemScript.age_years(world, character_id) < CharacterSystemScript.ADULT_AGE:
			continue
		var candidates: Array[Dictionary] = []
		var ids := world.character_registry.keys()
		ids.sort()
		for raw_id in ids:
			var candidate_id := String(raw_id)
			if _reserved_marriage_ids.has(candidate_id):
				continue
			if not CharacterSystemScript.can_marry(world, character_id, candidate_id).is_empty():
				continue
			var candidate: Dictionary = world.character_registry[candidate_id]
			var score := 0
			if String(candidate.get("employer_country", "")) != country_tag:
				score += 20
			if String(candidate.get("religion", "")) == String(character.get("religion", "")):
				score += 15
			if String(candidate.get("culture", "")) == String(character.get("culture", "")):
				score += 5
			var skills: Dictionary = candidate.get("skills", {})
			score += int(skills.get("diplomacy", 0)) + int(skills.get("stewardship", 0))
			candidates.append({"character_id": candidate_id, "score": score})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["score"]) > int(b["score"]) if int(a["score"]) != int(b["score"]) else String(a["character_id"]) < String(b["character_id"]))
		if not candidates.is_empty():
			var selected := String(candidates[0]["character_id"])
			var command := ArrangeMarriageCommandScript.new(character_id, selected, country_tag)
			if command.validate(world).is_empty():
				scheduler.submit(command)
				_reserved_marriage_ids[character_id] = true
				_reserved_marriage_ids[selected] = true
				_record(state, world.current_day, "arrange_marriage", "Selected the highest-scoring valid dynastic marriage candidate.")
				return true
	return false


func _press_useful_claim(world: CampaignWorldState, country_tag: String, state: Dictionary) -> bool:
	if not DiplomacySystemScript.country_wars(world, country_tag).is_empty():
		return false
	var court := world.living_characters_in_country(country_tag)
	for character_id in court:
		for raw_claim_id in (world.character_registry[character_id] as Dictionary).get("claims", []):
			var claim_id := String(raw_claim_id)
			var claim: Dictionary = world.claim_registry.get(claim_id, {})
			if bool(claim.get("pressed", false)):
				continue
			var title: Dictionary = world.title_registry.get(String(claim.get("title_id", "")), {})
			var defender := String(title.get("country_tag", ""))
			if defender.is_empty() or defender == country_tag:
				continue
			var own_strength := _country_strength(world, country_tag)
			var enemy_strength := _country_strength(world, defender)
			if own_strength * 100 < enemy_strength * 115:
				continue
			var command := DeclareClaimWarCommandScript.new(country_tag, defender, claim_id)
			if command.validate(world).is_empty():
				scheduler.submit(command)
				_record(state, world.current_day, "press_claim", "Pressed a court claim after passing truce and relative-strength checks.")
				return true
	return false


func _country_strength(world: CampaignWorldState, country_tag: String) -> int:
	var result := 0
	for army_id in world.country_armies(country_tag):
		result += int(world.get_army(army_id).get("strength", 0))
	return result


func _record(state: Dictionary, day: int, action: String, reason: String) -> void:
	state["last_action"] = action
	state["last_reason"] = reason
	var history: Array = state.get("decisions", [])
	history.append({"day": day, "action": action, "reason": reason})
	while history.size() > 16:
		history.pop_front()
	state["decisions"] = history


func _save_state(world: CampaignWorldState, country_tag: String, state: Dictionary) -> void:
	var runtime := world.country_runtime(country_tag)
	runtime["character_ai"] = state
	world.set_country_runtime(country_tag, runtime)
	events.character_ai_decision.emit(country_tag, String(state.get("last_action", "")), String(state.get("last_reason", "")))
