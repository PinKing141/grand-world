extends SceneTree

## FL2.3 headless integration test: home-port selection and a targeted
## return-to-port mission, both driven through the real NavalHUD controls and
## the shared "select a province on the map, then act" pattern Move/Embark
## already use.

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const NavalHUDScript = preload("res://scripts/ui/naval_hud.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMissionSystemScript = preload("res://scripts/simulation/fleet_mission_system.gd")

const CALAIS := 87
const KENT := 235


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval fleet home port HUD test failed: %s" % message)
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
	_require(simulation.initialized and hud != null, "naval HUD dependencies must initialize")

	simulation.choose_player_country("ENG")
	simulation.scheduler.process_commands()
	var world: CampaignWorldState = simulation.world
	world.fleet_registry.clear()
	world.ship_registry.clear()
	world.fleet_registry["home_fixture"] = CampaignWorldStateScript.make_fleet_record("home_fixture", "ENG", CALAIS)
	var fleet := world.get_fleet("home_fixture")
	var ship_id := "home_fixture_s0"
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, "ENG", "home_fixture", "war_galley", 0)
	fleet["ship_ids"] = [ship_id]
	world.fleet_registry["home_fixture"] = fleet
	FleetSystemScript.recompute_aggregate(world, "home_fixture")
	hud._refresh_all()
	for index in hud.fleet_option.item_count:
		if String(hud.fleet_option.get_item_metadata(index)) == "home_fixture":
			hud.fleet_option.select(index)
			break
	hud._refresh_fleet_details()
	_require(hud._selected_fleet_id() == "home_fixture", "the fixture must select the intended fleet")
	_require(hud.fleet_details_label.text.contains("Home port Calais"), "the fleet panel must display the current home port, resolved to a name rather than a raw province ID: %s" % hud.fleet_details_label.text)

	# No province selected yet: the button must be disabled, not silently
	# offer to submit an invalid command.
	_require(hud.set_home_port_button.disabled, "the home-port button must be disabled with no province selected")

	# Select KENT (a real ENG-owned port in the loaded 1444 scenario) and set
	# it as the new home port through the button.
	hud._on_province_selected({"province_id": KENT, "province_name": "Kent", "owner_tag": "ENG", "owner_name": "England", "is_playable": true})
	_require(not hud.set_home_port_button.disabled, "setting home port to a legally basable owned province must be enabled: %s" % hud.set_home_port_button.tooltip_text)
	hud._set_selected_fleet_home_port()
	simulation.scheduler.process_commands()
	_require(int(world.get_fleet("home_fixture")["home_port_id"]) == KENT, "the UI home-port action must reach WorldState")
	hud._refresh_all()
	hud._refresh_fleet_details()
	_require(hud.fleet_details_label.text.contains("Home port Kent"), "the fleet panel must reflect the new home port, resolved to a name: %s" % hud.fleet_details_label.text)

	# Targeted return-to-port: the fleet is away from home (at CALAIS, whose
	# real sea exit stands in for "not currently docked at a legal port" is
	# unnecessary here - CALAIS is itself still a legal ENG dock, so instead
	# prove the *target selection* mechanism directly: setting the mission
	# with KENT selected must persist KENT as the mission's own target,
	# distinct from "no target" (auto-nearest).
	hud._on_province_selected({"province_id": KENT, "province_name": "Kent", "owner_tag": "ENG", "owner_name": "England", "is_playable": true})
	for index in hud.mission_option.item_count:
		if String(hud.mission_option.get_item_metadata(index)) == "return_to_port":
			hud.mission_option.select(index)
			break
	hud._refresh_mission_validation()
	_require(hud.set_mission_button.tooltip_text.contains("Kent") or hud.set_mission_button.tooltip_text.contains(str(KENT)), "the mission button tooltip must name the selected target: %s" % hud.set_mission_button.tooltip_text)
	hud._set_selected_fleet_mission()
	simulation.scheduler.process_commands()
	var fleet_after := world.get_fleet("home_fixture")
	_require(String(fleet_after["mission"]) == "return_to_port", "the UI mission action must reach WorldState")
	var mission_targets: Array = fleet_after.get("mission_target_ids", [])
	_require(mission_targets.size() == 1 and int(mission_targets[0]) == KENT, "the selected province must persist as the mission's own target, not be silently dropped")
	hud._refresh_all()
	_require(hud.fleet_details_label.text.contains("target Kent") or hud.fleet_details_label.text.contains("target province %d" % KENT), "the fleet panel must show the mission's real target: %s" % hud.fleet_details_label.text)

	# FleetMissionSystem must actually complete the mission immediately once
	# the fleet is already docked exactly at its chosen target (KENT).
	fleet_after["location_id"] = KENT
	fleet_after["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	world.fleet_registry["home_fixture"] = fleet_after
	var events := simulation.event_bus
	FleetMissionSystemScript.process_day(world, events)
	_require(String(world.get_fleet("home_fixture")["mission"]) == "idle", "reaching the chosen target port must complete the return_to_port mission")

	print("Naval fleet home port HUD test passed.")
	quit(0)
