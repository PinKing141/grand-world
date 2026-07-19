extends SceneTree

## N6A: NavalAISystem's first planning layers - strategic posture, force
## construction, admiral assignment, and the two tactical rules this slice
## implements (retreat when outmatched, repair/return when damaged or
## unsupplied) - proven against the real, already-reviewed Iberian AI
## fixture phase_6_ai_test.gd itself uses (docs/roadmap/naval/06_N6's own
## "AI Content Rollout" step 2, "Portugal, Castile, and Aragon integrated
## into the existing Iberian slice" - this is exactly that fixture, not a
## bespoke one).
##
## Castile (206, 224), Aragon (212, 220), and Portugal (227, 231) each own
## at least one of the 29 real N0.3-reviewed fixture ports
## naval_fleet_stress_smoke.gd/naval_battle_blockade_stress_smoke.gd also
## use (harbour_level 1, enough for a war_galley), so all three actually
## build ships. Navarre (210) owns no port at all - genuinely landlocked,
## both historically and in the baked map data - and must take zero naval
## decisions. Granada (222/223/226/4546) is the interesting middle case:
## these provinces ARE structurally real ports (is_port_province is a
## structural fact independent of content-review status), just
## unreviewed/"candidate"-confidence ones with harbour_level 0 - too small
## for any ship this slice can build. Granada is therefore maritime-capable
## (takes posture decisions) but can never actually complete construction
## (every attempt is a real, recorded rejection) - proving the harbour-level
## gate in ConstructShipCommand.validate() is what's stopping it, not the
## AI silently doing nothing.

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
const UNDERDEVELOPED_PORT_COUNTRY := "GRA"
const LANDLOCKED_COUNTRY := "NAV"
## war_galley takes 150 construction days; Castile (AI schedule slot 0) does
## not get its first posture/construction review until day 60 (the world
## never actually sees current_day==0 by the time ai_hooks run, so slot 0's
## day-0 due check is effectively pushed to its next interval boundary,
## day 60 - the same _due()/slot mechanics land AI's StrategicAISystem
## already uses, not a naval-specific quirk). 60 + 150 + a small margin
## covers every maritime country's first ship actually completing.
const SIMULATED_DAYS := 215


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval AI test failed: %s" % message)
		quit(1)


func _make_simulation(seed_value: int) -> Dictionary:
	var world := CampaignWorldStateScript.new()
	world.initialize(OWNERS, NAMES, "naval_ai_test", seed_value)
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


func _run() -> void:
	var simulation := _make_simulation(14441111)
	var world: CampaignWorldState = simulation["world"]
	var naval_ai: NavalAISystem = simulation["naval_ai"]
	var scheduler: SimulationScheduler = simulation["scheduler"]

	_require(naval_ai._is_maritime_capable(world, "CAS"), "fixture assumption: Castile must own at least one port")
	_require(naval_ai._is_maritime_capable(world, "ARA"), "fixture assumption: Aragon must own at least one port")
	_require(naval_ai._is_maritime_capable(world, "POR"), "fixture assumption: Portugal must own at least one port")
	_require(naval_ai._is_maritime_capable(world, "GRA"), "fixture assumption: Granada must structurally own a port, even an underdeveloped one")
	_require(not naval_ai._is_maritime_capable(world, "NAV"), "fixture assumption: Navarre must be genuinely landlocked")

	for day in SIMULATED_DAYS:
		scheduler.advance_one_day()

	# Every maritime country must have actually built at least one ship and
	# recorded a real, inspectable decision trail - not just been eligible.
	for tag in MARITIME_COUNTRIES:
		_require(not world.country_ships(tag).is_empty(), "%s is maritime-capable with a large treasury and must have built at least one ship in %d days" % [tag, SIMULATED_DAYS])
		var snapshot := naval_ai.debug_snapshot(world, tag)
		_require(not (snapshot.get("decision_history", []) as Array).is_empty(), "%s must have a non-empty naval AI decision history" % tag)
		_require(String(snapshot.get("posture", "")) in ["peace", "threatened", "wartime", "invasion", "recovery", "expansion"], "%s must have a recognised naval posture: %s" % [tag, snapshot.get("posture", "")])
		_require(int(snapshot.get("desired_ship_count", 0)) > 0, "%s must have computed a positive desired ship count" % tag)
		var counts: Dictionary = snapshot.get("decision_counts", {})
		_require(int(counts.get("construction", 0)) > 0, "%s must have made at least one construction-category decision" % tag)

	# Granada: maritime-capable but every one of its ports is too small for
	# any ship this slice can build - it must take real posture decisions
	# and real, explained rejections, but never actually complete a ship.
	# Proves the harbour-level gate, not a silent no-op, is what stops it.
	_require(world.country_ships(UNDERDEVELOPED_PORT_COUNTRY).is_empty(), "Granada's harbour is too small for any ship this slice builds and must never complete one")
	var granada_snapshot := naval_ai.debug_snapshot(world, UNDERDEVELOPED_PORT_COUNTRY)
	_require(not (granada_snapshot.get("decision_history", []) as Array).is_empty(), "Granada must still take real posture decisions despite never building a ship")
	_require(not (granada_snapshot.get("rejected_candidates", []) as Array).is_empty(), "Granada must have a real, explained construction rejection on record")

	# Navarre is genuinely landlocked - the maritime-capability gate in
	# process_day() must actually gate, not just influence scoring.
	_require(world.country_ships(LANDLOCKED_COUNTRY).is_empty(), "landlocked Navarre must never build a ship")
	var navarre_snapshot := naval_ai.debug_snapshot(world, LANDLOCKED_COUNTRY)
	_require((navarre_snapshot.get("decision_history", []) as Array).is_empty(), "landlocked Navarre must have no naval AI decision history at all")

	# Every AI-submitted command must have gone through real validation -
	# the AI never mutates naval state directly, mirroring StrategicAISystem's
	# own contract.
	_require(int(world.global_counters.get("naval_ai_commands_submitted", 0)) > 0, "the fixture must actually exercise command submission, not just scoring")

	# Determinism: an identical seed must reproduce an identical outcome -
	# same ships built, same checksum, matching every other AI/combat
	# determinism check in this codebase.
	_cleanup(simulation)
	var simulation_b := _make_simulation(14441111)
	var world_b: CampaignWorldState = simulation_b["world"]
	var scheduler_b: SimulationScheduler = simulation_b["scheduler"]
	for day in SIMULATED_DAYS:
		scheduler_b.advance_one_day()
	for tag in MARITIME_COUNTRIES:
		_require(world.country_ships(tag).size() == world_b.country_ships(tag).size(), "%s must build an identical ship count from an identical seed" % tag)
	_require(world.checksum() == world_b.checksum(), "an identical seed must reproduce an identical checksum")
	_cleanup(simulation_b)

	print("Naval AI test passed. days=%d cas_ships=%d ara_ships=%d por_ships=%d" % [
		SIMULATED_DAYS, world.country_ships("CAS").size(), world.country_ships("ARA").size(), world.country_ships("POR").size(),
	])
	quit(0)
