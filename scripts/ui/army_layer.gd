class_name ArmyLayer
extends Node3D

## Presentation of authoritative armies: country emblem + troop counter markers,
## the selected army's route, and a destination marker. Reads simulation state
## and never writes it;
## deleting this node cannot affect any army.
##
## Markers are rebuilt only when an army event fires or the camera zoom
## changes; per-frame work is limited to interpolating armies in transit.

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")
const MARKER_ASSET_MANIFEST_PATH := "res://assets/marker_art/generated/marker_asset_manifest.json"
const SHIELD_ATLAS_PATH := "res://assets/marker_art/generated/country_shield_atlas.png"
const ARMY_FLAG_SHADER_PATH := "res://shaders/army_flag_marker.gdshader"
const ARMY_COUNTER_SHADER_PATH := "res://shaders/army_troop_counter.gdshader"
const MAX_DISPLAYED_TROOPS := 99999.0

const MAP_PIXEL_SIZE := 0.01
const MAP_HALF_WIDTH := 28.16
const MAP_HALF_HEIGHT := 10.24
const MAP_WORLD_WIDTH := MAP_HALF_WIDTH * 2.0
const MARKER_HALF_HEIGHT := 0.025
const FLAG_MARKER_SIZE := Vector2(0.09, 0.105)
const TROOP_COUNTER_SIZE := Vector2(0.18, 0.085)
const FLAG_MARKER_X_OFFSET := -0.045
const TROOP_COUNTER_X_OFFSET := 0.09
const STACK_X_SPACING := 0.03
const ROUTE_LIFT := 0.03
const ROUTE_WIDTH := 0.05
const ROUTE_INNER_PIXELS := 3.0
const ROUTE_OUTLINE_PIXELS := 5.5
const ROUTE_PREVIEW_DASH_PIXELS := 11.0
const ROUTE_PREVIEW_GAP_PIXELS := 7.0
const ROUTE_RETREAT_DASH_PIXELS := 5.0
const ROUTE_RETREAT_GAP_PIXELS := 5.0
# Markers keep a constant on-screen size: world scale is proportional to
# camera height, clamped so they never dwarf a province or vanish up close.
const MARKER_REFERENCE_HEIGHT := 3.5
const MARKER_MIN_SCALE := 0.2
const MARKER_MAX_SCALE := 1.1
# Beyond these camera heights the marker field fades out, then hides; the
# selected army stays visible so an ordered move can always be followed.
const MARKER_FADE_START_HEIGHT := 3.2
const MARKER_HIDE_HEIGHT := 4.6

@export var simulation_controller: GrandWorldSimulationController
@export var map_render: Node
@export var camera_controller: StrategyCameraController

var _graph: ProvinceGraph
var _height_image: Image
var _height_scale := 0.35
var _markers := MultiMeshInstance3D.new()
var _troop_counters := MultiMeshInstance3D.new()
var _selection_ring := MeshInstance3D.new()
var _route_outline_mesh := ImmediateMesh.new()
var _route_outline_instance := MeshInstance3D.new()
var _route_mesh := ImmediateMesh.new()
var _route_instance := MeshInstance3D.new()
var _destination_marker := MeshInstance3D.new()
var _invalid_destination_marker := Node3D.new()
var _selected_army_id := ""
var _preview_path := PackedInt32Array()
var _invalid_destination_id := -1
var _anchor_cache: Dictionary = {}
var _army_ids: Array = []
var _moving_markers: Array = []
var _events_connected := false
var _layout_dirty := true
var _route_dirty := true
var _last_marker_scale := -1.0
var _last_zoom_fade := -1.0
var _route_style := "none"
var _last_route_inner_width := 0.0
var _last_route_outline_width := 0.0
var _route_wrap_splits := 0
var _country_flag_indices: Dictionary = {}
var _shield_atlas_slots := 1024.0


func _ready() -> void:
	_load_marker_assets()
	_graph = ProvinceGraph.load_default()
	var height_texture := load("res://assets/heightmap.png") as Texture2D
	if height_texture != null:
		_height_image = height_texture.get_image()
		if _height_image != null and _height_image.is_compressed():
			_height_image.decompress()
	if map_render != null and map_render.get("final_material") != null:
		var scale_param = map_render.final_material.get_shader_parameter("terrain_height_scale")
		if scale_param != null:
			_height_scale = float(scale_param)

	var marker_mesh := PlaneMesh.new()
	# The emblem is the left half of a composite army marker. Troop strength is
	# rendered beside it, so unexplained standalone country flags no longer sit
	# over the map.
	marker_mesh.size = FLAG_MARKER_SIZE
	marker_mesh.orientation = PlaneMesh.FACE_Y
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = marker_mesh
	_markers.multimesh = multimesh
	_markers.material_override = _flag_marker_material()
	# MultiMesh instances default to identity transforms. Keep the batch hidden
	# until authoritative army transforms have been written, otherwise hundreds
	# of markers overlap at world origin during startup/capture warm-up.
	_markers.visible = false
	add_child(_markers)

	var counter_mesh := PlaneMesh.new()
	counter_mesh.size = TROOP_COUNTER_SIZE
	counter_mesh.orientation = PlaneMesh.FACE_Y
	var counter_multimesh := MultiMesh.new()
	counter_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	counter_multimesh.use_colors = true
	counter_multimesh.use_custom_data = true
	counter_multimesh.mesh = counter_mesh
	_troop_counters.name = "TroopCounters"
	_troop_counters.multimesh = counter_multimesh
	_troop_counters.material_override = _troop_counter_material()
	_troop_counters.visible = false
	add_child(_troop_counters)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.028
	ring.outer_radius = 0.042
	_selection_ring.mesh = ring
	_selection_ring.material_override = _unshaded_material(Color(0.2, 0.85, 1.0))
	_selection_ring.visible = false
	add_child(_selection_ring)

	_route_outline_instance.mesh = _route_outline_mesh
	_route_outline_instance.material_override = _unshaded_material(Color(0.055, 0.04, 0.022), false, true, 1)
	add_child(_route_outline_instance)

	_route_instance.mesh = _route_mesh
	_route_instance.material_override = _unshaded_material(Color(1.0, 0.86, 0.24), false, true, 2)
	add_child(_route_instance)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.14
	_destination_marker.mesh = cone
	_destination_marker.material_override = _unshaded_material(Color(1.0, 0.72, 0.2))
	_destination_marker.visible = false
	add_child(_destination_marker)

	_invalid_destination_marker.name = "InvalidDestination"
	var invalid_material := _unshaded_material(Color(0.96, 0.22, 0.12), false, true, 3)
	for angle in [-PI * 0.25, PI * 0.25]:
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.18, 0.025, 0.035)
		bar.mesh = bar_mesh
		bar.material_override = invalid_material
		bar.rotation.y = angle
		_invalid_destination_marker.add_child(bar)
	_invalid_destination_marker.visible = false
	add_child(_invalid_destination_marker)


func _load_marker_assets() -> void:
	var file := FileAccess.open(MARKER_ASSET_MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_warning("Marker asset manifest is missing; army flags will use the first atlas slot.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Marker asset manifest is invalid; army flags will use the first atlas slot.")
		return
	var manifest := parsed as Dictionary
	var atlas: Dictionary = manifest.get("shield_atlas", {})
	_shield_atlas_slots = maxf(float(int(atlas.get("columns", 32)) * int(atlas.get("rows", 32))), 1.0)
	for raw_tag in (manifest.get("countries", {}) as Dictionary):
		var record: Dictionary = manifest["countries"][raw_tag]
		_country_flag_indices[String(raw_tag)] = int(record.get("atlas_index", 0))


func _flag_marker_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(ARMY_FLAG_SHADER_PATH) as Shader
	material.set_shader_parameter("shield_atlas", load(SHIELD_ATLAS_PATH) as Texture2D)
	material.set_shader_parameter("atlas_grid", Vector2(32.0, _shield_atlas_slots / 32.0))
	material.render_priority = 3
	return material


func _troop_counter_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(ARMY_COUNTER_SHADER_PATH) as Shader
	material.render_priority = 4
	return material


func _unshaded_material(color: Color, vertex_color := false, on_top := false, priority := 0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.vertex_color_use_as_albedo = vertex_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = on_top
	material.render_priority = priority
	return material


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	if events == null:
		return
	_events_connected = true
	events.army_movement_ordered.connect(_mark_dirty.unbind(3))
	events.army_moved.connect(_mark_dirty.unbind(3))
	events.army_movement_completed.connect(_mark_dirty.unbind(2))
	events.army_movement_blocked.connect(_mark_dirty.unbind(3))
	events.army_movement_cancelled.connect(_mark_dirty.unbind(1))
	events.army_disbanded.connect(_mark_dirty.unbind(1))
	events.recruitment_completed.connect(_mark_dirty.unbind(3))
	events.battle_started.connect(_mark_dirty.unbind(3))
	events.battle_reinforced.connect(_mark_dirty.unbind(3))
	events.battle_round_resolved.connect(_mark_dirty.unbind(4))
	events.battle_ended.connect(_mark_dirty.unbind(3))
	events.army_retreat_started.connect(_mark_dirty.unbind(2))
	events.army_recovered.connect(_mark_dirty.unbind(1))
	events.army_destroyed.connect(_mark_dirty.unbind(2))
	events.world_reloaded.connect(_mark_dirty.unbind(1))


func _mark_dirty() -> void:
	_layout_dirty = true
	_route_dirty = true


func set_selected_army(army_id: String) -> void:
	_selected_army_id = army_id
	_mark_dirty()


func selected_army() -> String:
	return _selected_army_id


func set_preview_path(path: PackedInt32Array) -> void:
	if path == _preview_path and _invalid_destination_id < 0:
		return
	_preview_path = path
	_invalid_destination_id = -1
	_route_dirty = true


func clear_preview_path() -> void:
	if _preview_path.is_empty() and _invalid_destination_id < 0:
		return
	_preview_path = PackedInt32Array()
	_invalid_destination_id = -1
	_route_dirty = true


func set_invalid_destination(province_id: int) -> void:
	if province_id == _invalid_destination_id and _preview_path.is_empty():
		return
	_preview_path = PackedInt32Array()
	_invalid_destination_id = province_id
	_route_dirty = true


func anchor_world_position(province_id: int) -> Vector3:
	if _anchor_cache.has(province_id):
		return _anchor_cache[province_id]
	var anchor := _graph.anchor(province_id)
	var world_x := anchor.x * MAP_PIXEL_SIZE - MAP_HALF_WIDTH
	var world_z := anchor.y * MAP_PIXEL_SIZE - MAP_HALF_HEIGHT
	var world_y := 0.0
	if _height_image != null:
		var sample_x := clampi(int(float(anchor.x) / _graph.map_size.x * _height_image.get_width()), 0, _height_image.get_width() - 1)
		var sample_y := clampi(int(float(anchor.y) / _graph.map_size.y * _height_image.get_height()), 0, _height_image.get_height() - 1)
		world_y = _height_image.get_pixel(sample_x, sample_y).r * _height_scale
	var anchor_position := Vector3(world_x, world_y, world_z)
	_anchor_cache[province_id] = anchor_position
	return anchor_position


func _army_world_position(army: Dictionary, day_fraction: float) -> Vector3:
	var current := int(army.get("current_province_id", -1))
	var origin := anchor_world_position(current)
	if String(army.get("status", "")) not in ["moving", "retreating"]:
		return origin
	var remaining: Array = army.get("remaining_path", [])
	var path_index := int(army.get("path_index", 0))
	if path_index >= remaining.size():
		return origin
	var start_day := int(army.get("movement_start_day", -1))
	var arrival_day := int(army.get("next_arrival_day", -1))
	if start_day < 0 or arrival_day <= start_day:
		return origin
	var world := simulation_controller.world
	var progress := clampf(
		(float(world.current_day - start_day) + day_fraction) / float(arrival_day - start_day), 0.0, 1.0
	)
	return origin.lerp(anchor_world_position(int(remaining[path_index])), progress)


func _process(_delta: float) -> void:
	if simulation_controller == null or not simulation_controller.initialized:
		return
	if not _events_connected:
		_connect_events()
	var world := simulation_controller.world
	var camera := camera_controller.camera if camera_controller != null else get_viewport().get_camera_3d()
	var camera_height := MARKER_REFERENCE_HEIGHT
	if camera != null:
		camera_height = maxf(camera.global_position.y, 0.01)
	var marker_scale := clampf(camera_height / MARKER_REFERENCE_HEIGHT, MARKER_MIN_SCALE, MARKER_MAX_SCALE)
	var zoom_fade := 1.0 - smoothstep(MARKER_FADE_START_HEIGHT, MARKER_HIDE_HEIGHT, camera_height)
	var scale_changed := absf(marker_scale - _last_marker_scale) > 0.0005 or absf(zoom_fade - _last_zoom_fade) > 0.0005

	if world.army_registry.size() != _army_ids.size():
		_layout_dirty = true
	if _layout_dirty or scale_changed:
		_last_marker_scale = marker_scale
		_last_zoom_fade = zoom_fade
		_rebuild_markers(world, marker_scale, zoom_fade)
		_layout_dirty = false
		if scale_changed:
			_route_dirty = true
	elif not world.paused and not _moving_markers.is_empty():
		_update_moving_markers(world, marker_scale, zoom_fade)

	if _route_dirty:
		_route_dirty = false
		_refresh_route(world, marker_scale)


func _rebuild_markers(world, marker_scale: float, zoom_fade: float) -> void:
	_army_ids = world.army_registry.keys()
	_army_ids.sort()
	_moving_markers.clear()

	var multimesh := _markers.multimesh
	var counter_multimesh := _troop_counters.multimesh
	if multimesh.instance_count != _army_ids.size():
		multimesh.instance_count = _army_ids.size()
		counter_multimesh.instance_count = _army_ids.size()
		var hidden_basis := Basis.IDENTITY.scaled(Vector3.ONE * 0.0001)
		for initialize_index in range(multimesh.instance_count):
			multimesh.set_instance_transform(initialize_index, Transform3D(hidden_basis, Vector3.ZERO))
			counter_multimesh.set_instance_transform(initialize_index, Transform3D(hidden_basis, Vector3.ZERO))
	var day_fraction := simulation_controller.day_fraction()
	var stack_offsets := {}
	var selected_position := Vector3.ZERO
	var selected_found := false
	for index in _army_ids.size():
		var army_id := String(_army_ids[index])
		var army: Dictionary = world.army_registry[_army_ids[index]]
		var marker_position := _army_world_position(army, day_fraction)
		var stack_key := int(army.get("current_province_id", -1))
		var stacked := int(stack_offsets.get(stack_key, 0))
		stack_offsets[stack_key] = stacked + 1
		var instance_scale := marker_scale if army_id == _selected_army_id else maxf(marker_scale * zoom_fade, 0.0001)
		var stack_x := stacked * STACK_X_SPACING
		marker_position.x += stack_x * instance_scale
		marker_position.y += MARKER_HALF_HEIGHT * instance_scale
		var flag_position := marker_position + Vector3(FLAG_MARKER_X_OFFSET * instance_scale, 0.0, 0.0)
		var counter_position := marker_position + Vector3(TROOP_COUNTER_X_OFFSET * instance_scale, 0.002, 0.0)
		var marker_basis := Basis.IDENTITY.scaled(Vector3.ONE * instance_scale)
		multimesh.set_instance_transform(index, Transform3D(marker_basis, flag_position))
		counter_multimesh.set_instance_transform(index, Transform3D(marker_basis, counter_position))
		var owner_tag := String(army.get("owner_country_id", ""))
		var marker_alpha := 1.0 if army_id == _selected_army_id else zoom_fade
		multimesh.set_instance_color(index, Color(1.0, 1.0, 1.0, marker_alpha))
		var flag_index := int(_country_flag_indices.get(owner_tag, 0))
		multimesh.set_instance_custom_data(index, Color((float(flag_index) + 0.5) / _shield_atlas_slots, 0.0, 0.0, 0.0))
		var counter_color := Color(0.78, 0.96, 0.54, marker_alpha)
		if String(army.get("status", "")) == "retreating":
			counter_color = Color(1.0, 0.68, 0.42, marker_alpha)
		counter_multimesh.set_instance_color(index, counter_color)
		counter_multimesh.set_instance_custom_data(index, Color(clampf(float(int(army.get("strength", 0))) / MAX_DISPLAYED_TROOPS, 0.0, 1.0), 0.0, 0.0, 0.0))
		if String(army.get("status", "")) in ["moving", "retreating"]:
			_moving_markers.append([index, army_id, stack_x])
		if army_id == _selected_army_id:
			selected_position = marker_position
			selected_found = true

	_markers.visible = zoom_fade > 0.0 or selected_found
	_troop_counters.visible = _markers.visible
	_selection_ring.visible = selected_found
	if selected_found:
		_selection_ring.scale = Vector3.ONE * marker_scale
		_selection_ring.position = selected_position + Vector3(0.0, 0.02 * marker_scale, 0.0)
	_destination_marker.scale = Vector3.ONE * marker_scale


func _update_moving_markers(world, marker_scale: float, zoom_fade: float) -> void:
	var multimesh := _markers.multimesh
	var counter_multimesh := _troop_counters.multimesh
	var day_fraction := simulation_controller.day_fraction()
	for entry in _moving_markers:
		var index := int(entry[0])
		var army_id := String(entry[1])
		var army: Dictionary = world.army_registry.get(army_id, {})
		if army.is_empty() or String(army.get("status", "")) not in ["moving", "retreating"]:
			_layout_dirty = true
			return
		var instance_scale := marker_scale if army_id == _selected_army_id else maxf(marker_scale * zoom_fade, 0.0001)
		var marker_position := _army_world_position(army, day_fraction)
		marker_position.x += float(entry[2]) * instance_scale
		marker_position.y += MARKER_HALF_HEIGHT * instance_scale
		var flag_position := marker_position + Vector3(FLAG_MARKER_X_OFFSET * instance_scale, 0.0, 0.0)
		var counter_position := marker_position + Vector3(TROOP_COUNTER_X_OFFSET * instance_scale, 0.002, 0.0)
		var marker_basis := Basis.IDENTITY.scaled(Vector3.ONE * instance_scale)
		multimesh.set_instance_transform(index, Transform3D(marker_basis, flag_position))
		counter_multimesh.set_instance_transform(index, Transform3D(marker_basis, counter_position))
		var marker_alpha := 1.0 if army_id == _selected_army_id else zoom_fade
		multimesh.set_instance_color(index, Color(1.0, 1.0, 1.0, marker_alpha))
		var counter_color := Color(0.78, 0.96, 0.54, marker_alpha)
		if String(army.get("status", "")) == "retreating":
			counter_color = Color(1.0, 0.68, 0.42, marker_alpha)
		counter_multimesh.set_instance_color(index, counter_color)
		counter_multimesh.set_instance_custom_data(index, Color(clampf(float(int(army.get("strength", 0))) / MAX_DISPLAYED_TROOPS, 0.0, 1.0), 0.0, 0.0, 0.0))
		if army_id == _selected_army_id:
			_selection_ring.position = marker_position + Vector3(0.0, 0.02 * marker_scale, 0.0)


func debug_country_flag_index(country_tag: String) -> int:
	return int(_country_flag_indices.get(country_tag, -1))


func debug_uses_flag_atlas() -> bool:
	return _markers.material_override is ShaderMaterial and (_markers.material_override as ShaderMaterial).shader != null


func debug_troop_label_count() -> int:
	return _troop_counters.multimesh.instance_count


func debug_uses_batched_troop_counters() -> bool:
	for child in get_children():
		if child is Label3D:
			return false
	return _troop_counters.material_override is ShaderMaterial


func debug_marker_sizes() -> Vector4:
	return Vector4(FLAG_MARKER_SIZE.x, FLAG_MARKER_SIZE.y, TROOP_COUNTER_SIZE.x, TROOP_COUNTER_SIZE.y)


func debug_marker_visibility_band() -> Vector2:
	return Vector2(MARKER_FADE_START_HEIGHT, MARKER_HIDE_HEIGHT)


func debug_marker_stack_spacing() -> float:
	return STACK_X_SPACING


func _refresh_route(world, marker_scale: float) -> void:
	var path := _preview_path
	_route_wrap_splits = 0
	_route_style = "preview" if not path.is_empty() else "none"
	_route_outline_mesh.clear_surfaces()
	_route_mesh.clear_surfaces()
	_destination_marker.visible = false
	_invalid_destination_marker.visible = false
	if _invalid_destination_id >= 0:
		_route_style = "invalid"
		_invalid_destination_marker.visible = true
		_invalid_destination_marker.scale = Vector3.ONE * marker_scale
		_invalid_destination_marker.position = anchor_world_position(_invalid_destination_id) + Vector3(0.0, 0.1 * marker_scale, 0.0)
		_last_route_inner_width = 0.0
		_last_route_outline_width = 0.0
		return
	if path.is_empty() and not _selected_army_id.is_empty():
		var army: Dictionary = world.army_registry.get(_selected_army_id, {})
		if String(army.get("status", "")) in ["moving", "retreating"]:
			_route_style = "retreat" if String(army.get("status", "")) == "retreating" else "active"
			var remaining: Array = army.get("remaining_path", [])
			var path_index := int(army.get("path_index", 0))
			path = PackedInt32Array([int(army.get("current_province_id", -1))])
			for step in range(path_index, remaining.size()):
				path.append(int(remaining[step]))
	_destination_marker.visible = path.size() >= 2
	if path.size() < 2:
		_route_style = "none"
		_last_route_inner_width = 0.0
		_last_route_outline_width = 0.0
		return

	var inner_width := _pixels_to_world(ROUTE_INNER_PIXELS, marker_scale)
	var outline_width := _pixels_to_world(ROUTE_OUTLINE_PIXELS, marker_scale)
	_last_route_inner_width = inner_width
	_last_route_outline_width = outline_width
	var inner_material := _route_instance.material_override as StandardMaterial3D
	match _route_style:
		"retreat": inner_material.albedo_color = Color(0.95, 0.34, 0.14)
		"active": inner_material.albedo_color = Color(0.98, 0.84, 0.30)
		_: inner_material.albedo_color = Color(1.0, 0.92, 0.40)

	_route_outline_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_route_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(path.size() - 1):
		var from_position := anchor_world_position(path[index]) + Vector3(0, ROUTE_LIFT, 0)
		var to_position := anchor_world_position(path[index + 1]) + Vector3(0, ROUTE_LIFT, 0)
		_append_route_segment(from_position, to_position, inner_width, outline_width, marker_scale)
	_route_outline_mesh.surface_end()
	_route_mesh.surface_end()
	_destination_marker.position = anchor_world_position(path[path.size() - 1]) + Vector3(0.0, 0.1 * marker_scale, 0.0)


func _append_route_segment(from_position: Vector3, to_position: Vector3, inner_width: float, outline_width: float, marker_scale: float) -> void:
	var delta_x := to_position.x - from_position.x
	if absf(delta_x) <= MAP_HALF_WIDTH:
		_append_route_segment_local(from_position, to_position, inner_width, outline_width, marker_scale)
		return
	var seam_x := MAP_HALF_WIDTH if delta_x < 0.0 else -MAP_HALF_WIDTH
	var wrapped_to := to_position
	wrapped_to.x += MAP_WORLD_WIDTH if delta_x < 0.0 else -MAP_WORLD_WIDTH
	var denominator := wrapped_to.x - from_position.x
	if absf(denominator) <= 0.0001:
		return
	var seam_t := clampf((seam_x - from_position.x) / denominator, 0.0, 1.0)
	var first_seam := from_position.lerp(wrapped_to, seam_t)
	first_seam.x = seam_x
	var second_seam := first_seam
	second_seam.x = -seam_x
	_append_route_segment_local(from_position, first_seam, inner_width, outline_width, marker_scale)
	_append_route_segment_local(second_seam, to_position, inner_width, outline_width, marker_scale)
	_route_wrap_splits += 1


func _append_route_segment_local(from_position: Vector3, to_position: Vector3, inner_width: float, outline_width: float, marker_scale: float) -> void:
	var flat_delta := to_position - from_position
	flat_delta.y = 0.0
	var length := flat_delta.length()
	if length <= 0.0001:
		return
	var direction := flat_delta / length
	var dash_length := length
	var gap_length := 0.0
	if _route_style == "preview":
		dash_length = _pixels_to_world(ROUTE_PREVIEW_DASH_PIXELS, marker_scale)
		gap_length = _pixels_to_world(ROUTE_PREVIEW_GAP_PIXELS, marker_scale)
	elif _route_style == "retreat":
		dash_length = _pixels_to_world(ROUTE_RETREAT_DASH_PIXELS, marker_scale)
		gap_length = _pixels_to_world(ROUTE_RETREAT_GAP_PIXELS, marker_scale)
	var cursor := 0.0
	while cursor < length:
		var dash_end := minf(cursor + dash_length, length)
		var start := from_position + direction * cursor
		var finish := from_position + direction * dash_end
		_append_route_quad(_route_outline_mesh, start, finish, outline_width * 0.5)
		_append_route_quad(_route_mesh, start + Vector3(0.0, 0.002, 0.0), finish + Vector3(0.0, 0.002, 0.0), inner_width * 0.5)
		if gap_length <= 0.0:
			break
		cursor = dash_end + gap_length


func _append_route_quad(mesh: ImmediateMesh, from_position: Vector3, to_position: Vector3, half_width: float) -> void:
	var direction := to_position - from_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0000001:
		return
	var side := Vector3(-direction.z, 0.0, direction.x).normalized() * half_width
	mesh.surface_add_vertex(from_position - side)
	mesh.surface_add_vertex(from_position + side)
	mesh.surface_add_vertex(to_position + side)
	mesh.surface_add_vertex(from_position - side)
	mesh.surface_add_vertex(to_position + side)
	mesh.surface_add_vertex(to_position - side)


func _pixels_to_world(pixel_width: float, marker_scale: float) -> float:
	var camera := camera_controller.camera if camera_controller != null else get_viewport().get_camera_3d()
	var viewport_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	if camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return maxf(camera.size / viewport_height * pixel_width, 0.001)
	return ROUTE_WIDTH * marker_scale * pixel_width / ROUTE_INNER_PIXELS


func debug_route_style() -> String:
	return _route_style


func debug_route_surface_count() -> int:
	return _route_mesh.get_surface_count()


func debug_route_widths() -> Vector2:
	return Vector2(_last_route_inner_width, _last_route_outline_width)


func debug_destination_visible() -> bool:
	return _destination_marker.visible


func debug_invalid_destination_visible() -> bool:
	return _invalid_destination_marker.visible


func debug_selected_army() -> String:
	return _selected_army_id


func debug_markers_visible() -> bool:
	return _markers.visible


func debug_route_wrap_splits() -> int:
	return _route_wrap_splits


func debug_route_aabb() -> AABB:
	return _route_mesh.get_aabb()
