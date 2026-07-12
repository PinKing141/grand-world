class_name AIDefinitions
extends RefCounted

const DEFAULT_PATH := "res://assets/ai_definitions.json"

var _data: Dictionary = {}
var _error := ""


static func load_default() -> AIDefinitions:
	var definitions := AIDefinitions.new()
	definitions._load(DEFAULT_PATH)
	return definitions


static func from_data(data: Dictionary) -> AIDefinitions:
	var definitions := AIDefinitions.new()
	definitions._data = data.duplicate(true)
	definitions._error = definitions._validate()
	return definitions


func _load(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error = "Missing AI definitions: %s" % path
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_error = "AI definitions are not a JSON object."
		return
	_data = parsed
	_error = _validate()


func _validate() -> String:
	if int(_data.get("version", 0)) != 1:
		return "Unsupported AI definition version."
	if String(_data.get("slice_id", "")).is_empty():
		return "The AI slice needs a stable ID."
	if int(_data.get("end_day", 0)) <= int(_data.get("start_day", -1)):
		return "The AI slice end day must be after its start day."
	var countries = _data.get("countries", null)
	if not countries is Dictionary or (countries as Dictionary).is_empty():
		return "The AI slice needs country profiles."
	var seen_slots := {}
	for raw_tag in (countries as Dictionary):
		var tag := String(raw_tag)
		var profile = countries[raw_tag]
		if tag.length() != 3 or not profile is Dictionary:
			return "Invalid AI country profile: %s." % tag
		var slot := int((profile as Dictionary).get("slot", -1))
		if slot < 0 or seen_slots.has(slot):
			return "AI schedule slots must be unique non-negative integers."
		seen_slots[slot] = tag
		if int((profile as Dictionary).get("capital_province_id", -1)) < 0:
			return "%s needs a capital province." % tag
		if String((profile as Dictionary).get("strategy", "")).is_empty():
			return "%s needs a strategy." % tag
		if String((profile as Dictionary).get("objective", "")).is_empty():
			return "%s needs a campaign objective." % tag
		if String((profile as Dictionary).get("government", "")).is_empty() or String((profile as Dictionary).get("ruler", "")).is_empty():
			return "%s needs representative government and ruler content." % tag
	for raw_tag in countries:
		var profile: Dictionary = countries[raw_tag]
		for reference_field in ["preferred_targets", "preferred_allies"]:
			for raw_reference in profile.get(reference_field, []):
				if not countries.has(String(raw_reference)):
					return "%s references unknown AI country %s." % [String(raw_tag), String(raw_reference)]
	return ""


func is_valid() -> bool:
	return _error.is_empty()


func error() -> String:
	return _error


func slice_id() -> String:
	return String(_data.get("slice_id", ""))


func end_day() -> int:
	return int(_data.get("end_day", 7305))


func country_tags() -> Array[String]:
	var tags: Array[String] = []
	for raw_tag in (_data.get("countries", {}) as Dictionary):
		tags.append(String(raw_tag))
	tags.sort()
	return tags


func profile(country_tag: String) -> Dictionary:
	return ((_data.get("countries", {}) as Dictionary).get(country_tag, {}) as Dictionary).duplicate(true)


func initial_relationships() -> Array:
	return (_data.get("initial_relationships", []) as Array).duplicate(true)
