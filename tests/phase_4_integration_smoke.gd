extends SceneTree

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const EconomyHUDScript = preload("res://scripts/ui/economy_hud.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 4 integration smoke failed: %s" % message)
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
	var hud := scene.get_node("EconomyHUD") as EconomyHUDScript
	var map_render := scene.get_node("Map")
	var map_hud := scene.get_node("MapHUD") as MapHUD
	_require(simulation.initialized, "campaign must initialize with economy definitions")
	_require(simulation.world.province_states[1].has("economy"), "province runtime must contain economy state")

	simulation.choose_player_country("SWE")
	simulation.scheduler.process_commands()
	await process_frame
	_require(hud.resource_bar.visible, "choosing a country must show treasury and manpower")
	_require(hud.treasury_label.text.contains("Treasury"), "resource bar must show treasury")
	_require(hud.manpower_label.text.contains("Manpower"), "resource bar must show manpower")
	hud.economy_panel.show()
	hud._refresh_all()
	_require(hud.economy_title.text == "Sweden economy" and not hud.economy_title.text.contains("SWE"), "economy window must show only the full country name")

	var info := {
		"province_id": 1, "province_name": "Stockholm", "owner_tag": "SWE",
		"owner_name": "Sweden", "is_playable": true,
	}
	hud._on_province_selected(info)
	_require(hud.province_economy_panel.visible, "owned province selection must expose economic actions")
	var runtime := simulation.world.country_runtime("SWE")
	runtime["treasury"] = 500000
	simulation.world.set_country_runtime("SWE", runtime)
	hud._construct("tax_office")
	simulation.scheduler.process_commands()
	_require(simulation.world.construction_registry.size() == 1, "UI construction action must reach WorldState")

	# Heatmaps use the authoritative values and standard map buttons restore
	# political colours without rebuilding ownership state.
	hud._set_economy_map_mode("tax")
	await process_frame
	_require(not map_render.display_uses_political_colors, "tax mode must replace the presentation LUT")
	_require(map_hud.mode_legend.text.begins_with("Tax:"), "economic mode must explain its legend")
	map_hud.set_map_mode(0)
	await process_frame
	_require(map_render.display_uses_political_colors, "political mode must restore country colours")

	var checksum_before_save := simulation.world_checksum()
	var save_result := simulation.quick_save()
	_require(bool(save_result["ok"]), "Phase 4 quick save must succeed")
	var construction_id := String(simulation.world.construction_registry.keys()[0])
	simulation.cancel_construction("SWE", construction_id)
	simulation.scheduler.process_commands()
	_require(simulation.world.construction_registry.is_empty(), "post-save cancellation must apply")
	var load_result := simulation.quick_load()
	_require(bool(load_result["ok"]), "Phase 4 quick load must succeed")
	_require(simulation.world_checksum() == checksum_before_save, "load must restore the exact economic checksum")
	_require(simulation.world.construction_registry.size() == 1, "active construction must survive save/load")

	var save_path := ProjectSettings.globalize_path(ControllerScript.QUICK_SAVE_PATH)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	print("Phase 4 integration smoke passed.")
	quit(0)
