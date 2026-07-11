class_name DisbandArmyCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")

var country_tag := ""
var army_id := ""


func _init(p_country_tag: String, p_army_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	army_id = p_army_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Disband army %s" % army_id


func command_type() -> String:
	return "DisbandArmyCommand"


func validate(world: CampaignWorldState) -> String:
	var army := world.get_army(army_id)
	if army.is_empty():
		return "Unknown army."
	if String(army.get("owner_country_id", "")) != country_tag:
		return "This country does not control the army."
	if String(army.get("status", "idle")) == CampaignWorldState.ARMY_STATUS_MOVING:
		return "Stop the army before disbanding it."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var army := world.get_army(army_id)
	var runtime := world.country_runtime(country_tag)
	var returned := int(army.get("strength", 0)) / 4
	runtime["manpower"] = mini(int(runtime.get("maximum_manpower", 0)), int(runtime.get("manpower", 0)) + returned)
	world.set_country_runtime(country_tag, runtime)
	world.army_registry.erase(army_id)
	EconomySystemScript.recalculate_country(world, country_tag)
	events.army_disbanded.emit(army_id)
