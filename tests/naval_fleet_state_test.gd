extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")

const CALAIS := 87
const KENT := 235


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval fleet state test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "ENG"},
		{"ENG": "England"},
		"naval_fleet_state_test",
		14441111
	)
	return world


func _add_fleet_with_ships(world: CampaignWorldState, fleet_id: String, ship_ids: Array) -> void:
	var fleet := CampaignWorldStateScript.make_fleet_record(fleet_id, "ENG", CALAIS)
	fleet["ship_ids"] = ship_ids.duplicate()
	world.fleet_registry[fleet_id] = fleet
	for ship_id in ship_ids:
		world.ship_registry[String(ship_id)] = CampaignWorldStateScript.make_ship_record(String(ship_id), "ENG", fleet_id, "war_galley", 0)


func _run() -> void:
	var world := _make_world()
	_add_fleet_with_ships(world, "f_1", ["s_1", "s_2"])

	# Registry accessors.
	_require(world.get_fleet("f_1")["fleet_id"] == "f_1", "get_fleet must return the stored record")
	_require(world.get_ship("s_1")["fleet_id"] == "f_1", "get_ship must return the stored record")
	_require(world.country_fleets("ENG") == ["f_1"], "country_fleets must find England's fleet")
	var members := world.fleet_ships("f_1")
	_require(members.size() == 2 and members[0] == "s_1" and members[1] == "s_2", "fleet_ships must return sorted membership")
	_require(
		String(CampaignWorldStateScript.make_fleet_record("x", "ENG", CALAIS)["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_DOCKED,
		"a freshly constructed fleet must start docked at its home port"
	)

	# Save/load round trip preserves fleets, ships, and the checksum.
	var saved := world.to_save_dict("test")
	var checksum_before := world.checksum()
	var reloaded := _make_world()
	_add_fleet_with_ships(reloaded, "f_1", ["s_1", "s_2"])
	var apply_error := reloaded.apply_save_dict(saved)
	_require(apply_error.is_empty(), "a valid naval save must apply cleanly: %s" % apply_error)
	_require(reloaded.checksum() == checksum_before, "reloading a save must reproduce an identical checksum")
	_require(reloaded.get_fleet("f_1")["home_port_id"] == CALAIS, "reloaded fleet data must match")
	_require(reloaded.fleet_ships("f_1").size() == 2, "reloaded fleet must keep both ships")

	# Corruption rejection: orphan ship (fleet_id points nowhere).
	var orphan_save := world.to_save_dict("test")
	(orphan_save["ship_registry"] as Dictionary)["s_orphan"] = CampaignWorldStateScript.make_ship_record("s_orphan", "ENG", "f_missing", "war_galley", 0)
	_require(not _make_world().apply_save_dict(orphan_save).is_empty(), "an orphan ship referencing a missing fleet must be rejected")

	# Corruption rejection: non-reciprocal membership (ship says it belongs to
	# f_1, but f_1's own ship_ids does not list it).
	var non_reciprocal_save := world.to_save_dict("test")
	var broken_fleet: Dictionary = (non_reciprocal_save["fleet_registry"] as Dictionary)["f_1"]
	broken_fleet["ship_ids"] = ["s_1"]
	(non_reciprocal_save["fleet_registry"] as Dictionary)["f_1"] = broken_fleet
	_require(not _make_world().apply_save_dict(non_reciprocal_save).is_empty(), "non-reciprocal fleet/ship membership must be rejected")

	# Corruption rejection: duplicate ship listed twice in one fleet.
	var duplicate_save := world.to_save_dict("test")
	var duplicate_fleet: Dictionary = (duplicate_save["fleet_registry"] as Dictionary)["f_1"]
	duplicate_fleet["ship_ids"] = ["s_1", "s_1", "s_2"]
	(duplicate_save["fleet_registry"] as Dictionary)["f_1"] = duplicate_fleet
	_require(not _make_world().apply_save_dict(duplicate_save).is_empty(), "a ship listed twice in one fleet must be rejected")

	# Corruption rejection: unknown owner country.
	var unknown_owner_save := world.to_save_dict("test")
	var foreign_fleet: Dictionary = (unknown_owner_save["fleet_registry"] as Dictionary)["f_1"]
	foreign_fleet["owner_country_id"] = "ZZZ"
	(unknown_owner_save["fleet_registry"] as Dictionary)["f_1"] = foreign_fleet
	_require(not _make_world().apply_save_dict(unknown_owner_save).is_empty(), "a fleet owned by an unknown country must be rejected")

	# Schema migration: a pre-naval (schema 5) save must migrate to schema 6
	# with empty, valid naval registries.
	var legacy := saved.duplicate(true)
	legacy["schema_version"] = 5
	legacy.erase("fleet_registry")
	legacy.erase("ship_registry")
	legacy.erase("naval_construction_registry")
	var migrated := CampaignWorldStateScript.migrate_save_data(legacy)
	_require(int(migrated["schema_version"]) == CampaignWorldStateScript.SAVE_SCHEMA_VERSION, "schema 5 saves must migrate to the current schema")
	_require((migrated["fleet_registry"] as Dictionary).is_empty(), "migrated pre-naval saves must start with no fleets")
	_require((migrated["ship_registry"] as Dictionary).is_empty(), "migrated pre-naval saves must start with no ships")
	var migrated_world := _make_world()
	_require(migrated_world.apply_save_dict(migrated).is_empty(), "a migrated schema-5 save must apply cleanly with empty naval registries")

	print("Naval fleet state test passed. schema=%d fleets=%d ships=%d" % [CampaignWorldStateScript.SAVE_SCHEMA_VERSION, world.fleet_registry.size(), world.ship_registry.size()])
	quit(0)
