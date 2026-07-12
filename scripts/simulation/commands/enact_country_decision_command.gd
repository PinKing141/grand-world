class_name EnactCountryDecisionCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")

var country_tag := ""
var decision_id := ""


func _init(p_country_tag: String, p_decision_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	decision_id = p_decision_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s enacts decision %s" % [country_tag, decision_id]


func command_type() -> String:
	return "EnactCountryDecisionCommand"


func validate(world: CampaignWorldState) -> String:
	return CountryDepthSystemScript.decision_validation(world, country_tag, decision_id, CountryDepthDefinitionsScript.load_default())


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.enact_decision(world, events, country_tag, decision_id, CountryDepthDefinitionsScript.load_default())
