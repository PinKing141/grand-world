extends SceneTree

const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Ship definitions test failed: %s" % message)
		quit(1)


func _base_ship() -> Dictionary:
	return {
		"name": "Test Ship", "localisation_key": "ship_test", "family": "light",
		"unlock_date": {"year": 1444, "month": 1, "day": 1}, "end_date": null,
		"required_technology": {"track": "military", "level": 0},
		"cost": 1000, "construction_days": 10, "sailor_cost": 10, "monthly_maintenance": 10,
		"maximum_hull": 100, "maximum_morale_bp": 10000,
		"attack": 1, "defence": 1, "speed": 1, "positioning_weight": 1, "engagement_width": 1,
		"retreat_contribution": 1, "blockade_power": 1, "transport_capacity": 0, "supply_weight": 1,
		"repair_rate_bp": 100, "coastal_modifier_bp": 0, "inland_sea_modifier_bp": 0,
		"successor_id": "", "refund_bp": 5000, "required_harbour_level": 1, "required_shipyard": false,
	}


func _run() -> void:
	var definitions := ShipDefinitionsScript.load_default()
	_require(definitions.is_valid(), "baked ship definitions must load: %s" % definitions.error())

	var families := definitions.ship_families()
	for expected in ["heavy", "light", "galley", "transport"]:
		_require(families.has(expected), "the four required ship families must be present: missing %s" % expected)

	_require(definitions.has_ship("war_galley"), "war_galley must exist")
	_require(definitions.has_ship("heavy_galleon"), "heavy_galleon must exist")
	_require(definitions.has_ship("heavy_ship_of_the_line"), "heavy_ship_of_the_line must exist")
	_require(definitions.has_ship("transport_cog"), "transport_cog must exist")
	_require(String(definitions.ship("heavy_galleon")["successor_id"]) == "heavy_ship_of_the_line", "heavy_galleon must upgrade to the ship of the line")
	_require(int(definitions.ship("transport_cog")["transport_capacity"]) > 0, "the transport family must carry transport capacity")

	var ship_ids := definitions.ship_ids()
	for i in range(1, ship_ids.size()):
		_require(ship_ids[i - 1] < ship_ids[i], "ship_ids must be sorted ascending")

	var unlocked_1444 := definitions.unlocked_ship_ids({"year": 1444, "month": 1, "day": 1})
	_require(unlocked_1444.has("war_galley") and unlocked_1444.has("transport_cog"), "1444 must unlock the baseline ships")
	_require(not unlocked_1444.has("heavy_ship_of_the_line"), "the ship of the line must not be unlocked in 1444")
	var unlocked_1444_late := definitions.unlocked_ship_ids({"year": 1600, "month": 1, "day": 2})
	_require(unlocked_1444_late.has("heavy_ship_of_the_line"), "the ship of the line must unlock from 1600 onward")
	var unlocked_after_galleon_retires := definitions.unlocked_ship_ids({"year": 1650, "month": 1, "day": 2})
	_require(not unlocked_after_galleon_retires.has("heavy_galleon"), "the heavy galleon must retire after its end_date")

	# Malformed-data rejection (N2A "reject negative values, missing
	# successors, invalid technology tracks, circular upgrades, unknown
	# family names, and impossible date ranges").
	var missing_sections := ShipDefinitionsScript.from_data({"version": 1})
	_require(not missing_sections.is_valid(), "definitions with no families/ships must be rejected")

	var negative_cost := _base_ship()
	negative_cost["cost"] = -1
	var negative_result := ShipDefinitionsScript.from_data({"version": 1, "ship_families": ["light"], "ships": {"x": negative_cost}})
	_require(not negative_result.is_valid(), "a negative cost must be rejected")

	var unknown_family := _base_ship()
	unknown_family["family"] = "submarine"
	var family_result := ShipDefinitionsScript.from_data({"version": 1, "ship_families": ["light"], "ships": {"x": unknown_family}})
	_require(not family_result.is_valid(), "an unknown family must be rejected")

	var bad_track := _base_ship()
	bad_track["required_technology"] = {"track": "naval", "level": 0}
	var track_result := ShipDefinitionsScript.from_data({"version": 1, "ship_families": ["light"], "ships": {"x": bad_track}})
	_require(not track_result.is_valid(), "an invalid technology track must be rejected")

	var missing_successor := _base_ship()
	missing_successor["successor_id"] = "does_not_exist"
	var successor_result := ShipDefinitionsScript.from_data({"version": 1, "ship_families": ["light"], "ships": {"x": missing_successor}})
	_require(not successor_result.is_valid(), "a missing successor reference must be rejected")

	var cycle_a := _base_ship()
	cycle_a["successor_id"] = "b"
	var cycle_b := _base_ship()
	cycle_b["successor_id"] = "a"
	var cycle_result := ShipDefinitionsScript.from_data({"version": 1, "ship_families": ["light"], "ships": {"a": cycle_a, "b": cycle_b}})
	_require(not cycle_result.is_valid(), "a circular successor chain must be rejected")

	var bad_dates := _base_ship()
	bad_dates["unlock_date"] = {"year": 1500, "month": 1, "day": 1}
	bad_dates["end_date"] = {"year": 1400, "month": 1, "day": 1}
	var date_result := ShipDefinitionsScript.from_data({"version": 1, "ship_families": ["light"], "ships": {"x": bad_dates}})
	_require(not date_result.is_valid(), "an end date before the unlock date must be rejected")

	print("Ship definitions test passed. families=%d ships=%d unlocked_1444=%d" % [families.size(), ship_ids.size(), unlocked_1444.size()])
	quit(0)
