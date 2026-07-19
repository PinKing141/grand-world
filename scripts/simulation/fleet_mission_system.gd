class_name FleetMissionSystem
extends RefCounted

## N6A: the mechanical half of "Fleet Missions" (docs/roadmap/naval/
## 06_N6_AI_AND_UX.md) - daily processing that gives self-completing
## missions their actual behaviour, separate from SetFleetMissionCommand
## (which only validates and tags fleet.mission) and from NavalAISystem
## (which decides *when* to assign a mission, not what the mission does
## once assigned). "blockade" needs no entry here - BlockadeSystem already
## reads fleet.mission directly, it does not need a state-completion step
## since a blockade never "finishes," only stops being eligible.
## NavalAISystem's own _consider_mission_completion() separately stands an
## AI-controlled blockading fleet back down to idle once its target is gone
## (e.g. peace) - a naval-AI reconsideration concern, not a mission-mechanics
## one, so it lives there rather than here.
##
## Only "return_to_port" and "repair" are handled - the two missions this
## slice actually added to SetFleetMissionCommand.VALID_MISSIONS. Missions
## that need a threat map or transport-planning layer (patrol, intercept,
## protect_transport, protect_coast) are not implemented, so nothing here
## processes them.

const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")


static func process_day(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var graph := MaritimeGraphScript.load_default()
	var fleet_ids := world.fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		var mission := String((world.fleet_registry[raw_fleet_id] as Dictionary).get("mission", "idle"))
		if mission == "repair":
			_process_repair_mission(world, events, fleet_id)
		elif mission == "return_to_port":
			_process_return_to_port_mission(world, events, graph, fleet_id)


## "Remain docked until repair threshold is met" (06_N6 "Fleet Missions").
## Repair itself already happens unconditionally for any docked fleet at a
## legal repair port (FleetLogisticsSystem._process_repair(), unrelated to
## mission) - this only watches for "fully healed" and clears the mission
## tag, the same self-completion 06_N6 asks every mission to have. A fleet
## not yet docked anywhere useful simply waits; NavalAISystem is expected to
## have already sent it toward a port (return_to_port) before assigning
## repair, the same two-step split N3.2 already uses for embark-then-sail.
static func _process_repair_mission(world: CampaignWorldState, events: SimulationEventBus, fleet_id: String) -> void:
	var fleet := world.get_fleet(fleet_id)
	var aggregate: Dictionary = fleet.get("aggregate", {})
	var max_hull := int(aggregate.get("total_maximum_hull", 0))
	if max_hull <= 0 or int(aggregate.get("total_hull", 0)) < max_hull:
		return
	fleet["mission"] = "idle"
	world.fleet_registry[fleet_id] = fleet
	events.fleet_mission_changed.emit(fleet_id, "idle")


## "Forced/safe return" (06_N6 "Fleet Missions"). Mirrors
## NavalCombatSystem._begin_retreat()'s own "already legal here, else find
## the nearest legal port" shape exactly, the same bounded-recovery pattern
## N3.3's TransportSystem._attempt_recovery() established first - reused a
## third time here rather than a fourth slightly-different implementation.
## FL2.3: a player-chosen target (fleet.mission_target_ids[0], set through
## SetFleetMissionCommand the same way any other mission target is) is
## preferred over the auto-picked nearest port when it is itself a legal
## dock target - an empty/unset/illegal target falls through to the original
## auto-pick behaviour unchanged, so AI-assigned return_to_port (which never
## sets a target) is not affected by this at all.
static func _process_return_to_port_mission(world: CampaignWorldState, events: SimulationEventBus, graph: MaritimeGraph, fleet_id: String) -> void:
	var fleet := world.get_fleet(fleet_id)
	var owner := String(fleet.get("owner_country_id", ""))
	var location_id := int(fleet.get("location_id", -1))
	var location_status := String(fleet.get("location_status", ""))
	var target_ids := (fleet.get("mission_target_ids", []) as Array)
	var chosen_target_id := int(target_ids[0]) if not target_ids.is_empty() else -1
	if chosen_target_id == location_id and location_status == CampaignWorldState.FLEET_LOCATION_DOCKED and NavalAccessPolicyScript.can_dock(graph, world, owner, location_id):
		fleet["mission"] = "idle"
		world.fleet_registry[fleet_id] = fleet
		events.fleet_mission_changed.emit(fleet_id, "idle")
		return
	if location_status == CampaignWorldState.FLEET_LOCATION_DOCKED and chosen_target_id < 0 and NavalAccessPolicyScript.can_dock(graph, world, owner, location_id):
		fleet["mission"] = "idle"
		world.fleet_registry[fleet_id] = fleet
		events.fleet_mission_changed.emit(fleet_id, "idle")
		return
	var settled := location_status in [CampaignWorldState.FLEET_LOCATION_DOCKED, CampaignWorldState.FLEET_LOCATION_AT_SEA] \
		and (fleet.get("remaining_path", []) as Array).is_empty() and int(fleet.get("destination_id", -1)) < 0
	if not settled:
		return
	if not (fleet.get("transport_operation_ids", []) as Array).is_empty():
		return
	var destination_id := -1
	if chosen_target_id >= 0 and NavalAccessPolicyScript.can_dock(graph, world, owner, chosen_target_id):
		destination_id = chosen_target_id
	elif NavalAccessPolicyScript.can_dock(graph, world, owner, location_id):
		destination_id = location_id
	else:
		var nearest := graph.nearest_matching(location_id, func(candidate_id): return NavalAccessPolicyScript.can_dock(graph, world, owner, candidate_id))
		if bool(nearest["found"]):
			destination_id = int(nearest["id"])
	if destination_id < 0:
		return
	if destination_id == location_id:
		fleet["mission"] = "idle"
		world.fleet_registry[fleet_id] = fleet
		events.fleet_mission_changed.emit(fleet_id, "idle")
		return
	var command := MoveFleetCommandScript.new(fleet_id, destination_id, owner, "ai")
	if command.validate(world).is_empty():
		command.apply(world, events)
