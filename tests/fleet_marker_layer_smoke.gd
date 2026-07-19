extends SceneTree

## FL1.1/FL1.2/FL1.5 headless presentation test for FleetMarkerLayer: marker
## view models, clustering, click-to-cycle selection into NavalHUD, owner
## colour distinction, and zoom-based culling - the same shape
## conflict_marker_layer_smoke.gd already proves for battle/siege markers.

const FleetMarkerLayerScript = preload("res://scripts/ui/fleet_marker_layer.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")

const CALAIS := 87
const STRAITS_OF_DOVER := 1271


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Fleet marker layer smoke failed: %s" % message)
		quit(1)


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, location_id: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, location_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	world.fleet_registry[fleet_id] = fleet


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var simulation = scene.get_node("SimulationController")
	var fleet_markers := scene.get_node("FleetMarkerLayer") as FleetMarkerLayerScript
	var naval_hud := scene.get_node("NavalHUD") as NavalHUD
	var camera_controller := scene.get_node("CameraController") as StrategyCameraController
	_require(simulation.initialized and fleet_markers != null, "fleet presentation dependencies must initialize")

	simulation.choose_player_country("ENG")
	simulation.scheduler.process_commands()
	var world: CampaignWorldState = simulation.world
	world.fleet_registry.clear()
	_add_fleet(world, "fixture_eng_a", "ENG", CALAIS)
	_add_fleet(world, "fixture_fra_a", "FRA", CALAIS)
	_add_fleet(world, "fixture_eng_b", "ENG", STRAITS_OF_DOVER)
	fleet_markers.debug_force_refresh()

	_require(fleet_markers.debug_fleet_count() == 3, "every authoritative fleet must produce a logical marker")
	_require(fleet_markers.debug_cluster_count() == 2, "two co-located fleets at the same port must collapse into one cluster, distinct from the lone sea-zone fleet")
	_require(fleet_markers.debug_markers_visible(), "fleet markers must be visible at normal zoom")

	var selected: Array[Dictionary] = []
	fleet_markers.fleet_marker_selected.connect(func(marker: Dictionary) -> void: selected.append(marker))
	var port_cluster_position := Vector2.ZERO
	for index in fleet_markers.debug_cluster_count():
		# Deterministic: find the two-member cluster by clicking each anchor
		# and checking cluster_size, since cluster order is not itself part
		# of the debug contract.
		var candidate := fleet_markers.debug_cluster_screen_position(index)
		var probe := fleet_markers.marker_at_screen_position(candidate)
		if int(probe.get("cluster_size", 0)) == 2:
			port_cluster_position = candidate
			break
	_require(port_cluster_position != Vector2.ZERO, "the two-fleet port cluster must be locatable on screen")

	fleet_markers._on_map_click_requested(port_cluster_position)
	fleet_markers._on_map_click_requested(port_cluster_position)
	_require(selected.size() == 2, "clicking a visible fleet marker must emit an inspectable selection")
	_require(int(selected[0].get("cluster_size", 0)) == 2, "a clicked cluster must report its complete logical member count")
	_require(String(selected[0].get("fleet_id", "")) != String(selected[1].get("fleet_id", "")), "repeated clicks must cycle deterministically through co-located fleets")
	_require(naval_hud.naval_panel.visible, "clicking a fleet marker must open the naval panel")
	_require(String(naval_hud._selected_fleet_id()) in ["fixture_eng_a", "fixture_fra_a"], "clicking an ENG or FRA fleet must select it in the fleet panel (ownership scoping applies within the panel itself)")

	var eng_colour: Color = simulation.country_registry.country_colour("ENG")
	var fra_colour: Color = simulation.country_registry.country_colour("FRA")
	_require(eng_colour != fra_colour, "fixture must use two genuinely distinct national colours to prove owner-colour tinting")

	# FL1.3 route/mission-target feedback: styled by what the selected fleet
	# is actually doing, derived straight from remaining_path/path_index
	# (the same field retreat reuses - NavalCombatSystem._begin_retreat()).
	_add_fleet(world, "fixture_moving", "ENG", CALAIS)
	var moving_fleet := world.get_fleet("fixture_moving")
	moving_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_MOVING
	moving_fleet["remaining_path"] = [STRAITS_OF_DOVER]
	moving_fleet["path_index"] = 0
	world.fleet_registry["fixture_moving"] = moving_fleet
	fleet_markers.set_selected_fleet("fixture_moving")
	fleet_markers.debug_force_refresh()
	_require(fleet_markers.debug_route_style() == "moving", "a moving fleet's selected route must use the plain moving style")
	_require(fleet_markers.debug_route_surface_count() > 0, "a moving fleet's route must produce real line geometry")
	_require(fleet_markers.debug_destination_visible(), "a moving fleet must show a destination marker")

	var retreating_fleet := world.get_fleet("fixture_moving")
	retreating_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_RETREATING
	world.fleet_registry["fixture_moving"] = retreating_fleet
	fleet_markers.debug_force_refresh()
	_require(fleet_markers.debug_route_style() == "retreat", "a retreating fleet's selected route must use the retreat style")

	var transport_fleet := world.get_fleet("fixture_moving")
	transport_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_MOVING
	transport_fleet["transport_operation_ids"] = ["fixture_operation"]
	world.fleet_registry["fixture_moving"] = transport_fleet
	fleet_markers.debug_force_refresh()
	_require(fleet_markers.debug_route_style() == "transport", "a fleet carrying an active transport reservation must use the transport route style")

	var blockading_fleet := world.get_fleet("fixture_moving")
	blockading_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	blockading_fleet["remaining_path"] = []
	blockading_fleet["transport_operation_ids"] = []
	blockading_fleet["mission"] = "blockade"
	blockading_fleet["mission_target_ids"] = [STRAITS_OF_DOVER]
	world.fleet_registry["fixture_moving"] = blockading_fleet
	fleet_markers.debug_force_refresh()
	_require(fleet_markers.debug_route_style() == "none", "an on-station blockading fleet has no route to draw")
	_require(fleet_markers.debug_mission_target_visible(), "a blockade mission with a real target must show a mission-target marker even without a route")
	_require(not fleet_markers.debug_destination_visible(), "an on-station fleet must not show a stale destination marker")

	# Destroying the currently-selected fleet without an explicit deselect
	# (e.g. sunk in battle) must not leave stale route/target geometry
	# pointing at a fleet that no longer exists.
	world.fleet_registry.erase("fixture_moving")
	fleet_markers.debug_force_refresh()
	_require(fleet_markers.debug_route_style() == "none" and not fleet_markers.debug_mission_target_visible(), "destroying the selected fleet must clear its route and mission-target geometry")

	fleet_markers.set_selected_fleet("")

	# FL1.5 closure: NavalHUD-driven reverse sync. A HUD-side selection
	# change (the dropdown's own item_selected callback, which calls
	# _refresh_fleet_details() directly with no map interaction at all) must
	# push the new selection back out to the map, not just the other
	# direction (map click -> HUD, already proven above).
	_add_fleet(world, "fixture_reverse_sync", "ENG", STRAITS_OF_DOVER)
	naval_hud._refresh_all()
	var reverse_sync_index := -1
	for index in naval_hud.fleet_option.item_count:
		if String(naval_hud.fleet_option.get_item_metadata(index)) == "fixture_reverse_sync":
			reverse_sync_index = index
			break
	_require(reverse_sync_index >= 0, "a newly created fleet must appear in the HUD's own fleet dropdown once refreshed")
	naval_hud.fleet_option.select(reverse_sync_index)
	naval_hud._refresh_fleet_details()
	_require(fleet_markers.selected_fleet() == "fixture_reverse_sync", "a HUD dropdown selection change must push the new fleet ID back to the map's own selection, not just the reverse")

	# The same reverse sync must also hold for the HUD's own fallback
	# reselection (naval_hud._refresh_fleet_options()'s "previous fleet no
	# longer exists, fall back to the sorted-first fleet" rule) - not only
	# the direct dropdown-pick path just proven above.
	world.fleet_registry.erase("fixture_reverse_sync")
	naval_hud._refresh_all()
	_require(fleet_markers.selected_fleet() != "fixture_reverse_sync", "the map must not keep pointing at a fleet the HUD has already fallen back away from")
	_require(fleet_markers.selected_fleet() == naval_hud._selected_fleet_id(), "map and HUD selection must remain the exact same fleet ID after a HUD-driven fallback reselection")

	# FL1.5 closure: fleet_scuttled (emitted by this panel's own Scuttle
	# button) previously had no listener anywhere in the UI layer, so a
	# scuttled fleet's marker stayed on the map and its stale details stayed
	# shown in the panel until an unrelated event happened to refresh either.
	_add_fleet(world, "fixture_scuttled", "ENG", CALAIS)
	naval_hud._refresh_all()
	naval_hud.select_fleet("fixture_scuttled")
	_require(naval_hud._selected_fleet_id() == "fixture_scuttled", "the fixture fleet must actually be the HUD's selected fleet before scuttling it, or the listener check below would prove nothing")
	fleet_markers.debug_force_refresh()
	var pre_scuttle_count := fleet_markers.debug_fleet_count()
	world.fleet_registry.erase("fixture_scuttled")
	simulation.event_bus.fleet_scuttled.emit("fixture_scuttled", "ENG", 1)
	_require(fleet_markers._dirty, "fleet_scuttled must mark the map's fleet marker batch dirty")
	fleet_markers.debug_force_refresh()
	_require(fleet_markers.debug_fleet_count() == pre_scuttle_count - 1, "a scuttled fleet's marker must disappear once fleet_scuttled triggers a rebuild")
	_require(naval_hud._selected_fleet_id() != "fixture_scuttled", "fleet_scuttled must also refresh the HUD panel so it stops offering the now-nonexistent fleet")

	fleet_markers.set_selected_fleet("")

	# Zoom-out culling, mirroring conflict_marker_layer_smoke.gd's own check.
	camera_controller.global_position.y += 13.0 - camera_controller.camera.global_position.y
	camera_controller._sync_projection_to_height(true)
	fleet_markers.debug_force_refresh()
	_require(not fleet_markers.debug_markers_visible(), "fleet markers must cull at world zoom")
	camera_controller.reset_camera()

	# Destruction/removal cleanup, mirroring the naval-battle marker teardown
	# check in conflict_marker_layer_smoke.gd.
	world.fleet_registry.clear()
	fleet_markers.debug_force_refresh()
	_require(fleet_markers.debug_fleet_count() == 0 and fleet_markers.debug_cluster_count() == 0, "removing every fleet must clear the marker batch")

	print("Fleet marker layer smoke passed. logical_fleets=3 clusters=2 clickable_cluster=2 route_styles=moving,retreat,transport,none mission_target=1")
	quit(0)
