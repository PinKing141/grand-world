extends SceneTree

## FL3 "Automated verification": "Global planning work is bounded and meets
## its measured budget" - the last of the four untested claims
## FL3_CLOSURE_AUDIT.md recorded, deliberately last per its own recommended
## order: split/transfer (FL3.3), event-triggered replanning (FL3.4), and
## escort lifecycle (FL3.5) all now landed and are no longer expected to
## change planning cost further, so this measurement will not be
## immediately stale.
##
## NavalAISystem.process_day() only ever visits AIDefinitions' own real
## country roster - the existing 215-day naval_ai_test.gd fixture already
## proves correctness there, but its 5-country real Iberian roster is not a
## genuinely "global" scale to measure against. AIDefinitions.from_data()
## builds a synthetic 20-country roster instead, each a real N0.3 fixture
## port from the same FIXTURE_PORTS list naval_fleet_stress_smoke.gd/
## naval_battle_blockade_stress_smoke.gd already use, spread across every
## schedule slot so posture/construction/organisation/tactical/transport
## planning all genuinely fire across the run rather than only tactical's
## own short 5-day interval.
##
## Only NavalAISystem.process_day()'s own wall-clock time is measured, not
## the whole scheduler tick - FleetMovementSystem/NavalCombatSystem/
## BlockadeSystem's own cost is already budgeted separately by the existing
## stress smokes; this isolates naval AI planning specifically, matching
## the roadmap's own "global planning work" wording.
##
## The budget below is a conservative smoke-test guard, NOT an approved N0
## numerical performance budget (matching every other stress smoke's own
## framing in this project) - it catches an accidental O(n^2) regression,
## it does not certify a release-quality target.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const FleetLogisticsSystemScript = preload("res://scripts/simulation/fleet_logistics_system.gd")
const FleetMissionSystemScript = preload("res://scripts/simulation/fleet_mission_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")

const FIXTURE_PORTS := [87, 89, 90, 167, 168, 197, 206, 207, 209, 212, 213, 220, 224, 227, 229, 230, 231, 233, 235, 333]
const COUNTRY_COUNT := 20
const SIMULATED_DAYS := 65
## Measured ~6.85s for this exact fixture on the development machine this
## budget was set on (a resource-constrained laptop, not representative
## target hardware) - a ~4.4x margin above that, matching this project's
## own "generous conservative guard, not a tight bound" precedent
## (naval_fleet_stress_smoke.gd's own 15s guard over a measured ~3.7s).
const AI_PLANNING_BUDGET_MS := 30000.0


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval AI performance smoke failed: %s" % message)
		quit(1)


func _country_tag(index: int) -> String:
	return "Z%02d" % index


func _make_ai_definitions() -> AIDefinitions:
	var countries := {}
	for index in COUNTRY_COUNT:
		var tag := _country_tag(index)
		countries[tag] = {
			"slot": index,
			"capital_province_id": FIXTURE_PORTS[index % FIXTURE_PORTS.size()],
			"strategy": "balanced",
			"objective": "expand",
			"government": "monarchy",
			"ruler": "Test Ruler %d" % index,
			"minimum_reserve": 50000,
		}
	return AIDefinitionsScript.from_data({
		"version": 1,
		"slice_id": "naval_ai_performance_smoke",
		"start_day": 0,
		"end_day": 7305,
		"countries": countries,
	})


func _make_world() -> CampaignWorldState:
	var owners := {}
	for index in COUNTRY_COUNT:
		owners[FIXTURE_PORTS[index % FIXTURE_PORTS.size()]] = _country_tag(index)
	var names := {}
	for index in COUNTRY_COUNT:
		names[_country_tag(index)] = "Test Country %d" % index
	var world := CampaignWorldStateScript.new()
	world.initialize(owners, names, "naval_ai_performance_smoke", 14441111)
	EconomySystemScript.initialize_world(world)
	for index in COUNTRY_COUNT:
		var tag := _country_tag(index)
		var runtime := world.country_runtime(tag)
		runtime["treasury"] = 200000
		runtime["sailors"] = 2000
		world.set_country_runtime(tag, runtime)
	# Deliberately no starting fleets: with one port each, desired_ship_count
	# is 1 at the peacetime multiplier - starting with any ship already
	# built would make _plan_construction() see "fleet_sufficient" on its
	# very first tick for every country and never actually build anything,
	# understating real AI cost by skipping the one genuinely expensive
	# path (family/port selection, sailor/treasury checks, command
	# construction, validation, and application) this measurement exists
	# to capture. Starting empty means every country's own first
	# construction tick does real work.
	return world


func _run() -> void:
	var definitions := _make_ai_definitions()
	_require(definitions.is_valid(), "the synthetic AI roster itself must validate: %s" % definitions.error())
	_require(definitions.country_tags().size() == COUNTRY_COUNT, "fixture assumption: every synthetic country must register")

	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: FleetMovementSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: NavalCombatSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: BlockadeSystemScript.process_day(day_world, events))
	# EconomySystem.process_day() is what actually completes queued naval
	# construction (_complete_naval_construction()) - without it, every
	# ConstructShipCommand this fixture submits would sit in
	# naval_construction_registry forever and no ship would ever really
	# exist, understating both real AI cost and the whole point of this
	# measurement. Mirrors naval_ai_test.gd's own real scheduler wiring.
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: EconomySystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: FleetLogisticsSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: TransportSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: FleetMissionSystemScript.process_day(day_world, events))
	var naval_ai := NavalAISystemScript.new(scheduler, events, definitions)
	# Deliberately NOT wired through scheduler.ai_hooks: a GDScript lambda
	# captures outer local variables by value at creation time, not by
	# reference, so an accumulator mutated *inside* a repeatedly-invoked
	# ai_hooks closure never actually updates the ai_elapsed_usec declared
	# out here - a real bug caught by this measurement reading back as an
	# implausible 0.00ms on the first attempt, not assumed correct.
	# Calling process_day() directly, right after the day's own
	# advance_one_day() (the same point in the day ai_hooks would have run
	# it), sidesteps the closure entirely; a manual process_commands() call
	# keeps command application on the same day rather than lagging by one.
	var ai_elapsed_usec := 0
	for day in SIMULATED_DAYS:
		scheduler.advance_one_day()
		var started := Time.get_ticks_usec()
		naval_ai.process_day(world)
		ai_elapsed_usec += Time.get_ticks_usec() - started
		scheduler.process_commands()

	var ai_elapsed_ms := float(ai_elapsed_usec) / 1000.0
	_require(
		ai_elapsed_ms <= AI_PLANNING_BUDGET_MS,
		"%d days of naval AI planning across %d countries must complete within %.1f ms; measured %.2f ms" % [SIMULATED_DAYS, COUNTRY_COUNT, AI_PLANNING_BUDGET_MS, ai_elapsed_ms]
	)

	# A real correctness floor, not just a timing measurement - a budget
	# met by an AI that silently did nothing would be worthless.
	var countries_with_decisions := 0
	for index in COUNTRY_COUNT:
		var tag := _country_tag(index)
		var snapshot := naval_ai.debug_snapshot(world, tag)
		if not (snapshot.get("decision_history", []) as Array).is_empty():
			countries_with_decisions += 1
	_require(countries_with_decisions == COUNTRY_COUNT, "every one of the %d maritime-capable synthetic countries must have taken at least one real decision, not just been fast because it did nothing: got %d" % [COUNTRY_COUNT, countries_with_decisions])
	_require(int(world.global_counters.get("naval_ai_countries_planned", 0)) > 0, "the countries-planned counter must reflect genuine planning work")
	# war_galley takes 150 construction days (matching naval_ai_test.gd's own
	# comment) - far longer than this fixture's 65-day span, so a queued
	# order, not a completed ship, is the correct achievable proof that
	# real construction logic (family/port selection, sailor/treasury
	# checks, command validation and application) actually ran, not just a
	# bookkeeping rejection. Each country also submits exactly one real
	# SetNavyMaintenanceCommand (FL3.2's own maintenance-posture adjustment,
	# peacetime here since this fixture starts no war) - 2 real commands
	# per country, not 1, now that both are genuinely exercised.
	_require(int(world.global_counters.get("naval_ai_commands_submitted", 0)) == COUNTRY_COUNT * 2, "every one of the %d countries must have submitted exactly one real ConstructShipCommand and one real SetNavyMaintenanceCommand: got %d submitted commands" % [COUNTRY_COUNT, int(world.global_counters.get("naval_ai_commands_submitted", 0))])
	_require(world.naval_construction_registry.size() == COUNTRY_COUNT, "every country's queued construction order must be a real, live naval_construction_registry entry, not just a counted-but-discarded command: got %d entries" % world.naval_construction_registry.size())

	print("Naval AI performance smoke passed. countries=%d days=%d ai_elapsed_ms=%.2f decisions=%d commands=%d" % [
		COUNTRY_COUNT, SIMULATED_DAYS, ai_elapsed_ms,
		int(world.global_counters.get("naval_ai_decisions", 0)), int(world.global_counters.get("naval_ai_commands_submitted", 0)),
	])
	quit(0)
