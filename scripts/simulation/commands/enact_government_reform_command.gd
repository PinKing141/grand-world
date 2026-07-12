class_name EnactGovernmentReformCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
var country_tag := ""
var reform_id := ""

func _init(p_country_tag: String, p_reform_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag; reform_id = p_reform_id; issuer = p_country_tag; scheduled_day = p_scheduled_day
	description = "%s enacts government reform %s" % [country_tag, reform_id]

func command_type() -> String: return "EnactGovernmentReformCommand"

func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag): return "The country does not exist."
	var definitions := CountryDepthDefinitionsScript.load_default()
	var reform := definitions.reform(reform_id)
	var runtime := world.country_runtime(country_tag)
	if reform.is_empty(): return "The reform does not exist."
	if not (definitions.government(String(runtime.get("government_id", ""))).get("reforms", []) as Array).has(reform_id): return "This government cannot enact that reform."
	if (runtime.get("government_reforms", []) as Array).has(reform_id): return "That reform is already active."
	if int((runtime.get("technology", {}) as Dictionary).get("administrative", 0)) < int(reform.get("required_admin_tech", 0)): return "Administrative technology is too low."
	if int(runtime.get("authority_bp", 0)) < int(reform.get("authority_cost_bp", 0)): return "Government authority is too low."
	if int(runtime.get("treasury", 0)) < int(reform.get("treasury_cost", 0)): return "The treasury is too low."
	return ""

func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.enact_reform(world, events, country_tag, reform_id, CountryDepthDefinitionsScript.load_default())
