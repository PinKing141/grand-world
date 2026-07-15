extends SceneTree

const ConflictMarkerLayerScript = preload("res://scripts/ui/conflict_marker_layer.gd")
const WAR_COUNT := 120
const BATTLES_PER_WAR := 4
const SIEGES_PER_WAR := 2
const REBUILD_SAMPLES := 12
# This path is event/zoom driven rather than per-frame. The ordinary camera
# motion gate remains 16.67 ms P95; this extreme 720-record rebuild receives a
# separate one-frame 15 Hz ceiling while later incremental updates are assessed.
const REBUILD_P95_BUDGET_MS := 66.67


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Conflict marker stress smoke failed: %s" % message)
		quit(1)


func _fixture_war(war_index: int, province_ids: PackedInt32Array, player_country: String) -> Dictionary:
	var battles := {}
	var sieges := {}
	for battle_index in BATTLES_PER_WAR:
		var province_id := province_ids[(war_index * 3 + battle_index) % 30]
		battles["battle_%03d_%02d" % [war_index, battle_index]] = {
			"status": "active",
			"province_id": province_id,
		}
	for siege_index in SIEGES_PER_WAR:
		var province_id := province_ids[(war_index * 5 + siege_index) % 30]
		sieges["siege_%03d_%02d" % [war_index, siege_index]] = {
			"province_id": province_id,
			"progress_bp": (war_index * 137 + siege_index * 1100) % 10001,
		}
	return {
		"status": "active",
		"attacker_leader": player_country,
		"defender_leader": "FRA",
		"attackers": [player_country],
		"defenders": ["FRA"],
		"war_goal": {"type": "conquest", "province_id": province_ids[war_index % 30]},
		"total_war_score": 0,
		"peace_offers": {},
		"occupied_provinces": {},
		"battles": battles,
		"sieges": sieges,
	}


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var simulation = scene.get_node("SimulationController")
	var markers := scene.get_node("ConflictMarkerLayer") as ConflictMarkerLayerScript
	var camera_controller := scene.get_node("CameraController") as StrategyCameraController
	_require(simulation.initialized and markers != null, "stress dependencies must initialize")
	camera_controller.global_position.y += 3.5 - camera_controller.camera.global_position.y
	camera_controller._sync_projection_to_height(true)
	var province_ids := ProvinceGraph.load_default().land_province_ids()
	_require(province_ids.size() >= 30, "stress fixture requires thirty canonical land provinces")

	var original_wars: Dictionary = simulation.world.war_registry.duplicate(true)
	simulation.world.war_registry.clear()
	for war_index in WAR_COUNT:
		simulation.world.war_registry["stress_war_%03d" % war_index] = _fixture_war(war_index, province_ids, simulation.world.player_country)

	markers.debug_force_refresh()
	var expected_battles := WAR_COUNT * BATTLES_PER_WAR
	var expected_sieges := WAR_COUNT * SIEGES_PER_WAR
	_require(markers.debug_battle_count() == expected_battles, "every stress battle must remain logically addressable")
	_require(markers.debug_siege_count() == expected_sieges, "every stress siege must remain logically addressable")
	_require(markers.debug_cluster_count() < expected_battles + expected_sieges, "dense conflict locations must reduce to fewer visible clusters")
	_require(markers.debug_draw_count() == 2, "a large global war must remain bounded to two conflict-marker draw batches")
	var visible_cluster_count := markers.debug_cluster_count()
	var first_signature := markers.debug_cluster_signature()

	var samples: Array[float] = []
	for sample_index in REBUILD_SAMPLES:
		var started_usec := Time.get_ticks_usec()
		markers.debug_force_refresh()
		samples.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
		_require(markers.debug_cluster_signature() == first_signature, "clustering must be deterministic across rebuild %d" % sample_index)
	samples.sort()
	var p95_index := clampi(ceili(float(samples.size()) * 0.95) - 1, 0, samples.size() - 1)
	var p95_ms := samples[p95_index]
	_require(p95_ms <= REBUILD_P95_BUDGET_MS, "720 logical markers must rebuild within %.2f ms P95; measured %.2f ms" % [REBUILD_P95_BUDGET_MS, p95_ms])

	var selected: Array[Dictionary] = []
	markers.conflict_marker_selected.connect(func(marker: Dictionary) -> void: selected.append(marker))
	markers.war_hud = null
	markers._on_map_click_requested(markers.debug_cluster_screen_position(0))
	_require(selected.size() == 1 and int(selected[0].get("cluster_size", 0)) > 1, "a dense stress cluster must remain clickable and expose its hidden members")

	simulation.world.war_registry = original_wars
	markers.debug_force_refresh()
	print("Conflict marker stress smoke passed. logical=%d clusters=%d draws=2 rebuild_p95_ms=%.3f" % [expected_battles + expected_sieges, visible_cluster_count, p95_ms])
	quit(0)
