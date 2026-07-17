class_name ShipDefinitions
extends RefCounted

## N2.1 ship-definition loader/validator. See docs/roadmap/naval/02_N2_FLEET_LOGISTICS.md
## "Ship Definitions": rejects negative values, missing successors, invalid
## technology tracks, circular upgrades, unknown family names, and
## impossible date ranges.

const DEFAULT_PATH := "res://assets/ship_definitions.json"
const VALID_TECHNOLOGY_TRACKS := ["administrative", "diplomatic", "military"]
const NON_NEGATIVE_INT_FIELDS := [
	"cost", "sailor_cost", "monthly_maintenance", "maximum_hull",
	"attack", "defence", "positioning_weight", "engagement_width",
	"retreat_contribution", "blockade_power", "transport_capacity", "supply_weight",
	"refund_bp", "required_harbour_level",
]

var _data: Dictionary = {}
var _error := ""


static func load_default() -> ShipDefinitions:
	var definitions := ShipDefinitions.new()
	definitions._load(DEFAULT_PATH)
	return definitions


static func from_data(data: Dictionary) -> ShipDefinitions:
	var definitions := ShipDefinitions.new()
	definitions._data = data.duplicate(true)
	definitions._error = definitions._validate()
	return definitions


func _load(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error = "Missing ship definitions: %s" % path
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_error = "Ship definitions are not a JSON object."
		return
	_data = parsed
	_error = _validate()


func _validate() -> String:
	if int(_data.get("version", 0)) != 1:
		return "Unsupported ship definition version."
	var families = _data.get("ship_families", null)
	var ships = _data.get("ships", null)
	if not families is Array or (families as Array).is_empty():
		return "Ship definitions need at least one ship family."
	if not ships is Dictionary or (ships as Dictionary).is_empty():
		return "Ship definitions need ships."
	var family_set := {}
	for raw_family in (families as Array):
		family_set[String(raw_family)] = true
	for raw_id in ships:
		var ship_id := String(raw_id)
		var record = ships[raw_id]
		if ship_id.is_empty() or not record is Dictionary:
			return "Invalid ship record %s." % ship_id
		var ship: Dictionary = record
		if String(ship.get("name", "")).is_empty():
			return "%s needs a name." % ship_id
		if not family_set.has(String(ship.get("family", ""))):
			return "%s has an unknown family." % ship_id
		var unlock_date = ship.get("unlock_date", null)
		if not unlock_date is Dictionary or not _valid_date_record(unlock_date):
			return "%s has an invalid unlock date." % ship_id
		var end_date = ship.get("end_date", null)
		if end_date != null:
			if not end_date is Dictionary or not _valid_date_record(end_date):
				return "%s has an invalid end date." % ship_id
			if not _date_before_or_equal(unlock_date, end_date):
				return "%s has an end date before its unlock date." % ship_id
		var technology = ship.get("required_technology", null)
		if not technology is Dictionary or String((technology as Dictionary).get("track", "")) not in VALID_TECHNOLOGY_TRACKS:
			return "%s has an invalid required technology track." % ship_id
		if int((technology as Dictionary).get("level", -1)) < 0:
			return "%s has a negative required technology level." % ship_id
		for field in NON_NEGATIVE_INT_FIELDS:
			if int(ship.get(field, -1)) < 0:
				return "%s has a negative %s." % [ship_id, field]
		if int(ship.get("construction_days", 0)) <= 0:
			return "%s must take a positive number of construction days." % ship_id
		if int(ship.get("maximum_hull", 0)) <= 0:
			return "%s must have positive maximum hull." % ship_id
		if int(ship.get("maximum_morale_bp", 0)) <= 0:
			return "%s must have positive maximum morale." % ship_id
		if int(ship.get("speed", 0)) <= 0:
			return "%s must have positive speed." % ship_id
		if int(ship.get("repair_rate_bp", -1)) < 0:
			return "%s has a negative repair rate." % ship_id
		var successor := String(ship.get("successor_id", ""))
		if not successor.is_empty() and not ships.has(successor):
			return "%s references an unknown successor %s." % [ship_id, successor]
	if _has_successor_cycle(ships):
		return "Ship successor chain contains a cycle."
	return ""


static func _valid_date_record(value: Dictionary) -> bool:
	var year := int(value.get("year", 0))
	var month := int(value.get("month", 0))
	var day := int(value.get("day", 0))
	if year < 1 or month < 1 or month > 12 or day < 1:
		return false
	var month_days := [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return day <= month_days[month - 1]


static func _date_before_or_equal(earlier: Dictionary, later: Dictionary) -> bool:
	var earlier_key := int(earlier.get("year", 0)) * 10000 + int(earlier.get("month", 0)) * 100 + int(earlier.get("day", 0))
	var later_key := int(later.get("year", 0)) * 10000 + int(later.get("month", 0)) * 100 + int(later.get("day", 0))
	return earlier_key <= later_key


static func _has_successor_cycle(ships: Dictionary) -> bool:
	for raw_id in ships:
		var current := String(raw_id)
		var seen := {}
		while not current.is_empty():
			if seen.has(current):
				return true
			seen[current] = true
			current = String((ships[current] as Dictionary).get("successor_id", ""))
	return false


func is_valid() -> bool:
	return _error.is_empty()


func error() -> String:
	return _error


func ship_families() -> Array:
	return (_data.get("ship_families", []) as Array).duplicate(true)


func has_ship(ship_id: String) -> bool:
	return (_data.get("ships", {}) as Dictionary).has(ship_id)


func ship(ship_id: String) -> Dictionary:
	return (_data.get("ships", {}) as Dictionary).get(ship_id, {}).duplicate(true)


func ship_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id in (_data.get("ships", {}) as Dictionary):
		ids.append(String(raw_id))
	ids.sort()
	return ids


## Ships whose unlock_date has passed and (if set) whose end_date has not,
## as of the given campaign day expressed as a date dictionary.
func unlocked_ship_ids(current_date: Dictionary) -> Array[String]:
	var current_key := int(current_date.get("year", 0)) * 10000 + int(current_date.get("month", 0)) * 100 + int(current_date.get("day", 0))
	var ids: Array[String] = []
	for ship_id in ship_ids():
		var record := ship(ship_id)
		var unlock: Dictionary = record["unlock_date"]
		var unlock_key := int(unlock.get("year", 0)) * 10000 + int(unlock.get("month", 0)) * 100 + int(unlock.get("day", 0))
		if current_key < unlock_key:
			continue
		var end_date = record.get("end_date", null)
		if end_date != null:
			var end: Dictionary = end_date
			var end_key := int(end.get("year", 0)) * 10000 + int(end.get("month", 0)) * 100 + int(end.get("day", 0))
			if current_key > end_key:
				continue
		ids.append(ship_id)
	return ids
