class_name CreateFleetCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

var country_tag := ""
var ship_ids: Array = []


func _init(p_country_tag: String, p_ship_ids: Array, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	ship_ids = p_ship_ids.duplicate()
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s creates a fleet from %d ship(s)" % [country_tag, ship_ids.size()]


func command_type() -> String:
	return "CreateFleetCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country: %s" % country_tag
	if ship_ids.is_empty():
		return "A new fleet needs at least one ship."
	if FleetSystemScript.shared_organisable_port(world, ship_ids, country_tag) < 0:
		return "Those ships are not all docked, owned by %s, and at the same port." % country_tag
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var port_id := FleetSystemScript.shared_organisable_port(world, ship_ids, country_tag)
	var fleet_id := "f_%d" % world.take_counter("next_fleet_id")
	world.fleet_registry[fleet_id] = CampaignWorldState.make_fleet_record(fleet_id, country_tag, port_id)
	FleetSystemScript.move_ships(world, ship_ids, fleet_id)
	events.fleet_created.emit(fleet_id, country_tag, port_id)
