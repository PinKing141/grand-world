class_name DraggablePanel
extends PanelContainer

## EU4-style moveable window: click and hold any empty area of the panel
## (titles, labels, gaps — buttons keep working) to drag it anywhere on
## screen. Purely presentational; panels never leave the visible canvas.

var _dragging := false
var _drag_offset := Vector2.ZERO
var _pending_global_position := Vector2.ZERO
var _position_pending := false


func _ready() -> void:
	set_process(false)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_dragging = true
			_drag_offset = button.global_position - global_position
			_raise_to_front()
		else:
			_apply_pending_position()
			_dragging = false
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_pending_global_position = motion.global_position - _drag_offset
		_position_pending = true
		# High-polling mice can deliver many motion events per rendered frame.
		# Apply only the newest position to avoid repeated layout invalidation.
		set_process(true)
		accept_event()


func _raise_to_front() -> void:
	# Raise this panel above its siblings within its own HUD, then raise the
	# whole HUD above the other HUD layers, so a clicked window always wins
	# over windows from a different HUD (each HUD is its own Control layer).
	move_to_front()
	var top := self as Control
	while top.get_parent() is Control:
		top = top.get_parent() as Control
	if top != self:
		top.move_to_front()


func _process(_delta: float) -> void:
	_apply_pending_position()
	set_process(false)


func _apply_pending_position() -> void:
	if not _position_pending:
		return
	_position_pending = false
	global_position = _clamped_position(_pending_global_position).round()


func _clamp_to_canvas() -> void:
	global_position = _clamped_position(global_position).round()


func _clamped_position(requested: Vector2) -> Vector2:
	var canvas_size := get_viewport().get_visible_rect().size
	var max_position := (canvas_size - size).max(Vector2.ZERO)
	return requested.clamp(Vector2.ZERO, max_position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_dragging = false
		_position_pending = false
		set_process(false)
	elif what == NOTIFICATION_RESIZED and is_inside_tree():
		_clamp_to_canvas()
