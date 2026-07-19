extends SceneTree

const ConflictMarkerLayerScript = preload("res://scripts/ui/conflict_marker_layer.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

const STRAITS_OF_DOVER := 1271
const PICARDIE := 89


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

	# Naval battle marker (04_N4 "Player feedback"): a structurally separate
	# registry/multimesh from land battles/sieges - kept at a different
	# province than the land fixture above (222) so it never clusters with
	# it, proving the two marker families coexist independently rather than
	# needing to share a location to both prove clustering works.
	var naval_hud := scene.get_node("NavalHUD") as NavalHUD
	# NavalHUD only shows the panel for a chosen player (see _refresh_all()'s
	# empty-tag guard); the land fixture above never needed one since
	# WarHUD.focus_conflict_marker() doesn't check ownership.
	simulation.choose_player_country("ENG")
	simulation.scheduler.process_commands()
	var player := "ENG"
	simulation.world.fleet_registry["naval_fixture_fleet"] = CampaignWorldStateScript.make_fleet_record("naval_fixture_fleet", player, STRAITS_OF_DOVER)
	var naval_battle := CampaignWorldStateScript.make_naval_battle_record("naval_fixture_battle", "visual_fixture", STRAITS_OF_DOVER, simulation.world.current_day)
	naval_battle["attacker_fleets"] = ["naval_fixture_fleet"]
	naval_battle["defender_fleets"] = ["naval_fixture_enemy_fleet"]
	simulation.world.fleet_registry["naval_fixture_enemy_fleet"] = CampaignWorldStateScript.make_fleet_record("naval_fixture_enemy_fleet", "FRA", STRAITS_OF_DOVER)
	simulation.world.naval_battle_registry["naval_fixture_battle"] = naval_battle
	markers.debug_force_refresh()
	_require(markers.debug_naval_battle_count() == 1, "an active naval battle must produce a naval marker")
	_require(markers.debug_naval_battle_visible(), "the naval battle marker must be visible at normal zoom")
	_require(markers.debug_cluster_count() == 3, "the naval battle must add exactly one more cluster alongside the land battle and siege")
	# _rebuild() always assigns _clusters as [battle..., siege..., naval...]
	# (see conflict_marker_layer.gd); with exactly one cluster in each
	# category here, the naval cluster is deterministically the last one.
	var naval_marker_position := markers.debug_cluster_screen_position(2)
	var naval_selected_markers: Array[Dictionary] = []
	markers.conflict_marker_selected.connect(func(marker: Dictionary) -> void: naval_selected_markers.append(marker))
	markers._on_map_click_requested(naval_marker_position)
	_require(naval_selected_markers.size() == 1 and String(naval_selected_markers[0].get("marker_type", "")) == "naval_battle", "clicking the naval battle marker must emit a naval_battle-typed selection")
	_require(naval_hud.naval_panel.visible, "clicking a naval battle marker must open the naval panel")
	_require(String(naval_hud._selected_battle_id()) == "naval_fixture_battle", "clicking a naval battle marker must select it in the battle panel")
	simulation.world.fleet_registry.erase("naval_fixture_fleet")
	simulation.world.fleet_registry.erase("naval_fixture_enemy_fleet")
	simulation.world.naval_battle_registry.erase("naval_fixture_battle")
	markers.debug_force_refresh()
	_require(markers.debug_naval_battle_count() == 0, "removing the naval battle must clear its marker batch")

	# FL1.4 blockade marker: a persistent, always-on cue (not the manual
	# NavalHUD "show blockade map" overlay) - anchored on the blockaded LAND
	# province itself (PICARDIE), not the fleet's own sea zone (which is the
	# same STRAITS_OF_DOVER zone the now-cleared naval battle fixture used -
	# proving the two marker families never needed to share a location to
	# each prove their own clustering independently).
	simulation.world.war_registry["visual_fixture"]["attackers"] = ["ENG"]
	simulation.world.war_registry["visual_fixture"]["defenders"] = ["FRA"]
	simulation.world.set_province_owner(PICARDIE, "FRA")
	simulation.world.fleet_registry["blockade_fixture_fleet"] = CampaignWorldStateScript.make_fleet_record("blockade_fixture_fleet", player, STRAITS_OF_DOVER)
	var blockade_fleet: Dictionary = simulation.world.get_fleet("blockade_fixture_fleet")
	blockade_fleet["location_id"] = STRAITS_OF_DOVER
	blockade_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	blockade_fleet["mission"] = "blockade"
	simulation.world.ship_registry["blockade_fixture_ship"] = CampaignWorldStateScript.make_ship_record("blockade_fixture_ship", player, "blockade_fixture_fleet", "war_galley", 0)
	blockade_fleet["ship_ids"] = ["blockade_fixture_ship"]
	simulation.world.fleet_registry["blockade_fixture_fleet"] = blockade_fleet
	FleetSystemScript.recompute_aggregate(simulation.world, "blockade_fixture_fleet")
	markers.debug_force_refresh()
	_require(markers.debug_blockade_count() == 1, "an eligible blockading fleet at war with the province owner must produce a blockade marker")
	_require(markers.debug_blockade_visible(), "the blockade marker must be visible at normal zoom")
	_require(markers.debug_cluster_count() == 3, "the blockade must add exactly one more cluster alongside the land battle and siege (the naval battle cluster was already cleared above)")
	var blockade_marker_position := markers.debug_cluster_screen_position(2)
	var blockade_selected_markers: Array[Dictionary] = []
	markers.conflict_marker_selected.connect(func(marker: Dictionary) -> void: blockade_selected_markers.append(marker))
	markers._on_map_click_requested(blockade_marker_position)
	_require(blockade_selected_markers.size() == 1 and String(blockade_selected_markers[0].get("marker_type", "")) == "blockade", "clicking the blockade marker must emit a blockade-typed selection")
	_require((blockade_selected_markers[0].get("attacker_country_ids", []) as Array) == ["ENG"], "a blockade marker must identify every contributing attacker country")
	_require(String(blockade_selected_markers[0].get("primary_attacker_country_id", "")) == "ENG", "a blockade marker must identify its strongest attacker for compact presentation")
	_require(naval_hud.naval_panel.visible, "clicking a blockade marker must open the naval panel")
	_require(naval_hud.blockade_label.text.contains("blockade") and naval_hud.blockade_label.text.contains("England"), "clicking a blockade marker must select the province and name the blockading attacker in the naval panel")
	simulation.world.fleet_registry.erase("blockade_fixture_fleet")
	simulation.world.ship_registry.erase("blockade_fixture_ship")
	markers.debug_force_refresh()
	_require(markers.debug_blockade_count() == 0, "removing the blockading fleet must clear the blockade marker")

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
	print("Conflict marker layer smoke passed. logical_battles=3 battle_instances=1 siege_instances=1 draws=2 clickable_cluster=3 naval_battle=1 blockade=1")
	quit(0)
