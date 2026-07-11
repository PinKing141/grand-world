extends ComputeHelper
@export_group("Sub Viewports")
@export var country_field: SubViewport
@export var province_field: SubViewport
@export var output: SubViewport

@export_group("Data")
@export var map_data: MapData
@export var country_data: CountryData
@export var province_selector: ProvinceSelector
@export var province_map: Texture2D

@export_group("Texture & Shader Configuration")
@export var color_map_size: Vector2i
@export_file var lookup_path_shader = "res://shaders/generate_color_lookup.glsl"
@export_file var color_path_shader = "res://shaders/generate_color_map.glsl"
@export_file var mask_political_path_shader = "res://shaders/mask_political_map.glsl"


@export_group("Debugging & Profiling")
@export var profiler_enabled := true
@export var save_images_to_file := true
@export var use_prebaked_map_textures := true
@export var debug_ownership_editing_enabled := false
@export var debug_owner_tag := ""
@export_file var lookup_save_path = "res://assets/color_lookup_map.png"
@export_file var color_map_save_path = "res://assets/color_map.png"
@export_file var mask_political_save_path = "res://assets/mask_political_map.png"


# Update the viewport materials
var output_material: ShaderMaterial
var distance_material: ShaderMaterial
var province_material: ShaderMaterial
var final_material: ShaderMaterial


# Cached variables
var color_lookup: Image
var color_map: Image
var color_texture: ImageTexture
var political_map: Image
var political_color_map: Image
var display_uses_political_colors := true

# Presentation-only interaction state. Authoritative state arrives in Phase 2.
var hovered_province_id := -1
var selected_province_id := -1
var selected_country := ""
var is_political = true
# Rudimentary profiling
func time_function(function_name: String, callable: Callable):
	if not profiler_enabled:
		return callable.call()
	
	var start = Time.get_ticks_usec()
	var result = callable.call()
	var time_ms = (Time.get_ticks_usec() - start) / 1000.0
	print("[%s] %.2f ms" % [function_name, time_ms])
	return result

func update_material_dynamic_parameters(parameter_name, parameter_variant):
		output_material.set_shader_parameter(parameter_name, parameter_variant)
		distance_material.set_shader_parameter(parameter_name, parameter_variant)
func update_material_static_parameters(parameter_name, parameter_variant):
		province_material.set_shader_parameter(parameter_name, parameter_variant)
func update_viewports_dynamic():
		country_field.render_target_update_mode = SubViewport.UPDATE_ONCE
		country_field.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		
		await RenderingServer.frame_post_draw
		output.render_target_update_mode = SubViewport.UPDATE_ONCE
		output.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE


func update_color_map(province_id, new_color):
	var witdh = color_map.get_width()
	var x = province_id % witdh
	var y = floori(float(province_id) / witdh)
	if political_color_map != null:
		political_color_map.set_pixel(x, y, new_color)
	if display_uses_political_colors:
		color_map.set_pixel(x, y, new_color)
	color_texture.update(color_map)
	update_material_dynamic_parameters("color_map", color_texture)
	update_viewports_dynamic()


func apply_world_state_owners(province_owners: Dictionary) -> void:
	# WorldState is authoritative. Rebuild the presentation LUT in one batch so
	# loading a campaign never triggers thousands of GPU updates.
	if color_map == null or color_map.is_empty() or color_texture == null:
		return
	var width := color_map.get_width()
	var province_ids := province_owners.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		if province_id < 0 or province_id >= color_map.get_width() * color_map.get_height():
			continue
		var owner := String(province_owners[raw_province_id])
		var owner_color: Color = country_data.country_id_to_color.get(owner, Color(0.0, 0.0, 0.0, 0.0))
		if political_color_map != null:
			political_color_map.set_pixel(province_id % width, floori(float(province_id) / width), owner_color)
		if display_uses_political_colors:
			color_map.set_pixel(province_id % width, floori(float(province_id) / width), owner_color)
	color_texture.update(color_map)
	update_material_dynamic_parameters("color_map", color_texture)
	update_viewports_dynamic()


func apply_economy_heatmap(values: Dictionary) -> void:
	if political_color_map == null or color_texture == null:
		return
	display_uses_political_colors = false
	color_map = _copy_image(political_color_map)
	var maximum := 0.0
	for raw_value in values.values():
		maximum = maxf(maximum, float(raw_value))
	var width := color_map.get_width()
	var ids := values.keys()
	ids.sort()
	for raw_id in ids:
		var province_id := int(raw_id)
		if province_id < 0 or province_id >= color_map.get_width() * color_map.get_height():
			continue
		var normalized := clampf(float(values[raw_id]) / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
		var heat := Color(0.16, 0.22, 0.34).lerp(Color(0.95, 0.77, 0.18), sqrt(normalized))
		color_map.set_pixel(province_id % width, floori(float(province_id) / width), heat)
	color_texture.update(color_map)
	update_material_dynamic_parameters("color_map", color_texture)
	final_material.set_shader_parameter("map_mode", 0)
	clear_country_highlight()
	update_viewports_dynamic()


func restore_political_map() -> void:
	if political_color_map == null or color_texture == null:
		return
	display_uses_political_colors = true
	color_map = _copy_image(political_color_map)
	color_texture.update(color_map)
	update_material_dynamic_parameters("color_map", color_texture)
	update_viewports_dynamic()


func _copy_image(source: Image) -> Image:
	return Image.create_from_data(source.get_width(), source.get_height(), source.has_mipmaps(), source.get_format(), source.get_data())

	
func _ready():
	province_selector.province_image = province_map.get_image()
	# Initialize compute helper
	create_rd()
	set_output_texture_size(province_map.get_size())
	
	# Get viewport materials to update at runtime
	var output_color: ColorRect = output.get_node("Output")
	output_material = output_color.material
	
	var distance_color: ColorRect = country_field.get_node("Output")
	distance_material = distance_color.material
	
	var province_output: ColorRect = province_field.get_node("Output")
	province_material = province_output.material
	final_material = province_selector.province_map.material_override as ShaderMaterial
	
	
	# Godot 4.7 can crash in the addon's compute path on some drivers/headless runs.
	# Production uses deterministic prebaked textures; compute generation remains an
	# opt-in editor fallback for map topology work.
	if not use_prebaked_map_textures or not load_prebaked_map_textures():
		create_lookup_texture()
		create_color_map_texture()
		create_political_map_mask_texture()
	if political_color_map == null and color_map != null:
		political_color_map = _copy_image(color_map)

	province_selector.province_hovered.connect(_on_province_hovered)
	province_selector.province_hover_cleared.connect(_on_province_hover_cleared)
	province_selector.province_selected.connect(_on_province_selected)
	province_selector.selection_cleared.connect(_on_selection_cleared)
	final_material.set_shader_parameter("hover_enabled", false)
	final_material.set_shader_parameter("selection_enabled", false)
	final_material.set_shader_parameter("country_selection_enabled", false)
	final_material.set_shader_parameter("map_mode", 0)

	province_field.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	update_viewports_dynamic()
		
		

func load_prebaked_map_textures() -> bool:
	var lookup_resource := load(lookup_save_path) as Texture2D
	var color_resource := load(color_map_save_path) as Texture2D
	var mask_resource := load(mask_political_save_path) as Texture2D
	if lookup_resource == null or color_resource == null or mask_resource == null:
		push_warning("Prebaked map textures are missing; falling back to compute generation.")
		return false

	color_lookup = lookup_resource.get_image()
	color_map = color_resource.get_image()
	political_map = mask_resource.get_image()
	if color_lookup == null or color_map == null or political_map == null:
		push_warning("A prebaked map texture could not be read; falling back to compute generation.")
		return false

	color_texture = ImageTexture.create_from_image(color_map)
	political_color_map = _copy_image(color_map)
	final_material.set_shader_parameter("lookup_map", lookup_resource)
	distance_material.set_shader_parameter("lookup_map", lookup_resource)
	distance_material.set_shader_parameter("color_map", color_texture)
	province_material.set_shader_parameter("lookup_map", lookup_resource)
	province_material.set_shader_parameter("mask_map", mask_resource)
	return true

func _province_lookup_coordinate(province_id: int) -> Vector2:
	var lookup_x := province_id % 256
	var lookup_y := floori(float(province_id) / 256.0)
	return Vector2(float(lookup_x) / 255.0, float(lookup_y) / 255.0)


func _on_province_hovered(info: Dictionary, _screen_position: Vector2) -> void:
	var province_id: int = info["province_id"]
	if province_id == hovered_province_id:
		return
	hovered_province_id = province_id
	final_material.set_shader_parameter("hovered_province", _province_lookup_coordinate(province_id))
	final_material.set_shader_parameter("hover_enabled", true)


func _on_province_hover_cleared() -> void:
	if hovered_province_id < 0:
		return
	hovered_province_id = -1
	final_material.set_shader_parameter("hover_enabled", false)


func _on_province_selected(info: Dictionary) -> void:
	selected_province_id = info["province_id"]
	selected_country = info["owner_tag"]
	final_material.set_shader_parameter("selected_province", _province_lookup_coordinate(selected_province_id))
	final_material.set_shader_parameter("selection_enabled", true)
	if info.get("is_playable", false):
		highlight_country(selected_country)
	else:
		clear_country_highlight()


func _on_selection_cleared() -> void:
	selected_province_id = -1
	selected_country = ""
	final_material.set_shader_parameter("selection_enabled", false)
	clear_country_highlight()


func highlight_country(tag: String) -> void:
	# The final shader matches territory by the country's political colour in
	# the subviewport image, so no per-province state is required.
	if not country_data.country_id_to_color.has(tag):
		clear_country_highlight()
		return
	var color: Color = country_data.country_id_to_color[tag]
	final_material.set_shader_parameter("selected_country_color", Color(color.r, color.g, color.b, 1.0))
	final_material.set_shader_parameter("country_selection_enabled", true)


func clear_country_highlight() -> void:
	final_material.set_shader_parameter("country_selection_enabled", false)


func set_map_mode(mode: int) -> void:
	# 0 = political, 1 = terrain, 2 = debug province IDs. A uniform switch on
	# the final material: no distance-field or political texture rebuilds.
	final_material.set_shader_parameter("map_mode", clampi(mode, 0, 2))
	is_political = mode == 0


func debug_change_selected_province_owner() -> bool:
	if not debug_ownership_editing_enabled:
		push_warning("Ownership editing is disabled outside explicit debug mode.")
		return false
	if selected_province_id < 0 or debug_owner_tag.is_empty():
		return false
	if not country_data.country_id_to_color.has(debug_owner_tag):
		push_warning("Unknown debug owner tag: %s" % debug_owner_tag)
		return false
	country_data.province_id_to_owner[selected_province_id] = debug_owner_tag
	call_deferred("update_color_map", selected_province_id, country_data.country_id_to_color[debug_owner_tag])
	return true

func colors_equal(a: Color, b: Color, tolerance = 0.01):
	return (abs(a.r - b.r) < tolerance &&
			abs(a.g - b.g) < tolerance &&
			abs(a.b - b.b) < tolerance &&
			abs(a.a - b.a) < tolerance);

func color_map_remove_color(col_map: Image, color_to_remove: Color):
	for y in range(col_map.get_height()):
		for x in range(col_map.get_width()):
			var pixel: Color = col_map.get_pixel(x, y)
			
			if colors_equal(pixel, color_to_remove):
				col_map.set_pixel(x, y, Color(0, 0, 0, 0))

func color_map_remove_non_country_color(col_map: Image):
	var removed_color_map = Image.create_from_data(col_map.get_width(),
	 col_map.get_height(),
	 false,
	 col_map.get_format(),
	 col_map.get_data())
	
	var terrain_colors = country_data.terrain_colors.values()
	for terrain_color in terrain_colors:
		terrain_color.a = 1.
		color_map_remove_color(removed_color_map, terrain_color)
	return removed_color_map
func create_political_map_mask_texture():
	# Create output texture format 
	if not color_lookup:
		push_error("No lookup texture found")
		return
	var texture_size = color_lookup.get_size()
	
	var output_format = texture_format_from_texture_2d(texture_size,
	 RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM,
	 RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)

	var lookup_format = texture_format_from_texture_2d(texture_size,
	 RenderingDevice.DATA_FORMAT_R8G8_UNORM,
	 RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT)

	var color_format = texture_format_from_texture_2d(color_map.get_size(),
	 RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM,
	 RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT)


	var removed_terrain_colors_map = color_map_remove_non_country_color(color_map)

	var color_tex = create_texture(color_format, RDTextureView.new(), [removed_terrain_colors_map.get_data()])
	var look_image = create_texture(lookup_format, RDTextureView.new(), [color_lookup.get_data()])
	var political_image = create_texture(output_format, RDTextureView.new(), [])
	
	
	var lookup_uniform = create_uniform(look_image, 0, RenderingDevice.UNIFORM_TYPE_IMAGE)

	var color_uniform := create_uniform(color_tex, 1, RenderingDevice.UNIFORM_TYPE_IMAGE)
	
	var political_uniform = create_uniform(political_image, 2, RenderingDevice.UNIFORM_TYPE_IMAGE)

	
	var shader = compile_shader(mask_political_path_shader)
   

	var byte_data: PackedByteArray = compute_result([political_uniform, color_uniform, lookup_uniform], political_image, shader)


	# Create new image from the result
	var result_image = Image.create_from_data(color_lookup.get_width(), color_lookup.get_height(), false, Image.FORMAT_RGBA8, byte_data)
	if save_images_to_file:
		result_image.save_png(mask_political_save_path)
	
	update_material_static_parameters("mask_map", ImageTexture.create_from_image(result_image))
	

func create_color_map_texture():
	# Size of the colormap
	const TEXTURE_SIZE = Vector2i(256, 256)
	var output_format = texture_format_from_texture_2d(TEXTURE_SIZE, RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)

	var output_image = create_texture(output_format, RDTextureView.new(), [])
   
   
	var output_uniform = create_uniform(output_image, 0, RenderingDevice.UNIFORM_TYPE_IMAGE)
	
	var buffer: PackedInt32Array = country_data.populate_color_map_buffers()
	var buffer_bytes := buffer.to_byte_array()
	
	
	var buffer_storage = create_ssbo(buffer_bytes.size(), buffer_bytes)
	var uniform_buffer = create_uniform(buffer_storage, 1, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)

	var shader = compile_shader(color_path_shader)
   
	var byte_data: PackedByteArray = compute_result([output_uniform, uniform_buffer], output_image, shader);

	# Create new image from the result
	var result_image = Image.create_from_data(TEXTURE_SIZE.x, TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8, byte_data)
	color_map = result_image
	# for debugging
	if save_images_to_file:
		result_image.save_png(color_map_save_path)
	# store the texture so it can be updated later
	color_texture = ImageTexture.create_from_image(color_map)
	update_material_dynamic_parameters("color_map", color_texture)

	return result_image
	
func create_lookup_texture():
	if not province_map:
		push_error("No province map set.")
		return
	var province_size = province_map.get_size()


	var shader = compile_shader(lookup_path_shader)
   
	var input_format = texture_format_from_texture_2d(province_size,
	 RenderingDevice.DATA_FORMAT_R8G8B8A8_UINT,
	 RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT)

	
	var image_data = province_map.get_image()
	image_data.convert(Image.FORMAT_RGBA8)
	var input_image = create_texture(input_format, RDTextureView.new(), [image_data.get_data()])

	if not input_image.is_valid():
		print("Failed to create GPU input texture")
		clean_up()
		return
   

	var output_format = texture_format_from_texture_2d(province_size, RenderingDevice.DATA_FORMAT_R8G8_UNORM, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)
	# Create empty output texture
	var output_image = create_texture(output_format, RDTextureView.new(), [])
	
	if not output_image.is_valid():
		print("Failed to create output texture")
		clean_up()
		return
   
	
	var input_uniform = create_uniform(input_image, 0, RenderingDevice.UNIFORM_TYPE_IMAGE)

	var output_uniform = create_uniform(output_image, 1, RenderingDevice.UNIFORM_TYPE_IMAGE)

	var color_keys = map_data.province_color_to_id.keys()
	
	var colors := PackedInt32Array()

	for color in color_keys:
		var id = map_data.province_color_to_id[color]
		colors.append_array(PackedInt32Array([color.r8, color.g8, color.b8, id]))
			
	var color_bytes := colors.to_byte_array()

	
	# Create a storage buffer that can hold our values.

	var buffer_color := create_ssbo(color_bytes.size(), color_bytes)
	var uniform_color = create_uniform(buffer_color, 2, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)

	# Get the result back
	var byte_data: PackedByteArray = compute_result([input_uniform, output_uniform, uniform_color], output_image, shader);


	if byte_data.size() == 0:
		push_error("No data retrieved from GPU texture!")
		return
	
	# Create new image from the result
	var texture_size = get_output_texture_size()
	var result_image = Image.create_from_data(texture_size.x, texture_size.y, false, Image.FORMAT_RG8, byte_data)
	color_lookup = result_image
	# for debugging
	if save_images_to_file:
		result_image.save_png(lookup_save_path)
	var result_tex = ImageTexture.create_from_image(color_lookup)
	final_material.set_shader_parameter("lookup_map", result_tex)
	update_material_dynamic_parameters("lookup_map", result_tex)
	update_material_static_parameters("lookup_map", result_tex)
