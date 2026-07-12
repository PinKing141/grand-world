class_name AdvanceTechnologyCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
var country_tag := ""
var track := ""

func _init(p_country_tag: String, p_track: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag; track = p_track; issuer = p_country_tag; scheduled_day = p_scheduled_day
	description = "%s advances %s technology" % [country_tag, track]

func command_type() -> String: return "AdvanceTechnologyCommand"

func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or track not in CountryDepthDefinitions.TECHNOLOGY_TRACKS: return "The country or technology track is invalid."
	var definitions := CountryDepthDefinitionsScript.load_default()
	var cost := CountryDepthSystemScript.technology_cost(world, country_tag, track, definitions)
	if cost < 0: return "This technology track is already complete."
	if int((world.country_runtime(country_tag).get("technology_points", {}) as Dictionary).get(track, 0)) < cost: return "Insufficient %s technology points." % track
	return ""

func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.advance_technology(world, events, country_tag, track, CountryDepthDefinitionsScript.load_default())
