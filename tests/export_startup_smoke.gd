extends SceneTree

const STARTUP_FRAME_LIMIT := 600


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("Export startup smoke failed: %s" % message)
	quit(1)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_fail("main scene is missing from the package")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	var simulation = scene.get_node_or_null("SimulationController")
	var labels = scene.get_node_or_null("CountryLabelLayer")
	var army_layer = scene.get_node_or_null("ArmyLayer")
	var waited := 0
	while (simulation == null or not bool(simulation.get("initialized"))) and waited < STARTUP_FRAME_LIMIT:
		await process_frame
		waited += 1
	if simulation == null or not bool(simulation.get("initialized")):
		_fail("authoritative simulation did not initialize within %d frames" % STARTUP_FRAME_LIMIT)
		return
	if labels == null:
		_fail("country label presentation node is missing")
		return
	var shield_atlas := load("res://assets/marker_art/generated/country_shield_atlas.png") as Texture2D
	var icon_atlas := load("res://assets/marker_art/generated/marker_icon_atlas.png") as Texture2D
	if shield_atlas == null or icon_atlas == null or army_layer == null or not bool(army_layer.call("debug_uses_flag_atlas")):
		_fail("historical placeholder marker atlases or runtime binding are missing")
		return
	var marker_manifest := FileAccess.open("res://assets/marker_art/generated/marker_asset_manifest.json", FileAccess.READ)
	if marker_manifest == null:
		_fail("marker asset manifest is missing")
		return
	var history_file := FileAccess.open("res://assets/generated/history_profiles.json", FileAccess.READ)
	if history_file == null:
		_fail("generated runtime history profiles are missing")
		return
	var history_profiles = JSON.parse_string(history_file.get_as_text())
	if not history_profiles is Dictionary or int(history_profiles.get("schema_version", 0)) != 1:
		_fail("generated runtime history profiles are invalid")
		return
	var country_profiles: Dictionary = history_profiles.get("countries", {})
	var province_profiles: Dictionary = history_profiles.get("provinces", {})
	if country_profiles.size() != 1007 or province_profiles.size() != 3925:
		_fail("generated runtime history profile counts are incomplete")
		return
	if String((country_profiles.get("ENG", {}) as Dictionary).get("government", "")) != "monarchy":
		_fail("packaged country history profiles are not readable")
		return
	if String((province_profiles.get("1", {}) as Dictionary).get("capital", "")) != "Stockholm":
		_fail("packaged province history profiles are not readable")
		return
	print("Parsed Provinces:%d" % simulation.world.province_states.size())
	print("Parsed Country Colors:%d" % simulation.country_data.country_id_to_color.size())
	print("Parsed Countries:%d" % simulation.country_data.country_id_to_country_name.size())
	print("Marker Assets:shield=%s icons=%s EnglandSlot=%d" % [shield_atlas != null, icon_atlas != null, int(army_layer.call("debug_country_flag_index", "ENG"))])
	print("Export startup smoke passed. simulation=%s labels=%s" % [simulation.get("initialized"), labels != null])
	quit(0)
