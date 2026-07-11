extends SceneTree

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 2 global soak failed: %s" % message)
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
	_require(simulation.initialized, "global scenario must initialize")
	var province_count := simulation.world.province_states.size()
	var country_count := simulation.world.country_states.size()
	var owner_samples := {
		1: simulation.world.get_province_owner(1),
		151: simulation.world.get_province_owner(151),
		1128: simulation.world.get_province_owner(1128),
		1796: simulation.world.get_province_owner(1796),
	}
	var started := Time.get_ticks_usec()
	simulation.scheduler.advance_days(3653)
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	_require(simulation.world.current_day == 3653, "global campaign must advance ten years")
	_require(simulation.world.province_states.size() == province_count, "province registry must remain stable")
	_require(simulation.world.country_states.size() == country_count, "country registry must remain stable")
	for province_id in owner_samples:
		_require(simulation.world.get_province_owner(province_id) == owner_samples[province_id], "uncommanded ownership must remain stable for province %d" % province_id)
	_require(not simulation.world.checksum().is_empty(), "global soak must finish with a checksum")
	print("Phase 2 global ten-year soak passed in %.2f ms. checksum=%s" % [
		elapsed_ms,
		simulation.world.checksum().left(16),
	])
	quit(0)
