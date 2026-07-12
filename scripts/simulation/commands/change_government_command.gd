class_name ChangeGovernmentCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")

var country_tag := ""
var government_id := ""


func _init(p_country_tag: String, p_government_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	government_id = p_government_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s changes government to %s" % [country_tag, government_id]


func command_type() -> String:
	return "ChangeGovernmentCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "The country does not exist."
	var runtime := world.country_runtime(country_tag)
	if CountryDepthDefinitionsScript.load_default().government(government_id).is_empty():
		return "The government type does not exist."
	if String(runtime.get("government_id", "")) == government_id:
		return "This government is already active."
	if int((runtime.get("technology", {}) as Dictionary).get("administrative", 0)) < 3:
		return "Administrative technology 3 is required."
	if int(runtime.get("authority_bp", 0)) < 2000 or int(runtime.get("treasury", 0)) < 100000:
		return "Changing government requires 20% authority and 100.00."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.change_government(world, events, country_tag, government_id, CountryDepthDefinitionsScript.load_default())
