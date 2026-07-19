extends SceneTree

## N6A continuation: NavalAISystem._plan_transport() - the reachable slice of
## "atomic transport-objective planning and land-AI handoff" (06_N6
## "Transport Planning"). Reads StrategicAISystem's own existing
## target_province_id (no new "objective" concept invented) and ferries an
## idle army toward it once land movement genuinely cannot reach it but a
## real ship can.
##
## Discovered while writing this test, not assumed: NavalAccessPolicy.
## can_dock() deliberately never grants docking rights merely from being at
## war (01_N1's own "sailing into a hostile harbour is not the same act as
## marching an army into hostile territory"), so a hostile-held port like
## Picardie is never itself a legal transport destination, war or no war.
## _plan_transport() therefore lands at the country's own nearest legally
## dockable port that has a real land route onward to the objective - here,
## Calais, which is both England's own port and (confirmed below) land-
## adjacent to Picardie - not at the objective directly. Driven against the
## same hand-built Channel fixture naval_ai_threat_test.gd already uses, for
## the same reason: precise control over exactly which province is and
## isn't land-reachable from which.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")
const ProvincePathfinderScript = preload("res://scripts/simulation/province_pathfinder.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval AI transport test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize({CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR"}, {"ENG": "England", "BUR": "Burgundy"})
	return world


func _make_naval_ai(world: CampaignWorldState, events: SimulationEventBus) -> NavalAISystem:
	var scheduler := SimulationSchedulerScript.new(world, events)
	return NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())


func _set_land_target(world: CampaignWorldState, tag: String, target_province_id: int) -> void:
	var runtime := world.country_runtime(tag)
	var ai_state: Dictionary = runtime.get("ai", {})
	ai_state["target_province_id"] = target_province_id
	runtime["ai"] = ai_state
	world.set_country_runtime(tag, runtime)


func _add_army_and_fleet(world: CampaignWorldState, suffix: String, owner: String, port_id: int) -> void:
	var army_id := "army_%s" % suffix
	var fleet_id := "fleet_%s" % suffix
	world.army_registry[army_id] = CampaignWorldStateScript.make_army_record(army_id, owner, port_id)
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, port_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = port_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	var ship_id := "ship_%s" % suffix
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "transport_cog", 0)
	fleet["ship_ids"] = [ship_id]
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _run() -> void:
	var graph := ProvinceGraph.load_default()
	_require(not bool(ProvincePathfinderScript.find_route(graph, _make_world(), "ENG", KENT, PICARDIE).get("exists", false)), "fixture assumption: Kent must have no land or strait route to Picardie")
	_require(not bool(ProvincePathfinderScript.find_route(graph, _make_world(), "ENG", KENT, CALAIS).get("exists", false)), "fixture assumption: Kent must have no land route to Calais either - both need a real sea crossing")
	_require(bool(ProvincePathfinderScript.find_route(graph, _make_world(), "ENG", CALAIS, PICARDIE).get("exists", false)), "fixture assumption: Calais and Picardie must share a direct land route")

	# --- Beachhead handoff: an idle England army at Kent, with land AI's own
	# target set to Picardie (a hostile port - never itself a legal landing
	# site) and a transport-capable fleet docked at Kent, must be ferried to
	# Calais instead - England's own port with a real land route onward to
	# Picardie - through a real CreateTransportOperationCommand. ---
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_army_and_fleet(world, "kent", "ENG", KENT)
	_set_land_target(world, "ENG", PICARDIE)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_transport(world, "ENG")
	naval_ai.scheduler.process_commands()

	_require(world.transport_operation_registry.size() == 1, "an unreachable-by-land war objective with a real carrier and a legal beachhead must produce a transport operation")
	var operation: Dictionary = world.transport_operation_registry.values()[0]
	_require(String(operation.get("army_id", "")) == "army_kent", "the idle army at the shared port must be the one embarked")
	_require(int(operation.get("destination_province_id", -1)) == CALAIS, "the operation must target the legal beachhead (Calais), not the hostile port itself (Picardie)")
	_require(String(world.get_army("army_kent")["status"]) == CampaignWorldStateScript.ARMY_STATUS_EMBARKING, "the army must actually be embarking, not just referenced")
	var snapshot := naval_ai.debug_snapshot(world, "ENG")
	_require(String((snapshot["last_decision"] as Dictionary).get("category", "")) == "transport", "the decision must be recorded under the transport category")

	# --- Control: no war objective at all - must not invent a transport. ---
	var world_b := _make_world()
	var events_b := SimulationEventBusScript.new()
	root.add_child(events_b)
	_add_army_and_fleet(world_b, "kent_b", "ENG", KENT)
	var naval_ai_b := _make_naval_ai(world_b, events_b)
	naval_ai_b._plan_transport(world_b, "ENG")
	naval_ai_b.scheduler.process_commands()
	_require(world_b.transport_operation_registry.is_empty(), "no land objective at all must never produce a transport operation")

	# --- Control: an objective reachable directly by land from the army's
	# own province (Picardie from Calais, both continental) must not trigger
	# a transport - land AI's own march order already handles it. ---
	var world_c := _make_world()
	var events_c := SimulationEventBusScript.new()
	root.add_child(events_c)
	_add_army_and_fleet(world_c, "calais_c", "ENG", CALAIS)
	_set_land_target(world_c, "ENG", PICARDIE)
	var naval_ai_c := _make_naval_ai(world_c, events_c)
	naval_ai_c._plan_transport(world_c, "ENG")
	naval_ai_c.scheduler.process_commands()
	_require(world_c.transport_operation_registry.is_empty(), "a land-reachable objective must be left to land AI's own march order, not ferried")

	print("Naval AI transport test passed.")
	quit(0)
