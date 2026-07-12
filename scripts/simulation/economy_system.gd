class_name EconomySystem
extends RefCounted

const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")

const BASIS_POINTS := 10000
const TERRAIN_ECONOMY_BP := {
	"plains": 10000,
	"forest": 9500,
	"hills": 9000,
	"desert": 8500,
	"tundra": 8500,
	"marsh": 8000,
	"mountains": 7500,
}
const LOAN_PRINCIPAL := 100000
const MAXIMUM_DEBT := 1000000
const MONTHLY_INTEREST_BP := 100
const MANPOWER_RECOVERY_MONTHS := 120


static func initialize_world(world: CampaignWorldState, definitions = null) -> void:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	var province_ids := world.province_states.keys()
	province_ids.sort()
	for raw_id in province_ids:
		var province_id := int(raw_id)
		var state: Dictionary = world.province_states[raw_id]
		var definition: Dictionary = definitions.province(province_id)
		state["economy"] = _make_province_economy(definition)
		world.province_states[province_id] = state
	var tags := world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		var country: Dictionary = world.country_states[raw_tag]
		country["runtime_values"] = _make_country_runtime()
		world.country_states[tag] = country
	world.construction_registry.clear()
	world.recruitment_registry.clear()
	world.loan_registry.clear()
	world.global_counters["next_construction_id"] = 1
	world.global_counters["next_recruitment_id"] = 1
	world.global_counters["next_army_serial"] = 1
	world.global_counters["next_loan_id"] = 1
	recalculate_all(world, definitions)
	for raw_tag in tags:
		var tag := String(raw_tag)
		var runtime := world.country_runtime(tag)
		var gross := int((runtime.get("ledger", {}) as Dictionary).get("total_income", 0))
		runtime["treasury"] = maxi(50000, gross * 6)
		runtime["manpower"] = int(runtime.get("maximum_manpower", 0)) / 2
		world.set_country_runtime(tag, runtime)
	recalculate_all(world, definitions)


static func _make_province_economy(definition: Dictionary) -> Dictionary:
	return {
		"base_tax": int(definition.get("base_tax", 0)),
		"base_production": int(definition.get("base_production", 0)),
		"base_manpower": int(definition.get("base_manpower", 0)),
		"development": int(definition.get("development", 0)),
		"control_bp": int(definition.get("control_bp", BASIS_POINTS)),
		"unrest_bp": int(definition.get("unrest_bp", 0)),
		"devastation_bp": int(definition.get("devastation_bp", 0)),
		"trade_good": String(definition.get("trade_good", "unknown")),
		"terrain": String(definition.get("terrain", "plains")),
		"building_slots": int(definition.get("building_slots", 0)),
		"economic_eligible": bool(definition.get("economic_eligible", false)),
		"buildings": [],
	}


static func _make_country_runtime() -> Dictionary:
	return {
		"treasury": 0,
		"debt": 0,
		"manpower": 0,
		"maximum_manpower": 0,
		"army_maintenance_bp": BASIS_POINTS,
		"ledger": _empty_ledger(),
		"last_economy_day": -1,
	}


static func _empty_ledger() -> Dictionary:
	return {
		"tax": 0,
		"production": 0,
		"subject_income": 0,
		"event_income": 0,
		"total_income": 0,
		"army_maintenance": 0,
		"fort_maintenance": 0,
		"interest": 0,
		"event_expenses": 0,
		"total_expenses": 0,
		"balance": 0,
		"province_tax": {},
		"province_production": {},
	}


static func process_day(world: CampaignWorldState, events: SimulationEventBus, definitions = null) -> void:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	_complete_constructions(world, events, definitions)
	_complete_recruitments(world, events, definitions)


static func process_month(world: CampaignWorldState, events: SimulationEventBus, definitions = null) -> void:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	recalculate_all(world, definitions)
	var tags := world.country_states.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		var runtime := world.country_runtime(tag)
		var ledger: Dictionary = runtime.get("ledger", {})
		var treasury := int(runtime.get("treasury", 0)) + int(ledger.get("balance", 0))
		while treasury < 0 and int(runtime.get("debt", 0)) + LOAN_PRINCIPAL <= MAXIMUM_DEBT:
			var loan_id := _create_loan(world, tag, runtime)
			treasury += LOAN_PRINCIPAL
			events.loan_taken.emit(loan_id, tag, LOAN_PRINCIPAL)
		runtime["treasury"] = treasury
		var maximum_manpower := int(runtime.get("maximum_manpower", 0))
		var recovery := maxi(1, maximum_manpower / MANPOWER_RECOVERY_MONTHS) if maximum_manpower > 0 else 0
		runtime["manpower"] = mini(maximum_manpower, int(runtime.get("manpower", 0)) + recovery)
		runtime["last_economy_day"] = world.current_day
		world.set_country_runtime(tag, runtime)
	# Treasury/manpower changes do not alter the cached source breakdown, so a
	# second global province scan is unnecessary here.
	events.economy_month_processed.emit(world.current_day)


static func recalculate_all(world: CampaignWorldState, definitions = null) -> void:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	var tags := world.country_states.keys()
	tags.sort()
	var ledgers := {}
	var maximum_manpower := {}
	for raw_tag in tags:
		var tag := String(raw_tag)
		ledgers[tag] = _empty_ledger()
		maximum_manpower[tag] = 0
	var province_ids := world.province_states.keys()
	province_ids.sort()
	for raw_id in province_ids:
		var province_id := int(raw_id)
		var state: Dictionary = world.province_states[raw_id]
		var owner := String(state.get("owner", ""))
		if owner.is_empty() or not ledgers.has(owner):
			continue
		var economy: Dictionary = state.get("economy", {})
		if not bool(economy.get("economic_eligible", false)):
			continue
		var outputs := province_outputs(economy, definitions)
		var ledger: Dictionary = ledgers[owner]
		ledger["tax"] = int(ledger["tax"]) + int(outputs["tax"])
		ledger["production"] = int(ledger["production"]) + int(outputs["production"])
		(ledger["province_tax"] as Dictionary)[str(province_id)] = outputs["tax"]
		(ledger["province_production"] as Dictionary)[str(province_id)] = outputs["production"]
		ledgers[owner] = ledger
		maximum_manpower[owner] = int(maximum_manpower[owner]) + int(outputs["maximum_manpower"])
	var army_ids := world.army_registry.keys()
	army_ids.sort()
	for raw_army_id in army_ids:
		var army: Dictionary = world.army_registry[raw_army_id]
		var owner := String(army.get("owner_country_id", ""))
		if not ledgers.has(owner):
			continue
		var runtime := world.country_runtime(owner)
		var ledger: Dictionary = ledgers[owner]
		ledger["army_maintenance"] = int(ledger["army_maintenance"]) + int(army.get("base_monthly_maintenance", 500)) * int(runtime.get("army_maintenance_bp", BASIS_POINTS)) / BASIS_POINTS
		ledgers[owner] = ledger
	for raw_tag in tags:
		var tag := String(raw_tag)
		var runtime := world.country_runtime(tag)
		var ledger: Dictionary = ledgers[tag]
		ledger["interest"] = int(runtime.get("debt", 0)) * MONTHLY_INTEREST_BP / BASIS_POINTS
		var ruler_modifiers: Dictionary = runtime.get("ruler_modifiers", {})
		ledger["tax"] = int(ledger["tax"]) * (BASIS_POINTS + int(ruler_modifiers.get("tax_modifier_bp", 0))) / BASIS_POINTS
		ledger["production"] = int(ledger["production"]) * (BASIS_POINTS + int(ruler_modifiers.get("production_modifier_bp", 0))) / BASIS_POINTS
		maximum_manpower[tag] = int(maximum_manpower[tag]) * (BASIS_POINTS + int(ruler_modifiers.get("manpower_modifier_bp", 0))) / BASIS_POINTS
		ledger["total_income"] = int(ledger["tax"]) + int(ledger["production"]) + int(ledger["subject_income"]) + int(ledger["event_income"])
		ledger["total_expenses"] = int(ledger["army_maintenance"]) + int(ledger["fort_maintenance"]) + int(ledger["interest"]) + int(ledger["event_expenses"])
		ledger["balance"] = int(ledger["total_income"]) - int(ledger["total_expenses"])
		runtime["maximum_manpower"] = int(maximum_manpower[tag])
		runtime["manpower"] = mini(int(runtime.get("manpower", 0)), int(maximum_manpower[tag]))
		runtime["ledger"] = ledger
		world.set_country_runtime(tag, runtime)


static func recalculate_country(world: CampaignWorldState, country_tag: String, definitions = null) -> Dictionary:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	var ledger := _empty_ledger()
	var maximum_manpower := 0
	for raw_id in world.get_country_provinces(country_tag):
		var province_id := int(raw_id)
		var state: Dictionary = world.province_states.get(province_id, {})
		var economy: Dictionary = state.get("economy", {})
		if not bool(economy.get("economic_eligible", false)):
			continue
		var outputs := province_outputs(economy, definitions)
		ledger["tax"] += int(outputs["tax"])
		ledger["production"] += int(outputs["production"])
		(ledger["province_tax"] as Dictionary)[str(province_id)] = outputs["tax"]
		(ledger["province_production"] as Dictionary)[str(province_id)] = outputs["production"]
		maximum_manpower += int(outputs["maximum_manpower"])
	var runtime := world.country_runtime(country_tag)
	var ruler_modifiers: Dictionary = runtime.get("ruler_modifiers", {})
	ledger["tax"] = int(ledger["tax"]) * (BASIS_POINTS + int(ruler_modifiers.get("tax_modifier_bp", 0))) / BASIS_POINTS
	ledger["production"] = int(ledger["production"]) * (BASIS_POINTS + int(ruler_modifiers.get("production_modifier_bp", 0))) / BASIS_POINTS
	maximum_manpower = maximum_manpower * (BASIS_POINTS + int(ruler_modifiers.get("manpower_modifier_bp", 0))) / BASIS_POINTS
	var maintenance_bp := int(runtime.get("army_maintenance_bp", BASIS_POINTS))
	var army_maintenance := 0
	for army_id in world.country_armies(country_tag):
		var army := world.get_army(army_id)
		army_maintenance += int(army.get("base_monthly_maintenance", 500)) * maintenance_bp / BASIS_POINTS
	ledger["army_maintenance"] = army_maintenance
	ledger["interest"] = int(runtime.get("debt", 0)) * MONTHLY_INTEREST_BP / BASIS_POINTS
	ledger["total_income"] = int(ledger["tax"]) + int(ledger["production"]) + int(ledger["subject_income"]) + int(ledger["event_income"])
	ledger["total_expenses"] = int(ledger["army_maintenance"]) + int(ledger["fort_maintenance"]) + int(ledger["interest"]) + int(ledger["event_expenses"])
	ledger["balance"] = int(ledger["total_income"]) - int(ledger["total_expenses"])
	runtime["maximum_manpower"] = maximum_manpower
	runtime["manpower"] = mini(int(runtime.get("manpower", 0)), maximum_manpower)
	runtime["ledger"] = ledger
	world.set_country_runtime(country_tag, runtime)
	return ledger


static func province_outputs(economy: Dictionary, definitions = null) -> Dictionary:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	if not bool(economy.get("economic_eligible", false)):
		return {"tax": 0, "production": 0, "maximum_manpower": 0}
	var control := clampi(int(economy.get("control_bp", BASIS_POINTS)), 0, BASIS_POINTS)
	var devastation := clampi(int(economy.get("devastation_bp", 0)), 0, BASIS_POINTS)
	var terrain_bp := int(TERRAIN_ECONOMY_BP.get(String(economy.get("terrain", "plains")), BASIS_POINTS))
	var tax_bonus := 0
	var production_bonus := 0
	var manpower_bonus := 0
	for raw_building in economy.get("buildings", []):
		var building: Dictionary = definitions.building(String(raw_building))
		tax_bonus += int(building.get("tax_modifier_bp", 0))
		production_bonus += int(building.get("production_modifier_bp", 0))
		manpower_bonus += int(building.get("manpower_modifier_bp", 0))
	var common_bp := control * (BASIS_POINTS - devastation) / BASIS_POINTS
	common_bp = common_bp * terrain_bp / BASIS_POINTS
	var tax := int(economy.get("base_tax", 0)) * 1000 / 12
	tax = tax * common_bp / BASIS_POINTS
	tax = tax * (BASIS_POINTS + tax_bonus) / BASIS_POINTS
	var good: Dictionary = definitions.trade_good(String(economy.get("trade_good", "unknown")))
	var production := int(economy.get("base_production", 0)) * int(good.get("base_price", 2000)) / 12
	production = production * common_bp / BASIS_POINTS
	production = production * (BASIS_POINTS + production_bonus) / BASIS_POINTS
	var maximum_manpower := int(economy.get("base_manpower", 0)) * 1000
	maximum_manpower = maximum_manpower * common_bp / BASIS_POINTS
	maximum_manpower = maximum_manpower * (BASIS_POINTS + manpower_bonus) / BASIS_POINTS
	return {"tax": tax, "production": production, "maximum_manpower": maximum_manpower}


static func _complete_constructions(world: CampaignWorldState, events: SimulationEventBus, definitions) -> void:
	var ids := world.construction_registry.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = world.construction_registry[raw_id]
		if int(record.get("completion_day", 0)) > world.current_day:
			continue
		var province_id := int(record["province_id"])
		if world.get_province_owner(province_id) != String(record["country_tag"]):
			# Ownership changes pause rather than corrupt active projects. The
			# completion date moves forward one day for every paused day.
			record["completion_day"] = world.current_day + 1
			world.construction_registry[raw_id] = record
			continue
		var state: Dictionary = world.province_states[province_id]
		var economy: Dictionary = state.get("economy", {})
		var buildings: Array = economy.get("buildings", [])
		var building_id := String(record["building_id"])
		if not buildings.has(building_id):
			buildings.append(building_id)
			buildings.sort()
		economy["buildings"] = buildings
		state["economy"] = economy
		world.province_states[province_id] = state
		world.construction_registry.erase(raw_id)
		events.building_completed.emit(String(raw_id), province_id, building_id)
		recalculate_country(world, String(record["country_tag"]), definitions)


static func _complete_recruitments(world: CampaignWorldState, events: SimulationEventBus, definitions) -> void:
	var ids := world.recruitment_registry.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = world.recruitment_registry[raw_id]
		if int(record.get("completion_day", 0)) > world.current_day:
			continue
		if world.get_province_owner(int(record["province_id"])) != String(record["country_tag"]) or world.get_province_controller(int(record["province_id"])) != String(record["country_tag"]):
			record["completion_day"] = world.current_day + 1
			world.recruitment_registry[raw_id] = record
			continue
		var tag := String(record["country_tag"])
		var unit_id := String(record["unit_id"])
		var definition: Dictionary = definitions.unit(unit_id)
		var serial := world.take_counter("next_army_serial")
		var army_id := "a_%s_%d" % [tag, serial]
		var army := CampaignWorldState.make_army_record(army_id, tag, int(record["province_id"]))
		army["unit_id"] = unit_id
		army["regiment_count"] = 1
		army["strength"] = int(definition.get("maximum_strength", 1000))
		army["base_monthly_maintenance"] = int(definition.get("monthly_maintenance", 500))
		world.army_registry[army_id] = army
		world.recruitment_registry.erase(raw_id)
		events.recruitment_completed.emit(String(raw_id), army_id, int(record["province_id"]))
		recalculate_country(world, tag, definitions)


static func _create_loan(world: CampaignWorldState, country_tag: String, runtime: Dictionary) -> String:
	var loan_id := "loan_%d" % world.take_counter("next_loan_id")
	world.loan_registry[loan_id] = {
		"loan_id": loan_id,
		"country_tag": country_tag,
		"principal": LOAN_PRINCIPAL,
		"interest_bp": MONTHLY_INTEREST_BP,
		"start_day": world.current_day,
	}
	runtime["debt"] = int(runtime.get("debt", 0)) + LOAN_PRINCIPAL
	return loan_id


static func take_loan(world: CampaignWorldState, country_tag: String) -> String:
	var runtime := world.country_runtime(country_tag)
	var loan_id := _create_loan(world, country_tag, runtime)
	runtime["treasury"] = int(runtime.get("treasury", 0)) + LOAN_PRINCIPAL
	world.set_country_runtime(country_tag, runtime)
	return loan_id


static func format_money(amount: int) -> String:
	var sign_text := "-" if amount < 0 else ""
	var absolute := absi(amount)
	return "%s%d.%02d" % [sign_text, absolute / 1000, (absolute % 1000) / 10]
