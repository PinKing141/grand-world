extends SceneTree

## N6.3 "Save migration and corruption suite": every earlier per-phase test in
## this suite already proves migrate_save_data() upgrades from its own one
## adjacent schema to current (schema_version 1 through 6 each have a
## dedicated test - see phase_3/4/7/8 and naval_fleet_state/transport_
## operation tests) - but nothing exercised this pillar's own two schema
## bumps (7: naval_battle_registry, N4A; 8: blockaded_provinces, N5.1's
## blockade-transition tracking), and nothing proved the full schema-1
## through-9 chain executes correctly in a single migrate_save_data() call
## rather than only in isolated single-step tests. This closes that gap.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")

const OWNERS := {87: "ENG", 89: "BUR", 90: "BUR", 1271: ""}
const NAMES := {"ENG": "England", "BUR": "Burgundy"}


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval save schema migration test failed: %s" % message)
		quit(1)


## A real, populated schema-9 world: a war, a fleet/ship pair on each side of
## an active naval battle (reciprocal battle_id references, satisfying
## _validate_naval_battle_data's active-battle rule), and a blockaded
## province - so stripped-and-migrated saves are proven against genuine
## content, not an empty placeholder dict.
func _make_populated_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(OWNERS, NAMES)
	world.war_registry["war_1"] = {
		"war_id": "war_1", "status": "active", "attacker_leader": "ENG", "defender_leader": "BUR",
		"attackers": ["ENG"], "defenders": ["BUR"], "battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": 89, "target_country": "BUR", "justification": "claim", "peace_cost": 0},
	}
	world.fleet_registry["fleet_eng"] = CampaignWorldStateScript.make_fleet_record("fleet_eng", "ENG", 87)
	world.fleet_registry["fleet_bur"] = CampaignWorldStateScript.make_fleet_record("fleet_bur", "BUR", 89)
	world.ship_registry["ship_eng"] = CampaignWorldStateScript.make_ship_record("ship_eng", "ENG", "fleet_eng", "war_galley", 0)
	world.ship_registry["ship_bur"] = CampaignWorldStateScript.make_ship_record("ship_bur", "BUR", "fleet_bur", "war_galley", 0)
	var fleet_eng := world.get_fleet("fleet_eng")
	fleet_eng["ship_ids"] = ["ship_eng"]
	fleet_eng["location_id"] = 87
	fleet_eng["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_BATTLE
	fleet_eng["battle_id"] = "battle_1"
	world.fleet_registry["fleet_eng"] = fleet_eng
	var fleet_bur := world.get_fleet("fleet_bur")
	fleet_bur["ship_ids"] = ["ship_bur"]
	fleet_bur["location_id"] = 87
	fleet_bur["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_BATTLE
	fleet_bur["battle_id"] = "battle_1"
	world.fleet_registry["fleet_bur"] = fleet_bur
	world.naval_battle_registry["battle_1"] = CampaignWorldStateScript.make_naval_battle_record("battle_1", "war_1", 87, world.current_day)
	var battle: Dictionary = world.naval_battle_registry["battle_1"]
	battle["attacker_fleets"] = ["fleet_eng"]
	battle["defender_fleets"] = ["fleet_bur"]
	world.naval_battle_registry["battle_1"] = battle
	world.blockaded_provinces[89] = 6000
	return world


func _run() -> void:
	var baseline := _make_populated_world()
	var baseline_save := baseline.to_save_dict("test")
	_require(int(baseline_save["schema_version"]) == CampaignWorldStateScript.SAVE_SCHEMA_VERSION, "the populated fixture itself must already be current-schema")
	_require(_make_populated_world().apply_save_dict(baseline_save).is_empty(), "the populated fixture must load cleanly before any migration is tested")

	# Schema 7 -> current: a pre-N4A save predates naval battles outright, so
	# it must migrate to an explicit empty naval_battle_registry (no battle
	# can exist in a save from before the concept did) while everything else
	# genuinely present in the old save - including this fixture's real
	# fleets, ships, and war - survives untouched.
	var schema_7 := baseline_save.duplicate(true)
	schema_7["schema_version"] = 7
	schema_7.erase("naval_battle_registry")
	schema_7.erase("blockaded_provinces")
	var migrated_from_7 := CampaignWorldStateScript.migrate_save_data(schema_7)
	_require(int(migrated_from_7["schema_version"]) == CampaignWorldStateScript.SAVE_SCHEMA_VERSION, "a schema 7 save must migrate to the current schema")
	_require((migrated_from_7["naval_battle_registry"] as Dictionary).is_empty(), "a migrated pre-N4A save must start with no naval battles")
	_require((migrated_from_7["blockaded_provinces"] as Dictionary).is_empty(), "a migrated pre-N4A save must also start with no blockaded provinces (schema 8 too)")
	_require(int(migrated_from_7.get("migrated_from_schema", -1)) == 7, "the migrated save must record its true original schema")
	_require((migrated_from_7["fleet_registry"] as Dictionary).size() == 2, "genuinely present pre-existing fleets must survive a schema 7 migration untouched")
	# A migrated save still names the two fleets with battle_id="battle_1" -
	# stale references to the now-erased battle - so it must be loaded onto
	# a target that first clears that stale field, exactly like every other
	# "old save referencing a concept younger than itself" case in this
	# migration chain (e.g. schema 6's transport_operation_id was never
	# retroactively cleared from armies either). Real save/load code paths
	# never produce this combination; only this fixture's copy-then-strip
	# construction does, so the fix belongs in the test fixture, not the
	# migration function.
	for raw_fleet_id in (migrated_from_7["fleet_registry"] as Dictionary):
		var fleet: Dictionary = migrated_from_7["fleet_registry"][raw_fleet_id]
		fleet["battle_id"] = ""
		fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
		migrated_from_7["fleet_registry"][raw_fleet_id] = fleet
	_require(_make_populated_world().apply_save_dict(migrated_from_7).is_empty(), "a schema 7 save migrated to current must load cleanly")

	# Schema 8 -> current: a pre-N5.1 save predates blockade-transition
	# tracking specifically, but already has naval battles (schema 7 content
	# is untouched) - only blockaded_provinces is force-reset.
	var schema_8 := baseline_save.duplicate(true)
	schema_8["schema_version"] = 8
	schema_8.erase("blockaded_provinces")
	var migrated_from_8 := CampaignWorldStateScript.migrate_save_data(schema_8)
	_require(int(migrated_from_8["schema_version"]) == CampaignWorldStateScript.SAVE_SCHEMA_VERSION, "a schema 8 save must migrate to the current schema")
	_require((migrated_from_8["blockaded_provinces"] as Dictionary).is_empty(), "a migrated pre-N5.1 save must start with no province recorded as blockaded")
	_require(int(migrated_from_8.get("migrated_from_schema", -1)) == 8, "the migrated save must record its true original schema")
	_require((migrated_from_8["naval_battle_registry"] as Dictionary).size() == 1, "a schema 8 migration must leave the already-present naval_battle_registry untouched")
	_require(_make_populated_world().apply_save_dict(migrated_from_8).is_empty(), "a schema 8 save migrated to current must load cleanly")

	# Full chain: a genuinely ancient schema-1 save (predating armies,
	# economy, characters, country depth, and every naval registry) must
	# migrate through all eight intermediate steps in one migrate_save_data()
	# call, not just the single adjacent step every other test in this suite
	# exercises. migrate_save_data()'s own steps are unconditional overwrites
	# ({} or recreated defaults), not merges, so an ancient save's real
	# owners are the only surviving input that matters - the rest of the
	# stripped garbage is irrelevant to the result, deliberately, mirroring
	# what a genuine 1444-vintage save missing every one of these concepts
	# actually contains.
	var schema_1 := {
		"schema_version": 1,
		"game_version": baseline_save["game_version"],
		"scenario_id": baseline_save["scenario_id"],
		"current_day": baseline_save["current_day"],
		"player_country": baseline_save["player_country"],
		"paused": baseline_save["paused"],
		"game_speed": baseline_save["game_speed"],
		"campaign_seed": baseline_save["campaign_seed"],
		"rng_stream_states": baseline_save["rng_stream_states"],
		"province_owners": baseline_save["province_owners"],
		"province_controllers": baseline_save["province_controllers"],
		"country_runtime_values": baseline_save["country_runtime_values"],
		"global_flags": {},
		"global_counters": {},
		"diplomatic_relations": {},
		"war_registry": {},
		"checksum": "",
	}
	var migrated_chain := CampaignWorldStateScript.migrate_save_data(schema_1)
	_require(int(migrated_chain["schema_version"]) == CampaignWorldStateScript.SAVE_SCHEMA_VERSION, "a schema 1 save must migrate all the way to the current schema in one call")
	_require(not (migrated_chain["army_registry"] as Dictionary).is_empty(), "schema 1->2 must recreate a default army for each owned country")
	for empty_registry in ["province_economy", "construction_registry", "recruitment_registry", "loan_registry", "character_registry", "dynasty_registry", "title_registry", "claim_registry", "subject_registry", "country_event_registry", "rebel_faction_registry", "fleet_registry", "ship_registry", "naval_construction_registry", "transport_operation_registry", "naval_battle_registry", "blockaded_provinces"]:
		_require((migrated_chain[empty_registry] as Dictionary).is_empty(), "schema 1 chain migration must leave %s as an explicit empty registry" % empty_registry)
	var chain_target := CampaignWorldStateScript.new()
	chain_target.initialize(OWNERS, NAMES)
	_require(chain_target.apply_save_dict(migrated_chain).is_empty(), "a fully chain-migrated schema 1 save must load cleanly onto a fresh matching world")

	# FL2.4 closure audit: mission and mission_target_ids were the two fleet
	# fields _validate_naval_data() never structurally checked on load, unlike
	# every other fleet field this same function already validates above.
	var corrupt_mission := baseline_save.duplicate(true)
	(corrupt_mission["fleet_registry"] as Dictionary)["fleet_eng"]["mission"] = "not_a_real_mission"
	_require(_make_populated_world().apply_save_dict(corrupt_mission).contains("mission"), "a fleet with an unknown mission must be rejected on load")

	var corrupt_target := baseline_save.duplicate(true)
	(corrupt_target["fleet_registry"] as Dictionary)["fleet_eng"]["mission_target_ids"] = [999999]
	_require(_make_populated_world().apply_save_dict(corrupt_target).contains("mission target"), "a fleet with a mission target referencing an unknown province must be rejected on load")

	print("Naval save schema migration test passed.")
	quit(0)
