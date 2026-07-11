class_name ImproveRelationsCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

var country_tag := ""
var target_tag := ""


func _init(p_country: String, p_target: String, p_scheduled_day := -1) -> void:
	country_tag = p_country
	target_tag = p_target
	issuer = p_country
	scheduled_day = p_scheduled_day
	description = "Improve relations with %s" % target_tag


func command_type() -> String:
	return "ImproveRelationsCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or not world.has_country(target_tag) or country_tag == target_tag:
		return "Select two different existing countries."
	if DiplomacySystemScript.are_at_war(world, country_tag, target_tag):
		return "Relations cannot be improved while the countries are at war."
	if DiplomacySystemScript.opinion(world, country_tag, target_tag) >= 200:
		return "Relations are already at their maximum."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var opinion := DiplomacySystemScript.improve_relations(world, country_tag, target_tag)
	events.relations_changed.emit(country_tag, target_tag, opinion)
