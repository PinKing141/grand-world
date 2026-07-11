class_name SetArmyMaintenanceCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")

var country_tag := ""
var maintenance_bp := 10000


func _init(p_country_tag: String, p_maintenance_bp: int, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	maintenance_bp = p_maintenance_bp
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Set army maintenance to %d%%" % (maintenance_bp / 100)


func command_type() -> String:
	return "SetArmyMaintenanceCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country."
	if maintenance_bp not in [2500, 5000, 7500, 10000]:
		return "Maintenance must be 25%, 50%, 75%, or 100%."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var runtime := world.country_runtime(country_tag)
	runtime["army_maintenance_bp"] = maintenance_bp
	world.set_country_runtime(country_tag, runtime)
	EconomySystemScript.recalculate_country(world, country_tag)
	events.maintenance_changed.emit(country_tag, maintenance_bp)
