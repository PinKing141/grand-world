extends SceneTree

## N6.3: "100 seeded repetitions without invalid state or desync" - the
## G1/N6 exit gate's own words (docs/roadmap/naval/06_N6_AI_AND_UX.md "Exit
## Gate"), and 06_N6's "AI Content Rollout" step 1, "England and France
## Channel fixture." Each of 100 campaign seeds runs three independent
## Calais/Kent-vs-Picardie scenarios - a naval battle, a transport
## operation, and a blockade - then ticks the full relevant daily loop.
## Per-seed dice variance (battle rounds, hull damage) comes from the real
## campaign_seed-derived RNG streams every other combat test in this suite
## already relies on - this is not a fixed replay, each seed genuinely
## differs.
##
## The three scenarios are deliberately isolated into separate worlds, not
## combined into one - a first draft that put a transport fleet and a
## blockade fleet in the same sea zone as an ongoing battle discovered why:
## _join_reinforcements() correctly swept both into the fight as
## reinforcements (accurate, documented behaviour - "battle_paused" for an
## operation whose own carrier is fighting is a known, undecided gap, not a
## bug), which is real but not what this test exists to isolate. Separate
## worlds test each mechanism's own correctness under seed variance without
## incidental interference between them.
##
## "No invalid state" is checked two ways for every scenario, every seed:
## the same structural invariants naval_battle_blockade_stress_smoke.gd
## already checks at world scale (no duplicated/orphaned ship, no fleet
## claimed by two active battles), and the strongest available proof - a
## full save/load round trip, exercising every naval validator this
## pillar's own work has touched against whatever state that seed's dice
## actually produced, not a hand-picked fixture.
##
## "Desync" (two runs of the identical seed producing different results) is
## already covered elsewhere (naval_combat_test.gd, naval_ai_test.gd,
## simulation_frame_rate_determinism_test.gd); this test is about breadth
## across seeds and mechanisms, not repeating that proof again.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const FleetLogisticsSystemScript = preload("res://scripts/simulation/fleet_logistics_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")
const SetFleetMissionCommandScript = preload("res://scripts/simulation/commands/set_fleet_mission_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271
const SEED_COUNT := 100
const BASE_SEED := 14441111
const BATTLE_DAYS := 32
const TRANSPORT_DAYS := 15
const BLOCKADE_DAYS := 3

const OWNERS := {CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR", STRAITS_OF_DOVER: ""}
const NAMES := {"ENG": "England", "BUR": "Burgundy"}


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval Channel 100-seed acceptance test failed: %s" % message)
		quit(1)


func _make_world(seed_value: int) -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(OWNERS, NAMES, "channel_100_seed", seed_value)
	EconomySystemScript.initialize_world(world)
	world.war_registry["war_1"] = {
		"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "BUR",
		"attackers": ["ENG"], "defenders": ["BUR"], "battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": PICARDIE, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
	}
	return world


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, home_port_id: int, location_id: int, location_status: String, ship_count: int, definition_id: String) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, home_port_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = location_status
	var ship_ids: Array = []
	for index in ship_count:
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, definition_id, 0)
		ship_ids.append(ship_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


## No invalid state, structurally: no ship duplicated or orphaned, no fleet
## claimed by two active battles - the same checks
## naval_battle_blockade_stress_smoke.gd already applies at world scale.
func _check_structural_invariants(world: CampaignWorldState, seed_value: int, scenario: String) -> void:
	var seen_ships := {}
	for raw_fleet_id in world.fleet_registry:
		var fleet: Dictionary = world.fleet_registry[raw_fleet_id]
		for raw_ship_id in (fleet.get("ship_ids", []) as Array):
			var ship_id := String(raw_ship_id)
			_require(not seen_ships.has(ship_id), "seed %d (%s): ship %s must not belong to more than one fleet" % [seed_value, scenario, ship_id])
			seen_ships[ship_id] = true
			_require(world.ship_registry.has(ship_id), "seed %d (%s): every fleet-listed ship must still exist" % [seed_value, scenario])
			_require(String((world.ship_registry[ship_id] as Dictionary).get("fleet_id", "")) == String(raw_fleet_id), "seed %d (%s): ship %s and its fleet must agree on membership" % [seed_value, scenario, ship_id])
	var claimed_by := {}
	for raw_battle_id in world.naval_battle_registry:
		var battle: Dictionary = world.naval_battle_registry[raw_battle_id]
		if String(battle.get("status", "")) != "active":
			continue
		for raw_fleet_id in (battle.get("attacker_fleets", []) as Array) + (battle.get("defender_fleets", []) as Array):
			_require(not claimed_by.has(String(raw_fleet_id)), "seed %d (%s): fleet %s must not belong to two active battles" % [seed_value, scenario, raw_fleet_id])
			claimed_by[String(raw_fleet_id)] = true


## The strongest available proof: every naval validator this pillar's own
## work touches must accept whatever state this seed's dice actually
## produced, not just a hand-picked fixture.
func _check_save_round_trip(world: CampaignWorldState, seed_value: int, scenario: String) -> void:
	var saved := world.to_save_dict("acceptance")
	var reloaded := _make_world(seed_value)
	var load_error := reloaded.apply_save_dict(saved)
	_require(load_error.is_empty(), "seed %d (%s): a save must load cleanly: %s" % [seed_value, scenario, load_error])
	_require(reloaded.checksum() == world.checksum(), "seed %d (%s): the reloaded checksum must match exactly" % [seed_value, scenario])


func _run_battle_scenario(seed_value: int) -> Dictionary:
	var world := _make_world(seed_value)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	# A close but not symmetric matchup - a perfectly even fleet count grinds
	# to the round cap almost identically every seed, which would make this
	# test's own "genuinely different outcomes" check meaningless; a small
	# edge lets per-round dice variance actually decide the winner and the
	# round count, not just the exact hull-lost total.
	_add_fleet(world, "battle_eng", "ENG", CALAIS, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 4, "war_galley")
	_add_fleet(world, "battle_bur", "BUR", PICARDIE, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 3, "war_galley")
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: FleetMovementSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: NavalCombatSystemScript.advance_day(day_world, events))
	for day in BATTLE_DAYS:
		scheduler.advance_one_day()

	_check_structural_invariants(world, seed_value, "battle")
	_check_save_round_trip(world, seed_value, "battle")

	var completed_battles := 0
	var total_hull_lost := 0
	for raw_battle_id in world.naval_battle_registry:
		var battle: Dictionary = world.naval_battle_registry[raw_battle_id]
		if String(battle.get("status", "")) == "completed":
			completed_battles += 1
		total_hull_lost += int(battle.get("attacker_hull_lost", 0)) + int(battle.get("defender_hull_lost", 0))
	events.queue_free()
	return {"resolved": completed_battles > 0, "total_hull_lost": total_hull_lost}


func _run_transport_scenario(seed_value: int) -> Dictionary:
	var world := _make_world(seed_value)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	world.army_registry["army_kent"] = CampaignWorldStateScript.make_army_record("army_kent", "ENG", KENT)
	_add_fleet(world, "transport_fleet", "ENG", KENT, KENT, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 1, "transport_cog")
	var embark := CreateTransportOperationCommandScript.new("ENG", "army_kent", "transport_fleet", CALAIS)
	_require(embark.validate(world).is_empty(), "fixture assumption: the transport operation must validate: %s" % embark.validate(world))
	embark.apply(world, events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: FleetMovementSystemScript.advance_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: TransportSystemScript.process_day(day_world, events))
	for day in TRANSPORT_DAYS:
		scheduler.advance_one_day()

	_check_structural_invariants(world, seed_value, "transport")
	_check_save_round_trip(world, seed_value, "transport")

	var completed := not world.transport_operation_registry.has("transport_1") and String(world.get_army("army_kent").get("status", "")) == CampaignWorldStateScript.ARMY_STATUS_IDLE
	events.queue_free()
	return {"completed": completed}


func _run_blockade_scenario(seed_value: int) -> Dictionary:
	var world := _make_world(seed_value)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "blockade_fleet", "ENG", CALAIS, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 1, "light_caravel")
	var mission := SetFleetMissionCommandScript.new("ENG", "blockade_fleet", "blockade")
	_require(mission.validate(world).is_empty(), "fixture assumption: the blockade mission must validate: %s" % mission.validate(world))
	mission.apply(world, events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: BlockadeSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: FleetLogisticsSystemScript.process_day(day_world, events))
	for day in BLOCKADE_DAYS:
		scheduler.advance_one_day()

	_check_structural_invariants(world, seed_value, "blockade")
	_check_save_round_trip(world, seed_value, "blockade")

	var formed := not world.blockaded_provinces.is_empty()
	events.queue_free()
	return {"formed": formed}


func _run() -> void:
	var started_usec := Time.get_ticks_usec()
	var battle_outcomes := 0
	var hull_lost_values := {}
	var transports_completed := 0
	var blockades_formed := 0
	for index in SEED_COUNT:
		var seed_value := BASE_SEED + index
		var battle_result := _run_battle_scenario(seed_value)
		if bool(battle_result["resolved"]):
			battle_outcomes += 1
		hull_lost_values[int(battle_result["total_hull_lost"])] = true
		var transport_result := _run_transport_scenario(seed_value)
		if bool(transport_result["completed"]):
			transports_completed += 1
		var blockade_result := _run_blockade_scenario(seed_value)
		if bool(blockade_result["formed"]):
			blockades_formed += 1
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0

	_require(battle_outcomes == SEED_COUNT, "every seed's evenly-matched battle must reach a terminal state within %d days" % BATTLE_DAYS)
	_require(hull_lost_values.size() > 1, "different seeds must produce genuinely different combat outcomes, not a frozen replay - real dice variance, not just structural correctness")
	_require(transports_completed == SEED_COUNT, "every seed's uncontested Calais-bound transport must complete")
	_require(blockades_formed == SEED_COUNT, "every seed's uncontested blockade must register")

	print("Naval Channel 100-seed acceptance test passed. seeds=%d battles_resolved=%d distinct_hull_outcomes=%d transports_completed=%d blockades_formed=%d elapsed_ms=%.2f" % [
		SEED_COUNT, battle_outcomes, hull_lost_values.size(), transports_completed, blockades_formed, elapsed_ms,
	])
	quit(0)
