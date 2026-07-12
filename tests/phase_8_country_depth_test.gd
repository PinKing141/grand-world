extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const WarfareSystemScript = preload("res://scripts/simulation/warfare_system.gd")
const CharacterDefinitionsScript = preload("res://scripts/simulation/character_definitions.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const CountryDepthDefinitionsScript = preload("res://scripts/simulation/country_depth_definitions.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
const CountryDepthAISystemScript = preload("res://scripts/simulation/country_depth_ai_system.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const PeaceSystemScript = preload("res://scripts/simulation/peace_system.gd")
const IncreaseStabilityCommandScript = preload("res://scripts/simulation/commands/increase_stability_command.gd")
const AdvanceTechnologyCommandScript = preload("res://scripts/simulation/commands/advance_technology_command.gd")
const EnactGovernmentReformCommandScript = preload("res://scripts/simulation/commands/enact_government_reform_command.gd")
const SelectIdeaGroupCommandScript = preload("res://scripts/simulation/commands/select_idea_group_command.gd")
const StartProvinceConversionCommandScript = preload("res://scripts/simulation/commands/start_province_conversion_command.gd")
const AcceptCultureCommandScript = preload("res://scripts/simulation/commands/accept_culture_command.gd")
const SuppressRebelsCommandScript = preload("res://scripts/simulation/commands/suppress_rebels_command.gd")
const FabricateProvinceClaimCommandScript = preload("res://scripts/simulation/commands/fabricate_province_claim_command.gd")
const DeclareWarCommandScript = preload("res://scripts/simulation/commands/declare_war_command.gd")
const FormAllianceCommandScript = preload("res://scripts/simulation/commands/form_alliance_command.gd")
const CreateSubjectCommandScript = preload("res://scripts/simulation/commands/create_subject_command.gd")
const StartSubjectIntegrationCommandScript = preload("res://scripts/simulation/commands/start_subject_integration_command.gd")
const ChooseCountryEventOptionCommandScript = preload("res://scripts/simulation/commands/choose_country_event_option_command.gd")
const EnactCountryDecisionCommandScript = preload("res://scripts/simulation/commands/enact_country_decision_command.gd")
const ReleaseCountryCommandScript = preload("res://scripts/simulation/commands/release_country_command.gd")
const ConstructBuildingCommandScript = preload("res://scripts/simulation/commands/construct_building_command.gd")
const RecruitUnitCommandScript = preload("res://scripts/simulation/commands/recruit_unit_command.gd")

const OWNERS := {
	206: "CAS", 215: "CAS", 217: "CAS", 219: "CAS", 224: "CAS", 225: "CAS",
	211: "ARA", 212: "ARA", 214: "ARA", 220: "ARA",
	227: "POR", 228: "POR", 231: "POR",
	222: "GRA", 223: "GRA", 226: "GRA", 4546: "GRA", 210: "NAV",
}
const NAMES := {"CAS": "Castile", "ARA": "Aragon", "POR": "Portugal", "GRA": "Granada", "NAV": "Navarre", "SPA": "Spain"}


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 8 country-depth test failed: %s" % message)
		quit(1)


func _make_simulation(with_ai := false) -> Dictionary:
	var world := CampaignWorldStateScript.new()
	world.initialize(OWNERS, NAMES, "phase8_country_depth_test", 14441111)
	var economy = EconomyDefinitionsScript.load_default()
	EconomySystemScript.initialize_world(world, economy)
	WarfareSystemScript.initialize_armies(world)
	var characters := CharacterDefinitionsScript.load_default()
	CharacterSystemScript.initialize_world(world, characters)
	var definitions := CountryDepthDefinitionsScript.load_default()
	CountryDepthSystemScript.initialize_world(world, definitions)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.monthly_systems.append(func(month_world: CampaignWorldState) -> void:
		CountryDepthSystemScript.process_month(month_world, events, definitions)
		EconomySystemScript.process_month(month_world, events, economy))
	var ai = null
	if with_ai:
		ai = CountryDepthAISystemScript.new(scheduler, events, definitions)
	return {"world": world, "events": events, "scheduler": scheduler, "definitions": definitions, "economy": economy, "ai": ai}


func _cleanup(simulation: Dictionary) -> void:
	var scheduler: SimulationScheduler = simulation.get("scheduler")
	if scheduler != null:
		scheduler.monthly_systems.clear()
	var events: SimulationEventBus = simulation.get("events")
	if is_instance_valid(events):
		events.free()
	simulation.clear()


func _fund(world: CampaignWorldState, tag: String, points := 10000) -> void:
	var runtime := world.country_runtime(tag)
	runtime["treasury"] = 2000000
	runtime["manpower"] = maxi(20000, int(runtime.get("manpower", 0)))
	runtime["technology_points"] = {"administrative": points, "diplomatic": points, "military": points}
	world.set_country_runtime(tag, runtime)


func _apply(scheduler: SimulationScheduler, command: SimulationCommand) -> void:
	_require(command.validate(scheduler.world).is_empty(), "%s should validate: %s" % [command.command_type(), command.validate(scheduler.world)])
	scheduler.submit(command)
	scheduler.process_commands()


func _set_relation(world: CampaignWorldState, first: String, second: String, opinion_from_second: int, allied := true) -> void:
	var relation := DiplomacySystemScript.relation(world, first, second)
	var opinions: Dictionary = relation.get("opinions", {})
	opinions[second] = opinion_from_second
	relation["opinions"] = opinions
	relation["alliance"] = allied
	DiplomacySystemScript.set_relation(world, first, second, relation)


func _transfer(world: CampaignWorldState, province_id: int, tag: String) -> void:
	world.set_province_owner(province_id, tag)
	world.set_province_controller(province_id, tag)


func _run() -> void:
	var definitions := CountryDepthDefinitionsScript.load_default()
	_require(definitions.is_valid(), "country-depth definitions must validate: %s" % definitions.error())
	_require(definitions.country_tags() == ["ARA", "CAS", "GRA", "NAV", "POR"], "authored country IDs must be stable and sorted")
	var file := FileAccess.open(CountryDepthDefinitionsScript.DEFAULT_PATH, FileAccess.READ)
	var malformed: Dictionary = JSON.parse_string(file.get_as_text()).duplicate(true)
	malformed["provinces"]["206"].erase("provenance")
	_require(not CountryDepthDefinitionsScript.from_data(malformed).is_valid(), "validation must reject historical records without provenance")
	malformed = JSON.parse_string(FileAccess.open(CountryDepthDefinitionsScript.DEFAULT_PATH, FileAccess.READ).get_as_text()).duplicate(true)
	malformed["events"]["poor_harvest"]["options"][0]["effects"][0]["type"] = "arbitrary_script"
	_require(not CountryDepthDefinitionsScript.from_data(malformed).is_valid(), "validation must reject unsupported event effects")

	# Government, stability, technology, ideas, buildings, and units form one
	# complete command-driven progression loop.
	var progression := _make_simulation()
	var world: CampaignWorldState = progression["world"]
	var scheduler: SimulationScheduler = progression["scheduler"]
	_require(String(world.country_runtime("CAS").get("government_id", "")) == "crown_monarchy", "Castile needs its authored government")
	_require(String(world.province_states[223].get("economy", {}).get("religion", "")) == "sunni", "Granada's province setup must load religion")
	_fund(world, "CAS")
	_apply(scheduler, IncreaseStabilityCommandScript.new("CAS"))
	_require(int(world.country_runtime("CAS").get("stability", 0)) == 1, "stability investment must mutate authoritative state")
	_require(not ConstructBuildingCommandScript.new("CAS", 206, "temple").validate(world).is_empty(), "technology must lock advanced buildings")
	_apply(scheduler, AdvanceTechnologyCommandScript.new("CAS", "administrative"))
	_apply(scheduler, AdvanceTechnologyCommandScript.new("CAS", "administrative"))
	_require(ConstructBuildingCommandScript.new("CAS", 206, "temple").validate(world).is_empty(), "administrative technology 2 must unlock temples")
	_apply(scheduler, EnactGovernmentReformCommandScript.new("CAS", "centralized_crown"))
	_require((world.country_runtime("CAS").get("government_reforms", []) as Array).has("centralized_crown"), "reforms must become persistent country state")
	_apply(scheduler, SelectIdeaGroupCommandScript.new("CAS", "military"))
	_require(int(world.country_runtime("CAS").get("country_depth_modifiers", {}).get("army_power_bp", 0)) > 0, "ideas must feed production modifiers")
	for index in 3:
		_apply(scheduler, AdvanceTechnologyCommandScript.new("CAS", "military"))
	_require(RecruitUnitCommandScript.new("CAS", 206, "pike_square").validate(world).is_empty(), "military technology 3 must unlock pike units")
	_cleanup(progression)

	# Province identity, gradual conversion, explainable unrest, revolt, control,
	# and suppression remain deterministic across monthly processing.
	var society := _make_simulation()
	world = society["world"]
	scheduler = society["scheduler"]
	_fund(world, "CAS")
	var runtime := world.country_runtime("CAS")
	runtime["technology"]["diplomatic"] = 2
	world.set_country_runtime("CAS", runtime)
	var province: Dictionary = world.province_states[206]
	var province_economy: Dictionary = province.get("economy", {})
	province_economy["culture"] = "andalusian"
	province_economy["religion"] = "sunni"
	province["economy"] = province_economy
	world.province_states[206] = province
	_apply(scheduler, AcceptCultureCommandScript.new("CAS", "andalusian"))
	_apply(scheduler, StartProvinceConversionCommandScript.new("CAS", 206, "religion", "catholic"))
	for month in 20:
		CountryDepthSystemScript.process_month(world, society["events"], society["definitions"])
	_require(String(world.province_states[206].get("economy", {}).get("religion", "")) == "catholic", "religious conversion must finish gradually")
	province = world.province_states[206]
	province_economy = province.get("economy", {})
	province_economy["event_unrest_bp"] = 10000
	province["economy"] = province_economy
	world.province_states[206] = province
	for month in 22:
		CountryDepthSystemScript.process_month(world, society["events"], society["definitions"])
	var faction_id := "rebel_CAS_206"
	_require(world.rebel_faction_registry.has(faction_id), "high unrest must create an explainable rebel faction")
	_require(String(world.rebel_faction_registry[faction_id].get("status", "")) == "uprising", "sustained maximum unrest must start a revolt")
	_apply(scheduler, SuppressRebelsCommandScript.new("CAS", faction_id))
	_require(int(world.rebel_faction_registry[faction_id].get("progress_bp", 0)) <= 5000, "suppression must reduce rebel progress")
	_cleanup(society)

	# Claims gate conquest declarations and directly reduce the war-goal cost.
	var claims := _make_simulation()
	world = claims["world"]
	scheduler = claims["scheduler"]
	_fund(world, "CAS")
	_require(not DeclareWarCommandScript.new("CAS", "ARA", 214).validate(world).is_empty(), "unjustified conquest must be rejected")
	_apply(scheduler, FabricateProvinceClaimCommandScript.new("CAS", 214))
	_require(DeclareWarCommandScript.new("CAS", "ARA", 214).validate(world).is_empty(), "fabricated claims must unlock conquest")
	var declaration := DeclareWarCommandScript.new("CAS", "GRA", 223)
	_apply(scheduler, declaration)
	var war_id := String(world.war_registry.keys()[0])
	_require(PeaceSystemScript.term_cost(world.war_registry[war_id], {"type": "transfer_province", "province_id": 223}) == 15, "claim war goals must cost 15 war score")
	_cleanup(claims)

	# Subjects pay income, join wars, lose independent diplomacy, integrate, and
	# survive an exact schema-5 save/load round trip.
	var subjects := _make_simulation()
	world = subjects["world"]
	scheduler = subjects["scheduler"]
	_fund(world, "CAS")
	runtime = world.country_runtime("CAS")
	runtime["technology"]["diplomatic"] = 3
	world.set_country_runtime("CAS", runtime)
	_set_relation(world, "CAS", "NAV", 125)
	_apply(scheduler, CreateSubjectCommandScript.new("CAS", "NAV", "vassal"))
	var subject_id := String(world.subject_registry.keys()[0])
	EconomySystemScript.recalculate_all(world)
	_require(int(world.country_runtime("CAS").get("ledger", {}).get("subject_income", 0)) > 0, "vassals must pay income to their overlord")
	_require(not FormAllianceCommandScript.new("NAV", "POR").validate(world).is_empty(), "subjects must not form independent alliances")
	_apply(scheduler, DeclareWarCommandScript.new("CAS", "GRA", 223))
	var subject_war: Dictionary = world.war_registry[world.war_registry.keys()[0]]
	_require((subject_war.get("attackers", []) as Array).has("NAV"), "subjects must participate in overlord wars")
	var active_save := world.to_save_dict("phase8-test")
	var loaded := _make_simulation()
	_require((loaded["world"] as CampaignWorldState).apply_save_dict(active_save).is_empty(), "active subject state must load")
	_require((loaded["world"] as CampaignWorldState).checksum() == world.checksum(), "Phase 8 registries must round-trip exactly")
	_cleanup(loaded)
	world.war_registry.clear()
	_apply(scheduler, StartSubjectIntegrationCommandScript.new("CAS", subject_id))
	for month in 121:
		CountryDepthSystemScript.process_month(world, subjects["events"], subjects["definitions"])
	_require(world.get_province_owner(210) == "CAS" and String(world.subject_registry[subject_id].get("status", "")) == "integrated", "integration must transfer provinces and close the subject relationship")
	_cleanup(subjects)

	# Events, national decisions, country formation, reference replacement, and
	# country release use the same authoritative state and event bus.
	var statecraft := _make_simulation()
	world = statecraft["world"]
	scheduler = statecraft["scheduler"]
	_fund(world, "CAS")
	CountryDepthSystemScript.process_month(world, statecraft["events"], statecraft["definitions"])
	var pending := CountryDepthSystemScript.pending_event_for_country(world, "CAS")
	_require(not pending.is_empty(), "a valid data-driven event must trigger")
	_apply(scheduler, ChooseCountryEventOptionCommandScript.new("CAS", String(pending["instance_id"]), "relief"))
	_require(String(world.country_event_registry[pending["instance_id"]].get("status", "")) == "resolved", "event options must apply and enter history")
	runtime = world.country_runtime("CAS")
	runtime["technology"] = {"administrative": 3, "diplomatic": 3, "military": 3}
	runtime["stability"] = 1
	runtime["authority_bp"] = 9000
	world.set_country_runtime("CAS", runtime)
	_apply(scheduler, EnactCountryDecisionCommandScript.new("CAS", "centralize_state"))
	_set_relation(world, "CAS", "POR", 125)
	_apply(scheduler, CreateSubjectCommandScript.new("CAS", "POR", "vassal"))
	for province_id in [214, 223, 227]:
		_transfer(world, province_id, "CAS")
	_apply(scheduler, EnactCountryDecisionCommandScript.new("CAS", "form_spain"))
	_require(world.get_country_provinces("CAS").is_empty() and world.get_country_provinces("SPA").has(219), "formation must transfer the complete country to its successor tag")
	_require(CountryDepthSystemScript.overlord_of(world, "POR") == "SPA", "formation must replace subject references")
	_transfer(world, 210, "SPA")
	_apply(scheduler, ReleaseCountryCommandScript.new("SPA", "NAV", [210]))
	_require(world.get_province_owner(210) == "NAV", "release must restore an inactive country's core province")
	_cleanup(statecraft)

	# Schema-4 saves migrate to explicit empty Phase 8 registries, and validation
	# rejects cyclic subject graphs before mutating the target world.
	var migration := _make_simulation()
	var legacy := (migration["world"] as CampaignWorldState).to_save_dict("phase8-test")
	legacy["schema_version"] = 4
	legacy.erase("subject_registry")
	legacy.erase("country_event_registry")
	legacy.erase("rebel_faction_registry")
	var migrated := CampaignWorldStateScript.migrate_save_data(legacy)
	_require(int(migrated["schema_version"]) == CampaignWorldStateScript.SAVE_SCHEMA_VERSION and (migrated["subject_registry"] as Dictionary).is_empty(), "schema 4 must migrate to schema 5")
	var corrupt := (migration["world"] as CampaignWorldState).to_save_dict("phase8-test")
	corrupt["subject_registry"] = {
		"subject_a": {"subject_id": "subject_a", "overlord": "CAS", "subject": "NAV", "type": "vassal", "status": "active"},
		"subject_b": {"subject_id": "subject_b", "overlord": "NAV", "subject": "CAS", "type": "vassal", "status": "active"},
	}
	var corrupt_target := _make_simulation()
	_require((corrupt_target["world"] as CampaignWorldState).apply_save_dict(corrupt).contains("cycle"), "save validation must reject subject cycles")
	_cleanup(corrupt_target)

	# Country-depth AI submits regular validated commands and never controls the
	# selected player country.
	var ai_sim := _make_simulation(true)
	world = ai_sim["world"]
	_fund(world, "CAS")
	world.player_country = "CAS"
	CountryDepthSystemScript.process_month(world, ai_sim["events"], ai_sim["definitions"])
	(ai_sim["ai"] as CountryDepthAISystem).process_month(world)
	(ai_sim["scheduler"] as SimulationScheduler).process_commands()
	_require((ai_sim["scheduler"] as SimulationScheduler).command_history.all(func(record: Dictionary) -> bool: return String(record.get("issuer", "")) != "CAS"), "country-depth AI must exclude the player")
	_require(not (ai_sim["ai"] as CountryDepthAISystem).debug_snapshot(world, "ARA").is_empty(), "AI must persist explainable monthly decisions")
	_cleanup(ai_sim)
	_cleanup(migration)

	print("Phase 8 country-depth test passed. schema=%d content=%s" % [CampaignWorldStateScript.SAVE_SCHEMA_VERSION, definitions.content_version()])
	quit(0)
