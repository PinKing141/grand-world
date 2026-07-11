class_name DeclareWarCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

var attacker_tag := ""
var defender_tag := ""
var target_province_id := -1


func _init(p_attacker: String, p_defender: String, p_target_province: int, p_scheduled_day := -1) -> void:
	attacker_tag = p_attacker
	defender_tag = p_defender
	target_province_id = p_target_province
	issuer = p_attacker
	scheduled_day = p_scheduled_day
	description = "%s declares a conquest war on %s for province %d" % [attacker_tag, defender_tag, target_province_id]


func command_type() -> String:
	return "DeclareWarCommand"


func validate(world: CampaignWorldState) -> String:
	if attacker_tag == defender_tag or not world.has_country(attacker_tag) or not world.has_country(defender_tag):
		return "A war requires two different existing countries."
	if not world.has_province(target_province_id):
		return "The selected war-goal province does not exist."
	if world.get_province_owner(target_province_id) != defender_tag:
		return "%s no longer owns the selected war-goal province." % defender_tag
	if not DiplomacySystemScript.active_war_between(world, attacker_tag, defender_tag).is_empty():
		return "These countries are already at war."
	if DiplomacySystemScript.has_active_truce(world, attacker_tag, defender_tag):
		var end_day := int(DiplomacySystemScript.relation(world, attacker_tag, defender_tag)["truce_until_day"])
		return "A truce blocks war until campaign day %d." % end_day
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var relationship := DiplomacySystemScript.relation(world, attacker_tag, defender_tag)
	relationship["alliance"] = false
	DiplomacySystemScript.set_relation(world, attacker_tag, defender_tag, relationship)
	var war_id := "war_%06d" % world.take_counter("next_war_id")
	var attackers := [attacker_tag]
	var defenders := [defender_tag]
	for ally in _allies_of(world, attacker_tag):
		if ally != defender_tag and not DiplomacySystemScript.are_allied(world, ally, defender_tag):
			attackers.append(ally)
	for ally in _allies_of(world, defender_tag):
		if ally != attacker_tag and not attackers.has(ally):
			defenders.append(ally)
	attackers.sort()
	defenders.sort()
	world.war_registry[war_id] = {
		"war_id": war_id,
		"name": "%s conquest of province %d" % [attacker_tag, target_province_id],
		"status": "active",
		"start_day": world.current_day,
		"attacker_leader": attacker_tag,
		"defender_leader": defender_tag,
		"attackers": attackers,
		"defenders": defenders,
		"war_goal": {
			"type": "conquer_province",
			"province_id": target_province_id,
			"target_country": defender_tag,
		},
		"battles": {},
		"sieges": {},
		"occupied_provinces": {},
		"peace_offers": {},
		"battle_score_attacker": 0,
		"occupation_score_attacker": 0,
		"ticking_score_attacker": 0,
		"total_war_score": 0,
		"history": [{"day": world.current_day, "type": "war_declared", "actor": attacker_tag}],
	}
	events.war_declared.emit(war_id, attacker_tag, defender_tag, target_province_id)


func _allies_of(world: CampaignWorldState, country_tag: String) -> Array[String]:
	var allies: Array[String] = []
	var tags := world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		if tag != country_tag and DiplomacySystemScript.are_allied(world, country_tag, tag):
			allies.append(tag)
	return allies
