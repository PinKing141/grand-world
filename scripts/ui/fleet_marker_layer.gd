class_name FleetMarkerLayer
extends Node3D

## FL1.1/FL1.2/FL1.5: batched, clustered presentation of authoritative fleets.
## Reads simulation state only; deleting this node cannot affect any fleet.
## Anchors, clustering, badge rendering and click-to-cycle selection reuse the
## exact same proven machinery ConflictMarkerLayer already established for
## battle/siege/naval-battle markers - the same shader even renders the
## cluster-count digit badge automatically from INSTANCE_CUSTOM.g.

signal fleet_marker_selected(marker: Dictionary)

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const MARKER_ICON_ATLAS_PATH := "res://assets/marker_art/generated/marker_icon_atlas.png"
const MARKER_ICON_SHADER_PATH := "res://shaders/cartographic_marker_icon.gdshader"
const NAVY_ICON_INDEX := 1.0
const FLEET_PRIORITY := 1

const MAP_PIXEL_SIZE := 0.01
const MAP_HALF_WIDTH := 28.16
const MAP_HALF_HEIGHT := 10.24
const MAP_WORLD_WIDTH := MAP_HALF_WIDTH * 2.0
const MARKER_REFERENCE_HEIGHT := 3.5
const MARKER_MIN_SCALE := 0.24
const MARKER_MAX_SCALE := 1.05
const MARKER_FADE_START_HEIGHT := 4.5
const MARKER_HIDE_HEIGHT := 6.5
const FLEET_LIFT := 0.16
const ROUTE_LIFT := 0.03
const ROUTE_WIDTH := 0.05
const ROUTE_INNER_PIXELS := 3.0
const ROUTE_OUTLINE_PIXELS := 5.5
const ROUTE_MOVING_DASH_PIXELS := 11.0
const ROUTE_MOVING_GAP_PIXELS := 7.0
const ROUTE_RETREAT_DASH_PIXELS := 5.0
const ROUTE_RETREAT_GAP_PIXELS := 5.0
const ROUTE_TRANSPORT_DASH_PIXELS := 16.0
const ROUTE_TRANSPORT_GAP_PIXELS := 4.0

@export var simulation_controller: GrandWorldSimulationController
@export var map_render: Node
@export var camera_controller: StrategyCameraController
@export var naval_hud: NavalHUD
@export_range(12.0, 64.0, 1.0) var cluster_radius_pixels := 26.0
@export_range(8.0, 48.0, 1.0) var click_radius_pixels := 20.0

var _graph: ProvinceGraph
var _height_image: Image
var _height_scale := 0.35
var _fleet_markers := MultiMeshInstance3D.new()
var _anchor_cache: Dictionary = {}
var _events_connected := false
var _dirty := true
var _last_scale := -1.0
var _last_fade := -1.0
var _fleet_count := 0
var _clusters: Array[Dictionary] = []
var _last_cluster_signature := ""
var _last_cluster_member_index := -1
var _selected_fleet_id := ""
var _route_outline_mesh := ImmediateMesh.new()
var _route_outline_instance := MeshInstance3D.new()
var _route_mesh := ImmediateMesh.new()
var _route_instance := MeshInstance3D.new()
var _destination_marker := MeshInstance3D.new()
var _mission_target_marker := MeshInstance3D.new()
var _route_dirty := true
var _route_style := "none"
var _route_wrap_splits := 0
var _last_route_inner_width := 0.0
var _last_route_outline_width := 0.0


func _ready() -> void:
	_graph = ProvinceGraph.load_default()
	var height_texture := load("res://assets/heightmap.png") as Texture2D
	if height_texture != null:
		_height_image = height_texture.get_image()
		if _height_image != null and _height_image.is_compressed():
			_height_image.decompress()
	if map_render != null and map_render.get("final_material") != null:
		var scale_parameter = map_render.final_material.get_shader_parameter("terrain_height_scale")
		if scale_parameter != null:
			_height_scale = float(scale_parameter)
	_create_batch()
	_create_route_nodes()
	if camera_controller != null:
		camera_controller.map_click_requested.connect(_on_map_click_requested)


## Route/destination/mission-target geometry mirrors ArmyLayer's proven
## dashed-line ImmediateMesh approach exactly (same wraparound-aware segment
## splitting, same inner/outline two-pass draw) - a sea route and a land
## route are the same drawing problem, just over different anchors. Cooler
## blue/teal tones (vs. ArmyLayer's amber) keep the two visually distinct
## when both are on screen at once.
func _create_route_nodes() -> void:
	_route_outline_instance.mesh = _route_outline_mesh
	_route_outline_instance.material_override = _unshaded_material(Color(0.02, 0.05, 0.08), false, true, 1)
	add_child(_route_outline_instance)

	_route_instance.mesh = _route_mesh
	_route_instance.material_override = _unshaded_material(Color(0.30, 0.78, 0.96), false, true, 2)
	add_child(_route_instance)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.14
	_destination_marker.mesh = cone
	_destination_marker.material_override = _unshaded_material(Color(0.30, 0.78, 0.96))
	_destination_marker.visible = false
	add_child(_destination_marker)

	var target_ring := TorusMesh.new()
	target_ring.inner_radius = 0.05
	target_ring.outer_radius = 0.07
	_mission_target_marker.mesh = target_ring
	_mission_target_marker.material_override = _unshaded_material(Color(0.95, 0.62, 0.18))
	_mission_target_marker.visible = false
	add_child(_mission_target_marker)


func _unshaded_material(color: Color, vertex_color := false, on_top := false, priority := 0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.vertex_color_use_as_albedo = vertex_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = on_top
	material.render_priority = priority
	return material


func _create_batch() -> void:
	var fleet_icon := PlaneMesh.new()
	fleet_icon.size = Vector2(0.30, 0.30)
	fleet_icon.orientation = PlaneMesh.FACE_Y
	_fleet_markers.name = "FleetMarkers"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = fleet_icon
	_fleet_markers.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = load(MARKER_ICON_SHADER_PATH) as Shader
	material.set_shader_parameter("icon_atlas", load(MARKER_ICON_ATLAS_PATH) as Texture2D)
	material.set_shader_parameter("atlas_grid", Vector2(4.0, 3.0))
	material.set_shader_parameter("icon_index", NAVY_ICON_INDEX)
	material.render_priority = FLEET_PRIORITY
	_fleet_markers.material_override = material
	_fleet_markers.visible = false
	add_child(_fleet_markers)


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	if events == null:
		return
	_events_connected = true
	events.fleet_created.connect(_mark_dirty.unbind(3))
	events.fleets_merged.connect(_on_fleets_merged)
	events.fleet_ships_transferred.connect(_mark_dirty.unbind(2))
	events.fleet_home_port_changed.connect(_mark_dirty.unbind(2))
	events.fleet_movement_ordered.connect(_mark_dirty.unbind(3))
	events.fleet_moved.connect(_mark_dirty.unbind(3))
	events.fleet_movement_completed.connect(_mark_dirty.unbind(2))
	events.fleet_movement_blocked.connect(_mark_dirty.unbind(3))
	events.fleet_movement_cancelled.connect(_mark_dirty.unbind(1))
	events.fleet_mission_changed.connect(_mark_dirty.unbind(2))
	events.fleet_destroyed.connect(_mark_dirty.unbind(2))
	# FL1.5 closure: scuttling removes a fleet exactly like fleet_destroyed
	# does, but emits its own distinct event - without this, a scuttled
	# fleet's marker stayed on the map until some unrelated event happened
	# to mark the batch dirty.
	events.fleet_scuttled.connect(_mark_dirty.unbind(3))
	events.fleet_retreat_started.connect(_mark_dirty.unbind(2))
	events.naval_battle_started.connect(_mark_dirty.unbind(3))
	events.naval_battle_ended.connect(_mark_dirty.unbind(3))
	events.country_formed.connect(_mark_dirty.unbind(2))
	events.country_released.connect(_mark_dirty.unbind(3))
	events.country_extinct.connect(_mark_dirty.unbind(1))
	events.world_reloaded.connect(_mark_dirty.unbind(1))


func _mark_dirty() -> void:
	_dirty = true
	_route_dirty = true


func _on_fleets_merged(target_fleet_id: String, merged_fleet_ids: Array) -> void:
	_mark_dirty()
	# FL1.2: if the selected fleet is one of the records folded into the
	# deterministic survivor, follow that survivor explicitly. Falling back
	# to an unrelated sorted-first fleet loses the user's live context.
	if _selected_fleet_id != target_fleet_id and merged_fleet_ids.has(_selected_fleet_id):
		set_selected_fleet(target_fleet_id)


func set_selected_fleet(fleet_id: String) -> void:
	if fleet_id == _selected_fleet_id:
		return
	_selected_fleet_id = fleet_id
	_route_dirty = true


func selected_fleet() -> String:
	return _selected_fleet_id


func _process(_delta: float) -> void:
	if simulation_controller == null or not simulation_controller.initialized:
		return
	if not _events_connected:
		_connect_events()
	var camera := camera_controller.camera if camera_controller != null else get_viewport().get_camera_3d()
	var camera_height := MARKER_REFERENCE_HEIGHT if camera == null else maxf(camera.global_position.y, 0.01)
	var marker_scale := clampf(camera_height / MARKER_REFERENCE_HEIGHT, MARKER_MIN_SCALE, MARKER_MAX_SCALE)
	var fade := 1.0 - smoothstep(MARKER_FADE_START_HEIGHT, MARKER_HIDE_HEIGHT, camera_height)
	if _dirty or absf(marker_scale - _last_scale) > 0.0005 or absf(fade - _last_fade) > 0.0005:
		_last_scale = marker_scale
		_last_fade = fade
		_rebuild(marker_scale, fade)
		_dirty = false
		_route_dirty = true
	if _route_dirty:
		_route_dirty = false
		_refresh_route(marker_scale)


func _rebuild(marker_scale: float, fade: float) -> void:
	var fleets: Array[Dictionary] = []
	var fleet_ids := simulation_controller.world.fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		var fleet: Dictionary = simulation_controller.world.fleet_registry[raw_fleet_id]
		var location_id := int(fleet.get("location_id", -1))
		if not _graph.has_province(location_id):
			continue
		var aggregate: Dictionary = fleet.get("aggregate", {})
		var marker := {
			"marker_type": "fleet",
			"marker_id": String(raw_fleet_id),
			"fleet_id": String(raw_fleet_id),
			"province_id": location_id,
			"owner_country_id": String(fleet.get("owner_country_id", "")),
			"mission": String(fleet.get("mission", "idle")),
			"location_status": String(fleet.get("location_status", "")),
			"battle_id": String(fleet.get("battle_id", "")),
			"ship_count": int(aggregate.get("ship_count", 0)),
			"total_hull": int(aggregate.get("total_hull", 0)),
			"total_maximum_hull": int(aggregate.get("total_maximum_hull", 0)),
			"priority": FLEET_PRIORITY,
		}
		fleets.append(marker)
	_fleet_count = fleets.size()
	var clusters := _cluster_records(fleets)
	_clusters.assign(clusters)
	_rebuild_markers(clusters, marker_scale, fade)


func _record_key(record: Dictionary) -> String:
	return "%08d:%s:%s" % [int(record.get("province_id", -1)), String(record.get("owner_country_id", "")), String(record.get("marker_id", ""))]


## Mirrors ConflictMarkerLayer._cluster_records() exactly (FL8.3 already
## proved the native-sort/precomputed-key shape correct and fast there) -
## fold exact co-location first, then bucket nearby screen positions so a
## dense port never produces one marker per fleet.
func _cluster_records(records: Array[Dictionary]) -> Array[Dictionary]:
	if records.is_empty():
		return []
	var camera := camera_controller.camera if camera_controller != null else get_viewport().get_camera_3d()
	var keyed: Array = []
	for record in records:
		keyed.append([_record_key(record), record])
	keyed.sort()
	var ordered: Array[Dictionary] = []
	for pair in keyed:
		ordered.append(pair[1])
	var records_by_province: Dictionary = {}
	for record in ordered:
		var province_id := int(record.get("province_id", -1))
		var province_records: Array = records_by_province.get(province_id, [])
		province_records.append(record)
		records_by_province[province_id] = province_records
	var province_ids := records_by_province.keys()
	province_ids.sort()
	var clusters: Array[Dictionary] = []
	var buckets: Dictionary = {}
	var cell_size := maxf(cluster_radius_pixels, 1.0)
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var province_records: Array = records_by_province[raw_province_id]
		var world_position := anchor_world_position(province_id)
		var screen_position := camera.unproject_position(world_position) if camera != null else Vector2(world_position.x, world_position.z)
		var cell := Vector2i(floori(screen_position.x / cell_size), floori(screen_position.y / cell_size))
		var closest_index := -1
		var closest_distance := cluster_radius_pixels + 0.001
		for cell_y in range(cell.y - 1, cell.y + 2):
			for cell_x in range(cell.x - 1, cell.x + 2):
				for index in buckets.get(Vector2i(cell_x, cell_y), []):
					var distance: float = screen_position.distance_to(clusters[index]["screen_position"])
					if distance <= cluster_radius_pixels and distance < closest_distance:
						closest_index = index
						closest_distance = distance
		if closest_index < 0:
			clusters.append({
				"world_position": world_position,
				"screen_position": screen_position,
				"members": province_records.duplicate(),
			})
			var indices: Array = buckets.get(cell, [])
			indices.append(clusters.size() - 1)
			buckets[cell] = indices
		else:
			var members: Array = clusters[closest_index]["members"]
			members.append_array(province_records)
			clusters[closest_index]["members"] = members
	for cluster in clusters:
		var member_keys: Array[String] = []
		for member in cluster["members"]:
			member_keys.append(String(member.get("marker_id", "")))
		member_keys.sort()
		cluster["signature"] = "|".join(member_keys)
	return clusters


func _rebuild_markers(clusters: Array[Dictionary], marker_scale: float, fade: float) -> void:
	var multimesh := _fleet_markers.multimesh
	multimesh.instance_count = clusters.size()
	var index := 0
	for cluster in clusters:
		var representative: Dictionary = cluster["members"][0]
		var position: Vector3 = cluster["world_position"] + Vector3(0.0, FLEET_LIFT * marker_scale, 0.0)
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * marker_scale)
		var owner_tag := String(representative.get("owner_country_id", ""))
		var owner_colour: Color = simulation_controller.country_registry.country_colour(owner_tag) if simulation_controller.world.has_country(owner_tag) else Color(0.6, 0.6, 0.6)
		owner_colour.a = fade
		multimesh.set_instance_transform(index, Transform3D(basis, position))
		multimesh.set_instance_color(index, owner_colour)
		multimesh.set_instance_custom_data(index, Color(0.0, minf(float((cluster["members"] as Array).size()), 255.0) / 255.0, 0.0, 0.0))
		index += 1
	_fleet_markers.visible = fade > 0.0 and not clusters.is_empty()


func anchor_world_position(province_id: int) -> Vector3:
	if _anchor_cache.has(province_id):
		return _anchor_cache[province_id]
	var anchor := _graph.anchor(province_id)
	var world_y := 0.0
	if _height_image != null:
		var sample_x := clampi(int(float(anchor.x) / _graph.map_size.x * _height_image.get_width()), 0, _height_image.get_width() - 1)
		var sample_y := clampi(int(float(anchor.y) / _graph.map_size.y * _height_image.get_height()), 0, _height_image.get_height() - 1)
		world_y = _height_image.get_pixel(sample_x, sample_y).r * _height_scale
	var result := Vector3(anchor.x * MAP_PIXEL_SIZE - MAP_HALF_WIDTH, world_y, anchor.y * MAP_PIXEL_SIZE - MAP_HALF_HEIGHT)
	_anchor_cache[province_id] = result
	return result


func marker_at_screen_position(screen_position: Vector2) -> Dictionary:
	if not debug_markers_visible() or _clusters.is_empty():
		return {}
	var camera := camera_controller.camera if camera_controller != null else get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var candidates: Array[Dictionary] = []
	for cluster in _clusters:
		var projected := camera.unproject_position(cluster["world_position"])
		var distance := projected.distance_to(screen_position)
		if distance <= click_radius_pixels:
			candidates.append({"cluster": cluster, "distance": distance, "projected": projected})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return float(first["distance"]) < float(second["distance"]))
	var selected_cluster: Dictionary = candidates[0]["cluster"]
	var signature := String(selected_cluster["signature"])
	if signature == _last_cluster_signature:
		_last_cluster_member_index = (_last_cluster_member_index + 1) % selected_cluster["members"].size()
	else:
		_last_cluster_signature = signature
		_last_cluster_member_index = 0
	var result: Dictionary = (selected_cluster["members"][_last_cluster_member_index] as Dictionary).duplicate(true)
	result["cluster_size"] = selected_cluster["members"].size()
	result["cluster_member_index"] = _last_cluster_member_index
	result["cluster_signature"] = signature
	result["screen_position"] = candidates[0]["projected"]
	return result


func _on_map_click_requested(screen_position: Vector2) -> void:
	var marker := marker_at_screen_position(screen_position)
	if marker.is_empty():
		return
	fleet_marker_selected.emit(marker)
	set_selected_fleet(String(marker.get("fleet_id", "")))
	if naval_hud != null:
		naval_hud.select_fleet(String(marker.get("fleet_id", "")))


## FL1.3: draws the selected fleet's actual authoritative route
## (remaining_path/path_index - retreat reuses this exact field, see
## NavalCombatSystem._begin_retreat()), styled by what the fleet is actually
## doing: retreating, carrying an active transport reservation, or a plain
## order. A blockade mission's target is shown as a ring even with no route,
## since "moving" and "on station" are different feedback needs. Purely
## derived from world state every call - never becomes save authority.
func _refresh_route(marker_scale: float) -> void:
	_route_wrap_splits = 0
	_route_outline_mesh.clear_surfaces()
	_route_mesh.clear_surfaces()
	_destination_marker.visible = false
	_mission_target_marker.visible = false
	_route_style = "none"
	_last_route_inner_width = 0.0
	_last_route_outline_width = 0.0
	if _selected_fleet_id.is_empty() or not simulation_controller.world.fleet_registry.has(_selected_fleet_id):
		return
	var fleet: Dictionary = simulation_controller.world.fleet_registry[_selected_fleet_id]
	var location_status := String(fleet.get("location_status", ""))
	var mission := String(fleet.get("mission", "idle"))
	var mission_targets: Array = fleet.get("mission_target_ids", [])
	if mission == "blockade" and not mission_targets.is_empty():
		var target_id := int(mission_targets[0])
		if _graph.has_province(target_id):
			_mission_target_marker.visible = true
			_mission_target_marker.scale = Vector3.ONE * marker_scale
			_mission_target_marker.position = anchor_world_position(target_id) + Vector3(0.0, 0.05 * marker_scale, 0.0)
	if location_status not in [CampaignWorldStateScript.FLEET_LOCATION_MOVING, CampaignWorldStateScript.FLEET_LOCATION_RETREATING]:
		return
	var remaining: Array = fleet.get("remaining_path", [])
	var path_index := int(fleet.get("path_index", 0))
	if path_index >= remaining.size():
		return
	var path := PackedInt32Array([int(fleet.get("location_id", -1))])
	for step in range(path_index, remaining.size()):
		path.append(int(remaining[step]))
	if path.size() < 2:
		return
	var is_transport := not (fleet.get("transport_operation_ids", []) as Array).is_empty()
	if location_status == CampaignWorldStateScript.FLEET_LOCATION_RETREATING:
		_route_style = "retreat"
	elif is_transport:
		_route_style = "transport"
	else:
		_route_style = "moving"
	_destination_marker.visible = true
	var inner_width := _pixels_to_world(ROUTE_INNER_PIXELS, marker_scale)
	var outline_width := _pixels_to_world(ROUTE_OUTLINE_PIXELS, marker_scale)
	_last_route_inner_width = inner_width
	_last_route_outline_width = outline_width
	var inner_material := _route_instance.material_override as StandardMaterial3D
	match _route_style:
		"retreat": inner_material.albedo_color = Color(0.95, 0.34, 0.14)
		"transport": inner_material.albedo_color = Color(0.55, 0.90, 0.42)
		_: inner_material.albedo_color = Color(0.30, 0.78, 0.96)
	_route_outline_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_route_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(path.size() - 1):
		var from_position := anchor_world_position(path[index]) + Vector3(0.0, ROUTE_LIFT, 0.0)
		var to_position := anchor_world_position(path[index + 1]) + Vector3(0.0, ROUTE_LIFT, 0.0)
		_append_route_segment(from_position, to_position, inner_width, outline_width, marker_scale)
	_route_outline_mesh.surface_end()
	_route_mesh.surface_end()
	_destination_marker.scale = Vector3.ONE * marker_scale
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
	match _route_style:
		"moving":
			dash_length = _pixels_to_world(ROUTE_MOVING_DASH_PIXELS, marker_scale)
			gap_length = _pixels_to_world(ROUTE_MOVING_GAP_PIXELS, marker_scale)
		"retreat":
			dash_length = _pixels_to_world(ROUTE_RETREAT_DASH_PIXELS, marker_scale)
			gap_length = _pixels_to_world(ROUTE_RETREAT_GAP_PIXELS, marker_scale)
		"transport":
			dash_length = _pixels_to_world(ROUTE_TRANSPORT_DASH_PIXELS, marker_scale)
			gap_length = _pixels_to_world(ROUTE_TRANSPORT_GAP_PIXELS, marker_scale)
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


func debug_mission_target_visible() -> bool:
	return _mission_target_marker.visible


func debug_selected_fleet() -> String:
	return _selected_fleet_id


func debug_route_wrap_splits() -> int:
	return _route_wrap_splits


func debug_force_refresh() -> void:
	_dirty = true
	_process(0.0)


func debug_fleet_count() -> int:
	return _fleet_count


func debug_cluster_count() -> int:
	return _clusters.size()


func debug_cluster_signature() -> String:
	var signatures: Array[String] = []
	for cluster in _clusters:
		signatures.append(String(cluster.get("signature", "")))
	signatures.sort()
	return "\n".join(signatures)


func debug_markers_visible() -> bool:
	return _fleet_markers.visible


func debug_marker_instances() -> int:
	return _fleet_markers.multimesh.instance_count


func debug_cluster_screen_position(index: int) -> Vector2:
	if index < 0 or index >= _clusters.size():
		return Vector2.ZERO
	var camera := camera_controller.camera if camera_controller != null else get_viewport().get_camera_3d()
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(_clusters[index]["world_position"])
