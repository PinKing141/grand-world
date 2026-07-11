extends SceneTree

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")
const ChangeProvinceOwnerCommand = preload("res://scripts/simulation/commands/change_province_owner_command.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Frame-rate determinism test failed: %s" % message)
		quit(1)


func _make_controller(node_name: String) -> GrandWorldSimulationController:
	var data := CountryData.new()
	data.name = "%sCountryData" % node_name
	data.country_id_to_country_name = {"SWE": "Sweden", "DAN": "Denmark"}
	data.country_id_to_color = {"SWE": Color.BLUE, "DAN": Color.RED}
	data.province_id_to_owner = {1: "SWE", 2: "DAN", 3: "SWE"}
	var controller := GrandWorldSimulationController.new()
	controller.name = node_name
	controller.country_data = data
	root.add_child(controller)
	controller.set_process(false)
	controller.set_game_speed(3)
	controller.scheduler.submit(ChangeProvinceOwnerCommand.new(2, "SWE", "test", 50))
	return controller


func _run() -> void:
	var at_30_fps := _make_controller("At30Fps")
	var at_120_fps := _make_controller("At120Fps")
	for frame in range(300):
		at_30_fps._process(1.0 / 30.0)
	for frame in range(1200):
		at_120_fps._process(1.0 / 120.0)
	_require(at_30_fps.world.current_day == at_120_fps.world.current_day, "equal elapsed time must schedule the same day count")
	_require(at_30_fps.world.current_day == 100, "ten seconds at speed 3 must advance 100 days")
	_require(at_30_fps.world.checksum() == at_120_fps.world.checksum(), "30 FPS and 120 FPS runs must produce the same checksum")
	print("Frame-rate determinism test passed. day=%d checksum=%s" % [
		at_30_fps.world.current_day,
		at_30_fps.world.checksum().left(16),
	])
	quit(0)
