class_name EconomySystem
extends RefCounted

const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const NavalDefinitionsScript = preload("res://scripts/simulation/naval_definitions.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")

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
# N2.2: sailors recover faster than manpower - a placeholder rate pending
# balance review, not an approved N0 budget value. See docs/roadmap/naval/02_N2_FLEET_LOGISTICS.md
# "Sailors derive from... a simple explainable formula."
const SAILOR_RECOVERY_MONTHS := 60
const SAILORS_PER_OWNED_PORT := 200
# 05_N5 "Province and Port Effects": "Reduced port repair/construction
# effectiveness at high blockade." A local placeholder threshold, not shared
# with BlockadeSystem.SIEGE_ASSIST_THRESHOLD_BP or
# FleetLogisticsSystem.BLOCKADE_EFFECTIVENESS_THRESHOLD_BP even though the
# value happens to match today - each consumer of province_blockade_bp()
# owns its own placeholder magnitude so they can be tuned independently
# later, the same "no shared balance constant" convention this codebase
# already uses for BASIS_POINTS and friends across systems.
const BLOCKADE_CONSTRUCTION_THRESHOLD_BP := 5000


static func initialize_world(world: CampaignWorldState, definitions = null, ship_definitions = null, naval_definitions = null) -> void:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	if ship_definitions == null:
		ship_definitions = ShipDefinitionsScript.load_default()
	if naval_definitions == null:
		naval_definitions = NavalDefinitionsScript.load_default()
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
	world.naval_construction_registry.clear()
	world.global_counters["next_construction_id"] = 1
	world.global_counters["next_recruitment_id"] = 1
	world.global_counters["next_army_serial"] = 1
	world.global_counters["next_loan_id"] = 1
	world.global_counters["next_naval_construction_id"] = 1
	world.global_counters["next_fleet_id"] = 1
	world.global_counters["next_ship_id"] = 1
	recalculate_all(world, definitions, ship_definitions, naval_definitions)
	for raw_tag in tags:
		var tag := String(raw_tag)
		var runtime := world.country_runtime(tag)
		var gross := int((runtime.get("ledger", {}) as Dictionary).get("total_income", 0))
		runtime["treasury"] = maxi(50000, gross * 6)
		runtime["manpower"] = int(runtime.get("maximum_manpower", 0)) / 2
		runtime["sailors"] = int(runtime.get("maximum_sailors", 0)) / 2
		world.set_country_runtime(tag, runtime)
	recalculate_all(world, definitions, ship_definitions, naval_definitions)


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
		"sailors": 0,
		"maximum_sailors": 0,
		"army_maintenance_bp": BASIS_POINTS,
		"navy_maintenance_bp": BASIS_POINTS,
		"ledger": _empty_ledger(),
		"last_economy_day": -1,
	}


static func _empty_ledger() -> Dictionary:
	return {
		"tax": 0,
		"production": 0,
		"subject_income": 0,
		"subject_payments": 0,
		"event_income": 0,
		"blockade_loss": 0,
		"total_income": 0,
		"army_maintenance": 0,
		"navy_maintenance": 0,
		"fort_maintenance": 0,
		"interest": 0,
		"event_expenses": 0,
		"total_expenses": 0,
		"balance": 0,
		"province_tax": {},
		"province_production": {},
	}


static func process_day(world: CampaignWorldState, events: SimulationEventBus, definitions = null, ship_definitions = null) -> void:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	if ship_definitions == null:
		ship_definitions = ShipDefinitionsScript.load_default()
	_complete_constructions(world, events, definitions)
	_complete_recruitments(world, events, definitions)
	_complete_naval_construction(world, events, ship_definitions)


static func process_month(world: CampaignWorldState, events: SimulationEventBus, definitions = null, ship_definitions = null, naval_definitions = null) -> void:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	if ship_definitions == null:
		ship_definitions = ShipDefinitionsScript.load_default()
	if naval_definitions == null:
		naval_definitions = NavalDefinitionsScript.load_default()
	recalculate_all(world, definitions, ship_definitions, naval_definitions)
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
		var maximum_sailors := int(runtime.get("maximum_sailors", 0))
		var sailor_recovery := maxi(1, maximum_sailors / SAILOR_RECOVERY_MONTHS) if maximum_sailors > 0 else 0
		runtime["sailors"] = mini(maximum_sailors, int(runtime.get("sailors", 0)) + sailor_recovery)
		runtime["last_economy_day"] = world.current_day
		world.set_country_runtime(tag, runtime)
	# Treasury/manpower/sailor changes do not alter the cached source
	# breakdown, so a second global province scan is unnecessary here.
	events.economy_month_processed.emit(world.current_day)


static func recalculate_all(world: CampaignWorldState, definitions = null, ship_definitions = null, naval_definitions = null) -> void:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	if ship_definitions == null:
		ship_definitions = ShipDefinitionsScript.load_default()
	if naval_definitions == null:
		naval_definitions = NavalDefinitionsScript.load_default()
	var tags := world.country_states.keys()
	tags.sort()
	var ledgers := {}
	var maximum_manpower := {}
	var maximum_sailors := {}
	for raw_tag in tags:
		var tag := String(raw_tag)
		ledgers[tag] = _empty_ledger()
		maximum_manpower[tag] = 0
		maximum_sailors[tag] = 0
	# Precomputed once, not per-province: all_blockaded_provinces() is the
	# only affordable way to know which of possibly thousands of provinces
	# even need the (comparatively expensive, per-fleet) exact bp query -
	# most provinces are inland or at peace and skip it entirely.
	var blockaded_provinces := {}
	for province_id in BlockadeSystemScript.all_blockaded_provinces(world):
		blockaded_provinces[province_id] = true
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
		if blockaded_provinces.has(province_id):
			var blockade_bp := BlockadeSystemScript.province_blockade_bp(world, province_id)
			ledger["blockade_loss"] = int(ledger["blockade_loss"]) + (int(outputs["tax"]) + int(outputs["production"])) * blockade_bp / BASIS_POINTS
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
	for port_id in naval_definitions.enabled_port_ids():
		var owner := world.get_province_owner(port_id)
		if not ledgers.has(owner):
			continue
		maximum_sailors[owner] = int(maximum_sailors[owner]) + SAILORS_PER_OWNED_PORT
	var ship_ids := world.ship_registry.keys()
	ship_ids.sort()
	for raw_ship_id in ship_ids:
		var ship: Dictionary = world.ship_registry[raw_ship_id]
		var owner := String(ship.get("owner_country_id", ""))
		if not ledgers.has(owner):
			continue
		var runtime := world.country_runtime(owner)
		var ledger: Dictionary = ledgers[owner]
		var ship_definition: Dictionary = ship_definitions.ship(String(ship.get("definition_id", "")))
		ledger["navy_maintenance"] = int(ledger["navy_maintenance"]) + int(ship_definition.get("monthly_maintenance", 0)) * int(runtime.get("navy_maintenance_bp", BASIS_POINTS)) / BASIS_POINTS
		ledgers[owner] = ledger
	# Apply country-wide modifiers before subject payments so a subject pays from
	# its actual monthly tax and production rather than its unmodified base.
	for raw_tag in tags:
		var tag := String(raw_tag)
		var runtime := world.country_runtime(tag)
		var ledger: Dictionary = ledgers[tag]
		ledger["interest"] = int(runtime.get("debt", 0)) * MONTHLY_INTEREST_BP / BASIS_POINTS
		var modifiers := _combined_country_modifiers(runtime)
		ledger["tax"] = int(ledger["tax"]) * (BASIS_POINTS + int(modifiers.get("tax_modifier_bp", 0))) / BASIS_POINTS
		ledger["production"] = int(ledger["production"]) * (BASIS_POINTS + int(modifiers.get("production_modifier_bp", 0))) / BASIS_POINTS
		maximum_manpower[tag] = int(maximum_manpower[tag]) * (BASIS_POINTS + int(modifiers.get("manpower_modifier_bp", 0))) / BASIS_POINTS
		ledgers[tag] = ledger
	_apply_subject_payments(world, ledgers)
	for raw_tag in tags:
		var tag := String(raw_tag)
		var runtime := world.country_runtime(tag)
		var ledger: Dictionary = ledgers[tag]
		ledger["total_income"] = int(ledger["tax"]) + int(ledger["production"]) + int(ledger["subject_income"]) + int(ledger["event_income"]) - int(ledger["blockade_loss"])
		ledger["total_expenses"] = int(ledger["army_maintenance"]) + int(ledger["navy_maintenance"]) + int(ledger["fort_maintenance"]) + int(ledger["interest"]) + int(ledger["subject_payments"]) + int(ledger["event_expenses"])
		ledger["balance"] = int(ledger["total_income"]) - int(ledger["total_expenses"])
		runtime["maximum_manpower"] = int(maximum_manpower[tag])
		runtime["manpower"] = mini(int(runtime.get("manpower", 0)), int(maximum_manpower[tag]))
		runtime["maximum_sailors"] = int(maximum_sailors[tag])
		runtime["sailors"] = mini(int(runtime.get("sailors", 0)), int(maximum_sailors[tag]))
		runtime["ledger"] = ledger
		world.set_country_runtime(tag, runtime)


static func recalculate_country(world: CampaignWorldState, country_tag: String, definitions = null, ship_definitions = null, naval_definitions = null) -> Dictionary:
	if definitions == null:
		definitions = EconomyDefinitionsScript.load_default()
	if ship_definitions == null:
		ship_definitions = ShipDefinitionsScript.load_default()
	if naval_definitions == null:
		naval_definitions = NavalDefinitionsScript.load_default()
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
		var blockade_bp := BlockadeSystemScript.province_blockade_bp(world, province_id)
		if blockade_bp > 0:
			ledger["blockade_loss"] = int(ledger["blockade_loss"]) + (int(outputs["tax"]) + int(outputs["production"])) * blockade_bp / BASIS_POINTS
		(ledger["province_tax"] as Dictionary)[str(province_id)] = outputs["tax"]
		(ledger["province_production"] as Dictionary)[str(province_id)] = outputs["production"]
		maximum_manpower += int(outputs["maximum_manpower"])
	var runtime := world.country_runtime(country_tag)
	var modifiers := _combined_country_modifiers(runtime)
	ledger["tax"] = int(ledger["tax"]) * (BASIS_POINTS + int(modifiers.get("tax_modifier_bp", 0))) / BASIS_POINTS
	ledger["production"] = int(ledger["production"]) * (BASIS_POINTS + int(modifiers.get("production_modifier_bp", 0))) / BASIS_POINTS
	maximum_manpower = maximum_manpower * (BASIS_POINTS + int(modifiers.get("manpower_modifier_bp", 0))) / BASIS_POINTS
	var maintenance_bp := int(runtime.get("army_maintenance_bp", BASIS_POINTS))
	var army_maintenance := 0
	for army_id in world.country_armies(country_tag):
		var army := world.get_army(army_id)
		army_maintenance += int(army.get("base_monthly_maintenance", 500)) * maintenance_bp / BASIS_POINTS
	ledger["army_maintenance"] = army_maintenance
	var maximum_sailors := 0
	for port_id in naval_definitions.enabled_port_ids():
		if world.get_province_owner(port_id) == country_tag:
			maximum_sailors += SAILORS_PER_OWNED_PORT
	var navy_maintenance_bp := int(runtime.get("navy_maintenance_bp", BASIS_POINTS))
	var navy_maintenance := 0
	for ship_id in world.country_ships(country_tag):
		var ship := world.get_ship(ship_id)
		var ship_definition: Dictionary = ship_definitions.ship(String(ship.get("definition_id", "")))
		navy_maintenance += int(ship_definition.get("monthly_maintenance", 0)) * navy_maintenance_bp / BASIS_POINTS
	ledger["navy_maintenance"] = navy_maintenance
	ledger["interest"] = int(runtime.get("debt", 0)) * MONTHLY_INTEREST_BP / BASIS_POINTS
	_apply_single_country_subject_payments(world, country_tag, ledger)
	ledger["total_income"] = int(ledger["tax"]) + int(ledger["production"]) + int(ledger["subject_income"]) + int(ledger["event_income"]) - int(ledger["blockade_loss"])
	ledger["total_expenses"] = int(ledger["army_maintenance"]) + int(ledger["navy_maintenance"]) + int(ledger["fort_maintenance"]) + int(ledger["interest"]) + int(ledger["subject_payments"]) + int(ledger["event_expenses"])
	ledger["balance"] = int(ledger["total_income"]) - int(ledger["total_expenses"])
	runtime["maximum_manpower"] = maximum_manpower
	runtime["manpower"] = mini(int(runtime.get("manpower", 0)), maximum_manpower)
	runtime["maximum_sailors"] = maximum_sailors
	runtime["sailors"] = mini(int(runtime.get("sailors", 0)), maximum_sailors)
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


static func _combined_country_modifiers(runtime: Dictionary) -> Dictionary:
	var result := {"tax_modifier_bp": 0, "production_modifier_bp": 0, "manpower_modifier_bp": 0}
	for source_variant in [runtime.get("ruler_modifiers", {}), runtime.get("country_depth_modifiers", {})]:
		var source: Dictionary = source_variant
		for key in result:
			result[key] = int(result[key]) + int(source.get(key, 0))
	return result


static func _apply_subject_payments(world: CampaignWorldState, ledgers: Dictionary) -> void:
	var ids := world.subject_registry.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = world.subject_registry[raw_id]
		if String(record.get("status", "active")) != "active":
			continue
		var overlord := String(record.get("overlord", ""))
		var subject := String(record.get("subject", ""))
		if not ledgers.has(overlord) or not ledgers.has(subject):
			continue
		var subject_ledger: Dictionary = ledgers[subject]
		var payment := (int(subject_ledger.get("tax", 0)) + int(subject_ledger.get("production", 0))) * int(record.get("income_bp", 0)) / BASIS_POINTS
		subject_ledger["subject_payments"] = int(subject_ledger.get("subject_payments", 0)) + payment
		ledgers[subject] = subject_ledger
		var overlord_ledger: Dictionary = ledgers[overlord]
		overlord_ledger["subject_income"] = int(overlord_ledger.get("subject_income", 0)) + payment
		ledgers[overlord] = overlord_ledger


static func _apply_single_country_subject_payments(world: CampaignWorldState, country_tag: String, ledger: Dictionary) -> void:
	var ids := world.subject_registry.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = world.subject_registry[raw_id]
		if String(record.get("status", "active")) != "active":
			continue
		if String(record.get("subject", "")) == country_tag:
			ledger["subject_payments"] = int(ledger.get("subject_payments", 0)) + (int(ledger.get("tax", 0)) + int(ledger.get("production", 0))) * int(record.get("income_bp", 0)) / BASIS_POINTS
		elif String(record.get("overlord", "")) == country_tag:
			var subject_runtime := world.country_runtime(String(record.get("subject", "")))
			var subject_ledger: Dictionary = subject_runtime.get("ledger", {})
			ledger["subject_income"] = int(ledger.get("subject_income", 0)) + (int(subject_ledger.get("tax", 0)) + int(subject_ledger.get("production", 0))) * int(record.get("income_bp", 0)) / BASIS_POINTS


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
		army["attack"] = int(definition.get("attack", 100))
		army["defence"] = int(definition.get("defence", 100))
		world.army_registry[army_id] = army
		world.recruitment_registry.erase(raw_id)
		events.recruitment_completed.emit(String(raw_id), army_id, int(record["province_id"]))
		recalculate_country(world, tag, definitions)


## N2.2: on completion a ship joins a deterministic port reserve fleet
## (id "reserve_<port>_<country>", not a counter, so it is always the same
## fleet for a given port/owner - 02_N2_FLEET_LOGISTICS.md "on completion, the
## ship joins a deterministic port reserve fleet"). Ownership/control loss
## pauses completion by one day at a time, mirroring _complete_constructions/
## _complete_recruitments, so money and sailors already committed are never
## silently lost and no ship is ever duplicated.
static func _complete_naval_construction(world: CampaignWorldState, events: SimulationEventBus, ship_definitions) -> void:
	var ids := world.naval_construction_registry.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = world.naval_construction_registry[raw_id]
		if int(record.get("completion_day", 0)) > world.current_day:
			continue
		var port_id := int(record["port_id"])
		var country_tag := String(record["country_tag"])
		if world.get_province_owner(port_id) != country_tag or world.get_province_controller(port_id) != country_tag:
			record["completion_day"] = world.current_day + 1
			world.naval_construction_registry[raw_id] = record
			continue
		# 05_N5 "Province and Port Effects": "Reduced port repair/construction
		# effectiveness at high blockade." Reuses the same pause-one-day-at-a-
		# time mechanism ownership loss already uses just above, rather than a
		# separate partial-progress formula - a blockaded port simply does not
		# advance construction that day.
		if BlockadeSystemScript.province_blockade_bp(world, port_id) >= BLOCKADE_CONSTRUCTION_THRESHOLD_BP:
			record["completion_day"] = world.current_day + 1
			world.naval_construction_registry[raw_id] = record
			continue
		var definition_id := String(record["definition_id"])
		var fleet_id := _find_or_create_port_reserve_fleet(world, country_tag, port_id)
		var ship_serial := world.take_counter("next_ship_id")
		var ship_id := "s_%s_%d" % [country_tag, ship_serial]
		var ship := CampaignWorldState.make_ship_record(ship_id, country_tag, fleet_id, definition_id, world.current_day)
		world.ship_registry[ship_id] = ship
		var fleet := world.get_fleet(fleet_id)
		var member_ids: Array = fleet.get("ship_ids", [])
		member_ids.append(ship_id)
		member_ids.sort()
		fleet["ship_ids"] = member_ids
		world.fleet_registry[fleet_id] = fleet
		FleetSystemScript.recompute_aggregate(world, fleet_id, ship_definitions)
		world.naval_construction_registry.erase(raw_id)
		events.naval_construction_completed.emit(String(raw_id), ship_id, fleet_id, port_id)
		recalculate_country(world, country_tag, null, ship_definitions)


static func _find_or_create_port_reserve_fleet(world: CampaignWorldState, country_tag: String, port_id: int) -> String:
	var fleet_id := "reserve_%d_%s" % [port_id, country_tag]
	if not world.fleet_registry.has(fleet_id):
		world.fleet_registry[fleet_id] = CampaignWorldState.make_fleet_record(fleet_id, country_tag, port_id)
	return fleet_id


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
