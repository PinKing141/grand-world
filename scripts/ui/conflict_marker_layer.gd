class_name ConflictMarkerLayer
extends Node3D

## Batched presentation of authoritative battles and sieges.
## Battle crosses sit above siege squares when both states share a province.

signal conflict_marker_selected(marker: Dictionary)

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")
const MARKER_ICON_ATLAS_PATH := "res://assets/marker_art/generated/marker_icon_atlas.png"
const MARKER_ICON_SHADER_PATH := "res://shaders/cartographic_marker_icon.gdshader"

const MAP_PIXEL_SIZE := 0.01
const MAP_HALF_WIDTH := 28.16
const MAP_HALF_HEIGHT := 10.24
const MARKER_REFERENCE_HEIGHT := 3.5
const MARKER_MIN_SCALE := 0.28
const MARKER_MAX_SCALE := 1.15
const MARKER_FADE_START_HEIGHT := 4.5
const MARKER_HIDE_HEIGHT := 6.5
const BATTLE_LIFT := 0.19
const SIEGE_LIFT := 0.10
const BATTLE_PRIORITY := 2
const SIEGE_PRIORITY := 1

@export var simulation_controller: GrandWorldSimulationController
@export var map_render: Node
@export var camera_controller: StrategyCameraController
@export var war_hud: WarHUD
@export_range(12.0, 64.0, 1.0) var cluster_radius_pixels := 28.0
@export_range(8.0, 48.0, 1.0) var click_radius_pixels := 20.0

var _graph: ProvinceGraph
var _height_image: Image
var _height_scale := 0.35
var _battle_markers := MultiMeshInstance3D.new()
var _siege_markers := MultiMeshInstance3D.new()
var _anchor_cache: Dictionary = {}
var _events_connected := false
var _dirty := true
var _last_scale := -1.0
var _last_fade := -1.0
var _battle_count := 0
var _siege_count := 0
var _clusters: Array[Dictionary] = []
var _last_cluster_signature := ""
var _last_cluster_member_index := -1


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
	_create_batches()
	if camera_controller != null:
		camera_controller.map_click_requested.connect(_on_map_click_requested)


func _create_batches() -> void:
	var battle_icon := PlaneMesh.new()
	battle_icon.size = Vector2(0.34, 0.34)
	battle_icon.orientation = PlaneMesh.FACE_Y
	_battle_markers.name = "BattleMarkers"
	_battle_markers.multimesh = _create_multimesh(battle_icon)
	_battle_markers.material_override = _marker_material(2.0, 4)
	_battle_markers.visible = false
	add_child(_battle_markers)

	var siege_icon := PlaneMesh.new()
	siege_icon.size = Vector2(0.32, 0.32)
	siege_icon.orientation = PlaneMesh.FACE_Y
	_siege_markers.name = "SiegeMarkers"
	_siege_markers.multimesh = _create_multimesh(siege_icon)
	_siege_markers.material_override = _marker_material(3.0, 3)
	_siege_markers.visible = false
	add_child(_siege_markers)


func _create_multimesh(mesh: Mesh) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	return multimesh


func _marker_material(icon_index: float, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(MARKER_ICON_SHADER_PATH) as Shader
	material.set_shader_parameter("icon_atlas", load(MARKER_ICON_ATLAS_PATH) as Texture2D)
	material.set_shader_parameter("atlas_grid", Vector2(4.0, 3.0))
	material.set_shader_parameter("icon_index", icon_index)
	material.render_priority = priority
	return material


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	if events == null:
		return
	_events_connected = true
	events.date_changed.connect(_mark_dirty.unbind(2))
	events.war_declared.connect(_mark_dirty.unbind(4))
	events.battle_started.connect(_mark_dirty.unbind(3))
	events.battle_reinforced.connect(_mark_dirty.unbind(3))
	events.battle_round_resolved.connect(_mark_dirty.unbind(4))
	events.battle_ended.connect(_mark_dirty.unbind(3))
	events.occupation_changed.connect(_mark_dirty.unbind(3))
	events.peace_signed.connect(_mark_dirty.unbind(4))
	events.world_reloaded.connect(_mark_dirty.unbind(1))


func _mark_dirty() -> void:
	_dirty = true


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


func _rebuild(marker_scale: float, fade: float) -> void:
	var battles: Array[Dictionary] = []
	var sieges: Array[Dictionary] = []
	var war_ids := simulation_controller.world.war_registry.keys()
	war_ids.sort()
	for raw_war_id in war_ids:
		var war: Dictionary = simulation_controller.world.war_registry[raw_war_id]
		if String(war.get("status", "active")) != "active":
			continue
		var battle_ids := (war.get("battles", {}) as Dictionary).keys()
		battle_ids.sort()
		for raw_battle_id in battle_ids:
			var battle: Dictionary = (war.get("battles", {}) as Dictionary)[raw_battle_id]
			if String(battle.get("status", "")) == "active":
				var marker := battle.duplicate(true)
				marker["marker_type"] = "battle"
				marker["marker_id"] = String(raw_battle_id)
				marker["war_id"] = String(raw_war_id)
				marker["priority"] = BATTLE_PRIORITY
				battles.append(marker)
		var siege_ids := (war.get("sieges", {}) as Dictionary).keys()
		siege_ids.sort()
		for raw_siege_id in siege_ids:
			var marker: Dictionary = ((war.get("sieges", {}) as Dictionary)[raw_siege_id] as Dictionary).duplicate(true)
			marker["marker_type"] = "siege"
			marker["marker_id"] = String(raw_siege_id)
			marker["war_id"] = String(raw_war_id)
			marker["priority"] = SIEGE_PRIORITY
			sieges.append(marker)
	_battle_count = battles.size()
	_siege_count = sieges.size()
	var battle_clusters := _cluster_records(battles)
	var siege_clusters := _cluster_records(sieges)
	_clusters.assign(battle_clusters)
	_clusters.append_array(siege_clusters)
	_rebuild_battles(battle_clusters, marker_scale, fade)
	_rebuild_sieges(siege_clusters, marker_scale, fade)


func _record_less(first: Dictionary, second: Dictionary) -> bool:
	var first_key := "%08d:%s:%s" % [int(first.get("province_id", -1)), String(first.get("war_id", "")), String(first.get("marker_id", ""))]
	var second_key := "%08d:%s:%s" % [int(second.get("province_id", -1)), String(second.get("war_id", "")), String(second.get("marker_id", ""))]
	return first_key < second_key


func _cluster_records(records: Array[Dictionary]) -> Array[Dictionary]:
	if records.is_empty():
		return []
	var camera := camera_controller.camera if camera_controller != null else get_viewport().get_camera_3d()
	var ordered := records.duplicate()
	ordered.sort_custom(_record_less)
	# Exact co-location is the overwhelmingly common case in large wars. Fold
	# those records before projecting or doing any spatial-neighbour work.
	var records_by_province: Dictionary = {}
	for record in ordered:
		var province_id := int(record.get("province_id", -1))
		var province_records: Array = records_by_province.get(province_id, [])
		province_records.append(record)
		records_by_province[province_id] = province_records
	var province_ids := records_by_province.keys()
	province_ids.sort()
	var clusters: Array[Dictionary] = []
	# Fixed-anchor spatial buckets keep event-driven rebuilds close to O(n).
	# A cluster never changes its anchor, so deterministic membership does not
	# depend on floating-point centroid accumulation or registry insertion order.
	var buckets: Dictionary = {}
	var cell_size := maxf(cluster_radius_pixels, 1.0)
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var province_records: Array = records_by_province[raw_province_id]
		var representative: Dictionary = province_records[0]
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
				"marker_type": String(representative.get("marker_type", "")),
				"priority": int(representative.get("priority", 0)),
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
			member_keys.append("%s:%s:%s" % [String(member.get("marker_type", "")), String(member.get("war_id", "")), String(member.get("marker_id", ""))])
		member_keys.sort()
		cluster["signature"] = "|".join(member_keys)
	return clusters


func _rebuild_battles(clusters: Array[Dictionary], marker_scale: float, fade: float) -> void:
	var multimesh := _battle_markers.multimesh
	multimesh.instance_count = clusters.size()
	var index := 0
	for cluster in clusters:
		var position: Vector3 = cluster["world_position"] + Vector3(0.0, BATTLE_LIFT * marker_scale, 0.0)
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * marker_scale)
		multimesh.set_instance_transform(index, Transform3D(basis, position))
		multimesh.set_instance_color(index, Color(0.96, 0.24, 0.12, fade))
		multimesh.set_instance_custom_data(index, Color(0.0, minf(float((cluster["members"] as Array).size()), 255.0) / 255.0, 0.0, 0.0))
		index += 1
	_battle_markers.visible = fade > 0.0 and not clusters.is_empty()


func _rebuild_sieges(clusters: Array[Dictionary], marker_scale: float, fade: float) -> void:
	var multimesh := _siege_markers.multimesh
	multimesh.instance_count = clusters.size()
	var index := 0
	for cluster in clusters:
		var siege: Dictionary = cluster["members"][0]
		var center: Vector3 = cluster["world_position"] + Vector3(0.0, SIEGE_LIFT * marker_scale, 0.0)
		var progress := clampf(float(siege.get("progress_bp", 0)) / 10000.0, 0.0, 1.0)
		var color := Color(0.72, 0.76, 0.80).lerp(Color(1.0, 0.57, 0.12), progress)
		color.a = fade
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * marker_scale)
		multimesh.set_instance_transform(index, Transform3D(basis, center))
		multimesh.set_instance_color(index, color)
		multimesh.set_instance_custom_data(index, Color(0.0, minf(float((cluster["members"] as Array).size()), 255.0) / 255.0, 0.0, 0.0))
		index += 1
	_siege_markers.visible = fade > 0.0 and not clusters.is_empty()


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
		var distance_difference := float(first["distance"]) - float(second["distance"])
		if absf(distance_difference) > 0.001:
			return distance_difference < 0.0
		return int(first["cluster"]["priority"]) > int(second["cluster"]["priority"]))
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
	conflict_marker_selected.emit(marker)
	if war_hud != null:
		war_hud.focus_conflict_marker(marker)


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


func debug_force_refresh() -> void:
	_dirty = true
	_process(0.0)


func debug_battle_count() -> int:
	return _battle_count


func debug_siege_count() -> int:
	return _siege_count


func debug_cluster_count() -> int:
	return _clusters.size()


func debug_cluster_signature() -> String:
	var signatures: Array[String] = []
	for cluster in _clusters:
		signatures.append(String(cluster.get("signature", "")))
	signatures.sort()
	return "\n".join(signatures)


func debug_cluster_screen_position(index: int) -> Vector2:
	if index < 0 or index >= _clusters.size():
		return Vector2(-1.0, -1.0)
	var camera := camera_controller.camera if camera_controller != null else get_viewport().get_camera_3d()
	return camera.unproject_position(_clusters[index]["world_position"]) if camera != null else Vector2(-1.0, -1.0)


func debug_draw_count() -> int:
	return int(_battle_markers.visible) + int(_siege_markers.visible)


func debug_marker_instances() -> Vector2i:
	return Vector2i(_battle_markers.multimesh.instance_count, _siege_markers.multimesh.instance_count)


func debug_priority_order() -> Array[String]:
	return ["siege", "battle"]


func debug_markers_visible() -> bool:
	return _battle_markers.visible or _siege_markers.visible
