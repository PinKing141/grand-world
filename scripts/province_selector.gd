extends Node3D
class_name ProvinceSelector

signal province_hovered(info: Dictionary, screen_position: Vector2)
signal province_hover_cleared()
signal province_selected(info: Dictionary)
signal selection_cleared()

const RAY_LENGTH := 1000.0
const INVALID_PROVINCE_ID := -1
# World units per province-map pixel: the 56.32 x 20.48 terrain mesh spans the
# 5632 x 2048 province bitmap exactly.
const MAP_PIXEL_SIZE := 0.01

@export var map_data: MapData
@export var country_data: CountryData
@export var province_map: MeshInstance3D
@export var camera_controller: Node

var province_image: Image
var hovered_province_id := INVALID_PROVINCE_ID
var selected_province_id := INVALID_PROVINCE_ID

var _mouse_position := Vector2.ZERO
var _hover_dirty := true
var _selection_pending := false
var _selection_position := Vector2.ZERO
var _camera_drag_active := false


func _ready() -> void:
	set_physics_process(true)
	if camera_controller != null:
		camera_controller.connect("map_click_requested", _on_map_click_requested)
		camera_controller.connect("drag_started", _on_camera_drag_started)
		camera_controller.connect("drag_finished", _on_camera_drag_finished)


func get_current_camera() -> Camera3D:
	return get_viewport().get_camera_3d()


func get_province_at_screen_position(screen_position: Vector2) -> Dictionary:
	if province_image == null or province_image.is_empty() or map_data == null or country_data == null:
		return {}

	var camera := get_current_camera()
	if camera == null:
		return {}

	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := get_world_3d().get_direct_space_state().intersect_ray(query)
	if result.is_empty():
		return {}

	var texture_size := province_image.get_size()
	var pixel_size := MAP_PIXEL_SIZE
	var world_position: Vector3 = result["position"]
	var half_width := texture_size.x * pixel_size * 0.5
	var half_height := texture_size.y * pixel_size * 0.5
	var texture_x := clampi(int((world_position.x + half_width) / pixel_size), 0, texture_size.x - 1)
	var texture_y := clampi(int((world_position.z + half_height) / pixel_size), 0, texture_size.y - 1)
	var province_color := province_image.get_pixel(texture_x, texture_y)

	if not map_data.province_color_to_id.has(province_color):
		return {}

	var province_id: int = map_data.province_color_to_id[province_color]
	if province_id <= 0:
		return {}

	var province_name: String = map_data.province_color_to_name.get(province_color, "Unknown province")
	var owner_tag: String = country_data.province_id_to_owner.get(province_id, "No Owner")
	var owner_name: String = country_data.country_id_to_country_name.get(owner_tag, "")
	var is_playable := not owner_tag.is_empty() and owner_tag not in ["No Owner", "Ocean"] and not owner_name.is_empty()

	return {
		"province_id": province_id,
		"province_name": province_name,
		"owner_tag": owner_tag,
		"owner_name": owner_name,
		"is_playable": is_playable,
		"texture_position": Vector2i(texture_x, texture_y),
	}


func select_at_screen_position(screen_position: Vector2) -> void:
	# Programmatic selection used by search focus; bypasses the UI-hover guard
	# because the request came from the UI itself.
	var info := get_province_at_screen_position(screen_position)
	if info.is_empty():
		return
	selected_province_id = info["province_id"]
	province_selected.emit(info)


func clear_selection() -> void:
	if selected_province_id == INVALID_PROVINCE_ID:
		return
	selected_province_id = INVALID_PROVINCE_ID
	selection_cleared.emit()


func _clear_hover() -> void:
	if hovered_province_id == INVALID_PROVINCE_ID:
		return
	hovered_province_id = INVALID_PROVINCE_ID
	province_hover_cleared.emit()


func _pointer_is_over_ui() -> bool:
	var hovered_control := get_viewport().gui_get_hovered_control()
	return hovered_control != null and hovered_control.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _update_hover(screen_position: Vector2) -> void:
	if _camera_drag_active or _pointer_is_over_ui() or not get_viewport().get_visible_rect().has_point(screen_position):
		_clear_hover()
		return

	var info := get_province_at_screen_position(screen_position)
	if info.is_empty():
		_clear_hover()
		return

	var province_id: int = info["province_id"]
	if province_id != hovered_province_id:
		hovered_province_id = province_id
		province_hovered.emit(info, screen_position)
	else:
		# Keep the tooltip attached to the pointer without rebuilding its content.
		province_hovered.emit(info, screen_position)


func _select_at(screen_position: Vector2) -> void:
	if _pointer_is_over_ui():
		return
	var info := get_province_at_screen_position(screen_position)
	if info.is_empty():
		clear_selection()
		return
	selected_province_id = info["province_id"]
	province_selected.emit(info)


func _on_map_click_requested(screen_position: Vector2) -> void:
	_selection_position = screen_position
	_selection_pending = true


func _on_camera_drag_started() -> void:
	_camera_drag_active = true
	_selection_pending = false
	_clear_hover()


func _on_camera_drag_finished() -> void:
	_camera_drag_active = false
	_hover_dirty = true


func _physics_process(_delta: float) -> void:
	var current_mouse_position := get_viewport().get_mouse_position()
	if current_mouse_position != _mouse_position:
		_mouse_position = current_mouse_position
		_hover_dirty = true

	if _selection_pending:
		_selection_pending = false
		_select_at(_selection_position)
		_hover_dirty = true

	if _hover_dirty:
		_hover_dirty = false
		_update_hover(_mouse_position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_position = (event as InputEventMouseMotion).position
		_hover_dirty = true
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			clear_selection()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			clear_selection()
			get_viewport().set_input_as_handled()
