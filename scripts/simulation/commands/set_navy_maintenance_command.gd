class_name SetNavyMaintenanceCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

## FL3.2 closure: the naval mirror of SetArmyMaintenanceCommand, closing
## the "respect... maintenance..." bullet's own remaining gap. Reuses the
## already-fully-wired country_runtime "navy_maintenance_bp" field
## (economy_system.gd already scales the navy_maintenance ledger line by
## it - the economic connection was never missing) - only the command to
## actually change it was.

const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")

var country_tag := ""
var maintenance_bp := 10000


func _init(p_country_tag: String, p_maintenance_bp: int, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	maintenance_bp = p_maintenance_bp
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Set navy maintenance to %d%%" % (maintenance_bp / 100)


func command_type() -> String:
	return "SetNavyMaintenanceCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country."
	if maintenance_bp not in [2500, 5000, 7500, 10000]:
		return "Maintenance must be 25%, 50%, 75%, or 100%."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var runtime := world.country_runtime(country_tag)
	runtime["navy_maintenance_bp"] = maintenance_bp
	world.set_country_runtime(country_tag, runtime)
	EconomySystemScript.recalculate_country(world, country_tag)
	events.navy_maintenance_changed.emit(country_tag, maintenance_bp)
