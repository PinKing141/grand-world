extends SceneTree

## N6A continuation: NavalAISystem's sea-zone threat query and the two
## tactical decisions it now backs - evade a zone this country cannot
## safely cover, and take up blockade duty in one that is safe and has a
## reachable war target. Driven directly against a lightweight hand-built
## Channel fixture (the same CALAIS/KENT/PICARDIE/STRAITS_OF_DOVER shape
## naval_combat_test.gd and others already use) rather than the full Iberian
## AI fixture, for precise control over exactly how much enemy power is
## present - naval_ai_test.gd already proves the staggered-schedule/
## explainable-trace/determinism contract against the real fixture; this
## proves the threat query's own two decisions in isolation.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval AI threat test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize({CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR", STRAITS_OF_DOVER: ""}, {"ENG": "England", "BUR": "Burgundy"})
	world.war_registry["war_1"] = {
		"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "BUR",
		"attackers": ["ENG"], "defenders": ["BUR"], "battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": PICARDIE, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
	}
	return world


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, home_port_id: int, location_id: int, ship_count: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, home_port_id)
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


func _make_naval_ai(world: CampaignWorldState, events: SimulationEventBus) -> NavalAISystem:
	var scheduler := SimulationSchedulerScript.new(world, events)
	return NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())


func _run() -> void:
	# --- Evasion: a lone England ship shares the Straits of Dover directly
	# with an overwhelming Burgundian fleet - too dangerous to stay. ---
	var world_a := _make_world()
	var events_a := SimulationEventBusScript.new()
	root.add_child(events_a)
	_add_fleet(world_a, "fleet_eng_weak", "ENG", CALAIS, STRAITS_OF_DOVER, 1)
	_add_fleet(world_a, "fleet_bur_strong", "BUR", PICARDIE, STRAITS_OF_DOVER, 10)
	var naval_ai_a := _make_naval_ai(world_a, events_a)
	var threat_a := naval_ai_a._zone_threat(world_a, "ENG", STRAITS_OF_DOVER)
	_require(threat_a > 0, "fixture assumption: a directly co-located hostile fleet must register real threat")
	naval_ai_a._plan_tactical(world_a, "ENG")
	naval_ai_a.scheduler.process_commands()
	_require(String(world_a.get_fleet("fleet_eng_weak")["mission"]) == "return_to_port", "an outmatched fleet in a dangerous zone must evade toward port")
	var snapshot_a := naval_ai_a.debug_snapshot(world_a, "ENG")
	_require(String((snapshot_a["last_decision"] as Dictionary).get("reason", "")).contains("Evade"), "the evasion decision must be explained")

	# --- Blockade assignment: an equally-sized England fleet alone at the
	# Straits, at war with Burgundy, which owns the adjacent coastal
	# province Picardie - no threat, a real target, must take up blockade
	# duty rather than sit idle. ---
	var world_b := _make_world()
	var events_b := SimulationEventBusScript.new()
	root.add_child(events_b)
	_add_fleet(world_b, "fleet_eng_alone", "ENG", CALAIS, STRAITS_OF_DOVER, 2)
	var naval_ai_b := _make_naval_ai(world_b, events_b)
	_require(naval_ai_b._zone_threat(world_b, "ENG", STRAITS_OF_DOVER) == 0, "fixture assumption: no hostile fleet anywhere means zero threat")
	_require(naval_ai_b._zone_has_blockade_target(world_b, STRAITS_OF_DOVER, "ENG"), "fixture assumption: Picardie (Burgundy, at war) must be a reachable blockade target from the Straits")
	naval_ai_b._plan_tactical(world_b, "ENG")
	naval_ai_b.scheduler.process_commands()
	_require(String(world_b.get_fleet("fleet_eng_alone")["mission"]) == "blockade", "a safe fleet with a reachable war target must be assigned blockade duty")

	# --- Peacetime control: the same safe, alone fleet with no war at all
	# must not be assigned blockade duty - there is nothing to blockade.
	# FL3.4: it is no longer expected to stay "idle" either - a safe zone
	# with nothing more urgent to do is exactly patrol's own real trigger
	# (tests/naval_ai_tactical_missions_test.gd covers patrol directly). ---
	var world_c := _make_world()
	var events_c := SimulationEventBusScript.new()
	root.add_child(events_c)
	world_c.war_registry.clear()
	_add_fleet(world_c, "fleet_eng_peace", "ENG", CALAIS, STRAITS_OF_DOVER, 2)
	var naval_ai_c := _make_naval_ai(world_c, events_c)
	naval_ai_c._plan_tactical(world_c, "ENG")
	naval_ai_c.scheduler.process_commands()
	_require(String(world_c.get_fleet("fleet_eng_peace")["mission"]) != "blockade", "a fleet with no war must never be assigned blockade duty")

	print("Naval AI threat test passed. threat_at_straits=%d" % threat_a)
	quit(0)
