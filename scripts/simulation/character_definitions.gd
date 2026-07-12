class_name CharacterDefinitions
extends RefCounted

const DEFAULT_PATH := "res://assets/character_definitions.json"
const VALID_RANKS := ["barony", "county", "duchy", "kingdom", "empire"]
const VALID_SEXES := ["male", "female"]

var _data: Dictionary = {}
var _error := ""


static func load_default() -> CharacterDefinitions:
	var definitions := CharacterDefinitions.new()
	definitions._load(DEFAULT_PATH)
	return definitions


static func from_data(data: Dictionary) -> CharacterDefinitions:
	var definitions := CharacterDefinitions.new()
	definitions._data = data.duplicate(true)
	definitions._error = definitions._validate()
	return definitions


func _load(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error = "Missing character definitions: %s" % path
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_error = "Character definitions are not a JSON object."
		return
	_data = parsed
	_error = _validate()


func _validate() -> String:
	if int(_data.get("version", 0)) != 1:
		return "Unsupported character definition version."
	var characters = _data.get("characters", null)
	var dynasties = _data.get("dynasties", null)
	var titles = _data.get("titles", null)
	var rulers = _data.get("country_rulers", null)
	var claims = _data.get("claims", {})
	if not characters is Dictionary or (characters as Dictionary).is_empty():
		return "Character definitions need characters."
	if not dynasties is Dictionary or (dynasties as Dictionary).is_empty():
		return "Character definitions need dynasties."
	if not titles is Dictionary or (titles as Dictionary).is_empty():
		return "Character definitions need titles."
	if not rulers is Dictionary or (rulers as Dictionary).is_empty() or not claims is Dictionary:
		return "Character definitions need ruler and claim dictionaries."
	for raw_id in characters:
		var character_id := String(raw_id)
		var record = characters[raw_id]
		if character_id.is_empty() or not record is Dictionary:
			return "Invalid character record %s." % character_id
		var character: Dictionary = record
		if String(character.get("name", "")).is_empty() or String(character.get("sex", "")) not in VALID_SEXES:
			return "%s needs a name and valid sex." % character_id
		var birth = character.get("birth", null)
		if not birth is Dictionary or not _valid_date_record(birth):
			return "%s has an invalid birth date." % character_id
		if not dynasties.has(String(character.get("dynasty_id", ""))):
			return "%s references an unknown dynasty." % character_id
		for reference_field in ["father_id", "mother_id", "spouse_id"]:
			var reference := String(character.get(reference_field, ""))
			if not reference.is_empty() and not characters.has(reference):
				return "%s references unknown %s %s." % [character_id, reference_field, reference]
		for raw_child in character.get("children", []):
			if not characters.has(String(raw_child)):
				return "%s references unknown child %s." % [character_id, String(raw_child)]
		var spouse := String(character.get("spouse_id", ""))
		if not spouse.is_empty() and String((characters[spouse] as Dictionary).get("spouse_id", "")) != character_id:
			return "%s and %s do not have a symmetric marriage." % [character_id, spouse]
	if _has_ancestry_cycle(characters):
		return "Character ancestry contains a cycle."
	for raw_id in dynasties:
		var founder := String((dynasties[raw_id] as Dictionary).get("founder_id", ""))
		if not founder.is_empty() and not characters.has(founder):
			return "Dynasty %s has an unknown founder." % String(raw_id)
	for raw_id in titles:
		var title: Dictionary = titles[raw_id]
		if String(title.get("rank", "")) not in VALID_RANKS or not characters.has(String(title.get("holder_id", ""))):
			return "Title %s has an invalid rank or holder." % String(raw_id)
		var liege := String(title.get("liege_title_id", ""))
		if not liege.is_empty() and not titles.has(liege):
			return "Title %s has an unknown liege." % String(raw_id)
	if _has_title_cycle(titles):
		return "Title hierarchy contains a cycle."
	for raw_tag in rulers:
		var assignment: Dictionary = rulers[raw_tag]
		if not characters.has(String(assignment.get("ruler_id", ""))) or not titles.has(String(assignment.get("primary_title_id", ""))):
			return "%s has an invalid ruler or primary title." % String(raw_tag)
		var heir := String(assignment.get("heir_id", ""))
		if not heir.is_empty() and not characters.has(heir):
			return "%s has an invalid heir." % String(raw_tag)
	for raw_id in claims:
		var claim: Dictionary = claims[raw_id]
		if not characters.has(String(claim.get("claimant_id", ""))) or not titles.has(String(claim.get("title_id", ""))):
			return "Claim %s has an invalid claimant or title." % String(raw_id)
	return ""


func is_valid() -> bool:
	return _error.is_empty()


func error() -> String:
	return _error


func characters() -> Dictionary:
	return (_data.get("characters", {}) as Dictionary).duplicate(true)


func dynasties() -> Dictionary:
	return (_data.get("dynasties", {}) as Dictionary).duplicate(true)


func titles() -> Dictionary:
	return (_data.get("titles", {}) as Dictionary).duplicate(true)


func claims() -> Dictionary:
	return (_data.get("claims", {}) as Dictionary).duplicate(true)


func country_rulers() -> Dictionary:
	return (_data.get("country_rulers", {}) as Dictionary).duplicate(true)


static func _valid_date_record(value: Dictionary) -> bool:
	var year := int(value.get("year", 0))
	var month := int(value.get("month", 0))
	var day := int(value.get("day", 0))
	if year < 1 or month < 1 or month > 12 or day < 1:
		return false
	var month_days := [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return day <= month_days[month - 1]


static func _has_ancestry_cycle(characters: Dictionary) -> bool:
	for raw_id in characters:
		var seen := {}
		var stack: Array[String] = [String(raw_id)]
		while not stack.is_empty():
			var current: String = stack.pop_back()
			if seen.has(current):
				return true
			seen[current] = true
			var record: Dictionary = characters[current]
			for field in ["father_id", "mother_id"]:
				var parent := String(record.get(field, ""))
				if not parent.is_empty():
					stack.append(parent)
	return false


static func _has_title_cycle(titles: Dictionary) -> bool:
	for raw_id in titles:
		var current := String(raw_id)
		var seen := {}
		while not current.is_empty():
			if seen.has(current):
				return true
			seen[current] = true
			current = String((titles[current] as Dictionary).get("liege_title_id", ""))
	return false
