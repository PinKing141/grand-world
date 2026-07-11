class_name CancelConstructionCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")

var country_tag := ""
var construction_id := ""


func _init(p_country_tag: String, p_construction_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	construction_id = p_construction_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Cancel construction %s" % construction_id


func command_type() -> String:
	return "CancelConstructionCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.construction_registry.has(construction_id):
		return "Unknown construction project."
	if String(world.construction_registry[construction_id].get("country_tag", "")) != country_tag:
		return "This country does not control the construction project."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var record: Dictionary = world.construction_registry[construction_id]
	var definition: Dictionary = EconomyDefinitionsScript.load_default().building(String(record["building_id"]))
	var refund := int(record.get("cost", 0)) * int(definition.get("refund_bp", 5000)) / 10000
	var runtime := world.country_runtime(country_tag)
	runtime["treasury"] = int(runtime.get("treasury", 0)) + refund
	world.set_country_runtime(country_tag, runtime)
	world.construction_registry.erase(construction_id)
	EconomySystemScript.recalculate_country(world, country_tag)
	events.building_cancelled.emit(construction_id, int(record["province_id"]), refund)
