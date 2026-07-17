class_name SplitFleetCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

var country_tag := ""
var source_fleet_id := ""
var ship_ids: Array = []


func _init(p_country_tag: String, p_source_fleet_id: String, p_ship_ids: Array, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	source_fleet_id = p_source_fleet_id
	ship_ids = p_ship_ids.duplicate()
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s splits %d ship(s) from %s" % [country_tag, ship_ids.size(), source_fleet_id]


func command_type() -> String:
	return "SplitFleetCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country: %s" % country_tag
	if ship_ids.is_empty():
		return "A split needs at least one ship."
	if not FleetSystemScript.is_docked_and_organisable(world, source_fleet_id, country_tag):
		return "The source fleet is not docked and owned by %s." % country_tag
	var source_members: Array = world.get_fleet(source_fleet_id).get("ship_ids", [])
	for raw_ship_id in ship_ids:
		if not source_members.has(String(raw_ship_id)):
			return "Ship %s does not belong to %s." % [String(raw_ship_id), source_fleet_id]
	if FleetSystemScript.shared_organisable_port(world, ship_ids, country_tag) < 0:
		return "The selected ships are not eligible to split."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var port_id := int(world.get_fleet(source_fleet_id).get("location_id", -1))
	var fleet_id := "f_%d" % world.take_counter("next_fleet_id")
	world.fleet_registry[fleet_id] = CampaignWorldState.make_fleet_record(fleet_id, country_tag, port_id)
	FleetSystemScript.move_ships(world, ship_ids, fleet_id)
	events.fleet_created.emit(fleet_id, country_tag, port_id)
