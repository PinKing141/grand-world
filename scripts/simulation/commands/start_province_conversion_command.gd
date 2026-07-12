class_name StartProvinceConversionCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
var country_tag := ""
var province_id := -1
var conversion_type := "religion"
var target := ""

func _init(p_country_tag: String, p_province_id: int, p_type: String, p_target: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag; province_id = p_province_id; conversion_type = p_type; target = p_target; issuer = p_country_tag; scheduled_day = p_scheduled_day
	description = "%s begins %s conversion in province %d" % [country_tag, conversion_type, province_id]

func command_type() -> String: return "StartProvinceConversionCommand"

func validate(world: CampaignWorldState) -> String:
	if not world.has_province(province_id) or world.get_province_owner(province_id) != country_tag: return "Conversion requires an owned province."
	if conversion_type not in ["culture", "religion"]: return "The conversion type is invalid."
	var definitions := CountryDepthDefinitionsScript.load_default()
	if conversion_type == "culture" and not definitions.cultures().has(target): return "The target culture does not exist."
	if conversion_type == "religion" and not definitions.religions().has(target): return "The target religion does not exist."
	var economy: Dictionary = world.province_states[province_id].get("economy", {})
	if not (economy.get("conversion", {}) as Dictionary).is_empty(): return "A conversion is already active."
	if String(economy.get(conversion_type, "")) == target: return "The province already has the target %s." % conversion_type
	return ""

func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.start_conversion(world, events, country_tag, province_id, conversion_type, target)
