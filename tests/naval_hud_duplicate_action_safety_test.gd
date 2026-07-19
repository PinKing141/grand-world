extends SceneTree

## FL6.2 (Input and focus) automatable slice: "Verify double-click, rapid-click
## and key-repeat cannot duplicate commands." Godot's own Button.pressed does
## not literally double-fire from one physical click, so the real risk this
## covers is calling an action handler twice before the UI has refreshed
## itself to disable the button (a genuine race: two rapid presses landing in
## the same SimulationScheduler command batch, before process_commands() runs
## and the button's own validate()-driven disabled state catches up). Every
## handler here calls its action function TWICE in a row with no refresh in
## between, then processes commands once, and checks the world ends up
## exactly as if the button had only been pressed once - covering the
## highest-risk cases (treasury/sailor double-spend on construction, capacity
## double-reservation on embark) plus the three organisation commands'
## ownership-integrity invariant and a cancel-then-cancel-again case.
##
## Move, retreat, cancel-movement, set-home-port, set-mission, and
## assign-admiral are not covered here individually: audited instead of
## tested, since each is either a pure state-overwrite (a second identical
## order just recomputes the same result) or naturally rejected once the
## first command's apply() has already changed the precondition the second
## command's validate() checks (documented per-case in
## docs/roadmap/naval/g1_finish_line/evidence/FL6_AUTOMATABLE_ACCEPTANCE.md).

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const NavalHUDScript = preload("res://scripts/ui/naval_hud.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

const CALAIS := 87


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval HUD duplicate action safety test failed: %s" % message)
		quit(1)


func _add_fleet(world: CampaignWorldState, fleet_id: String, definitions: Array) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, "ENG", CALAIS)
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


func _test_construct_ship_double_press(simulation: ControllerScript, hud: NavalHUDScript) -> void:
	var world := simulation.world
	world.naval_construction_registry.clear()
	var runtime := world.country_runtime("ENG")
	# Deliberately generous - even with treasury/sailors for many ships, the
	# real guard here is ConstructShipCommand's own one-project-per-port
	# queue limit, not a resource shortfall.
	runtime["treasury"] = 5000000
	runtime["sailors"] = 5000
	world.set_country_runtime("ENG", runtime)
	hud._on_province_selected({"province_id": CALAIS, "province_name": "Calais", "owner_tag": "ENG", "owner_name": "England", "is_playable": true})
	_require(hud.ship_option.item_count > 0, "fixture assumption: the ship option list must be populated")
	# FL3.2's technology gate (ConstructShipCommand.validate()) means the
	# alphabetically-first default selection ("heavy_galleon", required
	# military tech 1) is not actually buildable by a fresh ENG country at
	# zero technology - explicitly pick a tech-0 ship instead, the same
	# "deliberately generous" spirit the treasury/sailors setup above already
	# uses so this test proves duplicate-press safety, not eligibility.
	for index in hud.ship_option.item_count:
		if String(hud.ship_option.get_item_metadata(index)) == "war_galley":
			hud.ship_option.select(index)
			break
	var treasury_before := int(world.country_runtime("ENG")["treasury"])

	hud._construct_selected_ship()
	hud._construct_selected_ship()
	simulation.scheduler.process_commands()

	_require(world.naval_construction_registry.size() == 1, "DUPLICATE_CONSTRUCTION: two rapid presses must queue exactly one construction project, not two")
	var definition_id := String((world.naval_construction_registry.values()[0] as Dictionary).get("definition_id", ""))
	var ShipDefinitionsScript = load("res://scripts/simulation/ship_definitions.gd")
	var cost := int(ShipDefinitionsScript.load_default().ship(definition_id).get("cost", 0))
	_require(int(world.country_runtime("ENG")["treasury"]) == treasury_before - cost, "DOUBLE_SPEND: treasury must be debited exactly once, not twice")


func _test_embark_double_press(simulation: ControllerScript, hud: NavalHUDScript) -> void:
	var world := simulation.world
	world.army_registry.clear()
	world.fleet_registry.clear()
	world.ship_registry.clear()
	world.transport_operation_registry.clear()
	_add_fleet(world, "dup_carrier", ["transport_cog"])
	world.army_registry["dup_army"] = CampaignWorldStateScript.make_army_record("dup_army", "ENG", CALAIS)
	hud._refresh_all()
	_select_fleet(hud, "dup_carrier")
	for index in hud.army_option.item_count:
		if String(hud.army_option.get_item_metadata(index)) == "dup_army":
			hud.army_option.select(index)
			break
	hud._on_province_selected({"province_id": 235, "province_name": "Kent", "owner_tag": "ENG", "owner_name": "England", "is_playable": true})
	_require(not hud.embark_button.disabled, "fixture assumption: a legal embark order must be enabled: %s" % hud.embark_button.tooltip_text)

	hud._embark_selected_army()
	hud._embark_selected_army()
	simulation.scheduler.process_commands()

	_require(world.transport_operation_registry.size() == 1, "DUPLICATE_TRANSPORT: two rapid embark presses must create exactly one transport operation, not two reserving capacity twice over")
	_require(String(world.get_army("dup_army")["status"]) == CampaignWorldStateScript.ARMY_STATUS_EMBARKING, "the army must be embarking exactly once, not corrupted by a rejected second attempt")


func _test_organisation_double_press(simulation: ControllerScript, hud: NavalHUDScript) -> void:
	var world := simulation.world
	world.fleet_registry.clear()
	world.ship_registry.clear()
	_add_fleet(world, "dup_source", ["war_galley", "war_galley"])
	_add_fleet(world, "dup_target", ["war_galley"])
	hud._refresh_all()
	_select_fleet(hud, "dup_source")
	var ships_before := world.country_ships("ENG").size()

	# Split: select one ship, press split twice.
	hud.ship_transfer_list.select(0, false)
	hud._refresh_organisation_validation()
	_require(not hud.split_fleet_button.disabled, "fixture assumption: splitting one ship must be legal: %s" % hud.split_fleet_button.tooltip_text)
	hud._split_selected_ships()
	hud._split_selected_ships()
	simulation.scheduler.process_commands()
	_require(world.country_ships("ENG").size() == ships_before, "DUPLICATE_SPLIT: no ship may be lost or duplicated by a rapid double-press split")

	# Transfer: refresh, select the remaining source ship, press transfer twice.
	hud._refresh_all()
	_select_fleet(hud, "dup_source")
	hud.ship_transfer_list.select(0, false)
	for index in hud.target_fleet_option.item_count:
		if String(hud.target_fleet_option.get_item_metadata(index)) == "dup_target":
			hud.target_fleet_option.select(index)
			break
	hud._refresh_organisation_validation()
	_require(not hud.transfer_ships_button.disabled, "fixture assumption: transferring must be legal: %s" % hud.transfer_ships_button.tooltip_text)
	hud._transfer_selected_ships()
	hud._transfer_selected_ships()
	simulation.scheduler.process_commands()
	_require(world.country_ships("ENG").size() == ships_before, "DUPLICATE_TRANSFER: no ship may be lost or duplicated by a rapid double-press transfer")

	# Merge: refresh, select the (now likely empty/erased) source alongside
	# the target - use whatever two ENG fleets remain to prove a double merge
	# press cannot corrupt ownership either way.
	hud._refresh_all()
	var remaining_fleets := world.country_fleets("ENG")
	if remaining_fleets.size() >= 2:
		_select_fleet(hud, remaining_fleets[0])
		for index in hud.target_fleet_option.item_count:
			if String(hud.target_fleet_option.get_item_metadata(index)) == remaining_fleets[1]:
				hud.target_fleet_option.select(index)
				break
		if not hud.merge_fleets_button.disabled:
			hud._merge_selected_fleets()
			hud._merge_selected_fleets()
			simulation.scheduler.process_commands()
			_require(world.country_ships("ENG").size() == ships_before, "DUPLICATE_MERGE: no ship may be lost or duplicated by a rapid double-press merge")


func _test_cancel_transport_double_press(simulation: ControllerScript, hud: NavalHUDScript) -> void:
	var world := simulation.world
	world.army_registry.clear()
	world.fleet_registry.clear()
	world.ship_registry.clear()
	world.transport_operation_registry.clear()
	_add_fleet(world, "dup_cancel_carrier", ["transport_cog"])
	world.army_registry["dup_cancel_army"] = CampaignWorldStateScript.make_army_record("dup_cancel_army", "ENG", CALAIS)
	hud._refresh_all()
	_select_fleet(hud, "dup_cancel_carrier")
	for index in hud.army_option.item_count:
		if String(hud.army_option.get_item_metadata(index)) == "dup_cancel_army":
			hud.army_option.select(index)
			break
	hud._on_province_selected({"province_id": 235, "province_name": "Kent", "owner_tag": "ENG", "owner_name": "England", "is_playable": true})
	hud._embark_selected_army()
	simulation.scheduler.process_commands()
	_require(world.transport_operation_registry.size() == 1, "fixture assumption: the embark must have created one operation")
	hud._refresh_fleet_details()
	_require(hud.cancel_transport_button.visible, "fixture assumption: the fresh embarking operation must be cancellable")

	# Two rapid presses of Cancel: the second must find nothing left to
	# cancel (the button's own meta is stale after the first cancellation
	# erases the operation) and must not error or resurrect anything.
	hud._cancel_selected_transport()
	hud._cancel_selected_transport()
	simulation.scheduler.process_commands()
	_require(world.transport_operation_registry.is_empty(), "DUPLICATE_CANCEL: a double-cancel must not leave a dangling or resurrected operation")
	_require(String(world.get_army("dup_cancel_army")["status"]) == CampaignWorldStateScript.ARMY_STATUS_IDLE, "the army must end up idle, not stuck in a corrupted intermediate state")


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

	_test_construct_ship_double_press(simulation, hud)
	_test_embark_double_press(simulation, hud)
	_test_organisation_double_press(simulation, hud)
	_test_cancel_transport_double_press(simulation, hud)

	print("Naval HUD duplicate action safety test passed.")
	quit(0)
