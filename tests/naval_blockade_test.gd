extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")
const WarfareSystemScript = preload("res://scripts/simulation/warfare_system.gd")
const NavalDefinitionsScript = preload("res://scripts/simulation/naval_definitions.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const FleetLogisticsSystemScript = preload("res://scripts/simulation/fleet_logistics_system.gd")
const SetFleetMissionCommandScript = preload("res://scripts/simulation/commands/set_fleet_mission_command.gd")
const ConstructShipCommandScript = preload("res://scripts/simulation/commands/construct_ship_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval blockade test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		# STRAITS_OF_DOVER is registered unowned (not simply left absent from
		# province_states) so a fleet sitting AT_SEA there - every blockading
		# fleet in this file - is a save-validatable location: apply_save_dict
		# rejects any fleet whose location_id/home_port_id is not a known
		# province, sea zone or not.
		{CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR", STRAITS_OF_DOVER: ""},
		{"ENG": "England", "BUR": "Burgundy"}
	)
	EconomySystemScript.initialize_world(world)
	world.war_registry["war_1"] = {
		"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "BUR",
		"attackers": ["ENG"], "defenders": ["BUR"], "battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": CALAIS, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
	}
	return world


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, location_id: int, ship_count: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, location_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	var ship_ids: Array = []
	for index in ship_count:
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "war_galley", 0)
		ship_ids.append(ship_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _damage_ships(world: CampaignWorldState, fleet_id: String, hull_bp: int) -> void:
	for ship_id in world.fleet_ships(fleet_id):
		var ship := world.get_ship(ship_id)
		ship["hull_bp"] = hull_bp
		world.ship_registry[ship_id] = ship
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _expected_required_power(world: CampaignWorldState, province_id: int) -> int:
	var economy: Dictionary = (world.province_states[province_id] as Dictionary).get("economy", {})
	var development := int(economy.get("base_tax", 0)) + int(economy.get("base_production", 0))
	var naval_definitions := NavalDefinitionsScript.load_default()
	var harbour_level := 0
	if naval_definitions.is_port(province_id):
		harbour_level = int(naval_definitions.port(province_id).get("harbour_level", 0))
	return BlockadeSystemScript.BASE_REQUIRED_POWER + development + harbour_level * BlockadeSystemScript.HARBOUR_LEVEL_REQUIRED_POWER


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng", "ENG", STRAITS_OF_DOVER, 3)
	# war_galley's blockade_power is 1 per ship (assets/ship_definitions.json).
	_require(int(world.get_fleet("fleet_eng")["aggregate"]["total_blockade_power"]) == 3, "fixture assumption: three war galleys must provide 3 total blockade power")

	# --- SetFleetMissionCommand ---
	_require(not SetFleetMissionCommandScript.new("ENG", "fleet_eng", "not_a_real_mission").validate(world).is_empty(), "an unknown mission must be rejected")
	_require(not SetFleetMissionCommandScript.new("BUR", "fleet_eng", "blockade").validate(world).is_empty(), "a country that does not own the fleet must be rejected")
	var set_mission := SetFleetMissionCommandScript.new("ENG", "fleet_eng", "blockade")
	_require(set_mission.validate(world).is_empty(), "a legal mission change must be accepted: %s" % set_mission.validate(world))
	set_mission.apply(world, events)
	_require(String(world.get_fleet("fleet_eng")["mission"]) == "blockade", "the mission change must reach WorldState")

	# --- Eligibility ---
	_require(BlockadeSystemScript.is_fleet_eligible(world, "fleet_eng"), "an at-sea, blockade-mission, supplied fleet must be eligible")
	var fleet := world.get_fleet("fleet_eng")
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	world.fleet_registry["fleet_eng"] = fleet
	_require(not BlockadeSystemScript.is_fleet_eligible(world, "fleet_eng"), "a docked fleet must not be eligible - blockade requires holding station at sea")
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	fleet["mission"] = "idle"
	world.fleet_registry["fleet_eng"] = fleet
	_require(not BlockadeSystemScript.is_fleet_eligible(world, "fleet_eng"), "a fleet not on blockade mission must not be eligible")
	fleet["mission"] = "blockade"
	fleet["supplied"] = false
	world.fleet_registry["fleet_eng"] = fleet
	_require(not BlockadeSystemScript.is_fleet_eligible(world, "fleet_eng"), "an unsupplied fleet must not be eligible")
	fleet["supplied"] = true
	world.fleet_registry["fleet_eng"] = fleet
	_require(BlockadeSystemScript.is_fleet_eligible(world, "fleet_eng"), "fixture must be restored to eligible before continuing")

	# --- Effective power and damage scaling ---
	_require(BlockadeSystemScript.effective_power(world, "fleet_eng") == 3, "an undamaged fleet must contribute its full blockade power")
	for ship_id in world.fleet_ships("fleet_eng"):
		var ship := world.get_ship(ship_id)
		ship["hull_bp"] = BlockadeSystemScript.DAMAGED_EFFECTIVENESS_THRESHOLD_BP - 1
		world.ship_registry[ship_id] = ship
	FleetSystemScript.recompute_aggregate(world, "fleet_eng")
	_require(BlockadeSystemScript.effective_power(world, "fleet_eng") == 0, "a fleet below the damage effectiveness threshold must contribute zero blockade power")
	for ship_id in world.fleet_ships("fleet_eng"):
		var ship := world.get_ship(ship_id)
		ship["hull_bp"] = 10000
		world.ship_registry[ship_id] = ship
	FleetSystemScript.recompute_aggregate(world, "fleet_eng")

	# --- Which provinces this fleet blockades ---
	var targets := BlockadeSystemScript.blockaded_provinces_for_fleet(world, "fleet_eng")
	_require(targets.has(PICARDIE), "a hostile coastal province adjacent to the fleet's sea zone must be blockaded")
	_require(not targets.has(CALAIS) and not targets.has(KENT), "the fleet's own country's provinces must never be blockaded")
	var contributors := BlockadeSystemScript.blockade_contributors(world, PICARDIE)
	_require(contributors.size() == 1, "one blockading country must produce one contributor record")
	_require(String(contributors[0].get("country_id", "")) == "ENG" and int(contributors[0].get("effective_power", 0)) == 3, "the contributor query must expose the real country and damage-aware effective power")
	_require((contributors[0].get("fleet_ids", []) as Array) == ["fleet_eng"], "the contributor query must expose stable contributing fleet IDs")
	_require(BlockadeSystemScript.primary_blockading_country(world, PICARDIE) == "ENG", "the compact primary-attacker query must resolve the strongest contributor")

	# --- Combining multiple fleets, clamped, ineligible fleets excluded ---
	_add_fleet(world, "fleet_eng_2", "ENG", STRAITS_OF_DOVER, 2)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_2", "blockade").apply(world, events)
	contributors = BlockadeSystemScript.blockade_contributors(world, PICARDIE)
	_require(contributors.size() == 1 and int(contributors[0].get("effective_power", 0)) == 5, "multiple fleets from one country must aggregate into one contributor without losing fleet identity")
	_require((contributors[0].get("fleet_ids", []) as Array) == ["fleet_eng", "fleet_eng_2"], "contributing fleet IDs must remain sorted deterministically")
	var picardie_required := _expected_required_power(world, PICARDIE)
	var expected_bp_5 := clampi(5 * BlockadeSystemScript.BASIS_POINTS / picardie_required, 0, BlockadeSystemScript.BASIS_POINTS)
	_require(BlockadeSystemScript.province_blockade_bp(world, PICARDIE) == expected_bp_5, "two eligible fleets must combine their raw power (3 + 2) before target resistance is applied as a bp fraction of required power: expected %d got %d" % [expected_bp_5, BlockadeSystemScript.province_blockade_bp(world, PICARDIE)])
	_add_fleet(world, "fleet_eng_3", "ENG", STRAITS_OF_DOVER, 1)
	# fleet_eng_3 is left on its default "idle" mission - it must not contribute.
	_require(BlockadeSystemScript.province_blockade_bp(world, PICARDIE) == expected_bp_5, "a fleet not on blockade mission must not contribute even if co-located and hostile")

	# --- Target resistance: required power scales with development/harbour level, clamps at full blockade ---
	_require(expected_bp_5 < BlockadeSystemScript.BASIS_POINTS, "fixture assumption: 5 raw power must not fully blockade a developed, harboured port")
	_require(expected_bp_5 > 0, "fixture assumption: 5 raw power must still register a real, non-zero blockade")
	var world_cap := _make_world()
	var events_cap := SimulationEventBusScript.new()
	root.add_child(events_cap)
	var required_cap := _expected_required_power(world_cap, PICARDIE)
	_add_fleet(world_cap, "fleet_eng_cap", "ENG", STRAITS_OF_DOVER, required_cap)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_cap", "blockade").apply(world_cap, events_cap)
	_require(int(world_cap.get_fleet("fleet_eng_cap")["aggregate"]["total_blockade_power"]) >= required_cap, "fixture assumption: a fleet with one war galley per required-power point must meet or exceed Picardie's required power")
	_require(BlockadeSystemScript.province_blockade_bp(world_cap, PICARDIE) == BlockadeSystemScript.BASIS_POINTS, "attacker power at or above required power must clamp to a full 10000 bp blockade, not overflow past it")

	# --- Economy ledger integration ---
	EconomySystemScript.recalculate_all(world)
	var picardie_state: Dictionary = world.province_states[PICARDIE]
	var picardie_outputs := EconomySystemScript.province_outputs(picardie_state.get("economy", {}))
	var picardie_bp := BlockadeSystemScript.province_blockade_bp(world, PICARDIE)
	_require(picardie_bp == expected_bp_5, "fixture assumption: Picardie blockade bp must still match the resistance formula at this point")
	var expected_loss := (int(picardie_outputs["tax"]) + int(picardie_outputs["production"])) * picardie_bp / EconomySystemScript.BASIS_POINTS
	var bur_ledger: Dictionary = (world.country_runtime("BUR").get("ledger", {}) as Dictionary)
	_require(int(bur_ledger.get("blockade_loss", -1)) == expected_loss, "blockade_loss must equal the formula applied to the blockaded province's raw tax+production: expected %d got %s" % [expected_loss, bur_ledger.get("blockade_loss")])
	_require(int(bur_ledger.get("total_income", 0)) == int(bur_ledger.get("tax", 0)) + int(bur_ledger.get("production", 0)) + int(bur_ledger.get("subject_income", 0)) + int(bur_ledger.get("event_income", 0)) - int(bur_ledger.get("blockade_loss", 0)), "total_income must subtract blockade_loss")
	var eng_ledger: Dictionary = (world.country_runtime("ENG").get("ledger", {}) as Dictionary)
	_require(int(eng_ledger.get("blockade_loss", -1)) == 0, "a country with no blockaded provinces must show zero blockade_loss")
	var bur_recalc_single := EconomySystemScript.recalculate_country(world, "BUR")
	_require(int(bur_recalc_single.get("blockade_loss", -1)) == expected_loss, "recalculate_country must match recalculate_all's blockade_loss computation")

	# --- A province with no war, or no eligible fleets, is not blockaded. ---
	_require(BlockadeSystemScript.province_blockade_bp(world, CALAIS) == 0, "a friendly province must never show a blockade value")
	var world_peace := _make_world()
	world_peace.war_registry.clear()
	var events_peace := SimulationEventBusScript.new()
	root.add_child(events_peace)
	_add_fleet(world_peace, "fleet_eng", "ENG", STRAITS_OF_DOVER, 3)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng", "blockade").apply(world_peace, events_peace)
	_require(BlockadeSystemScript.province_blockade_bp(world_peace, PICARDIE) == 0, "with no active war, a fleet must not blockade even if otherwise eligible")

	# --- all_blockaded_provinces ---
	var all_targets := BlockadeSystemScript.all_blockaded_provinces(world)
	_require(all_targets.has(PICARDIE), "the world-wide query must include every currently blockaded province")
	_require(not all_targets.has(CALAIS), "the world-wide query must never include a friendly province")

	# --- War blockade score: bounded daily accumulator, decays on release ---
	var world_ws := _make_world()
	var events_ws := SimulationEventBusScript.new()
	root.add_child(events_ws)
	_add_fleet(world_ws, "fleet_eng", "ENG", STRAITS_OF_DOVER, 3)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng", "blockade").apply(world_ws, events_ws)
	var scheduler_ws := SimulationSchedulerScript.new(world_ws, events_ws)
	scheduler_ws.daily_systems.append(
		func(day_world) -> void: WarfareSystemScript.advance_day(day_world, events_ws)
	)
	_require(int(world_ws.war_registry["war_1"].get("blockade_score_attacker", 0)) == 0, "blockade score must start at zero")
	for day in 3:
		scheduler_ws.advance_one_day()
	_require(int(world_ws.war_registry["war_1"]["blockade_score_attacker"]) == 3, "an uncontested attacker blockade must accumulate one point per day: got %d" % int(world_ws.war_registry["war_1"]["blockade_score_attacker"]))
	for day in 40:
		scheduler_ws.advance_one_day()
	_require(int(world_ws.war_registry["war_1"]["blockade_score_attacker"]) == BlockadeSystemScript.BLOCKADE_SCORE_MAX, "blockade score must clamp at its maximum rather than grow unbounded")
	SetFleetMissionCommandScript.new("ENG", "fleet_eng", "idle").apply(world_ws, events_ws)
	for day in 5:
		scheduler_ws.advance_one_day()
	_require(int(world_ws.war_registry["war_1"]["blockade_score_attacker"]) == BlockadeSystemScript.BLOCKADE_SCORE_MAX - 5, "releasing the blockade must decay the score toward zero at one point per day: got %d" % int(world_ws.war_registry["war_1"]["blockade_score_attacker"]))
	var total_after_release := int(world_ws.war_registry["war_1"]["total_war_score"])
	_require(total_after_release == clampi(int(world_ws.war_registry["war_1"].get("battle_score_attacker", 0)) + int(world_ws.war_registry["war_1"].get("occupation_score_attacker", 0)) + int(world_ws.war_registry["war_1"].get("ticking_score_attacker", 0)) + int(world_ws.war_registry["war_1"].get("blockade_score_attacker", 0)), -100, 100), "total_war_score must include blockade_score_attacker")

	# --- Coastal siege assist: only an above-threshold, on-side blockade speeds a coastal siege ---
	_require(BlockadeSystemScript.province_blockade_bp(world, PICARDIE) < BlockadeSystemScript.SIEGE_ASSIST_THRESHOLD_BP, "fixture assumption: the earlier 5-power fleet's blockade must remain below the siege-assist threshold")
	_require(BlockadeSystemScript.siege_assist_bp(world, ["ENG"], PICARDIE) == 0, "a below-threshold blockade must not grant siege assist")

	var world_no_assist := _make_world()
	var events_no_assist := SimulationEventBusScript.new()
	root.add_child(events_no_assist)
	# world.initialize() auto-creates one default army per country at its
	# lowest-ID province ("a_BUR" lands on Picardie, BUR's only province) -
	# erase it so the siege army marches in uncontested rather than fighting
	# a land battle first, keeping this fixture isolated to siege-assist
	# behaviour rather than the already-covered battle-to-siege transition.
	world_no_assist.army_registry.erase("a_BUR")
	world_no_assist.army_registry["a_eng_siege"] = CampaignWorldStateScript.make_army_record("a_eng_siege", "ENG", PICARDIE)
	var scheduler_no_assist := SimulationSchedulerScript.new(world_no_assist, events_no_assist)
	scheduler_no_assist.daily_systems.append(
		func(day_world) -> void: WarfareSystemScript.advance_day(day_world, events_no_assist)
	)

	var world_assist := _make_world()
	var events_assist := SimulationEventBusScript.new()
	root.add_child(events_assist)
	world_assist.army_registry.erase("a_BUR")
	world_assist.army_registry["a_eng_siege"] = CampaignWorldStateScript.make_army_record("a_eng_siege", "ENG", PICARDIE)
	_add_fleet(world_assist, "fleet_eng_siege", "ENG", STRAITS_OF_DOVER, _expected_required_power(world_assist, PICARDIE))
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_siege", "blockade").apply(world_assist, events_assist)
	_require(BlockadeSystemScript.siege_assist_bp(world_assist, ["ENG"], PICARDIE) >= BlockadeSystemScript.SIEGE_ASSIST_THRESHOLD_BP, "fixture assumption: the siege-assist fleet must clear the configured threshold")
	_require(BlockadeSystemScript.blockade_bp_by_side(world_assist, ["BUR"], PICARDIE) == 0, "blockade_bp_by_side must only credit fleets owned by the specified coalition, not the whole world's hostile presence")
	var scheduler_assist := SimulationSchedulerScript.new(world_assist, events_assist)
	scheduler_assist.daily_systems.append(
		func(day_world) -> void: WarfareSystemScript.advance_day(day_world, events_assist)
	)

	for day in 5:
		scheduler_no_assist.advance_one_day()
		scheduler_assist.advance_one_day()
	var no_assist_sieges: Dictionary = (world_no_assist.war_registry["war_1"] as Dictionary).get("sieges", {})
	var assist_sieges: Dictionary = (world_assist.war_registry["war_1"] as Dictionary).get("sieges", {})
	_require(no_assist_sieges.has(str(PICARDIE)), "fixture assumption: the unassisted siege must exist after 5 days")
	_require(assist_sieges.has(str(PICARDIE)), "fixture assumption: the assisted siege must exist after 5 days")
	var no_assist_progress := int((no_assist_sieges[str(PICARDIE)] as Dictionary).get("progress_bp", 0))
	var assist_progress := int((assist_sieges[str(PICARDIE)] as Dictionary).get("progress_bp", 0))
	_require(no_assist_progress > 0 and assist_progress > 0, "both sieges must be actively progressing")
	_require(assist_progress > no_assist_progress, "an above-threshold coastal blockade must speed the land siege's daily progress: assisted=%d unassisted=%d" % [assist_progress, no_assist_progress])

	# --- coastal_siege_support_changed fires exactly on assist transitions ---
	var world_support := _make_world()
	var events_support := SimulationEventBusScript.new()
	root.add_child(events_support)
	world_support.army_registry.erase("a_BUR")
	world_support.army_registry["a_eng_siege_support"] = CampaignWorldStateScript.make_army_record("a_eng_siege_support", "ENG", PICARDIE)
	var support_events: Array = []
	events_support.coastal_siege_support_changed.connect(func(war_id: String, province_id: int, assisted: bool) -> void: support_events.append([war_id, province_id, assisted]))
	var scheduler_support := SimulationSchedulerScript.new(world_support, events_support)
	scheduler_support.daily_systems.append(
		func(day_world) -> void: WarfareSystemScript.advance_day(day_world, events_support)
	)
	scheduler_support.advance_one_day()
	_require(support_events.is_empty(), "an unassisted siege must not fire coastal_siege_support_changed on creation")

	_add_fleet(world_support, "fleet_eng_support", "ENG", STRAITS_OF_DOVER, _expected_required_power(world_support, PICARDIE))
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_support", "blockade").apply(world_support, events_support)
	scheduler_support.advance_one_day()
	_require(support_events.size() == 1 and support_events[0] == ["war_1", PICARDIE, true], "gaining assist must fire coastal_siege_support_changed(war_1, Picardie, true) exactly once: got %s" % [support_events])

	scheduler_support.advance_one_day()
	_require(support_events.size() == 1, "an unchanged assisted state must not re-fire coastal_siege_support_changed")

	SetFleetMissionCommandScript.new("ENG", "fleet_eng_support", "idle").apply(world_support, events_support)
	scheduler_support.advance_one_day()
	_require(support_events.size() == 2 and support_events[1] == ["war_1", PICARDIE, false], "losing assist must fire coastal_siege_support_changed(war_1, Picardie, false) exactly once: got %s" % [support_events])

	# --- Port repair effectiveness reduced while blockaded ---
	var world_repair_free := _make_world()
	var events_repair_free := SimulationEventBusScript.new()
	root.add_child(events_repair_free)
	_add_fleet(world_repair_free, "fleet_bur_repair", "BUR", PICARDIE, 1)
	var fleet_free := world_repair_free.get_fleet("fleet_bur_repair")
	fleet_free["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	world_repair_free.fleet_registry["fleet_bur_repair"] = fleet_free
	_damage_ships(world_repair_free, "fleet_bur_repair", 0)
	var bur_runtime_free := world_repair_free.country_runtime("BUR")
	bur_runtime_free["treasury"] = 1000000
	bur_runtime_free["sailors"] = 1000000
	world_repair_free.set_country_runtime("BUR", bur_runtime_free)
	FleetLogisticsSystemScript.process_day(world_repair_free, events_repair_free)
	var hull_free := int(world_repair_free.get_ship("fleet_bur_repair_s0").get("hull_bp", -1))

	var world_repair_blocked := _make_world()
	var events_repair_blocked := SimulationEventBusScript.new()
	root.add_child(events_repair_blocked)
	_add_fleet(world_repair_blocked, "fleet_bur_repair", "BUR", PICARDIE, 1)
	var fleet_blocked := world_repair_blocked.get_fleet("fleet_bur_repair")
	fleet_blocked["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	world_repair_blocked.fleet_registry["fleet_bur_repair"] = fleet_blocked
	_damage_ships(world_repair_blocked, "fleet_bur_repair", 0)
	var bur_runtime_blocked := world_repair_blocked.country_runtime("BUR")
	bur_runtime_blocked["treasury"] = 1000000
	bur_runtime_blocked["sailors"] = 1000000
	world_repair_blocked.set_country_runtime("BUR", bur_runtime_blocked)
	_add_fleet(world_repair_blocked, "fleet_eng_repair_blockade", "ENG", STRAITS_OF_DOVER, _expected_required_power(world_repair_blocked, PICARDIE))
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_repair_blockade", "blockade").apply(world_repair_blocked, events_repair_blocked)
	_require(BlockadeSystemScript.province_blockade_bp(world_repair_blocked, PICARDIE) >= FleetLogisticsSystemScript.BLOCKADE_EFFECTIVENESS_THRESHOLD_BP, "fixture assumption: the blockading fleet must clear the repair-penalty threshold")
	FleetLogisticsSystemScript.process_day(world_repair_blocked, events_repair_blocked)
	var hull_blocked := int(world_repair_blocked.get_ship("fleet_bur_repair_s0").get("hull_bp", -1))

	var repair_rate := int(ShipDefinitionsScript.load_default().ship("war_galley").get("repair_rate_bp", 0))
	var expected_blocked_gain := repair_rate * (FleetLogisticsSystemScript.BASIS_POINTS - FleetLogisticsSystemScript.BLOCKADE_REPAIR_PENALTY_BP) / FleetLogisticsSystemScript.BASIS_POINTS
	_require(hull_free == repair_rate, "an unblockaded port must repair a ship at its full daily rate: expected %d got %d" % [repair_rate, hull_free])
	_require(hull_blocked == expected_blocked_gain, "a blockaded port must repair a ship at a reduced rate: expected %d got %d" % [expected_blocked_gain, hull_blocked])
	_require(hull_free > hull_blocked, "a blockaded port must repair strictly slower than an unblockaded one")

	# --- Naval construction delayed while its port is blockaded ---
	var world_build_free := _make_world()
	var events_build_free := SimulationEventBusScript.new()
	root.add_child(events_build_free)
	var bur_runtime_build_free := world_build_free.country_runtime("BUR")
	bur_runtime_build_free["treasury"] = 1000000
	bur_runtime_build_free["sailors"] = 1000000
	world_build_free.set_country_runtime("BUR", bur_runtime_build_free)
	var build_cmd_free := ConstructShipCommandScript.new("BUR", PICARDIE, "war_galley")
	_require(build_cmd_free.validate(world_build_free).is_empty(), "fixture assumption: BUR must legally be able to build a war galley at Picardie: %s" % build_cmd_free.validate(world_build_free))
	build_cmd_free.apply(world_build_free, events_build_free)
	var construction_id_free := String(world_build_free.naval_construction_registry.keys()[0])
	var construction_free: Dictionary = world_build_free.naval_construction_registry[construction_id_free]
	construction_free["completion_day"] = world_build_free.current_day
	world_build_free.naval_construction_registry[construction_id_free] = construction_free
	EconomySystemScript._complete_naval_construction(world_build_free, events_build_free, ShipDefinitionsScript.load_default())
	_require(not world_build_free.naval_construction_registry.has(construction_id_free), "an unblockaded port's construction must complete on schedule")

	var world_build_blocked := _make_world()
	var events_build_blocked := SimulationEventBusScript.new()
	root.add_child(events_build_blocked)
	var bur_runtime_build_blocked := world_build_blocked.country_runtime("BUR")
	bur_runtime_build_blocked["treasury"] = 1000000
	bur_runtime_build_blocked["sailors"] = 1000000
	world_build_blocked.set_country_runtime("BUR", bur_runtime_build_blocked)
	_add_fleet(world_build_blocked, "fleet_eng_build_blockade", "ENG", STRAITS_OF_DOVER, _expected_required_power(world_build_blocked, PICARDIE))
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_build_blockade", "blockade").apply(world_build_blocked, events_build_blocked)
	_require(BlockadeSystemScript.province_blockade_bp(world_build_blocked, PICARDIE) >= EconomySystemScript.BLOCKADE_CONSTRUCTION_THRESHOLD_BP, "fixture assumption: the blockading fleet must clear the construction-pause threshold")
	var build_cmd_blocked := ConstructShipCommandScript.new("BUR", PICARDIE, "war_galley")
	_require(build_cmd_blocked.validate(world_build_blocked).is_empty(), "fixture assumption: a blockade must not itself block legally starting construction: %s" % build_cmd_blocked.validate(world_build_blocked))
	build_cmd_blocked.apply(world_build_blocked, events_build_blocked)
	var construction_id_blocked := String(world_build_blocked.naval_construction_registry.keys()[0])
	var construction_blocked: Dictionary = world_build_blocked.naval_construction_registry[construction_id_blocked]
	construction_blocked["completion_day"] = world_build_blocked.current_day
	world_build_blocked.naval_construction_registry[construction_id_blocked] = construction_blocked
	EconomySystemScript._complete_naval_construction(world_build_blocked, events_build_blocked, ShipDefinitionsScript.load_default())
	_require(world_build_blocked.naval_construction_registry.has(construction_id_blocked), "a blockaded port's construction must not complete on schedule")
	var delayed_record: Dictionary = world_build_blocked.naval_construction_registry[construction_id_blocked]
	_require(int(delayed_record["completion_day"]) == world_build_blocked.current_day + 1, "a blockaded port must push completion forward by exactly one day, mirroring the ownership-loss pause")

	# --- Contested zones: an opposing at-sea fleet eliminates blockade eligibility ---
	var world_contested := _make_world()
	var events_contested := SimulationEventBusScript.new()
	root.add_child(events_contested)
	_add_fleet(world_contested, "fleet_eng_contested", "ENG", STRAITS_OF_DOVER, _expected_required_power(world_contested, PICARDIE))
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_contested", "blockade").apply(world_contested, events_contested)
	_require(BlockadeSystemScript.province_blockade_bp(world_contested, PICARDIE) == BlockadeSystemScript.BASIS_POINTS, "fixture assumption: an uncontested blockade must be at full strength before adding a contester")
	_add_fleet(world_contested, "fleet_bur_contest", "BUR", STRAITS_OF_DOVER, 1)
	_require(not BlockadeSystemScript.is_fleet_eligible(world_contested, "fleet_eng_contested"), "an opposing at-sea fleet sharing the zone must eliminate blockade eligibility")
	_require(BlockadeSystemScript.province_blockade_bp(world_contested, PICARDIE) == 0, "a contested blockade must register zero, not merely reduced, power")

	# A docked opposing fleet is not actually present in the zone, so it must not contest.
	var world_docked_contest := _make_world()
	var events_docked_contest := SimulationEventBusScript.new()
	root.add_child(events_docked_contest)
	_add_fleet(world_docked_contest, "fleet_eng_dc", "ENG", STRAITS_OF_DOVER, _expected_required_power(world_docked_contest, PICARDIE))
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_dc", "blockade").apply(world_docked_contest, events_docked_contest)
	_add_fleet(world_docked_contest, "fleet_bur_dc", "BUR", STRAITS_OF_DOVER, 1)
	var bur_dc_fleet := world_docked_contest.get_fleet("fleet_bur_dc")
	bur_dc_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	world_docked_contest.fleet_registry["fleet_bur_dc"] = bur_dc_fleet
	_require(BlockadeSystemScript.province_blockade_bp(world_docked_contest, PICARDIE) == BlockadeSystemScript.BASIS_POINTS, "a docked opposing fleet must not contest a blockade")

	# --- blockade_started/blockade_ended events, tracked via BlockadeSystem.process_day() ---
	var world_events := _make_world()
	var events_events := SimulationEventBusScript.new()
	root.add_child(events_events)
	var started_provinces: Array = []
	var ended_provinces: Array = []
	events_events.blockade_started.connect(func(province_id: int) -> void: started_provinces.append(province_id))
	events_events.blockade_ended.connect(func(province_id: int) -> void: ended_provinces.append(province_id))
	var scheduler_events := SimulationSchedulerScript.new(world_events, events_events)
	scheduler_events.daily_systems.append(
		func(day_world) -> void: BlockadeSystemScript.process_day(day_world, events_events)
	)
	_require(world_events.blockaded_provinces.is_empty(), "no province should be recorded as blockaded before any fleet exists")
	scheduler_events.advance_one_day()
	_require(started_provinces.is_empty(), "no blockade_started event before any eligible fleet exists")

	_add_fleet(world_events, "fleet_eng_events", "ENG", STRAITS_OF_DOVER, _expected_required_power(world_events, PICARDIE))
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_events", "blockade").apply(world_events, events_events)
	scheduler_events.advance_one_day()
	_require(started_provinces == [PICARDIE], "a genuinely blockaded province must emit exactly one blockade_started event: got %s" % [started_provinces])
	_require(world_events.blockaded_provinces.has(str(PICARDIE)), "the persisted blockade state must include the newly blockaded province")
	_require(ended_provinces.is_empty(), "no blockade_ended event yet")

	scheduler_events.advance_one_day()
	_require(started_provinces.size() == 1, "an already-blockaded province must not emit a second blockade_started event on a following day")

	SetFleetMissionCommandScript.new("ENG", "fleet_eng_events", "idle").apply(world_events, events_events)
	scheduler_events.advance_one_day()
	_require(ended_provinces == [PICARDIE], "releasing the blockade must emit exactly one blockade_ended event: got %s" % [ended_provinces])
	_require(not world_events.blockaded_provinces.has(str(PICARDIE)), "the persisted blockade state must drop the released province")

	# --- Port fully blockaded/unblocked events ---
	var world_full := _make_world()
	var events_full := SimulationEventBusScript.new()
	root.add_child(events_full)
	var started_full: Array = []
	var ended_full: Array = []
	var fully_blockaded: Array = []
	var unblocked: Array = []
	events_full.blockade_started.connect(func(province_id: int) -> void: started_full.append(province_id))
	events_full.blockade_ended.connect(func(province_id: int) -> void: ended_full.append(province_id))
	events_full.port_fully_blockaded.connect(func(province_id: int) -> void: fully_blockaded.append(province_id))
	events_full.port_unblocked.connect(func(province_id: int) -> void: unblocked.append(province_id))
	var scheduler_full := SimulationSchedulerScript.new(world_full, events_full)
	scheduler_full.daily_systems.append(
		func(day_world) -> void: BlockadeSystemScript.process_day(day_world, events_full)
	)

	_add_fleet(world_full, "fleet_eng_full", "ENG", STRAITS_OF_DOVER, 3)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_full", "blockade").apply(world_full, events_full)
	var partial_bp := BlockadeSystemScript.province_blockade_bp(world_full, PICARDIE)
	_require(partial_bp > 0 and partial_bp < BlockadeSystemScript.BASIS_POINTS, "fixture assumption: a 3-power fleet must produce a genuine but not full blockade")
	scheduler_full.advance_one_day()
	_require(started_full == [PICARDIE], "the genuine-but-partial blockade must still fire blockade_started")
	_require(fully_blockaded.is_empty(), "a partial blockade must not fire port_fully_blockaded")

	var required_full := _expected_required_power(world_full, PICARDIE)
	_add_fleet(world_full, "fleet_eng_full_2", "ENG", STRAITS_OF_DOVER, required_full)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_full_2", "blockade").apply(world_full, events_full)
	scheduler_full.advance_one_day()
	_require(fully_blockaded == [PICARDIE], "reaching full blockade power must fire exactly one port_fully_blockaded event: got %s" % [fully_blockaded])
	_require(started_full.size() == 1, "reaching full blockade must not re-fire blockade_started - the blockade was already active")

	SetFleetMissionCommandScript.new("ENG", "fleet_eng_full_2", "idle").apply(world_full, events_full)
	scheduler_full.advance_one_day()
	_require(unblocked == [PICARDIE], "dropping back below full power must fire exactly one port_unblocked event: got %s" % [unblocked])
	_require(ended_full.is_empty(), "dropping back below full power, while still genuinely blockaded, must not fire blockade_ended")

	SetFleetMissionCommandScript.new("ENG", "fleet_eng_full", "idle").apply(world_full, events_full)
	scheduler_full.advance_one_day()
	_require(ended_full == [PICARDIE], "releasing the remaining blockade must finally fire blockade_ended: got %s" % [ended_full])

	# --- blockade_level_changed fires on tier transitions, not on every bp change ---
	var world_tier := _make_world()
	var events_tier := SimulationEventBusScript.new()
	root.add_child(events_tier)
	var tier_events: Array = []
	events_tier.blockade_level_changed.connect(func(province_id: int, tier: int) -> void: tier_events.append([province_id, tier]))
	var scheduler_tier := SimulationSchedulerScript.new(world_tier, events_tier)
	scheduler_tier.daily_systems.append(
		func(day_world) -> void: BlockadeSystemScript.process_day(day_world, events_tier)
	)

	_add_fleet(world_tier, "fleet_eng_tier", "ENG", STRAITS_OF_DOVER, 1)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_tier", "blockade").apply(world_tier, events_tier)
	_require(BlockadeSystemScript.blockade_tier(BlockadeSystemScript.province_blockade_bp(world_tier, PICARDIE)) == BlockadeSystemScript.BLOCKADE_TIER_LIGHT, "fixture assumption: a single-ship fleet must land in the light blockade tier")
	scheduler_tier.advance_one_day()
	_require(tier_events == [[PICARDIE, BlockadeSystemScript.BLOCKADE_TIER_LIGHT]], "a newly formed light blockade must fire exactly one blockade_level_changed(Picardie, LIGHT): got %s" % [tier_events])

	scheduler_tier.advance_one_day()
	_require(tier_events.size() == 1, "an unchanged tier must not re-fire blockade_level_changed")

	var required_tier := _expected_required_power(world_tier, PICARDIE)
	_add_fleet(world_tier, "fleet_eng_tier_2", "ENG", STRAITS_OF_DOVER, required_tier)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_tier_2", "blockade").apply(world_tier, events_tier)
	scheduler_tier.advance_one_day()
	_require(tier_events.size() == 2 and tier_events[1] == [PICARDIE, BlockadeSystemScript.BLOCKADE_TIER_FULL], "jumping straight to a full blockade must fire exactly one blockade_level_changed(Picardie, FULL), skipping the intermediate tiers: got %s" % [tier_events])

	SetFleetMissionCommandScript.new("ENG", "fleet_eng_tier", "idle").apply(world_tier, events_tier)
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_tier_2", "idle").apply(world_tier, events_tier)
	scheduler_tier.advance_one_day()
	_require(tier_events.size() == 3 and tier_events[2] == [PICARDIE, BlockadeSystemScript.BLOCKADE_TIER_NONE], "releasing the blockade entirely must fire exactly one blockade_level_changed(Picardie, NONE): got %s" % [tier_events])

	# --- Save/load preserves blockaded_provinces; corruption is rejected ---
	var world_save_active := _make_world()
	var events_save_active := SimulationEventBusScript.new()
	root.add_child(events_save_active)
	_add_fleet(world_save_active, "fleet_eng_save", "ENG", STRAITS_OF_DOVER, _expected_required_power(world_save_active, PICARDIE))
	# Save validation requires a real, owned port for home_port_id (_add_fleet
	# defaults it to the same value as location_id, a sea zone, which is fine
	# for every non-save-testing fixture elsewhere in this file but not here).
	var save_fleet := world_save_active.get_fleet("fleet_eng_save")
	save_fleet["home_port_id"] = CALAIS
	world_save_active.fleet_registry["fleet_eng_save"] = save_fleet
	SetFleetMissionCommandScript.new("ENG", "fleet_eng_save", "blockade").apply(world_save_active, events_save_active)
	var scheduler_save_active := SimulationSchedulerScript.new(world_save_active, events_save_active)
	scheduler_save_active.daily_systems.append(
		func(day_world) -> void: BlockadeSystemScript.process_day(day_world, events_save_active)
	)
	scheduler_save_active.advance_one_day()
	_require(world_save_active.blockaded_provinces.has(str(PICARDIE)), "fixture assumption: this world must have an active recorded blockade before saving")
	var active_save := world_save_active.to_save_dict("naval-blockade-test")
	var reloaded_active := _make_world()
	var reload_error := reloaded_active.apply_save_dict(active_save)
	_require(reload_error.is_empty(), "a save with an active blockade record must load: %s" % reload_error)
	_require(reloaded_active.checksum() == world_save_active.checksum(), "an active-blockade save/load round trip must reproduce an identical checksum")
	_require(reloaded_active.blockaded_provinces.has(str(PICARDIE)), "the reloaded world must preserve the active blockade record")

	var corrupted_save := active_save.duplicate(true)
	corrupted_save["blockaded_provinces"] = {"999999": true}
	var corrupted_target := _make_world()
	_require(corrupted_target.apply_save_dict(corrupted_save).contains("blockaded"), "a blockaded-provinces record referencing an unknown province must be rejected")

	print("Naval blockade test passed. picardie_bp=%d" % BlockadeSystemScript.province_blockade_bp(world, PICARDIE))
	quit(0)
