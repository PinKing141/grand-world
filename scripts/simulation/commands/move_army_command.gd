class_name MoveArmyCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const ProvincePathfinderScript = preload("res://scripts/simulation/province_pathfinder.gd")

var army_id := ""
var destination_province_id := -1
var issuing_country := ""
var sequence_number := 0


func _init(
	p_army_id: String,
	p_destination: int,
	p_issuing_country: String,
	p_issuer := "player",
	p_scheduled_day := -1,
	p_sequence_number := 0
) -> void:
	army_id = p_army_id
	destination_province_id = p_destination
	issuing_country = p_issuing_country
	sequence_number = p_sequence_number
	issuer = p_issuer
	scheduled_day = p_scheduled_day
	description = "Move %s to province %d" % [army_id, destination_province_id]


func command_type() -> String:
	return "MoveArmyCommand"


func validate(world: CampaignWorldState) -> String:
	if army_id.is_empty() or destination_province_id < 0:
		return "The movement order is malformed."
	var army := world.get_army(army_id)
	if army.is_empty():
		return "The army no longer exists."
	if String(army.get("owner_country_id", "")) != issuing_country:
		return "%s does not control this army." % issuing_country
	if String(army.get("status", CampaignWorldState.ARMY_STATUS_IDLE)) == CampaignWorldState.ARMY_STATUS_EMBARKED:
		return "The army is embarked."
	if bool(army.get("movement_locked", false)):
		return "The army is movement-locked."
	if String(army.get("status", CampaignWorldState.ARMY_STATUS_IDLE)) in [CampaignWorldState.ARMY_STATUS_BATTLE, CampaignWorldState.ARMY_STATUS_RETREATING, CampaignWorldState.ARMY_STATUS_RECOVERING]:
		return "The army cannot receive orders in its current state."
	var graph := ProvinceGraph.load_default()
	var current := int(army.get("current_province_id", -1))
	if destination_province_id == current:
		return "The army is already in that province."
	var route := ProvincePathfinderScript.find_route(
		graph, world, issuing_country, current, destination_province_id
	)
	if not bool(route["exists"]):
		return String(route["failure_reason"])
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var graph := ProvinceGraph.load_default()
	var army := world.get_army(army_id)
	var current := int(army.get("current_province_id", -1))
	var route := ProvincePathfinderScript.find_route(
		graph, world, issuing_country, current, destination_province_id
	)
	var path: PackedInt32Array = route["path"]
	var remaining: Array = []
	for index in range(1, path.size()):
		remaining.append(int(path[index]))
	army["destination_province_id"] = destination_province_id
	army["remaining_path"] = remaining
	army["path_index"] = 0
	army["movement_start_day"] = world.current_day
	army["next_arrival_day"] = world.current_day + ProvincePathfinderScript.leg_cost_days(graph, current, int(remaining[0]))
	army["movement_progress"] = 0.0
	army["status"] = CampaignWorldState.ARMY_STATUS_MOVING
	world.army_registry[army_id] = army
	events.army_movement_ordered.emit(army_id, path, _estimated_arrival_day(world, graph, path))


func _estimated_arrival_day(world: CampaignWorldState, graph: ProvinceGraph, path: PackedInt32Array) -> int:
	var day := world.current_day
	for index in range(path.size() - 1):
		day += ProvincePathfinderScript.leg_cost_days(graph, path[index], path[index + 1])
	return day
