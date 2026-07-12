class_name CountryDepthDefinitions
extends RefCounted

const DEFAULT_PATH := "res://assets/country_depth_definitions.json"
const TECHNOLOGY_TRACKS := ["administrative", "diplomatic", "military"]
const SUPPORTED_EFFECTS := ["authority", "centralisation", "conversion_speed", "country_modifier", "form_country", "province_unrest", "stability", "tolerance_heathen", "treasury"]

var _data: Dictionary = {}
var _error := ""
static var _default_instance: CountryDepthDefinitions


static func load_default() -> CountryDepthDefinitions:
	if _default_instance == null:
		_default_instance = CountryDepthDefinitions.new()
		_default_instance._load(DEFAULT_PATH)
	return _default_instance


static func from_data(data: Dictionary) -> CountryDepthDefinitions:
	var definitions := CountryDepthDefinitions.new()
	definitions._data = data.duplicate(true)
	definitions._error = definitions._validate()
	return definitions


func _load(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error = "Missing country-depth definitions: %s" % path
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_error = "Country-depth definitions are not a JSON object."
		return
	_data = parsed
	_error = _validate()


func _validate() -> String:
	if int(_data.get("version", 0)) != 1 or String(_data.get("content_version", "")).is_empty():
		return "Country-depth definitions need supported schema and content versions."
	var localisation = _data.get("localisation", null)
	var governments = _data.get("governments", null)
	var reforms = _data.get("reforms", null)
	var cultures = _data.get("cultures", null)
	var religions = _data.get("religions", null)
	var technology = _data.get("technology", null)
	var ideas = _data.get("idea_groups", null)
	var countries = _data.get("countries", null)
	var provinces = _data.get("provinces", null)
	var events = _data.get("events", null)
	var decisions = _data.get("decisions", null)
	for pair in [["localisation", localisation], ["governments", governments], ["reforms", reforms], ["cultures", cultures], ["religions", religions], ["technology", technology], ["idea groups", ideas], ["countries", countries], ["provinces", provinces], ["events", events], ["decisions", decisions]]:
		if not pair[1] is Dictionary or (pair[1] as Dictionary).is_empty():
			return "Country-depth definitions need %s." % String(pair[0])
	for raw_id in governments:
		var government: Dictionary = governments[raw_id]
		if not localisation.has(String(government.get("name_key", ""))):
			return "Government %s has missing localisation." % String(raw_id)
		for raw_reform in government.get("reforms", []):
			if not reforms.has(String(raw_reform)):
				return "Government %s references unknown reform %s." % [String(raw_id), String(raw_reform)]
	for raw_id in reforms:
		if not localisation.has(String((reforms[raw_id] as Dictionary).get("name_key", ""))):
			return "Reform %s has missing localisation." % String(raw_id)
	for track in TECHNOLOGY_TRACKS:
		if not technology.has(track):
			return "Technology is missing the %s track." % track
		var levels: Array = (technology[track] as Dictionary).get("levels", [])
		if levels.is_empty():
			return "%s technology needs levels." % track.capitalize()
		for index in range(levels.size()):
			if int((levels[index] as Dictionary).get("level", -1)) != index:
				return "%s technology levels must be contiguous from zero." % track.capitalize()
	for raw_id in ideas:
		if not localisation.has(String((ideas[raw_id] as Dictionary).get("name_key", ""))):
			return "Idea group %s has missing localisation." % String(raw_id)
	for raw_tag in countries:
		var country: Dictionary = countries[raw_tag]
		if not governments.has(String(country.get("government", ""))) or not cultures.has(String(country.get("primary_culture", ""))) or not religions.has(String(country.get("state_religion", ""))):
			return "%s has invalid government, culture, or religion references." % String(raw_tag)
		if String(country.get("provenance", "")).is_empty():
			return "%s needs historical provenance notes." % String(raw_tag)
		for raw_culture in country.get("accepted_cultures", []):
			if not cultures.has(String(raw_culture)):
				return "%s accepts unknown culture %s." % [String(raw_tag), String(raw_culture)]
	for raw_id in provinces:
		var province: Dictionary = provinces[raw_id]
		if int(String(raw_id)) <= 0 or not cultures.has(String(province.get("culture", ""))) or not religions.has(String(province.get("religion", ""))):
			return "Province %s has invalid ID, culture, or religion." % String(raw_id)
		if String(province.get("provenance", "")).is_empty():
			return "Province %s needs historical provenance notes." % String(raw_id)
	for collection in [events, decisions]:
		for raw_id in collection:
			var definition: Dictionary = collection[raw_id]
			if not localisation.has(String(definition.get("title_key", definition.get("name_key", "")))):
				return "%s has missing localisation." % String(raw_id)
			var options: Array = definition.get("options", [])
			for raw_option in options:
				if not localisation.has(String((raw_option as Dictionary).get("text_key", ""))):
					return "%s has an event option with missing localisation." % String(raw_id)
			var effect_groups: Array = [definition.get("effects", [])] if options.is_empty() else options.map(func(option): return (option as Dictionary).get("effects", []))
			for raw_effects in effect_groups:
				for raw_effect in raw_effects:
					if String((raw_effect as Dictionary).get("type", "")) not in SUPPORTED_EFFECTS:
						return "%s uses unsupported effect %s." % [String(raw_id), String((raw_effect as Dictionary).get("type", ""))]
	return ""


func is_valid() -> bool:
	return _error.is_empty()


func error() -> String:
	return _error


func content_version() -> String:
	return String(_data.get("content_version", ""))


func localize(key: String) -> String:
	return String((_data.get("localisation", {}) as Dictionary).get(key, "[%s]" % key))


func government(id: String) -> Dictionary:
	return ((_data.get("governments", {}) as Dictionary).get(id, {}) as Dictionary).duplicate(true)


func reform(id: String) -> Dictionary:
	return ((_data.get("reforms", {}) as Dictionary).get(id, {}) as Dictionary).duplicate(true)


func cultures() -> Dictionary:
	return (_data.get("cultures", {}) as Dictionary).duplicate(true)


func religions() -> Dictionary:
	return (_data.get("religions", {}) as Dictionary).duplicate(true)


func technology_track(id: String) -> Dictionary:
	return ((_data.get("technology", {}) as Dictionary).get(id, {}) as Dictionary).duplicate(true)


func idea_group(id: String) -> Dictionary:
	return ((_data.get("idea_groups", {}) as Dictionary).get(id, {}) as Dictionary).duplicate(true)


func idea_groups() -> Dictionary:
	return (_data.get("idea_groups", {}) as Dictionary).duplicate(true)


func governments() -> Dictionary:
	return (_data.get("governments", {}) as Dictionary).duplicate(true)


func country(tag: String) -> Dictionary:
	return ((_data.get("countries", {}) as Dictionary).get(tag, {}) as Dictionary).duplicate(true)


func country_tags() -> Array[String]:
	var tags: Array[String] = []
	for raw_tag in (_data.get("countries", {}) as Dictionary):
		tags.append(String(raw_tag))
	tags.sort()
	return tags


func province(id: int) -> Dictionary:
	return ((_data.get("provinces", {}) as Dictionary).get(str(id), {}) as Dictionary).duplicate(true)


func event(id: String) -> Dictionary:
	return ((_data.get("events", {}) as Dictionary).get(id, {}) as Dictionary).duplicate(true)


func events() -> Dictionary:
	return (_data.get("events", {}) as Dictionary).duplicate(true)


func decision(id: String) -> Dictionary:
	return ((_data.get("decisions", {}) as Dictionary).get(id, {}) as Dictionary).duplicate(true)


func decisions() -> Dictionary:
	return (_data.get("decisions", {}) as Dictionary).duplicate(true)
