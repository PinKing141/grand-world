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
	_require(hud.fleet_summary_label.text.begins_with("Fleets 1"), "a fresh England must load its source-tracked Channel fleet")
	_require(simulation.world.fleet_registry.has("starting_fleet_eng_channel"), "the campaign must initialize England's reviewed gameplay-placeholder fleet")

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
	_require(hud.fleet_option.item_count >= 2, "the completed ship must create a Calais reserve alongside England's starting fleet")
	# Select the newly constructed transport at Calais; the starting Channel
	# fleet is correctly based in Kent and cannot embark a Calais army.
	for index in hud.fleet_option.item_count:
		var candidate_id := String(hud.fleet_option.get_item_metadata(index))
		if int(simulation.world.get_fleet(candidate_id).get("location_id", -1)) == CALAIS:
			hud.fleet_option.select(index)
			break
	hud._refresh_fleet_details()
	var fleet_id := hud._selected_fleet_id()
	_require(not fleet_id.is_empty(), "the new fleet must be selectable")
	_require(hud.fleet_details_label.text.contains("Ships 1"), "the fleet panel must show the one completed ship")

	# FL2 closure audit: the panel must show damage-aware usable transport
	# capacity (TransportSystem.usable_capacity(), the same query command
	# validation uses), not the raw aggregate total that still counts a
	# disabled/badly damaged ship - a real correctness bug found and fixed by
	# that audit.
	var capacity_ship_id := String(simulation.world.fleet_ships(fleet_id)[0])
	var capacity_ship := simulation.world.get_ship(capacity_ship_id)
	capacity_ship["hull_bp"] = 4000
	simulation.world.ship_registry[capacity_ship_id] = capacity_ship
	hud._refresh_fleet_details()
	_require(hud.fleet_details_label.text.contains("Transport 0/0 reserved"), "a badly damaged ship must show zero usable transport capacity, not its raw undamaged total: %s" % hud.fleet_details_label.text)
	capacity_ship["hull_bp"] = 10000
	simulation.world.ship_registry[capacity_ship_id] = capacity_ship
	hud._refresh_fleet_details()
	_require(hud.fleet_details_label.text.contains("Transport 0/1000 reserved"), "restoring hull must restore the fleet panel's usable transport capacity: %s" % hud.fleet_details_label.text)

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
	_require(hud.fleet_option.item_count >= 2, "the naval panel must reflect both starting and constructed fleets after reload")

	# Cancel the reloaded operation through the UI, closing the loop.
	hud._cancel_selected_transport()
	simulation.scheduler.process_commands()
	_require(String(simulation.world.get_army("army_test")["status"]) == CampaignWorldStateScript.ARMY_STATUS_IDLE, "the UI cancel action must reach WorldState")
	_require(simulation.world.transport_operation_registry.is_empty(), "cancellation must remove the operation")

	# N5.3: fleet mission control (SetFleetMissionCommand) and the port
	# blockade label - a docked, uncontested port must read as not blockaded.
	hud._refresh_all()
	for index in hud.mission_option.item_count:
		if String(hud.mission_option.get_item_metadata(index)) == "blockade":
			hud.mission_option.select(index)
			break
	hud._refresh_mission_validation()
	_require(not hud.set_mission_button.disabled, "setting a docked fleet's mission must be enabled: %s" % hud.set_mission_button.tooltip_text)
	hud._set_selected_fleet_mission()
	simulation.scheduler.process_commands()
	_require(String(simulation.world.get_fleet(fleet_id)["mission"]) == "blockade", "the UI mission action must reach WorldState")
	hud._refresh_all()
	_require(hud.fleet_details_label.text.contains("Mission Blockade"), "the fleet panel must reflect the new mission")
	hud._on_province_selected({"province_id": CALAIS, "province_name": "Calais", "owner_tag": "ENG", "owner_name": "England", "is_playable": true})
	_require(hud.blockade_label.text.contains("not blockaded"), "an uncontested home port must read as not blockaded")

	# FL2.4 closure audit: the mission dropdown's tooltip must not stay silent
	# for the tactical missions FL3.4 gave real behaviour to, and must not
	# overclaim automatic stand-down for a player-controlled fleet (only
	# NavalAISystem's own AI-only planning loop does that - see
	# naval_ai_system.gd's player_country skip).
	for index in hud.mission_option.item_count:
		if String(hud.mission_option.get_item_metadata(index)) == "patrol":
			hud.mission_option.select(index)
			break
	hud._refresh_mission_validation()
	_require(hud.set_mission_button.tooltip_text.contains("player fleet keeps it until changed"), "the patrol tooltip must not overclaim automatic stand-down for a player fleet: %s" % hud.set_mission_button.tooltip_text)
	for index in hud.mission_option.item_count:
		if String(hud.mission_option.get_item_metadata(index)) == "trade_protection":
			hud.mission_option.select(index)
			break
	hud._refresh_mission_validation()
	_require(hud.set_mission_button.tooltip_text.contains("no gameplay effect yet"), "the trade_protection tooltip must be honest about having no consumer yet: %s" % hud.set_mission_button.tooltip_text)
	for index in hud.mission_option.item_count:
		if String(hud.mission_option.get_item_metadata(index)) == "blockade":
			hud.mission_option.select(index)
			break
	hud._refresh_mission_validation()

	# N4.4: battle panel, retreat control, and final report. Naval combat's
	# own correctness is proven separately (naval_combat_test.gd); this only
	# proves the UI actually reads and drives it. A synthetic hostile fleet
	# and battle are injected directly into the already-loaded real campaign
	# world, the same "tweak real state, then verify the panel" pattern
	# phase_5_integration_smoke.gd already uses for its own war-score display
	# check, since building a real opposing navy through the full economy/AI
	# loop would test WarfareSystem/AI, not this panel.
	if not simulation.world.has_country("FRA"):
		simulation.world.country_states["FRA"] = {"runtime_values": {}}
	var hostile_fleet_id := "hostile_test_fleet"
	simulation.world.fleet_registry[hostile_fleet_id] = CampaignWorldStateScript.make_fleet_record(hostile_fleet_id, "FRA", CALAIS)
	var hostile_ship_id := "hostile_test_ship"
	simulation.world.ship_registry[hostile_ship_id] = CampaignWorldStateScript.make_ship_record(hostile_ship_id, "FRA", hostile_fleet_id, "war_galley", simulation.world.current_day)
	var hostile_fleet := simulation.world.get_fleet(hostile_fleet_id)
	hostile_fleet["ship_ids"] = [hostile_ship_id]
	simulation.world.fleet_registry[hostile_fleet_id] = hostile_fleet
	var battle_id := "test_naval_battle"
	simulation.world.war_registry["test_war"] = {
		"war_id": "test_war", "status": "active", "attacker_leader": "ENG", "defender_leader": "FRA",
		"attackers": ["ENG"], "defenders": ["FRA"], "battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": CALAIS, "target_country": "FRA", "justification": "claim", "peace_cost": 0},
	}
	var battle := CampaignWorldStateScript.make_naval_battle_record(battle_id, "test_war", CALAIS, simulation.world.current_day)
	battle["attacker_fleets"] = [fleet_id]
	battle["defender_fleets"] = [hostile_fleet_id]
	battle["round"] = 3
	battle["attacker_hull_lost"] = 40
	battle["defender_hull_lost"] = 120
	battle["defender_ships_sunk"] = 1
	simulation.world.naval_battle_registry[battle_id] = battle
	var player_fleet := simulation.world.get_fleet(fleet_id)
	player_fleet["battle_id"] = battle_id
	player_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_BATTLE
	simulation.world.fleet_registry[fleet_id] = player_fleet

	hud._refresh_all()
	_require(hud.battle_option.item_count == 1, "an active battle involving the player's fleet must appear in the battle list")
	_require(hud.battle_details_label.text.contains("round 3"), "the battle panel must show the current round")
	_require(hud.battle_details_label.text.contains("1 sunk"), "the battle panel must show ships sunk")
	_require(hud.fleet_details_label.text.contains("In battle"), "the fleet panel must show the fleet is in battle")
	_require(not hud.retreat_button.disabled, "retreat must be enabled once the minimum round count is met: %s" % hud.retreat_button.tooltip_text)

	hud._retreat_selected_fleet()
	simulation.scheduler.process_commands()
	_require(String(simulation.world.get_fleet(fleet_id).get("battle_id", "")).is_empty(), "the UI retreat action must clear the fleet's battle reference")
	_require(String(simulation.world.get_naval_battle(battle_id)["status"]) == "completed", "withdrawing the only attacker must end the battle")
	hud._refresh_all()
	_require(hud.battle_report_label.text.contains("Defender"), "the final report must record the defender's win once the attacker withdrew: %s" % hud.battle_report_label.text)

	var save_path := ProjectSettings.globalize_path(ControllerScript.QUICK_SAVE_PATH)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	print("Naval HUD integration smoke passed. fleet=%s" % fleet_id)
	quit(0)
