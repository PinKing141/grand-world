extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const WarfareSystemScript = preload("res://scripts/simulation/warfare_system.gd")
const CharacterDefinitionsScript = preload("res://scripts/simulation/character_definitions.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
const CountryDepthAISystemScript = preload("res://scripts/simulation/country_depth_ai_system.gd")

const OWNERS := {
	206: "CAS", 215: "CAS", 217: "CAS", 219: "CAS", 224: "CAS", 225: "CAS",
	211: "ARA", 212: "ARA", 214: "ARA", 220: "ARA",
	227: "POR", 228: "POR", 231: "POR",
	222: "GRA", 223: "GRA", 226: "GRA", 4546: "GRA", 210: "NAV",
}
const NAMES := {"CAS": "Castile", "ARA": "Aragon", "POR": "Portugal", "GRA": "Granada", "NAV": "Navarre", "SPA": "Spain"}
const TARGET_DAY := 93262 # Replaced at runtime by SimulationDate.date_to_day(1700, 1, 1).


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 8 1444-1700 soak failed: %s" % message)
		quit(1)


func _make_simulation() -> Dictionary:
	var world := CampaignWorldStateScript.new()
	world.initialize(OWNERS, NAMES, "phase8_alpha_soak", 14441111)
	var economy = EconomyDefinitionsScript.load_default()
	EconomySystemScript.initialize_world(world, economy)
	WarfareSystemScript.initialize_armies(world)
	var character_definitions := CharacterDefinitionsScript.load_default()
	CharacterSystemScript.initialize_world(world, character_definitions)
	var depth_definitions := CountryDepthDefinitionsScript.load_default()
	CountryDepthSystemScript.initialize_world(world, depth_definitions)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	var depth_ai := CountryDepthAISystemScript.new(scheduler, events, depth_definitions)
	return {
		"world": world, "events": events, "scheduler": scheduler, "ai": depth_ai,
		"economy": economy, "characters": character_definitions, "depth": depth_definitions,
	}


func _advance_one_month(simulation: Dictionary) -> void:
	var world: CampaignWorldState = simulation["world"]
	var current := SimulationDateScript.day_to_date(world.current_day)
	var next_month := int(current["month"]) + 1
	var next_year := int(current["year"])
	if next_month > 12:
		next_month = 1
		next_year += 1
	world.current_day = mini(SimulationDateScript.date_to_day(next_year, next_month, 1), SimulationDateScript.date_to_day(1700, 1, 1))
	CharacterSystemScript.process_month(world, simulation["events"])
	CountryDepthSystemScript.process_month(world, simulation["events"], simulation["depth"])
	(simulation["ai"] as CountryDepthAISystem).process_month(world)
	(simulation["scheduler"] as SimulationScheduler).process_commands()
	EconomySystemScript.process_month(world, simulation["events"], simulation["economy"])


func _advance_to_day(simulation: Dictionary, target_day: int) -> void:
	var world: CampaignWorldState = simulation["world"]
	while world.current_day < target_day:
		_advance_one_month(simulation)


func _validate_world(simulation: Dictionary) -> void:
	var world: CampaignWorldState = simulation["world"]
	var definitions: CountryDepthDefinitions = simulation["depth"]
	var cultures := definitions.cultures()
	var religions := definitions.religions()
	for province_id in world.province_states:
		var economy: Dictionary = world.province_states[province_id].get("economy", {})
		_require(cultures.has(String(economy.get("culture", ""))), "province %d must retain a valid culture" % int(province_id))
		_require(religions.has(String(economy.get("religion", ""))), "province %d must retain a valid religion" % int(province_id))
		_require(int(economy.get("control_bp", -1)) in range(0, 10001), "province control must stay within basis-point bounds")
		_require(int(economy.get("unrest_bp", -1)) in range(0, 10001), "province unrest must stay within basis-point bounds")
	for raw_id in world.subject_registry:
		var record: Dictionary = world.subject_registry[raw_id]
		_require(world.has_country(String(record.get("overlord", ""))) and world.has_country(String(record.get("subject", ""))), "subjects must retain valid country references")
	for tag in definitions.country_tags():
		var runtime := world.country_runtime(tag)
		var technology: Dictionary = runtime.get("technology", {})
		for track in CountryDepthDefinitions.TECHNOLOGY_TRACKS:
			_require(int(technology.get(track, -1)) in range(0, 6), "%s technology must stay within authored levels" % track)
		_require((runtime.get("event_history", []) as Array).size() <= 64, "event histories must stay bounded")
		_require((runtime.get("country_depth_ai", {}).get("history", []) as Array).size() <= 16, "AI explanation histories must stay bounded")
	_require(int(world.country_runtime("CAS").get("technology", {}).get("administrative", 0)) >= 4, "the 256-year campaign must demonstrate long-term technology progression")
	_require(not world.checksum().is_empty(), "the completed campaign needs a deterministic checksum")


func _cleanup(simulation: Dictionary) -> void:
	var events: SimulationEventBus = simulation.get("events")
	if is_instance_valid(events):
		events.free()
	simulation.clear()


func _run() -> void:
	var expected_target := SimulationDateScript.date_to_day(1700, 1, 1)
	_require(expected_target > 0, "1700 target date must be representable")
	var started := Time.get_ticks_usec()
	var first := _make_simulation()
	var checkpoint_day := SimulationDateScript.date_to_day(1600, 1, 1)
	_advance_to_day(first, checkpoint_day)
	var checkpoint := (first["world"] as CampaignWorldState).to_save_dict("phase8-soak-checkpoint")
	var second := _make_simulation()
	_require((second["world"] as CampaignWorldState).apply_save_dict(checkpoint).is_empty(), "the 1600 deterministic replay checkpoint must load")
	_advance_to_day(first, expected_target)
	_advance_to_day(second, expected_target)
	var first_world: CampaignWorldState = first["world"]
	var second_world: CampaignWorldState = second["world"]
	_require(first_world.current_day == expected_target, "campaign must reach 1 January 1700")
	_require(first_world.checksum() == second_world.checksum(), "two identical 1444-1700 campaigns must finish byte-identically")
	_validate_world(first)
	_validate_world(second)
	var save := first_world.to_save_dict("phase8-soak")
	var loaded := _make_simulation()
	_require((loaded["world"] as CampaignWorldState).apply_save_dict(save).is_empty(), "the completed 1700 campaign must load")
	_require((loaded["world"] as CampaignWorldState).checksum() == first_world.checksum(), "the 1700 save must round-trip exactly")
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	_require(elapsed_ms < 90000.0, "the 256-year campaign plus century replay must stay within 90 seconds")
	print("Phase 8 1444-1700 soak passed in %.2f ms. checksum=%s" % [elapsed_ms, first_world.checksum().left(16)])
	_cleanup(first)
	_cleanup(second)
	_cleanup(loaded)
	quit(0)
