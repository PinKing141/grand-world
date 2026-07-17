extends ComputeHelper

const LOW_END_ADAPTER_PATTERNS := [
	"intel(r) uhd graphics 600",
	"intel uhd graphics 600",
]
const LOW_END_SUBVIEWPORT_SIZE := Vector2i(2816, 1024)

@export_group("Sub Viewports")
@export var country_field: SubViewport
@export var province_field: SubViewport
@export var output: SubViewport

@export_group("Data")
@export var map_data: MapData
@export var country_data: CountryData
@export var province_selector: ProvinceSelector
@export var province_map: Texture2D
@export var camera_controller: Node

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
@export var normalize_political_palette := true
@export_range(0.0, 0.5, 0.01) var appanage_realm_tint := 0.30
@export_range(0.0, 0.4, 0.01) var vassal_realm_tint := 0.18
@export_range(0.0, 0.3, 0.01) var personal_union_realm_tint := 0.10
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
var realm_color_map: Image
var subject_cue_map: Image
var realm_color_texture: ImageTexture
var subject_cue_texture: ImageTexture
var control_state_map: Image
var control_state_texture: ImageTexture
var _subject_registry: Dictionary = {}
var _subject_to_overlord: Dictionary = {}
var _subject_presentations: Dictionary = {}
var _realm_roots: Dictionary = {}
var _presentation_country_colors: Dictionary = {}
var _last_strategic_zoom := -1.0
var _compute_resources_active := false


func _enter_tree() -> void:
	var adapter_name := RenderingServer.get_video_adapter_name().to_lower()
	for pattern in LOW_END_ADAPTER_PATTERNS:
		if pattern in adapter_name:
			_apply_low_end_viewport_sizes()
			return


func _apply_low_end_viewport_sizes() -> void:
	# These intermediate maps are four times the display's pixel count at full
	# resolution. Halving each dimension keeps border generation sharp at the
	# laptop's native resolution while reducing render-target memory by 75%.
	for viewport_path in [
		"Subviewports/ProvinceEdgeLattice",
		"Subviewports/ColorOutput",
		"Subviewports/CountryDistanceField",
	]:
		var viewport := get_node_or_null(viewport_path) as SubViewport
		if viewport != null:
			viewport.size = LOW_END_SUBVIEWPORT_SIZE

# Presentation-only interaction state. Authoritative state arrives in Phase 2.
var hovered_province_id := -1
var selected_province_id := -1
var selected_country := ""
var war_goal_province_id := -1
var accessibility_profile := 0
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
		if parameter_name == "color_map" and final_material != null:
			final_material.set_shader_parameter("owner_color_map", parameter_variant)
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


func apply_world_state_owners(province_owners: Dictionary, subject_registry: Dictionary = {}) -> void:
	# WorldState is authoritative. Rebuild the presentation LUT in one batch so
	# loading a campaign never triggers thousands of GPU updates.
	if color_map == null or color_map.is_empty() or color_texture == null:
		return
	_subject_registry = subject_registry.duplicate(true)
	_rebuild_subject_presentation_index()
	_ensure_realm_presentation_maps()
	var width := color_map.get_width()
	var province_ids := province_owners.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		if province_id < 0 or province_id >= color_map.get_width() * color_map.get_height():
			continue
		var owner_tag := String(province_owners[raw_province_id])
		var owner_color := _presentation_country_color(owner_tag)
		var realm_color := _presentation_country_color(_realm_root(owner_tag))
		if political_color_map != null:
			political_color_map.set_pixel(province_id % width, floori(float(province_id) / width), owner_color)
		if display_uses_political_colors:
			color_map.set_pixel(province_id % width, floori(float(province_id) / width), owner_color)
		realm_color_map.set_pixel(province_id % width, floori(float(province_id) / width), realm_color)
		subject_cue_map.set_pixel(province_id % width, floori(float(province_id) / width), _subject_cue(owner_tag))
	color_texture.update(color_map)
	update_material_dynamic_parameters("color_map", color_texture)
	_upload_realm_presentation_maps()
	update_viewports_dynamic()


func update_province_owner(province_id: int, owner_tag: String) -> void:
	if color_map == null or color_map.is_empty() or color_texture == null:
		return
	var width := color_map.get_width()
	if province_id < 0 or province_id >= width * color_map.get_height():
		return
	var coordinate := Vector2i(province_id % width, floori(float(province_id) / width))
	var owner_color := _presentation_country_color(owner_tag)
	if political_color_map != null:
		political_color_map.set_pixelv(coordinate, owner_color)
	if display_uses_political_colors:
		color_map.set_pixelv(coordinate, owner_color)
	_ensure_realm_presentation_maps()
	realm_color_map.set_pixelv(coordinate, _presentation_country_color(_realm_root(owner_tag)))
	subject_cue_map.set_pixelv(coordinate, _subject_cue(owner_tag))
	color_texture.update(color_map)
	update_material_dynamic_parameters("color_map", color_texture)
	_upload_realm_presentation_maps()
	update_viewports_dynamic()


func _rebuild_subject_presentation_index() -> void:
	_subject_to_overlord.clear()
	_subject_presentations.clear()
	_realm_roots.clear()
	_presentation_country_colors.clear()
	var ids := _subject_registry.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = _subject_registry[raw_id]
		if String(record.get("status", "active")) != "active":
			continue
		var subject := String(record.get("subject", ""))
		var overlord := String(record.get("overlord", ""))
		if subject.is_empty() or overlord.is_empty() or subject == overlord:
			continue
		_subject_to_overlord[subject] = overlord
		_subject_presentations[subject] = String(record.get("presentation", record.get("type", "vassal")))


func _realm_root(tag: String) -> String:
	if tag.is_empty():
		return tag
	if _realm_roots.has(tag):
		return String(_realm_roots[tag])
	var current := tag
	var visited := {}
	while _subject_to_overlord.has(current) and not visited.has(current):
		visited[current] = true
		current = String(_subject_to_overlord[current])
	_realm_roots[tag] = current
	return current


func _normalized_country_color(tag: String) -> Color:
	var source: Color = country_data.country_id_to_color.get(tag, Color(0.0, 0.0, 0.0, 0.0))
	if source.a <= 0.001 or not normalize_political_palette:
		return source
	var saturation := source.s
	if saturation >= 0.12:
		saturation = clampf(lerpf(saturation, 0.56, 0.35), 0.34, 0.72)
	var value := clampf(lerpf(source.v, 0.72, 0.42), 0.48, 0.82)
	return Color.from_hsv(source.h, saturation, value, source.a)


func _presentation_country_color(tag: String) -> Color:
	if tag.is_empty():
		return Color(0.0, 0.0, 0.0, 0.0)
	if _presentation_country_colors.has(tag):
		return _presentation_country_colors[tag]
	var color := _normalized_country_color(tag)
	if _subject_to_overlord.has(tag):
		var overlord_color := _normalized_country_color(_realm_root(tag))
		var presentation := String(_subject_presentations.get(tag, "vassal"))
		var strength := vassal_realm_tint
		match presentation:
			"appanage": strength = appanage_realm_tint
			"personal_union": strength = personal_union_realm_tint
		color = color.lerp(overlord_color, strength)
	_presentation_country_colors[tag] = color
	return color


func _subject_cue(tag: String) -> Color:
	if not _subject_to_overlord.has(tag):
		return Color(0.0, 0.0, 0.0, 1.0)
	var presentation := String(_subject_presentations.get(tag, "vassal"))
	var presentation_code := 0.5
	match presentation:
		"appanage": presentation_code = 0.25
		"personal_union": presentation_code = 0.75
	return Color(1.0, presentation_code, 0.0, 1.0)


func _ensure_realm_presentation_maps() -> void:
	if color_map == null or color_map.is_empty():
		return
	var required_size := color_map.get_size()
	if realm_color_map == null or realm_color_map.get_size() != required_size:
		realm_color_map = Image.create(required_size.x, required_size.y, false, Image.FORMAT_RGBA8)
		realm_color_map.fill(Color(0.0, 0.0, 0.0, 0.0))
	if subject_cue_map == null or subject_cue_map.get_size() != required_size:
		subject_cue_map = Image.create(required_size.x, required_size.y, false, Image.FORMAT_RGBA8)
		subject_cue_map.fill(Color(0.0, 0.0, 0.0, 1.0))


func _upload_realm_presentation_maps() -> void:
	if realm_color_map == null or subject_cue_map == null:
		return
	if realm_color_texture == null:
		realm_color_texture = ImageTexture.create_from_image(realm_color_map)
	else:
		realm_color_texture.update(realm_color_map)
	if subject_cue_texture == null:
		subject_cue_texture = ImageTexture.create_from_image(subject_cue_map)
	else:
		subject_cue_texture.update(subject_cue_map)
	output_material.set_shader_parameter("realm_color_map", realm_color_texture)
	output_material.set_shader_parameter("subject_cue_map", subject_cue_texture)
	final_material.set_shader_parameter("realm_color_map", realm_color_texture)
	final_material.set_shader_parameter("subject_cue_map", subject_cue_texture)


func apply_control_states(province_states: Dictionary, player_country: String = "") -> void:
	_ensure_control_state_map()
	control_state_map.fill(Color(0.0, 0.0, 0.0, 1.0))
	var province_ids := province_states.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var state: Dictionary = province_states[raw_province_id]
		_write_control_state(
			province_id,
			String(state.get("owner", "")),
			String(state.get("controller", state.get("owner", ""))),
			player_country
		)
	_upload_control_state_map()


func update_province_control(province_id: int, owner_tag: String, controller_tag: String, player_country: String = "") -> void:
	_ensure_control_state_map()
	_write_control_state(province_id, owner_tag, controller_tag, player_country)
	_upload_control_state_map()


func _ensure_control_state_map() -> void:
	var required_size := Vector2i(256, 256)
	if color_map != null and not color_map.is_empty():
		required_size = color_map.get_size()
	if control_state_map == null or control_state_map.get_size() != required_size:
		control_state_map = Image.create(required_size.x, required_size.y, false, Image.FORMAT_RGBA8)
		control_state_map.fill(Color(0.0, 0.0, 0.0, 1.0))


func _write_control_state(province_id: int, owner_tag: String, controller_tag: String, player_country: String) -> void:
	if control_state_map == null or control_state_map.is_empty():
		return
	var width := control_state_map.get_width()
	if province_id < 0 or province_id >= width * control_state_map.get_height():
		return
	var occupied := not controller_tag.is_empty() and controller_tag != owner_tag
	var player_controls := occupied and not player_country.is_empty() and controller_tag == player_country
	var player_is_occupied := occupied and not player_country.is_empty() and owner_tag == player_country
	control_state_map.set_pixel(
		province_id % width,
		floori(float(province_id) / width),
		Color(1.0 if occupied else 0.0, 1.0 if player_controls else 0.0, 1.0 if player_is_occupied else 0.0, 1.0)
	)


func _upload_control_state_map() -> void:
	if control_state_map == null or final_material == null:
		return
	if control_state_texture == null:
		control_state_texture = ImageTexture.create_from_image(control_state_map)
	else:
		control_state_texture.update(control_state_map)
	final_material.set_shader_parameter("control_state_map", control_state_texture)


func _on_camera_zoom_changed(_camera_height: float, normalized_zoom: float) -> void:
	_set_strategic_zoom(normalized_zoom)


func _set_strategic_zoom(normalized_zoom: float) -> void:
	var clamped_zoom := clampf(normalized_zoom, 0.0, 1.0)
	if is_equal_approx(clamped_zoom, _last_strategic_zoom):
		return
	_last_strategic_zoom = clamped_zoom
	if final_material != null:
		final_material.set_shader_parameter("strategic_zoom", clamped_zoom)


func apply_economy_heatmap(values: Dictionary) -> void:
	if political_color_map == null or color_texture == null:
		return
	display_uses_political_colors = false
	set_war_goal_province(-1)
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


func apply_strategy_overlay(colors: Dictionary, semantic_war_goal_id := -1) -> void:
	if political_color_map == null or color_texture == null:
		return
	display_uses_political_colors = false
	set_war_goal_province(semantic_war_goal_id)
	color_map = _copy_image(political_color_map)
	var width := color_map.get_width()
	var ids := colors.keys()
	ids.sort()
	for raw_id in ids:
		var province_id := int(raw_id)
		if province_id < 0 or province_id >= color_map.get_width() * color_map.get_height():
			continue
		color_map.set_pixel(province_id % width, floori(float(province_id) / width), colors[raw_id])
	color_texture.update(color_map)
	update_material_dynamic_parameters("color_map", color_texture)
	final_material.set_shader_parameter("map_mode", 0)
	clear_country_highlight()
	update_viewports_dynamic()


func restore_political_map() -> void:
	if political_color_map == null or color_texture == null:
		return
	display_uses_political_colors = true
	set_war_goal_province(-1)
	color_map = _copy_image(political_color_map)
	color_texture.update(color_map)
	update_material_dynamic_parameters("color_map", color_texture)
	update_viewports_dynamic()


func set_war_goal_province(province_id: int) -> void:
	war_goal_province_id = province_id
	if final_material == null:
		return
	final_material.set_shader_parameter("war_goal_enabled", province_id >= 0)
	final_material.set_shader_parameter("war_goal_province", _province_lookup_coordinate(province_id) if province_id >= 0 else Vector2(-1.0, -1.0))


func debug_war_goal_province() -> int:
	return war_goal_province_id


func set_accessibility_profile(profile: int) -> void:
	accessibility_profile = clampi(profile, 0, 3)
	if final_material == null:
		return
	final_material.set_shader_parameter("accessibility_profile", accessibility_profile)
	final_material.set_shader_parameter("accessibility_pattern_boost", 1.0 if accessibility_profile == 0 else (1.6 if accessibility_profile == 3 else 1.35))
	match accessibility_profile:
		1:
			final_material.set_shader_parameter("hover_color", Color(1.0, 0.72, 0.10))
			final_material.set_shader_parameter("selection_color", Color(0.20, 0.78, 1.0))
			final_material.set_shader_parameter("occupation_color", Color(0.68, 0.30, 0.74))
			final_material.set_shader_parameter("player_occupation_color", Color(0.16, 0.52, 0.92))
			final_material.set_shader_parameter("enemy_occupation_color", Color(0.95, 0.46, 0.12))
			final_material.set_shader_parameter("war_goal_color", Color(1.0, 0.88, 0.24))
		2:
			final_material.set_shader_parameter("hover_color", Color(1.0, 0.38, 0.24))
			final_material.set_shader_parameter("selection_color", Color(0.95, 0.95, 0.95))
			final_material.set_shader_parameter("occupation_color", Color(0.52, 0.70, 0.28))
			final_material.set_shader_parameter("player_occupation_color", Color(0.10, 0.72, 0.66))
			final_material.set_shader_parameter("enemy_occupation_color", Color(0.86, 0.20, 0.52))
			final_material.set_shader_parameter("war_goal_color", Color(1.0, 0.46, 0.24))
		3:
			final_material.set_shader_parameter("hover_color", Color(1.0, 0.78, 0.0))
			final_material.set_shader_parameter("selection_color", Color.WHITE)
			final_material.set_shader_parameter("occupation_color", Color(0.72, 0.24, 0.82))
			final_material.set_shader_parameter("player_occupation_color", Color(0.18, 0.62, 1.0))
			final_material.set_shader_parameter("enemy_occupation_color", Color(1.0, 0.30, 0.08))
			final_material.set_shader_parameter("war_goal_color", Color(1.0, 0.86, 0.0))
		_:
			final_material.set_shader_parameter("hover_color", Color(1.0, 0.83, 0.25))
			final_material.set_shader_parameter("selection_color", Color(0.2, 0.85, 1.0))
			final_material.set_shader_parameter("occupation_color", Color(0.48, 0.24, 0.58))
			final_material.set_shader_parameter("player_occupation_color", Color(0.55, 0.28, 0.70))
			final_material.set_shader_parameter("enemy_occupation_color", Color(0.84, 0.35, 0.16))
			final_material.set_shader_parameter("war_goal_color", Color(1.0, 0.78, 0.12))


func debug_accessibility_profile() -> int:
	return accessibility_profile


func debug_semantic_priority() -> Array[String]:
	return ["passive_borders", "occupation", "war_goal", "hover", "selection"]


func _copy_image(source: Image) -> Image:
	return Image.create_from_data(source.get_width(), source.get_height(), source.has_mipmaps(), source.get_format(), source.get_data())

	
func _ready():
	province_selector.province_image = province_map.get_image()

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
		_initialize_compute_resources()
		create_lookup_texture()
		create_color_map_texture()
		create_political_map_mask_texture()
		_clean_up_compute_resources()
	if political_color_map == null and color_map != null:
		political_color_map = _copy_image(color_map)

	province_selector.province_hovered.connect(_on_province_hovered)
	province_selector.province_hover_cleared.connect(_on_province_hover_cleared)
	province_selector.province_selected.connect(_on_province_selected)
	province_selector.selection_cleared.connect(_on_selection_cleared)
	final_material.set_shader_parameter("hover_enabled", false)
	final_material.set_shader_parameter("selection_enabled", false)
	final_material.set_shader_parameter("country_selection_enabled", false)
	final_material.set_shader_parameter("war_goal_enabled", false)
	final_material.set_shader_parameter("accessibility_profile", accessibility_profile)
	final_material.set_shader_parameter("map_mode", 0)
	_ensure_realm_presentation_maps()
	_upload_realm_presentation_maps()
	_ensure_control_state_map()
	_upload_control_state_map()
	if camera_controller != null and camera_controller.has_signal("zoom_changed"):
		camera_controller.zoom_changed.connect(_on_camera_zoom_changed)
	if camera_controller != null and camera_controller.has_method("normalized_zoom"):
		_set_strategic_zoom(float(camera_controller.normalized_zoom()))

	province_field.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	update_viewports_dynamic()


func _exit_tree() -> void:
	_clean_up_compute_resources()


func _initialize_compute_resources() -> void:
	if _compute_resources_active:
		return
	create_rd()
	_compute_resources_active = true
	set_output_texture_size(province_map.get_size())


func _clean_up_compute_resources() -> void:
	if not _compute_resources_active:
		return
	clean_up()
	_compute_resources_active = false


func debug_compute_resources_active() -> bool:
	return _compute_resources_active


func debug_intermediate_viewport_size() -> Vector2i:
	return output.size
		
		

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
	final_material.set_shader_parameter("owner_color_map", color_texture)
	distance_material.set_shader_parameter("lookup_map", lookup_resource)
	distance_material.set_shader_parameter("color_map", color_texture)
	province_material.set_shader_parameter("lookup_map", lookup_resource)
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
	var color: Color = _presentation_country_color(tag)
	final_material.set_shader_parameter("selected_country_color", Color(color.r, color.g, color.b, 1.0))
	final_material.set_shader_parameter("country_selection_enabled", true)


func clear_country_highlight() -> void:
	final_material.set_shader_parameter("country_selection_enabled", false)


func debug_presentation_color(tag: String) -> Color:
	return _presentation_country_color(tag)


func debug_realm_root(tag: String) -> String:
	return _realm_root(tag)


func debug_subject_cue(province_id: int) -> Color:
	if subject_cue_map == null or subject_cue_map.is_empty():
		return Color.TRANSPARENT
	var coordinate := Vector2i(province_id % subject_cue_map.get_width(), floori(float(province_id) / subject_cue_map.get_width()))
	if coordinate.x < 0 or coordinate.y < 0 or coordinate.y >= subject_cue_map.get_height():
		return Color.TRANSPARENT
	return subject_cue_map.get_pixelv(coordinate)


func debug_control_cue(province_id: int) -> Color:
	if control_state_map == null or control_state_map.is_empty():
		return Color.TRANSPARENT
	var coordinate := Vector2i(province_id % control_state_map.get_width(), floori(float(province_id) / control_state_map.get_width()))
	if coordinate.x < 0 or coordinate.y < 0 or coordinate.y >= control_state_map.get_height():
		return Color.TRANSPARENT
	return control_state_map.get_pixelv(coordinate)


func debug_strategic_zoom() -> float:
	return _last_strategic_zoom


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
		return
   

	var output_format = texture_format_from_texture_2d(province_size, RenderingDevice.DATA_FORMAT_R8G8_UNORM, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)
	# Create empty output texture
	var output_image = create_texture(output_format, RDTextureView.new(), [])
	
	if not output_image.is_valid():
		print("Failed to create output texture")
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
