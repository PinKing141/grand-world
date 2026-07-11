class_name ArmyLayer
extends Node3D

## Presentation of authoritative armies: markers, the selected army's route,
## and a destination marker. Reads simulation state every frame and never
## writes it; deleting this node cannot affect any army.

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")

const MAP_PIXEL_SIZE := 0.01
const MAP_HALF_WIDTH := 28.16
const MAP_HALF_HEIGHT := 10.24
const MARKER_LIFT := 0.045
const ROUTE_LIFT := 0.03
const ROUTE_WIDTH := 0.05

@export var simulation_controller: GrandWorldSimulationController
@export var map_render: Node

var _graph: ProvinceGraph
var _height_image: Image
var _height_scale := 0.35
var _markers := MultiMeshInstance3D.new()
var _selection_ring := MeshInstance3D.new()
var _route_mesh := ImmediateMesh.new()
var _route_instance := MeshInstance3D.new()
var _destination_marker := MeshInstance3D.new()
var _selected_army_id := ""
var _preview_path := PackedInt32Array()
var _route_signature := ""
var _anchor_cache: Dictionary = {}


func _ready() -> void:
	_graph = ProvinceGraph.load_default()
	var height_texture := load("res://assets/heightmap.png") as Texture2D
	if height_texture != null:
		_height_image = height_texture.get_image()
	if map_render != null and map_render.get("final_material") != null:
		var scale_param = map_render.final_material.get_shader_parameter("terrain_height_scale")
		if scale_param != null:
			_height_scale = float(scale_param)

	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.07, 0.09, 0.07)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = marker_mesh
	_markers.multimesh = multimesh
	_markers.material_override = _unshaded_material(Color.WHITE, true)
	add_child(_markers)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.07
	ring.outer_radius = 0.1
	_selection_ring.mesh = ring
	_selection_ring.material_override = _unshaded_material(Color(0.2, 0.85, 1.0))
	_selection_ring.visible = false
	add_child(_selection_ring)

	_route_instance.mesh = _route_mesh
	_route_instance.material_override = _unshaded_material(Color(1.0, 0.92, 0.4))
	add_child(_route_instance)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.14
	_destination_marker.mesh = cone
	_destination_marker.material_override = _unshaded_material(Color(1.0, 0.72, 0.2))
	_destination_marker.visible = false
	add_child(_destination_marker)


func _unshaded_material(color: Color, vertex_color := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.vertex_color_use_as_albedo = vertex_color
	return material


func set_selected_army(army_id: String) -> void:
	_selected_army_id = army_id
	_route_signature = ""


func selected_army() -> String:
	return _selected_army_id


func set_preview_path(path: PackedInt32Array) -> void:
	_preview_path = path
	_route_signature = ""


func clear_preview_path() -> void:
	set_preview_path(PackedInt32Array())


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
	var position := Vector3(world_x, world_y, world_z)
	_anchor_cache[province_id] = position
	return position


func _army_world_position(army: Dictionary, day_fraction: float) -> Vector3:
	var current := int(army.get("current_province_id", -1))
	var origin := anchor_world_position(current)
	if String(army.get("status", "")) != "moving":
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
	var world := simulation_controller.world
	var day_fraction := simulation_controller.day_fraction()
	var army_ids := world.army_registry.keys()
	army_ids.sort()

	var multimesh := _markers.multimesh
	if multimesh.instance_count != army_ids.size():
		multimesh.instance_count = army_ids.size()
	var stack_offsets := {}
	var selected_position := Vector3.ZERO
	var selected_found := false
	for index in army_ids.size():
		var army_id := String(army_ids[index])
		var army: Dictionary = world.army_registry[army_ids[index]]
		var position := _army_world_position(army, day_fraction)
		var stack_key := int(army.get("current_province_id", -1))
		var stacked := int(stack_offsets.get(stack_key, 0))
		stack_offsets[stack_key] = stacked + 1
		position.x += stacked * 0.08
		position.y += MARKER_LIFT
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))
		var owner := String(army.get("owner_country_id", ""))
		var color: Color = simulation_controller.country_data.country_id_to_color.get(owner, Color.GRAY)
		multimesh.set_instance_color(index, Color(color.r, color.g, color.b, 1.0))
		if army_id == _selected_army_id:
			selected_position = position
			selected_found = true

	_selection_ring.visible = selected_found
	if selected_found:
		_selection_ring.position = selected_position + Vector3(0.0, 0.02, 0.0)
	_refresh_route(world)


func _refresh_route(world) -> void:
	var path := _preview_path
	if path.is_empty() and not _selected_army_id.is_empty():
		var army: Dictionary = world.army_registry.get(_selected_army_id, {})
		if String(army.get("status", "")) == "moving":
			var remaining: Array = army.get("remaining_path", [])
			var path_index := int(army.get("path_index", 0))
			path = PackedInt32Array([int(army.get("current_province_id", -1))])
			for step in range(path_index, remaining.size()):
				path.append(int(remaining[step]))
	var signature := "%s|%s" % [_selected_army_id, path]
	if signature == _route_signature:
		return
	_route_signature = signature
	_route_mesh.clear_surfaces()
	_destination_marker.visible = path.size() >= 2
	if path.size() < 2:
		return
	_route_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in range(path.size() - 1):
		var from_position := anchor_world_position(path[index]) + Vector3(0, ROUTE_LIFT, 0)
		var to_position := anchor_world_position(path[index + 1]) + Vector3(0, ROUTE_LIFT, 0)
		var direction := (to_position - from_position)
		direction.y = 0.0
		var side := Vector3(-direction.z, 0.0, direction.x).normalized() * ROUTE_WIDTH * 0.5
		_route_mesh.surface_add_vertex(from_position - side)
		_route_mesh.surface_add_vertex(from_position + side)
		_route_mesh.surface_add_vertex(to_position - side)
		_route_mesh.surface_add_vertex(to_position + side)
	_route_mesh.surface_end()
	_destination_marker.position = anchor_world_position(path[path.size() - 1]) + Vector3(0.0, 0.1, 0.0)
