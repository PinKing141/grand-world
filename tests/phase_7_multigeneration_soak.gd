extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const WarfareSystemScript = preload("res://scripts/simulation/warfare_system.gd")
const CharacterDefinitionsScript = preload("res://scripts/simulation/character_definitions.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const CharacterAISystemScript = preload("res://scripts/simulation/character_ai_system.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")

const YEARS := 100
const SOAK_MONTHS := YEARS * 12
const OWNERS := {
	206: "CAS", 215: "CAS", 217: "CAS", 219: "CAS", 224: "CAS", 225: "CAS",
	211: "ARA", 212: "ARA", 214: "ARA", 220: "ARA", 227: "POR", 228: "POR", 231: "POR",
	222: "GRA", 223: "GRA", 226: "GRA", 4546: "GRA", 210: "NAV",
}
const NAMES := {"CAS": "Castile", "ARA": "Aragon", "POR": "Portugal", "GRA": "Granada", "NAV": "Navarre"}


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 7 multi-generation soak failed: %s" % message)
		quit(1)


func _make_simulation() -> Dictionary:
	var world := CampaignWorldStateScript.new()
	world.initialize(OWNERS, NAMES, "phase7_multigeneration", 14441111)
	var economy = EconomyDefinitionsScript.load_default()
	EconomySystemScript.initialize_world(world, economy)
	WarfareSystemScript.initialize_armies(world)
	var definitions := CharacterDefinitionsScript.load_default()
	CharacterSystemScript.initialize_world(world, definitions)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	var ai := CharacterAISystemScript.new(scheduler, events)
	scheduler.monthly_systems.append(func(month_world: CampaignWorldState) -> void:
		CharacterSystemScript.process_month(month_world, events)
		ai.process_month(month_world)
		EconomySystemScript.process_month(month_world, events, economy))
	return {"world": world, "events": events, "scheduler": scheduler, "ai": ai}


func _validate_references(world: CampaignWorldState) -> void:
	for raw_id in world.character_registry:
		var character_id := String(raw_id)
		var character: Dictionary = world.character_registry[raw_id]
		for field in ["father_id", "mother_id", "spouse_id"]:
			var reference := String(character.get(field, ""))
			_require(reference.is_empty() or world.character_registry.has(reference), "%s has invalid %s" % [character_id, field])
		var spouse := String(character.get("spouse_id", ""))
		if not spouse.is_empty():
			_require(String((world.character_registry[spouse] as Dictionary).get("spouse_id", "")) == character_id, "%s marriage is asymmetric" % character_id)
		for raw_child in character.get("children", []):
			_require(world.character_registry.has(String(raw_child)), "%s has an invalid child" % character_id)
	for raw_id in world.dynasty_registry:
		for raw_member in (world.dynasty_registry[raw_id] as Dictionary).get("living_members", []):
			_require(world.character_registry.has(String(raw_member)) and bool((world.character_registry[String(raw_member)] as Dictionary).get("alive", false)), "%s has an invalid living-member index" % String(raw_id))
	for raw_id in world.title_registry:
		var holder := String((world.title_registry[raw_id] as Dictionary).get("holder_id", ""))
		_require(world.character_registry.has(holder) and bool((world.character_registry[holder] as Dictionary).get("alive", false)), "%s must retain a living holder" % String(raw_id))
	for tag in NAMES:
		var ruler := CharacterSystemScript.ruler_id(world, String(tag))
		_require(world.character_registry.has(ruler) and bool((world.character_registry[ruler] as Dictionary).get("alive", false)), "%s must retain a living ruler" % String(tag))


func _advance_months(simulation: Dictionary, month_count: int) -> void:
	var world: CampaignWorldState = simulation["world"]
	var scheduler: SimulationScheduler = simulation["scheduler"]
	for month_index in range(month_count):
		var date := SimulationDateScript.day_to_date(world.current_day)
		var next_year := int(date["year"])
		var next_month := int(date["month"]) + 1
		if next_month > 12:
			next_month = 1
			next_year += 1
		world.current_day = SimulationDateScript.date_to_day(next_year, next_month, 1)
		for system in scheduler.monthly_systems:
			system.call(world)
		scheduler.process_commands()


func _cleanup(simulation: Dictionary) -> void:
	var scheduler: SimulationScheduler = simulation.get("scheduler")
	if scheduler != null:
		scheduler.monthly_systems.clear()
	var events: SimulationEventBus = simulation.get("events")
	if is_instance_valid(events):
		events.free()
	simulation.clear()


func _run() -> void:
	var simulation := _make_simulation()
	var world: CampaignWorldState = simulation["world"]
	var scheduler: SimulationScheduler = simulation["scheduler"]
	var counts := {"births": 0, "deaths": 0, "successions": 0, "marriages": 0, "illnesses": 0}
	var events: SimulationEventBus = simulation["events"]
	events.character_born.connect(func(_id: String, _mother: String, _father: String) -> void: counts["births"] = int(counts["births"]) + 1)
	events.character_died.connect(func(_id: String, _cause: String, _day: int) -> void: counts["deaths"] = int(counts["deaths"]) + 1)
	events.succession_resolved.connect(func(_country: String, _old: String, _new: String, _heir: String) -> void: counts["successions"] = int(counts["successions"]) + 1)
	events.character_married.connect(func(_first: String, _second: String) -> void: counts["marriages"] = int(counts["marriages"]) + 1)
	events.character_became_ill.connect(func(_id: String, _illness: String, _until: int) -> void: counts["illnesses"] = int(counts["illnesses"]) + 1)

	_advance_months(simulation, SOAK_MONTHS / 2)
	var midpoint_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_validate_references(world)
	var midpoint_save := world.to_save_dict("phase7-soak")
	var replay := _make_simulation()
	var replay_world: CampaignWorldState = replay["world"]
	_require(replay_world.apply_save_dict(midpoint_save).is_empty(), "a fifty-year family state must load")
	var replay_scheduler: SimulationScheduler = replay["scheduler"]
	_advance_months(simulation, 120)
	_advance_months(replay, 120)
	_require(world.checksum() == replay_world.checksum(), "save/load must preserve ten further years of family AI and succession exactly")
	_cleanup(replay)
	_advance_months(simulation, SOAK_MONTHS / 2 - 120)
	var end_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_validate_references(world)

	_require(int(SimulationDateScript.day_to_date(world.current_day)["year"]) == 1544, "the autonomous family campaign must complete one hundred years")
	_require(int(counts["births"]) >= 10, "the soak must create multiple generations")
	_require(int(counts["deaths"]) >= 10, "the soak must exercise natural death repeatedly")
	_require(int(counts["successions"]) >= 5, "the soak must exercise multiple country successions")
	_require(int(counts["marriages"]) >= 5, "character AI must arrange repeated valid marriages")
	_require(int(counts["illnesses"]) >= 1, "the health system must produce representative illness events")
	for raw_tag in NAMES:
		var ai_state: Dictionary = world.country_runtime(String(raw_tag)).get("character_ai", {})
		_require((ai_state.get("decisions", []) as Array).size() <= 16, "%s character AI history must remain bounded" % String(raw_tag))
	_require(end_memory <= midpoint_memory + 32 * 1024 * 1024, "second-half memory growth must stay within 32 MiB")

	var saved := world.to_save_dict("phase7-soak")
	var loaded := _make_simulation()
	var loaded_world: CampaignWorldState = loaded["world"]
	_require(loaded_world.apply_save_dict(saved).is_empty() and loaded_world.checksum() == world.checksum(), "the final multi-generation state must round-trip exactly")
	_cleanup(loaded)
	print("Phase 7 hundred-year multi-generation soak passed. characters=%d births=%d deaths=%d successions=%d marriages=%d memory_delta=%.2fMiB checksum=%s" % [
		world.character_registry.size(), int(counts["births"]), int(counts["deaths"]), int(counts["successions"]), int(counts["marriages"]),
		(end_memory - midpoint_memory) / 1048576.0, world.checksum().left(16),
	])
	_cleanup(simulation)
	quit(0)
