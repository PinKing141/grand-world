extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const ConstructBuildingCommandScript = preload("res://scripts/simulation/commands/construct_building_command.gd")
const RecruitUnitCommandScript = preload("res://scripts/simulation/commands/recruit_unit_command.gd")
const SetArmyMaintenanceCommandScript = preload("res://scripts/simulation/commands/set_army_maintenance_command.gd")
const TakeLoanCommandScript = preload("res://scripts/simulation/commands/take_loan_command.gd")
const RepayLoanCommandScript = preload("res://scripts/simulation/commands/repay_loan_command.gd")

const MADRID := 217
const TOLEDO := 219
const GRANADA := 223


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 4 economy test failed: %s" % message)
		quit(1)


func _make_world():
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{MADRID: "CAS", TOLEDO: "CAS", GRANADA: "GRA"},
		{"CAS": "Castile", "GRA": "Granada"}
	)
	EconomySystemScript.initialize_world(world)
	return world


func _make_scheduler(world, events):
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.start_of_day_systems.append(
		func(day_world) -> void: EconomySystemScript.process_day(day_world, events)
	)
	scheduler.monthly_systems.append(
		func(month_world) -> void: EconomySystemScript.process_month(month_world, events)
	)
	return scheduler


func _run() -> void:
	var definitions = EconomyDefinitionsScript.load_default()
	_require(definitions.is_valid(), "baked economy definitions must load")
	_require(definitions.provinces.size() == 3924, "all graph provinces need economy definitions")
	var madrid_definition: Dictionary = definitions.province(MADRID)
	_require(int(madrid_definition["base_tax"]) == 5, "Madrid base tax must come from history")
	_require(int(madrid_definition["base_production"]) == 5, "Madrid production must come from history")
	_require(String(madrid_definition["trade_good"]) == "cloth", "Madrid must produce cloth")

	var world = _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler = _make_scheduler(world, events)
	var runtime := world.country_runtime("CAS")
	var ledger: Dictionary = runtime["ledger"]
	_require(int(ledger["tax"]) > 0 and int(ledger["production"]) > 0, "Castile must begin with tax and production")
	var tax_sum := 0
	for value in (ledger["province_tax"] as Dictionary).values():
		tax_sum += int(value)
	_require(tax_sum == int(ledger["tax"]), "province tax sources must equal the ledger category")

	# Exactly one month tick on 1 December 1444.
	var december_first := SimulationDateScript.date_to_day(1444, 12, 1)
	var starting_treasury := int(runtime["treasury"])
	scheduler.advance_days(december_first - 1)
	_require(int(world.country_runtime("CAS")["treasury"]) == starting_treasury, "treasury cannot change before the month boundary")
	scheduler.advance_one_day()
	runtime = world.country_runtime("CAS")
	_require(int(runtime["last_economy_day"]) == december_first, "monthly economy must run on 1 December")
	_require(int(runtime["treasury"]) == starting_treasury + int(runtime["ledger"]["balance"]), "monthly balance must be applied exactly once")

	# Construction spends money, completes on an exact day, and changes output.
	runtime["treasury"] = 500000
	world.set_country_runtime("CAS", runtime)
	var tax_before := int(EconomySystemScript.province_outputs(world.province_states[MADRID]["economy"])["tax"])
	scheduler.submit(ConstructBuildingCommandScript.new("CAS", MADRID, "tax_office"))
	scheduler.process_commands()
	_require(world.construction_registry.size() == 1, "valid construction must create a queue record")
	_require(int(world.country_runtime("CAS")["treasury"]) == 450000, "construction must charge its upfront cost")
	var construction: Dictionary = world.construction_registry.values()[0]
	var completion_day := int(construction["completion_day"])
	while world.current_day < completion_day:
		scheduler.advance_one_day()
	_require(world.construction_registry.is_empty(), "construction must complete on schedule")
	_require((world.province_states[MADRID]["economy"]["buildings"] as Array).has("tax_office"), "completed building must enter province state")
	var tax_after := int(EconomySystemScript.province_outputs(world.province_states[MADRID]["economy"])["tax"])
	_require(tax_after > tax_before, "tax office must increase authoritative tax output")

	# Recruitment reserves money/manpower and produces an authoritative army.
	runtime = world.country_runtime("CAS")
	runtime["treasury"] = 500000
	runtime["manpower"] = int(runtime["maximum_manpower"])
	world.set_country_runtime("CAS", runtime)
	var armies_before := world.country_armies("CAS").size()
	scheduler.submit(RecruitUnitCommandScript.new("CAS", MADRID))
	scheduler.process_commands()
	_require(world.recruitment_registry.size() == 1, "valid recruitment must create a queue record")
	_require(int(world.country_runtime("CAS")["manpower"]) == int(runtime["manpower"]) - 1000, "recruitment must reserve manpower")
	var recruitment: Dictionary = world.recruitment_registry.values()[0]
	while world.current_day < int(recruitment["completion_day"]):
		scheduler.advance_one_day()
	_require(world.country_armies("CAS").size() == armies_before + 1, "completed recruitment must create an army")
	var maintenance_at_full := int(world.country_runtime("CAS")["ledger"]["army_maintenance"])
	scheduler.submit(SetArmyMaintenanceCommandScript.new("CAS", 2500))
	scheduler.process_commands()
	_require(int(world.country_runtime("CAS")["ledger"]["army_maintenance"]) < maintenance_at_full, "maintenance policy must change monthly expenses")

	# Rejected spending is immutable.
	runtime = world.country_runtime("GRA")
	runtime["treasury"] = 0
	world.set_country_runtime("GRA", runtime)
	var checksum_before_rejection := world.checksum()
	scheduler.submit(ConstructBuildingCommandScript.new("GRA", GRANADA, "workshop"))
	scheduler.process_commands()
	_require(world.checksum() == checksum_before_rejection, "rejected economic commands must not mutate state")

	# Loans and repayment are explicit, deterministic commands.
	runtime = world.country_runtime("CAS")
	runtime["treasury"] = 500000
	world.set_country_runtime("CAS", runtime)
	scheduler.submit(TakeLoanCommandScript.new("CAS"))
	scheduler.process_commands()
	_require(int(world.country_runtime("CAS")["debt"]) == 100000, "taking a loan must create debt")
	var loan_id := String(world.loan_registry.keys()[0])
	scheduler.submit(RepayLoanCommandScript.new("CAS", loan_id))
	scheduler.process_commands()
	_require(int(world.country_runtime("CAS")["debt"]) == 0 and world.loan_registry.is_empty(), "repayment must remove principal and loan record")

	# JSON save round-trip preserves exact checksum and active Phase 4 state.
	var saved := world.to_save_dict("phase4-test")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var reloaded = _make_world()
	_require(reloaded.apply_save_dict(parsed).is_empty(), "schema 3 JSON save must load")
	_require(reloaded.checksum() == world.checksum(), "schema 3 JSON round-trip must preserve checksum")

	# Schema 2 migration adds economy registries while retaining Phase 3 armies.
	var legacy := saved.duplicate(true)
	legacy["schema_version"] = 2
	legacy.erase("province_economy")
	legacy.erase("construction_registry")
	legacy.erase("recruitment_registry")
	legacy.erase("loan_registry")
	var migrated := CampaignWorldStateScript.migrate_save_data(legacy)
	_require(int(migrated["schema_version"]) == 3, "schema 2 saves must migrate to schema 3")
	var migrated_world = _make_world()
	_require(migrated_world.apply_save_dict(migrated).is_empty(), "migrated Phase 3 save must load")
	_require(not migrated_world.country_runtime("CAS").is_empty(), "migration must retain initialized country economy")

	print("Phase 4 economy test passed. balance=%d tax_building_output=%d" % [int(ledger["balance"]), tax_after])
	quit(0)
