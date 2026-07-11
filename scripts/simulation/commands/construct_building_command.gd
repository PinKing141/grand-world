class_name ConstructBuildingCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")

var country_tag := ""
var province_id := -1
var building_id := ""


func _init(p_country_tag: String, p_province_id: int, p_building_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	province_id = p_province_id
	building_id = p_building_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Construct %s in province %d" % [building_id, province_id]


func command_type() -> String:
	return "ConstructBuildingCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country: %s" % country_tag
	if not world.has_province(province_id):
		return "Unknown province ID: %d" % province_id
	if world.get_province_owner(province_id) != country_tag:
		return "The country does not own this province."
	var definition: Dictionary = EconomyDefinitionsScript.load_default().building(building_id)
	if definition.is_empty():
		return "Unknown building: %s" % building_id
	var economy: Dictionary = world.province_states[province_id].get("economy", {})
	if not bool(economy.get("economic_eligible", false)):
		return "This province cannot support economic buildings."
	var buildings: Array = economy.get("buildings", [])
	if buildings.has(building_id):
		return "This building is already present."
	var active := 0
	for raw_id in world.construction_registry:
		var record: Dictionary = world.construction_registry[raw_id]
		if int(record.get("province_id", -1)) == province_id:
			active += 1
			if String(record.get("building_id", "")) == building_id:
				return "This building is already under construction."
	if buildings.size() + active >= int(economy.get("building_slots", 0)):
		return "No building slots are available."
	if int(world.country_runtime(country_tag).get("treasury", 0)) < int(definition.get("cost", 0)):
		return "Insufficient treasury."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var definition: Dictionary = EconomyDefinitionsScript.load_default().building(building_id)
	var runtime := world.country_runtime(country_tag)
	runtime["treasury"] = int(runtime.get("treasury", 0)) - int(definition["cost"])
	world.set_country_runtime(country_tag, runtime)
	var construction_id := "construction_%d" % world.take_counter("next_construction_id")
	world.construction_registry[construction_id] = {
		"construction_id": construction_id,
		"country_tag": country_tag,
		"province_id": province_id,
		"building_id": building_id,
		"cost": int(definition["cost"]),
		"start_day": world.current_day,
		"completion_day": world.current_day + int(definition["construction_days"]),
	}
	EconomySystemScript.recalculate_country(world, country_tag)
	events.building_started.emit(construction_id, province_id, building_id)
