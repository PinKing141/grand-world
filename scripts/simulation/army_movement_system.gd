class_name ArmyMovementSystem
extends RefCounted

## Advances authoritative army movement one campaign day at a time.
##
## Movement is scheduled by arrival day, never by rendered frames: an army
## ordered on day D with a 7-day leg enters the next province on day D+7 at
## every frame rate and every game speed. Presentation only interpolates.

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBus = preload("res://scripts/simulation/simulation_event_bus.gd")
const ProvincePathfinderScript = preload("res://scripts/simulation/province_pathfinder.gd")


static func advance_day(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var graph := ProvinceGraph.load_default()
	var army_ids := world.army_registry.keys()
	army_ids.sort()
	for raw_army_id in army_ids:
		var army_id := String(raw_army_id)
		var army: Dictionary = world.army_registry[raw_army_id]
		if String(army.get("status", "")) not in [CampaignWorldState.ARMY_STATUS_MOVING, CampaignWorldState.ARMY_STATUS_RETREATING]:
			continue
		var arrival_day := int(army.get("next_arrival_day", -1))
		if arrival_day < 0 or world.current_day < arrival_day:
			_update_progress(world, army)
			continue

		var remaining: Array = army.get("remaining_path", [])
		var path_index := int(army.get("path_index", 0))
		if path_index >= remaining.size():
			_finish(world, events, army_id, army)
			continue
		var entered := int(remaining[path_index])
		var owner := String(army.get("owner_country_id", ""))
		if not ProvincePathfinderScript.can_enter(graph, world, owner, entered):
			# Access changed mid-route (ownership flip, new restriction):
			# the army halts in its current province with a clear status.
			army["status"] = CampaignWorldState.ARMY_STATUS_BLOCKED
			army["next_arrival_day"] = -1
			army["movement_progress"] = 0.0
			world.army_registry[army_id] = army
			events.army_movement_blocked.emit(
				army_id, entered, "Movement blocked entering province %d." % entered
			)
			continue

		var previous := int(army.get("current_province_id", -1))
		army["current_province_id"] = entered
		army["path_index"] = path_index + 1
		events.army_moved.emit(army_id, previous, entered)

		if path_index + 1 >= remaining.size():
			_finish(world, events, army_id, army)
			continue
		var next_province := int(remaining[path_index + 1])
		army["movement_start_day"] = world.current_day
		army["next_arrival_day"] = world.current_day + ProvincePathfinderScript.leg_cost_days(graph, entered, next_province)
		army["movement_progress"] = 0.0
		world.army_registry[army_id] = army


static func _update_progress(world: CampaignWorldState, army: Dictionary) -> void:
	var start_day := int(army.get("movement_start_day", -1))
	var arrival_day := int(army.get("next_arrival_day", -1))
	if start_day < 0 or arrival_day <= start_day:
		return
	army["movement_progress"] = clampf(
		float(world.current_day - start_day) / float(arrival_day - start_day), 0.0, 1.0
	)


static func _finish(world: CampaignWorldState, events: SimulationEventBus, army_id: String, army: Dictionary) -> void:
	var was_retreating := bool(army.get("retreating", false))
	army["destination_province_id"] = -1
	army["remaining_path"] = []
	army["path_index"] = 0
	army["movement_start_day"] = -1
	army["next_arrival_day"] = -1
	army["movement_progress"] = 0.0
	army["retreating"] = false
	if was_retreating:
		army["status"] = CampaignWorldState.ARMY_STATUS_RECOVERING
		army["recovery_until_day"] = world.current_day + 5
		army["movement_locked"] = true
	else:
		army["status"] = CampaignWorldState.ARMY_STATUS_IDLE
	world.army_registry[army_id] = army
	events.army_movement_completed.emit(army_id, int(army.get("current_province_id", -1)))
