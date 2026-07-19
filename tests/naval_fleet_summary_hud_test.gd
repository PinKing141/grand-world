extends SceneTree

## FL2.1 closure (fleet-summary panel packet) headless integration test: the
## real NavalHUD fleet panel must show resolved names instead of raw IDs, a
## mixed-family class breakdown, passive repair state with no repair mission
## set, and route/ETA text for a fleet mid-journey - driven through
## hud._refresh_fleet_details() against a real, loaded main.tscn campaign,
## not a mocked panel.

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const NavalHUDScript = preload("res://scripts/ui/naval_hud.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")

const CALAIS := 87
const KENT := 235
const STRAITS_OF_DOVER := 1271


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval fleet summary HUD test failed: %s" % message)
		quit(1)


func _add_fleet(world: CampaignWorldState, fleet_id: String, port_id: int, definitions: Array) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, "ENG", port_id)
	var ship_ids: Array = []
	for index in range(definitions.size()):
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, "ENG", fleet_id, String(definitions[index]), 0)
		ship_ids.append(ship_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _select_fleet(hud: NavalHUDScript, fleet_id: String) -> void:
	for index in hud.fleet_option.item_count:
		if String(hud.fleet_option.get_item_metadata(index)) == fleet_id:
			hud.fleet_option.select(index)
			break
	hud._refresh_fleet_details()


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

	# A named, mixed-family fleet: name, owner, resolved location/home port,
	# and the class breakdown must all be real text, not raw IDs.
	_add_fleet(world, "named_fixture", CALAIS, ["heavy_galleon", "light_caravel", "war_galley", "transport_cog"])
	var named_fleet := world.get_fleet("named_fixture")
	named_fleet["display_name"] = "First Channel Squadron"
	world.fleet_registry["named_fixture"] = named_fleet
	# An unnamed fleet: the panel must fall back to the raw fleet_id.
	_add_fleet(world, "unnamed_fixture", CALAIS, ["war_galley"])
	hud._refresh_all()

	_select_fleet(hud, "named_fixture")
	var text := hud.fleet_details_label.text
	_require(text.contains("Name First Channel Squadron"), "the panel must show the fleet's real display_name: %s" % text)
	_require(text.contains("Owner England"), "the panel must resolve the owning country to a name, not a raw tag: %s" % text)
	_require(text.contains("Location Calais"), "the panel must resolve the fleet's location to a name, not a raw province ID: %s" % text)
	_require(text.contains("Home port Calais"), "the panel must resolve the home port to a name: %s" % text)
	_require(text.contains("Ships 4 (1 heavy, 1 light, 1 galley, 1 transport)"), "the panel must show a real per-family class breakdown: %s" % text)
	_require(text.contains("Crew 100%"), "four freshly built ships must read as fully crewed: %s" % text)
	_require(text.contains("Admiral none"), "a fleet with no admiral assigned must say so explicitly: %s" % text)

	_select_fleet(hud, "unnamed_fixture")
	_require(hud.fleet_details_label.text.contains("Name unnamed_fixture"), "a fleet with no display_name must fall back to its raw fleet_id: %s" % hud.fleet_details_label.text)

	# Admiral name resolution: assign a real character and confirm the panel
	# shows the resolved name, not the raw character_id.
	world.character_registry["ch_admiral_fixture"] = {
		"character_id": "ch_admiral_fixture", "name": "Sir Test Admiral", "alive": true,
		"employer_country": "ENG", "admiral_fleet_id": "unnamed_fixture", "commander_army_id": "",
	}
	var admiral_fleet := world.get_fleet("unnamed_fixture")
	admiral_fleet["admiral_id"] = "ch_admiral_fixture"
	world.fleet_registry["unnamed_fixture"] = admiral_fleet
	hud._refresh_fleet_details()
	_require(hud.fleet_details_label.text.contains("Admiral Sir Test Admiral"), "the panel must resolve the admiral's real name, not the raw character_id: %s" % hud.fleet_details_label.text)

	# Passive repair with no repair mission set - the exact gap the FL2
	# closure audit found: a damaged ship must be visible even though nothing
	# ever set fleet.mission to "repair".
	_require(String(world.get_fleet("unnamed_fixture").get("mission", "")) == "idle", "fixture assumption: the fleet must not be on the repair mission")
	var damaged_ship := world.get_ship("unnamed_fixture_s0")
	damaged_ship["repairing"] = true
	world.ship_registry["unnamed_fixture_s0"] = damaged_ship
	hud._refresh_fleet_details()
	_require(hud.fleet_details_label.text.contains("Repairing 1/1 ships"), "passive repair must be visible without the repair mission set: %s" % hud.fleet_details_label.text)

	# Route and ETA text: order a real two-leg Channel crossing, matching
	# naval_fleet_movement_test.gd's own Calais -> Straits of Dover -> Kent
	# fixture, then verify the panel shows the untraversed route and both the
	# next-waypoint arrival and the final ETA.
	# The real campaign controller already registers FleetMovementSystem as a
	# daily system (simulation_controller.gd) - unlike naval_fleet_movement_
	# test.gd's own from-scratch scheduler, nothing extra needs wiring here.
	var move := MoveFleetCommandScript.new("named_fixture", KENT, "ENG")
	_require(move.validate(world).is_empty(), "the route fixture's move order must be legal: %s" % move.validate(world))
	simulation.scheduler.submit(move)
	simulation.scheduler.process_commands()
	_select_fleet(hud, "named_fixture")
	var moving_fleet := world.get_fleet("named_fixture")
	_require((moving_fleet["remaining_path"] as Array) == [STRAITS_OF_DOVER, KENT], "fixture assumption: the route must cross the Straits of Dover to Kent")
	var expected_final_eta := FleetSystemScript.route_completion_day(world, "named_fixture")
	var route_text := hud.fleet_details_label.text
	_require(route_text.contains("next waypoint arrival %s" % SimulationDateScript.format_day(int(moving_fleet["next_arrival_day"]))), "the panel must show the real next-waypoint arrival day, not the final ETA mislabelled as such: %s" % route_text)
	_require(route_text.contains("final ETA %s" % SimulationDateScript.format_day(expected_final_eta)), "the panel must show a real final ETA summed across the whole remaining route: %s" % route_text)
	_require(route_text.contains("Route") and route_text.contains("Kent"), "the panel must show the untraversed route, naming Kent as the final resolved waypoint: %s" % route_text)

	# Partial traversal: advance one tick so the leg into the Straits of
	# Dover resolves, then confirm the panel's route text updates to match
	# the fleet's new position while the final ETA stays internally
	# consistent with route_completion_day().
	simulation.scheduler.advance_one_day()
	simulation.scheduler.advance_one_day()
	var mid_route_fleet := world.get_fleet("named_fixture")
	_require(int(mid_route_fleet["location_id"]) == STRAITS_OF_DOVER, "fixture assumption: the fleet must be mid-route at the Straits of Dover after two ticks")
	hud._refresh_fleet_details()
	var mid_expected_final_eta := FleetSystemScript.route_completion_day(world, "named_fixture")
	_require(hud.fleet_details_label.text.contains("final ETA %s" % SimulationDateScript.format_day(mid_expected_final_eta)), "mid-route, the panel's final ETA must still match route_completion_day(): %s" % hud.fleet_details_label.text)

	print("Naval fleet summary HUD test passed.")
	quit(0)
