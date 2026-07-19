extends SceneTree

## FL3.2 correctness fix: ship_definitions.json's real data already declares
## required_technology per ship (only the "heavy" family requires above
## level 0 today - heavy_galleon needs military 1, heavy_ship_of_the_line
## needs military 3), but ConstructShipCommand.validate() never checked it,
## so a technology-gated world could always build every ship. Fixed by
## mirroring RecruitUnitCommand.validate()'s own country_depth_enabled/
## required_technology check exactly (commands/recruit_unit_command.gd:32-36).
## This test proves the command-level gate (reject below, accept at exact
## level, stay inert without country depth) and the naval-AI-level fix
## (skip a locked family and build the next-ranked one instead of
## repeatedly proposing the same rejected candidate).

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")
const ConstructShipCommandScript = preload("res://scripts/simulation/commands/construct_ship_command.gd")

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


func _set_treasury(world: CampaignWorldState, tag: String, treasury: int, sailors: int = 1000000) -> void:
	var runtime := world.country_runtime(tag)
	runtime["treasury"] = treasury
	runtime["sailors"] = sailors
	var ledger: Dictionary = runtime.get("ledger", {})
	ledger["total_expenses"] = 0
	runtime["ledger"] = ledger
	world.set_country_runtime(tag, runtime)


func _set_technology(world: CampaignWorldState, tag: String, military_level: int) -> void:
	world.global_flags["country_depth_enabled"] = true
	var runtime := world.country_runtime(tag)
	runtime["technology"] = {"administrative": 0, "diplomatic": 0, "military": military_level}
	world.set_country_runtime(tag, runtime)


func _test_command_gate_disabled_without_country_depth() -> void:
	var world := _make_world(false)
	_set_treasury(world, "ENG", 5000000)
	# country_depth_enabled is never set on this world - the same
	# synthetic/legacy-save compatibility RecruitUnitCommand's own gate
	# already relies on. heavy_galleon (not heavy_ship_of_the_line, which
	# only unlocks in 1600 regardless of technology) is date-unlocked from
	# the campaign start, isolating this check to the technology gate alone.
	var command := ConstructShipCommandScript.new("ENG", CALAIS, "heavy_galleon")
	_check(command.validate(world).is_empty(), "GATE_WRONGLY_ACTIVE_WITHOUT_DEPTH", "a synthetic world with no country_depth_enabled flag must never apply the technology gate: %s" % command.validate(world))


func _test_command_gate_rejects_below_requirement() -> void:
	var world := _make_world(false)
	_set_treasury(world, "ENG", 5000000)
	_set_technology(world, "ENG", 0)
	var command := ConstructShipCommandScript.new("ENG", CALAIS, "heavy_galleon")
	var failure := command.validate(world)
	_check(not failure.is_empty(), "GATE_DID_NOT_REJECT", "military technology 0 must reject a ship requiring military technology 1")
	_check(failure.contains("military technology 1"), "GATE_WRONG_MESSAGE", "the rejection must name the missing track and level: got '%s'" % failure)


func _test_command_gate_accepts_at_exact_requirement() -> void:
	var world := _make_world(false)
	_set_treasury(world, "ENG", 5000000)
	_set_technology(world, "ENG", 1)
	var command := ConstructShipCommandScript.new("ENG", CALAIS, "heavy_galleon")
	_check(command.validate(world).is_empty(), "GATE_REJECTED_AT_EXACT_LEVEL", "military technology exactly 1 must accept a ship requiring military technology 1: %s" % command.validate(world))
	# One level above the requirement must also remain accepted - the gate
	# is a floor, not an exact match.
	_set_technology(world, "ENG", 2)
	_check(command.validate(world).is_empty(), "GATE_REJECTED_ABOVE_LEVEL", "military technology above the requirement must still accept: %s" % command.validate(world))


func _make_naval_ai(world: CampaignWorldState, events: SimulationEventBus) -> NavalAISystem:
	var scheduler := SimulationSchedulerScript.new(world, events)
	return NavalAISystemScript.new(scheduler, events, AIDefinitionsScript.load_default())


func _test_ai_skips_locked_family() -> void:
	# "wartime" posture (heavy 4500bp, galley 3000bp, light 1500bp,
	# transport 1000bp) weights "heavy" highest, but at military technology
	# 0 neither heavy ship is eligible (heavy_galleon needs 1,
	# heavy_ship_of_the_line needs 3) - every other family (galley/light/
	# transport) is fully eligible at technology 0. The AI must not just
	# give up on the locked top-ranked family; it must fall through to the
	# next-ranked eligible one - "galley," the second-highest wartime
	# weight, from an empty fleet where every family's deficit is directly
	# proportional to its own mix weight.
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 5000000)
	_set_technology(world, "ENG", 0)
	var naval_ai := _make_naval_ai(world, events)
	var profile := AIDefinitionsScript.load_default().profile("ENG")
	naval_ai._review_posture(world, "ENG", profile)
	var posture := String((world.country_runtime("ENG").get("naval_ai", {}) as Dictionary).get("posture", ""))
	_check(posture == "wartime", "FIXTURE_WRONG_POSTURE", "fixture assumption: this scenario must resolve to 'wartime', got '%s'" % posture)
	naval_ai._plan_construction(world, "ENG", profile)
	naval_ai.scheduler.process_commands()
	_check(world.naval_construction_registry.size() == 1, "AI_DID_NOT_BUILD_ANYTHING", "a locked top-priority family must not stop the AI from building an eligible one instead")
	if world.naval_construction_registry.size() == 1:
		var record: Dictionary = world.naval_construction_registry.values()[0]
		var definition_id := String(record.get("definition_id", ""))
		var family := String(ShipDefinitionsScript.load_default().ship(definition_id).get("family", ""))
		_check(family != "heavy", "AI_BUILT_LOCKED_FAMILY", "the AI must never queue a technology-locked design: built '%s' in family '%s'" % [definition_id, family])
		_check(family == "galley", "AI_DID_NOT_PICK_NEXT_RANKED_FAMILY", "wartime's second-highest weight after the locked 'heavy' family is 'galley' - expected that family, got '%s' (%s)" % [family, definition_id])
	var last_decision: Dictionary = naval_ai.debug_snapshot(world, "ENG")["last_decision"]
	_check(String(last_decision.get("category", "")) == "construction" and String(last_decision.get("action", "")) == "ConstructShipCommand", "AI_LAST_DECISION_NOT_SUCCESSFUL_CONSTRUCTION", "the final recorded decision must be the successful ConstructShipCommand submission, not a rejection, once a legal family exists: got %s" % last_decision)


func _test_ai_records_one_rejection_when_every_family_locked() -> void:
	# A country_depth-enabled world where every family requires more
	# technology than the country has must record exactly one clear
	# rejection, not one per family attempted and not a crash. Every real
	# family except "heavy" requires only military technology 0 today, so a
	# below-zero synthetic value is the only way to lock every family with
	# the current data - not a realistic in-game value, but a valid probe
	# of the same "< requirement" comparison the level-1/level-3 cases above
	# already exercise at their real boundary.
	var world := _make_world(true)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	_set_treasury(world, "ENG", 5000000)
	_set_technology(world, "ENG", -1)
	var naval_ai := _make_naval_ai(world, events)
	var profile := AIDefinitionsScript.load_default().profile("ENG")
	naval_ai._review_posture(world, "ENG", profile)
	naval_ai._plan_construction(world, "ENG", profile)
	naval_ai.scheduler.process_commands()
	_check(world.naval_construction_registry.is_empty(), "FIXTURE_BUILT_DESPITE_LOCKED_TECH", "fixture assumption: below-zero military technology must lock every family")
	var rejected: Array = naval_ai.debug_snapshot(world, "ENG")["rejected_candidates"]
	_check(not rejected.is_empty(), "NO_REJECTION_RECORDED", "a fully locked navy must still record an explained rejection")
	if not rejected.is_empty():
		var last_rejection: Dictionary = rejected.back()
		_check(String(last_rejection.get("reason", "")).contains("technology-eligible"), "REJECTION_WRONG_REASON", "the rejection must explain that no technology-eligible design exists: got '%s'" % last_rejection.get("reason", ""))


func _test_player_and_ai_share_command_contract() -> void:
	# Both paths go through ConstructShipCommand.validate() directly - a
	# player-issued command and an AI-submitted one must be rejected by the
	# exact same rule with the exact same message, since neither path has
	# its own parallel eligibility check.
	var world := _make_world(false)
	_set_treasury(world, "ENG", 5000000)
	_set_technology(world, "ENG", 0)
	var player_command := ConstructShipCommandScript.new("ENG", CALAIS, "heavy_galleon")
	var ai_command := ConstructShipCommandScript.new("ENG", CALAIS, "heavy_galleon")
	_check(player_command.validate(world) == ai_command.validate(world), "PLAYER_AI_CONTRACT_DIVERGED", "a player-issued and an AI-issued command for the identical illegal ship must be rejected with the identical message")
	_check(not player_command.validate(world).is_empty(), "PLAYER_AI_CONTRACT_FIXTURE_NOT_LOCKED", "fixture assumption: this ship must genuinely be locked at technology 0")


func _run() -> void:
	_test_command_gate_disabled_without_country_depth()
	_test_command_gate_rejects_below_requirement()
	_test_command_gate_accepts_at_exact_requirement()
	_test_ai_skips_locked_family()
	_test_ai_records_one_rejection_when_every_family_locked()
	_test_player_and_ai_share_command_contract()
	if not _failures.is_empty():
		for failure in _failures:
			push_error("Naval ship technology gate test failed: %s" % failure)
		print("Naval ship technology gate test FAILED. failures=%d" % _failures.size())
		quit(1)
		return
	print("Naval ship technology gate test passed. cases=disabled_without_depth,rejects_below,accepts_at_exact,ai_skips_locked,ai_all_locked,player_ai_contract")
	quit(0)
