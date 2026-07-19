extends SceneTree

## FL3.3/FL3.5: three more real NavalAISystem behaviors added after FL3.4 -
## reinforcement (_consider_reinforcement()), home-port reassignment on
## access loss (_consider_home_port()), and danger-aware transport routing
## (_route_too_dangerous()). Driven against the same hand-built Channel
## fixture the other naval-AI tests already use, for the same reason:
## precise control over exactly which fleets, wars, and ownership are
## present where.

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

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, code: String, detail: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [code, detail])


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize({CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR", STRAITS_OF_DOVER: ""}, {"ENG": "England", "BUR": "Burgundy"})
	world.war_registry["war_1"] = {
		"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "BUR",
		"attackers": ["ENG"], "defenders": ["BUR"], "battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": PICARDIE, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
	}
	return world


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, home_port_id: int, location_id: int, location_status: String, ship_count: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, home_port_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = location_status
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


func _test_reinforcement_when_weaker() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng_engaged", "ENG", CALAIS, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 1)
	_add_fleet(world, "fleet_bur_engaged", "BUR", PICARDIE, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 5)
	var engaged_eng := world.get_fleet("fleet_eng_engaged")
	engaged_eng["battle_id"] = "battle_1"
	world.fleet_registry["fleet_eng_engaged"] = engaged_eng
	var engaged_bur := world.get_fleet("fleet_bur_engaged")
	engaged_bur["battle_id"] = "battle_1"
	world.fleet_registry["fleet_bur_engaged"] = engaged_bur
	var battle := CampaignWorldStateScript.make_naval_battle_record("battle_1", "war_1", STRAITS_OF_DOVER, world.current_day)
	battle["attacker_fleets"] = ["fleet_eng_engaged"]
	battle["defender_fleets"] = ["fleet_bur_engaged"]
	world.naval_battle_registry["battle_1"] = battle
	_add_fleet(world, "fleet_eng_reserve", "ENG", CALAIS, CALAIS, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 3)

	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_tactical(world, "ENG")
	naval_ai.scheduler.process_commands()
	var reserve := world.get_fleet("fleet_eng_reserve")
	_check(String(reserve.get("location_status", "")) == CampaignWorldStateScript.FLEET_LOCATION_MOVING, "REINFORCEMENT_NOT_ORDERED", "a docked reserve fleet must be ordered to reinforce an active battle its own side is losing, got location_status '%s'" % reserve.get("location_status", ""))
	_check((reserve.get("remaining_path", []) as Array).has(STRAITS_OF_DOVER) or int(reserve.get("destination_id", -1)) == STRAITS_OF_DOVER, "REINFORCEMENT_WRONG_DESTINATION", "the reserve fleet must be routed toward the battle's own zone")


func _test_no_reinforcement_when_not_weaker() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng_engaged_b", "ENG", CALAIS, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 5)
	_add_fleet(world, "fleet_bur_engaged_b", "BUR", PICARDIE, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 1)
	var engaged_eng := world.get_fleet("fleet_eng_engaged_b")
	engaged_eng["battle_id"] = "battle_2"
	world.fleet_registry["fleet_eng_engaged_b"] = engaged_eng
	var engaged_bur := world.get_fleet("fleet_bur_engaged_b")
	engaged_bur["battle_id"] = "battle_2"
	world.fleet_registry["fleet_bur_engaged_b"] = engaged_bur
	var battle := CampaignWorldStateScript.make_naval_battle_record("battle_2", "war_1", STRAITS_OF_DOVER, world.current_day)
	battle["attacker_fleets"] = ["fleet_eng_engaged_b"]
	battle["defender_fleets"] = ["fleet_bur_engaged_b"]
	world.naval_battle_registry["battle_2"] = battle
	_add_fleet(world, "fleet_eng_reserve_b", "ENG", CALAIS, CALAIS, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 3)

	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_tactical(world, "ENG")
	naval_ai.scheduler.process_commands()
	var reserve := world.get_fleet("fleet_eng_reserve_b")
	_check(String(reserve.get("location_status", "")) == CampaignWorldStateScript.FLEET_LOCATION_DOCKED, "REINFORCEMENT_SENT_WHEN_ALREADY_WINNING", "a reserve fleet must not be sent to reinforce a side that is already stronger, got location_status '%s'" % reserve.get("location_status", ""))


func _test_home_port_reassigned_on_access_loss() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng_displaced", "ENG", CALAIS, KENT, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 2)
	world.set_province_owner(CALAIS, "BUR")
	world.set_province_controller(CALAIS, "BUR")
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_organisation(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(int(world.get_fleet("fleet_eng_displaced")["home_port_id"]) == KENT, "HOME_PORT_NOT_REASSIGNED", "a fleet whose home port lost basing rights must be reassigned to a still-owned port, got %d" % int(world.get_fleet("fleet_eng_displaced")["home_port_id"]))


func _test_home_port_left_alone_when_still_legal() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng_settled", "ENG", CALAIS, KENT, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 2)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_organisation(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(int(world.get_fleet("fleet_eng_settled")["home_port_id"]) == CALAIS, "HOME_PORT_CHANGED_UNNECESSARILY", "a fleet whose home port is still legally basable must not be reassigned")


func _test_transport_avoids_dangerous_route() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	world.army_registry["army_kent"] = CampaignWorldStateScript.make_army_record("army_kent", "ENG", KENT)
	world.fleet_registry["fleet_kent"] = CampaignWorldStateScript.make_fleet_record("fleet_kent", "ENG", KENT)
	world.ship_registry["fleet_kent_transport"] = CampaignWorldStateScript.make_ship_record("fleet_kent_transport", "ENG", "fleet_kent", "transport_cog", 0)
	var kent_fleet := world.get_fleet("fleet_kent")
	kent_fleet["location_id"] = KENT
	kent_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	kent_fleet["ship_ids"] = ["fleet_kent_transport"]
	world.fleet_registry["fleet_kent"] = kent_fleet
	FleetSystemScript.recompute_aggregate(world, "fleet_kent")
	var runtime := world.country_runtime("ENG")
	var ai_state: Dictionary = runtime.get("ai", {})
	ai_state["target_province_id"] = PICARDIE
	runtime["ai"] = ai_state
	world.set_country_runtime("ENG", runtime)
	# A strong hostile fleet squarely on the only legal Kent -> Calais route.
	_add_fleet(world, "fleet_bur_blocker", "BUR", PICARDIE, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 8)

	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_transport(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(world.transport_operation_registry.is_empty(), "TRANSPORT_SAILED_THROUGH_DANGER", "a transport must not be created when its only legal route passes through a zone the AI itself would call dangerous")


func _run() -> void:
	_test_reinforcement_when_weaker()
	_test_no_reinforcement_when_not_weaker()
	_test_home_port_reassigned_on_access_loss()
	_test_home_port_left_alone_when_still_legal()
	_test_transport_avoids_dangerous_route()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval AI reinforcement/home-port/transport test failed: %s" % failure)
		print("Naval AI reinforcement/home-port/transport test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval AI reinforcement/home-port/transport test passed. cases=reinforcement_weaker,reinforcement_not_weaker,home_port_reassigned,home_port_unchanged,transport_avoids_danger")
	quit(0)
