extends SceneTree

const ConflictMarkerLayerScript = preload("res://scripts/ui/conflict_marker_layer.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Conflict marker layer smoke failed: %s" % message)
		quit(1)


func _run() -> void:
	var capture_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
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
	var war_hud := scene.get_node("WarHUD") as WarHUD
	_require(simulation.initialized and markers != null, "conflict presentation dependencies must initialize")
	_require(markers.debug_battle_count() == 0 and markers.debug_siege_count() == 0, "a fresh campaign must not invent conflict markers")

	simulation.world.war_registry["visual_fixture"] = {
		"status": "active",
		"attacker_leader": simulation.world.player_country,
		"defender_leader": "FRA",
		"attackers": [simulation.world.player_country],
		"defenders": ["FRA"],
		"war_goal": {"type": "conquest", "province_id": 222},
		"total_war_score": 0,
		"peace_offers": {},
		"occupied_provinces": {},
		"battles": {
			"battle_fixture_a": {"status": "active", "province_id": 222},
			"battle_fixture_b": {"status": "active", "province_id": 222},
			"battle_fixture_c": {"status": "active", "province_id": 222},
		},
		"sieges": {
			"222": {"province_id": 222, "progress_bp": 6400, "side": 1, "breached": false},
		},
	}
	markers.debug_force_refresh()
	_require(markers.debug_battle_count() == 3 and markers.debug_siege_count() == 1, "authoritative battle and siege state must produce every logical marker")
	_require(markers.debug_cluster_count() == 2, "three co-located battles must collapse into one battle cluster while the siege keeps its higher-detail square")
	_require(markers.debug_marker_instances() == Vector2i(1, 1), "battle and siege artwork must use one atlas-backed instance per visible cluster")
	_require(markers.debug_draw_count() == 2, "all active battles and sieges must stay within two draw batches")
	_require(markers.debug_priority_order() == ["siege", "battle"], "battle markers must render above sieges in a dense overlap")
	var selected_markers: Array[Dictionary] = []
	markers.conflict_marker_selected.connect(func(marker: Dictionary) -> void: selected_markers.append(marker))
	var marker_position := markers.debug_cluster_screen_position(0)
	markers._on_map_click_requested(marker_position)
	markers._on_map_click_requested(marker_position)
	_require(selected_markers.size() == 2, "clicking a visible marker must emit an inspectable marker selection")
	_require(int(selected_markers[0].get("cluster_size", 0)) == 3, "a clicked cluster must report its complete logical member count")
	_require(String(selected_markers[0].get("marker_id", "")) != String(selected_markers[1].get("marker_id", "")), "repeated clicks must cycle deterministically through co-located conflicts")
	_require(war_hud.diplomacy_panel.visible and war_hud._current_war_id == "visual_fixture", "marker selection must open and focus the war inspector")
	_require(war_hud.details_label.text.contains("marker 2 of 3 in cluster"), "the war inspector must explain the focused cluster member")
	if not capture_path.is_empty():
		root.size = Vector2i(1152, 648)
		camera_controller.global_position.y += 1.0 - camera_controller.camera.global_position.y
		camera_controller._sync_projection_to_height(true)
		camera_controller.focus_world_position(markers.anchor_world_position(222))
		for hud_name in ["MapHUD", "SimulationHUD", "EconomyHUD", "WarHUD", "AIDebugHUD", "CharacterHUD", "CountryDepthHUD"]:
			var hud := scene.get_node_or_null(hud_name) as Control
			if hud != null:
				hud.visible = false
		for _frame in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		_require(capture != null and capture.save_png(capture_path) == OK, "conflict marker capture must save")

	camera_controller.global_position.y += 13.0 - camera_controller.camera.global_position.y
	camera_controller._sync_projection_to_height(true)
	markers.debug_force_refresh()
	_require(not markers.debug_markers_visible(), "conflict markers must cull at world zoom")

	simulation.world.war_registry.erase("visual_fixture")
	camera_controller.reset_camera()
	markers.debug_force_refresh()
	_require(markers.debug_battle_count() == 0 and markers.debug_siege_count() == 0, "ending a conflict must clear both marker batches")
	print("Conflict marker layer smoke passed. logical_battles=3 battle_instances=1 siege_instances=1 draws=2 clickable_cluster=3")
	quit(0)
