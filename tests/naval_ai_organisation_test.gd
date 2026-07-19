extends SceneTree

## N6A continuation: NavalAISystem._consider_fleet_merge() - "group
## compatible ships into task fleets" (06_N6 "Operational allocation"), the
## other half of _plan_organisation() alongside the pre-existing admiral
## assignment.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval AI organisation test failed: %s" % message)
		quit(1)


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	# Picardie/Straits of Dover are unowned here (this file's own fixtures
	# never declare a war or a hostile owner) - included purely so
	# _overseas_objective_landing() has a real, existing, ENG-uncontrolled
	# province to target for the transport-separation tests below; every
	# pre-existing merge test in this file is unaffected, since none of
	# them reference either province.
	world.initialize({CALAIS: "ENG", KENT: "ENG", PICARDIE: "", STRAITS_OF_DOVER: ""}, {"ENG": "England"})
	return world


func _make_naval_ai(world: CampaignWorldState, events: SimulationEventBus) -> NavalAISystem:
	var scheduler := SimulationSchedulerScript.new(world, events)
	return NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())


func _add_fleet(world: CampaignWorldState, fleet_id: String, port_id: int, transport_op: String) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, "ENG", port_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = port_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	var ship_id := "%s_s0" % fleet_id
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, "ENG", fleet_id, "war_galley", 0)
	fleet["ship_ids"] = [ship_id]
	if not transport_op.is_empty():
		fleet["transport_operation_ids"] = [transport_op]
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _add_mixed_fleet(world: CampaignWorldState, fleet_id: String, port_id: int, families: Array[String]) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, "ENG", port_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = port_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	var ship_ids: Array = []
	for index in families.size():
		var definition_id := "war_galley" if families[index] != "transport" else "transport_cog"
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, "ENG", fleet_id, definition_id, 0)
		ship_ids.append(ship_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _set_overseas_objective(world: CampaignWorldState, target_province_id: int) -> void:
	var runtime := world.country_runtime("ENG")
	var ai_state: Dictionary = runtime.get("ai", {})
	ai_state["target_province_id"] = target_province_id
	runtime["ai"] = ai_state
	world.set_country_runtime("ENG", runtime)


## FL3.3: _consider_transport_ship_separation() - "group ships into task
## fleets" also covers preparing a dedicated transport fleet ahead of a
## pending overseas run, not just consolidating idle combat fleets.
func _test_split_mixed_fleet_before_transport_run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_mixed_fleet(world, "fleet_mixed", CALAIS, ["galley", "transport"])
	_set_overseas_objective(world, PICARDIE)
	var naval_ai := _make_naval_ai(world, events)
	var ship_definitions := preload("res://scripts/simulation/ship_definitions.gd").load_default()
	naval_ai._plan_organisation(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(world.country_fleets("ENG").size() == 2, "SPLIT_FIXTURE_NOT_TWO_FLEETS", "a mixed fleet with a live overseas objective must be split into exactly two fleets: got %d" % world.country_fleets("ENG").size())
	var original := world.get_fleet("fleet_mixed")
	var original_families := {}
	for raw_ship_id in (original.get("ship_ids", []) as Array):
		original_families[String(ship_definitions.ship(String(world.get_ship(String(raw_ship_id)).get("definition_id", ""))).get("family", ""))] = true
	_check(original_families.size() == 1 and original_families.has("transport"), "ORIGINAL_FLEET_NOT_PURE_TRANSPORT", "the original fleet must be left holding only its transport-family ship(s): got families %s" % [original_families.keys()])
	for raw_fleet_id in world.country_fleets("ENG"):
		var fleet_id := String(raw_fleet_id)
		if fleet_id == "fleet_mixed":
			continue
		var split_fleet := world.get_fleet(fleet_id)
		for raw_ship_id in (split_fleet.get("ship_ids", []) as Array):
			var family := String(ship_definitions.ship(String(world.get_ship(String(raw_ship_id)).get("definition_id", ""))).get("family", ""))
			_check(family != "transport", "SPLIT_FLEET_HAS_TRANSPORT_SHIP", "the newly split-off fleet must hold only the non-transport ships, got a %s ship" % family)


func _test_no_split_without_overseas_objective() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_mixed_fleet(world, "fleet_mixed", CALAIS, ["galley", "transport"])
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_organisation(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(world.country_fleets("ENG").size() == 1, "SPLIT_FIRED_WITHOUT_OBJECTIVE", "a mixed fleet must never be split when there is no live overseas objective needing transport")


func _test_no_split_for_pure_fleet() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_mixed_fleet(world, "fleet_pure", CALAIS, ["transport", "transport"])
	_set_overseas_objective(world, PICARDIE)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_organisation(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(world.country_fleets("ENG").size() == 1, "SPLIT_FIRED_FOR_PURE_FLEET", "an already-pure transport fleet must never be split - there is nothing to separate")


func _run() -> void:
	# --- Two separate, unled, single-ship fleets docked at the same port
	# must consolidate into one task fleet. ---
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_a", CALAIS, "")
	_add_fleet(world, "fleet_b", CALAIS, "")
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_organisation(world, "ENG")
	naval_ai.scheduler.process_commands()

	_require(world.country_fleets("ENG").size() == 1, "two same-port fleets must merge into exactly one")
	var merged_id := world.country_fleets("ENG")[0]
	_require(merged_id == "fleet_a", "the lowest-sorted fleet ID must be the merge target")
	_require((world.get_fleet("fleet_a")["ship_ids"] as Array).size() == 2, "the surviving fleet must carry both ships")
	_require(not world.fleet_registry.has("fleet_b"), "the emptied source fleet must be removed, not left as a ghost entry")
	var snapshot := naval_ai.debug_snapshot(world, "ENG")
	_require(String((snapshot["last_decision"] as Dictionary).get("action", "")) == "MergeFleetsCommand", "the decision must record the real command that was submitted")

	# --- Control: fleets at different ports must not be merged. ---
	var world_b := _make_world()
	var events_b := SimulationEventBusScript.new()
	root.add_child(events_b)
	_add_fleet(world_b, "fleet_c", CALAIS, "")
	_add_fleet(world_b, "fleet_d", KENT, "")
	var naval_ai_b := _make_naval_ai(world_b, events_b)
	naval_ai_b._plan_organisation(world_b, "ENG")
	naval_ai_b.scheduler.process_commands()
	_require(world_b.country_fleets("ENG").size() == 2, "fleets docked at different ports must never merge")

	# --- Control: a fleet carrying a transport operation must never be
	# merged away, even if another idle fleet shares its port - merging
	# would strand the operation's own fleet_id reference. ---
	var world_c := _make_world()
	var events_c := SimulationEventBusScript.new()
	root.add_child(events_c)
	_add_fleet(world_c, "fleet_e", CALAIS, "transport_1")
	_add_fleet(world_c, "fleet_f", CALAIS, "")
	var naval_ai_c := _make_naval_ai(world_c, events_c)
	naval_ai_c._plan_organisation(world_c, "ENG")
	naval_ai_c.scheduler.process_commands()
	_require(world_c.country_fleets("ENG").size() == 2, "a fleet carrying a transport operation must never be merged")

	_test_split_mixed_fleet_before_transport_run()
	_test_no_split_without_overseas_objective()
	_test_no_split_for_pure_fleet()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval AI organisation test failed: %s" % failure)
		print("Naval AI organisation test FAILED. failures=%d" % _failures.size())
		quit(1)
		return

	print("Naval AI organisation test passed. cases=merge,merge_different_ports,merge_transport_excluded,split_before_transport,no_split_without_objective,no_split_pure_fleet")
	quit(0)
