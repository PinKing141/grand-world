class_name SelectIdeaGroupCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
var country_tag := ""
var idea_id := ""

func _init(p_country_tag: String, p_idea_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag; idea_id = p_idea_id; issuer = p_country_tag; scheduled_day = p_scheduled_day
	description = "%s selects idea group %s" % [country_tag, idea_id]

func command_type() -> String: return "SelectIdeaGroupCommand"

func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or CountryDepthDefinitionsScript.load_default().idea_group(idea_id).is_empty(): return "The country or idea group is invalid."
	if not String(world.country_runtime(country_tag).get("idea_group_id", "")).is_empty(): return "A national direction is already selected."
	return ""

func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.select_idea_group(world, events, country_tag, idea_id, CountryDepthDefinitionsScript.load_default())
