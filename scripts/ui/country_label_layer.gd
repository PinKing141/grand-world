class_name CountryLabelLayer
extends Node3D

## Deterministic, shape-aware country labels.
##
## Layout is derived from a conservative province-ID raster. Each country name
## follows the dominant axis of its main connected land body and is scaled from
## that body's oriented extent. Tiny or ambiguous shapes use conservative
## fallbacks. Only labels that survive zoom and projected screen-space collision
## are instantiated, and ownership changes rebuild only the old/new countries.

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")

const FONT_PATH := "res://assets/fonts/LibreBaskerville-Variable.ttf"
const BATCH_SHADER_PATH := "res://shaders/country_label_msdf.gdshader"
const TERRITORY_MAP_PATH := "res://assets/label_territory_map.png"
const TERRITORY_METADATA_PATH := "res://assets/label_territory_map.json"
const MAP_PIXEL_SIZE := 0.01
const MAP_HALF_WIDTH := 28.16
const MAP_HALF_HEIGHT := 10.24
const LABEL_FONT_SIZE := 64
const LABEL_OUTLINE_SIZE := 0
const LABEL_INK := Color(0.93, 0.89, 0.75, 0.98)
const LABEL_LIFT := 0.035
const LABEL_FILL := 0.94
const SHAPE_LABEL_FILL := 0.54
const MAX_PIXEL_SIZE := 0.0065
const MIN_READABLE_PIXEL_SIZE := 0.0003
const MIN_SHAPE_CELLS := 8
const MIN_ALIGNMENT_ANISOTROPY := 0.18
const MAX_LABEL_ANGLE_DEGREES := 72.0
const MAJOR_AXIS_SIGMA_SPAN := 3.4
const MINOR_AXIS_SIGMA_SPAN := 2.7
const MIN_CLOSE_ZOOM_LABEL_SCALE := 0.48
const MIN_LABEL_SCALE_CAMERA_HEIGHT := 0.8
const FULL_LABEL_SCALE_CAMERA_HEIGHT := 2.4
const SCREEN_COLLISION_PADDING := 3.0
const COLLISION_GRID_SIZE := 128.0
const MIN_PROJECTED_LABEL_WIDTH := 28.0
const MIN_PROJECTED_LABEL_HEIGHT := 11.0
const BATCH_REBUILD_PAN_THRESHOLD := 192.0
const BATCH_PAN_SETTLE_USEC := 90_000
const MAX_INCREMENTAL_TAGS_PER_FRAME := 4
# MSDF Label3D allocation can initialise render resources per node. Spread the
# fallback path across frames so entering a dense region cannot create a
# one-frame hitch; the final batched renderer removes this node queue entirely.
const MAX_NODE_CREATIONS_PER_FRAME := 6
const DEBUG_MAP_MODE := 2
const UNSUPPORTED_LABEL_ADAPTER_PATTERNS := [
	"intel(r) uhd graphics 600",
	"intel uhd graphics 600",
]
@export var use_batched_msdf_renderer := true

@export var simulation_controller: GrandWorldSimulationController
@export var map_render: Node

var _graph: ProvinceGraph
var _height_image: Image
var _height_scale := 0.35
var _territory_image: Image
var _territory_scale := 0
var _territory_cell_province_ids: PackedInt32Array = []
var _territory_cell_width := 0
var _label_font: FontVariation
var _base_font: FontFile
var _font_ascii_ready := false
var _font_atlas_ready := false
var _hardware_compatibility_mode := false

var _batch_canvas: CanvasLayer
var _batch_root: Node2D
var _batch_shader: Shader
var _batch_pages: Dictionary = {} # atlas page -> MultiMeshInstance2D record
var _batched_visible_tags: Dictionary = {}
var _batch_glyph_count := 0
var _batch_pan_reference_valid := false
var _batch_reference_camera_transform := Transform3D.IDENTITY
var _batch_reference_camera_size := 0.0
var _batch_reference_viewport_size := Vector2.ZERO
var _batch_reference_world := Vector3.ZERO
var _batch_reference_screen := Vector2.ZERO
var _batch_screen_offset := Vector2.ZERO
var _batch_translation_pending := false
var _batch_last_pan_usec := 0

var _layouts: Dictionary = {} # tag -> deterministic layout descriptor
var _label_nodes: Dictionary = {} # tag -> lazily-created Label3D
var _screen_rects: Dictionary = {} # visible tag -> projected Rect2
var _desired_visible: Dictionary = {}
var _pending_node_tags: Array[String] = []
var _pending_tags: Dictionary = {}
var _events_connected := false
var _full_rebuild_pending := true
var _initial_rebuild_active := false
var _initial_rebuild_started_usec := 0
var _initial_layout_cpu_ms := 0.0
var _visibility_dirty := true
var _camera_signature_valid := false
var _last_camera_transform := Transform3D.IDENTITY
var _last_viewport_size := Vector2.ZERO
var _last_camera_projection := Camera3D.PROJECTION_PERSPECTIVE
var _last_camera_fov := 0.0
var _last_camera_size := 0.0
var _last_rebuilt_tags: Array[String] = []
var _stage_profile_enabled := false
var _debug_batch_durations_ms: Array[float] = []
var _debug_stage_timings: Dictionary = {}
var _last_bbox_setup_us := 0
var _last_scan_us := 0
var _visibility_revision := 0
var _label_render_scale := 1.0
var _metrics := {
	"initial_layout_ms": 0.0,
	"initial_wall_ms": 0.0,
	"max_layout_batch_ms": 0.0,
	"max_layout_batch_tags": [],
	"last_incremental_ms": 0.0,
	"last_visibility_ms": 0.0,
	"last_node_batch_ms": 0.0,
	"max_node_batch_ms": 0.0,
	"layout_count": 0,
	"node_count": 0,
	"batch_draw_count": 0,
	"batch_glyph_count": 0,
	"label3d_node_count": 0,
	"renderer": "label3d_fallback",
	"visible_count": 0,
	"territory_fit_count": 0,
	"shape_aligned_count": 0,
	"full_name_count": 0,
	"screen_fallback_count": 0,
}


func _ready() -> void:
	# This node is late in the scene tree and Godot readies siblings in reverse
	# order. Defer font/atlas/territory work so authoritative simulation startup
	# and packaged-build validation cannot be starved by presentation resources.
	_stage_profile_enabled = OS.has_environment("LABEL_STAGE_PROFILE")
	_initialize_label_resources.call_deferred()


func _initialize_label_resources() -> void:
	if _requires_hardware_compatibility_mode():
		# This legacy adapter loses its D3D12 device as soon as the custom MSDF
		# atlas is uploaded. Keep the strategic map and campaign fully usable;
		# only the optional country-name overlay is suppressed.
		_hardware_compatibility_mode = true
		_metrics["renderer"] = "disabled_hardware_compatibility"
		_font_ascii_ready = true
		_font_atlas_ready = true
		hide()
		set_process(false)
		return
	_graph = ProvinceGraph.load_default()
	_create_batch_canvas()
	_load_bundled_font()
	_load_territory_map()
	_load_heightmap()
	if map_render != null and map_render.get("final_material") != null:
		var scale_param = map_render.final_material.get_shader_parameter("terrain_height_scale")
		if scale_param != null:
			_height_scale = float(scale_param)


func _requires_hardware_compatibility_mode() -> bool:
	var adapter_name := RenderingServer.get_video_adapter_name().to_lower()
	for pattern in UNSUPPORTED_LABEL_ADAPTER_PATTERNS:
		if String(pattern) in adapter_name:
			return true
	return false


func _load_bundled_font() -> void:
	var base_font := load(FONT_PATH) as FontFile
	if base_font == null:
		push_error("Country labels require bundled font %s" % FONT_PATH)
		_font_ascii_ready = true
		return
	_base_font = base_font
	_label_font = FontVariation.new()
	_label_font.base_font = base_font
	_warm_label_font_incrementally.call_deferred()


func _warm_label_font_incrementally() -> void:
	var base_font := _label_font.base_font as FontFile if _label_font != null else null
	if base_font == null:
		_font_ascii_ready = true
		return
	# Rendering the complete Latin/Latin-1 MSDF range in _ready() blocked the
	# Windows message pump for several seconds. Warm a small glyph batch per
	# frame instead. ASCII completes first so normal country names can begin
	# layout while the extended localisation range continues in the background.
	for range_start in range(32, 384, 16):
		var range_end := mini(range_start + 15, 383)
		base_font.render_range(
			0,
			Vector2i(LABEL_FONT_SIZE, LABEL_FONT_SIZE),
			range_start,
			range_end
		)
		if range_end >= 127:
			_font_ascii_ready = true
		await get_tree().process_frame
	_font_ascii_ready = true
	_label_font.get_string_size(
		"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØŒÙÚÛÜÝŸßàáâãäåæçèéêëìíîïñòóôõöøœùúûüýÿ",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		LABEL_FONT_SIZE
	)
	_font_atlas_ready = true
	_refresh_msdf_atlas_pages()
	_visibility_dirty = true


func _create_batch_canvas() -> void:
	if not use_batched_msdf_renderer:
		return
	_batch_shader = load(BATCH_SHADER_PATH) as Shader
	if _batch_shader == null:
		push_error("Country label batch shader is missing: %s" % BATCH_SHADER_PATH)
		use_batched_msdf_renderer = false
		return
	_batch_canvas = CanvasLayer.new()
	_batch_canvas.name = "BatchedCountryLabels"
	# The map labels must appear over the 3D map but below every normal HUD.
	_batch_canvas.layer = -1
	add_child(_batch_canvas)
	_batch_root = Node2D.new()
	_batch_root.name = "GlyphPages"
	_batch_canvas.add_child(_batch_root)


func _refresh_msdf_atlas_pages() -> void:
	_clear_batch_pages()
	if not use_batched_msdf_renderer or _base_font == null or _batch_root == null or _batch_shader == null:
		return
	var font_size := Vector2i(LABEL_FONT_SIZE, LABEL_FONT_SIZE)
	var texture_count := _base_font.get_texture_count(0, font_size)
	for page_index in texture_count:
		var atlas_image := _base_font.get_texture_image(0, font_size, page_index)
		if atlas_image == null or atlas_image.is_empty():
			continue
		var atlas_texture := ImageTexture.create_from_image(atlas_image)
		var material := ShaderMaterial.new()
		material.shader = _batch_shader
		material.set_shader_parameter("msdf_atlas", atlas_texture)
		material.set_shader_parameter("fill_color", LABEL_INK)
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_custom_data = true
		multimesh.mesh = quad
		var instance := MultiMeshInstance2D.new()
		instance.name = "AtlasPage_%d" % page_index
		instance.multimesh = multimesh
		instance.material = material
		instance.visible = false
		_batch_root.add_child(instance)
		_batch_pages[page_index] = {
			"node": instance,
			"multimesh": multimesh,
			"atlas_size": Vector2(atlas_image.get_size()),
			"texture": atlas_texture,
		}


func _clear_batch_pages() -> void:
	for record in _batch_pages.values():
		var instance := (record as Dictionary).get("node") as MultiMeshInstance2D
		if instance != null:
			instance.queue_free()
	_batch_pages.clear()
	_batched_visible_tags.clear()
	_batch_glyph_count = 0


func _load_territory_map() -> void:
	var metadata_file := FileAccess.open(TERRITORY_METADATA_PATH, FileAccess.READ)
	if metadata_file == null:
		push_error("Country label territory metadata is missing: %s" % TERRITORY_METADATA_PATH)
		return
	var metadata_json := JSON.new()
	if metadata_json.parse(metadata_file.get_as_text()) != OK or not metadata_json.data is Dictionary:
		push_error("Country label territory metadata is invalid.")
		return
	var metadata: Dictionary = metadata_json.data
	_territory_scale = int(metadata.get("scale", 0))
	if _territory_scale <= 0:
		push_error("Country label territory scale must be positive.")
		return
	var territory_texture := load(TERRITORY_MAP_PATH) as Texture2D
	if territory_texture == null:
		push_error("Country label territory map is missing: %s" % TERRITORY_MAP_PATH)
		return
	_territory_image = territory_texture.get_image()
	if _territory_image == null or _territory_image.is_empty():
		push_error("Country label territory map failed to decode.")
		_territory_image = null
	else:
		if _territory_image.is_compressed():
			_territory_image.decompress()
		_build_territory_cell_cache()


## The territory PNG is already baked at cell resolution (one pixel per
## label-layout cell, per tools/map_labels/build_label_territory_map.py), so
## `_territory_province_id()` used to call `Image.get_pixel()` and decode a
## Color to an int on every single lookup - repeated many times over as
## `_shape_alignment()`/`_largest_safe_rectangle()` scan each country's own
## bounding box (FL8.2: measured 6-20ms per large country, dominated by this
## exact call). Decoding the whole image to a flat int lookup table once, at
## load time, turns every later lookup into a plain array index - identical
## values, computed once instead of on every scan.
func _build_territory_cell_cache() -> void:
	_territory_cell_width = _territory_image.get_width()
	var height := _territory_image.get_height()
	_territory_cell_province_ids.resize(_territory_cell_width * height)
	for y in height:
		for x in _territory_cell_width:
			var colour := _territory_image.get_pixel(x, y)
			_territory_cell_province_ids[y * _territory_cell_width + x] = (
				roundi(colour.r * 255.0) * 65536
				+ roundi(colour.g * 255.0) * 256
				+ roundi(colour.b * 255.0)
			)


func _load_heightmap() -> void:
	var height_texture := load("res://assets/heightmap.png") as Texture2D
	if height_texture == null:
		return
	_height_image = height_texture.get_image()
	if _height_image != null and _height_image.is_compressed():
		_height_image.decompress()


func _connect_events() -> void:
	if _events_connected or simulation_controller.event_bus == null:
		return
	var events := simulation_controller.event_bus
	_events_connected = true
	events.province_owner_changed.connect(_on_province_owner_changed)
	events.world_reloaded.connect(func(_checksum: String) -> void: _request_full_rebuild())
	events.country_formed.connect(func(old_tag: String, new_tag: String) -> void:
		_queue_country(old_tag)
		_queue_country(new_tag)
	)
	events.country_released.connect(func(releasing_tag: String, released_tag: String, _ids: Array) -> void:
		_queue_country(releasing_tag)
		_queue_country(released_tag)
	)
	events.country_extinct.connect(_queue_country)
	var map_hud = simulation_controller.map_hud
	if map_hud != null and map_hud.has_signal("map_mode_changed"):
		map_hud.map_mode_changed.connect(func(_mode: int, _external: String) -> void:
			_visibility_dirty = true
		)


func _process(_delta: float) -> void:
	if not _font_ascii_ready or simulation_controller == null or not simulation_controller.initialized:
		return
	_connect_events()
	if _full_rebuild_pending:
		_begin_full_rebuild()
	if not _pending_tags.is_empty():
		_process_incremental_layouts()
	var camera_changed := _camera_or_viewport_changed()
	if _visibility_dirty:
		_update_visibility()
	elif camera_changed:
		if _translate_batch_for_orthographic_pan():
			_batch_translation_pending = true
			_batch_last_pan_usec = Time.get_ticks_usec()
		else:
			_update_visibility()
	elif _batch_translation_pending and Time.get_ticks_usec() - _batch_last_pan_usec >= BATCH_PAN_SETTLE_USEC:
		_update_visibility()
	if not _pending_node_tags.is_empty():
		_process_node_creation_queue()


func _request_full_rebuild() -> void:
	_full_rebuild_pending = true
	_pending_tags.clear()
	_visibility_dirty = true


func _on_province_owner_changed(_province_id: int, old_owner: String, new_owner: String) -> void:
	_queue_country(old_owner)
	_queue_country(new_owner)


func _queue_country(tag: String) -> void:
	if tag.is_empty() or tag in ["No Owner", "Ocean"]:
		return
	_pending_tags[tag] = true


func _begin_full_rebuild() -> void:
	_full_rebuild_pending = false
	_pending_tags.clear()
	_last_rebuilt_tags.clear()
	_initial_rebuild_active = true
	_initial_rebuild_started_usec = Time.get_ticks_usec()
	_initial_layout_cpu_ms = 0.0
	_metrics["initial_layout_ms"] = 0.0
	_metrics["initial_wall_ms"] = 0.0
	_metrics["max_layout_batch_ms"] = 0.0
	_metrics["max_layout_batch_tags"] = []
	_metrics["max_node_batch_ms"] = 0.0
	var active_tags := {}
	var tags := simulation_controller.world.country_to_provinces.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := String(raw_tag)
		active_tags[tag] = true
		_pending_tags[tag] = true
	for raw_tag in _layouts.keys():
		var tag := String(raw_tag)
		if not active_tags.has(tag):
			_remove_country(tag)
	_update_layout_metrics()
	_visibility_dirty = false


func _process_incremental_layouts() -> void:
	var started := Time.get_ticks_usec()
	_last_rebuilt_tags.clear()
	var tags := _pending_tags.keys()
	tags.sort()
	var count := mini(tags.size(), MAX_INCREMENTAL_TAGS_PER_FRAME)
	for index in count:
		var tag := String(tags[index])
		_pending_tags.erase(tag)
		_rebuild_country_layout(tag)
		_last_rebuilt_tags.append(tag)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	if _stage_profile_enabled and _initial_rebuild_active:
		_debug_batch_durations_ms.append(elapsed_ms)
	if _initial_rebuild_active:
		_initial_layout_cpu_ms += elapsed_ms
		_metrics["initial_layout_ms"] = _initial_layout_cpu_ms
		if elapsed_ms > float(_metrics["max_layout_batch_ms"]):
			_metrics["max_layout_batch_ms"] = elapsed_ms
			_metrics["max_layout_batch_tags"] = _last_rebuilt_tags.duplicate()
		if _pending_tags.is_empty():
			_initial_rebuild_active = false
			_metrics["initial_wall_ms"] = float(Time.get_ticks_usec() - _initial_rebuild_started_usec) / 1000.0
			_visibility_dirty = true
	else:
		_metrics["last_incremental_ms"] = elapsed_ms
		_visibility_dirty = true
	_update_layout_metrics()


func _rebuild_country_layout(tag: String) -> void:
	var t0 := Time.get_ticks_usec()
	var body := _main_land_body(tag)
	var t1 := Time.get_ticks_usec()
	if body.is_empty():
		_remove_country(tag)
		return
	var shape := _shape_alignment(body)
	var t2 := Time.get_ticks_usec()
	var region := Rect2i() if not shape.is_empty() else _largest_safe_rectangle(body)
	var t3 := Time.get_ticks_usec()
	var layout := _make_layout(tag, body, region, shape)
	var t4 := Time.get_ticks_usec()
	if _stage_profile_enabled:
		_debug_stage_timings[tag] = {
			"land_body_ms": float(t1 - t0) * 0.001,
			"bbox_setup_ms": float(_last_bbox_setup_us) * 0.001,
			"shape_scan_ms": float(_last_scan_us) * 0.001,
			"shape_total_ms": float(t2 - t1) * 0.001,
			"rect_ms": float(t3 - t2) * 0.001,
			"layout_ms": float(t4 - t3) * 0.001,
			"total_ms": float(t4 - t0) * 0.001,
		}
	if layout.is_empty():
		_remove_country(tag)
		return
	_layouts[tag] = layout
	if _label_nodes.has(tag):
		_apply_layout(_label_nodes[tag] as Label3D, layout)


func _remove_country(tag: String) -> void:
	_layouts.erase(tag)
	_screen_rects.erase(tag)
	_desired_visible.erase(tag)
	_pending_node_tags.erase(tag)
	if _label_nodes.has(tag):
		var node := _label_nodes[tag] as Label3D
		_label_nodes.erase(tag)
		node.queue_free()


func _main_land_body(tag: String) -> PackedInt32Array:
	var owned_land := PackedInt32Array()
	for raw_id in simulation_controller.world.get_country_provinces(tag):
		var province_id := int(raw_id)
		if _graph.is_land(province_id):
			owned_land.append(province_id)
	if owned_land.is_empty():
		return PackedInt32Array()
	owned_land.sort()
	var owned := {}
	for province_id in owned_land:
		owned[province_id] = true
	var visited := {}
	var best := PackedInt32Array()
	for province_id in owned_land:
		if visited.has(province_id):
			continue
		var component := PackedInt32Array()
		var stack := PackedInt32Array([province_id])
		visited[province_id] = true
		while not stack.is_empty():
			var current := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			component.append(current)
			for neighbor in _graph.land_neighbors(current):
				if owned.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					stack.append(neighbor)
		if component.size() > best.size():
			component.sort()
			best = component
	return best


func _largest_safe_rectangle(body: PackedInt32Array) -> Rect2i:
	if _territory_image == null or _territory_scale <= 0:
		return Rect2i()
	var owned := {}
	var pixel_bounds := Rect2i()
	var has_bounds := false
	for province_id in body:
		owned[province_id] = true
		var province_bounds := _graph.bounding_rect(province_id)
		if province_bounds.has_area():
			pixel_bounds = province_bounds if not has_bounds else pixel_bounds.merge(province_bounds)
			has_bounds = true
	if not has_bounds:
		return Rect2i()
	var min_cell := Vector2i(
		clampi(pixel_bounds.position.x / _territory_scale, 0, _territory_image.get_width() - 1),
		clampi(pixel_bounds.position.y / _territory_scale, 0, _territory_image.get_height() - 1)
	)
	var pixel_end := pixel_bounds.end
	var max_cell := Vector2i(
		clampi(ceili(float(pixel_end.x) / float(_territory_scale)), min_cell.x + 1, _territory_image.get_width()),
		clampi(ceili(float(pixel_end.y) / float(_territory_scale)), min_cell.y + 1, _territory_image.get_height())
	)
	var width := max_cell.x - min_cell.x
	if width <= 0:
		return Rect2i()
	var heights := PackedInt32Array()
	heights.resize(width)
	var best := Rect2i()
	for y in range(min_cell.y, max_cell.y):
		for local_x in width:
			var province_id := _territory_province_id(min_cell.x + local_x, y)
			heights[local_x] = heights[local_x] + 1 if owned.has(province_id) else 0
		var stack: Array[int] = []
		for local_x in range(width + 1):
			var current_height := heights[local_x] if local_x < width else 0
			while not stack.is_empty() and heights[stack[-1]] > current_height:
				var height := heights[stack.pop_back()]
				var left := stack[-1] + 1 if not stack.is_empty() else 0
				var candidate := Rect2i(
					Vector2i(min_cell.x + left, y - height + 1),
					Vector2i(local_x - left, height)
				)
				if _region_is_better(candidate, best):
					best = candidate
			stack.append(local_x)
	return best


func _region_is_better(candidate: Rect2i, current: Rect2i) -> bool:
	var candidate_area := candidate.get_area()
	var current_area := current.get_area()
	if candidate_area != current_area:
		return candidate_area > current_area
	if candidate.size.x != current.size.x:
		return candidate.size.x > current.size.x
	if candidate.position.y != current.position.y:
		return candidate.position.y < current.position.y
	return candidate.position.x < current.position.x


func _territory_province_id(x: int, y: int) -> int:
	return _territory_cell_province_ids[y * _territory_cell_width + x]


func _shape_alignment(body: PackedInt32Array) -> Dictionary:
	var t_bbox_start := Time.get_ticks_usec()
	_last_bbox_setup_us = 0
	_last_scan_us = 0
	if _territory_image == null or _territory_scale <= 0:
		return {}
	var owned := {}
	var pixel_bounds := Rect2i()
	var has_bounds := false
	for province_id in body:
		owned[province_id] = true
		var province_bounds := _graph.bounding_rect(province_id)
		if province_bounds.has_area():
			pixel_bounds = province_bounds if not has_bounds else pixel_bounds.merge(province_bounds)
			has_bounds = true
	if not has_bounds:
		_last_bbox_setup_us = Time.get_ticks_usec() - t_bbox_start
		return {}
	var min_cell := Vector2i(
		clampi(pixel_bounds.position.x / _territory_scale, 0, _territory_image.get_width() - 1),
		clampi(pixel_bounds.position.y / _territory_scale, 0, _territory_image.get_height() - 1)
	)
	var max_cell := Vector2i(
		clampi(ceili(float(pixel_bounds.end.x) / float(_territory_scale)), min_cell.x + 1, _territory_image.get_width()),
		clampi(ceili(float(pixel_bounds.end.y) / float(_territory_scale)), min_cell.y + 1, _territory_image.get_height())
	)
	var t_scan_start := Time.get_ticks_usec()
	_last_bbox_setup_us = t_scan_start - t_bbox_start
	var count := 0
	var coordinate_sum := Vector2.ZERO
	var square_sum := Vector2.ZERO
	var cross_sum := 0.0
	for y in range(min_cell.y, max_cell.y):
		for x in range(min_cell.x, max_cell.x):
			if not owned.has(_territory_province_id(x, y)):
				continue
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			count += 1
			coordinate_sum += point
			square_sum += point * point
			cross_sum += point.x * point.y
	_last_scan_us = Time.get_ticks_usec() - t_scan_start
	if count < MIN_SHAPE_CELLS:
		return {}
	var mean := coordinate_sum / float(count)
	var covariance_xx := maxf(0.0, square_sum.x / float(count) - mean.x * mean.x)
	var covariance_yy := maxf(0.0, square_sum.y / float(count) - mean.y * mean.y)
	var covariance_xy := cross_sum / float(count) - mean.x * mean.y
	var trace := covariance_xx + covariance_yy
	var discriminant := sqrt(maxf(0.0, (covariance_xx - covariance_yy) * (covariance_xx - covariance_yy) + 4.0 * covariance_xy * covariance_xy))
	var major_eigenvalue := maxf(0.0, (trace + discriminant) * 0.5)
	var minor_eigenvalue := maxf(0.0, (trace - discriminant) * 0.5)
	if major_eigenvalue <= 0.0001:
		return {}
	var anisotropy := clampf(1.0 - minor_eigenvalue / major_eigenvalue, 0.0, 1.0)
	var angle := 0.5 * atan2(2.0 * covariance_xy, covariance_xx - covariance_yy)
	var angle_degrees := rad_to_deg(angle)
	if anisotropy < MIN_ALIGNMENT_ANISOTROPY:
		angle_degrees = 0.0
	angle_degrees = clampf(angle_degrees, -MAX_LABEL_ANGLE_DEGREES, MAX_LABEL_ANGLE_DEGREES)
	if absf(angle_degrees) < 4.0:
		angle_degrees = 0.0
	angle = deg_to_rad(angle_degrees)
	var direction := Vector2(cos(angle), sin(angle))
	var perpendicular := Vector2(-direction.y, direction.x)
	var major_variance := maxf(0.0, direction.x * direction.x * covariance_xx + 2.0 * direction.x * direction.y * covariance_xy + direction.y * direction.y * covariance_yy)
	var minor_variance := maxf(0.0, perpendicular.x * perpendicular.x * covariance_xx + 2.0 * perpendicular.x * perpendicular.y * covariance_xy + perpendicular.y * perpendicular.y * covariance_yy)
	var major_span_cells := maxf(1.0, sqrt(major_variance) * MAJOR_AXIS_SIGMA_SPAN)
	var minor_span_cells := maxf(1.0, sqrt(minor_variance) * MINOR_AXIS_SIGMA_SPAN)
	return {
		"center": mean * float(_territory_scale),
		"angle_degrees": angle_degrees,
		"anisotropy": anisotropy,
		"cell_count": count,
		"world_size": Vector2(major_span_cells, minor_span_cells) * float(_territory_scale) * MAP_PIXEL_SIZE,
	}


func _label_basis(angle_degrees: float) -> Basis:
	var angle := deg_to_rad(angle_degrees)
	var direction := Vector2(cos(angle), sin(angle))
	return Basis(
		Vector3(direction.x, 0.0, direction.y),
		Vector3(direction.y, 0.0, -direction.x),
		Vector3.UP
	)


func _make_layout(tag: String, body: PackedInt32Array, region: Rect2i, shape: Dictionary) -> Dictionary:
	if _label_font == null:
		return {}
	var full_name: String = String(simulation_controller.country_registry.display_name(tag))
	if full_name.is_empty():
		return {}
	var map_center := Vector2.ZERO
	var region_world_size := Vector2.ZERO
	if region.has_area():
		map_center = (Vector2(region.position) + Vector2(region.size) * 0.5) * float(_territory_scale)
		region_world_size = Vector2(region.size) * float(_territory_scale) * MAP_PIXEL_SIZE
	else:
		var anchor: Vector2i = _graph.anchor(body[0])
		map_center = Vector2(anchor)
		region_world_size = Vector2(MAP_PIXEL_SIZE, MAP_PIXEL_SIZE)
	var angle_degrees := 0.0
	var fit_world_size := region_world_size
	var fit_mode := "territory"
	if not shape.is_empty():
		map_center = shape["center"]
		angle_degrees = float(shape["angle_degrees"])
		fit_world_size = shape["world_size"]
		fit_mode = "shape_aligned"

	var text: String = full_name
	var text_pixels := _text_pixel_bounds(text)
	var pixel_size := _fit_pixel_size(text_pixels, fit_world_size, SHAPE_LABEL_FILL if not shape.is_empty() else LABEL_FILL)
	var fits_territory := pixel_size > 0.0
	if pixel_size < MIN_READABLE_PIXEL_SIZE:
		fit_mode = "screen_fallback"
		pixel_size = MIN_READABLE_PIXEL_SIZE
		fits_territory = false
	pixel_size = minf(pixel_size, MAX_PIXEL_SIZE)
	var world_position := Vector3(
		map_center.x * MAP_PIXEL_SIZE - MAP_HALF_WIDTH,
		_height_at_map_pixel(map_center) + LABEL_LIFT,
		map_center.y * MAP_PIXEL_SIZE - MAP_HALF_HEIGHT
	)
	var half_world := text_pixels * pixel_size * 0.5
	var territory_world := Rect2(
		Vector2(
			float(region.position.x * _territory_scale) * MAP_PIXEL_SIZE - MAP_HALF_WIDTH,
			float(region.position.y * _territory_scale) * MAP_PIXEL_SIZE - MAP_HALF_HEIGHT
		),
		region_world_size
	)
	return {
		"tag": tag,
		"full_name": full_name,
		"text": text,
		"fit_mode": fit_mode,
		"fits_territory": fits_territory,
		"position": world_position,
		"basis": _label_basis(angle_degrees),
		"angle_degrees": angle_degrees,
		"alignment_anisotropy": float(shape.get("anisotropy", 0.0)),
		"shape_cell_count": int(shape.get("cell_count", 0)),
		"fit_world_size": fit_world_size,
		"pixel_size": pixel_size,
		"half_world": half_world,
		"weight": body.size(),
		"body_province_count": body.size(),
		"territory_rect_cells": region,
		"territory_rect_world": territory_world,
	}


func _text_pixel_bounds(text: String) -> Vector2:
	var size := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT_SIZE)
	var outline := float(LABEL_OUTLINE_SIZE * 2)
	return Vector2(size.x + outline, maxf(size.y, _label_font.get_height(LABEL_FONT_SIZE)) + outline)


func _fit_pixel_size(text_pixels: Vector2, region_world_size: Vector2, fill: float) -> float:
	if text_pixels.x <= 0.0 or text_pixels.y <= 0.0 or region_world_size.x <= 0.0 or region_world_size.y <= 0.0:
		return 0.0
	return minf(region_world_size.x / text_pixels.x, region_world_size.y / text_pixels.y) * fill


func _height_at_map_pixel(pixel: Vector2) -> float:
	if _height_image == null or _height_image.is_empty():
		return 0.0
	var sample_x := clampi(int(pixel.x / float(_graph.map_size.x) * _height_image.get_width()), 0, _height_image.get_width() - 1)
	var sample_y := clampi(int(pixel.y / float(_graph.map_size.y) * _height_image.get_height()), 0, _height_image.get_height() - 1)
	return _height_image.get_pixel(sample_x, sample_y).r * _height_scale


func _camera_or_viewport_changed() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var viewport_size := get_viewport().get_visible_rect().size
	var changed := (
		not _camera_signature_valid
		or not camera.global_transform.is_equal_approx(_last_camera_transform)
		or not viewport_size.is_equal_approx(_last_viewport_size)
		or camera.projection != _last_camera_projection
		or not is_equal_approx(camera.fov, _last_camera_fov)
		or not is_equal_approx(camera.size, _last_camera_size)
	)
	if changed:
		_camera_signature_valid = true
		_last_camera_transform = camera.global_transform
		_last_viewport_size = viewport_size
		_last_camera_projection = camera.projection
		_last_camera_fov = camera.fov
		_last_camera_size = camera.size
	return changed


func _country_labels_allowed() -> bool:
	var map_hud = simulation_controller.map_hud
	if map_hud == null:
		return true
	if map_hud.has_method("country_labels_visible"):
		return bool(map_hud.country_labels_visible())
	if map_hud.has_method("get_map_mode"):
		return int(map_hud.get_map_mode()) != DEBUG_MAP_MODE
	return true


func _update_visibility() -> void:
	var started := Time.get_ticks_usec()
	_visibility_dirty = false
	_visibility_revision += 1
	_screen_rects.clear()
	if not _country_labels_allowed():
		_desired_visible.clear()
		_pending_node_tags.clear()
		_hide_all_nodes()
		_clear_batched_instances()
		_finish_visibility_metrics(started)
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_label_render_scale = _camera_label_scale(camera)
	var min_count := maxf(1.0, (camera.global_position.y - 0.8) * 1.5)
	var candidates: Array[String] = []
	for raw_tag in _layouts:
		var tag := String(raw_tag)
		var layout: Dictionary = _layouts[tag]
		if float(layout.get("weight", 0)) >= min_count:
			if String(layout.get("fit_mode", "")) != "screen_fallback" or camera.global_position.y <= 2.2:
				candidates.append(tag)
	var close_zoom := camera.global_position.y <= 2.2
	var screen_distances := {}
	if close_zoom:
		var viewport_center := get_viewport().get_visible_rect().size * 0.5
		for tag in candidates:
			var position: Vector3 = (_layouts[tag] as Dictionary)["position"]
			screen_distances[tag] = camera.unproject_position(position).distance_squared_to(viewport_center)
	candidates.sort_custom(func(first: String, second: String) -> bool:
		var first_weight := int((_layouts[first] as Dictionary).get("weight", 0))
		var second_weight := int((_layouts[second] as Dictionary).get("weight", 0))
		if close_zoom:
			var first_distance := float(screen_distances.get(first, INF))
			var second_distance := float(screen_distances.get(second, INF))
			if not is_equal_approx(first_distance, second_distance):
				return first_distance < second_distance
		return first < second if first_weight == second_weight else first_weight > second_weight
	)

	var collision_grid: Dictionary = {}
	var kept_rects: Dictionary = {}
	var visible := {}
	var visible_order: Array[String] = []
	var viewport_bounds := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(64.0)
	for tag in candidates:
		var rect := _projected_screen_rect(camera, _layouts[tag])
		if not rect.has_area():
			continue
		# Labels smaller than this cannot communicate a full public country
		# name at normal viewing distance. Let them appear at the next closer
		# zoom instead of spending several Label3D draws on illegible text.
		if rect.size.x < MIN_PROJECTED_LABEL_WIDTH or rect.size.y < MIN_PROJECTED_LABEL_HEIGHT:
			continue
		rect = rect.grow(SCREEN_COLLISION_PADDING)
		if not rect.intersects(viewport_bounds):
			continue
		# A country close to the camera horizon can project far beyond the
		# viewport. Off-screen area cannot collide with a visible label, and
		# clipping it here prevents unbounded collision-grid iteration.
		rect = rect.intersection(viewport_bounds)
		if not rect.has_area():
			continue
		if _screen_rect_collides(rect, collision_grid, kept_rects):
			continue
		visible[tag] = true
		visible_order.append(tag)
		kept_rects[tag] = rect
		_screen_rects[tag] = rect
		_add_screen_rect_to_grid(tag, rect, collision_grid)

	_desired_visible = visible
	_pending_node_tags.clear()
	if use_batched_msdf_renderer:
		_hide_all_nodes()
		_rebuild_batched_glyphs(visible_order, camera)
		_finish_visibility_metrics(started)
		return
	for raw_tag in _label_nodes:
		var label := _label_nodes[raw_tag] as Label3D
		label.visible = visible.has(raw_tag)
		if _layouts.has(raw_tag):
			label.pixel_size = float((_layouts[raw_tag] as Dictionary)["pixel_size"]) * _label_render_scale
	for tag in visible_order:
		if not _label_nodes.has(tag):
			_pending_node_tags.append(tag)
	_finish_visibility_metrics(started)


func _rebuild_batched_glyphs(visible_order: Array[String], camera: Camera3D) -> void:
	_reset_batch_pan_offset()
	_batch_translation_pending = false
	_batched_visible_tags.clear()
	_batch_glyph_count = 0
	if not _font_atlas_ready or _base_font == null or _batch_pages.is_empty():
		_clear_batched_instances()
		return
	var page_instances: Dictionary = {}
	for raw_page in _batch_pages:
		page_instances[int(raw_page)] = []
	for tag in visible_order:
		if not _layouts.has(tag):
			continue
		var glyphs := _build_screen_glyphs(camera, _layouts[tag] as Dictionary)
		if glyphs.is_empty():
			continue
		_batched_visible_tags[tag] = true
		for glyph in glyphs:
			var record := glyph as Dictionary
			var page := int(record["page"])
			if not page_instances.has(page):
				continue
			(page_instances[page] as Array).append(record)
			_batch_glyph_count += 1
	for raw_page in _batch_pages:
		var page := int(raw_page)
		var page_record := _batch_pages[page] as Dictionary
		var instance := page_record["node"] as MultiMeshInstance2D
		var multimesh := page_record["multimesh"] as MultiMesh
		var records := page_instances.get(page, []) as Array
		multimesh.instance_count = records.size()
		for index in records.size():
			var glyph := records[index] as Dictionary
			multimesh.set_instance_transform_2d(index, glyph["transform"] as Transform2D)
			multimesh.set_instance_custom_data(index, glyph["uv_rect"] as Color)
		instance.visible = not records.is_empty()
	_capture_batch_pan_reference(camera)


func _capture_batch_pan_reference(camera: Camera3D) -> void:
	_batch_pan_reference_valid = camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	_batch_reference_camera_transform = camera.global_transform
	_batch_reference_camera_size = camera.size
	_batch_reference_viewport_size = get_viewport().get_visible_rect().size
	_batch_reference_world = Vector3(camera.global_position.x, 0.0, camera.global_position.z)
	_batch_reference_screen = camera.unproject_position(_batch_reference_world)


func _translate_batch_for_orthographic_pan() -> bool:
	if not use_batched_msdf_renderer or not _batch_pan_reference_valid or _batch_root == null:
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return false
	var viewport_size := get_viewport().get_visible_rect().size
	var compatible := (
		is_equal_approx(camera.size, _batch_reference_camera_size)
		and viewport_size.is_equal_approx(_batch_reference_viewport_size)
		and camera.global_transform.basis.is_equal_approx(_batch_reference_camera_transform.basis)
		and is_equal_approx(camera.global_position.y, _batch_reference_camera_transform.origin.y)
	)
	if not compatible:
		return false
	var offset := camera.unproject_position(_batch_reference_world) - _batch_reference_screen
	if offset.length() >= BATCH_REBUILD_PAN_THRESHOLD:
		return false
	_batch_screen_offset = offset
	_batch_root.position = offset
	_visibility_revision += 1
	return true


func _reset_batch_pan_offset() -> void:
	_batch_screen_offset = Vector2.ZERO
	if _batch_root != null:
		_batch_root.position = Vector2.ZERO


func _build_screen_glyphs(camera: Camera3D, layout: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var position: Vector3 = layout["position"]
	if camera.is_position_behind(position):
		return result
	var basis: Basis = layout["basis"]
	var world_pixel_size := float(layout["pixel_size"]) * _label_render_scale
	var screen_center := camera.unproject_position(position)
	var screen_x_point := camera.unproject_position(position + basis.x * world_pixel_size)
	var screen_y_point := camera.unproject_position(position + basis.y * world_pixel_size)
	var screen_x_vector := screen_x_point - screen_center
	var screen_y_vector := screen_y_point - screen_center
	if screen_x_vector.length_squared() <= 0.000001 or screen_y_vector.length_squared() <= 0.000001:
		return result
	var x_scale := screen_x_vector.length()
	var y_scale := screen_y_vector.length()
	var x_direction := screen_x_vector.normalized()
	var y_direction := screen_y_vector.normalized()
	var text := String(layout["text"])
	var font_size := Vector2i(LABEL_FONT_SIZE, LABEL_FONT_SIZE)
	var cursor_x := 0.0
	var previous_glyph := -1
	var pending: Array[Dictionary] = []
	var local_bounds := Rect2()
	var has_bounds := false
	for character_index in text.length():
		var codepoint := text.unicode_at(character_index)
		var glyph_index := _base_font.get_glyph_index(LABEL_FONT_SIZE, codepoint, 0)
		if glyph_index <= 0:
			glyph_index = _base_font.get_glyph_index(LABEL_FONT_SIZE, "?".unicode_at(0), 0)
		if previous_glyph >= 0:
			cursor_x += _base_font.get_kerning(0, LABEL_FONT_SIZE, Vector2i(previous_glyph, glyph_index)).x
		var glyph_size := _base_font.get_glyph_size(0, font_size, glyph_index)
		var glyph_offset := _base_font.get_glyph_offset(0, font_size, glyph_index)
		var texture_index := _base_font.get_glyph_texture_idx(0, font_size, glyph_index)
		if texture_index >= 0 and glyph_size.x > 0.0 and glyph_size.y > 0.0 and _batch_pages.has(texture_index):
			var glyph_rect := Rect2(Vector2(cursor_x, 0.0) + glyph_offset, glyph_size)
			local_bounds = glyph_rect if not has_bounds else local_bounds.merge(glyph_rect)
			has_bounds = true
			pending.append({
				"page": texture_index,
				"rect": glyph_rect,
				"atlas_rect": _base_font.get_glyph_uv_rect(0, font_size, glyph_index),
			})
		cursor_x += _base_font.get_glyph_advance(0, LABEL_FONT_SIZE, glyph_index).x
		previous_glyph = glyph_index
	if not has_bounds:
		return result
	var local_center := local_bounds.get_center()
	for raw_glyph in pending:
		var glyph := raw_glyph as Dictionary
		var glyph_rect := glyph["rect"] as Rect2
		var local_position := glyph_rect.get_center() - local_center
		var glyph_center := screen_center + x_direction * local_position.x * x_scale + y_direction * local_position.y * y_scale
		var transform := Transform2D(
			x_direction * glyph_rect.size.x * x_scale,
			y_direction * glyph_rect.size.y * y_scale,
			glyph_center
		)
		var page_record := _batch_pages[int(glyph["page"])] as Dictionary
		var atlas_size := page_record["atlas_size"] as Vector2
		var atlas_rect := glyph["atlas_rect"] as Rect2
		result.append({
			"page": int(glyph["page"]),
			"transform": transform,
			"uv_rect": Color(
				atlas_rect.position.x / atlas_size.x,
				atlas_rect.position.y / atlas_size.y,
				atlas_rect.size.x / atlas_size.x,
				atlas_rect.size.y / atlas_size.y
			),
		})
	return result


func _clear_batched_instances() -> void:
	_reset_batch_pan_offset()
	_batch_pan_reference_valid = false
	_batch_translation_pending = false
	_batched_visible_tags.clear()
	_batch_glyph_count = 0
	for record in _batch_pages.values():
		var page_record := record as Dictionary
		var multimesh := page_record.get("multimesh") as MultiMesh
		var instance := page_record.get("node") as MultiMeshInstance2D
		if multimesh != null:
			multimesh.instance_count = 0
		if instance != null:
			instance.visible = false


func _process_node_creation_queue() -> void:
	var started := Time.get_ticks_usec()
	var count := mini(_pending_node_tags.size(), MAX_NODE_CREATIONS_PER_FRAME)
	for _index in count:
		var tag: String = _pending_node_tags.pop_front()
		if not _desired_visible.has(tag) or not _layouts.has(tag):
			continue
		var label := _ensure_label_node(tag)
		label.pixel_size = float((_layouts[tag] as Dictionary)["pixel_size"]) * _label_render_scale
		label.visible = true
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_metrics["last_node_batch_ms"] = elapsed_ms
	_metrics["max_node_batch_ms"] = maxf(float(_metrics["max_node_batch_ms"]), elapsed_ms)
	_metrics["node_count"] = _label_nodes.size()


func _projected_screen_rect(camera: Camera3D, layout: Dictionary) -> Rect2:
	var position: Vector3 = layout["position"]
	if camera.is_position_behind(position):
		return Rect2()
	var basis: Basis = layout["basis"]
	var half: Vector2 = (layout["half_world"] as Vector2) * _label_render_scale
	var points: Array[Vector2] = []
	var directions: Array[float] = [-1.0, 1.0]
	for horizontal in directions:
		for vertical in directions:
			var corner: Vector3 = position + basis.x * half.x * horizontal + basis.y * half.y * vertical
			if camera.is_position_behind(corner):
				return Rect2()
			points.append(camera.unproject_position(corner))
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect


func _camera_label_scale(camera: Camera3D) -> float:
	var height_ratio := clampf(inverse_lerp(MIN_LABEL_SCALE_CAMERA_HEIGHT, FULL_LABEL_SCALE_CAMERA_HEIGHT, camera.global_position.y), 0.0, 1.0)
	return lerpf(MIN_CLOSE_ZOOM_LABEL_SCALE, 1.0, height_ratio)


func _screen_rect_collides(rect: Rect2, grid: Dictionary, kept_rects: Dictionary) -> bool:
	var checked := {}
	var cell_min := Vector2i(floori(rect.position.x / COLLISION_GRID_SIZE), floori(rect.position.y / COLLISION_GRID_SIZE))
	var cell_max := Vector2i(floori(rect.end.x / COLLISION_GRID_SIZE), floori(rect.end.y / COLLISION_GRID_SIZE))
	for cell_y in range(cell_min.y, cell_max.y + 1):
		for cell_x in range(cell_min.x, cell_max.x + 1):
			var cell := Vector2i(cell_x, cell_y)
			for raw_tag in (grid.get(cell, []) as Array):
				var tag := String(raw_tag)
				if checked.has(tag):
					continue
				checked[tag] = true
				if rect.intersects(kept_rects[tag] as Rect2):
					return true
	return false


func _add_screen_rect_to_grid(tag: String, rect: Rect2, grid: Dictionary) -> void:
	var cell_min := Vector2i(floori(rect.position.x / COLLISION_GRID_SIZE), floori(rect.position.y / COLLISION_GRID_SIZE))
	var cell_max := Vector2i(floori(rect.end.x / COLLISION_GRID_SIZE), floori(rect.end.y / COLLISION_GRID_SIZE))
	for cell_y in range(cell_min.y, cell_max.y + 1):
		for cell_x in range(cell_min.x, cell_max.x + 1):
			var cell := Vector2i(cell_x, cell_y)
			if not grid.has(cell):
				grid[cell] = []
			(grid[cell] as Array).append(tag)


func _ensure_label_node(tag: String) -> Label3D:
	if _label_nodes.has(tag):
		return _label_nodes[tag]
	var label := Label3D.new()
	label.name = "Country_%s" % tag
	label.font = _label_font
	label.font_size = LABEL_FONT_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = true
	label.no_depth_test = true
	label.render_priority = 2
	label.outline_render_priority = 1
	label.modulate = LABEL_INK
	label.outline_modulate = Color.TRANSPARENT
	label.outline_size = LABEL_OUTLINE_SIZE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The font is imported as MSDF, so one sharp glyph atlas supports the full
	# country-label zoom range without blurred bitmap mip transitions.
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	add_child(label)
	_label_nodes[tag] = label
	_apply_layout(label, _layouts[tag])
	return label


func _apply_layout(label: Label3D, layout: Dictionary) -> void:
	label.text = String(layout["text"])
	label.pixel_size = float(layout["pixel_size"])
	label.position = layout["position"]
	label.basis = layout["basis"]


func _hide_all_nodes() -> void:
	for label in _label_nodes.values():
		(label as Label3D).visible = false


func _update_layout_metrics() -> void:
	var territory_fit_count := 0
	var shape_aligned_count := 0
	var screen_fallback_count := 0
	for layout in _layouts.values():
		match String((layout as Dictionary).get("fit_mode", "")):
			"territory": territory_fit_count += 1
			"shape_aligned": shape_aligned_count += 1
			"screen_fallback": screen_fallback_count += 1
	_metrics["layout_count"] = _layouts.size()
	_metrics["territory_fit_count"] = territory_fit_count + shape_aligned_count
	_metrics["shape_aligned_count"] = shape_aligned_count
	_metrics["full_name_count"] = territory_fit_count + shape_aligned_count + screen_fallback_count
	_metrics["screen_fallback_count"] = screen_fallback_count
	_update_render_metrics()


func _finish_visibility_metrics(started_usec: int) -> void:
	_metrics["last_visibility_ms"] = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_metrics["visible_count"] = _screen_rects.size()
	_update_render_metrics()


func _update_render_metrics() -> void:
	if _hardware_compatibility_mode:
		_metrics["node_count"] = 0
		_metrics["batch_draw_count"] = 0
		_metrics["batch_glyph_count"] = 0
		_metrics["label3d_node_count"] = 0
		_metrics["renderer"] = "disabled_hardware_compatibility"
		return
	if use_batched_msdf_renderer:
		var active_pages := 0
		for record in _batch_pages.values():
			var instance := (record as Dictionary).get("node") as MultiMeshInstance2D
			if instance != null and instance.visible:
				active_pages += 1
		_metrics["node_count"] = active_pages
		_metrics["batch_draw_count"] = active_pages
		_metrics["batch_glyph_count"] = _batch_glyph_count
		_metrics["label3d_node_count"] = _label_nodes.size()
		_metrics["renderer"] = "screen_space_msdf_multimesh"
	else:
		_metrics["node_count"] = _label_nodes.size()
		_metrics["batch_draw_count"] = 0
		_metrics["batch_glyph_count"] = 0
		_metrics["label3d_node_count"] = _label_nodes.size()
		_metrics["renderer"] = "label3d_fallback"


# Test/profiling API. These methods intentionally return copies.
func debug_metrics() -> Dictionary:
	_update_layout_metrics()
	return _metrics.duplicate(true)


## FL8.2a: only populated when the LABEL_STAGE_PROFILE environment variable
## is set at startup - avoids any always-on overhead for normal play/tests.
func debug_batch_durations_ms() -> Array[float]:
	return _debug_batch_durations_ms.duplicate()


func debug_stage_timings(tag: String) -> Dictionary:
	return (_debug_stage_timings.get(tag, {}) as Dictionary).duplicate()


func debug_label_style() -> Dictionary:
	return {
		"fill_color": LABEL_INK,
		"outline_size": LABEL_OUTLINE_SIZE,
		"minimum_screen_width": MIN_PROJECTED_LABEL_WIDTH,
		"minimum_screen_height": MIN_PROJECTED_LABEL_HEIGHT,
		"background_enabled": false,
	}


func debug_layout(tag: String) -> Dictionary:
	return (_layouts.get(tag, {}) as Dictionary).duplicate(true)


func debug_layout_count() -> int:
	return _layouts.size()


func debug_layout_tags() -> Array[String]:
	var tags: Array[String] = []
	for raw_tag in _layouts:
		tags.append(String(raw_tag))
	tags.sort()
	return tags


func debug_node_count() -> int:
	_update_render_metrics()
	return int(_metrics["node_count"])


func debug_has_node(tag: String) -> bool:
	return _batched_visible_tags.has(tag) if use_batched_msdf_renderer else _label_nodes.has(tag)


func debug_visible_tags() -> Array[String]:
	var tags: Array[String] = []
	for raw_tag in _screen_rects:
		tags.append(String(raw_tag))
	tags.sort()
	return tags


func debug_screen_rects() -> Dictionary:
	var rects := _screen_rects.duplicate(true)
	if use_batched_msdf_renderer and not _batch_screen_offset.is_zero_approx():
		var bounds := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(64.0)
		var outside: Array = []
		for raw_tag in rects:
			var rect := rects[raw_tag] as Rect2
			rect.position += _batch_screen_offset
			if not rect.intersects(bounds):
				outside.append(raw_tag)
			else:
				rects[raw_tag] = rect.intersection(bounds)
		for raw_tag in outside:
			rects.erase(raw_tag)
	return rects


func debug_pending_count() -> int:
	return _pending_tags.size() + _pending_node_tags.size() + (1 if _full_rebuild_pending else 0)


func debug_last_rebuilt_tags() -> Array[String]:
	return _last_rebuilt_tags.duplicate()


func debug_visibility_revision() -> int:
	return _visibility_revision


func debug_render_scale() -> float:
	return _label_render_scale


func debug_viewport_size() -> Vector2:
	return _last_viewport_size


func debug_font_path() -> String:
	return FONT_PATH
