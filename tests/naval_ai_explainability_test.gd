extends SceneTree

## FL3.6: NavalAISystem's decision records now carry the roadmap's own named
## structured fields (targets, constraints, posture, next_planning_day), not
## just free text buried in `reason`, and a new naval_ai_candidates_evaluated
## global counter distinguishes "a concrete command candidate was built and
## either accepted or rejected" from a pure bookkeeping "nothing to do"
## decision like fleet_sufficient/hold_stations. Reuses the exact Channel
## fixture pattern naval_ai_strategic_posture_test.gd already established.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const AssignAdmiralCommandScript = preload("res://scripts/simulation/commands/assign_admiral_command.gd")

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


func _test_posture_structured_fields() -> void:
	var world := _make_world(false)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 20000)
	var naval_ai := _make_naval_ai(world, events)
	var profile := AIDefinitionsScript.load_default().profile("ENG")
	world.current_day = int(profile.get("slot", 0))
	naval_ai._review_posture(world, "ENG", profile)
	var last_decision: Dictionary = naval_ai.debug_snapshot(world, "ENG")["last_decision"]
	_check(String(last_decision.get("posture", "")) == "peace", "POSTURE_FIELD_MISSING", "the decision record's own posture field must match the classification just made: got '%s'" % last_decision.get("posture", ""))
	_check((last_decision.get("targets", null) is Array) and (last_decision["targets"] as Array).is_empty(), "POSTURE_TARGETS_WRONG", "a country-wide posture review has no single fleet/province target, so targets must be present and empty")
	var constraints: Dictionary = last_decision.get("constraints", {})
	_check(int(constraints.get("treasury", -1)) == 20000, "POSTURE_CONSTRAINTS_MISSING_TREASURY", "constraints must record the actual treasury value that gated the branch: got %s" % constraints)
	_check(constraints.has("reserve") and constraints.has("at_war") and constraints.has("in_debt"), "POSTURE_CONSTRAINTS_INCOMPLETE", "constraints must record reserve/at_war/in_debt, the values that actually decided the posture branch: got %s" % constraints)
	_check(bool(constraints.get("at_war", true)) == false, "POSTURE_CONSTRAINTS_WRONG_AT_WAR", "this fixture has no war, so at_war must record false: got %s" % constraints)
	var expected_next := naval_ai._next_due_day(world.current_day, NavalAISystemScript.POSTURE_INTERVAL, int(profile.get("slot", 0)))
	_check(int(last_decision.get("next_planning_day", -1)) == expected_next, "POSTURE_NEXT_PLANNING_DAY_WRONG", "the decision record's own next_planning_day must match the same _next_due_day() calculation debug_snapshot() already trusts: expected %d got %s" % [expected_next, last_decision.get("next_planning_day")])


func _test_tactical_targets_include_fleet() -> void:
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_eng", "ENG", CALAIS, STRAITS_OF_DOVER, 3)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._consider_blockade_or_evade(world, "ENG", "fleet_eng")
	var last_decision: Dictionary = naval_ai.debug_snapshot(world, "ENG")["last_decision"]
	var targets: Array = last_decision.get("targets", [])
	_check(targets.has("fleet_eng"), "TACTICAL_TARGETS_MISSING_FLEET", "a tactical decision about one specific fleet must list that fleet's ID in targets: got %s" % [targets])
	_check(targets.has(STRAITS_OF_DOVER), "TACTICAL_TARGETS_MISSING_ZONE", "the decision must also record which zone it concerned: got %s" % [targets])


func _test_candidates_evaluated_counter() -> void:
	# Bookkeeping ("nothing to do") decisions must not inflate the counter.
	var world_none := _make_world(false)
	var events_none := SimulationEventBusScript.new()
	root.add_child(events_none)
	_set_treasury(world_none, "ENG", 20000)
	var naval_ai_none := _make_naval_ai(world_none, events_none)
	var profile_none := AIDefinitionsScript.load_default().profile("ENG")
	# Pre-set navy maintenance to the peacetime rate _review_posture() would
	# itself pick, so its own new _consider_navy_maintenance() step finds
	# nothing to change and this fixture stays isolated to pure posture
	# bookkeeping - otherwise a real, freshly-added SetNavyMaintenanceCommand
	# would legitimately fire and evaluate as a real candidate here too.
	var runtime_none := world_none.country_runtime("ENG")
	runtime_none["navy_maintenance_bp"] = int(profile_none.get("peace_maintenance_bp", 5000))
	world_none.set_country_runtime("ENG", runtime_none)
	naval_ai_none._review_posture(world_none, "ENG", profile_none)
	_check(int(world_none.global_counters.get("naval_ai_candidates_evaluated", 0)) == 0, "POSTURE_BUMPED_CANDIDATES", "a pure posture-classification bookkeeping record must not count as an evaluated candidate")

	# An accepted candidate (a real command actually submitted) bumps both
	# naval_ai_commands_submitted and naval_ai_candidates_evaluated by one.
	var world_accept := _make_world(true)
	var events_accept := SimulationEventBusScript.new()
	root.add_child(events_accept)
	_set_treasury(world_accept, "ENG", 5000000, 0, 0)
	var runtime_accept := world_accept.country_runtime("ENG")
	runtime_accept["sailors"] = 1000000
	world_accept.set_country_runtime("ENG", runtime_accept)
	var naval_ai_accept := _make_naval_ai(world_accept, events_accept)
	var profile_accept := AIDefinitionsScript.load_default().profile("ENG")
	naval_ai_accept._review_posture(world_accept, "ENG", profile_accept)
	naval_ai_accept._plan_construction(world_accept, "ENG", profile_accept)
	naval_ai_accept.scheduler.process_commands()
	_check(world_accept.naval_construction_registry.size() == 1, "ACCEPT_FIXTURE_DID_NOT_QUEUE", "fixture assumption: a well-funded, well-crewed wartime England must queue a real construction")
	_check(int(world_accept.global_counters.get("naval_ai_candidates_evaluated", 0)) == 1, "ACCEPTED_CANDIDATE_NOT_COUNTED", "an accepted command candidate must count as exactly one evaluated candidate: got %s" % world_accept.global_counters.get("naval_ai_candidates_evaluated", 0))
	_check(int(world_accept.global_counters.get("naval_ai_commands_submitted", 0)) == 1, "ACCEPT_FIXTURE_COMMANDS_SUBMITTED_WRONG", "fixture assumption: exactly one command must have been submitted")

	# A rejected candidate (a real command built, then found illegal) also
	# bumps naval_ai_candidates_evaluated by one, but never naval_ai_commands_submitted.
	var world_reject := _make_world(true)
	var events_reject := SimulationEventBusScript.new()
	root.add_child(events_reject)
	_add_fleet(world_reject, "fleet_eng_a", "ENG", CALAIS, CALAIS, 3)
	var fleet_a := world_reject.get_fleet("fleet_eng_a")
	fleet_a["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	world_reject.fleet_registry["fleet_eng_a"] = fleet_a
	var naval_ai_reject := _make_naval_ai(world_reject, events_reject)
	# A real command candidate that is concretely rejected: the first
	# assignment (issued by ENG, who owns the fleet) is accepted; a second
	# attempt issued by BUR - who does not own fleet_eng_a - fails
	# AssignAdmiralCommand.validate()'s own ownership check, exercising
	# _submit()'s own failure path with a genuine, constructed command
	# object, not a synthetic rejection.
	var character_id := CharacterSystemScript._create_courtier(world_reject, events_reject, "ENG", "male")
	var command := AssignAdmiralCommandScript.new("ENG", "fleet_eng_a", character_id)
	naval_ai_reject._submit(world_reject, "ENG", "organisation", command, 70, "test assignment", [])
	var bad_command := AssignAdmiralCommandScript.new("BUR", "fleet_eng_a", character_id)
	naval_ai_reject._submit(world_reject, "ENG", "organisation", bad_command, 70, "test rejection", [])
	_check(int(world_reject.global_counters.get("naval_ai_candidates_evaluated", 0)) == 2, "REJECTED_CANDIDATE_NOT_COUNTED", "one accepted plus one rejected candidate must total exactly two evaluated candidates: got %s" % world_reject.global_counters.get("naval_ai_candidates_evaluated", 0))
	_check(int(world_reject.global_counters.get("naval_ai_commands_submitted", 0)) == 1, "REJECTED_CANDIDATE_WRONGLY_SUBMITTED", "a rejected candidate must never increment naval_ai_commands_submitted: got %s" % world_reject.global_counters.get("naval_ai_commands_submitted", 0))
	var rejected: Array = naval_ai_reject.debug_snapshot(world_reject, "ENG")["rejected_candidates"]
	_check(not rejected.is_empty() and (rejected.back() as Dictionary).get("targets", []) == [], "REJECTED_CANDIDATE_MISSING_TARGETS_KEY", "a rejected candidate record must carry a targets field, even if empty for this call: got %s" % [rejected])


func _run() -> void:
	_test_posture_structured_fields()
	_test_tactical_targets_include_fleet()
	_test_candidates_evaluated_counter()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval AI explainability test failed: %s" % failure)
		print("Naval AI explainability test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval AI explainability test passed. cases=posture_fields,tactical_targets,candidates_evaluated_counter")
	quit(0)
