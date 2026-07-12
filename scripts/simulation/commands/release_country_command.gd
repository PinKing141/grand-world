class_name ReleaseCountryCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")

var releasing_tag := ""
var released_tag := ""
var province_ids: Array[int] = []


func _init(p_releasing_tag: String, p_released_tag: String, p_province_ids: Array, p_scheduled_day := -1) -> void:
	releasing_tag = p_releasing_tag
	released_tag = p_released_tag
	for raw_id in p_province_ids:
		province_ids.append(int(raw_id))
	province_ids.sort()
	issuer = p_releasing_tag
	scheduled_day = p_scheduled_day
	description = "%s releases %s" % [releasing_tag, released_tag]


func command_type() -> String:
	return "ReleaseCountryCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(releasing_tag) or not world.has_country(released_tag) or releasing_tag == released_tag:
		return "Release requires two different existing countries."
	if not world.get_country_provinces(released_tag).is_empty():
		return "The released country is already active."
	if province_ids.is_empty():
		return "At least one province must be released."
	for province_id in province_ids:
		if world.get_province_owner(province_id) != releasing_tag:
			return "Every released province must be owned by the releasing country."
		if not (world.province_states[province_id].get("economy", {}).get("cores", []) as Array).has(released_tag):
			return "Every released province must be a core of the released country."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	CountryDepthSystemScript.release_country(world, events, releasing_tag, released_tag, province_ids, CountryDepthDefinitionsScript.load_default())
