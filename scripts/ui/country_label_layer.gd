class_name CountryLabelLayer
extends Node3D

## EU4/CK-style country name labels laid flat over each nation's territory.
##
## Large realms get true curved names: a parabolic centreline is fitted through
## the country's provinces and each glyph is placed and rotated along it. Small
## realms keep a single straight (optionally tilted) label. Name size scales
## with province count, so larger realms read larger.
##
## Each country owns a holder Node3D whose children are its glyphs; the glyphs
## are pooled and reused, so ownership changes reposition rather than rebuild.
## Rebuilds happen only on ownership change; per frame there is only a cheap
## zoom level-of-detail and overlap pass.

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")

const MAP_PIXEL_SIZE := 0.01
const MAP_HALF_WIDTH := 28.16
const MAP_HALF_HEIGHT := 10.24
const LABEL_FONT_SIZE := 64
const LABEL_LIFT := 0.03
# Name size scales with land-province count (robust to scattered realms).
const BASE_PIXEL_SIZE := 0.0038
const COUNT_EXPONENT := 0.4
const MIN_PIXEL_SIZE := 0.004
const MAX_PIXEL_SIZE := 0.03
const OVERLAP_TOLERANCE := 0.5
const GLYPH_SPACING := 6.0
# Realms with at least this many provinces get curved per-glyph names; smaller
# ones stay single straight labels for performance.
const CURVE_MIN_COUNT := 6
# A straight name past this elongation follows the territory's long axis, up to
# this tilt so it never runs unreadably vertical.
const ELONGATION_MIN := 1.7
const MAX_TILT := deg_to_rad(42.0)

@export var simulation_controller: GrandWorldSimulationController
@export var map_render: Node

var _graph: ProvinceGraph
var _height_image: Image
var _height_scale := 0.35
var _label_font: FontVariation
var _labels: Dictionary = {}          # tag -> Node3D holder
var _label_weight: Dictionary = {}    # tag -> int land-province count (0 = inactive)
var _label_center: Dictionary = {}    # tag -> Vector2 world (x, z) footprint centre
var _label_half: Dictionary = {}      # tag -> Vector2 half (width, height) footprint
var _dirty := true
var _events_connected := false
var _last_camera_height := -1.0


func _ready() -> void:
	# Period serif via the OS font set (Georgia/Times ship on Windows, the
	# export target); letter-spaced for the engraved map-label look.
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Georgia", "Times New Roman", "serif"])
	_label_font = FontVariation.new()
	_label_font.base_font = system_font
	_label_font.spacing_glyph = int(GLYPH_SPACING)
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
		if tag.is_empty():
			continue
		var country_name := String(names.get(tag, tag)).to_upper()
		if country_name.is_empty() or country_name == "NO OWNER":
			continue
		var provinces: Array = world.country_to_provinces[raw_tag]
		var points: Array[Vector3] = []
		var sum := Vector3.ZERO
		for raw_pid in provinces:
			var pid := int(raw_pid)
			if not _graph.is_land(pid):
				continue
			var point := _anchor_world(pid)
			points.append(point)
			sum += point
		var count := points.size()
		if count == 0:
			continue
		var center := sum / float(count)
		var seat := points[0]
		var best_dist := INF
		for point in points:
			var dist := (point.x - center.x) * (point.x - center.x) + (point.z - center.z) * (point.z - center.z)
			if dist < best_dist:
				best_dist = dist
				seat = point

		var holder: Node3D = _labels.get(tag)
		if holder == null:
			holder = Node3D.new()
			_labels[tag] = holder
			add_child(holder)
		var pixel_size := clampf(BASE_PIXEL_SIZE * pow(float(count), COUNT_EXPONENT), MIN_PIXEL_SIZE, MAX_PIXEL_SIZE)
		var half: Vector2
		if count >= CURVE_MIN_COUNT and country_name.strip_edges().length() >= 3:
			half = _layout_curved(holder, country_name, points, center, seat.y, pixel_size)
		else:
			half = _layout_straight(holder, country_name, seat, pixel_size, _territory_basis(points, center))
		_label_weight[tag] = count
		_label_center[tag] = Vector2(seat.x, seat.z)
		_label_half[tag] = half
		seen[tag] = true

	for tag in _labels.keys():
		if not seen.has(tag):
			_labels[tag].visible = false
			_label_weight[tag] = 0
	_last_camera_height = -1.0


func _ensure_glyphs(holder: Node3D, needed: int) -> void:
	while holder.get_child_count() < needed:
		holder.add_child(_make_glyph())
	for i in holder.get_child_count():
		(holder.get_child(i) as Label3D).visible = i < needed


func _make_glyph() -> Label3D:
	var label := Label3D.new()
	if _label_font != null:
		label.font = _label_font
	label.font_size = LABEL_FONT_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = true
	label.modulate = Color(0.96, 0.94, 0.86)
	label.outline_modulate = Color(0.03, 0.03, 0.05, 0.9)
	label.outline_size = 8
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return label


func _layout_straight(holder: Node3D, text: String, seat: Vector3, pixel_size: float, orientation: Basis) -> Vector2:
	_ensure_glyphs(holder, 1)
	var glyph := holder.get_child(0) as Label3D
	glyph.text = text
	glyph.pixel_size = pixel_size
	glyph.position = Vector3(seat.x, seat.y + LABEL_LIFT, seat.z)
	glyph.basis = orientation
	var width := _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT_SIZE).x * pixel_size
	return Vector2(width * 0.5, float(LABEL_FONT_SIZE) * pixel_size * 0.5)


func _layout_curved(holder: Node3D, text: String, points: Array[Vector3], center: Vector3, base_y: float, pixel_size: float) -> Vector2:
	# Principal axis of the province cloud on the flat map plane.
	var cxx := 0.0
	var czz := 0.0
	var cxz := 0.0
	for point in points:
		var dx := point.x - center.x
		var dz := point.z - center.z
		cxx += dx * dx
		czz += dz * dz
		cxz += dx * dz
	var angle := 0.5 * atan2(2.0 * cxz, cxx - czz)
	var major := Vector3(cos(angle), 0.0, sin(angle))
	# Read left-to-right for wide realms, top-to-bottom for tall ones.
	if absf(major.x) >= absf(major.z):
		if major.x < 0.0:
			major = -major
	elif major.z < 0.0:
		major = -major
	var minor := Vector3(-major.z, 0.0, major.x)

	# Fit perpendicular offset perp(t) = a t^2 + b t + c along the axis, so the
	# name follows the territory's bend.
	var s0 := 0.0
	var s1 := 0.0
	var s2 := 0.0
	var s3 := 0.0
	var s4 := 0.0
	var p0 := 0.0
	var p1 := 0.0
	var p2 := 0.0
	for point in points:
		var d := Vector3(point.x - center.x, 0.0, point.z - center.z)
		var t := d.dot(major)
		var perp := d.dot(minor)
		var t2 := t * t
		s0 += 1.0
		s1 += t
		s2 += t2
		s3 += t2 * t
		s4 += t2 * t2
		p0 += perp
		p1 += perp * t
		p2 += perp * t2
	var coeffs := _solve3(s4, s3, s2, s3, s2, s1, s2, s1, s0, p2, p1, p0)
	var a := coeffs.x
	var b := coeffs.y
	var c := coeffs.z

	# Measure glyph advances and lay the name centred on the curve.
	var advances := PackedFloat32Array()
	var total := 0.0
	for i in text.length():
		var w := (_label_font.get_char_size(text.unicode_at(i), LABEL_FONT_SIZE).x + GLYPH_SPACING) * pixel_size
		advances.append(w)
		total += w
	# Tame the curvature so a sprawling or L-shaped realm can't over-bend its
	# name: cap the end deviation to a fraction of the name's length.
	var half_span := total * 0.5
	var dev := maxf(absf(a * half_span * half_span + b * half_span + c), absf(a * half_span * half_span - b * half_span + c))
	var limit := 0.32 * total
	if dev > limit and dev > 0.0001:
		var scale := limit / dev
		a *= scale
		b *= scale
		c *= scale
	_ensure_glyphs(holder, text.length())
	var cursor := -total * 0.5
	for i in text.length():
		var advance := advances[i]
		var t := cursor + advance * 0.5
		var perp := a * t * t + b * t + c
		var pos := center + major * t + minor * perp
		var tangent := (major + minor * (2.0 * a * t + b)).normalized()
		var glyph := holder.get_child(i) as Label3D
		glyph.text = text[i]
		glyph.pixel_size = pixel_size
		glyph.position = Vector3(pos.x, base_y + LABEL_LIFT, pos.z)
		var glyph_up := Vector3(tangent.z, 0.0, -tangent.x)
		glyph.basis = Basis(tangent, glyph_up, Vector3(0.0, 1.0, 0.0))
		cursor += advance
	return Vector2(total * 0.5, float(LABEL_FONT_SIZE) * pixel_size * 0.5)


func _territory_basis(points: Array[Vector3], center: Vector3) -> Basis:
	var tilt := 0.0
	if points.size() >= 4:
		var cxx := 0.0
		var czz := 0.0
		var cxz := 0.0
		for point in points:
			var dx := point.x - center.x
			var dz := point.z - center.z
			cxx += dx * dx
			czz += dz * dz
			cxz += dx * dz
		var n := float(points.size())
		cxx /= n
		czz /= n
		cxz /= n
		var mid := (cxx + czz) * 0.5
		var radius := sqrt(pow((cxx - czz) * 0.5, 2.0) + cxz * cxz)
		var minor := maxf(mid - radius, 0.00001)
		if (mid + radius) / minor >= ELONGATION_MIN:
			tilt = clampf(0.5 * atan2(2.0 * cxz, cxx - czz), -MAX_TILT, MAX_TILT)
	var advance := Vector3(cos(tilt), 0.0, sin(tilt))
	var glyph_up := Vector3(sin(tilt), 0.0, -cos(tilt))
	return Basis(advance, glyph_up, Vector3(0.0, 1.0, 0.0))


func _solve3(m00: float, m01: float, m02: float, m10: float, m11: float, m12: float, m20: float, m21: float, m22: float, r0: float, r1: float, r2: float) -> Vector3:
	# Cramer's rule for a 3x3 system; returns zero (straight name) if singular.
	var det := m00 * (m11 * m22 - m12 * m21) - m01 * (m10 * m22 - m12 * m20) + m02 * (m10 * m21 - m11 * m20)
	if absf(det) < 1e-9:
		return Vector3.ZERO
	var det_a := r0 * (m11 * m22 - m12 * m21) - m01 * (r1 * m22 - m12 * r2) + m02 * (r1 * m21 - m11 * r2)
	var det_b := m00 * (r1 * m22 - m12 * r2) - r0 * (m10 * m22 - m12 * m20) + m02 * (m10 * r2 - r1 * m20)
	var det_c := m00 * (m11 * r2 - r1 * m21) - m01 * (m10 * r2 - r1 * m20) + r0 * (m10 * m21 - m11 * m20)
	return Vector3(det_a / det, det_b / det, det_c / det)


func _update_zoom_visibility() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_height := camera.global_position.y
	if absf(camera_height - _last_camera_height) < 0.05:
		return
	_last_camera_height = camera_height
	var min_count := maxf(1.0, (camera_height - 1.0) * 0.9)
	var candidates: Array = []
	for tag in _labels.keys():
		var weight: int = _label_weight.get(tag, 0)
		if weight > 0 and float(weight) >= min_count:
			candidates.append(tag)
		else:
			_labels[tag].visible = false
	candidates.sort_custom(func(a: String, b: String) -> bool: return int(_label_weight[a]) > int(_label_weight[b]))
	var kept: Array[Rect2] = []
	for tag in candidates:
		var rect := _label_rect(tag)
		var clash := false
		for other in kept:
			if rect.intersects(other):
				clash = true
				break
		_labels[tag].visible = not clash
		if not clash:
			kept.append(rect)


func _label_rect(tag: String) -> Rect2:
	var c: Vector2 = _label_center.get(tag, Vector2.ZERO)
	var h: Vector2 = _label_half.get(tag, Vector2.ZERO)
	var width := h.x * 2.0 * OVERLAP_TOLERANCE
	var height := h.y * 2.0 * OVERLAP_TOLERANCE
	return Rect2(c.x - width * 0.5, c.y - height * 0.5, width, height)
