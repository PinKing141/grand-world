class_name BreakAllianceCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

var country_tag := ""
var target_tag := ""


func _init(p_country: String, p_target: String, p_scheduled_day := -1) -> void:
	country_tag = p_country
	target_tag = p_target
	issuer = p_country
	scheduled_day = p_scheduled_day
	description = "Break alliance with %s" % target_tag


func command_type() -> String:
	return "BreakAllianceCommand"


func validate(world: CampaignWorldState) -> String:
	if not DiplomacySystemScript.are_allied(world, country_tag, target_tag):
		return "These countries are not allied."
	if DiplomacySystemScript.are_at_war(world, country_tag, target_tag):
		return "An alliance cannot be broken between opposing war participants."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var record := DiplomacySystemScript.relation(world, country_tag, target_tag)
	record["alliance"] = false
	DiplomacySystemScript.set_relation(world, country_tag, target_tag, record)
	DiplomacySystemScript.improve_relations(world, country_tag, target_tag, -50)
	events.alliance_changed.emit(country_tag, target_tag, false)
