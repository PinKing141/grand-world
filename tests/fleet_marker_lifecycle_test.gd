extends SceneTree

## FL1.3 lifecycle regression: selected fleet-route presentation must always
## reconcile from authoritative state after cancellation, peace cleanup, and
## a real quick-save/quick-load round trip. Merge/split selection is exercised
## through the real HUD in naval_fleet_organisation_hud_test.gd.

const FleetMarkerLayerScript = preload("res://scripts/ui/fleet_marker_layer.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const CancelFleetMovementCommandScript = preload("res://scripts/simulation/commands/cancel_fleet_movement_command.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")

const CALAIS := 87
const STRAITS_OF_DOVER := 1271

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("Fleet marker lifecycle test failed: %s" % message)
	return false


func _add_fleet(world: CampaignWorldState, fleet_id: String) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, "ENG", CALAIS)
	var ship_id := "%s_ship" % fleet_id
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, "ENG", fleet_id, "war_galley", world.current_day)
	var fleet := world.get_fleet(fleet_id)
	fleet["ship_ids"] = [ship_id]
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _set_route(world: CampaignWorldState, fleet_id: String, status := CampaignWorldStateScript.FLEET_LOCATION_MOVING) -> void:
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = CALAIS
	fleet["location_status"] = status
	fleet["destination_id"] = STRAITS_OF_DOVER
	fleet["remaining_path"] = [STRAITS_OF_DOVER]
	fleet["path_index"] = 0
	fleet["movement_start_day"] = world.current_day
	fleet["next_arrival_day"] = world.current_day + 1
	world.fleet_registry[fleet_id] = fleet


func _clear_route(world: CampaignWorldState, fleet_id: String) -> void:
	var fleet := world.get_fleet(fleet_id)
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	fleet["destination_id"] = -1
	fleet["remaining_path"] = []
	fleet["path_index"] = 0
	fleet["movement_start_day"] = -1
	fleet["next_arrival_day"] = -1
	world.fleet_registry[fleet_id] = fleet


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if not _require(packed != null, "main scene must load"):
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var simulation = scene.get_node("SimulationController")
	var markers := scene.get_node("FleetMarkerLayer") as FleetMarkerLayerScript
	var hud := scene.get_node("NavalHUD") as NavalHUD
	if not _require(simulation.initialized and markers != null and hud != null, "simulation, HUD, and fleet markers must initialize"):
		quit(1)
		return

	simulation.choose_player_country("ENG")
	simulation.scheduler.process_commands()
	var world: CampaignWorldState = simulation.world
	world.fleet_registry.clear()
	world.ship_registry.clear()
	world.naval_battle_registry.clear()
	world.transport_operation_registry.clear()
	_add_fleet(world, "route_fixture")
	_set_route(world, "route_fixture")
	hud._refresh_all()
	hud.select_fleet("route_fixture")
	markers.debug_force_refresh()
	_require(markers.selected_fleet() == "route_fixture", "the fixture fleet must be selected on the map")
	_require(markers.debug_route_style() == "moving" and markers.debug_destination_visible(), "authoritative moving state must draw a route before lifecycle transitions")

	# Cancellation: use the real command/event path, not a direct UI clear.
	var cancel := CancelFleetMovementCommandScript.new("route_fixture", "ENG")
	_require(cancel.validate(world).is_empty(), "the fixture route must be legally cancellable: %s" % cancel.validate(world))
	cancel.apply(world, simulation.event_bus)
	_require(markers._route_dirty, "fleet_movement_cancelled must dirty selected route presentation immediately")
	markers.debug_force_refresh()
	_require(markers.debug_route_style() == "none" and not markers.debug_destination_visible(), "movement cancellation must remove route geometry and its destination marker")

	# Real save/load reconciliation in both directions: a saved route must be
	# restored after an in-memory clear, and a saved no-route state must erase
	# stale geometry introduced after the save.
	_set_route(world, "route_fixture")
	markers.debug_force_refresh()
	var saved_route: Dictionary = simulation.quick_save()
	_require(bool(saved_route.get("ok", false)), "quick-save with a selected route must succeed: %s" % saved_route.get("message", ""))
	_clear_route(world, "route_fixture")
	markers.debug_force_refresh()
	_require(markers.debug_route_style() == "none", "the pre-load mutation must genuinely clear the route")
	var loaded_route: Dictionary = simulation.quick_load()
	_require(bool(loaded_route.get("ok", false)), "quick-load of a selected route must succeed: %s" % loaded_route.get("message", ""))
	markers.debug_force_refresh()
	_require(markers.selected_fleet() == "route_fixture" and markers.debug_route_style() == "moving", "world_reloaded must rebuild the selected route from restored authoritative state")

	_clear_route(world, "route_fixture")
	var saved_clear: Dictionary = simulation.quick_save()
	_require(bool(saved_clear.get("ok", false)), "quick-save with no route must succeed: %s" % saved_clear.get("message", ""))
	_set_route(world, "route_fixture")
	markers.debug_force_refresh()
	_require(markers.debug_route_style() == "moving", "the stale-route mutation must genuinely draw geometry before reload")
	var loaded_clear: Dictionary = simulation.quick_load()
	_require(bool(loaded_clear.get("ok", false)), "quick-load of the no-route state must succeed: %s" % loaded_clear.get("message", ""))
	markers.debug_force_refresh()
	_require(markers.debug_route_style() == "none" and not markers.debug_destination_visible(), "world_reloaded must remove route geometry absent from the restored state")

	# Peace cleanup: an active battle participant can have retreat-route data
	# while still referenced by the battle. The authoritative peace cleanup
	# clears that route and emits naval_battle_ended, which must invalidate the
	# map in the same transition.
	_set_route(world, "route_fixture", CampaignWorldStateScript.FLEET_LOCATION_RETREATING)
	var fleet := world.get_fleet("route_fixture")
	fleet["battle_id"] = "peace_battle"
	world.fleet_registry["route_fixture"] = fleet
	var battle := CampaignWorldStateScript.make_naval_battle_record("peace_battle", "peace_war", STRAITS_OF_DOVER, world.current_day)
	battle["attacker_fleets"] = ["route_fixture"]
	battle["defender_fleets"] = []
	world.naval_battle_registry["peace_battle"] = battle
	markers.debug_force_refresh()
	_require(markers.debug_route_style() == "retreat", "the peace fixture must expose real retreat geometry before cleanup")
	NavalCombatSystemScript.end_war_battles(world, simulation.event_bus, "peace_war", "peace")
	_require(markers._route_dirty, "peace-driven naval_battle_ended must dirty selected route presentation")
	markers.debug_force_refresh()
	_require((world.get_fleet("route_fixture").get("remaining_path", []) as Array).is_empty(), "peace cleanup must clear the authoritative retreat path")
	_require(markers.debug_route_style() == "none" and not markers.debug_destination_visible(), "peace cleanup must remove retreat geometry without waiting for an unrelated refresh")

	if _failed:
		quit(1)
		return
	print("Fleet marker lifecycle test passed. cancellation=1 save_load_restore=1 save_load_clear=1 peace_cleanup=1")
	quit(0)
