class_name CancelShipConstructionCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")

var country_tag := ""
var construction_id := ""


func _init(p_country_tag: String, p_construction_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	construction_id = p_construction_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Cancel naval construction %s" % construction_id


func command_type() -> String:
	return "CancelShipConstructionCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.naval_construction_registry.has(construction_id):
		return "Unknown naval construction project."
	if String(world.naval_construction_registry[construction_id].get("country_tag", "")) != country_tag:
		return "This country does not control this naval construction project."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var record: Dictionary = world.naval_construction_registry[construction_id]
	var ship_definitions := ShipDefinitionsScript.load_default()
	var definition := ship_definitions.ship(String(record["definition_id"]))
	var refund := int(record.get("amount_paid", 0)) * int(definition.get("refund_bp", 5000)) / 10000
	var runtime := world.country_runtime(country_tag)
	runtime["treasury"] = int(runtime.get("treasury", 0)) + refund
	runtime["sailors"] = int(runtime.get("sailors", 0)) + int(record.get("reserved_sailors", 0))
	world.set_country_runtime(country_tag, runtime)
	world.naval_construction_registry.erase(construction_id)
	EconomySystemScript.recalculate_country(world, country_tag)
	events.naval_construction_cancelled.emit(construction_id, int(record["port_id"]), refund)
