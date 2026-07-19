extends SceneTree

## FL3.2: NavalAISystem's now-full six-posture spectrum (peace, threatened,
## wartime, invasion, recovery, expansion) and the real heavy/light/galley/
## transport construction mix POSTURE_SHIP_MIX_BP now drives, replacing the
## old two-posture/single-ship-type slice. Driven against the same hand-built
## Channel fixture naval_ai_threat_test.gd/naval_ai_transport_test.gd already
## use, for the same reason: precise control over war, debt, threat, and
## overseas-objective state independently of each other.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
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


func _make_world(at_war: bool) -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize({CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR", STRAITS_OF_DOVER: ""}, {"ENG": "England", "BUR": "Burgundy"})
	EconomySystemScript.initialize_world(world)
	if at_war:
		world.war_registry["war_1"] = {
			"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "BUR",
			"attackers": ["ENG"], "defenders": ["BUR"], "battle_score_attacker": 0,
			"war_goal": {"type": "conquer_province", "province_id": PICARDIE, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
		}
	return world


func _make_naval_ai(world: CampaignWorldState, events: SimulationEventBus) -> NavalAISystem:
	var scheduler := SimulationSchedulerScript.new(world, events)
	return NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())


func _set_treasury(world: CampaignWorldState, tag: String, treasury: int, debt: int = 0, balance: int = 0) -> void:
	var runtime := world.country_runtime(tag)
	runtime["treasury"] = treasury
	runtime["debt"] = debt
	var ledger: Dictionary = runtime.get("ledger", {})
	ledger["balance"] = balance
	ledger["total_expenses"] = 0
	runtime["ledger"] = ledger
	world.set_country_runtime(tag, runtime)


func _set_land_target(world: CampaignWorldState, tag: String, target_province_id: int) -> void:
	var runtime := world.country_runtime(tag)
	var ai_state: Dictionary = runtime.get("ai", {})
	ai_state["target_province_id"] = target_province_id
	runtime["ai"] = ai_state
	world.set_country_runtime(tag, runtime)


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


func _test_peace() -> void:
	var world := _make_world(false)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 20000)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._review_posture(world, "ENG", AIDefinitionsScript.load_default().profile("ENG"))
	var state: Dictionary = world.country_runtime("ENG").get("naval_ai", {})
	_check(String(state.get("posture", "")) == "peace", "PEACE_WRONG_POSTURE", "no war, no debt, modest treasury, no threat must be 'peace', got '%s'" % state.get("posture", ""))
	_check(int(state.get("desired_ship_count", -1)) == 2, "PEACE_DESIRED_COUNT_WRONG", "2 ports at the peacetime x1 multiplier must be 2, got %d" % state.get("desired_ship_count", -1))


func _test_expansion() -> void:
	var world := _make_world(false)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 10000000)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._review_posture(world, "ENG", AIDefinitionsScript.load_default().profile("ENG"))
	var state: Dictionary = world.country_runtime("ENG").get("naval_ai", {})
	_check(String(state.get("posture", "")) == "expansion", "EXPANSION_WRONG_POSTURE", "a treasury comfortably above reserve with no war or debt must be 'expansion', got '%s'" % state.get("posture", ""))
	_check(int(state.get("desired_ship_count", -1)) == 4, "EXPANSION_DESIRED_COUNT_WRONG", "2 ports at the ambitious x2 multiplier must be 4, got %d" % state.get("desired_ship_count", -1))


func _test_threatened() -> void:
	var world := _make_world(false)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 20000)
	# Pre-war tension, not a declared war - "threatened" must fire from
	# rivalry alone, since NavalThreatMap's own hostile_power is deliberately
	# war-gated (see _country_rival_power()'s own doc comment for why).
	DiplomacySystemScript.set_relation(world, "ENG", "BUR", {"rivalry": true})
	_add_fleet(world, "fleet_bur_threat", "BUR", PICARDIE, STRAITS_OF_DOVER, 6)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._review_posture(world, "ENG", AIDefinitionsScript.load_default().profile("ENG"))
	var state: Dictionary = world.country_runtime("ENG").get("naval_ai", {})
	_check(String(state.get("posture", "")) == "threatened", "THREATENED_WRONG_POSTURE", "hostile power staged right off an owned port, no war yet, must be 'threatened', got '%s'" % state.get("posture", ""))


func _test_wartime() -> void:
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 60000)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._review_posture(world, "ENG", AIDefinitionsScript.load_default().profile("ENG"))
	var state: Dictionary = world.country_runtime("ENG").get("naval_ai", {})
	_check(String(state.get("posture", "")) == "wartime", "WARTIME_WRONG_POSTURE", "at war with no active overseas objective must be 'wartime', got '%s'" % state.get("posture", ""))


func _test_invasion() -> void:
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 60000)
	_set_land_target(world, "ENG", PICARDIE)
	var naval_ai := _make_naval_ai(world, events)
	_check(naval_ai._overseas_objective_landing(world, "ENG") >= 0, "INVASION_FIXTURE_UNREACHABLE", "fixture assumption: Picardie must be reachable via a legal beachhead")
	naval_ai._review_posture(world, "ENG", AIDefinitionsScript.load_default().profile("ENG"))
	var state: Dictionary = world.country_runtime("ENG").get("naval_ai", {})
	_check(String(state.get("posture", "")) == "invasion", "INVASION_WRONG_POSTURE", "at war with a live, sea-reachable overseas objective must be 'invasion', got '%s'" % state.get("posture", ""))


func _test_recovery_and_precedence() -> void:
	# Debt alone, no war: recovery.
	var world_a := _make_world(false)
	var events_a := SimulationEventBusScript.new()
	root.add_child(events_a)
	_set_treasury(world_a, "ENG", 60000, 5000, 0)
	var naval_ai_a := _make_naval_ai(world_a, events_a)
	naval_ai_a._review_posture(world_a, "ENG", AIDefinitionsScript.load_default().profile("ENG"))
	var state_a: Dictionary = world_a.country_runtime("ENG").get("naval_ai", {})
	_check(String(state_a.get("posture", "")) == "recovery", "RECOVERY_WRONG_POSTURE", "outstanding debt with no war must be 'recovery', got '%s'" % state_a.get("posture", ""))
	_check(int(state_a.get("desired_ship_count", -1)) == 2, "RECOVERY_DESIRED_COUNT_WRONG", "recovery must stay at the frozen peacetime x1 multiplier (2), got %d" % state_a.get("desired_ship_count", -1))

	# Negative ledger balance alone (no formal debt yet): also recovery.
	var world_b := _make_world(false)
	var events_b := SimulationEventBusScript.new()
	root.add_child(events_b)
	_set_treasury(world_b, "ENG", 60000, 0, -500)
	var naval_ai_b := _make_naval_ai(world_b, events_b)
	naval_ai_b._review_posture(world_b, "ENG", AIDefinitionsScript.load_default().profile("ENG"))
	var state_b: Dictionary = world_b.country_runtime("ENG").get("naval_ai", {})
	_check(String(state_b.get("posture", "")) == "recovery", "NEGATIVE_BALANCE_NOT_RECOVERY", "a negative ledger balance alone must also trigger 'recovery', got '%s'" % state_b.get("posture", ""))

	# Precedence: war must win over debt, matching StrategicAISystem's own
	# "war beats debt" branch order - a country at war and in debt is still
	# fighting a war, not quietly recovering.
	var world_c := _make_world(true)
	var events_c := SimulationEventBusScript.new()
	root.add_child(events_c)
	_set_treasury(world_c, "ENG", 60000, 5000, 0)
	var naval_ai_c := _make_naval_ai(world_c, events_c)
	naval_ai_c._review_posture(world_c, "ENG", AIDefinitionsScript.load_default().profile("ENG"))
	var state_c: Dictionary = world_c.country_runtime("ENG").get("naval_ai", {})
	_check(String(state_c.get("posture", "")) == "wartime", "WAR_DID_NOT_BEAT_DEBT", "war must take precedence over debt, got '%s'" % state_c.get("posture", ""))


func _test_construction_mix_and_sailor_reserve() -> void:
	var ship_definitions := ShipDefinitionsScript.load_default()
	# The mix table itself: every posture's basis-point row must sum to
	# 10000, and invasion must weight transport meaningfully higher than
	# peace does - the whole point of that posture.
	for posture in NavalAISystemScript.POSTURE_SHIP_MIX_BP:
		var row: Dictionary = NavalAISystemScript.POSTURE_SHIP_MIX_BP[posture]
		var total := 0
		for family in row:
			total += int(row[family])
		_check(total == 10000, "MIX_ROW_NOT_10000", "posture '%s' mix must sum to 10000bp, got %d" % [posture, total])
	var invasion_transport := int((NavalAISystemScript.POSTURE_SHIP_MIX_BP["invasion"] as Dictionary)["transport"])
	var peace_transport := int((NavalAISystemScript.POSTURE_SHIP_MIX_BP["peace"] as Dictionary)["transport"])
	_check(invasion_transport > peace_transport, "INVASION_NOT_TRANSPORT_HEAVY", "invasion posture must weight transport higher than peace, got %d vs %d" % [invasion_transport, peace_transport])

	# Real construction from an empty fleet under "wartime" (heavy is the
	# unambiguous highest-weighted family) must actually build a heavy ship.
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 5000000, 0, 0)
	var runtime := world.country_runtime("ENG")
	runtime["sailors"] = 5000
	world.set_country_runtime("ENG", runtime)
	var naval_ai := _make_naval_ai(world, events)
	var profile := AIDefinitionsScript.load_default().profile("ENG")
	naval_ai._review_posture(world, "ENG", profile)
	var posture := String((world.country_runtime("ENG").get("naval_ai", {}) as Dictionary).get("posture", ""))
	_check(posture == "wartime", "CONSTRUCTION_FIXTURE_WRONG_POSTURE", "fixture assumption: this scenario must resolve to 'wartime', got '%s'" % posture)
	naval_ai._plan_construction(world, "ENG", profile)
	naval_ai.scheduler.process_commands()
	_check(world.naval_construction_registry.size() == 1, "CONSTRUCTION_NOT_QUEUED", "a well-funded wartime England must queue exactly one construction")
	if world.naval_construction_registry.size() == 1:
		var record: Dictionary = world.naval_construction_registry.values()[0]
		var family := String(ship_definitions.ship(String(record.get("definition_id", ""))).get("family", ""))
		_check(family == "heavy", "WARTIME_DID_NOT_BUILD_HEAVY", "wartime's highest-weighted family is heavy, got '%s'" % family)

	# Sailor reserve: generous treasury but too few sailors for even the
	# cheapest ship in the target family must be proactively rejected, not
	# silently deferred to ConstructShipCommand.validate().
	var world_b := _make_world(true)
	var events_b := SimulationEventBusScript.new()
	root.add_child(events_b)
	_set_treasury(world_b, "ENG", 5000000, 0, 0)
	var runtime_b := world_b.country_runtime("ENG")
	runtime_b["sailors"] = 1
	world_b.set_country_runtime("ENG", runtime_b)
	var naval_ai_b := _make_naval_ai(world_b, events_b)
	var profile_b := AIDefinitionsScript.load_default().profile("ENG")
	naval_ai_b._review_posture(world_b, "ENG", profile_b)
	naval_ai_b._plan_construction(world_b, "ENG", profile_b)
	naval_ai_b.scheduler.process_commands()
	_check(world_b.naval_construction_registry.is_empty(), "SAILOR_RESERVE_NOT_RESPECTED", "one sailor cannot crew any real ship - construction must be rejected, not queued")
	var snapshot_b := naval_ai_b.debug_snapshot(world_b, "ENG")
	_check(String((snapshot_b["last_decision"] as Dictionary).get("action", "")) == "insufficient_sailors", "SAILOR_REJECTION_NOT_RECORDED", "the rejection must be explained as insufficient_sailors, got '%s'" % (snapshot_b["last_decision"] as Dictionary).get("action", ""))


func _run() -> void:
	_test_peace()
	_test_expansion()
	_test_threatened()
	_test_wartime()
	_test_invasion()
	_test_recovery_and_precedence()
	_test_construction_mix_and_sailor_reserve()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval AI strategic posture test failed: %s" % failure)
		print("Naval AI strategic posture test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval AI strategic posture test passed. cases=peace,expansion,threatened,wartime,invasion,recovery,precedence,mix,sailor_reserve")
	quit(0)
