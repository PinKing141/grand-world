extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")
const RequestFleetRetreatCommandScript = preload("res://scripts/simulation/commands/request_fleet_retreat_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval combat test failed: %s" % message)
		quit(1)


func _make_world(owners: Dictionary, names: Dictionary) -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(owners, names)
	EconomySystemScript.initialize_world(world)
	world.war_registry["war_1"] = {
		"war_id": "war_1",
		"status": "active",
		"attacker_leader": "ENG",
		"defender_leader": "BUR",
		"attackers": ["ENG"],
		"defenders": ["BUR"],
		"battle_score_attacker": 0,
		# Save validation requires a structurally valid war_goal even though
		# naval combat itself never reads it - a land-warfare concept this
		# fixture only carries to satisfy the shared war_registry schema.
		"war_goal": {"type": "conquer_province", "province_id": CALAIS, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
	}
	return world


func _make_channel_world() -> CampaignWorldState:
	return _make_world({CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR"}, {"ENG": "England", "BUR": "Burgundy"})


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, location_id: int, ship_count: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, location_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	var ship_ids: Array = []
	for index in ship_count:
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "war_galley", 0)
		ship_ids.append(ship_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _make_scheduler(world: CampaignWorldState, events: SimulationEventBus) -> SimulationScheduler:
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(
		func(day_world) -> void: FleetMovementSystemScript.advance_day(day_world, events)
	)
	scheduler.daily_systems.append(
		func(day_world) -> void: NavalCombatSystemScript.advance_day(day_world, events)
	)
	return scheduler


func _run() -> void:
	# --- Lopsided engagement: three England war galleys against one
	# Burgundy war galley, meeting in open water. Overwhelming power means
	# the outcome is deterministic regardless of dice variance, without
	# needing to pin an exact round count. ---
	var world := _make_channel_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng", "ENG", STRAITS_OF_DOVER, 3)
	_add_fleet(world, "fleet_bur", "BUR", STRAITS_OF_DOVER, 1)
	var scheduler := _make_scheduler(world, events)

	scheduler.advance_one_day()
	_require(not String(world.get_fleet("fleet_eng")["battle_id"]).is_empty(), "co-located hostile fleets must start a battle")
	var battle_id := String(world.get_fleet("fleet_eng")["battle_id"])
	_require(String(world.get_fleet("fleet_bur")["battle_id"]) == battle_id, "both sides must reference the same battle")
	_require(String(world.get_fleet("fleet_eng")["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_BATTLE, "an engaged fleet must report battle status")
	var battle := world.get_naval_battle(battle_id)
	_require((battle["attacker_fleets"] as Array) == ["fleet_eng"], "England (the war's attacker) must be recorded as the attacking side")
	_require((battle["defender_fleets"] as Array) == ["fleet_bur"], "Burgundy (the war's defender) must be recorded as the defending side")

	for i in range(34):
		scheduler.advance_one_day()
		if String(world.get_naval_battle(battle_id).get("status", "")) == "completed":
			break
	battle = world.get_naval_battle(battle_id)
	_require(String(battle.get("status", "")) == "completed", "the battle must reach a terminal state well within the round cap")
	_require(String(battle.get("winner_side", "")) == "attacker", "the overwhelmingly stronger side must win")
	_require(not world.fleet_registry.has("fleet_bur") or String(world.get_fleet("fleet_bur")["location_status"]) != CampaignWorldStateScript.FLEET_LOCATION_BATTLE, "the losing fleet must leave battle status one way or another")
	_require(world.fleet_registry.has("fleet_eng"), "the overwhelmingly stronger side must survive")
	var winner := world.get_fleet("fleet_eng")
	_require(String(winner["battle_id"]).is_empty(), "the winning fleet must have its battle reference cleared")
	_require(String(winner["location_status"]) in [CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, CampaignWorldStateScript.FLEET_LOCATION_DOCKED], "the winning fleet must return to a normal location status")
	_require(int(world.war_registry["war_1"]["battle_score_attacker"]) > 0, "England winning as the war's attacker must move war score in its favour")

	# No ship may exist in two fleets, and every surviving ship must still be
	# listed by exactly the fleet that owns it.
	var seen_ships := {}
	for raw_fleet_id in world.fleet_registry:
		for raw_ship_id in (world.fleet_registry[raw_fleet_id] as Dictionary).get("ship_ids", []):
			var ship_id := String(raw_ship_id)
			_require(not seen_ships.has(ship_id), "ship %s must not belong to two fleets after battle" % ship_id)
			seen_ships[ship_id] = true
			_require(world.ship_registry.has(ship_id), "every fleet-listed ship must still exist")
			_require(String((world.ship_registry[ship_id] as Dictionary).get("fleet_id", "")) == String(raw_fleet_id), "ship %s and its fleet must still agree on membership" % ship_id)

	# --- Determinism: an identical fixture, same campaign seed, must resolve
	# to the identical outcome. ---
	var world_b := _make_channel_world()
	var events_b := SimulationEventBusScript.new()
	root.add_child(events_b)
	_add_fleet(world_b, "fleet_eng", "ENG", STRAITS_OF_DOVER, 3)
	_add_fleet(world_b, "fleet_bur", "BUR", STRAITS_OF_DOVER, 1)
	var scheduler_b := _make_scheduler(world_b, events_b)
	var battle_id_b := ""
	for i in range(35):
		scheduler_b.advance_one_day()
		if battle_id_b.is_empty() and not String(world_b.get_fleet("fleet_eng").get("battle_id", "")).is_empty():
			battle_id_b = String(world_b.get_fleet("fleet_eng")["battle_id"])
		if not battle_id_b.is_empty() and String(world_b.get_naval_battle(battle_id_b).get("status", "")) == "completed":
			break
	_require(world.fleet_registry.has("fleet_eng") == world_b.fleet_registry.has("fleet_eng"), "identical fixtures must produce identical survivors")
	_require(world.current_day == world_b.current_day, "identical fixtures must resolve in the identical number of ticks")
	if world.fleet_registry.has("fleet_eng"):
		_require(int(world.get_fleet("fleet_eng")["aggregate"]["total_hull"]) == int(world_b.get_fleet("fleet_eng")["aggregate"]["total_hull"]), "identical fixtures must leave the survivor at identical hull")

	# --- Retreat: a closer fight (five versus one) where the loser has a
	# legal home port must actually sail there, not just vanish or freeze
	# in RETREATING status - this exercises the fix to FleetMovementSystem's
	# own guard (it previously only ever advanced MOVING fleets, never
	# RETREATING ones) end-to-end. ---
	var world_c := _make_channel_world()
	var events_c := SimulationEventBusScript.new()
	root.add_child(events_c)
	_add_fleet(world_c, "fleet_eng_c", "ENG", STRAITS_OF_DOVER, 5)
	_add_fleet(world_c, "fleet_bur_c", "BUR", STRAITS_OF_DOVER, 1)
	var scheduler_c := _make_scheduler(world_c, events_c)
	for i in range(45):
		scheduler_c.advance_one_day()
		if world_c.fleet_registry.has("fleet_bur_c") and int(world_c.get_fleet("fleet_bur_c")["location_id"]) == PICARDIE and String(world_c.get_fleet("fleet_bur_c")["location_status"]) != CampaignWorldStateScript.FLEET_LOCATION_RETREATING:
			break
	_require(world_c.fleet_registry.has("fleet_bur_c"), "Burgundy's fleet must survive by retreating, not be destroyed, when a legal home port exists")
	var retreated := world_c.get_fleet("fleet_bur_c")
	_require(String(retreated["location_status"]) != CampaignWorldStateScript.FLEET_LOCATION_RETREATING, "a retreating fleet must actually complete its retreat, not freeze indefinitely")
	_require(int(retreated["location_id"]) == PICARDIE, "Burgundy's fleet must retreat to its own port, Picardie")

	# Note: "no legal retreat -> explicit destruction" is not exercised
	# end-to-end here. NavalCombatSystem._begin_retreat searches the full
	# real-world maritime graph (MaritimeGraph.load_default()), and any
	# province absent from a lightweight test fixture's ownership map reads
	# as "unclaimed" - which NavalAccessPolicy.can_dock treats as dockable by
	# anyone. Genuinely isolating a fleet from every port on the real map
	# would need the entire map under hostile control, not a small fixture -
	# the identical limitation N3.3's evidence doc already documented for
	# TransportSystem's analogous recovery search. The destruction branch
	# itself mirrors CancelShipConstructionCommand/_destroy_stranded_operation's
	# already-proven erase-and-emit pattern exactly, so it is not a new kind
	# of risk, just untested via full end-to-end geography here.

	# --- Save/load mid-battle. Fleets meet at Picardie (a real, owned port
	# in this fixture) rather than the Straits of Dover sea zone, because
	# save validation requires every fleet location to be a known province -
	# a sea zone outside this lightweight fixture's ownership map would
	# itself be rejected as "unknown," independent of anything battle-related. ---
	var world_e := _make_channel_world()
	var events_e := SimulationEventBusScript.new()
	root.add_child(events_e)
	_add_fleet(world_e, "fleet_eng_e", "ENG", PICARDIE, 2)
	_add_fleet(world_e, "fleet_bur_e", "BUR", PICARDIE, 2)
	var scheduler_e := _make_scheduler(world_e, events_e)
	scheduler_e.advance_one_day()
	scheduler_e.advance_one_day()
	_require(not world_e.naval_battle_registry.is_empty(), "fixture assumption: the battle must still be active mid-fight")
	var checksum_before := world_e.checksum()
	var saved := world_e.to_save_dict("test")
	var reloaded := _make_channel_world()
	_add_fleet(reloaded, "fleet_eng_e", "ENG", PICARDIE, 2)
	_add_fleet(reloaded, "fleet_bur_e", "BUR", PICARDIE, 2)
	var apply_error := reloaded.apply_save_dict(saved)
	_require(apply_error.is_empty(), "a mid-battle save must apply cleanly: %s" % apply_error)
	_require(reloaded.checksum() == checksum_before, "reloading a mid-battle save must reproduce an identical checksum")
	_require(reloaded.naval_battle_registry.size() == world_e.naval_battle_registry.size(), "the reloaded world must keep the active battle")

	# Corruption rejection: a fleet claiming a battle the registry does not have.
	var dangling_save := saved.duplicate(true)
	var dangling_fleets: Dictionary = (dangling_save["fleet_registry"] as Dictionary).duplicate(true)
	var stray_fleet: Dictionary = (dangling_fleets["fleet_eng_e"] as Dictionary).duplicate(true)
	stray_fleet["battle_id"] = "naval_battle_does_not_exist"
	dangling_fleets["fleet_eng_e"] = stray_fleet
	dangling_save["fleet_registry"] = dangling_fleets
	_require(not _make_channel_world().apply_save_dict(dangling_save).is_empty(), "a fleet referencing an unknown naval battle must be rejected")

	# --- Reinforcement: a friendly fleet arriving at an already-active
	# battle's location joins the correct side rather than starting a
	# separate, overlapping battle. ---
	var world_f := _make_channel_world()
	var events_f := SimulationEventBusScript.new()
	root.add_child(events_f)
	_add_fleet(world_f, "fleet_eng_f", "ENG", STRAITS_OF_DOVER, 1)
	_add_fleet(world_f, "fleet_bur_f", "BUR", STRAITS_OF_DOVER, 1)
	var scheduler_f := _make_scheduler(world_f, events_f)
	scheduler_f.advance_one_day()
	var battle_id_f := String(world_f.get_fleet("fleet_eng_f")["battle_id"])
	_require(not battle_id_f.is_empty(), "fixture assumption: the initial pair must start a battle")
	_add_fleet(world_f, "fleet_eng_f2", "ENG", STRAITS_OF_DOVER, 1)
	scheduler_f.advance_one_day()
	_require(String(world_f.get_fleet("fleet_eng_f2")["battle_id"]) == battle_id_f, "a friendly fleet arriving at an active battle's location must reinforce it")
	_require((world_f.get_naval_battle(battle_id_f)["attacker_fleets"] as Array).has("fleet_eng_f2"), "the battle record must list the reinforcing fleet")
	_require(String(world_f.get_fleet("fleet_eng_f2")["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_BATTLE, "a reinforcing fleet must report battle status")

	# --- Voluntary retreat: rejected before the minimum round count, then
	# accepted; withdrawing the only attacker ends the battle in the
	# defender's favour, exactly as a combat defeat would. ---
	var world_g := _make_channel_world()
	var events_g := SimulationEventBusScript.new()
	root.add_child(events_g)
	_add_fleet(world_g, "fleet_eng_g", "ENG", STRAITS_OF_DOVER, 1)
	_add_fleet(world_g, "fleet_bur_g", "BUR", STRAITS_OF_DOVER, 1)
	var scheduler_g := _make_scheduler(world_g, events_g)
	scheduler_g.advance_one_day()
	var request := RequestFleetRetreatCommandScript.new("ENG", "fleet_eng_g")
	_require(not request.validate(world_g).is_empty(), "retreat must be rejected before the minimum round count")
	for i in range(NavalCombatSystemScript.MIN_RETREAT_ROUNDS):
		scheduler_g.advance_one_day()
		if String(world_g.get_fleet("fleet_eng_g").get("battle_id", "")).is_empty():
			break
	_require(not String(world_g.get_fleet("fleet_eng_g").get("battle_id", "")).is_empty(), "fixture assumption: the battle must still be active and undecided at the minimum round count")
	var battle_id_g := String(world_g.get_fleet("fleet_eng_g")["battle_id"])
	request = RequestFleetRetreatCommandScript.new("ENG", "fleet_eng_g")
	_require(request.validate(world_g).is_empty(), "retreat must be accepted once the minimum round count is met: %s" % request.validate(world_g))
	request.apply(world_g, events_g)
	_require(String(world_g.get_fleet("fleet_eng_g")["battle_id"]).is_empty(), "a withdrawn fleet must have its battle reference cleared immediately")
	_require(not (world_g.get_naval_battle(battle_id_g)["attacker_fleets"] as Array).has("fleet_eng_g"), "a withdrawn fleet must be removed from the battle's side list")
	_require(String(world_g.get_naval_battle(battle_id_g)["status"]) == "completed", "withdrawing the only attacker must end the battle immediately")
	_require(String(world_g.get_naval_battle(battle_id_g)["winner_side"]) == "defender", "the side that was withdrawn from must lose, exactly as a combat defeat would")

	# --- Complete battle model: positioning/active assignments are retained
	# for the report, morale can terminate a side before total sinking, and a
	# disabled non-transport hull can be captured atomically. ---
	_require(int(battle.get("attacker_initial_ships", 0)) == 3, "battle reports must retain initial attacker ship totals")
	_require(not (battle.get("attacker_positioning_breakdown", {}) as Dictionary).is_empty(), "battle reports must explain attacker positioning")
	_require(not (battle.get("attacker_active_ships", []) as Array).is_empty(), "stable active-ship assignment must be retained")
	_require(int(battle.get("attacker_morale_bp", 10000)) < 10000 or int(battle.get("defender_morale_bp", 10000)) < 10000, "combat must apply authoritative morale loss")

	var morale_world := _make_channel_world()
	var morale_events := SimulationEventBusScript.new()
	root.add_child(morale_events)
	_add_fleet(morale_world, "fleet_eng_morale", "ENG", STRAITS_OF_DOVER, 1)
	_add_fleet(morale_world, "fleet_bur_morale", "BUR", STRAITS_OF_DOVER, 1)
	var fragile := morale_world.get_fleet("fleet_bur_morale")
	fragile["morale_bp"] = NavalCombatSystemScript.MORALE_COLLAPSE_BP + 50
	morale_world.fleet_registry["fleet_bur_morale"] = fragile
	var morale_scheduler := _make_scheduler(morale_world, morale_events)
	morale_scheduler.advance_one_day()
	var morale_battle_id := String(morale_world.get_fleet("fleet_eng_morale").get("battle_id", ""))
	morale_scheduler.advance_one_day()
	var morale_battle := morale_world.get_naval_battle(morale_battle_id)
	_require(String(morale_battle.get("status", "")) == "completed", "a side below the morale threshold after a round must collapse")
	_require(String(morale_battle.get("end_reason", "")) == "morale_collapse", "morale termination must be explicit in the battle report")

	var capture_world := _make_channel_world()
	var capture_events := SimulationEventBusScript.new()
	root.add_child(capture_events)
	_add_fleet(capture_world, "fleet_eng_capture", "ENG", STRAITS_OF_DOVER, 1)
	_add_fleet(capture_world, "fleet_bur_capture", "BUR", STRAITS_OF_DOVER, 1)
	var captured_ship_id := String(capture_world.fleet_ships("fleet_bur_capture")[0])
	var disabled_ship := capture_world.get_ship(captured_ship_id)
	disabled_ship["hull_bp"] = NavalCombatSystemScript.CAPTURE_HULL_BP
	disabled_ship["disabled"] = true
	capture_world.ship_registry[captured_ship_id] = disabled_ship
	FleetSystemScript.recompute_aggregate(capture_world, "fleet_bur_capture")
	var capture_battle_id := "naval_battle_capture"
	var capture_battle := CampaignWorldStateScript.make_naval_battle_record(capture_battle_id, "war_1", STRAITS_OF_DOVER, 0)
	capture_battle["attacker_fleets"] = ["fleet_eng_capture"]
	capture_battle["defender_fleets"] = ["fleet_bur_capture"]
	for capture_fleet_id in ["fleet_eng_capture", "fleet_bur_capture"]:
		var capture_fleet := capture_world.get_fleet(capture_fleet_id)
		capture_fleet["battle_id"] = capture_battle_id
		capture_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_BATTLE
		capture_world.fleet_registry[capture_fleet_id] = capture_fleet
	capture_world.naval_battle_registry[capture_battle_id] = capture_battle
	NavalCombatSystemScript._finish_battle(capture_world, capture_events, capture_battle, true, preload("res://scripts/simulation/ship_definitions.gd").load_default())
	_require(capture_world.ship_registry.has(captured_ship_id), "a captured ship must remain a stable ship record")
	var captured_ship := capture_world.get_ship(captured_ship_id)
	_require(String(captured_ship.get("owner_country_id", "")) == "ENG" and String(captured_ship.get("fleet_id", "")) == "fleet_eng_capture", "capture must atomically change ship owner and fleet membership")
	_require(String(captured_ship.get("captured_from", "")) == "BUR" and String(captured_ship.get("captured_battle_id", "")) == capture_battle_id, "capture provenance must identify the old owner and battle")
	_require((capture_world.get_naval_battle(capture_battle_id).get("attacker_captured_ship_ids", []) as Array).has(captured_ship_id), "the final report must list captured ships")

	print("Naval combat test passed. battle=%s days=%d" % [battle_id, world.current_day])
	quit(0)
