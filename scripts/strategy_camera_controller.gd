extends Node3D
class_name StrategyCameraController

signal map_click_requested(screen_position: Vector2)
signal drag_started()
signal drag_finished()

@export_group("Keyboard Panning")
@export var keyboard_pan_speed := 8.0
@export var keyboard_acceleration := 30.0
@export var keyboard_deceleration := 38.0
@export_range(0.0, 1.0, 0.05) var zoom_speed_multiplier := 0.75

@export_group("Mouse Panning")
@export_range(2.0, 30.0, 1.0) var drag_threshold_pixels := 7.0
@export var enable_left_mouse_drag := true
@export var enable_middle_mouse_drag := true

@export_group("Zoom")
@export var wheel_zoom_step := 0.72
@export var min_camera_height := 0.8
@export var max_camera_height := 13.0
@export var reference_camera_height := 3.5
@export var zoom_to_cursor := true

@export_group("Map Limits")
@export var map_plane_height := 0.0
@export var map_bounds := Rect2(-28.16, -10.24, 56.32, 20.48)

@onready var camera: Camera3D = $Camera3D

var is_dragging := false
var _gesture_active := false
var _gesture_button := MOUSE_BUTTON_NONE
var _press_position := Vector2.ZERO
var _drag_anchor := Vector3.ZERO
var _drag_anchor_valid := false
var _keyboard_velocity := Vector3.ZERO
var _initial_transform := Transform3D.IDENTITY


func _ready() -> void:
	_initial_transform = global_transform
	_ensure_default_input_actions()


func _process(delta: float) -> void:
	_update_keyboard_pan(delta)
	if Input.is_action_just_pressed("camera_zoom_in"):
		_zoom_at_screen(get_viewport().get_visible_rect().size * 0.5, -1.0, 1.0)
	if Input.is_action_just_pressed("camera_zoom_out"):
		_zoom_at_screen(get_viewport().get_visible_rect().size * 0.5, 1.0, 1.0)
	if Input.is_action_just_pressed("camera_reset"):
		reset_camera()


func reset_camera() -> void:
	global_transform = _initial_transform
	_keyboard_velocity = Vector3.ZERO


func focus_world_position(target: Vector3) -> void:
	# Pan so the screen centre lands on the target map point, keeping height.
	var center_intersection := _screen_to_map_plane(get_viewport().get_visible_rect().size * 0.5)
	if center_intersection.is_empty():
		return
	var center: Vector3 = center_intersection["point"]
	global_position += Vector3(target.x - center.x, 0.0, target.z - center.z)
	_keyboard_velocity = Vector3.ZERO
	_clamp_to_map_bounds()


func _update_keyboard_pan(delta: float) -> void:
	if _keyboard_focus_blocks_movement():
		_keyboard_velocity = _keyboard_velocity.move_toward(Vector3.ZERO, keyboard_deceleration * delta)
		return

	var input_direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	var zoom_ratio := clampf(camera.global_position.y / reference_camera_height, 0.35, 3.5)
	var height_scale := lerpf(1.0, zoom_ratio, clampf(zoom_speed_multiplier, 0.0, 1.0))
	var desired_velocity := Vector3(input_direction.x, 0.0, input_direction.y) * keyboard_pan_speed * height_scale
	var rate := keyboard_acceleration if not input_direction.is_zero_approx() else keyboard_deceleration
	_keyboard_velocity = _keyboard_velocity.move_toward(desired_velocity, rate * delta)
	if not _keyboard_velocity.is_zero_approx() and not is_dragging:
		global_position += _keyboard_velocity * delta
		_clamp_to_map_bounds()


func _keyboard_focus_blocks_movement() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _pointer_is_over_ui() -> bool:
	var hovered_control := get_viewport().gui_get_hovered_control()
	return hovered_control != null and hovered_control.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _gesture_active:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if _pointer_is_over_ui():
			return
		var zoom_direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		_zoom_at_screen(event.position, zoom_direction, maxf(absf(event.factor), 1.0))
		get_viewport().set_input_as_handled()
		return

	var is_left_drag_button := event.button_index == MOUSE_BUTTON_LEFT and enable_left_mouse_drag
	var is_middle_drag_button := event.button_index == MOUSE_BUTTON_MIDDLE and enable_middle_mouse_drag
	if not is_left_drag_button and not is_middle_drag_button:
		return

	if event.pressed:
		if _pointer_is_over_ui() or _gesture_active:
			return
		_begin_gesture(event.position, event.button_index)
		get_viewport().set_input_as_handled()
	elif _gesture_active and event.button_index == _gesture_button:
		_finish_gesture(event.position)
		get_viewport().set_input_as_handled()


func _begin_gesture(screen_position: Vector2, button: MouseButton) -> void:
	_gesture_active = true
	_gesture_button = button
	_press_position = screen_position
	_drag_anchor_valid = false
	_keyboard_velocity = Vector3.ZERO
	if button == MOUSE_BUTTON_MIDDLE:
		_start_drag(screen_position)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not is_dragging and event.position.distance_to(_press_position) >= drag_threshold_pixels:
		_start_drag(_press_position)
	if is_dragging:
		_pan_drag(event.position)
		get_viewport().set_input_as_handled()


func _start_drag(screen_position: Vector2) -> void:
	is_dragging = true
	var intersection := _screen_to_map_plane(screen_position)
	if not intersection.is_empty():
		_drag_anchor = intersection["point"]
		_drag_anchor_valid = true
	drag_started.emit()


func _pan_drag(screen_position: Vector2) -> void:
	if not _drag_anchor_valid:
		return
	var intersection := _screen_to_map_plane(screen_position)
	if intersection.is_empty():
		return
	var current_point: Vector3 = intersection["point"]
	var world_delta := _drag_anchor - current_point
	global_position += Vector3(world_delta.x, 0.0, world_delta.z)
	_clamp_to_map_bounds()


func _finish_gesture(screen_position: Vector2) -> void:
	var completed_drag := is_dragging
	var completed_button := _gesture_button
	_gesture_active = false
	_gesture_button = MOUSE_BUTTON_NONE
	is_dragging = false
	_drag_anchor_valid = false
	if completed_drag:
		drag_finished.emit()
	elif completed_button == MOUSE_BUTTON_LEFT:
		map_click_requested.emit(screen_position)


func _cancel_gesture() -> void:
	var was_dragging := is_dragging
	_gesture_active = false
	_gesture_button = MOUSE_BUTTON_NONE
	is_dragging = false
	_drag_anchor_valid = false
	if was_dragging:
		drag_finished.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _gesture_active:
		_cancel_gesture()


func _screen_to_map_plane(screen_position: Vector2) -> Dictionary:
	if camera == null:
		return {}
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) < 0.00001:
		return {}
	var distance := (map_plane_height - ray_origin.y) / ray_direction.y
	if distance < 0.0:
		return {}
	return {"point": ray_origin + ray_direction * distance}


func _zoom_at_screen(screen_position: Vector2, direction: float, amount: float) -> void:
	if camera == null:
		return
	var before := _screen_to_map_plane(screen_position)
	var backward := camera.global_basis.z.normalized()
	if backward.y < 0.0:
		backward = -backward
	var height_scale := clampf(camera.global_position.y / reference_camera_height, 0.45, 3.5)
	var requested_motion := backward * wheel_zoom_step * direction * amount * height_scale
	var current_height := camera.global_position.y
	var target_height := clampf(current_height + requested_motion.y, min_camera_height, max_camera_height)
	if absf(requested_motion.y) < 0.00001 or is_equal_approx(target_height, current_height):
		return
	requested_motion *= (target_height - current_height) / requested_motion.y
	global_position += requested_motion

	if zoom_to_cursor and not before.is_empty():
		var after := _screen_to_map_plane(screen_position)
		if not after.is_empty():
			var anchor_before: Vector3 = before["point"]
			var anchor_after: Vector3 = after["point"]
			global_position += Vector3(anchor_before.x - anchor_after.x, 0.0, anchor_before.z - anchor_after.z)
	_clamp_to_map_bounds()


func _clamp_to_map_bounds() -> void:
	var center_position := get_viewport().get_visible_rect().size * 0.5
	var center_intersection := _screen_to_map_plane(center_position)
	if center_intersection.is_empty():
		return
	var center: Vector3 = center_intersection["point"]
	var clamped_x := clampf(center.x, map_bounds.position.x, map_bounds.end.x)
	var clamped_z := clampf(center.z, map_bounds.position.y, map_bounds.end.y)
	global_position += Vector3(clamped_x - center.x, 0.0, clamped_z - center.z)


func _ensure_default_input_actions() -> void:
	_ensure_key_action("camera_left", [KEY_A], [KEY_LEFT])
	_ensure_key_action("camera_right", [KEY_D], [KEY_RIGHT])
	_ensure_key_action("camera_up", [KEY_W], [KEY_UP])
	_ensure_key_action("camera_down", [KEY_S], [KEY_DOWN])
	_ensure_key_action("camera_zoom_in", [], [KEY_EQUAL, KEY_PAGEUP, KEY_KP_ADD])
	_ensure_key_action("camera_zoom_out", [], [KEY_MINUS, KEY_PAGEDOWN, KEY_KP_SUBTRACT])
	_ensure_key_action("camera_reset", [], [KEY_HOME])


func _ensure_key_action(action_name: StringName, physical_keys: Array, logical_keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	if not InputMap.action_get_events(action_name).is_empty():
		return
	for key in physical_keys:
		var physical_event := InputEventKey.new()
		physical_event.physical_keycode = key
		InputMap.action_add_event(action_name, physical_event)
	for key in logical_keys:
		var logical_event := InputEventKey.new()
		logical_event.keycode = key
		InputMap.action_add_event(action_name, logical_event)
