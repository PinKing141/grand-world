extends SceneTree

## FL3.4: NavalAISystem's four newly real tactical missions - escort
## (protect_transport), intercept, protect_coast, and patrol - plus
## _consider_mission_completion(), the "stand down once the reason no
## longer applies" half none of these four missions get for free from the
## simulation layer (unlike blockade/return_to_port/repair, which
## FleetMissionSystem itself resolves). Driven against the same hand-built
## Channel fixture naval_ai_threat_test.gd/naval_ai_transport_test.gd
## already use, for the same reason: precise control over exactly which
## transport operations, wars, and fleets are present in which zone.

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
# Kent's other real sea-zone exit (confirmed against the live maritime
# graph): its only land neighbour is Kent itself, with no hostile-owned
# coastal province nearby - unlike the Straits (Picardie-adjacent), a
# hostile fleet staged here threatens home coastline with no blockade
# target of its own, the clean case protect_coast needs to be distinguished
# from blockade.
const KENT_COASTAL_ZONE := 1270

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_world(at_war: bool) -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize({CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR", STRAITS_OF_DOVER: ""}, {"ENG": "England", "BUR": "Burgundy"})
	if at_war:
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


func _add_transport_operation(world: CampaignWorldState, operation_id: String, country_tag: String, zone_id: int) -> void:
	world.transport_operation_registry[operation_id] = CampaignWorldStateScript.make_transport_operation_record(operation_id, country_tag, "army_%s" % operation_id, "fleet_%s" % operation_id, CALAIS, KENT, 500, world.current_day, world.current_day + 2)
	var operation := world.get_transport_operation(operation_id)
	operation["state"] = CampaignWorldStateScript.TRANSPORT_STATE_SAILING
	operation["current_location_id"] = zone_id
	world.transport_operation_registry[operation_id] = operation


func _make_naval_ai(world: CampaignWorldState, events: SimulationEventBus) -> NavalAISystem:
	var scheduler := SimulationSchedulerScript.new(world, events)
	return NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())


func _test_escort() -> void:
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng_guard", "ENG", CALAIS, STRAITS_OF_DOVER, 3)
	_add_transport_operation(world, "op_friendly", "ENG", STRAITS_OF_DOVER)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_tactical(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(String(world.get_fleet("fleet_eng_guard")["mission"]) == "protect_transport", "ESCORT_NOT_ASSIGNED", "an idle warship sharing a zone with its own sailing transport must escort it, got '%s'" % world.get_fleet("fleet_eng_guard")["mission"])


func _test_intercept() -> void:
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng_hunter", "ENG", CALAIS, STRAITS_OF_DOVER, 3)
	_add_transport_operation(world, "op_hostile", "BUR", STRAITS_OF_DOVER)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_tactical(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(String(world.get_fleet("fleet_eng_hunter")["mission"]) == "intercept", "INTERCEPT_NOT_ASSIGNED", "an idle warship sharing a zone with a hostile sailing transport must intercept it, got '%s'" % world.get_fleet("fleet_eng_hunter")["mission"])

	# Control: an ally's transport operation in the same zone must never be
	# intercepted - only a hostile one.
	var world_b := _make_world(false)
	var events_b := SimulationEventBusScript.new()
	root.add_child(events_b)
	_add_fleet(world_b, "fleet_eng_calm", "ENG", CALAIS, STRAITS_OF_DOVER, 3)
	_add_transport_operation(world_b, "op_neutral", "BUR", STRAITS_OF_DOVER)
	var naval_ai_b := _make_naval_ai(world_b, events_b)
	naval_ai_b._plan_tactical(world_b, "ENG")
	naval_ai_b.scheduler.process_commands()
	_check(String(world_b.get_fleet("fleet_eng_calm")["mission"]) != "intercept", "INTERCEPT_WITHOUT_WAR", "a transport from a country not at war must never be intercepted, got '%s'" % world_b.get_fleet("fleet_eng_calm")["mission"])


func _test_patrol() -> void:
	var world := _make_world(false)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng_patrol", "ENG", CALAIS, STRAITS_OF_DOVER, 2)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_tactical(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(String(world.get_fleet("fleet_eng_patrol")["mission"]) == "patrol", "PATROL_NOT_ASSIGNED", "an idle warship in a safe zone with nothing else to do must patrol, got '%s'" % world.get_fleet("fleet_eng_patrol")["mission"])


func _test_protect_coast() -> void:
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	# Threat_score nets hostile power against friendly power already present
	# (the fleet being evaluated counts as its own friendly_power) - a
	# modestly stronger hostile fleet is needed for a positive threat_score
	# at all, but not so much stronger that evade fires instead of
	# protect_coast (own power must stay within EVADE_POWER_RATIO_BP of the
	# *net* threat_score, not the raw hostile total).
	_add_fleet(world, "fleet_eng_coast", "ENG", KENT, KENT_COASTAL_ZONE, 3)
	_add_fleet(world, "fleet_bur_raider", "BUR", PICARDIE, KENT_COASTAL_ZONE, 4)
	var naval_ai := _make_naval_ai(world, events)
	_check(not bool(naval_ai.threat_map.assess(world, "ENG", KENT_COASTAL_ZONE, naval_ai.graph)["has_blockade_target"]), "PROTECT_COAST_FIXTURE_HAS_BLOCKADE_TARGET", "fixture assumption: Kent's coastal zone must offer no blockade target, to isolate protect_coast from blockade")
	naval_ai._plan_tactical(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(String(world.get_fleet("fleet_eng_coast")["mission"]) == "protect_coast", "PROTECT_COAST_NOT_ASSIGNED", "hostile power near owned coastline with no blockade target must trigger protect_coast, got '%s'" % world.get_fleet("fleet_eng_coast")["mission"])


func _test_mission_completion() -> void:
	# Escort stands down once the transport operation it was guarding is
	# gone (completed, cancelled, or lost) - not left stuck on
	# protect_transport forever.
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng_escort", "ENG", CALAIS, STRAITS_OF_DOVER, 3)
	var fleet := world.get_fleet("fleet_eng_escort")
	fleet["mission"] = "protect_transport"
	world.fleet_registry["fleet_eng_escort"] = fleet
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_tactical(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(String(world.get_fleet("fleet_eng_escort")["mission"]) == "idle", "ESCORT_NOT_STOOD_DOWN", "escort must stand down to idle once no friendly transport remains in the zone, got '%s'" % world.get_fleet("fleet_eng_escort")["mission"])

	# Escort stands down and immediately gets to keep escorting is NOT
	# expected in one tick (one command per tick) - but while a real
	# operation is still present, mission_completion must not touch it.
	var world_b := _make_world(true)
	var events_b := SimulationEventBusScript.new()
	root.add_child(events_b)
	_add_fleet(world_b, "fleet_eng_still_escorting", "ENG", CALAIS, STRAITS_OF_DOVER, 3)
	var fleet_b := world_b.get_fleet("fleet_eng_still_escorting")
	fleet_b["mission"] = "protect_transport"
	world_b.fleet_registry["fleet_eng_still_escorting"] = fleet_b
	_add_transport_operation(world_b, "op_still_here", "ENG", STRAITS_OF_DOVER)
	var naval_ai_b := _make_naval_ai(world_b, events_b)
	naval_ai_b._plan_tactical(world_b, "ENG")
	naval_ai_b.scheduler.process_commands()
	_check(String(world_b.get_fleet("fleet_eng_still_escorting")["mission"]) == "protect_transport", "ESCORT_STOOD_DOWN_TOO_EARLY", "escort must not be reset while the transport it is guarding is still there, got '%s'" % world_b.get_fleet("fleet_eng_still_escorting")["mission"])


func _run() -> void:
	_test_escort()
	_test_intercept()
	_test_protect_coast()
	_test_patrol()
	_test_mission_completion()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval AI tactical missions test failed: %s" % failure)
		print("Naval AI tactical missions test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval AI tactical missions test passed. cases=escort,intercept,protect_coast,patrol,mission_completion")
	quit(0)
