class_name MergeFleetsCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

var country_tag := ""
var fleet_ids: Array = []


func _init(p_country_tag: String, p_fleet_ids: Array, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	fleet_ids = p_fleet_ids.duplicate()
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s merges %d fleets" % [country_tag, fleet_ids.size()]


func _sorted_fleet_ids() -> Array:
	var result: Array = fleet_ids.duplicate()
	result.sort()
	return result


func command_type() -> String:
	return "MergeFleetsCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country: %s" % country_tag
	if fleet_ids.size() < 2:
		return "Merging requires at least two fleets."
	var seen := {}
	var shared_port := -1
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		if seen.has(fleet_id):
			return "Fleet %s was named more than once." % fleet_id
		seen[fleet_id] = true
		if not FleetSystemScript.is_docked_and_organisable(world, fleet_id, country_tag):
			return "Fleet %s is not docked and owned by %s." % [fleet_id, country_tag]
		var port_id := int(world.get_fleet(fleet_id).get("location_id", -1))
		if shared_port < 0:
			shared_port = port_id
		elif shared_port != port_id:
			return "Fleets must be docked at the same port to merge."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var ordered := _sorted_fleet_ids()
	var target_fleet_id := String(ordered[0])
	for index in range(1, ordered.size()):
		var source_fleet_id := String(ordered[index])
		var members := world.fleet_ships(source_fleet_id)
		FleetSystemScript.move_ships(world, members, target_fleet_id)
	events.fleets_merged.emit(target_fleet_id, ordered)
