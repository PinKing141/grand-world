class_name MoveFleetCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

var fleet_id := ""
var destination_id := -1
var issuing_country := ""


func _init(p_fleet_id: String, p_destination_id: int, p_issuing_country: String, p_issuer := "player", p_scheduled_day := -1) -> void:
	fleet_id = p_fleet_id
	destination_id = p_destination_id
	issuing_country = p_issuing_country
	issuer = p_issuer
	scheduled_day = p_scheduled_day
	description = "Move %s to %d" % [fleet_id, destination_id]


func command_type() -> String:
	return "MoveFleetCommand"


func validate(world: CampaignWorldState) -> String:
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return "The fleet no longer exists."
	if String(fleet.get("owner_country_id", "")) != issuing_country:
		return "%s does not control this fleet." % issuing_country
	if bool(fleet.get("movement_locked", false)):
		return "The fleet is movement-locked."
	if not (fleet.get("transport_operation_ids", []) as Array).is_empty():
		return "The fleet is carrying a transport operation and cannot receive independent orders."
	if String(fleet.get("location_status", "")) in [CampaignWorldState.FLEET_LOCATION_BATTLE, CampaignWorldState.FLEET_LOCATION_RETREATING]:
		return "The fleet cannot receive orders in its current state."
	var current := int(fleet.get("location_id", -1))
	if destination_id == current:
		return "The fleet is already there."
	var graph := MaritimeGraphScript.load_default()
	var route := NavalAccessPolicyScript.find_legal_route(graph, world, issuing_country, current, destination_id)
	if not bool(route["exists"]):
		return String(route["failure_reason"])
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var graph := MaritimeGraphScript.load_default()
	var fleet := world.get_fleet(fleet_id)
	var current := int(fleet.get("location_id", -1))
	var route := NavalAccessPolicyScript.find_legal_route(graph, world, issuing_country, current, destination_id)
	var path: Array = route["path"]
	var remaining: Array = []
	for index in range(1, path.size()):
		remaining.append(int((path[index] as Dictionary)["id"]))
	var speed_bp := FleetSystemScript.speed_multiplier_bp(fleet)
	fleet["destination_id"] = destination_id
	fleet["remaining_path"] = remaining
	fleet["path_index"] = 0
	fleet["movement_start_day"] = world.current_day
	fleet["next_arrival_day"] = world.current_day + graph.leg_cost_days(current, int(remaining[0]), speed_bp)
	fleet["movement_progress"] = 0.0
	fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_MOVING
	world.fleet_registry[fleet_id] = fleet
	events.fleet_movement_ordered.emit(fleet_id, remaining, int(route["total_days"]) + world.current_day)
