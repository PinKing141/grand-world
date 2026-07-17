class_name FleetMovementSystem
extends RefCounted

## Advances authoritative fleet movement one campaign day at a time, mirroring
## ArmyMovementSystem's arrival-day model exactly (02_N2_FLEET_LOGISTICS.md
## "Movement mirrors the proven army arrival-day model"). A fleet ordered on
## day D with a 3-day leg enters the next node on day D+3 at every frame rate
## and every game speed. Presentation only interpolates.
##
## Each leg is revalidated here, not just at MoveFleetCommand time - access
## can change mid-route (a port loses its dock grant, ownership flips). A
## blocked fleet halts at its last legal node rather than teleporting or
## being deleted.

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBus = preload("res://scripts/simulation/simulation_event_bus.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")


static func advance_day(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var graph := MaritimeGraphScript.load_default()
	var fleet_ids := world.fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		var fleet: Dictionary = world.fleet_registry[raw_fleet_id]
		if String(fleet.get("location_status", "")) not in [CampaignWorldState.FLEET_LOCATION_MOVING, CampaignWorldState.FLEET_LOCATION_RETREATING]:
			continue
		var arrival_day := int(fleet.get("next_arrival_day", -1))
		if arrival_day < 0 or world.current_day < arrival_day:
			_update_progress(world, fleet)
			world.fleet_registry[fleet_id] = fleet
			continue

		var remaining: Array = fleet.get("remaining_path", [])
		var path_index := int(fleet.get("path_index", 0))
		if path_index >= remaining.size():
			_finish(graph, world, events, fleet_id, fleet)
			continue
		var entered := int(remaining[path_index])
		var owner := String(fleet.get("owner_country_id", ""))
		var block_reason := _entry_failure_reason(graph, world, owner, entered)
		if not block_reason.is_empty():
			var current_location_id := int(fleet.get("location_id", -1))
			fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_DOCKED if graph.is_port_province(current_location_id) else CampaignWorldState.FLEET_LOCATION_AT_SEA
			fleet["destination_id"] = -1
			fleet["remaining_path"] = []
			fleet["path_index"] = 0
			fleet["next_arrival_day"] = -1
			fleet["movement_progress"] = 0.0
			world.fleet_registry[fleet_id] = fleet
			events.fleet_movement_blocked.emit(fleet_id, entered, block_reason)
			continue

		var previous := int(fleet.get("location_id", -1))
		fleet["location_id"] = entered
		fleet["path_index"] = path_index + 1
		events.fleet_moved.emit(fleet_id, previous, entered)

		if path_index + 1 >= remaining.size():
			_finish(graph, world, events, fleet_id, fleet)
			continue
		var next_node := int(remaining[path_index + 1])
		var speed_bp := FleetSystemScript.speed_multiplier_bp(fleet)
		fleet["movement_start_day"] = world.current_day
		fleet["next_arrival_day"] = world.current_day + graph.leg_cost_days(entered, next_node, speed_bp)
		fleet["movement_progress"] = 0.0
		world.fleet_registry[fleet_id] = fleet


static func _entry_failure_reason(graph: MaritimeGraph, world: CampaignWorldState, owner: String, entered: int) -> String:
	if graph.is_port_province(entered):
		if not NavalAccessPolicyScript.can_dock(graph, world, owner, entered):
			return NavalAccessPolicyScript.dock_failure_reason(graph, world, owner, entered)
		return ""
	if not NavalAccessPolicyScript.can_sail(graph, entered):
		return "Sea zone %d is not navigable." % entered
	return ""


static func _update_progress(world: CampaignWorldState, fleet: Dictionary) -> void:
	var start_day := int(fleet.get("movement_start_day", -1))
	var arrival_day := int(fleet.get("next_arrival_day", -1))
	if start_day < 0 or arrival_day <= start_day:
		return
	fleet["movement_progress"] = clampf(
		float(world.current_day - start_day) / float(arrival_day - start_day), 0.0, 1.0
	)


static func _finish(graph: MaritimeGraph, world: CampaignWorldState, events: SimulationEventBus, fleet_id: String, fleet: Dictionary) -> void:
	var current_location_id := int(fleet.get("location_id", -1))
	fleet["destination_id"] = -1
	fleet["remaining_path"] = []
	fleet["path_index"] = 0
	fleet["movement_start_day"] = -1
	fleet["next_arrival_day"] = -1
	fleet["movement_progress"] = 0.0
	fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_DOCKED if graph.is_port_province(current_location_id) else CampaignWorldState.FLEET_LOCATION_AT_SEA
	world.fleet_registry[fleet_id] = fleet
	events.fleet_movement_completed.emit(fleet_id, current_location_id)
