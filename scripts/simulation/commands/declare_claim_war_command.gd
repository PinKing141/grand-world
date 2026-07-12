class_name DeclareClaimWarCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

var attacker_tag := ""
var defender_tag := ""
var claim_id := ""


func _init(p_attacker: String, p_defender: String, p_claim_id: String, p_scheduled_day := -1) -> void:
	attacker_tag = p_attacker
	defender_tag = p_defender
	claim_id = p_claim_id
	issuer = p_attacker
	scheduled_day = p_scheduled_day
	description = "%s presses %s against %s" % [attacker_tag, claim_id, defender_tag]


func command_type() -> String:
	return "DeclareClaimWarCommand"


func validate(world: CampaignWorldState) -> String:
	if attacker_tag == defender_tag or not world.has_country(attacker_tag) or not world.has_country(defender_tag):
		return "A claim war requires two different existing countries."
	if not DiplomacySystemScript.overlord_of(world, attacker_tag).is_empty():
		return "Subjects cannot declare independent wars."
	if not DiplomacySystemScript.overlord_of(world, defender_tag).is_empty():
		return "Declare war on the subject's overlord instead."
	if not world.claim_registry.has(claim_id):
		return "The selected claim does not exist."
	var claim: Dictionary = world.claim_registry[claim_id]
	var claimant_id := String(claim.get("claimant_id", ""))
	var title_id := String(claim.get("title_id", ""))
	if not world.character_registry.has(claimant_id) or not bool((world.character_registry[claimant_id] as Dictionary).get("alive", false)):
		return "The claimant is not alive."
	if String((world.character_registry[claimant_id] as Dictionary).get("employer_country", "")) != attacker_tag:
		return "The claimant is not part of the attacking court."
	if not world.title_registry.has(title_id) or String((world.title_registry[title_id] as Dictionary).get("country_tag", "")) != defender_tag:
		return "The claim does not target the defending country's title."
	if not DiplomacySystemScript.active_war_between(world, attacker_tag, defender_tag).is_empty():
		return "These countries are already at war."
	if DiplomacySystemScript.has_active_truce(world, attacker_tag, defender_tag):
		return "A truce blocks this claim war."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var claim: Dictionary = world.claim_registry[claim_id]
	var title_id := String(claim["title_id"])
	var title: Dictionary = world.title_registry[title_id]
	var target_province := int(title.get("capital_province_id", -1))
	var relationship := DiplomacySystemScript.relation(world, attacker_tag, defender_tag)
	relationship["alliance"] = false
	DiplomacySystemScript.set_relation(world, attacker_tag, defender_tag, relationship)
	var war_id := "war_%06d" % world.take_counter("next_war_id")
	var attackers: Array[String] = [attacker_tag]
	var defenders: Array[String] = [defender_tag]
	for subject in DiplomacySystemScript.direct_subjects(world, attacker_tag):
		attackers.append(subject)
	for subject in DiplomacySystemScript.direct_subjects(world, defender_tag):
		defenders.append(subject)
	world.war_registry[war_id] = {
		"war_id": war_id, "name": "%s claim on %s" % [attacker_tag, title_id], "status": "active",
		"start_day": world.current_day, "attacker_leader": attacker_tag, "defender_leader": defender_tag,
		"attackers": attackers, "defenders": defenders,
		"war_goal": {"type": "press_claim", "province_id": target_province, "target_country": defender_tag, "claim_id": claim_id, "title_id": title_id, "claimant_id": String(claim["claimant_id"])},
		"battles": {}, "sieges": {}, "occupied_provinces": {}, "peace_offers": {},
		"battle_score_attacker": 0, "occupation_score_attacker": 0, "ticking_score_attacker": 0,
		"total_war_score": 0, "history": [{"day": world.current_day, "type": "claim_war_declared", "actor": attacker_tag, "claim_id": claim_id}],
	}
	events.war_declared.emit(war_id, attacker_tag, defender_tag, target_province)
