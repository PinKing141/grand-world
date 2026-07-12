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
		push_error("Phase 6 regional soak failed: %s" % message)
		quit(1)


func _run() -> void:
	var definitions := AIDefinitionsScript.load_default()
	_require(definitions.is_valid(), "AI definitions must validate")
	var world := CampaignWorldState.new()
	world.initialize(OWNERS, NAMES, definitions.slice_id(), 14441111)
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
	var ai := StrategicAISystemScript.new(scheduler, events, definitions)
	ai.initialize_world(world)
	CampaignGoalSystemScript.initialize_world(world, definitions)
	scheduler.ai_hooks.append(func(ai_world: CampaignWorldState) -> void:
		CampaignGoalSystemScript.process_day(ai_world, events, definitions)
		ai.process_day(ai_world))

	var midpoint := definitions.end_day() / 2
	scheduler.advance_days(midpoint)
	var midpoint_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_require(String(world.global_flags.get("campaign_status", "")) == "running", "the campaign must remain active before its completion date")
	scheduler.advance_days(definitions.end_day() - midpoint)
	var end_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))

	_require(world.current_day == definitions.end_day(), "the unattended campaign must reach its configured twenty-year endpoint")
	_require(String(world.global_flags.get("campaign_status", "")) == "completed", "an observer campaign must complete cleanly")
	var summary: Dictionary = world.global_flags.get("campaign_summary", {})
	_require(int(summary.get("day", -1)) == definitions.end_day(), "campaign summary must record the completion day")
	_require((summary.get("countries", {}) as Dictionary).size() == 5, "campaign summary must retain all five slice countries")
	_require(int(world.global_counters.get("ai_decisions", 0)) >= 100, "the long run must contain sustained strategic decisions")
	_require(int(world.global_counters.get("ai_commands_submitted", 0)) >= 20, "the long run must contain sustained autonomous commands")

	var accepted := 0
	var rejected := 0
	var command_types := {}
	for record in scheduler.command_history:
		var command_type := String(record.get("type", ""))
		command_types[command_type] = int(command_types.get(command_type, 0)) + 1
		if bool(record.get("accepted", false)):
			accepted += 1
		else:
			rejected += 1
	_require(rejected * 100 <= maxi(accepted + rejected, 1) * 15, "AI command rejection rate must stay at or below 15%%")
	_require(int(command_types.get("DeclareWarCommand", 0)) > 0, "the soak must exercise autonomous war declarations")
	_require(int(command_types.get("MoveArmyCommand", 0)) > 0, "the soak must exercise autonomous military movement")
	_require(int(command_types.get("OfferPeaceCommand", 0)) > 0, "the soak must exercise autonomous peace negotiation")
	_require(int(command_types.get("ConstructBuildingCommand", 0)) > 0, "the soak must exercise autonomous economic investment")
	for tag in definitions.country_tags():
		var state: Dictionary = world.country_runtime(tag).get("ai", {})
		_require((state.get("decision_history", []) as Array).size() <= StrategicAISystemScript.MAX_DECISION_HISTORY, "%s decision history must remain bounded" % tag)
		_require((state.get("rejected_candidates", []) as Array).size() <= 8, "%s rejected-candidate history must remain bounded" % tag)
	# Command history grows by design for development diagnostics; persistent AI
	# caches must remain bounded and the allocator must not jump continuously.
	_require(end_memory <= midpoint_memory + 32 * 1024 * 1024, "second-half memory growth must stay below the 32 MiB soak budget")

	print("Phase 6 twenty-year regional soak passed. day=%d decisions=%d commands=%d memory_delta=%.2fMiB checksum=%s" % [
		world.current_day, int(world.global_counters.get("ai_decisions", 0)), scheduler.command_history.size(),
		(end_memory - midpoint_memory) / 1048576.0, world.checksum().left(16),
	])
	scheduler.ai_hooks.clear()
	events.free()
	quit(0)
