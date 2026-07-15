class_name CountryRegistry
extends RefCounted

## Runtime view of the generated canonical country identity registry.
##
## The Python build gate performs source hashes and manifest coverage checks.
## Runtime validation repeats the structural/reference checks required for a
## safe packaged campaign bootstrap.

const REGISTRY_PATH := "res://assets/country_registry.json"
const SCHEMA_VERSION := 1

var _data: Dictionary = {}
var _error := ""


func load_registry(path := REGISTRY_PATH):
	_load(path)
	return self


func _load(path: String) -> void:
	_data.clear()
	_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error = "missing file %s" % path
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		_error = "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return
	if not json.data is Dictionary:
		_error = "registry root must be a dictionary"
		return
	_data = json.data
	_error = _validate()


func _validate() -> String:
	if int(_data.get("schema_version", 0)) != SCHEMA_VERSION:
		return "expected schema version %d" % SCHEMA_VERSION
	var countries: Dictionary = _data.get("countries", {})
	var pseudo_countries: Dictionary = _data.get("pseudo_countries", {})
	var localisation: Dictionary = (_data.get("localisation", {}) as Dictionary).get("en", {})
	if countries.is_empty():
		return "countries must be a non-empty dictionary"
	if localisation.is_empty():
		return "English country localisation must be a non-empty dictionary"
	if int((_data.get("metadata", {}) as Dictionary).get("country_count", -1)) != countries.size():
		return "metadata country count does not match the registry"

	var tag_pattern := RegEx.new()
	if tag_pattern.compile("^[A-Z0-9]{3}$") != OK:
		return "internal tag validation pattern failed"
	var names_to_tags: Dictionary = {}
	var tags := countries.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		if tag_pattern.search(tag) == null:
			return "invalid country tag %s" % tag
		if pseudo_countries.has(tag):
			return "country %s is also registered as a pseudo-country" % tag
		var definition: Dictionary = countries[raw_tag]
		var display_name := String(definition.get("display_name", ""))
		if display_name.is_empty() or display_name != display_name.strip_edges():
			return "country %s has an empty or padded display name" % tag
		for field in ["name_key", "adjective_key"]:
			var key := String(definition.get(field, ""))
			if key.is_empty() or not localisation.has(key) or String(localisation[key]).is_empty():
				return "country %s has unresolved localisation field %s" % [tag, field]
		if not bool(definition.get("scenario_country", false)):
			return "country %s is not marked as a scenario country" % tag
		var colour: Array = definition.get("colour_rgb8", [])
		if colour.size() != 3:
			return "country %s has invalid colour_rgb8" % tag
		for component in colour:
			if int(component) < 0 or int(component) > 255:
				return "country %s has an out-of-range colour component" % tag
		for field in ["country_history_path", "colour_path"]:
			var source_path := String(definition.get(field, ""))
			if not _is_canonical_resource_path(source_path):
				return "country %s source path is not canonical: %s" % [tag, source_path]
		if not names_to_tags.has(display_name):
			names_to_tags[display_name] = []
		(names_to_tags[display_name] as Array).append(tag)

	var actual_collisions: Dictionary = {}
	for raw_name in names_to_tags:
		var collision_tags: Array = names_to_tags[raw_name]
		if collision_tags.size() > 1:
			collision_tags.sort()
			actual_collisions[String(raw_name)] = collision_tags
	var approved: Dictionary = _data.get("approved_name_collisions", {})
	if actual_collisions.size() != approved.size():
		return "display-name collision exceptions do not match the registry"
	for raw_name in actual_collisions:
		if not approved.has(raw_name):
			return "unapproved display-name collision: %s" % String(raw_name)
		var approved_tags: Array = ((approved[raw_name] as Dictionary).get("tags", []) as Array).duplicate()
		approved_tags.sort()
		if approved_tags != actual_collisions[raw_name]:
			return "stale display-name collision exception: %s" % String(raw_name)

	for raw_id in pseudo_countries:
		var pseudo_id := String(raw_id)
		var definition: Dictionary = pseudo_countries[raw_id]
		if countries.has(pseudo_id):
			return "pseudo-country %s is also a scenario country" % pseudo_id
		if bool(definition.get("scenario_country", true)) or bool(definition.get("selectable", true)):
			return "pseudo-country %s must be non-scenario and non-selectable" % pseudo_id
		for field in ["name_key", "adjective_key"]:
			var key := String(definition.get(field, ""))
			if key.is_empty() or not localisation.has(key):
				return "pseudo-country %s has unresolved localisation field %s" % [pseudo_id, field]
	return ""


func _is_canonical_resource_path(path: String) -> bool:
	if path.is_empty() or path != path.strip_edges() or not path.begins_with("res://"):
		return false
	var relative := path.trim_prefix("res://")
	return (
		not relative.is_empty()
		and not relative.begins_with("/")
		and not relative.ends_with("/")
		and not relative.contains("\\")
		and not relative.contains("//")
		and not relative.split("/").has(".")
		and not relative.split("/").has("..")
	)


func is_valid() -> bool:
	return _error.is_empty()


func error() -> String:
	return _error


func country_count() -> int:
	return (_data.get("countries", {}) as Dictionary).size()


func country_tags() -> Array[String]:
	var result: Array[String] = []
	for raw_tag in (_data.get("countries", {}) as Dictionary).keys():
		result.append(String(raw_tag))
	result.sort()
	return result


func has_country(tag: String) -> bool:
	return (_data.get("countries", {}) as Dictionary).has(tag)


func country_definition(tag: String) -> Dictionary:
	return ((_data.get("countries", {}) as Dictionary).get(tag, {}) as Dictionary).duplicate(true)


func country_names() -> Dictionary:
	var result := {}
	for tag in country_tags():
		result[tag] = String(((_data["countries"] as Dictionary)[tag] as Dictionary).get("display_name", tag))
	return result


func display_name(tag: String) -> String:
	var countries: Dictionary = _data.get("countries", {})
	if countries.has(tag):
		return String((countries[tag] as Dictionary).get("display_name", tag))
	var pseudo: Dictionary = _data.get("pseudo_countries", {})
	return String((pseudo.get(tag, {}) as Dictionary).get("display_name", tag))


func localize(key: String, locale := "en") -> String:
	var locales: Dictionary = _data.get("localisation", {})
	var table: Dictionary = locales.get(locale, locales.get("en", {}))
	return String(table.get(key, key))


func _definition_colour(definition: Dictionary) -> Color:
	if definition.has("colour_rgb8"):
		var rgb: Array = definition["colour_rgb8"]
		return Color(float(rgb[0]) / 255.0, float(rgb[1]) / 255.0, float(rgb[2]) / 255.0, 1.0)
	var rgba: Array = definition.get("colour_rgba", [0.5, 0.5, 0.5, 1.0])
	if rgba.size() != 4:
		return Color.GRAY
	return Color(float(rgba[0]), float(rgba[1]), float(rgba[2]), float(rgba[3]))


func country_colour(tag: String) -> Color:
	var countries: Dictionary = _data.get("countries", {})
	if countries.has(tag):
		return _definition_colour(countries[tag])
	var pseudo: Dictionary = _data.get("pseudo_countries", {})
	if pseudo.has(tag):
		return _definition_colour(pseudo[tag])
	return Color.GRAY


func sync_presentation_country_data(country_data: CountryData) -> void:
	# CountryData is a native map-addon type. Keep its presentation dictionaries
	# as generated mirrors while the campaign consumes this registry directly.
	var id_to_name: Dictionary = country_data.country_id_to_country_name
	var id_to_colour: Dictionary = country_data.country_id_to_color
	var name_to_colour: Dictionary = country_data.country_name_to_color
	id_to_name.clear()
	id_to_colour.clear()
	name_to_colour.clear()
	var countries: Dictionary = _data.get("countries", {})
	for tag in country_tags():
		var definition: Dictionary = countries[tag]
		var display_name := String(definition["display_name"])
		var colour := _definition_colour(definition)
		id_to_name[tag] = display_name
		id_to_colour[tag] = colour
		name_to_colour[display_name] = colour
	var pseudo: Dictionary = _data.get("pseudo_countries", {})
	var pseudo_ids := pseudo.keys()
	pseudo_ids.sort()
	for raw_id in pseudo_ids:
		var pseudo_id := String(raw_id)
		var definition: Dictionary = pseudo[raw_id]
		var display_name := String(definition["display_name"])
		var colour := _definition_colour(definition)
		id_to_name[pseudo_id] = display_name
		id_to_colour[pseudo_id] = colour
		name_to_colour[display_name] = colour
