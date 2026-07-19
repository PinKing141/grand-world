extends SceneTree

## FL3 "Automated verification": "AI recovers from destroyed fleets, blocked/
## captured ports, access loss, peace, debt and insufficient sailors" -
## previously untested as a matrix per FL3_CLOSURE_AUDIT.md's own accounting
## ("only two narrow slices exist... destroyed fleets, blocked/captured
## ports after a plan is already committed, access loss mid-plan, peace
## signing mid-plan, debt, and insufficient sailors are not exercised as
## AI-recovery scenarios at all"). Each case here proves a genuine before/
## during/after story - a real obstacle, the AI's correct reaction to it,
## the obstacle clearing, and the AI actually resuming useful work - not
## just a one-shot rejection, which several of these already had covered
## elsewhere. "Access loss"/"captured home port" is not duplicated here -
## tests/naval_ai_reinforcement_homeport_transport_test.gd's own
## _test_home_port_reassigned_on_access_loss() already proves that exact
## recovery story end to end.
##
## Two real gaps were found and fixed while building this, not assumed
## fixed: NavalCombatSystem._begin_retreat()'s no-legal-retreat destruction
## path never cleared the destroyed fleet's admiral back-reference (a
## previously-recorded, deliberately-left-open gap from FL2_5_SCUTTLE_
## COMMAND.md, closed here since it directly blocks "recovers from destroyed
## fleets"), and _consider_mission_completion() never reconsidered a
## "blockade"-missioned fleet at all, so a fleet still tagged blockade after
## peace was invisible to every other tactical decision forever, not merely
## ineffective at blockading.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")
const AssignAdmiralCommandScript = preload("res://scripts/simulation/commands/assign_admiral_command.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")

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


func _set_treasury(world: CampaignWorldState, tag: String, treasury: int, sailors: int = 1000000) -> void:
	var runtime := world.country_runtime(tag)
	runtime["treasury"] = treasury
	runtime["sailors"] = sailors
	runtime["debt"] = 0
	var ledger: Dictionary = runtime.get("ledger", {})
	ledger["balance"] = 0
	ledger["total_expenses"] = 0
	runtime["ledger"] = ledger
	world.set_country_runtime(tag, runtime)


## Destroyed fleets: a fleet with an assigned admiral is destroyed through
## the real no-legal-retreat combat path (not a synthetic erase), and the
## freed admiral must become available for the AI to reassign to a
## surviving fleet - proving both the admiral-cleanup fix and that the AI
## actually resumes useful work with the freed character, not just that
## nothing crashes.
func _test_recovers_from_destroyed_fleet_and_admiral() -> void:
	# NavalAccessPolicy.can_dock() treats any *unowned* port as legally
	# dockable by anyone (naval_access_policy.gd:43) - so merely flipping
	# Calais/Kent to a hostile owner is not enough to strand a fleet in the
	# real full maritime graph; countless other unowned ports worldwide
	# would still be "legal." Forcing a genuine no-legal-retreat requires
	# every real port in the graph to be hostile-owned, the same fixture
	# shape tests/naval_destructive_edge_gate_test.gd's own
	# _test_retreat_and_save() already established for this exact reason.
	var graph := MaritimeGraphScript.load_default()
	var hostile_owners := {STRAITS_OF_DOVER: ""}
	for port_id in graph.port_province_ids():
		hostile_owners[int(port_id)] = "BUR"
	var world := CampaignWorldStateScript.new()
	world.initialize(hostile_owners, {"ENG": "England", "BUR": "Burgundy"})
	EconomySystemScript.initialize_world(world)
	world.war_registry["war_1"] = {
		"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "BUR",
		"attackers": ["ENG"], "defenders": ["BUR"], "battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": PICARDIE, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
	}
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_doomed", "ENG", STRAITS_OF_DOVER, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 1)
	_add_fleet(world, "fleet_survivor", "ENG", STRAITS_OF_DOVER, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 2)
	var admiral_id := CharacterSystemScript._create_courtier(world, events, "ENG", "male")
	AssignAdmiralCommandScript.new("ENG", "fleet_doomed", admiral_id).apply(world, events)
	_check(String(world.get_fleet("fleet_doomed").get("admiral_id", "")) == admiral_id, "FIXTURE_ADMIRAL_NOT_ASSIGNED", "fixture assumption: the doomed fleet must start with its admiral assigned")
	NavalCombatSystemScript._begin_retreat(world, events, "fleet_doomed", STRAITS_OF_DOVER)
	_check(not world.fleet_registry.has("fleet_doomed"), "FIXTURE_FLEET_NOT_DESTROYED", "fixture assumption: a fleet with no legal retreat destination must be destroyed outright")
	_check(String(world.character_registry.get(admiral_id, {}).get("admiral_fleet_id", "unset")) == "", "ADMIRAL_STILL_ATTACHED_TO_DESTROYED_FLEET", "the destroyed fleet's admiral must have its admiral_fleet_id cleared, not left dangling")

	# fleet_survivor needs no legal port of its own to already exist for this
	# assignment - AssignAdmiralCommand.validate() has no location/docking
	# requirement at all, only ownership and admiral eligibility.
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._plan_organisation(world, "ENG")
	naval_ai.scheduler.process_commands()
	_check(String(world.get_fleet("fleet_survivor").get("admiral_id", "")) == admiral_id, "ADMIRAL_NOT_REASSIGNED", "the freed admiral must be assignable to a surviving fleet by the AI's own organisation planning: got '%s'" % world.get_fleet("fleet_survivor").get("admiral_id", ""))


## Debt: a country in debt classifies as "recovery" (frozen ship count);
## once debt clears, the very next posture review must resume normal
## (non-frozen) planning on the same persistent AI state, not just classify
## a fresh world correctly in isolation.
func _test_recovers_from_debt() -> void:
	var world := _make_world(false)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 60000, 1000000)
	var runtime := world.country_runtime("ENG")
	runtime["debt"] = 5000
	world.set_country_runtime("ENG", runtime)
	var naval_ai := _make_naval_ai(world, events)
	var profile := AIDefinitionsScript.load_default().profile("ENG")
	naval_ai._review_posture(world, "ENG", profile)
	var during := String((world.country_runtime("ENG").get("naval_ai", {}) as Dictionary).get("posture", ""))
	_check(during == "recovery", "DEBT_DID_NOT_TRIGGER_RECOVERY", "fixture assumption: outstanding debt must classify as 'recovery', got '%s'" % during)
	var during_desired := int((world.country_runtime("ENG").get("naval_ai", {}) as Dictionary).get("desired_ship_count", -1))
	_check(during_desired == 2, "DEBT_DESIRED_COUNT_WRONG", "recovery must freeze at the peacetime x1 multiplier (2), got %d" % during_desired)

	_set_treasury(world, "ENG", 60000, 1000000)
	naval_ai._review_posture(world, "ENG", profile)
	var after := String((world.country_runtime("ENG").get("naval_ai", {}) as Dictionary).get("posture", ""))
	_check(after != "recovery", "DID_NOT_RECOVER_FROM_DEBT", "the same country's posture must leave 'recovery' the moment debt clears, got '%s'" % after)
	var after_desired := int((world.country_runtime("ENG").get("naval_ai", {}) as Dictionary).get("desired_ship_count", -1))
	_check(after_desired == 4, "DID_NOT_RESUME_AMBITIOUS_MULTIPLIER", "clearing debt must resume the ambitious x2 multiplier, got %d" % after_desired)


## Insufficient sailors: construction is proactively rejected while sailors
## are unavailable; once sailors replenish, the very next construction tick
## must actually succeed with a real queued ship, not just stop rejecting.
func _test_recovers_from_insufficient_sailors() -> void:
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 5000000, 1)
	var naval_ai := _make_naval_ai(world, events)
	var profile := AIDefinitionsScript.load_default().profile("ENG")
	naval_ai._review_posture(world, "ENG", profile)
	naval_ai._plan_construction(world, "ENG", profile)
	naval_ai.scheduler.process_commands()
	_check(world.naval_construction_registry.is_empty(), "FIXTURE_BUILT_DESPITE_NO_SAILORS", "fixture assumption: one sailor cannot crew any real ship")
	var during_action := String((world.country_runtime("ENG").get("naval_ai", {}) as Dictionary).get("last_decision", {}).get("action", ""))
	_check(during_action == "insufficient_sailors", "SAILOR_REJECTION_NOT_RECORDED", "the rejection must be explained as insufficient_sailors, got '%s'" % during_action)

	var runtime := world.country_runtime("ENG")
	runtime["sailors"] = 1000000
	world.set_country_runtime("ENG", runtime)
	naval_ai._plan_construction(world, "ENG", profile)
	naval_ai.scheduler.process_commands()
	_check(world.naval_construction_registry.size() == 1, "DID_NOT_RECOVER_FROM_NO_SAILORS", "replenished sailors must let the very next construction tick actually queue a real ship")


## Peace: a blockading fleet's mission never "finishes" on its own
## (BlockadeSystem's own live queries already zero out correctly the
## instant a war ends - see FL5_2_BLOCKADE_COASTAL_CONTRACT.md), but
## nothing previously reset the fleet's own mission tag, and every other
## tactical decision requires mission == "idle" to even consider a fleet -
## so a post-peace blockading fleet was invisible to reinforcement/escort/
## intercept/protect_coast/patrol forever, not merely ineffective. Proves
## the fix: the fleet stands down to idle once peace lands, and becomes
## genuinely reconsiderable (picks up patrol) on the very next tactical tick.
func _test_recovers_from_peace_mid_blockade() -> void:
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_add_fleet(world, "fleet_blockading", "ENG", CALAIS, STRAITS_OF_DOVER, CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 3)
	var naval_ai := _make_naval_ai(world, events)
	naval_ai._consider_blockade_or_evade(world, "ENG", "fleet_blockading")
	naval_ai.scheduler.process_commands()
	_check(String(world.get_fleet("fleet_blockading").get("mission", "")) == "blockade", "FIXTURE_NOT_BLOCKADING", "fixture assumption: an idle fleet at a safe zone with a reachable war target must take up blockade duty")

	world.war_registry["war_1"]["status"] = "ended"
	var stood_down := naval_ai._consider_mission_completion(world, "ENG", "fleet_blockading")
	naval_ai.scheduler.process_commands()
	_check(stood_down, "DID_NOT_STAND_DOWN_AFTER_PEACE", "a blockading fleet must stand down to idle once its war ends and its target vanishes")
	_check(String(world.get_fleet("fleet_blockading").get("mission", "")) == "idle", "MISSION_TAG_STILL_BLOCKADE", "the fleet's own mission tag must actually change to idle, not just become ineffective")

	# Genuinely reconsiderable: with no war and no threat, patrol is the
	# correct next assignment for an idle fleet in a safe zone.
	var picked_up := naval_ai._consider_patrol(world, "ENG", "fleet_blockading")
	naval_ai.scheduler.process_commands()
	_check(picked_up, "NOT_RECONSIDERED_AFTER_PEACE", "the freed fleet must be genuinely visible to the next tactical decision, not still excluded")
	_check(String(world.get_fleet("fleet_blockading").get("mission", "")) == "patrol", "DID_NOT_PICK_UP_PATROL", "an idle fleet in a safe post-peace zone with nothing more urgent must take up patrol")


## Blocked/captured ports: a port used for construction is captured -
## _best_construction_port() already scopes to _country_ports() (owned and
## enabled only), so a captured port drops out automatically without any
## special-case recovery code, and the AI must build at its one remaining
## owned port instead of failing.
func _test_recovers_from_captured_construction_port() -> void:
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 5000000, 1000000)
	world.set_province_owner(CALAIS, "BUR")
	world.set_province_controller(CALAIS, "BUR")
	var naval_ai := _make_naval_ai(world, events)
	var profile := AIDefinitionsScript.load_default().profile("ENG")
	naval_ai._review_posture(world, "ENG", profile)
	naval_ai._plan_construction(world, "ENG", profile)
	naval_ai.scheduler.process_commands()
	_check(world.naval_construction_registry.size() == 1, "DID_NOT_RECOVER_FROM_CAPTURED_PORT", "losing one of two owned ports must not stop construction at the remaining one")
	if world.naval_construction_registry.size() == 1:
		var record: Dictionary = world.naval_construction_registry.values()[0]
		_check(int(record.get("port_id", -1)) == KENT, "BUILT_AT_CAPTURED_PORT", "construction must land at the still-owned port (Kent), not the captured one (Calais): got %d" % int(record.get("port_id", -1)))


func _run() -> void:
	_test_recovers_from_destroyed_fleet_and_admiral()
	_test_recovers_from_debt()
	_test_recovers_from_insufficient_sailors()
	_test_recovers_from_peace_mid_blockade()
	_test_recovers_from_captured_construction_port()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval AI recovery matrix test failed: %s" % failure)
		print("Naval AI recovery matrix test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval AI recovery matrix test passed. cases=destroyed_fleet_admiral,debt,insufficient_sailors,peace_mid_blockade,captured_construction_port")
	quit(0)
