extends SceneTree

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBus = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationScheduler = preload("res://scripts/simulation/simulation_scheduler.gd")
const SelectPlayerCountryCommand = preload("res://scripts/simulation/commands/select_player_country_command.gd")
const ChangeProvinceOwnerCommand = preload("res://scripts/simulation/commands/change_province_owner_command.gd")
const CampaignSaveService = preload("res://scripts/simulation/campaign_save_service.gd")
const SimulationDate = preload("res://scripts/simulation/simulation_date.gd")

const TEST_SAVE_PATH := "user://tests/phase2_core_save.json"


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Simulation core test failed: %s" % message)
		quit(1)


func _new_world() -> CampaignWorldState:
	var world := CampaignWorldState.new()
	world.initialize(
		{1: "SWE", 2: "DAN", 3: "SWE", 4: "No Owner"},
		{"SWE": "Sweden", "DAN": "Denmark"},
		"test_1444",
		123456
	)
	return world


func _run_replay() -> CampaignWorldState:
	var world := _new_world()
	var events := SimulationEventBus.new()
	root.add_child(events)
	var scheduler := SimulationScheduler.new(world, events)
	scheduler.submit(SelectPlayerCountryCommand.new("SWE", "test", 0))
	scheduler.submit(ChangeProvinceOwnerCommand.new(2, "SWE", "test", 31))
	scheduler.submit(ChangeProvinceOwnerCommand.new(1, "DAN", "test", 400))
	for day in range(3653):
		world.next_random_u32("events")
		scheduler.advance_one_day()
	return world


func _run() -> void:
	# Calendar boundaries use a proleptic Gregorian calendar from 1444-11-11.
	_require(SimulationDate.format_day(0) == "11 November 1444", "campaign must start on 11 November 1444")
	_require(SimulationDate.format_day(19) == "30 November 1444", "November boundary must be correct")
	_require(SimulationDate.format_day(20) == "1 December 1444", "month rollover must be correct")
	_require(SimulationDate.is_leap_year(1600), "1600 must be a leap year")
	_require(not SimulationDate.is_leap_year(1500), "1500 must not be a leap year")
	var known_day := SimulationDate.date_to_day(1500, 3, 1)
	_require(SimulationDate.day_to_date(known_day) == {"year": 1500, "month": 3, "day": 1}, "date conversion must round-trip")

	var world := _new_world()
	_require(world.get_province_owner(4).is_empty(), "non-country source labels must normalize to empty ownership")
	_require(world.get_country_provinces("SWE") == [1, 3], "country index must be sorted and complete")
	var events := SimulationEventBus.new()
	root.add_child(events)
	var rejected: Array[String] = []
	var month_events := [0]
	var year_events := [0]
	events.command_rejected.connect(func(_id: int, _type: String, reason: String) -> void: rejected.append(reason))
	events.month_started.connect(func(_day: int, _year: int, _month: int) -> void: month_events[0] += 1)
	events.year_started.connect(func(_day: int, _year: int) -> void: year_events[0] += 1)
	var scheduler := SimulationScheduler.new(world, events)
	scheduler.submit(SelectPlayerCountryCommand.new("SWE"))
	scheduler.submit(ChangeProvinceOwnerCommand.new(2, "SWE"))
	scheduler.submit(ChangeProvinceOwnerCommand.new(999, "SWE"))
	scheduler.process_commands()
	_require(world.player_country == "SWE", "player-country command must apply")
	_require(world.get_province_owner(2) == "SWE", "ownership command must apply")
	_require(world.get_country_provinces("DAN").is_empty(), "old owner index must update")
	_require(world.get_country_provinces("SWE") == [1, 2, 3], "new owner index must update deterministically")
	_require(rejected.size() == 1 and rejected[0].contains("999"), "invalid commands must publish a reason")
	scheduler.advance_days(60)
	_require(month_events[0] >= 2, "month-boundary events must be published")
	_require(year_events[0] >= 1, "year-boundary events must be published")

	var replay_a := _run_replay()
	var replay_b := _run_replay()
	_require(replay_a.checksum() == replay_b.checksum(), "fixed command and RNG streams must replay identically")
	_require(replay_a.current_day == 3653, "ten-year soak must reach the requested day")

	var save_result := CampaignSaveService.save_world(replay_a, TEST_SAVE_PATH, "test")
	_require(save_result["ok"], "save must succeed: %s" % save_result["message"])
	var loaded := _new_world()
	var load_result := CampaignSaveService.load_world(loaded, TEST_SAVE_PATH)
	_require(load_result["ok"], "load must succeed: %s" % load_result["message"])
	_require(loaded.checksum() == replay_a.checksum(), "save/load must preserve the authoritative checksum")
	var incompatible := replay_a.to_save_dict("test")
	incompatible["schema_version"] = 999
	_require(not loaded.apply_save_dict(incompatible).is_empty(), "unsupported schemas must be rejected")
	var corrupted_path := "user://tests/phase2_corrupted_save.json"
	var corrupted := replay_a.to_save_dict("test")
	corrupted["current_day"] = int(corrupted["current_day"]) + 1
	var corrupted_file := FileAccess.open(corrupted_path, FileAccess.WRITE)
	corrupted_file.store_string(JSON.stringify(corrupted))
	corrupted_file.close()
	var checksum_before_corrupt_load := loaded.checksum()
	var corrupted_result := CampaignSaveService.load_world(loaded, corrupted_path)
	_require(not corrupted_result["ok"], "checksum-corrupted saves must be rejected")
	_require(loaded.checksum() == checksum_before_corrupt_load, "failed loads must not mutate the active campaign")

	var absolute_test_save := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(absolute_test_save):
		DirAccess.remove_absolute(absolute_test_save)
	var absolute_corrupted_save := ProjectSettings.globalize_path(corrupted_path)
	if FileAccess.file_exists(absolute_corrupted_save):
		DirAccess.remove_absolute(absolute_corrupted_save)
	print("Simulation core test passed. checksum=%s" % replay_a.checksum().left(16))
	quit(0)
