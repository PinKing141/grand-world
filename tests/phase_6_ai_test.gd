extends SceneTree

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBus = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationScheduler = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const ArmyMovementSystemScript = preload("res://scripts/simulation/army_movement_system.gd")
const WarfareSystemScript = preload("res://scripts/simulation/warfare_system.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const StrategicAISystemScript = preload("res://scripts/simulation/strategic_ai_system.gd")
const CampaignGoalSystemScript = preload("res://scripts/simulation/campaign_goal_system.gd")

const OWNERS := {
	206: "CAS", 215: "CAS", 217: "CAS", 219: "CAS", 224: "CAS", 225: "CAS",
	211: "ARA", 212: "ARA", 214: "ARA", 220: "ARA",
	227: "POR", 228: "POR", 231: "POR",
	222: "GRA", 223: "GRA", 226: "GRA", 4546: "GRA",
	210: "NAV",
}
const NAMES := {"CAS": "Castile", "ARA": "Aragon", "POR": "Portugal", "GRA": "Granada", "NAV": "Navarre"}


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 6 AI test failed: %s" % message)
		quit(1)


func _make_simulation() -> Dictionary:
	var world := CampaignWorldState.new()
	world.initialize(OWNERS, NAMES, "iberia_ai_test", 14441111)
	world.global_flags["enforce_military_access"] = true
	var economy = EconomyDefinitionsScript.load_default()
	EconomySystemScript.initialize_world(world, economy)
	WarfareSystemScript.initialize_armies(world)
	var events := SimulationEventBus.new()
	root.add_child(events)
	var scheduler := SimulationScheduler.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: ArmyMovementSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: WarfareSystemScript.advance_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: EconomySystemScript.process_day(day_world, events, economy))
	scheduler.monthly_systems.append(func(month_world: CampaignWorldState) -> void: EconomySystemScript.process_month(month_world, events, economy))
	var ai_definitions := AIDefinitionsScript.load_default()
	var ai := StrategicAISystemScript.new(scheduler, events, ai_definitions)
	ai.initialize_world(world)
	CampaignGoalSystemScript.initialize_world(world, ai_definitions)
	scheduler.ai_hooks.append(func(ai_world: CampaignWorldState) -> void:
		CampaignGoalSystemScript.process_day(ai_world, events, ai_definitions)
		ai.process_day(ai_world))
	return {"world": world, "events": events, "scheduler": scheduler, "ai": ai, "definitions": ai_definitions}


func _command_types(scheduler: SimulationScheduler) -> Dictionary:
	var counts := {}
	for record in scheduler.command_history:
		var type := String(record.get("type", ""))
		counts[type] = int(counts.get(type, 0)) + 1
	return counts


func _cleanup_simulation(simulation: Dictionary) -> void:
	var scheduler: SimulationScheduler = simulation.get("scheduler")
	if scheduler != null:
		scheduler.ai_hooks.clear()
	var events: SimulationEventBus = simulation.get("events")
	if is_instance_valid(events):
		events.free()
	simulation.clear()


func _run() -> void:
	var definitions := AIDefinitionsScript.load_default()
	_require(definitions.is_valid(), "AI definitions must validate: %s" % definitions.error())
	_require(definitions.country_tags() == ["ARA", "CAS", "GRA", "NAV", "POR"], "the slice roster must be stable and sorted")
	var malformed := {
		"version": 1, "slice_id": "broken", "start_day": 0, "end_day": 30,
		"countries": {
			"AAA": {"slot": 0, "capital_province_id": 1, "strategy": "test", "objective": "test", "government": "test", "ruler": "test"},
			"BBB": {"slot": 0, "capital_province_id": 2, "strategy": "test", "objective": "test", "government": "test", "ruler": "test"},
		},
	}
	_require(not AIDefinitionsScript.from_data(malformed).is_valid(), "schema validation must reject duplicate AI schedule slots")

	var first := _make_simulation()
	var world: CampaignWorldState = first["world"]
	var scheduler: SimulationScheduler = first["scheduler"]
	var ai: StrategicAISystem = first["ai"]
	for tag in definitions.country_tags():
		_require((world.country_runtime(tag).get("ai", {}) as Dictionary).get("enabled", false), "%s needs persistent AI state" % tag)
	_require(bool(world.global_flags.get("ai_enabled", false)), "the regional AI must be enabled")
	_require(String(world.global_flags.get("vertical_slice_id", "")) == definitions.slice_id(), "campaign goals must identify the slice")

	scheduler.advance_days(420)
	var counts := _command_types(scheduler)
	_require(int(counts.get("SetArmyMaintenanceCommand", 0)) > 0, "economic AI must manage maintenance")
	_require(int(counts.get("RequestMilitaryAccessCommand", 0)) > 0, "diplomatic AI must request useful access")
	_require(int(counts.get("GrantMilitaryAccessCommand", 0)) > 0, "friendly AI must answer access requests")
	_require(int(counts.get("ImproveRelationsCommand", 0)) > 0, "AI must improve relations toward a preferred alliance")
	_require(int(counts.get("DeclareWarCommand", 0)) > 0, "Castile must be able to declare its strength-gated conquest war")
	_require(int(counts.get("MoveArmyCommand", 0)) > 0, "military AI must issue graph-valid army orders")
	_require(int(world.global_counters.get("ai_decisions", 0)) > 0, "AI decisions must be counted deterministically")
	var castile_debug := ai.debug_snapshot(world, "CAS")
	_require(not String(castile_debug.get("goal", "")).is_empty(), "debug snapshots must expose the current goal")
	_require((castile_debug.get("decision_history", []) as Array).size() > 0, "debug snapshots must expose bounded decision history")
	_require(int(castile_debug.get("campaign_seed", 0)) == world.campaign_seed, "debug snapshots must expose deterministic seed information")
	_require(castile_debug.has("rejected_candidates"), "debug snapshots must expose rejected candidate reasons")

	# Save/load at the end of a fully processed AI day must preserve future AI.
	var saved := world.to_save_dict("phase6-test")
	var loaded_sim := _make_simulation()
	var loaded_world: CampaignWorldState = loaded_sim["world"]
	_require(loaded_world.apply_save_dict(saved).is_empty(), "AI campaign state must load")
	var loaded_ai: StrategicAISystem = loaded_sim["ai"]
	loaded_ai.ensure_world(loaded_world)
	var loaded_scheduler: SimulationScheduler = loaded_sim["scheduler"]
	for day in range(500):
		scheduler.advance_one_day()
		loaded_scheduler.advance_one_day()
	_require(world.checksum() == loaded_world.checksum(), "save/load must not alter future deterministic AI decisions")
	var final_counts := _command_types(scheduler)
	_require(int(final_counts.get("ConstructBuildingCommand", 0)) > 0, "economic AI must eventually invest surplus treasury in a scored building")

	# A fresh replay with the same seed and no player input must match exactly.
	var replay := _make_simulation()
	var replay_world: CampaignWorldState = replay["world"]
	var replay_scheduler: SimulationScheduler = replay["scheduler"]
	replay_scheduler.advance_days(world.current_day)
	_require(replay_world.checksum() == world.checksum(), "fixed-seed autonomous campaigns must replay to the same checksum")

	# Selecting a player country removes only that country from autonomous control.
	var player_run := _make_simulation()
	var player_world: CampaignWorldState = player_run["world"]
	var player_scheduler: SimulationScheduler = player_run["scheduler"]
	player_world.player_country = "CAS"
	player_scheduler.advance_days(120)
	for record in player_scheduler.command_history:
		_require(String(record.get("issuer", "")) != "CAS", "AI must never issue commands for the selected player country")

	var rejected := 0
	for record in scheduler.command_history:
		if not bool(record.get("accepted", false)):
			rejected += 1
	_require(rejected * 100 <= maxi(scheduler.command_history.size(), 1) * 15, "AI command rejection rate must stay at or below 15%%")
	print("Phase 6 AI test passed. day=%d commands=%s wars=%d checksum=%s" % [world.current_day, counts, world.war_registry.size(), world.checksum().left(16)])
	_cleanup_simulation(first)
	_cleanup_simulation(loaded_sim)
	_cleanup_simulation(replay)
	_cleanup_simulation(player_run)
	quit(0)
