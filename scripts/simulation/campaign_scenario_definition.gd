class_name CampaignScenarioDefinition
extends RefCounted

var _scenario_id := ""
var _province_initial_owners: Dictionary = {}
var _country_names: Dictionary = {}
var _initial_subjects: Array[Dictionary] = []
var _error := ""


func initialize_from_country_registry(
		country_data: CountryData,
		country_registry,
		p_scenario_id: String
) -> void:
	_scenario_id = p_scenario_id
	_error = ""
	_province_initial_owners.clear()
	_initial_subjects.clear()
	_country_names = country_registry.country_names()
	var province_ids := country_data.province_id_to_owner.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var imported_owner := String(country_data.province_id_to_owner[raw_province_id])
		if imported_owner.is_empty() or imported_owner in ["No Owner", "Ocean"]:
			_province_initial_owners[province_id] = ""
		elif _country_names.has(imported_owner):
			_province_initial_owners[province_id] = imported_owner
		else:
			_error = "Province %d references unknown imported owner %s." % [province_id, imported_owner]
			return
	_load_initial_relations()


func _load_initial_relations() -> void:
	var path := "res://assets/%s_relations.json" % _scenario_id
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error = "Could not open scenario relation data %s." % path
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_error = "Scenario relation data %s is not a JSON object." % path
		return
	var data: Dictionary = parsed
	if int(data.get("schema_version", 0)) != 1:
		_error = "Scenario relation data %s uses an unsupported schema version." % path
		return
	if String(data.get("scenario_id", "")) != _scenario_id:
		_error = "Scenario relation data %s targets a different scenario." % path
		return
	var seen_subjects := {}
	for raw_record in data.get("initial_subjects", []):
		if not raw_record is Dictionary:
			_error = "Scenario relation data %s contains a non-object subject record." % path
			return
		var record: Dictionary = raw_record
		var overlord := String(record.get("overlord", ""))
		var subject := String(record.get("subject", ""))
		var subject_type := String(record.get("type", ""))
		var presentation := String(record.get("presentation", ""))
		if not _country_names.has(overlord) or not _country_names.has(subject) or overlord == subject:
			_error = "Scenario subject relation %s -> %s references invalid countries." % [overlord, subject]
			return
		if subject_type not in ["vassal", "personal_union"]:
			_error = "Scenario subject relation %s -> %s has invalid type %s." % [overlord, subject, subject_type]
			return
		if presentation not in ["", "appanage", "personal_union", "colonial_subject", "vassal"]:
			_error = "Scenario subject relation %s -> %s has invalid presentation %s." % [overlord, subject, presentation]
			return
		if seen_subjects.has(subject):
			_error = "Scenario subject %s has more than one initial overlord." % subject
			return
		seen_subjects[subject] = true
		_initial_subjects.append({
			"overlord": overlord,
			"subject": subject,
			"type": subject_type,
			"presentation": presentation,
		})
	_initial_subjects.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return "%s|%s" % [first["overlord"], first["subject"]] < "%s|%s" % [second["overlord"], second["subject"]]
	)


func is_valid() -> bool:
	return _error.is_empty()


func error() -> String:
	return _error


func scenario_id() -> String:
	return _scenario_id


func province_initial_owners() -> Dictionary:
	return _province_initial_owners.duplicate()


func country_names() -> Dictionary:
	return _country_names.duplicate()


func initial_subjects() -> Array[Dictionary]:
	return _initial_subjects.duplicate(true)


func has_province(province_id: int) -> bool:
	return _province_initial_owners.has(province_id)


func has_country(country_tag: String) -> bool:
	return _country_names.has(country_tag)
