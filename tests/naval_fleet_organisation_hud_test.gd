extends SceneTree

## FL2.2 headless integration test: split, transfer and merge driven through
## the real NavalHUD controls (ship multi-select, target-fleet picker, and
## the three action buttons), proving the UI reaches SplitFleetCommand/
## TransferShipsCommand/MergeFleetsCommand exactly as a player would trigger
## them - not just that the underlying commands validate correctly (already
## proven by naval_fleet_organisation_test.gd).

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const NavalHUDScript = preload("res://scripts/ui/naval_hud.gd")
const FleetMarkerLayerScript = preload("res://scripts/ui/fleet_marker_layer.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

const CALAIS := 87


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval fleet organisation HUD test failed: %s" % message)
		quit(1)


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, port_id: int, ship_count: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, port_id)
	var fleet := world.get_fleet(fleet_id)
	var ship_ids: Array = []
	for index in ship_count:
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "war_galley", 0)
		ship_ids.append(ship_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


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
	var fleet_markers := scene.get_node("FleetMarkerLayer") as FleetMarkerLayerScript
	_require(simulation.initialized and hud != null and fleet_markers != null, "naval HUD and map-marker dependencies must initialize")

	simulation.choose_player_country("ENG")
	simulation.scheduler.process_commands()
	var world: CampaignWorldState = simulation.world
	world.fleet_registry.clear()
	world.ship_registry.clear()
	_add_fleet(world, "org_fixture_a", "ENG", CALAIS, 3)
	_add_fleet(world, "org_fixture_b", "ENG", CALAIS, 1)
	hud._refresh_all()

	# Select the 3-ship fleet; the 1-ship fleet must be the only eligible
	# split/transfer/merge target since both are docked, organisable and
	# share CALAIS.
	for index in hud.fleet_option.item_count:
		if String(hud.fleet_option.get_item_metadata(index)) == "org_fixture_a":
			hud.fleet_option.select(index)
			break
	hud._refresh_fleet_details()
	_require(hud._selected_fleet_id() == "org_fixture_a", "the fixture must select the intended source fleet")
	_require(fleet_markers.selected_fleet() == "org_fixture_a", "selecting the source in the HUD must synchronize the same fleet to the map")
	_require(hud.ship_transfer_list.item_count == 3, "the ship list must show every ship in the selected fleet")
	_require(hud.target_fleet_option.item_count == 1 and String(hud.target_fleet_option.get_item_metadata(0)) == "org_fixture_b", "the target list must offer the other co-located fleet")

	# Split: select exactly one ship and split it into a brand-new fleet.
	hud.ship_transfer_list.select(0, false)
	hud._refresh_organisation_validation()
	_require(not hud.split_fleet_button.disabled, "splitting one selected ship must be enabled: %s" % hud.split_fleet_button.tooltip_text)
	var split_ship_id := String(hud.ship_transfer_list.get_item_metadata(0))
	var fleet_count_before_split := world.fleet_registry.size()
	hud._split_selected_ships()
	simulation.scheduler.process_commands()
	_require(world.fleet_registry.size() == fleet_count_before_split + 1, "the UI split action must create exactly one new fleet")
	_require(String(world.get_ship(split_ship_id)["fleet_id"]) != "org_fixture_a", "the split ship must leave its source fleet")
	_require(hud._selected_fleet_id() == "org_fixture_a" and fleet_markers.selected_fleet() == "org_fixture_a", "a live selection must remain on the surviving source fleet across a split in both HUD and map")
	hud._refresh_all()
	for index in hud.fleet_option.item_count:
		if String(hud.fleet_option.get_item_metadata(index)) == "org_fixture_a":
			hud.fleet_option.select(index)
			break
	hud._refresh_fleet_details()
	_require(hud.ship_transfer_list.item_count == 2, "the source fleet's ship list must reflect the split")

	# Transfer: move one remaining ship from org_fixture_a to org_fixture_b.
	hud.ship_transfer_list.select(0, false)
	for index in hud.target_fleet_option.item_count:
		if String(hud.target_fleet_option.get_item_metadata(index)) == "org_fixture_b":
			hud.target_fleet_option.select(index)
			break
	hud._refresh_organisation_validation()
	_require(not hud.transfer_ships_button.disabled, "transferring to an eligible target must be enabled: %s" % hud.transfer_ships_button.tooltip_text)
	var transfer_ship_id := String(hud.ship_transfer_list.get_item_metadata(0))
	hud._transfer_selected_ships()
	simulation.scheduler.process_commands()
	_require(String(world.get_ship(transfer_ship_id)["fleet_id"]) == "org_fixture_b", "the UI transfer action must move the ship into the target fleet")
	hud._refresh_all()
	for index in hud.fleet_option.item_count:
		if String(hud.fleet_option.get_item_metadata(index)) == "org_fixture_a":
			hud.fleet_option.select(index)
			break
	hud._refresh_fleet_details()
	_require(hud.ship_transfer_list.item_count == 1, "the source fleet must show one remaining ship after the transfer")

	# Merge: select org_fixture_b itself before folding it into
	# org_fixture_a. The selected fleet is deliberately the lexicographically
	# later ID, so MergeFleetsCommand removes it and the HUD/map must retarget
	# together to the deterministic surviving fleet.
	for index in hud.fleet_option.item_count:
		if String(hud.fleet_option.get_item_metadata(index)) == "org_fixture_b":
			hud.fleet_option.select(index)
			break
	hud._refresh_fleet_details()
	_require(hud._selected_fleet_id() == "org_fixture_b" and fleet_markers.selected_fleet() == "org_fixture_b", "the fleet that will be merged away must be selected in both HUD and map before the command")
	for index in hud.target_fleet_option.item_count:
		if String(hud.target_fleet_option.get_item_metadata(index)) == "org_fixture_a":
			hud.target_fleet_option.select(index)
			break
	hud._refresh_organisation_validation()
	_require(not hud.merge_fleets_button.disabled, "merging into an eligible target must be enabled: %s" % hud.merge_fleets_button.tooltip_text)
	hud._merge_selected_fleets()
	simulation.scheduler.process_commands()
	# MergeFleetsCommand.apply() keeps the alphabetically-first fleet ID as
	# the survivor regardless of which side issued the command
	# (_sorted_fleet_ids()) - "org_fixture_a" outlives "org_fixture_b" here.
	_require(not world.fleet_registry.has("org_fixture_b"), "the UI merge action must remove the merged-away fleet")
	_require(int((world.get_fleet("org_fixture_a").get("ship_ids", []) as Array).size()) == 3, "the surviving fleet must own every ship after the merge")
	_require(hud._selected_fleet_id() == "org_fixture_a", "the HUD must retarget a merged-away live selection to the deterministic surviving fleet")
	_require(fleet_markers.selected_fleet() == "org_fixture_a", "the map must retarget to the same surviving fleet after the selected fleet is merged away")
	fleet_markers.debug_force_refresh()
	_require(fleet_markers.debug_route_style() == "none" and not fleet_markers.debug_destination_visible(), "retargeting a merged-away selection must not leave route geometry owned by the removed fleet")

	print("Naval fleet organisation HUD test passed.")
	quit(0)
