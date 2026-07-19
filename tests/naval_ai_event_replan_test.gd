extends SceneTree

## FL3.4's own still-open sub-item: "avoid daily full replanning; use
## staggered schedules and event-triggered invalidation." Staggered
## schedules were already real; event-triggered invalidation did not exist
## at all - the FL3 closure audit's own finding was "a fleet that becomes
## acutely endangered the day after its own TACTICAL_INTERVAL tick waits up
## to 5 days (minus stagger) before the AI reconsiders it." NavalAISystem
## now subscribes to naval_battle_started/fleet_moved and forces an
## off-schedule tactical reconsideration for any country with a fleet in
## the touched zone, tracked by a new naval_ai_event_replans counter so a
## "replan storm" (many countries triggered the same day) is measurable,
## not just theoretically bounded.
##
## Uses Castile from the real AIDefinitions roster (the same fixture
## tests/naval_ai_test.gd's own 215-day run uses) rather than the
## lightweight synthetic ENG/BUR Channel fixture most other naval-AI tests
## use - process_day()'s own country_tags loop (where this new logic
## lives) only ever visits countries AIDefinitions actually lists, which
## the synthetic Channel countries are not.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")

const OWNERS := {206: "CAS", 215: "CAS", 217: "CAS", 219: "CAS", 224: "CAS", 225: "CAS"}
const NAMES := {"CAS": "Castile"}
const CAS_FLEET_ZONE := 1749

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(OWNERS, NAMES)
	EconomySystemScript.initialize_world(world)
	var runtime := world.country_runtime("CAS")
	runtime["treasury"] = 5000000
	runtime["sailors"] = 1000000
	world.set_country_runtime("CAS", runtime)
	return world


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, location_id: int, ship_count: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, location_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	var ship_ids: Array = []
	for index in ship_count:
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "war_galley", 0)
		ship_ids.append(ship_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _off_schedule_day(naval_ai: NavalAISystem, tag: String) -> int:
	var slot := int(AIDefinitionsScript.load_default().profile(tag).get("slot", 0))
	var day := slot + 2
	while naval_ai._due(day, NavalAISystemScript.TACTICAL_INTERVAL, slot):
		day += 1
	return day


func _test_fleet_moved_triggers_off_schedule_replan() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	var naval_ai := NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())
	_add_fleet(world, "fleet_cas", "CAS", CAS_FLEET_ZONE, 2)

	var day := _off_schedule_day(naval_ai, "CAS")
	var slot := int(AIDefinitionsScript.load_default().profile("CAS").get("slot", 0))
	_check(not naval_ai._due(day, NavalAISystemScript.TACTICAL_INTERVAL, slot), "FIXTURE_DAY_NOT_OFF_SCHEDULE", "fixture assumption: the chosen day must genuinely be off Castile's own tactical schedule")
	world.current_day = day

	# Control: on this exact off-schedule day, with no trigger fired, no
	# tactical decision must be recorded at all yet.
	naval_ai.process_day(world)
	var before_replans := int(world.global_counters.get("naval_ai_event_replans", 0))
	_check(before_replans == 0, "CONTROL_FALSELY_TRIGGERED", "with no event fired, no off-schedule tactical replan must occur: got %d" % before_replans)

	# A hostile fleet arriving in Castile's own zone must force an
	# immediate reconsideration this same off-schedule day, not wait for
	# the next real tactical tick.
	events.fleet_moved.emit("hostile_probe", -1, CAS_FLEET_ZONE)
	naval_ai.process_day(world)
	naval_ai.scheduler.process_commands()
	_check(int(world.global_counters.get("naval_ai_event_replans", 0)) == before_replans + 1, "EVENT_DID_NOT_TRIGGER_REPLAN", "a fleet_moved arrival in Castile's own zone must force exactly one event-triggered replan on this off-schedule day")
	var snapshot := naval_ai.debug_snapshot(world, "CAS")
	var last_decision: Dictionary = snapshot.get("last_decision", {})
	_check(String(last_decision.get("category", "")) == "tactical" and int(last_decision.get("day", -1)) == day, "TACTICAL_DECISION_NOT_RECORDED_TODAY", "the forced replan must actually record a tactical decision on the trigger day itself: got %s" % last_decision)


func _test_battle_started_triggers_off_schedule_replan() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	var naval_ai := NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())
	_add_fleet(world, "fleet_cas", "CAS", CAS_FLEET_ZONE, 2)

	var day := _off_schedule_day(naval_ai, "CAS")
	world.current_day = day
	events.naval_battle_started.emit("war_x", "battle_x", CAS_FLEET_ZONE)
	naval_ai.process_day(world)
	naval_ai.scheduler.process_commands()
	_check(int(world.global_counters.get("naval_ai_event_replans", 0)) == 1, "BATTLE_START_DID_NOT_TRIGGER_REPLAN", "a battle starting in Castile's own zone must force an off-schedule tactical replan")


func _test_unrelated_zone_does_not_trigger() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	var naval_ai := NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())
	_add_fleet(world, "fleet_cas", "CAS", CAS_FLEET_ZONE, 2)

	var day := _off_schedule_day(naval_ai, "CAS")
	world.current_day = day
	# A fleet moving somewhere Castile has no presence at all must not
	# force a replan - the trigger is scoped to zones a country actually
	# has a fleet in, not a blanket "something happened somewhere" signal.
	events.fleet_moved.emit("irrelevant_fleet", -1, 999999)
	naval_ai.process_day(world)
	_check(int(world.global_counters.get("naval_ai_event_replans", 0)) == 0, "UNRELATED_ZONE_TRIGGERED_REPLAN", "a fleet arriving somewhere Castile has no fleet must never force a replan there")


func _run() -> void:
	_test_fleet_moved_triggers_off_schedule_replan()
	_test_battle_started_triggers_off_schedule_replan()
	_test_unrelated_zone_does_not_trigger()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval AI event replan test failed: %s" % failure)
		print("Naval AI event replan test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval AI event replan test passed. cases=fleet_moved_trigger,battle_started_trigger,unrelated_zone_no_trigger")
	quit(0)
