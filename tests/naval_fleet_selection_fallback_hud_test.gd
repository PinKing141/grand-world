extends SceneTree

## FL2.1 closure (last open bullet): "selection survival on fleet
## destruction" was previously unverified and structurally fragile -
## _refresh_fleet_options() only ever called select() when the previously
## selected fleet still existed; if it was destroyed/merged away, nothing
## called select() at all, and which fleet ended up shown was whatever
## Godot's OptionButton happens to default to, not a decision this code
## made. This proves the new explicit fallback: when the selected fleet is
## gone but others remain, selection moves to the alphabetically-first
## remaining fleet (_country_fleets()'s own sorted order), and the fleet
## panel actually refreshes to match - not a stale read of the old selection.

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const NavalHUDScript = preload("res://scripts/ui/naval_hud.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

const CALAIS := 87


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval fleet selection fallback HUD test failed: %s" % message)
		quit(1)


func _add_fleet(world: CampaignWorldState, fleet_id: String) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, "ENG", CALAIS)
	var ship_id := "%s_s0" % fleet_id
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, "ENG", fleet_id, "war_galley", 0)
	var fleet := world.get_fleet(fleet_id)
	fleet["ship_ids"] = [ship_id]
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

	# Three fleets so the fallback's target (the sorted-first remainder) is
	# a real choice, not trivially "the only fleet left."
	_add_fleet(world, "fixture_a")
	_add_fleet(world, "fixture_m")
	_add_fleet(world, "fixture_z")
	hud._refresh_all()

	# Select the LAST-sorted fleet deliberately, so Godot's own implicit
	# "select index 0 by default" behaviour would land on fixture_a even
	# without this packet's fix - the test instead destroys fixture_z itself
	# to prove the fallback is a real decision made after selection changes,
	# not a coincidence of already starting near the top.
	_select_fleet(hud, "fixture_z")
	_require(hud._selected_fleet_id() == "fixture_z", "the fixture must select the intended fleet before destroying it")

	simulation.scuttle_fleet("ENG", "fixture_z")
	simulation.scheduler.process_commands()
	_require(not world.fleet_registry.has("fixture_z"), "fixture assumption: the selected fleet must actually be destroyed")
	hud._refresh_all()

	_require(hud._selected_fleet_id() == "fixture_a", "selection must fall back to the alphabetically-first remaining fleet, not an undocumented engine default: got '%s'" % hud._selected_fleet_id())
	_require(hud.fleet_details_label.text.contains("Name fixture_a"), "the fleet panel must actually refresh to the new selection's real details, not a stale read: %s" % hud.fleet_details_label.text)

	# Destroying the fleet the fallback itself just picked must cascade
	# correctly too - not just work once.
	simulation.scuttle_fleet("ENG", "fixture_a")
	simulation.scheduler.process_commands()
	hud._refresh_all()
	_require(hud._selected_fleet_id() == "fixture_m", "a second cascading destruction must fall back again, to the next sorted-first survivor: got '%s'" % hud._selected_fleet_id())

	# The trivial "zero fleets left" case must still be handled cleanly too.
	simulation.scuttle_fleet("ENG", "fixture_m")
	simulation.scheduler.process_commands()
	hud._refresh_all()
	_require(hud._selected_fleet_id().is_empty(), "with no fleets left, selection must be empty, not stuck on a destroyed ID")
	_require(hud.fleet_details_label.text == "No fleets.", "the panel must show its real empty state: %s" % hud.fleet_details_label.text)

	print("Naval fleet selection fallback HUD test passed.")
	quit(0)
