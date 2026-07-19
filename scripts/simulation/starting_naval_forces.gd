class_name StartingNavalForces
extends RefCounted

const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

const VALID_REVIEW_STATUSES := ["approved placeholder", "approved historical"]

var _data: Dictionary = {}
var _error := ""


static func load_for_scenario(scenario_id: String):
	var content = new()
	content._load("res://assets/%s_naval_forces.json" % scenario_id, scenario_id)
	return content


func _load(path: String, scenario_id: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error = "Could not open starting naval content %s." % path
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_error = "Starting naval content is not a JSON object."
		return
	_data = parsed
	_error = _validate(scenario_id)


func _validate(scenario_id: String) -> String:
	if _data.is_empty():
		return ""
	if int(_data.get("schema_version", 0)) != 1 or String(_data.get("scenario_id", "")) != scenario_id:
		return "Starting naval content has the wrong schema or scenario."
	var graph := MaritimeGraphScript.load_default()
	var definitions := ShipDefinitionsScript.load_default()
	var seen_fleets := {}
	for raw_record in _data.get("fleets", []):
		if not raw_record is Dictionary:
			return "Starting naval content contains a non-object fleet."
		var record: Dictionary = raw_record
		var fleet_id := String(record.get("fleet_id", ""))
		var country := String(record.get("country_tag", ""))
		var port_id := int(record.get("home_port_id", -1))
		if fleet_id.is_empty() or country.is_empty() or seen_fleets.has(fleet_id):
			return "Starting naval content has a duplicate or incomplete fleet ID."
		seen_fleets[fleet_id] = true
		if not graph.is_port_province(port_id) or not graph.is_port_enabled(port_id):
			return "Starting fleet %s has an invalid home port." % fleet_id
		var ships: Array = record.get("ships", [])
		if ships.is_empty():
			return "Starting fleet %s has no ships." % fleet_id
		for raw_definition_id in ships:
			if not definitions.has_ship(String(raw_definition_id)):
				return "Starting fleet %s has an unknown ship definition." % fleet_id
		var provenance = record.get("provenance", null)
		if not provenance is Dictionary:
			return "Starting fleet %s has no provenance." % fleet_id
		for field in ["source", "evidence_class", "confidence", "reviewer", "review_date", "review_status", "note"]:
			if String((provenance as Dictionary).get(field, "")).is_empty():
				return "Starting fleet %s has incomplete provenance." % fleet_id
		if String((provenance as Dictionary).get("review_status", "")) not in VALID_REVIEW_STATUSES:
			return "Starting fleet %s is not approved for use." % fleet_id
	return ""


func is_valid() -> bool:
	return _error.is_empty()


func error() -> String:
	return _error


func fleets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_record in _data.get("fleets", []):
		result.append((raw_record as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("fleet_id", "")) < String(b.get("fleet_id", "")))
	return result


func initialize_world(world: CampaignWorldState) -> String:
	if not is_valid():
		return _error
	if not world.fleet_registry.is_empty() or not world.ship_registry.is_empty():
		return ""
	var graph := MaritimeGraphScript.load_default()
	var definitions := ShipDefinitionsScript.load_default()
	for record in fleets():
		var fleet_id := String(record["fleet_id"])
		var country := String(record["country_tag"])
		var port_id := int(record["home_port_id"])
		if not world.has_country(country):
			return "Starting fleet %s references a country absent from the scenario." % fleet_id
		# Focused controller tests reuse the production scenario ID with a tiny
		# synthetic ownership map (for example Sweden/Denmark only). Registry
		# country names still exist there, but countries with no scenario
		# territory are deliberately out of scope and receive no starting force.
		if world.get_country_provinces(country).is_empty():
			continue
		if world.get_province_owner(port_id) != country or world.get_province_controller(port_id) != country:
			return "Starting fleet %s is not based in an owned and controlled port." % fleet_id
		if not graph.is_port_enabled(port_id):
			return "Starting fleet %s uses a disabled port." % fleet_id
		var fleet := CampaignWorldState.make_fleet_record(fleet_id, country, port_id)
		fleet["display_name"] = String(record.get("display_name", fleet_id))
		fleet["mission"] = String(record.get("mission", "none"))
		fleet["mission_started_day"] = world.current_day
		var ship_ids: Array = []
		var ship_index := 1
		for raw_definition_id in (record.get("ships", []) as Array):
			var ship_id := "%s_ship_%02d" % [fleet_id, ship_index]
			world.ship_registry[ship_id] = CampaignWorldState.make_ship_record(ship_id, country, fleet_id, String(raw_definition_id), world.current_day)
			ship_ids.append(ship_id)
			ship_index += 1
		fleet["ship_ids"] = ship_ids
		world.fleet_registry[fleet_id] = fleet
		FleetSystemScript.recompute_aggregate(world, fleet_id, definitions)
		var runtime := world.country_runtime(country)
		runtime["naval_ai_controlled"] = true
		world.set_country_runtime(country, runtime)
	world.global_flags["starting_naval_content_status"] = String(_data.get("content_status", ""))
	return ""
