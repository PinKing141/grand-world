class_name ChooseCountryEventOptionCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")

var country_tag := ""
var event_instance_id := ""
var option_id := ""


func _init(p_country_tag: String, p_event_instance_id: String, p_option_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	event_instance_id = p_event_instance_id
	option_id = p_option_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s chooses %s for event %s" % [country_tag, option_id, event_instance_id]


func command_type() -> String:
	return "ChooseCountryEventOptionCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.country_event_registry.has(event_instance_id):
		return "The event does not exist."
	var instance: Dictionary = world.country_event_registry[event_instance_id]
	if String(instance.get("country_tag", "")) != country_tag or String(instance.get("status", "")) != "pending":
		return "The event is not pending for this country."
	var definition := CountryDepthDefinitionsScript.load_default().event(String(instance.get("definition_id", "")))
	for raw_option in definition.get("options", []):
		if String((raw_option as Dictionary).get("id", "")) == option_id:
			return ""
	return "The selected event option does not exist."


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.choose_event_option(world, events, event_instance_id, option_id, CountryDepthDefinitionsScript.load_default())
