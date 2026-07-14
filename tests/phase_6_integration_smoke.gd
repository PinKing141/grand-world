extends SceneTree

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const AIDebugHUDScript = preload("res://scripts/ui/ai_debug_hud.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 6 integration smoke failed: %s" % message)
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
	var ai_hud := scene.get_node("AIDebugHUD") as AIDebugHUDScript
	var map_hud := scene.get_node("MapHUD") as MapHUD
	var map_render := scene.get_node("Map")
	_require(simulation.initialized, "campaign must initialize")
	_require(simulation.ai_definitions != null and simulation.ai_definitions.is_valid(), "AI definitions must be packaged and valid")
	_require(ai_hud != null and ai_hud.campaign_button != null, "AI campaign HUD must instantiate in the packaged scene")
	_require(ai_hud.country_option.item_count == 5, "the inspector must expose all five Iberian slice countries")

	ai_hud.panel.show()
	ai_hud._refresh_all()
	_require(ai_hud.objective_label.text.contains("Castile") and not ai_hud.objective_label.text.contains("CAS"), "campaign panel must use the country's full display name")
	_require(ai_hud.status_label.text.contains("Day 0/7305"), "campaign panel must show the twenty-year completion horizon")
	_require(ai_hud.strategy_label.text.contains("Goal:"), "AI inspector must expose strategic state")
	_require(ai_hud.resources_label.text.contains("desired"), "AI inspector must expose military and reserve targets")

	# Exercise the real scene scheduler so UI refreshes from actual AI events.
	simulation.scheduler.advance_days(35)
	await process_frame
	ai_hud._refresh_all()
	var snapshot := simulation.ai_debug_snapshot("CAS")
	_require(not snapshot.is_empty(), "controller must expose a country AI snapshot")
	_require((snapshot.get("decision_history", []) as Array).size() > 0, "scheduled AI decisions must reach the inspector")
	_require(ai_hud.history_label.text.contains("Recent decisions"), "decision history must be readable in the panel")

	ai_hud._show_objective_map()
	await process_frame
	_require(not map_render.display_uses_political_colors, "AI objectives must render through the strategy overlay")
	_require(map_hud.mode_legend.text.begins_with("AI objectives:"), "objective overlay must explain its colours")
	map_hud.set_map_mode(MapHUD.MODE_POLITICAL)
	_require(map_render.display_uses_political_colors, "political mode must restore country colours")

	var checksum_before_save := simulation.world_checksum()
	var save_result := simulation.quick_save()
	_require(bool(save_result.get("ok", false)), "AI campaign quick save must succeed")
	var castile_runtime := simulation.world.country_runtime("CAS")
	(castile_runtime["ai"] as Dictionary)["goal"] = "deliberate_test_mutation"
	simulation.world.set_country_runtime("CAS", castile_runtime)
	_require(simulation.world_checksum() != checksum_before_save, "AI state must participate in the deterministic checksum")
	var load_result := simulation.quick_load()
	_require(bool(load_result.get("ok", false)), "AI campaign quick load must succeed")
	_require(simulation.world_checksum() == checksum_before_save, "loading must restore exact AI and campaign state")
	_require(String(simulation.ai_debug_snapshot("CAS").get("goal", "")) != "deliberate_test_mutation", "loaded debugger state must reflect restored AI data")

	var save_path := ProjectSettings.globalize_path(ControllerScript.QUICK_SAVE_PATH)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	print("Phase 6 integration smoke passed. countries=5 day=%d checksum=%s" % [simulation.world.current_day, simulation.world_checksum().left(16)])
	quit(0)
