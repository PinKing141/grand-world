extends SceneTree

## FL2.6 closure (transport workflow packet) headless integration test: the
## real NavalHUD transport panel must resolve the destination to a name, show
## reserved/required/available capacity persistently (not just inside a
## failure tooltip), expose the operation's route once it is sailing, offer
## cancellation during BOTH embarking and disembarking (the panel previously
## only ever offered it for embarking, silently hiding a legal
## disembarking-state cancellation), and let the player focus the carried
## army on the map for the single-operation case. Also proves war/peace/
## access changes actually refresh the panel, closing the closure audit's
## "unverified assumption" finding for that event coverage.

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
		push_error("Naval transport workflow HUD test failed: %s" % message)
		quit(1)


func _select_fleet(hud: NavalHUDScript, fleet_id: String) -> void:
	for index in hud.fleet_option.item_count:
		if String(hud.fleet_option.get_item_metadata(index)) == fleet_id:
			hud.fleet_option.select(index)
			break
	hud._refresh_fleet_details()


func _select_army(hud: NavalHUDScript, army_id: String) -> void:
	for index in hud.army_option.item_count:
		if String(hud.army_option.get_item_metadata(index)) == army_id:
			hud.army_option.select(index)
			break


func _advance_until_state(simulation: ControllerScript, hud: NavalHUDScript, operation_id: String, state: String, maximum_days := 15) -> bool:
	for day in range(maximum_days + 1):
		if String(simulation.world.get_transport_operation(operation_id).get("state", "")) == state:
			hud._refresh_fleet_details()
			return true
		if day < maximum_days:
			simulation.scheduler.advance_one_day()
	return false


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
	_require(simulation.initialized and hud != null and hud.army_layer != null, "naval HUD dependencies, including the wired ArmyLayer, must initialize")

	simulation.choose_player_country("ENG")
	simulation.scheduler.process_commands()
	var world: CampaignWorldState = simulation.world
	world.fleet_registry.clear()
	world.ship_registry.clear()
	# Clear England's real 1444 starting army too - otherwise it may be
	# co-located with the fixture at Calais and, since _populate_army_options()
	# does not preserve selection across a refresh, could silently become the
	# dropdown's default (index 0) selection instead of the intended fixture
	# army, exactly the hazard naval_hud_integration_smoke.gd's own fixture
	# comment warns about.
	world.army_registry.clear()

	world.fleet_registry["carrier"] = CampaignWorldStateScript.make_fleet_record("carrier", "ENG", CALAIS)
	world.ship_registry["carrier_s0"] = CampaignWorldStateScript.make_ship_record("carrier_s0", "ENG", "carrier", "transport_cog", 0)
	var carrier := world.get_fleet("carrier")
	carrier["ship_ids"] = ["carrier_s0"]
	world.fleet_registry["carrier"] = carrier
	FleetSystemScript.recompute_aggregate(world, "carrier")
	world.army_registry["army_workflow"] = CampaignWorldStateScript.make_army_record("army_workflow", "ENG", CALAIS)

	hud._refresh_all()
	_select_fleet(hud, "carrier")
	_require(hud.focus_carried_army_button.disabled, "with no active transport, focusing a carried army must be disabled: %s" % hud.focus_carried_army_button.tooltip_text)

	# Pre-embark: a persistent required/available preview, not just a
	# tooltip that only appears once the command has already been rejected.
	_select_army(hud, "army_workflow")
	hud._refresh_transport_panel()
	_require(hud.transport_label.text.contains("Selected army requires 1 capacity · 1000 available"), "the panel must show a persistent required/available capacity preview: %s" % hud.transport_label.text)

	hud._on_province_selected({"province_id": KENT, "province_name": "Kent", "owner_tag": "ENG", "owner_name": "England", "is_playable": true})
	_require(not hud.embark_button.disabled, "a legal embark order must be enabled: %s" % hud.embark_button.tooltip_text)
	hud._embark_selected_army()
	simulation.scheduler.process_commands()
	var operation_id := String(world.get_army("army_workflow").get("transport_operation_id", ""))
	_require(not operation_id.is_empty(), "the UI embark action must reach WorldState")
	hud._refresh_fleet_details()

	# Embarking: destination resolved to a name, reserved capacity shown,
	# cancellation offered with the correct consequence tooltip, and the
	# carried army can be focused on the map.
	var text := hud.transport_label.text
	_require(text.contains("Embarking bound for Kent · 1 capacity reserved"), "the operation line must resolve the destination to a name and show reserved capacity: %s" % text)
	_require(hud.cancel_transport_button.visible, "an embarking operation must be cancellable")
	_require(hud.cancel_transport_button.tooltip_text.contains("returns the army to its origin"), "the embarking cancellation tooltip must explain the consequence: %s" % hud.cancel_transport_button.tooltip_text)
	_require(not hud.focus_carried_army_button.disabled, "with exactly one active operation, focusing the carried army must be enabled")
	_require(String(hud.focus_carried_army_button.get_meta("army_id", "")) == "army_workflow", "the focus button must target the real carried army")
	hud._focus_carried_army()
	_require(hud.army_layer.selected_army() == "army_workflow", "pressing focus must actually select the carried army on ArmyLayer")

	# Sailing: the route must appear, resolved to names, and cancellation
	# must no longer be offered (CancelTransportOperationCommand rejects a
	# sailing operation - there is no legal cancel action to offer).
	_require(_advance_until_state(simulation, hud, operation_id, CampaignWorldStateScript.TRANSPORT_STATE_SAILING), "fixture assumption: the operation must reach sailing within the day budget")
	text = hud.transport_label.text
	_require(text.contains("Route") and text.contains("Kent"), "a sailing operation must show its real route, naming Kent as the destination: %s" % text)
	_require(not hud.cancel_transport_button.visible, "a sailing operation must not offer cancellation, matching CancelTransportOperationCommand.validate()")

	# Disembarking: the fixed gap - CancelTransportOperationCommand.validate()
	# has always accepted this state, but the panel previously only ever
	# offered the button for embarking, never disembarking.
	_require(_advance_until_state(simulation, hud, operation_id, CampaignWorldStateScript.TRANSPORT_STATE_DISEMBARKING), "fixture assumption: the operation must reach disembarking within the day budget")
	_require(hud.cancel_transport_button.visible, "a disembarking operation must be cancellable - this is the gap this packet fixes")
	_require(hud.cancel_transport_button.tooltip_text.contains("lands the army immediately"), "the disembarking cancellation tooltip must explain the real consequence: %s" % hud.cancel_transport_button.tooltip_text)

	# Completion: once the operation is gone, focusing a carried army must be
	# disabled again, not left stale pointing at a finished operation.
	for day in range(3):
		if not world.transport_operation_registry.has(operation_id):
			break
		simulation.scheduler.advance_one_day()
	_require(not world.transport_operation_registry.has(operation_id), "fixture assumption: the operation must complete within the day budget")
	hud._refresh_fleet_details()
	_require(hud.focus_carried_army_button.disabled, "once the transport completes, focusing a carried army must be disabled again")

	# War/peace/access hookups: the panel must refresh from these events
	# directly, not rely on an unrelated naval event happening to fire
	# afterward - matches war_hud.gd's own exact hookup for the same events.
	world.fleet_registry["late_fixture"] = CampaignWorldStateScript.make_fleet_record("late_fixture", "ENG", CALAIS)
	_require(hud.fleet_summary_label.text.begins_with("Fleets 1"), "fixture assumption: the panel must not have picked up the new fleet yet")
	simulation.event_bus.war_declared.emit("war_test", "ENG", "FRA", CALAIS)
	_require(hud.fleet_summary_label.text.begins_with("Fleets 2"), "war_declared must refresh the panel: %s" % hud.fleet_summary_label.text)

	world.fleet_registry["later_fixture"] = CampaignWorldStateScript.make_fleet_record("later_fixture", "ENG", CALAIS)
	simulation.event_bus.peace_signed.emit("war_test", "ENG", "FRA", world.current_day)
	_require(hud.fleet_summary_label.text.begins_with("Fleets 3"), "peace_signed must refresh the panel: %s" % hud.fleet_summary_label.text)

	world.fleet_registry["latest_fixture"] = CampaignWorldStateScript.make_fleet_record("latest_fixture", "ENG", CALAIS)
	simulation.event_bus.military_access_changed.emit("ENG", "FRA", true)
	_require(hud.fleet_summary_label.text.begins_with("Fleets 4"), "military_access_changed must refresh the panel: %s" % hud.fleet_summary_label.text)

	print("Naval transport workflow HUD test passed.")
	quit(0)
