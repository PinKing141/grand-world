extends SceneTree

## N3.3/N4.3/N5.2 peace-and-extinction closeout: CountryDepthSystem already
## hard-erases an extinct country's armies from army_registry directly, with
## no equivalent sweep of its naval registries. Left as-is, an extinct
## country mid-transport or mid-battle at sea would leave dangling
## transport_operation_registry/naval_battle_registry references that
## _validate_transport_data/_validate_naval_battle_data reject on the very
## next save load - a real corruption bug, not a hygiene gap. This test
## drives that exact scenario through _reconcile_country_status directly
## (the codebase's own precedent for unit-testing "private" static helpers;
## see naval_blockade_test.gd and naval_transport_recovery_test.gd).

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")

const CALAIS := 87
const KENT := 235


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval country extinction test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "FRA"},
		{"ENG": "England", "FRA": "France"}
	)
	return world


func _add_character(world: CampaignWorldState, character_id: String, employer: String) -> void:
	world.character_registry[character_id] = {
		"character_id": character_id, "name": character_id, "sex": "male",
		"birth": {"year": 1400, "month": 1, "day": 1},
		"alive": true, "death_day": -1, "death_cause": "",
		"culture": "Test", "religion": "Test", "dynasty_id": "",
		"father_id": "", "mother_id": "", "spouse_id": "", "former_spouses": [], "children": [],
		"employer_country": employer,
		"skills": {"diplomacy": 1, "martial": 1, "stewardship": 1, "intrigue": 1, "learning": 1},
		"traits": [], "health_bp": 8000, "fertility_bp": 5000, "stress_bp": 0,
		"titles": [], "claims": [], "event_cooldowns": {}, "last_birth_day": -9999,
		"commander_army_id": "", "admiral_fleet_id": "",
		"illness": "", "illness_until_day": -1, "opinion_modifiers": [],
	}


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)

	# ENG starts as a recognised, active land country.
	var eng_runtime := world.country_runtime("ENG")
	eng_runtime["country_status"] = "active"
	world.set_country_runtime("ENG", eng_runtime)
	world.global_flags["country_depth_active_countries"] = ["ENG", "FRA"]

	# An ENG army mid-transport, referenced by a live transport operation.
	world.army_registry["eng_army"] = CampaignWorldStateScript.make_army_record("eng_army", "ENG", CALAIS)
	world.army_registry["eng_army"]["transport_operation_id"] = "transport_1"
	world.army_registry["eng_army"]["status"] = CampaignWorldState.ARMY_STATUS_EMBARKING

	# An ENG fleet, with an admiral, carrying that transport operation and
	# simultaneously locked in an active naval battle against an FRA fleet.
	world.fleet_registry["eng_fleet"] = CampaignWorldStateScript.make_fleet_record("eng_fleet", "ENG", CALAIS)
	world.fleet_registry["eng_fleet"]["admiral_id"] = "eng_admiral"
	world.fleet_registry["eng_fleet"]["transport_operation_ids"] = ["transport_1"]
	world.fleet_registry["eng_fleet"]["battle_id"] = "naval_battle_000001"
	world.fleet_registry["eng_fleet"]["ship_ids"] = ["eng_ship"]
	world.ship_registry["eng_ship"] = CampaignWorldStateScript.make_ship_record("eng_ship", "ENG", "eng_fleet", "war_galley", 0)

	world.fleet_registry["fra_fleet"] = CampaignWorldStateScript.make_fleet_record("fra_fleet", "FRA", KENT)
	world.fleet_registry["fra_fleet"]["battle_id"] = "naval_battle_000001"
	world.fleet_registry["fra_fleet"]["ship_ids"] = ["fra_ship"]
	world.ship_registry["fra_ship"] = CampaignWorldStateScript.make_ship_record("fra_ship", "FRA", "fra_fleet", "war_galley", 0)

	var battle := CampaignWorldStateScript.make_naval_battle_record("naval_battle_000001", "war_1", CALAIS, 0)
	battle["attacker_fleets"] = ["eng_fleet"]
	battle["defender_fleets"] = ["fra_fleet"]
	world.naval_battle_registry["naval_battle_000001"] = battle
	world.war_registry["war_1"] = {
		"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "FRA",
		"attackers": ["ENG"], "defenders": ["FRA"],
		"war_goal": {"type": "conquer_province", "province_id": KENT, "target_country": "FRA", "justification": "claim", "peace_cost": 0},
		"battles": {}, "sieges": {}, "occupied_provinces": {}, "peace_offers": {},
		"battle_score_attacker": 0, "occupation_score_attacker": 0, "ticking_score_attacker": 0, "blockade_score_attacker": 0,
		"total_war_score": 0, "history": [],
	}

	world.transport_operation_registry["transport_1"] = CampaignWorldStateScript.make_transport_operation_record(
		"transport_1", "ENG", "eng_army", "eng_fleet", CALAIS, KENT, 100, 0, 5
	)

	world.naval_construction_registry["eng_construction"] = CampaignWorldStateScript.make_naval_construction_record(
		"eng_construction", "ENG", CALAIS, "war_galley", 0, 10, 500
	)

	world.dynasty_registry[""] = {}
	_add_character(world, "eng_admiral", "ENG")
	world.character_registry["eng_admiral"]["admiral_fleet_id"] = "eng_fleet"

	var army_lost_signals: Array = []
	events.transport_operation_army_lost.connect(func(operation_id, army_id, reason): army_lost_signals.append([operation_id, army_id, reason]))
	var fleet_destroyed_signals: Array = []
	events.fleet_destroyed.connect(func(fleet_id, reason): fleet_destroyed_signals.append([fleet_id, reason]))
	var battle_ended_signals: Array = []
	events.naval_battle_ended.connect(func(war_id, battle_id, winner_side): battle_ended_signals.append([war_id, battle_id, winner_side]))

	# Strip ENG of every province so _current_land_country_tags no longer
	# reports it - the trigger _reconcile_country_status watches for.
	world.set_province_owner(CALAIS, "FRA")

	CountryDepthSystemScript._reconcile_country_status(world, events)

	_require(String(world.country_runtime("ENG").get("country_status", "")) == "extinct", "ENG must be marked extinct")
	_require(not world.army_registry.has("eng_army"), "the extinct country's army must already be gone")

	_require(not world.transport_operation_registry.has("transport_1"), "the dangling transport operation must be cleaned up")
	_require(army_lost_signals.size() == 1 and String(army_lost_signals[0][2]) == "country_extinct", "the transport loss must be reported as an extinction")

	_require(not world.fleet_registry.has("eng_fleet"), "the extinct country's fleet must be gone")
	_require(not world.ship_registry.has("eng_ship"), "the extinct country's ship must be gone")
	_require(fleet_destroyed_signals.size() == 1 and String(fleet_destroyed_signals[0][0]) == "eng_fleet", "fleet destruction must be reported")

	_require(String(world.character_registry["eng_admiral"]["admiral_fleet_id"]).is_empty(), "the admiral's fleet assignment must be cleared")

	_require(String(world.naval_battle_registry["naval_battle_000001"]["status"]) == "completed", "the battle must end once one side has no fleets left")
	_require(String(world.naval_battle_registry["naval_battle_000001"]["winner_side"]) == "defender", "FRA (the remaining side) must be recorded as the winner")
	_require(battle_ended_signals.size() == 1, "the battle-ended event must fire exactly once")

	_require(not world.naval_construction_registry.has("eng_construction"), "the extinct country's naval construction must be cleaned up")

	# The save must now round-trip cleanly - before this fix, the dangling
	# transport operation and battle-fleet reference would both fail
	# _validate_transport_data / _validate_naval_battle_data on load.
	var saved := world.to_save_dict("test")
	var reloaded := _make_world()
	var load_error := reloaded.apply_save_dict(saved)
	_require(load_error.is_empty(), "the post-extinction save must load cleanly: %s" % load_error)

	print("Naval country extinction test passed.")
	quit(0)
