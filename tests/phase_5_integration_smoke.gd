extends SceneTree

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const WarHUDScript = preload("res://scripts/ui/war_hud.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 5 integration smoke failed: %s" % message)
		quit(1)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var simulation := scene.get_node("SimulationController") as ControllerScript
	var hud := scene.get_node("WarHUD") as WarHUDScript
	var country_hud := scene.get_node("EconomyHUD") as EconomyHUD
	var map_render := scene.get_node("Map")
	var map_hud := scene.get_node("MapHUD") as MapHUD
	_require(simulation.initialized, "campaign must initialize")
	_require(hud != null and hud.diplomacy_button != null, "war HUD must instantiate in the packaged scene")

	var player := "CAS" if simulation.world.has_country("CAS") else String(simulation.world.country_states.keys()[0])
	simulation.choose_player_country(player)
	simulation.scheduler.process_commands()
	await process_frame
	_require(not hud.diplomacy_button.visible, "the legacy floating diplomacy button must remain hidden")
	_require(country_hud.diplomacy_button.visible and country_hud.diplomacy_button.text == "Dip", "choosing a country must expose diplomacy through the unified top-left HUD")
	country_hud.diplomacy_button.pressed.emit()
	await process_frame
	_require(hud.diplomacy_panel.visible, "the unified Dip button must open the diplomacy and war panel")

	var target_id := -1
	var target_tag := ""
	var province_ids := simulation.world.province_states.keys()
	province_ids.sort()
	for raw_id in province_ids:
		var owner := simulation.world.get_province_owner(int(raw_id))
		if not owner.is_empty() and owner != player and CountryDepthSystemScript.has_valid_claim_or_core(simulation.world, player, int(raw_id)):
			target_id = int(raw_id)
			target_tag = owner
			break
	_require(target_id >= 0, "the scenario needs a justified foreign target province")
	hud._on_province_selected({"province_id": target_id, "owner_tag": target_tag, "owner_name": target_tag, "is_playable": true})
	var target_name := String(simulation.country_data.country_id_to_country_name.get(target_tag, "Unknown country"))
	_require(hud.target_title.text == target_name and not hud.target_title.text.contains(target_tag), "diplomacy target must show only the full country name")
	_require(not hud.declare_war_button.disabled, "a valid foreign province must enable the declaration flow")
	hud._declare_war()
	simulation.scheduler.process_commands()
	await process_frame
	var wars := simulation.country_wars(player)
	_require(wars.size() == 1, "the UI declaration must reach authoritative WarState")
	var war_id := wars[0]
	_require(DiplomacySystemScript.are_at_war(simulation.world, player, target_tag), "the target must become hostile")
	_require(hud.war_option.item_count == 1 and hud._current_war_id == war_id, "war overview must select the new war")
	_require(not hud.war_option.get_item_text(0).contains(player) and not hud.war_option.get_item_text(0).contains(target_tag), "war list must use full country names instead of tags")
	_require(hud.war_summary.text.contains("War score"), "war overview must explain score and goal")

	hud._show_war_map()
	await process_frame
	_require(not map_render.display_uses_political_colors, "war map must use the strategy overlay")
	_require(map_hud.mode_legend.text.begins_with("War:") and map_hud.mode_legend.text.contains("double border"), "war overlay must explain the war-goal shape as well as its colours")
	_require(map_render.debug_war_goal_province() == target_id, "war map must bind its authoritative goal as a semantic target")
	_require(bool(map_render.final_material.get_shader_parameter("war_goal_enabled")), "war-goal border rendering must be enabled in the final shader")
	var goal_overlay_color: Color = map_render.color_map.get_pixel(target_id % map_render.color_map.get_width(), floori(float(target_id) / map_render.color_map.get_width()))
	_require(Vector3(goal_overlay_color.r, goal_overlay_color.g, goal_overlay_color.b).distance_to(Vector3(1.0, 0.82, 0.12)) > 0.1, "war goals must preserve side/occupation fill instead of replacing the province with solid gold")
	hud._show_relations_map()
	await process_frame
	_require(map_hud.mode_legend.text.begins_with("Relations:"), "relations overlay must explain its colours")
	_require(map_render.debug_war_goal_province() == -1, "leaving the war map must clear its semantic goal border")
	hud._show_access_map()
	await process_frame
	_require(map_hud.mode_legend.text.begins_with("Military access:"), "military-access overlay must explain its permissions")
	map_hud.set_map_mode(MapHUD.MODE_POLITICAL)
	_require(map_render.display_uses_political_colors, "political mode must restore country colours")

	var checksum_before_save := simulation.world_checksum()
	var save_result := simulation.quick_save()
	_require(bool(save_result["ok"]), "an active war quick save must succeed")
	simulation.world.war_registry[war_id]["total_war_score"] = 77
	_require(simulation.world_checksum() != checksum_before_save, "the test mutation must affect the checksum")
	var load_result := simulation.quick_load()
	_require(bool(load_result["ok"]), "an active war quick load must succeed")
	_require(simulation.world_checksum() == checksum_before_save, "loading must restore exact diplomacy and war state")
	_require(simulation.country_wars(player) == [war_id], "active participants must survive load")

	var save_path := ProjectSettings.globalize_path(ControllerScript.QUICK_SAVE_PATH)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	print("Phase 5 integration smoke passed. war=%s target=%s/%d" % [war_id, target_tag, target_id])
	quit(0)
