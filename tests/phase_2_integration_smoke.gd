extends SceneTree

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")
const SimulationHUD = preload("res://scripts/ui/simulation_hud.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 2 integration smoke test failed: %s" % message)
		quit(1)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var simulation := scene.get_node("SimulationController") as GrandWorldSimulationController
	var country_data := scene.get_node("Map/ProvinceSelector/CountryData") as CountryData
	var simulation_hud := scene.get_node("SimulationHUD") as SimulationHUD
	_require(simulation != null and simulation.initialized, "simulation controller must bootstrap")
	_require(simulation.world.current_day == 0, "campaign must begin at day zero")
	_require(simulation.world.paused, "new campaigns must begin paused")
	_require(simulation_hud.date_label.text == "11 November 1444", "HUD must show the scenario date")

	simulation.choose_player_country("SWE")
	simulation.scheduler.process_commands()
	_require(simulation.world.player_country == "SWE", "country selection must enter WorldState")
	_require(simulation_hud.player_label.text.contains("Sweden"), "HUD must show the player country")

	var checksum_before := simulation.world_checksum()
	simulation.change_province_owner_for_testing(1, "DAN")
	simulation.scheduler.process_commands()
	await process_frame
	_require(simulation.world.get_province_owner(1) == "DAN", "ownership command must mutate WorldState")
	_require(country_data.province_id_to_owner.get(1, "") == "DAN", "presentation owner mirror must update")
	_require(simulation.world_checksum() != checksum_before, "authoritative mutation must change the checksum")

	simulation.set_game_speed(3)
	simulation.scheduler.process_commands()
	_require(not simulation.world.paused and simulation.world.game_speed == 3, "speed command must resume at the requested speed")
	simulation.set_paused(true)
	simulation.scheduler.process_commands()
	_require(simulation.world.paused, "pause command must stop authoritative time")
	var day_before_step := simulation.world.current_day
	simulation.debug_step_one_day()
	_require(simulation.world.current_day == day_before_step + 1, "debug step must advance exactly one day")

	var saved_checksum := simulation.world_checksum()
	var save_result := simulation.quick_save()
	_require(save_result["ok"], "quick save must succeed")
	simulation.change_province_owner_for_testing(1, "SWE")
	simulation.scheduler.process_commands()
	_require(simulation.world.get_province_owner(1) == "SWE", "post-save mutation must apply")
	var load_result := simulation.quick_load()
	_require(load_result["ok"], "quick load must succeed")
	_require(simulation.world_checksum() == saved_checksum, "quick load must restore the checksum")
	_require(country_data.province_id_to_owner.get(1, "") == "DAN", "load must rebuild presentation ownership")

	var quick_save_absolute := ProjectSettings.globalize_path(GrandWorldSimulationController.QUICK_SAVE_PATH)
	if FileAccess.file_exists(quick_save_absolute):
		DirAccess.remove_absolute(quick_save_absolute)
	print("Phase 2 integration smoke test passed.")
	quit(0)
