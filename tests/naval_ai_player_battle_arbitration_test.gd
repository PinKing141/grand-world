extends SceneTree

## FL3 "Automated verification": "AI and player targeting the same sea zone
## still produces one authoritative battle" - previously untested, per
## FL3_CLOSURE_AUDIT.md's own accounting. Proves this through the real
## command/scheduler pipeline, not by reasoning about the code alone: a
## player-issued MoveFleetCommand (submitted directly, mirroring
## NavalHUD/simulation_controller's own path) and an AI-issued one
## (submitted via NavalAISystem._submit(), the real function every AI
## decision goes through) both target the same zone the same scheduler day,
## and both fleets are allowed to arrive on whatever day FleetMovementSystem
## actually completes each journey - not assumed to be simultaneous, since
## NavalCombatSystem._start_battles() runs once per day off a single,
## deterministic full-registry scan regardless of when or how each fleet
## got there, and this test verifies that claim rather than assuming it.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271
const MAX_WAIT_DAYS := 20

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize({CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR", STRAITS_OF_DOVER: ""}, {"ENG": "England", "BUR": "Burgundy"})
	EconomySystemScript.initialize_world(world)
	world.player_country = "ENG"
	world.war_registry["war_1"] = {
		"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "BUR",
		"attackers": ["ENG"], "defenders": ["BUR"], "battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": PICARDIE, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
	}
	return world


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, location_id: int, ship_count: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, location_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	var ship_ids: Array = []
	for index in ship_count:
		var ship_id := "%s_s%d" % [fleet_id, index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "war_galley", 0)
		ship_ids.append(ship_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: FleetMovementSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: NavalCombatSystemScript.advance_day(day_world, events))
	var naval_ai := NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())

	_add_fleet(world, "fleet_eng", "ENG", KENT, 3)
	_add_fleet(world, "fleet_bur", "BUR", PICARDIE, 3)

	# The player's own path: a direct MoveFleetCommand submission, the same
	# call NavalHUD/simulation_controller.move_fleet() makes.
	var player_move := MoveFleetCommandScript.new("fleet_eng", STRAITS_OF_DOVER, "ENG", "player")
	_check(player_move.validate(world).is_empty(), "PLAYER_MOVE_INVALID", "fixture assumption: the player's move must be legal: %s" % player_move.validate(world))
	scheduler.submit(player_move)

	# The AI's own path: NavalAISystem._submit(), the real function every AI
	# decision (including MoveFleetCommand ones, e.g. reinforcement) goes
	# through - not a synthetic direct scheduler.submit() bypassing it.
	var ai_move := MoveFleetCommandScript.new("fleet_bur", STRAITS_OF_DOVER, "BUR")
	_check(naval_ai._submit(world, "BUR", "tactical", ai_move, 90, "test: AI moves toward the same zone the player targeted", []), "AI_MOVE_REJECTED", "fixture assumption: the AI's move must be accepted by _submit(): %s" % ai_move.validate(world))

	# Both commands were submitted before any day has advanced - both are
	# "today's" commands regardless of source, exactly the scenario named.
	_check(world.naval_battle_registry.is_empty(), "BATTLE_FORMED_TOO_EARLY", "no battle can exist before either fleet has actually moved anywhere")

	var days_waited := 0
	while (int(world.get_fleet("fleet_eng").get("location_id", -1)) != STRAITS_OF_DOVER or int(world.get_fleet("fleet_bur").get("location_id", -1)) != STRAITS_OF_DOVER) and days_waited < MAX_WAIT_DAYS:
		scheduler.advance_one_day()
		days_waited += 1
	_check(days_waited < MAX_WAIT_DAYS, "FLEETS_NEVER_CO_LOCATED", "fixture assumption: both a 1-hop Kent and a 1-hop Picardie sailing must reach the Straits of Dover well within %d days" % MAX_WAIT_DAYS)
	_check(int(world.get_fleet("fleet_eng").get("location_id", -1)) == STRAITS_OF_DOVER, "ENG_NEVER_ARRIVED", "the player's fleet must have actually reached its ordered destination")
	_check(int(world.get_fleet("fleet_bur").get("location_id", -1)) == STRAITS_OF_DOVER, "BUR_NEVER_ARRIVED", "the AI's fleet must have actually reached its ordered destination")

	# The two co-located, at-war fleets might not yet share a battle on the
	# exact day the second one arrives if arrival and _start_battles() land
	# on different sub-steps of the same advance_one_day() call - advance
	# one further day to let the day's own daily_systems pass settle.
	if world.naval_battle_registry.is_empty():
		scheduler.advance_one_day()

	_check(world.naval_battle_registry.size() == 1, "NOT_EXACTLY_ONE_BATTLE", "a player-targeted and an AI-targeted fleet arriving at the same zone must produce exactly one authoritative battle, got %d: %s" % [world.naval_battle_registry.size(), world.naval_battle_registry.keys()])
	if world.naval_battle_registry.size() == 1:
		var battle: Dictionary = world.naval_battle_registry.values()[0]
		_check(int(battle.get("zone_id", -1)) == STRAITS_OF_DOVER, "BATTLE_WRONG_ZONE", "the battle must be recorded at the zone both fleets actually converged on")
		_check(String(battle.get("war_id", "")) == "war_1", "BATTLE_WRONG_WAR", "the battle must be attributed to the one active war between the two owners")
		var attacker_fleets: Array = battle.get("attacker_fleets", [])
		var defender_fleets: Array = battle.get("defender_fleets", [])
		_check(attacker_fleets.has("fleet_eng") or defender_fleets.has("fleet_eng"), "ENG_NOT_IN_BATTLE", "the player's fleet must be a participant on some side of the one battle")
		_check(attacker_fleets.has("fleet_bur") or defender_fleets.has("fleet_bur"), "BUR_NOT_IN_BATTLE", "the AI's fleet must be a participant on some side of the one battle")
		_check(not (attacker_fleets.has("fleet_eng") and attacker_fleets.has("fleet_bur")), "BOTH_FLEETS_SAME_SIDE_ATTACKER", "the two hostile fleets must be on opposing sides, not the same side")
		_check(not (defender_fleets.has("fleet_eng") and defender_fleets.has("fleet_bur")), "BOTH_FLEETS_SAME_SIDE_DEFENDER", "the two hostile fleets must be on opposing sides, not the same side")
		_check(String(world.get_fleet("fleet_eng").get("battle_id", "")) == String(world.get_fleet("fleet_bur").get("battle_id", "")), "FLEETS_REFERENCE_DIFFERENT_BATTLES", "both fleets must reference the exact same battle_id, not two independently-formed records")

	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval AI/player battle arbitration test failed: %s" % failure)
		print("Naval AI/player battle arbitration test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval AI/player battle arbitration test passed. days_waited=%d battles=%d" % [days_waited, world.naval_battle_registry.size()])
	quit(0)
