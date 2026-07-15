class_name StrategyMinimap
extends Control

## Lightweight campaign minimap. It reuses the authored terrain texture and
## reads the live strategic camera, so it does not create a second viewport or
## render the 3D map twice.

signal world_position_requested(world_position: Vector3)

const MAP_BOUNDS := Rect2(-28.16, -10.24, 56.32, 20.48)
const WORLD_TEXTURE := preload("res://assets/terrain_base_map.png")

@export var camera_controller: StrategyCameraController

var debug_last_requested_world_position := Vector3.ZERO
var _redraw_accumulator := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(286.0, 118.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	queue_redraw()


func _process(delta: float) -> void:
	_redraw_accumulator += delta
	if _redraw_accumulator >= 0.1:
		_redraw_accumulator = 0.0
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	var world_position := world_from_local(mouse_event.position)
	debug_last_requested_world_position = world_position
	if camera_controller != null:
		camera_controller.focus_world_position(world_position)
	world_position_requested.emit(world_position)
	accept_event()


func world_from_local(local_position: Vector2) -> Vector3:
	var safe_size := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var normalized := Vector2(
		clampf(local_position.x / safe_size.x, 0.0, 1.0),
		clampf(local_position.y / safe_size.y, 0.0, 1.0)
	)
	return Vector3(
		MAP_BOUNDS.position.x + normalized.x * MAP_BOUNDS.size.x,
		0.0,
		MAP_BOUNDS.position.y + normalized.y * MAP_BOUNDS.size.y
	)


func _draw() -> void:
	var map_rect := Rect2(Vector2.ZERO, size)
	draw_texture_rect(WORLD_TEXTURE, map_rect, false)
	draw_rect(map_rect, Color("d3aa5f"), false, 2.0)
	if camera_controller == null or camera_controller.camera == null:
		return

	var camera := camera_controller.camera
	var centre := camera_controller.global_position
	var normalized_centre := Vector2(
		(centre.x - MAP_BOUNDS.position.x) / MAP_BOUNDS.size.x,
		(centre.z - MAP_BOUNDS.position.y) / MAP_BOUNDS.size.y
	)
	var viewport_size := get_viewport_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var world_height := camera.size if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else camera.global_position.y * 1.35
	var world_width := world_height * aspect
	var outline_size := Vector2(
		clampf(world_width / MAP_BOUNDS.size.x * size.x, 8.0, size.x),
		clampf(world_height / MAP_BOUNDS.size.y * size.y, 8.0, size.y)
	)
	var outline_centre := Vector2(normalized_centre.x * size.x, normalized_centre.y * size.y)
	var outline := Rect2(outline_centre - outline_size * 0.5, outline_size)
	outline.position.x = clampf(outline.position.x, 0.0, maxf(size.x - outline.size.x, 0.0))
	outline.position.y = clampf(outline.position.y, 0.0, maxf(size.y - outline.size.y, 0.0))
	draw_rect(outline, Color(1.0, 0.93, 0.68, 0.95), false, 2.0)

