class_name FormAllianceCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

var country_tag := ""
var target_tag := ""


func _init(p_country: String, p_target: String, p_scheduled_day := -1) -> void:
	country_tag = p_country
	target_tag = p_target
	issuer = p_country
	scheduled_day = p_scheduled_day
	description = "Form alliance with %s" % target_tag


func command_type() -> String:
	return "FormAllianceCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or not world.has_country(target_tag) or country_tag == target_tag:
		return "Select two different existing countries."
	if DiplomacySystemScript.are_at_war(world, country_tag, target_tag):
		return "Countries at war cannot form an alliance."
	if DiplomacySystemScript.are_allied(world, country_tag, target_tag):
		return "These countries are already allied."
	if DiplomacySystemScript.opinion(world, country_tag, target_tag) < 25:
		return "Opinion must be at least +25 to form an alliance."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var record := DiplomacySystemScript.relation(world, country_tag, target_tag)
	record["alliance"] = true
	DiplomacySystemScript.set_relation(world, country_tag, target_tag, record)
	events.alliance_changed.emit(country_tag, target_tag, true)
