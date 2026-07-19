extends SceneTree

## FL3 "Automated verification": "Confirm trace production does not change
## authoritative results" - previously untested and previously untestable,
## per FL3_CLOSURE_AUDIT.md's own accounting: "there is in fact no way to
## disable it - recording is unconditional, not gated behind a flag."
## NavalAISystem._record_decision()/_record_rejected_candidate() gained a
## world.global_flags["naval_ai_tracing_enabled"] toggle (default true, so
## every existing caller is unaffected) specifically to make this claim
## checkable, not just theoretically true. The checksummed global_counters
## (naval_ai_decisions/naval_ai_commands_submitted/naval_ai_candidates_
## evaluated) are deliberately NOT gated by this flag - they are the
## roadmap's own separate "Add counters for..." bullet, authoritative
## tallies rather than trace content, and this test proves both halves:
## the counters stay identical whether or not tracing runs, while the trace
## content itself (decision_history/rejected_candidates) is genuinely
## produced only when enabled, not always silently written regardless.
##
## Reuses tests/naval_ai_test.gd's own real 29-port Iberian fixture and
## 215-day simulated span - the same rigor that test's two-instance
## determinism replay already established, adapted here to vary the
## tracing flag between the two instances instead of nothing at all.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const FleetLogisticsSystemScript = preload("res://scripts/simulation/fleet_logistics_system.gd")
const FleetMissionSystemScript = preload("res://scripts/simulation/fleet_mission_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")

const OWNERS := {
	206: "CAS", 215: "CAS", 217: "CAS", 219: "CAS", 224: "CAS", 225: "CAS",
	211: "ARA", 212: "ARA", 214: "ARA", 220: "ARA",
	227: "POR", 228: "POR", 231: "POR",
	222: "GRA", 223: "GRA", 226: "GRA", 4546: "GRA",
	210: "NAV",
}
const NAMES := {"CAS": "Castile", "ARA": "Aragon", "POR": "Portugal", "GRA": "Granada", "NAV": "Navarre"}
const MARITIME_COUNTRIES := ["CAS", "ARA", "POR"]
const SIMULATED_DAYS := 215

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_simulation(seed_value: int, tracing_enabled: bool) -> Dictionary:
	var world := CampaignWorldStateScript.new()
	world.initialize(OWNERS, NAMES, "naval_ai_trace_neutrality_test", seed_value)
	world.global_flags["naval_ai_tracing_enabled"] = tracing_enabled
	EconomySystemScript.initialize_world(world)
	for tag in MARITIME_COUNTRIES:
		var runtime := world.country_runtime(tag)
		runtime["treasury"] = 200000
		runtime["sailors"] = 2000
		world.set_country_runtime(tag, runtime)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: FleetMovementSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: NavalCombatSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: BlockadeSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: EconomySystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: FleetLogisticsSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: TransportSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: FleetMissionSystemScript.process_day(day_world, events))
	scheduler.monthly_systems.append(func(month_world: CampaignWorldState) -> void: EconomySystemScript.process_month(month_world, events))
	scheduler.monthly_systems.append(func(month_world: CampaignWorldState) -> void: FleetLogisticsSystemScript.process_month(month_world, events))
	var ai_definitions := AIDefinitionsScript.load_default()
	var naval_ai := NavalAISystemScript.new(scheduler, events, ai_definitions)
	scheduler.ai_hooks.append(func(ai_world: CampaignWorldState) -> void: naval_ai.process_day(ai_world))
	return {"world": world, "events": events, "scheduler": scheduler, "naval_ai": naval_ai}


func _cleanup(simulation: Dictionary) -> void:
	var scheduler: SimulationScheduler = simulation["scheduler"]
	scheduler.ai_hooks.clear()
	var events: SimulationEventBus = simulation["events"]
	if is_instance_valid(events):
		events.queue_free()


## A stringified fingerprint of every authoritative registry a naval-AI
## decision could plausibly influence, plus each maritime country's own
## runtime state with its "naval_ai" trace sub-dictionary explicitly
## stripped out first - the one part of country_runtime this test expects
## to genuinely differ between a tracing and a non-tracing run, and the
## only part. Uses CampaignWorldState's own _canonical_variant() so the
## comparison is exactly as deterministic/sorted as checksum() itself.
func _gameplay_fingerprint(world: CampaignWorldState) -> String:
	var parts: Array[String] = [
		"fleets=%s" % world._canonical_variant(world.fleet_registry),
		"ships=%s" % world._canonical_variant(world.ship_registry),
		"naval_construction=%s" % world._canonical_variant(world.naval_construction_registry),
		"transport_operations=%s" % world._canonical_variant(world.transport_operation_registry),
		"naval_battles=%s" % world._canonical_variant(world.naval_battle_registry),
		"wars=%s" % world._canonical_variant(world.war_registry),
		"blockaded_provinces=%s" % world._canonical_variant(world.blockaded_provinces),
	]
	var tags := MARITIME_COUNTRIES.duplicate()
	tags.sort()
	for tag in tags:
		var runtime := world.country_runtime(tag).duplicate(true)
		runtime.erase("naval_ai")
		parts.append("runtime[%s]=%s" % [tag, world._canonical_variant(runtime)])
	return "\n".join(parts)


func _run() -> void:
	var traced := _make_simulation(14441111, true)
	var untraced := _make_simulation(14441111, false)
	var traced_world: CampaignWorldState = traced["world"]
	var untraced_world: CampaignWorldState = untraced["world"]
	var traced_naval_ai: NavalAISystem = traced["naval_ai"]
	var untraced_naval_ai: NavalAISystem = untraced["naval_ai"]

	for day in SIMULATED_DAYS:
		traced["scheduler"].advance_one_day()
		untraced["scheduler"].advance_one_day()

	for tag in MARITIME_COUNTRIES:
		_check(not traced_world.country_ships(tag).is_empty(), "FIXTURE_TRACED_NO_SHIPS", "fixture assumption: %s must have built at least one ship in the traced run" % tag)
		_check(not untraced_world.country_ships(tag).is_empty(), "FIXTURE_UNTRACED_NO_SHIPS", "fixture assumption: %s must have built at least one ship in the untraced run" % tag)

	# The counters are not trace content - both runs must count identically.
	for counter in ["naval_ai_decisions", "naval_ai_commands_submitted", "naval_ai_candidates_evaluated"]:
		var traced_value := int(traced_world.global_counters.get(counter, -1))
		var untraced_value := int(untraced_world.global_counters.get(counter, -2))
		_check(traced_value > 0, "COUNTER_NEVER_INCREMENTED", "fixture assumption: %s must have actually incremented in the traced run" % counter)
		_check(traced_value == untraced_value, "COUNTER_DIFFERS_WITH_TRACING", "%s must be identical whether or not tracing is enabled - it is a counter, not trace content: traced=%d untraced=%d" % [counter, traced_value, untraced_value])

	# The toggle must be a genuine switch, not a no-op.
	for tag in MARITIME_COUNTRIES:
		var traced_snapshot := traced_naval_ai.debug_snapshot(traced_world, tag)
		var untraced_snapshot := untraced_naval_ai.debug_snapshot(untraced_world, tag)
		_check(not (traced_snapshot.get("decision_history", []) as Array).is_empty(), "TRACING_ON_PRODUCED_NO_TRACE", "%s must have a real, non-empty decision history when tracing is enabled" % tag)
		_check((untraced_snapshot.get("decision_history", []) as Array).is_empty(), "TRACING_OFF_STILL_PRODUCED_TRACE", "%s must have an empty decision history when tracing is disabled, not a silently-populated one: got %d entries" % [tag, (untraced_snapshot.get("decision_history", []) as Array).size()])
		_check((untraced_snapshot.get("rejected_candidates", []) as Array).is_empty(), "TRACING_OFF_STILL_RECORDED_REJECTIONS", "%s must have empty rejected_candidates when tracing is disabled: got %d entries" % [tag, (untraced_snapshot.get("rejected_candidates", []) as Array).size()])

	# The actual claim: every authoritative, gameplay-relevant registry must
	# be byte-identical whether or not the AI recorded its own reasoning
	# about how it got there.
	var traced_fingerprint := _gameplay_fingerprint(traced_world)
	var untraced_fingerprint := _gameplay_fingerprint(untraced_world)
	_check(traced_fingerprint == untraced_fingerprint, "TRACE_PRODUCTION_CHANGED_AUTHORITATIVE_RESULTS", "every fleet/ship/construction/transport/battle/war/blockade record and non-trace runtime field must be identical with tracing on vs off")

	_cleanup(traced)
	_cleanup(untraced)
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval AI trace neutrality test failed: %s" % failure)
		print("Naval AI trace neutrality test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval AI trace neutrality test passed. days=%d" % SIMULATED_DAYS)
	quit(0)
