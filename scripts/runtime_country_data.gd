extends CountryData

## Runtime adapter for the map editor's native CountryData node.
##
## The native base class reparses thousands of source text files from _ready(),
## which blocks the main thread during normal game startup. Runtime builds load a
## single generated cache instead. parse_all_files() remains available to editor
## tools, and tools/runtime_data/build_country_data_cache.gd rebuilds this cache
## with the addon's canonical parser whenever source data changes.
const CACHE_PATH := "res://assets/generated/country_data_runtime_cache.json"


func _ready() -> void:
	var file := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if file == null:
		push_error("Country runtime cache is missing: %s" % CACHE_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1:
		push_error("Country runtime cache is invalid or unsupported: %s" % CACHE_PATH)
		return
	_load_string_map(country_id_to_country_name, parsed.get("country_id_to_country_name", {}))
	_load_color_map(country_name_to_color, parsed.get("country_name_to_color", {}))
	_load_color_map(country_id_to_color, parsed.get("country_id_to_color", {}))
	_load_int_string_map(province_id_to_owner, parsed.get("province_id_to_owner", {}))
	_load_int_string_map(province_id_to_name, parsed.get("province_id_to_name", {}))
	_load_color_map(terrain_colors, parsed.get("terrain_colors", {}))


func _load_string_map(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	for raw_key in source:
		target[String(raw_key)] = String(source[raw_key])


func _load_int_string_map(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	for raw_key in source:
		target[int(raw_key)] = String(source[raw_key])


func _load_color_map(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	for raw_key in source:
		target[String(raw_key)] = Color.from_string(String(source[raw_key]), Color.TRANSPARENT)
