class_name CountryLabelLayer
extends Node3D

## EU4/CK-style country name labels laid flat over each nation's territory.
## A name is centred on the country's land and its size scales with the
## country's territorial extent, so larger realms read as larger names.
##
## Labels are rebuilt only when ownership changes; the only per-frame work is
## a cheap zoom level-of-detail pass that hides small realms when zoomed out.

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")

const MAP_PIXEL_SIZE := 0.01
const MAP_HALF_WIDTH := 28.16
const MAP_HALF_HEIGHT := 10.24
const LABEL_FONT_SIZE := 64
const LABEL_LIFT := 0.03
const MIN_PIXEL_SIZE := 0.0032
const MAX_PIXEL_SIZE := 0.06
# Fraction of a country's width the name should try to span, and the glyph
# aspect used to fit the text to that width before rendering.
const WIDTH_FILL := 0.85
const GLYPH_ASPECT := 0.55

@export var simulation_controller: GrandWorldSimulationController
@export var map_render: Node

var _graph: ProvinceGraph
var _height_image: Image
var _height_scale := 0.35
var _labels: Dictionary = {}          # tag -> Label3D
var _label_extent: Dictionary = {}    # tag -> float world extent (-1 = inactive)
var _dirty := true
var _events_connected := false
var _last_camera_height := -1.0


func _ready() -> void:
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


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	if events == null:
		return
	_events_connected = true
	events.province_owner_changed.connect(func(_p: int, _o: String, _n: String) -> void: _dirty = true)
	events.world_reloaded.connect(func(_c: String) -> void: _dirty = true)


func _process(_delta: float) -> void:
	if simulation_controller == null or not simulation_controller.initialized:
		return
	if not _events_connected:
		_connect_events()
	if _dirty:
		_dirty = false
		_rebuild_labels()
	_update_zoom_visibility()


func _anchor_world(province_id: int) -> Vector3:
	var anchor := _graph.anchor(province_id)
	var world_x := anchor.x * MAP_PIXEL_SIZE - MAP_HALF_WIDTH
	var world_z := anchor.y * MAP_PIXEL_SIZE - MAP_HALF_HEIGHT
	var world_y := 0.0
	if _height_image != null:
		var sample_x := clampi(int(float(anchor.x) / _graph.map_size.x * _height_image.get_width()), 0, _height_image.get_width() - 1)
		var sample_y := clampi(int(float(anchor.y) / _graph.map_size.y * _height_image.get_height()), 0, _height_image.get_height() - 1)
		world_y = _height_image.get_pixel(sample_x, sample_y).r * _height_scale
	return Vector3(world_x, world_y, world_z)


func _rebuild_labels() -> void:
	var world := simulation_controller.world
	var names: Dictionary = simulation_controller.country_data.country_id_to_country_name
	var seen := {}
	var country_tags := world.country_to_provinces.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		var tag := String(raw_tag)
		var provinces: Array = world.country_to_provinces[raw_tag]
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		var sum := Vector3.ZERO
		var top_y := 0.0
		var count := 0
		for raw_pid in provinces:
			var pid := int(raw_pid)
			if not _graph.is_land(pid):
				continue
			var point := _anchor_world(pid)
			min_x = minf(min_x, point.x)
			max_x = maxf(max_x, point.x)
			min_z = minf(min_z, point.z)
			max_z = maxf(max_z, point.z)
			sum += point
			top_y = maxf(top_y, point.y)
			count += 1
		if count == 0:
			continue
		var center := sum / float(count)
		var bbox_width := max_x - min_x
		var extent := maxf(bbox_width, max_z - min_z)

		var label: Label3D = _labels.get(tag)
		if label == null:
			label = _make_label()
			_labels[tag] = label
			add_child(label)
		var country_name := String(names.get(tag, tag)).to_upper()
		if label.text != country_name:
			label.text = country_name
		var char_count := maxi(country_name.length(), 3)
		var approx_text_px := float(LABEL_FONT_SIZE) * GLYPH_ASPECT * float(char_count)
		var target_world := maxf(bbox_width, 0.25) * WIDTH_FILL
		label.pixel_size = clampf(target_world / approx_text_px, MIN_PIXEL_SIZE, MAX_PIXEL_SIZE)
		label.position = Vector3(center.x, top_y + LABEL_LIFT, center.z)
		_label_extent[tag] = extent
		seen[tag] = true

	for tag in _labels.keys():
		if not seen.has(tag):
			_labels[tag].visible = false
			_label_extent[tag] = -1.0
	# Force the level-of-detail pass to re-evaluate every label next frame.
	_last_camera_height = -1.0


func _make_label() -> Label3D:
	var label := Label3D.new()
	label.font_size = LABEL_FONT_SIZE
	label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)  # lie flat on the map plane
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = true
	label.modulate = Color(0.96, 0.94, 0.86)
	label.outline_modulate = Color(0.03, 0.03, 0.05, 0.92)
	label.outline_size = 16
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return label


func _update_zoom_visibility() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_height := camera.global_position.y
	if absf(camera_height - _last_camera_height) < 0.05:
		return
	_last_camera_height = camera_height
	# Zoomed out (large height) shows only large realms; zoomed in reveals the
	# rest. Keeps a thousand tiny minors from overlapping into noise.
	var min_extent := camera_height * 0.05
	for tag in _labels.keys():
		var extent: float = _label_extent.get(tag, -1.0)
		var label: Label3D = _labels[tag]
		label.visible = extent >= 0.0 and extent >= min_extent
