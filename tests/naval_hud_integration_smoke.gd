extends SceneTree

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const NavalHUDScript = preload("res://scripts/ui/naval_hud.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")

const CALAIS := 87


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval HUD integration smoke failed: %s" % message)
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
	var hud := scene.get_node("NavalHUD") as NavalHUDScript
	_require(simulation.initialized, "campaign must initialize")
	_require(hud != null, "the naval HUD must be present in the main scene")

	simulation.choose_player_country("ENG")
	simulation.scheduler.process_commands()
	await process_frame
	_require(hud.naval_toggle_button.visible, "choosing a country must reveal the naval toggle")
	hud.toggle_naval_panel()
	_require(hud.naval_panel.visible, "toggling must open the naval panel")
	_require(hud.fleet_summary_label.text.begins_with("Fleets 0"), "a fresh England must start with no fleets")

	# Give England enough treasury and sailors to actually build, then drive
	# construction the same way a player would: select the port province,
	# pick a ship, press Build.
	var runtime := simulation.world.country_runtime("ENG")
	runtime["treasury"] = 500000
	runtime["sailors"] = 1000
	simulation.world.set_country_runtime("ENG", runtime)
	hud._on_province_selected({"province_id": CALAIS, "province_name": "Calais", "owner_tag": "ENG", "owner_name": "England", "is_playable": true})
	_require(hud.port_construction_label.text.contains(str(CALAIS)), "selecting an owned port must expose naval construction")
	_require(hud.ship_option.item_count > 0, "the ship option list must be populated")
	# Build a transport_cog specifically (not whichever ship sorts first) -
	# the later transport section needs real transport capacity.
	for index in hud.ship_option.item_count:
		if String(hud.ship_option.get_item_metadata(index)) == "transport_cog":
			hud.ship_option.select(index)
			break
	_require(String(hud.ship_option.get_item_metadata(hud.ship_option.selected)) == "transport_cog", "the fixture must select a transport-capable ship")
	hud._construct_selected_ship()
	simulation.scheduler.process_commands()
	_require(simulation.world.naval_construction_registry.size() == 1, "the UI construction action must reach WorldState")
	hud._refresh_all()
	_require(not hud.construction_queue_label.text.begins_with("No active"), "an active construction must be reflected in the panel")

	# Fast-forward past construction to get a real fleet with a real ship,
	# then drive the fleet panel: select it, verify details, order a move.
	var construction: Dictionary = simulation.world.naval_construction_registry.values()[0]
	while simulation.world.current_day < int(construction["completion_day"]) + 1:
		simulation.scheduler.advance_one_day()
	hud._refresh_all()
	_require(hud.fleet_option.item_count == 1, "the completed ship must join exactly one England fleet")
	var fleet_id := hud._selected_fleet_id()
	_require(not fleet_id.is_empty(), "the new fleet must be selectable")
	_require(hud.fleet_details_label.text.contains("Ships 1"), "the fleet panel must show the one completed ship")

	# Transport: embark a real army onto the just-completed fleet through the
	# UI, the same way a player would - select the army, pick a destination
	# province, press Embark.
	simulation.world.army_registry["army_test"] = CampaignWorldStateScript.make_army_record("army_test", "ENG", CALAIS)
	hud._refresh_all()
	_require(hud.army_option.item_count > 0, "an England army co-located with the selected fleet must appear in the embark list")
	# England's real 1444 scenario default army may also be co-located and
	# sort earlier alphabetically - select the fixture army explicitly.
	for index in hud.army_option.item_count:
		if String(hud.army_option.get_item_metadata(index)) == "army_test":
			hud.army_option.select(index)
			break
	_require(String(hud.army_option.get_item_metadata(hud.army_option.selected)) == "army_test", "the fixture must select the intended test army")
	hud._on_province_selected({"province_id": 235, "province_name": "Kent", "owner_tag": "ENG", "owner_name": "England", "is_playable": true})
	_require(not hud.embark_button.disabled, "embarking to a legal destination must be enabled: %s" % hud.embark_button.tooltip_text)
	hud._embark_selected_army()
	simulation.scheduler.process_commands()
	_require(String(simulation.world.get_army("army_test")["status"]) == CampaignWorldStateScript.ARMY_STATUS_EMBARKING, "the UI embark action must reach WorldState")
	hud._refresh_all()
	_require(not hud.transport_label.text.begins_with("No active"), "an active transport must be reflected in the panel")
	_require(hud.cancel_transport_button.visible, "cancelling must be offered while embarking")

	# Save/load round trip: naval state (fleet, ship, treasury/sailor spend,
	# and now an active transport operation) must survive exactly, matching
	# the pattern every other phase's integration smoke already verifies.
	var checksum_before_save := simulation.world_checksum()
	var save_result := simulation.quick_save()
	_require(bool(save_result["ok"]), "naval quick save must succeed")
	simulation.world.fleet_registry.clear()
	var load_result := simulation.quick_load()
	_require(bool(load_result["ok"]), "naval quick load must succeed")
	_require(simulation.world_checksum() == checksum_before_save, "load must restore the exact naval checksum")
	_require(simulation.world.fleet_registry.has(fleet_id), "the fleet must survive save/load")
	_require(simulation.world.transport_operation_registry.size() == 1, "the active transport operation must survive save/load")
	hud._refresh_all()
	_require(hud.fleet_option.item_count == 1, "the naval panel must reflect the reloaded fleet")

	# Cancel the reloaded operation through the UI, closing the loop.
	hud._cancel_selected_transport()
	simulation.scheduler.process_commands()
	_require(String(simulation.world.get_army("army_test")["status"]) == CampaignWorldStateScript.ARMY_STATUS_IDLE, "the UI cancel action must reach WorldState")
	_require(simulation.world.transport_operation_registry.is_empty(), "cancellation must remove the operation")

	var save_path := ProjectSettings.globalize_path(ControllerScript.QUICK_SAVE_PATH)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	print("Naval HUD integration smoke passed. fleet=%s" % fleet_id)
	quit(0)
