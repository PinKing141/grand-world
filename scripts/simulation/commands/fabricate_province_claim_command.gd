class_name FabricateProvinceClaimCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
var country_tag := ""
var province_id := -1

func _init(p_country_tag: String, p_province_id: int, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag; province_id = p_province_id; issuer = p_country_tag; scheduled_day = p_scheduled_day
	description = "%s fabricates a claim on province %d" % [country_tag, province_id]

func command_type() -> String: return "FabricateProvinceClaimCommand"

func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or not world.has_province(province_id): return "The country or province is invalid."
	if world.get_province_owner(province_id) == country_tag or world.get_province_owner(province_id).is_empty(): return "Claims require a foreign owned province."
	if CountryDepthSystemScript.has_valid_claim_or_core(world, country_tag, province_id): return "A valid claim or core already exists."
	if int((world.country_runtime(country_tag).get("technology_points", {}) as Dictionary).get("diplomatic", 0)) < 100: return "Fabricating a claim costs 100 diplomatic points."
	return ""

func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.fabricate_claim(world, events, country_tag, province_id)
