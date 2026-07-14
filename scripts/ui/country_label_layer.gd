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
const TERRITORY_MAP_PATH := "res://assets/label_territory_map.png"
const TERRITORY_METADATA_PATH := "res://assets/label_territory_map.json"
const MAP_PIXEL_SIZE := 0.01
const MAP_HALF_WIDTH := 28.16
const MAP_HALF_HEIGHT := 10.24
const LABEL_FONT_SIZE := 64
const LABEL_OUTLINE_SIZE := 4
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
const MAX_INCREMENTAL_TAGS_PER_FRAME := 4
const MAX_NODE_CREATIONS_PER_FRAME := 24
const DEBUG_MAP_MODE := 2

@export var simulation_controller: GrandWorldSimulationController
@export var map_render: Node

var _graph: ProvinceGraph
var _height_image: Image
var _height_scale := 0.35
var _territory_image: Image
var _territory_scale := 0
var _label_font: FontVariation

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
var _last_rebuilt_tags: Array[String] = []
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
	"visible_count": 0,
	"territory_fit_count": 0,
	"shape_aligned_count": 0,
	"full_name_count": 0,
	"screen_fallback_count": 0,
}


func _ready() -> void:
	_graph = ProvinceGraph.load_default()
	_load_bundled_font()
	_load_territory_map()
	_load_heightmap()
	if map_render != null and map_render.get("final_material") != null:
		var scale_param = map_render.final_material.get_shader_parameter("terrain_height_scale")
		if scale_param != null:
			_height_scale = float(scale_param)


func _load_bundled_font() -> void:
	var base_font := load(FONT_PATH) as Font
	if base_font == null:
		push_error("Country labels require bundled font %s" % FONT_PATH)
		return
	_label_font = FontVariation.new()
	_label_font.base_font = base_font


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
	var file := FileAccess.open(TERRITORY_MAP_PATH, FileAccess.READ)
	if file == null:
		push_error("Country label territory map is missing: %s" % TERRITORY_MAP_PATH)
		return
	_territory_image = Image.new()
	var error := _territory_image.load_png_from_buffer(file.get_buffer(file.get_length()))
	if error != OK:
		push_error("Country label territory map failed to decode: %s" % error_string(error))
		_territory_image = null


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
	if simulation_controller == null or not simulation_controller.initialized:
		return
	_connect_events()
	if _full_rebuild_pending:
		_begin_full_rebuild()
	if not _pending_tags.is_empty():
		_process_incremental_layouts()
	if _visibility_dirty or _camera_or_viewport_changed():
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
	var body := _main_land_body(tag)
	if body.is_empty():
		_remove_country(tag)
		return
	var shape := _shape_alignment(body)
	var region := Rect2i() if not shape.is_empty() else _largest_safe_rectangle(body)
	var layout := _make_layout(tag, body, region, shape)
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
	var colour := _territory_image.get_pixel(x, y)
	return (
		roundi(colour.r * 255.0) * 65536
		+ roundi(colour.g * 255.0) * 256
		+ roundi(colour.b * 255.0)
	)


func _shape_alignment(body: PackedInt32Array) -> Dictionary:
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
		return {}
	var min_cell := Vector2i(
		clampi(pixel_bounds.position.x / _territory_scale, 0, _territory_image.get_width() - 1),
		clampi(pixel_bounds.position.y / _territory_scale, 0, _territory_image.get_height() - 1)
	)
	var max_cell := Vector2i(
		clampi(ceili(float(pixel_bounds.end.x) / float(_territory_scale)), min_cell.x + 1, _territory_image.get_width()),
		clampi(ceili(float(pixel_bounds.end.y) / float(_territory_scale)), min_cell.y + 1, _territory_image.get_height())
	)
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
	)
	if changed:
		_camera_signature_valid = true
		_last_camera_transform = camera.global_transform
		_last_viewport_size = viewport_size
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
	for raw_tag in _label_nodes:
		var label := _label_nodes[raw_tag] as Label3D
		label.visible = visible.has(raw_tag)
		if _layouts.has(raw_tag):
			label.pixel_size = float((_layouts[raw_tag] as Dictionary)["pixel_size"]) * _label_render_scale
	for tag in visible_order:
		if not _label_nodes.has(tag):
			_pending_node_tags.append(tag)
	_finish_visibility_metrics(started)


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
	label.modulate = Color(0.055, 0.045, 0.035, 0.98)
	label.outline_modulate = Color(0.94, 0.9, 0.76, 0.62)
	label.outline_size = LABEL_OUTLINE_SIZE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	_metrics["node_count"] = _label_nodes.size()


func _finish_visibility_metrics(started_usec: int) -> void:
	_metrics["last_visibility_ms"] = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_metrics["node_count"] = _label_nodes.size()
	_metrics["visible_count"] = _screen_rects.size()


# Test/profiling API. These methods intentionally return copies.
func debug_metrics() -> Dictionary:
	_update_layout_metrics()
	return _metrics.duplicate(true)


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
	return _label_nodes.size()


func debug_has_node(tag: String) -> bool:
	return _label_nodes.has(tag)


func debug_visible_tags() -> Array[String]:
	var tags: Array[String] = []
	for raw_tag in _screen_rects:
		tags.append(String(raw_tag))
	tags.sort()
	return tags


func debug_screen_rects() -> Dictionary:
	return _screen_rects.duplicate(true)


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
