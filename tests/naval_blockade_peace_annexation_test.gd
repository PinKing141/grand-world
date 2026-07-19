extends SceneTree

## FL5.2: confirms BlockadeSystem's event ordering holds across the two
## transitions naval_blockade_test.gd does not exercise - a war concluding
## in peace, and the blockaded province itself being annexed by the
## blockading side - both mid-blockade, both driven through the real daily
## scheduler rather than asserted in prose. BlockadeSystem is a pure query
## layer (see its own header comment): neither transition needs a special
## case in BlockadeSystem itself, since province_blockade_bp() is always
## recomputed live from current war/ownership state. This test proves that
## claim rather than assuming it.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")
const SetFleetMissionCommandScript = preload("res://scripts/simulation/commands/set_fleet_mission_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
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


func _expected_required_power(world: CampaignWorldState, province_id: int) -> int:
	var naval_definitions := preload("res://scripts/simulation/naval_definitions.gd").load_default()
	return BlockadeSystemScript.required_power(world, province_id, naval_definitions)


func _test_peace_releases_blockade_same_day() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var started: Array = []
	var ended: Array = []
	events.blockade_started.connect(func(province_id: int) -> void: started.append(province_id))
	events.blockade_ended.connect(func(province_id: int) -> void: ended.append(province_id))
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(
		func(day_world) -> void: BlockadeSystemScript.process_day(day_world, events)
	)

	_add_fleet(world, "fleet_eng", "ENG", STRAITS_OF_DOVER, _expected_required_power(world, PICARDIE))
	SetFleetMissionCommandScript.new("ENG", "fleet_eng", "blockade").apply(world, events)
	scheduler.advance_one_day()
	_check(started == [PICARDIE], "PEACE_FIXTURE_NOT_BLOCKADED", "fixture assumption: the blockade must be genuinely active before peace concludes: got %s" % [started])
	_check(BlockadeSystemScript.province_blockade_bp(world, PICARDIE) == BlockadeSystemScript.BASIS_POINTS, "PEACE_FIXTURE_NOT_FULL", "fixture assumption: the blockade must be at full strength before peace concludes")

	# Simulate PeaceSystem concluding the war - the same "status" mutation
	# peace_system.gd itself performs (see peace_system.gd:180), applied
	# directly here since this is a BlockadeSystem query-layer test, not a
	# PeaceSystem integration test. Per the finish-line scheduler order
	# (simulation_controller.gd), any command-driven change like this lands
	# before the day's daily_systems run, so the very next
	# BlockadeSystem.process_day() tick must already see the war as over.
	world.war_registry["war_1"]["status"] = "ended"
	_check(BlockadeSystemScript.province_blockade_bp(world, PICARDIE) == 0, "PEACE_QUERY_STILL_BLOCKADED", "province_blockade_bp must drop to zero the instant the war ends, with no dependency on a scheduler tick")
	scheduler.advance_one_day()
	_check(ended == [PICARDIE], "PEACE_NOT_RELEASED_SAME_DAY", "a war concluding in peace must release an active blockade on the very next process_day() tick, not one day late: got ended=%s" % [ended])
	_check(not world.blockaded_provinces.has(str(PICARDIE)), "PEACE_STILL_PERSISTED", "the persisted blockaded_provinces record must drop the province once peace releases it")


func _test_annexation_releases_blockade_same_day() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var started: Array = []
	var ended: Array = []
	events.blockade_started.connect(func(province_id: int) -> void: started.append(province_id))
	events.blockade_ended.connect(func(province_id: int) -> void: ended.append(province_id))
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(
		func(day_world) -> void: BlockadeSystemScript.process_day(day_world, events)
	)

	_add_fleet(world, "fleet_eng", "ENG", STRAITS_OF_DOVER, _expected_required_power(world, PICARDIE))
	SetFleetMissionCommandScript.new("ENG", "fleet_eng", "blockade").apply(world, events)
	scheduler.advance_one_day()
	_check(started == [PICARDIE], "ANNEX_FIXTURE_NOT_BLOCKADED", "fixture assumption: the blockade must be genuinely active before annexation: got %s" % [started])

	# Simulate the blockading side (ENG) annexing the blockaded province
	# outright - a province ownership change is the same "target_owner ==
	# owner" self-exclusion blockaded_provinces_for_fleet() already applies
	# to a country's own territory, applied here mid-blockade rather than
	# only at fixture setup.
	var picardie_state: Dictionary = world.province_states[PICARDIE]
	picardie_state["owner"] = "ENG"
	world.province_states[PICARDIE] = picardie_state
	_check(BlockadeSystemScript.province_blockade_bp(world, PICARDIE) == 0, "ANNEX_QUERY_STILL_BLOCKADED", "a province annexed by the blockading side must immediately stop registering as blockaded - a country cannot blockade its own territory")
	scheduler.advance_one_day()
	_check(ended == [PICARDIE], "ANNEX_NOT_RELEASED_SAME_DAY", "annexing the blockaded province must release the blockade on the very next process_day() tick: got ended=%s" % [ended])
	_check(not world.blockaded_provinces.has(str(PICARDIE)), "ANNEX_STILL_PERSISTED", "the persisted blockaded_provinces record must drop a province annexed by the blockading side")


func _run() -> void:
	_test_peace_releases_blockade_same_day()
	_test_annexation_releases_blockade_same_day()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval blockade peace/annexation test failed: %s" % failure)
		print("Naval blockade peace/annexation test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval blockade peace/annexation test passed. cases=peace_release,annexation_release")
	quit(0)
