extends SceneTree

## FL3.5: the two escort-lifecycle gaps FL3_3_FL3_5_REINFORCEMENT_HOMEPORT_
## DANGER.md recorded and deliberately left open - "nothing goes looking
## for an escort ahead of departure" and "an escort assigned this way does
## not follow the transport's route once it moves on." Both are now real:
## _plan_transport() proactively reserves an idle same-port fleet as escort
## the moment a transport operation is created, and _consider_escort_follow()
## chases the escorted operation's current zone once they part ways, instead
## of sitting still or being stood down. Transport operations are hand-
## constructed directly (rather than driven through the full embark/sail
## state machine) so each test controls exactly which state/zone the
## operation is in, the same "inject the state, test the one function"
## pattern this pillar's other focused naval-AI tests already use.

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
	return world


func _make_naval_ai(world: CampaignWorldState, events: SimulationEventBus) -> NavalAISystem:
	var scheduler := SimulationSchedulerScript.new(world, events)
	return NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, location_id: int, location_status: String, ship_count: int, definition_id: String = "war_galley") -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, location_id)
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


func _add_sailing_operation(world: CampaignWorldState, operation_id: String, tag: String, current_location_id: int) -> void:
	world.transport_operation_registry[operation_id] = CampaignWorldStateScript.make_transport_operation_record(
		operation_id, tag, "army_%s" % operation_id, "carrier_%s" % operation_id, KENT, PICARDIE, 500, 0, 5
	)
	var operation: Dictionary = world.transport_operation_registry[operation_id]
	operation["state"] = CampaignWorldStateScript.TRANSPORT_STATE_SAILING
	operation["current_location_id"] = current_location_id
	world.transport_operation_registry[operation_id] = operation


func _set_land_target(world: CampaignWorldState, tag: String, target_province_id: int) -> void:
	var runtime := world.country_runtime(tag)
	var ai_state: Dictionary = runtime.get("ai", {})
	ai_state["target_province_id"] = target_province_id
	runtime["ai"] = ai_state
	world.set_country_runtime(tag, runtime)


## Proactive reservation: creating a transport operation must, in the same
## tactical tick, also reserve a second idle same-port fleet as escort -
## not wait for the two to coincidentally share a zone at sea later.
func _test_proactive_escort_reservation() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	world.army_registry["army_kent"] = CampaignWorldStateScript.make_army_record("army_kent", "ENG", KENT)
	world.fleet_registry["fleet_carrier"] = CampaignWorldStateScript.make_fleet_record("fleet_carrier", "ENG", KENT)
	var carrier := world.get_fleet("fleet_carrier")
	carrier["location_id"] = KENT
	carrier["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	world.ship_registry["carrier_ship"] = CampaignWorldStateScript.make_ship_record("carrier_ship", "ENG", "fleet_carrier", "transport_cog", 0)
	carrier["ship_ids"] = ["carrier_ship"]
	world.fleet_registry["fleet_carrier"] = carrier
	FleetSystemScript.recompute_aggregate(world, "fleet_carrier")
	_add_fleet(world, "fleet_escort_candidate", "ENG", KENT, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 2)
	_set_land_target(world, "ENG", PICARDIE)

	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_transport(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(world.transport_operation_registry.size() == 1, "FIXTURE_NO_TRANSPORT_CREATED", "fixture assumption: this scenario must actually create a transport operation")
	_check(String(world.get_fleet("fleet_escort_candidate").get("mission", "")) == "protect_transport", "ESCORT_NOT_PROACTIVELY_RESERVED", "an idle fleet sharing the departure port must be reserved as escort the same tick the transport operation is created: got mission '%s'" % world.get_fleet("fleet_escort_candidate").get("mission", ""))


## Escort follow: a protect_transport fleet no longer sharing a zone with
## its country's sailing operation must chase it, not sit still.
func _test_escort_follows_departed_transport() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_escort", "ENG", KENT, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 2)
	var fleet := world.get_fleet("fleet_escort")
	fleet["mission"] = "protect_transport"
	world.fleet_registry["fleet_escort"] = fleet
	_add_sailing_operation(world, "op_1", "ENG", STRAITS_OF_DOVER)

	var naval_ai := _make_naval_ai(world, events)
	var followed := naval_ai._consider_escort_follow(world, "ENG", "fleet_escort")
	naval_ai.scheduler.process_commands()
	_check(followed, "ESCORT_DID_NOT_FOLLOW", "an escort no longer co-located with its country's sailing transport must be ordered to chase it")
	_check(String(world.get_fleet("fleet_escort").get("location_status", "")) == CampaignWorldStateScript.FLEET_LOCATION_MOVING, "ESCORT_NOT_ACTUALLY_MOVING", "the escort must actually be moving toward the transport's zone, not just recorded as deciding to")


## Control: an escort already sharing a zone with its transport has
## nothing to chase.
func _test_escort_does_not_chase_when_already_co_located() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_escort", "ENG", STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 2)
	var fleet := world.get_fleet("fleet_escort")
	fleet["mission"] = "protect_transport"
	world.fleet_registry["fleet_escort"] = fleet
	_add_sailing_operation(world, "op_1", "ENG", STRAITS_OF_DOVER)

	var naval_ai := _make_naval_ai(world, events)
	_check(not naval_ai._consider_escort_follow(world, "ENG", "fleet_escort"), "ESCORT_CHASED_WHILE_ALREADY_THERE", "an escort already sharing a zone with its transport must not be given a redundant move order")


## Mission completion: a protect_transport fleet must not be abandoned to
## idle just because it currently isn't co-located with its convoy, as
## long as the country still has some sailing operation left to escort -
## _consider_escort_follow() (not mission completion) is responsible for
## closing that gap by actually chasing it.
func _test_mission_completion_survives_temporary_separation() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_escort", "ENG", KENT, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 2)
	var fleet := world.get_fleet("fleet_escort")
	fleet["mission"] = "protect_transport"
	world.fleet_registry["fleet_escort"] = fleet
	_add_sailing_operation(world, "op_1", "ENG", STRAITS_OF_DOVER)

	var naval_ai := _make_naval_ai(world, events)
	_check(not naval_ai._consider_mission_completion(world, "ENG", "fleet_escort"), "ESCORT_ABANDONED_DURING_SEPARATION", "an escort not currently co-located with its transport must not be stood down while the country still has a sailing operation somewhere")
	_check(String(world.get_fleet("fleet_escort").get("mission", "")) == "protect_transport", "MISSION_TAG_CHANGED_DURING_SEPARATION", "the mission tag itself must remain protect_transport during the gap")


func _test_mission_completion_stands_down_once_nothing_left() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_escort", "ENG", KENT, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 2)
	var fleet := world.get_fleet("fleet_escort")
	fleet["mission"] = "protect_transport"
	world.fleet_registry["fleet_escort"] = fleet
	# No transport operations exist at all for ENG - nothing left to escort.

	var naval_ai := _make_naval_ai(world, events)
	var stood_down := naval_ai._consider_mission_completion(world, "ENG", "fleet_escort")
	naval_ai.scheduler.process_commands()
	_check(stood_down, "DID_NOT_STAND_DOWN_WITH_NOTHING_TO_ESCORT", "an escort must stand down to idle once its country has no sailing transport operation left at all")
	_check(String(world.get_fleet("fleet_escort").get("mission", "")) == "idle", "MISSION_TAG_NOT_RESET", "the mission tag must actually change to idle")


func _run() -> void:
	_test_proactive_escort_reservation()
	_test_escort_follows_departed_transport()
	_test_escort_does_not_chase_when_already_co_located()
	_test_mission_completion_survives_temporary_separation()
	_test_mission_completion_stands_down_once_nothing_left()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval AI escort lifecycle test failed: %s" % failure)
		print("Naval AI escort lifecycle test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval AI escort lifecycle test passed. cases=proactive_reservation,follows_departed_transport,no_chase_when_co_located,survives_temporary_separation,stands_down_when_nothing_left")
	quit(0)
