extends SceneTree

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const CountryDepthHUDScript = preload("res://scripts/ui/country_depth_hud.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 8 integration smoke failed: %s" % message)
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
	var hud := scene.get_node("CountryDepthHUD") as CountryDepthHUDScript
	var map_render := scene.get_node("Map")
	var map_hud := scene.get_node("MapHUD") as MapHUD
	_require(simulation.initialized, "campaign must initialize")
	_require(simulation.country_depth_definitions != null and simulation.country_depth_definitions.is_valid(), "country-depth content must be packaged and valid")
	_require(int(simulation.world.global_flags.get("country_depth_version", 0)) == 1, "main campaign must initialize Phase 8 state")
	_require(hud != null and hud.open_button != null, "country-depth HUD must instantiate")

	simulation.choose_player_country("CAS")
	simulation.scheduler.process_commands()
	await process_frame
	_require(hud.open_button.visible, "choosing a country must expose Country & State")
	hud.panel.show()
	var runtime := simulation.world.country_runtime("CAS")
	runtime["treasury"] = 500000
	runtime["technology_points"] = {"administrative": 5000, "diplomatic": 5000, "military": 5000}
	simulation.world.set_country_runtime("CAS", runtime)
	hud._refresh_all()
	_require(hud.overview_label.text.contains("Stability"), "government tab must explain stability and authority")
	_require(hud.admin_tech_button.text.contains("next"), "technology controls must show level, points, and next cost")
	_require(hud.reform_option.item_count > 0 and hud.idea_option.item_count > 0, "government reforms and national directions need player paths")
	hud._advance_technology("administrative")
	simulation.scheduler.process_commands()
	_require(int(simulation.world.country_runtime("CAS").get("technology", {}).get("administrative", 0)) == 1, "technology HUD action must reach authoritative state")

	var foreign_info := {"province_id": 214, "province_name": "Aragon", "owner_tag": "ARA", "owner_name": "Aragon", "is_playable": true}
	hud._on_province_selected(foreign_info)
	_require(hud.province_label.text.contains("Culture") and hud.province_label.text.contains("Unrest sources"), "society tab must explain selected province identity and unrest")
	_require(not hud.fabricate_claim_button.disabled, "eligible foreign provinces must expose claim fabrication")
	hud._fabricate_claim()
	simulation.scheduler.process_commands()
	_require(CountryDepthSystemScript.has_valid_claim_or_core(simulation.world, "CAS", 214), "claim button must create an authoritative timed claim")

	hud._set_map_mode("culture", "Culture integration test")
	await process_frame
	_require(not map_render.display_uses_political_colors, "culture map mode must apply a strategy overlay")
	_require(map_hud.mode_legend.text == "Culture integration test", "country-depth map modes must display their explanation")
	map_hud.set_map_mode(0)
	await process_frame
	_require(map_render.display_uses_political_colors, "political map mode must restore country colours")

	simulation.debug_jump_to_next_month()
	await process_frame
	hud._refresh_all()
	var pending := CountryDepthSystemScript.pending_event_for_country(simulation.world, "CAS")
	_require(not pending.is_empty() and hud.event_options.get_child_count() > 0, "player events must appear with clickable response options")
	_require(hud.decisions_box.get_child_count() == simulation.country_depth_decisions().size(), "all data-driven national decisions must appear")
	_require(hud.target_country_option.item_count > 0, "subject tab must expose diplomatic subject targets")

	var checksum_before_save := simulation.world_checksum()
	var save_result := simulation.quick_save()
	_require(bool(save_result.get("ok", false)), "Phase 8 quick save must succeed")
	var mutated := simulation.world.country_runtime("CAS")
	mutated["stability"] = -3
	simulation.world.set_country_runtime("CAS", mutated)
	var load_result := simulation.quick_load()
	_require(bool(load_result.get("ok", false)), "Phase 8 quick load must succeed")
	_require(simulation.world_checksum() == checksum_before_save, "quick load must restore Phase 8 state exactly")

	print("Phase 8 integration smoke passed. event=%s checksum=%s" % [String(pending.get("definition_id", "")), simulation.world_checksum().left(16)])
	quit(0)
