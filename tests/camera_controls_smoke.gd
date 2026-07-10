extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Camera controls smoke test failed: %s" % message)
		quit(1)


func _mouse_button(position: Vector2, pressed: bool, button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.pressed = pressed
	event.button_index = button
	return event


func _mouse_motion(position: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event


func _run() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	_require(packed_scene != null, "main scene must load")
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var controller = scene.get_node("CameraController")
	var selector := scene.get_node("Map/ProvinceSelector") as ProvinceSelector
	_require(controller != null, "strategy camera controller must exist")
	_require(InputMap.has_action("camera_left"), "camera input actions must be installed")
	_require(InputMap.has_action("camera_zoom_in"), "keyboard zoom action must be installed")

	var click_positions: Array[Vector2] = []
	var drag_starts := [0]
	var drag_finishes := [0]
	controller.map_click_requested.connect(func(position: Vector2): click_positions.append(position))
	controller.drag_started.connect(func(): drag_starts[0] += 1)
	controller.drag_finished.connect(func(): drag_finishes[0] += 1)

	var center := root.get_visible_rect().size * 0.5
	controller._handle_mouse_button(_mouse_button(center, true, MOUSE_BUTTON_LEFT))
	controller._handle_mouse_motion(_mouse_motion(center + Vector2(3, 2), Vector2(3, 2)))
	_require(not controller.is_dragging, "sub-threshold pointer movement must remain a click")
	controller._handle_mouse_button(_mouse_button(center + Vector2(3, 2), false, MOUSE_BUTTON_LEFT))
	_require(click_positions.size() == 1, "a stationary left gesture must emit exactly one click")
	selector._selection_pending = false

	var position_before_drag: Vector3 = controller.global_position
	controller._handle_mouse_button(_mouse_button(center, true, MOUSE_BUTTON_LEFT))
	controller._handle_mouse_motion(_mouse_motion(center + Vector2(36, 18), Vector2(36, 18)))
	_require(controller.is_dragging, "movement beyond the threshold must start dragging")
	_require(not controller.global_position.is_equal_approx(position_before_drag), "dragging must move the camera")
	controller._handle_mouse_button(_mouse_button(center + Vector2(36, 18), false, MOUSE_BUTTON_LEFT))
	_require(click_positions.size() == 1, "a drag must never emit a province click")
	_require(drag_starts[0] == 1 and drag_finishes[0] == 1, "drag lifecycle signals must balance")
	_require(not selector._selection_pending, "a drag must not queue province selection")

	controller._handle_mouse_button(_mouse_button(center, true, MOUSE_BUTTON_MIDDLE))
	_require(controller.is_dragging, "middle mouse must begin panning immediately")
	controller._handle_mouse_button(_mouse_button(center, false, MOUSE_BUTTON_MIDDLE))
	_require(click_positions.size() == 1, "middle-mouse panning must never emit a province click")

	controller.reset_camera()
	var position_before_keyboard: Vector3 = controller.global_position
	Input.action_press("camera_right")
	controller._process(0.2)
	Input.action_release("camera_right")
	_require(controller.global_position.x > position_before_keyboard.x, "keyboard actions must pan the camera")

	controller.reset_camera()
	var initial_transform: Transform3D = controller.global_transform
	var initial_height: float = controller.camera.global_position.y
	controller._zoom_at_screen(center, -1.0, 1.0)
	var zoomed_in_height: float = controller.camera.global_position.y
	_require(zoomed_in_height < initial_height, "zoom-in must lower the camera toward the map")
	_require(zoomed_in_height >= controller.min_camera_height, "zoom-in must respect minimum height")
	controller._zoom_at_screen(center, 1.0, 1.0)
	_require(controller.camera.global_position.y > zoomed_in_height, "zoom-out must raise the camera")
	_require(controller.camera.global_position.y <= controller.max_camera_height, "zoom-out must respect maximum height")
	controller.reset_camera()
	_require(controller.global_transform.is_equal_approx(initial_transform), "Home/reset must restore the initial view")

	print("Camera controls smoke test passed.")
	scene.queue_free()
	quit(0)
