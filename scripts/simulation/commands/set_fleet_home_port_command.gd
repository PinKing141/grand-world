class_name SetFleetHomePortCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")

var country_tag := ""
var fleet_id := ""
var new_home_port_id := -1


func _init(p_country_tag: String, p_fleet_id: String, p_new_home_port_id: int, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	fleet_id = p_fleet_id
	new_home_port_id = p_new_home_port_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s sets %s's home port to %d" % [country_tag, fleet_id, new_home_port_id]


func command_type() -> String:
	return "SetFleetHomePortCommand"


func validate(world: CampaignWorldState) -> String:
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return "Unknown fleet: %s" % fleet_id
	if String(fleet.get("owner_country_id", "")) != country_tag:
		return "%s does not own %s." % [country_tag, fleet_id]
	var graph := MaritimeGraphScript.load_default()
	if not NavalAccessPolicyScript.can_base(graph, world, country_tag, new_home_port_id):
		return NavalAccessPolicyScript.dock_failure_reason(graph, world, country_tag, new_home_port_id)
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var fleet := world.get_fleet(fleet_id)
	fleet["home_port_id"] = new_home_port_id
	world.fleet_registry[fleet_id] = fleet
	events.fleet_home_port_changed.emit(fleet_id, new_home_port_id)
