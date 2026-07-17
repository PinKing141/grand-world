class_name TransferShipsCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

var country_tag := ""
var ship_ids: Array = []
var target_fleet_id := ""


func _init(p_country_tag: String, p_ship_ids: Array, p_target_fleet_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	ship_ids = p_ship_ids.duplicate()
	target_fleet_id = p_target_fleet_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s transfers %d ship(s) to %s" % [country_tag, ship_ids.size(), target_fleet_id]


func command_type() -> String:
	return "TransferShipsCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country: %s" % country_tag
	if ship_ids.is_empty():
		return "A transfer needs at least one ship."
	if not FleetSystemScript.is_docked_and_organisable(world, target_fleet_id, country_tag):
		return "The target fleet is not docked and owned by %s." % country_tag
	var source_port := FleetSystemScript.shared_organisable_port(world, ship_ids, country_tag)
	if source_port < 0:
		return "The selected ships are not eligible to transfer."
	var target_port := int(world.get_fleet(target_fleet_id).get("location_id", -1))
	if source_port != target_port:
		return "The ships and the target fleet are not at the same port."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	FleetSystemScript.move_ships(world, ship_ids, target_fleet_id)
	events.fleet_ships_transferred.emit(target_fleet_id, ship_ids.size())
