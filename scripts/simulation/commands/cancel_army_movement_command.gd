class_name CancelArmyMovementCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

var army_id := ""
var issuing_country := ""


func _init(p_army_id: String, p_issuing_country: String, p_issuer := "player", p_scheduled_day := -1) -> void:
	army_id = p_army_id
	issuing_country = p_issuing_country
	issuer = p_issuer
	scheduled_day = p_scheduled_day
	description = "Cancel movement of %s" % army_id


func command_type() -> String:
	return "CancelArmyMovementCommand"


func validate(world: CampaignWorldState) -> String:
	var army := world.get_army(army_id)
	if army.is_empty():
		return "The army no longer exists."
	if String(army.get("owner_country_id", "")) != issuing_country:
		return "%s does not control this army." % issuing_country
	if String(army.get("status", "")) != CampaignWorldState.ARMY_STATUS_MOVING:
		return "The army is not moving."
	if bool(army.get("movement_locked", false)):
		return "The army is movement-locked."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	# The army finishes nothing: it stays in its authoritative current
	# province and the rest of the route is discarded.
	var army := world.get_army(army_id)
	army["destination_province_id"] = -1
	army["remaining_path"] = []
	army["path_index"] = 0
	army["movement_start_day"] = -1
	army["next_arrival_day"] = -1
	army["movement_progress"] = 0.0
	army["status"] = CampaignWorldState.ARMY_STATUS_IDLE
	world.army_registry[army_id] = army
	events.army_movement_cancelled.emit(army_id)
