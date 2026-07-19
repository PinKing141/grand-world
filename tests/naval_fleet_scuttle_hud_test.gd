extends SceneTree

## FL2.5 headless integration test: the armed-confirmation Scuttle control,
## driven through the real NavalHUD button handlers rather than by calling
## ScuttleFleetCommand directly, per
## docs/roadmap/naval/g1_finish_line/evidence/FL2_5_SCUTTLE_COMMAND.md rule 8.

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const NavalHUDScript = preload("res://scripts/ui/naval_hud.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

const CALAIS := 87
const KENT := 235


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval fleet scuttle HUD test failed: %s" % message)
		quit(1)


func _add_fleet(world: CampaignWorldState, fleet_id: String, port_id: int, ship_definitions: Array) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, "ENG", port_id)
	var ship_ids: Array = []
	for index in range(ship_definitions.size()):
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, "ENG", fleet_id, String(ship_definitions[index]), 0)
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
	_add_fleet(world, "scuttle_fixture", CALAIS, ["war_galley", "light_caravel"])
	_add_fleet(world, "other_fixture", CALAIS, ["war_galley"])
	hud._refresh_all()

	_select_fleet(hud, "scuttle_fixture")
	_require(hud._selected_fleet_id() == "scuttle_fixture", "the fixture must select the intended fleet")
	_require(not hud.scuttle_fleet_button.disabled, "a docked, idle, unencumbered fleet's Scuttle button must be enabled: %s" % hud.scuttle_fleet_button.tooltip_text)
	_require(hud.scuttle_fleet_button.text == "Scuttle", "the Scuttle button must not start armed")

	# First press arms the button - it must rename to name the fleet's ship
	# count and NOT submit a command yet.
	hud._scuttle_selected_fleet()
	_require(world.fleet_registry.has("scuttle_fixture"), "arming Scuttle on the first press must not remove the fleet")
	_require(hud.scuttle_fleet_button.text.contains("2") and hud.scuttle_fleet_button.text.contains("Confirm"), "the armed button must name the ship count and ask for confirmation: %s" % hud.scuttle_fleet_button.text)

	# Switching the selected fleet must disarm the confirmation - it must not
	# leak onto whichever fleet happens to be selected on the next press.
	_select_fleet(hud, "other_fixture")
	_require(hud.scuttle_fleet_button.text == "Scuttle", "changing fleet selection must disarm the confirmation state")
	_select_fleet(hud, "scuttle_fixture")
	_require(hud.scuttle_fleet_button.text == "Scuttle", "re-selecting the fleet after switching away must require re-arming, not resume the old armed state")

	# Arm again, then confirm: the second press while still armed for the
	# same fleet must actually submit ScuttleFleetCommand.
	hud._scuttle_selected_fleet()
	_require(hud.scuttle_fleet_button.text.contains("Confirm"), "the button must be armed again before confirming")
	hud._scuttle_selected_fleet()
	simulation.scheduler.process_commands()
	_require(not world.fleet_registry.has("scuttle_fixture"), "confirming while armed must submit ScuttleFleetCommand and remove the fleet")
	_require(not world.ship_registry.has("scuttle_fixture_s0") and not world.ship_registry.has("scuttle_fixture_s1"), "confirming must remove the scuttled fleet's ships")
	_require(world.fleet_registry.has("other_fixture"), "the untouched fleet must survive")

	hud._refresh_all()
	_require(hud._selected_fleet_id() == "other_fixture", "selection must fall back to a surviving fleet once the scuttled one is gone")
	_require(hud.scuttle_fleet_button.text == "Scuttle" and not hud.scuttle_fleet_button.disabled, "the panel must return to a clean, unarmed state for the surviving fleet")

	print("Naval fleet scuttle HUD test passed.")
	quit(0)
