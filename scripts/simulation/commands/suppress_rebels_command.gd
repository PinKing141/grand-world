class_name SuppressRebelsCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")

var country_tag := ""
var faction_id := ""


func _init(p_country_tag: String, p_faction_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	faction_id = p_faction_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s suppresses rebel faction %s" % [country_tag, faction_id]


func command_type() -> String:
	return "SuppressRebelsCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "The country does not exist."
	if not world.rebel_faction_registry.has(faction_id):
		return "The rebel faction does not exist."
	var faction: Dictionary = world.rebel_faction_registry[faction_id]
	if String(faction.get("country_tag", "")) != country_tag:
		return "The rebel faction does not belong to this country."
	if int(world.country_runtime(country_tag).get("manpower", 0)) < 1000:
		return "Suppressing rebels requires 1,000 manpower."
	if int(world.country_runtime(country_tag).get("treasury", 0)) < 25000:
		return "Suppressing rebels costs 25.00."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.suppress_rebels(world, events, country_tag, faction_id)
