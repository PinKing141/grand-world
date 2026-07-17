extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

# N0.3 Channel fixture.
const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271

const CLOSED_WATER_SAMPLE := 1250


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval access policy test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR"},
		{"ENG": "England", "BUR": "Burgundy"}
	)
	return world


func _run() -> void:
	var graph := MaritimeGraphScript.load_default()
	var world := _make_world()

	# Question 1: sail access.
	_require(NavalAccessPolicyScript.can_sail(graph, STRAITS_OF_DOVER), "the Straits of Dover must be sailable by anyone")
	_require(not NavalAccessPolicyScript.can_sail(graph, CLOSED_WATER_SAMPLE), "closed water must never be sailable")

	# Question 2: docking, own port and default-deny.
	_require(NavalAccessPolicyScript.can_dock(graph, world, "ENG", CALAIS), "England must be able to dock at its own port")
	_require(not NavalAccessPolicyScript.can_dock(graph, world, "BUR", CALAIS), "an unrelated country must be denied docking by default")
	_require(NavalAccessPolicyScript.dock_failure_reason(graph, world, "ENG", CALAIS).is_empty(), "an allowed dock must report no failure reason")
	_require(not NavalAccessPolicyScript.dock_failure_reason(graph, world, "BUR", CALAIS).is_empty(), "a denied dock must report a non-empty failure reason")

	# N1.4 access explanation must name the exact relationship, not just allow/deny.
	_require(NavalAccessPolicyScript.explain_dock(graph, world, "ENG", CALAIS).find("owns/controls") >= 0, "an own-port explanation must cite ownership")
	_require(NavalAccessPolicyScript.explain_dock(graph, world, "BUR", CALAIS).find("NOT dock") >= 0, "a denied explanation must clearly say so")

	# War does NOT grant docking (unlike land invasion access) - deliberate.
	world.war_registry["w_test"] = {
		"war_id": "w_test", "status": "active",
		"attackers": ["BUR"], "defenders": ["ENG"],
	}
	_require(DiplomacySystemScript.are_at_war(world, "BUR", "ENG"), "test war setup must register as active")
	_require(not NavalAccessPolicyScript.can_dock(graph, world, "BUR", CALAIS), "being at war must not itself grant docking at a hostile port")
	world.war_registry.clear()

	# Alliance grants docking.
	var allied := DiplomacySystemScript.relation(world, "ENG", "BUR")
	allied["alliance"] = true
	DiplomacySystemScript.set_relation(world, "ENG", "BUR", allied)
	_require(NavalAccessPolicyScript.can_dock(graph, world, "BUR", CALAIS), "an ally must be able to dock")
	_require(NavalAccessPolicyScript.explain_dock(graph, world, "BUR", CALAIS).find("allied") >= 0, "an alliance-granted explanation must name the alliance, not just say allowed")
	# ... but alliance alone does not grant basing rights (ownership-only for now).
	_require(not NavalAccessPolicyScript.can_base(graph, world, "BUR", CALAIS), "an ally without ownership must not receive basing rights yet")
	_require(NavalAccessPolicyScript.can_base(graph, world, "ENG", CALAIS), "the owner must always have basing rights at its own port")
	allied["alliance"] = false
	DiplomacySystemScript.set_relation(world, "ENG", "BUR", allied)
	_require(not NavalAccessPolicyScript.can_dock(graph, world, "BUR", CALAIS), "removing the alliance must remove docking again")

	# Explicit military_access (reused as the naval_access proxy) grants docking.
	var access := DiplomacySystemScript.relation(world, "BUR", "ENG")
	var access_grants: Dictionary = access["military_access"]
	access_grants["BUR"] = true
	access["military_access"] = access_grants
	DiplomacySystemScript.set_relation(world, "BUR", "ENG", access)
	_require(NavalAccessPolicyScript.can_dock(graph, world, "BUR", CALAIS), "explicit access must grant docking")
	access_grants["BUR"] = false
	access["military_access"] = access_grants
	DiplomacySystemScript.set_relation(world, "BUR", "ENG", access)
	_require(not NavalAccessPolicyScript.can_dock(graph, world, "BUR", CALAIS), "revoking access must remove docking again")

	# Subject/overlord relationship grants docking.
	world.subject_registry["s_test"] = {"subject": "BUR", "overlord": "ENG", "status": "active"}
	_require(DiplomacySystemScript.overlord_of(world, "BUR") == "ENG", "test subject setup must register")
	_require(NavalAccessPolicyScript.can_dock(graph, world, "BUR", CALAIS), "a subject must be able to dock in its overlord's ports")
	_require(NavalAccessPolicyScript.can_dock(graph, world, "ENG", PICARDIE), "an overlord must be able to dock in its subject's ports")
	world.subject_registry.clear()

	# Disabled/unknown ports are always denied regardless of relationship.
	_require(not NavalAccessPolicyScript.can_dock(graph, world, "ENG", STRAITS_OF_DOVER), "a sea zone is never dockable as a port")
	_require(not NavalAccessPolicyScript.can_base(graph, world, "ENG", STRAITS_OF_DOVER), "a sea zone never provides basing rights")

	# Supply range query: Straits of Dover is one port-leg from both Calais and Kent.
	var supplied := NavalAccessPolicyScript.supply_range_query(graph, world, "ENG", STRAITS_OF_DOVER, 5)
	_require(bool(supplied["supplied"]), "England must be supplied near its own Channel ports")
	_require(int(supplied["nearest_port_id"]) == CALAIS, "the nearest basing port must tie-break to the lowest stable ID (Calais over Kent)")
	_require(int(supplied["range_cost"]) == 1, "Straits of Dover to Calais must cost exactly one port-entry leg")

	var out_of_range := NavalAccessPolicyScript.supply_range_query(graph, world, "ENG", STRAITS_OF_DOVER, 0)
	_require(not bool(out_of_range["supplied"]), "a zero-day range limit must report unsupplied")
	_require(int(out_of_range["nearest_port_id"]) == CALAIS, "an unsupplied result must still report which port was nearest")
	_require(not String(out_of_range["failure_reason"]).is_empty(), "an unsupplied result must explain why")

	# Burgundy owns Picardie, which sits directly on the Straits of Dover, so
	# each country's nearest basing port genuinely differs.
	var burgundy_supplied := NavalAccessPolicyScript.supply_range_query(graph, world, "BUR", STRAITS_OF_DOVER, 5)
	_require(bool(burgundy_supplied["supplied"]), "Burgundy must be supplied at its own adjacent port")
	_require(int(burgundy_supplied["nearest_port_id"]) == PICARDIE, "Burgundy's nearest basing port from the Straits of Dover must be its own Picardie, not England's")

	var closed_query := NavalAccessPolicyScript.supply_range_query(graph, world, "ENG", CLOSED_WATER_SAMPLE, 999)
	_require(not bool(closed_query["supplied"]), "a closed_water zone must never report supplied")
	_require(not String(closed_query["failure_reason"]).is_empty(), "a closed_water zone query must explain the rejection")

	print("Naval access policy test passed. calais_range=%d" % int(supplied["range_cost"]))
	quit(0)
