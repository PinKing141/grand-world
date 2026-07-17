class_name NavalDefinitions
extends RefCounted

## N1.1 data-audit definitions: sea-zone classification and port candidates
## baked by tools/naval/build_naval_graph_data.py from assets/province_graph.json.
## This is a definitions loader only - no pathfinding, access, or fleet logic.
## See docs/roadmap/naval/01_N1_MARITIME_GRAPH_AUTHORITY.md.

const DEFAULT_PATH := "res://assets/naval_definitions.json"
const VALID_CLASSIFICATIONS := ["coastal_sea", "inland_sea", "open_ocean", "closed_water"]

var _data: Dictionary = {}
var _error := ""


static func load_default() -> NavalDefinitions:
	var definitions := NavalDefinitions.new()
	definitions._load(DEFAULT_PATH)
	return definitions


static func from_data(data: Dictionary) -> NavalDefinitions:
	var definitions := NavalDefinitions.new()
	definitions._data = data.duplicate(true)
	definitions._error = definitions._validate()
	return definitions


func _load(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error = "Missing naval definitions: %s" % path
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_error = "Naval definitions are not a JSON object."
		return
	_data = parsed
	_error = _validate()


func _validate() -> String:
	if int(_data.get("version", 0)) != 1:
		return "Unsupported naval definition version."
	var sea_zones = _data.get("sea_zones", null)
	var ports = _data.get("ports", null)
	if not sea_zones is Dictionary or (sea_zones as Dictionary).is_empty():
		return "Naval definitions need sea zones."
	if not ports is Dictionary or (ports as Dictionary).is_empty():
		return "Naval definitions need ports."
	for raw_id in sea_zones:
		var zone_id := String(raw_id)
		var record = sea_zones[raw_id]
		if zone_id.is_empty() or not record is Dictionary:
			return "Invalid sea zone record %s." % zone_id
		var zone: Dictionary = record
		if String(zone.get("classification", "")) not in VALID_CLASSIFICATIONS:
			return "Sea zone %s has an invalid classification." % zone_id
	for raw_id in ports:
		var port_id := String(raw_id)
		var record = ports[raw_id]
		if port_id.is_empty() or not record is Dictionary:
			return "Invalid port record %s." % port_id
		var port: Dictionary = record
		var sea_exits: Array = port.get("sea_exits", [])
		if sea_exits.is_empty():
			return "Port %s has no sea exits." % port_id
		if not port.has("primary_exit") or not sea_exits.has(port["primary_exit"]):
			return "Port %s primary_exit is not one of its own sea exits." % port_id
		var primary_exit_id := str(int(port["primary_exit"]))
		if not sea_zones.has(primary_exit_id):
			return "Port %s references an unknown sea zone %s." % [port_id, primary_exit_id]
	return ""


func is_valid() -> bool:
	return _error.is_empty()


func error() -> String:
	return _error


func is_sea_zone(province_id: int) -> bool:
	return (_data.get("sea_zones", {}) as Dictionary).has(str(province_id))


func sea_zone(province_id: int) -> Dictionary:
	return (_data.get("sea_zones", {}) as Dictionary).get(str(province_id), {}).duplicate(true)


func sea_zone_ids() -> Array[int]:
	var ids: Array[int] = []
	for raw_id in (_data.get("sea_zones", {}) as Dictionary):
		ids.append(int(raw_id))
	ids.sort()
	return ids


func is_port(province_id: int) -> bool:
	return (_data.get("ports", {}) as Dictionary).has(str(province_id))


func port(province_id: int) -> Dictionary:
	return (_data.get("ports", {}) as Dictionary).get(str(province_id), {}).duplicate(true)


func port_ids() -> Array[int]:
	var ids: Array[int] = []
	for raw_id in (_data.get("ports", {}) as Dictionary):
		ids.append(int(raw_id))
	ids.sort()
	return ids


func enabled_port_ids() -> Array[int]:
	var ids: Array[int] = []
	var ports: Dictionary = _data.get("ports", {})
	for raw_id in ports:
		if bool((ports[raw_id] as Dictionary).get("enabled", false)):
			ids.append(int(raw_id))
	ids.sort()
	return ids


func graph_content_hash() -> String:
	return String(_data.get("graph_content_hash", ""))
