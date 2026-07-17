class_name CancelFleetMovementCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")

var fleet_id := ""
var issuing_country := ""


func _init(p_fleet_id: String, p_issuing_country: String, p_issuer := "player", p_scheduled_day := -1) -> void:
	fleet_id = p_fleet_id
	issuing_country = p_issuing_country
	issuer = p_issuer
	scheduled_day = p_scheduled_day
	description = "Cancel movement of %s" % fleet_id


func command_type() -> String:
	return "CancelFleetMovementCommand"


func validate(world: CampaignWorldState) -> String:
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return "The fleet no longer exists."
	if String(fleet.get("owner_country_id", "")) != issuing_country:
		return "%s does not control this fleet." % issuing_country
	if String(fleet.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_MOVING:
		return "The fleet is not moving."
	if bool(fleet.get("movement_locked", false)):
		return "The fleet is movement-locked."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	# The fleet finishes nothing: it stays at its authoritative current
	# location (a sea zone, since it was mid-route) and the rest of the
	# route is discarded.
	var graph := MaritimeGraphScript.load_default()
	var fleet := world.get_fleet(fleet_id)
	var current := int(fleet.get("location_id", -1))
	fleet["destination_id"] = -1
	fleet["remaining_path"] = []
	fleet["path_index"] = 0
	fleet["movement_start_day"] = -1
	fleet["next_arrival_day"] = -1
	fleet["movement_progress"] = 0.0
	fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_DOCKED if graph.is_port_province(current) else CampaignWorldState.FLEET_LOCATION_AT_SEA
	world.fleet_registry[fleet_id] = fleet
	events.fleet_movement_cancelled.emit(fleet_id)
