extends SceneTree

const OUTPUT_PATH := "res://assets/generated/country_data_runtime_cache.json"


func _initialize() -> void:
	var country_data := CountryData.new()
	country_data.provinces_folder = "res://assets/provinces"
	country_data.countries_folder = "res://assets/countries"
	country_data.countries_color_folder = "res://assets/country_colors"
	country_data.parse_all_files()

	var payload := {
		"version": 1,
		"country_id_to_country_name": _string_map(country_data.country_id_to_country_name),
		"country_name_to_color": _color_map(country_data.country_name_to_color),
		"country_id_to_color": _color_map(country_data.country_id_to_color),
		"province_id_to_owner": _string_map(country_data.province_id_to_owner),
		"province_id_to_name": _string_map(country_data.province_id_to_name),
		"terrain_colors": _color_map(country_data.terrain_colors),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/generated"))
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write country runtime cache: %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(payload, "\t", false, true))
	file.close()
	print(
		"COUNTRY DATA CACHE BUILT: %d countries, %d province owners" % [
			country_data.country_id_to_country_name.size(),
			country_data.province_id_to_owner.size(),
		]
	)
	country_data.free()
	quit(0)


func _string_map(source: Dictionary) -> Dictionary:
	var result := {}
	var keys := source.keys()
	keys.sort()
	for raw_key in keys:
		result[str(raw_key)] = str(source[raw_key])
	return result


func _color_map(source: Dictionary) -> Dictionary:
	var result := {}
	var keys := source.keys()
	keys.sort()
	for raw_key in keys:
		var color: Color = source[raw_key]
		result[str(raw_key)] = color.to_html(true)
	return result
