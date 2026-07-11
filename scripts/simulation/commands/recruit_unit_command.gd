class_name RecruitUnitCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")

var country_tag := ""
var province_id := -1
var unit_id := "infantry_regiment"


func _init(p_country_tag: String, p_province_id: int, p_unit_id := "infantry_regiment", p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	province_id = p_province_id
	unit_id = p_unit_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Recruit %s in province %d" % [unit_id, province_id]


func command_type() -> String:
	return "RecruitUnitCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag) or not world.has_province(province_id):
		return "Unknown country or province."
	if world.get_province_owner(province_id) != country_tag or world.get_province_controller(province_id) != country_tag:
		return "Recruitment requires an owned and controlled province."
	var definition: Dictionary = EconomyDefinitionsScript.load_default().unit(unit_id)
	if definition.is_empty():
		return "Unknown unit: %s" % unit_id
	var economy: Dictionary = world.province_states[province_id].get("economy", {})
	if not bool(economy.get("economic_eligible", false)):
		return "This province cannot recruit land units."
	var runtime := world.country_runtime(country_tag)
	if int(runtime.get("treasury", 0)) < int(definition.get("cost", 0)):
		return "Insufficient treasury."
	if int(runtime.get("manpower", 0)) < int(definition.get("manpower_cost", 0)):
		return "Insufficient manpower."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var definition: Dictionary = EconomyDefinitionsScript.load_default().unit(unit_id)
	var runtime := world.country_runtime(country_tag)
	runtime["treasury"] = int(runtime.get("treasury", 0)) - int(definition["cost"])
	runtime["manpower"] = int(runtime.get("manpower", 0)) - int(definition["manpower_cost"])
	world.set_country_runtime(country_tag, runtime)
	var recruitment_id := "recruitment_%d" % world.take_counter("next_recruitment_id")
	world.recruitment_registry[recruitment_id] = {
		"recruitment_id": recruitment_id,
		"country_tag": country_tag,
		"province_id": province_id,
		"unit_id": unit_id,
		"start_day": world.current_day,
		"completion_day": world.current_day + int(definition["recruitment_days"]),
	}
	events.recruitment_started.emit(recruitment_id, province_id, unit_id)
