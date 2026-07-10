extends SceneTree

const DEFINITION_PATH := "res://assets/definition.csv"
const PROVINCE_MAP_PATH := "res://assets/provinces.bmp"
const GEOGRAPHY_MAP_PATH := "res://assets/colormap_water.png"
const OUTPUT_PATH := "res://docs/data/province_geography.csv"

# This strategy map uses a cropped Mercator-style projection, not a full
# pole-to-pole equirectangular projection. These constants are calibrated from
# stable control points at Stockholm, London, and Cairo in the province map.
const MERCATOR_EQUATOR_Y := 1343.856076
const MERCATOR_PIXELS_PER_UNIT := 796.164187


func _initialize() -> void:
	var definitions := _load_definitions()
	if definitions.is_empty():
		push_error("No province definitions were loaded.")
		quit(1)
		return

	var province_image := Image.load_from_file(PROVINCE_MAP_PATH)
	var geography_image := Image.load_from_file(GEOGRAPHY_MAP_PATH)
	if province_image == null or province_image.is_empty():
		push_error("Could not load %s" % PROVINCE_MAP_PATH)
		quit(1)
		return
	if geography_image == null or geography_image.is_empty():
		push_error("Could not load %s" % GEOGRAPHY_MAP_PATH)
		quit(1)
		return
	if province_image.get_width() % geography_image.get_width() != 0 or province_image.get_height() % geography_image.get_height() != 0:
		push_error("Province image dimensions must be an integer multiple of the geography image dimensions.")
		quit(1)
		return
	var geography_scale_x := province_image.get_width() / geography_image.get_width()
	var geography_scale_y := province_image.get_height() / geography_image.get_height()
	if geography_scale_x != geography_scale_y:
		push_error("Province and geography images must use the same horizontal and vertical scale.")
		quit(1)
		return

	province_image.convert(Image.FORMAT_RGB8)
	geography_image.convert(Image.FORMAT_RGB8)
	var max_id: int = definitions["max_id"]
	var color_to_id: Dictionary = definitions["color_to_id"]
	var names: Dictionary = definitions["names"]
	var width := province_image.get_width()
	var height := province_image.get_height()
	var pixel_count := width * height
	var province_bytes := province_image.get_data()
	var geography_bytes := geography_image.get_data()

	var counts := PackedInt64Array()
	var sum_x := PackedInt64Array()
	var sum_y := PackedInt64Array()
	var sum_r := PackedInt64Array()
	var sum_g := PackedInt64Array()
	var sum_b := PackedInt64Array()
	var luma_80 := PackedInt64Array()
	var luma_100 := PackedInt64Array()
	var luma_120 := PackedInt64Array()
	for values in [counts, sum_x, sum_y, sum_r, sum_g, sum_b, luma_80, luma_100, luma_120]:
		values.resize(max_id + 1)

	var x := 0
	var y := 0
	var unknown_pixels := 0
	for pixel_index in range(pixel_count):
		var byte_index := pixel_index * 3
		var key := (province_bytes[byte_index] << 16) | (province_bytes[byte_index + 1] << 8) | province_bytes[byte_index + 2]
		var province_id: int = color_to_id.get(key, -1)
		if province_id >= 0:
			var geography_x: int = x / geography_scale_x
			var geography_y: int = y / geography_scale_y
			var geography_index := (geography_y * geography_image.get_width() + geography_x) * 3
			var red: int = geography_bytes[geography_index]
			var green: int = geography_bytes[geography_index + 1]
			var blue: int = geography_bytes[geography_index + 2]
			var luma := (77 * red + 150 * green + 29 * blue) >> 8
			counts[province_id] += 1
			sum_x[province_id] += x
			sum_y[province_id] += y
			sum_r[province_id] += red
			sum_g[province_id] += green
			sum_b[province_id] += blue
			if luma >= 80:
				luma_80[province_id] += 1
			if luma >= 100:
				luma_100[province_id] += 1
			if luma >= 120:
				luma_120[province_id] += 1
		else:
			unknown_pixels += 1
		x += 1
		if x == width:
			x = 0
			y += 1

	var output_absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output_absolute.get_base_dir())
	var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		push_error("Could not write %s" % OUTPUT_PATH)
		quit(1)
		return

	output.store_csv_line(PackedStringArray([
		"province_id", "province_name", "pixel_count", "centroid_x", "centroid_y",
		"longitude", "latitude", "mean_red", "mean_green", "mean_blue",
		"luma_80_ratio", "luma_100_ratio", "luma_120_ratio"
	]))
	for province_id in range(max_id + 1):
		var count: int = counts[province_id]
		if count == 0:
			continue
		var centroid_x := float(sum_x[province_id]) / count
		var centroid_y := float(sum_y[province_id]) / count
		var longitude := centroid_x / width * 360.0 - 180.0
		var mercator_y := (MERCATOR_EQUATOR_Y - centroid_y) / MERCATOR_PIXELS_PER_UNIT
		var latitude := rad_to_deg(2.0 * atan(exp(mercator_y)) - PI / 2.0)
		output.store_csv_line(PackedStringArray([
			str(province_id), str(names.get(province_id, "")), str(count),
			"%.3f" % centroid_x, "%.3f" % centroid_y,
			"%.5f" % longitude, "%.5f" % latitude,
			"%.3f" % (float(sum_r[province_id]) / count),
			"%.3f" % (float(sum_g[province_id]) / count),
			"%.3f" % (float(sum_b[province_id]) / count),
			"%.6f" % (float(luma_80[province_id]) / count),
			"%.6f" % (float(luma_100[province_id]) / count),
			"%.6f" % (float(luma_120[province_id]) / count),
		]))
	output.close()
	print("Wrote geography audit for %d definitions to %s (%d unknown pixels)." % [names.size(), OUTPUT_PATH, unknown_pixels])
	quit(0)


func _load_definitions() -> Dictionary:
	var file := FileAccess.open(DEFINITION_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not load %s" % DEFINITION_PATH)
		return {}
	var content := file.get_buffer(file.get_length()).get_string_from_ascii()
	var color_to_id := {}
	var names := {}
	var max_id := 0
	var is_header := true
	for line in content.split("\n"):
		var fields := line.strip_edges().split(";")
		if is_header:
			is_header = false
			continue
		if fields.size() < 5 or not fields[0].is_valid_int():
			continue
		var province_id := fields[0].to_int()
		var red := fields[1].to_int()
		var green := fields[2].to_int()
		var blue := fields[3].to_int()
		var key := (red << 16) | (green << 8) | blue
		color_to_id[key] = province_id
		names[province_id] = fields[4]
		max_id = maxi(max_id, province_id)
	return {
		"color_to_id": color_to_id,
		"names": names,
		"max_id": max_id,
	}
