extends SceneTree

const NavalDefinitionsScript = preload("res://scripts/simulation/naval_definitions.gd")

# N0.3 Channel fixture.
const CALAIS := 87
const KENT := 235
const PICARDIE := 89
const STRAITS_OF_DOVER := 1271
const THE_CHANNEL := 1272

# N0.3 Iberian fixture.
const ALGARVE := 230
const CADIZ := 1749
const BARCELONA := 213
const STRAITS_OF_GIBRALTAR := 1293

# A body of water this project's geography audit expects to be non-navigable.
const CLOSED_WATER_SAMPLE_COUNT_MINIMUM := 1


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval definitions test failed: %s" % message)
		quit(1)


func _run() -> void:
	var definitions := NavalDefinitionsScript.load_default()
	_require(definitions.is_valid(), "baked naval definitions must load: %s" % definitions.error())

	_require(definitions.is_sea_zone(STRAITS_OF_DOVER), "Straits of Dover must be a sea zone")
	_require(definitions.is_sea_zone(STRAITS_OF_GIBRALTAR), "Straits of Gibraltar must be a sea zone")
	_require(
		String(definitions.sea_zone(STRAITS_OF_DOVER)["classification"]) == "coastal_sea",
		"Straits of Dover must be classified coastal_sea"
	)
	_require(
		String(definitions.sea_zone(STRAITS_OF_GIBRALTAR)["classification"]) == "coastal_sea",
		"Straits of Gibraltar must be classified coastal_sea"
	)

	_require(definitions.is_port(CALAIS), "Calais must be a port candidate")
	_require(definitions.is_port(KENT), "Kent must be a port candidate")
	_require(definitions.is_port(PICARDIE), "Picardie must be a port candidate")
	_require(definitions.is_port(ALGARVE), "Algarve must be a port candidate")
	_require(definitions.is_port(CADIZ), "Cadiz must be a port candidate")
	_require(definitions.is_port(BARCELONA), "Barcelona must be a port candidate")

	var calais: Dictionary = definitions.port(CALAIS)
	_require(bool(calais["enabled"]), "Calais fixture port must be enabled")
	var calais_sea_exits: Array = calais["sea_exits"]
	var calais_primary_exit := int(calais["primary_exit"])
	var calais_exit_matched := false
	for raw_exit in calais_sea_exits:
		if int(raw_exit) == calais_primary_exit:
			calais_exit_matched = true
	_require(calais_exit_matched, "Calais primary exit must be one of its own sea exits")

	var picardie: Dictionary = definitions.port(PICARDIE)
	_require(int(picardie["primary_exit"]) == STRAITS_OF_DOVER, "Picardie's fixture primary exit must be the Straits of Dover")
	_require(
		String((picardie["provenance"] as Dictionary).get("confidence", "")) == "placeholder-reviewed",
		"Picardie must carry the N0.3 reviewed provenance"
	)

	var sea_zone_ids := definitions.sea_zone_ids()
	_require(sea_zone_ids.size() > 0 and sea_zone_ids[0] <= sea_zone_ids[sea_zone_ids.size() - 1], "sea_zone_ids must be sorted ascending")
	var port_ids := definitions.port_ids()
	_require(port_ids.size() > 0 and port_ids[0] <= port_ids[port_ids.size() - 1], "port_ids must be sorted ascending")
	_require(definitions.enabled_port_ids().size() <= port_ids.size(), "enabled ports cannot exceed total port candidates")

	var closed_water_found := 0
	for zone_id in sea_zone_ids:
		if String(definitions.sea_zone(zone_id)["classification"]) == "closed_water":
			closed_water_found += 1
	_require(closed_water_found >= CLOSED_WATER_SAMPLE_COUNT_MINIMUM, "at least one closed_water (non-navigable) sea zone must be detected")

	_require(not definitions.graph_content_hash().is_empty(), "naval definitions must record the source graph content hash")

	# Malformed-data rejection (N1E graph malformed-data coverage).
	var missing_sections := NavalDefinitionsScript.from_data({"version": 1})
	_require(not missing_sections.is_valid(), "definitions with no sea_zones/ports must be rejected")

	var bad_classification := NavalDefinitionsScript.from_data({
		"version": 1,
		"sea_zones": {"1271": {"classification": "lava_sea"}},
		"ports": {"87": {"sea_exits": [1271], "primary_exit": 1271}},
	})
	_require(not bad_classification.is_valid(), "an unknown sea-zone classification must be rejected")

	var dangling_primary_exit := NavalDefinitionsScript.from_data({
		"version": 1,
		"sea_zones": {"1271": {"classification": "coastal_sea"}},
		"ports": {"87": {"sea_exits": [1271, 9999999], "primary_exit": 9999999}},
	})
	_require(not dangling_primary_exit.is_valid(), "a port referencing an unknown sea zone must be rejected")

	print("Naval definitions test passed. sea_zones=%d ports=%d closed_water=%d" % [sea_zone_ids.size(), port_ids.size(), closed_water_found])
	quit(0)
