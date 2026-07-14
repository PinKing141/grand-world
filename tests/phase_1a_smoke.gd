extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 1A smoke test failed: %s" % message)
		quit(1)


func _run() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	_require(packed_scene != null, "main scene must load")
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var selector := scene.get_node("Map/ProvinceSelector") as ProvinceSelector
	var map := scene.get_node("Map")
	var hud = scene.get_node("MapHUD")
	var country_data := scene.get_node("Map/ProvinceSelector/CountryData") as CountryData
	_require(selector != null, "province selector must exist")
	_require(hud != null, "map HUD must exist")
	_require(selector.province_image != null and not selector.province_image.is_empty(), "province image must be ready")
	_require(map.final_material.get_shader_parameter("terrain_class_map") != null, "explicit terrain class texture must be assigned")
	_require(map.final_material.get_shader_parameter("terrain_base_map") != null, "physical terrain base texture must be assigned")
	_require(map.final_material.get_shader_parameter("height_map") != null, "elevation texture must be assigned")

	var original_owner: String = country_data.province_id_to_owner.get(1, "")
	var country_field_mode = map.country_field.render_target_update_mode
	var province_field_mode = map.province_field.render_target_update_mode
	var color_output_mode = map.output.render_target_update_mode
	var info := {
		"province_id": 1,
		"province_name": "Stockholm",
		"owner_tag": "SWE",
		"owner_name": "Sweden",
		"is_playable": true,
		"texture_position": Vector2i.ZERO,
	}

	selector.province_hovered.emit(info, Vector2(120, 90))
	await process_frame
	_require(hud.tooltip.visible, "hover must show the tooltip")
	_require(hud.tooltip_title.text == "Stockholm", "tooltip must show the province name")
	_require(map.final_material.get_shader_parameter("hover_enabled") == true, "hover shader state must be enabled")
	_require(map.country_field.render_target_update_mode == country_field_mode, "hover must not redraw the country distance field")
	_require(map.province_field.render_target_update_mode == province_field_mode, "hover must not redraw the province distance field")
	_require(map.output.render_target_update_mode == color_output_mode, "hover must not redraw the full-resolution political map")

	selector.selected_province_id = 1
	selector.province_selected.emit(info)
	await process_frame
	_require(hud.province_panel.visible, "selection must show the province panel")
	_require(hud.owner_value.text.contains("Sweden"), "panel must show the owner")
	_require(hud.culture_value.text == "Swedish", "panel must load province metadata")
	_require(country_data.province_id_to_owner.get(1, "") == original_owner, "normal selection must not mutate ownership")
	_require(map.final_material.get_shader_parameter("selection_enabled") == true, "selection shader state must be enabled")
	_require(map.final_material.get_shader_parameter("country_selection_enabled") == true, "selecting a playable province must highlight its country")
	_require(hud.terrain_value.text.contains("Temperate"), "panel must show the province biome")
	_require(hud.coastal_value.text == "Coastal", "Stockholm must report as coastal")
	_require(hud.open_country_button.visible, "playable selection must offer the country panel")

	hud._show_country_panel("SWE")
	await process_frame
	_require(hud.country_panel.visible, "country panel must open")
	_require(hud.country_title.text == "Sweden" and not hud.country_title.text.contains("SWE"), "country panel must show only the full country name")
	_require(not hud.country_province_count.text.begins_with("0 "), "country panel must count owned provinces")
	hud._close_country_panel()

	# Map modes are a single uniform switch; no viewport rebuilds allowed.
	hud.set_map_mode(1)
	await process_frame
	_require(map.final_material.get_shader_parameter("map_mode") == 1, "terrain mode must reach the shader")
	hud.set_map_mode(2)
	await process_frame
	_require(map.final_material.get_shader_parameter("map_mode") == 2, "debug mode must reach the shader")
	_require(map.country_field.render_target_update_mode == country_field_mode, "map modes must not redraw the country distance field")
	_require(map.province_field.render_target_update_mode == province_field_mode, "map modes must not redraw the province distance field")
	_require(map.output.render_target_update_mode == color_output_mode, "map modes must not redraw the full-resolution political map")
	hud.set_map_mode(0)

	# Search index and camera focus.
	hud._on_search_text_changed("Stockholm")
	_require(hud.search_results.item_count >= 1, "search must find Stockholm")
	hud._on_search_text_changed("Sweden")
	_require(hud.search_results.item_count >= 1 and hud.search_results.get_item_text(0) == "Sweden", "country search result must show the full name without its tag")
	hud._on_search_text_changed("Sweden")
	_require(hud.search_results.item_count >= 1, "search must find Sweden")
	hud._on_search_text_changed("")
	var camera_controller = scene.get_node("CameraController")
	var camera_before: Vector3 = camera_controller.global_position
	camera_controller.focus_world_position(Vector3(5.0, 0.0, 3.0))
	_require(not camera_controller.global_position.is_equal_approx(camera_before), "camera focus must move the camera")
	camera_controller.reset_camera()

	selector.clear_selection()
	selector.province_hover_cleared.emit()
	await process_frame
	_require(not hud.province_panel.visible, "clearing selection must hide the panel")
	_require(not hud.tooltip.visible, "clearing hover must hide the tooltip")
	_require(map.final_material.get_shader_parameter("selection_enabled") == false, "selection shader state must clear")
	_require(map.final_material.get_shader_parameter("country_selection_enabled") == false, "country highlight must clear with the selection")

	print("Phase 1A smoke test passed.")
	scene.queue_free()
	quit(0)
