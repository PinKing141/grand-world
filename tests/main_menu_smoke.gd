extends SceneTree

const MainMenuScript = preload("res://scripts/ui/main_menu.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Main menu smoke failed: %s" % message)
		quit(1)


func _run() -> void:
	var capture_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
	var packed := load("res://scenes/main_menu.tscn") as PackedScene
	_require(packed != null, "the packaged main-menu scene must load")
	var menu := packed.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame
	_require(not menu.debug_has_reference_branding(), "the menu must not contain DLC, reference-game, or publisher branding")
	var actions: Array = menu.debug_primary_actions()
	_require("SINGLE PLAYER" in actions and "MULTIPLAYER" in actions and "OPTIONS" in actions and "EXIT" in actions, "the reference composition's primary navigation must be present")
	_require(menu.get_node("EuropeBackdrop") is TextureRect, "the menu needs the Europe-focused project terrain backdrop")
	for viewport_size in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var target_size: Vector2 = menu.debug_target_dock_size(viewport_size)
		_require(target_size.x <= viewport_size.x - 24.0 and target_size.y <= viewport_size.y - 24.0, "responsive dock target must retain edge clearance at %s: %s" % [viewport_size, target_size])
	var dock := menu.get_node("MainDock") as Control
	_require(root.get_visible_rect().encloses(dock.get_global_rect()), "main controls must remain inside the active startup viewport: %s" % dock.get_global_rect())
	_require(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main_menu.tscn", "the project must boot into the new menu")
	if not capture_path.is_empty():
		for _frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		_require(capture != null and capture.save_png(capture_path) == OK, "the main-menu visual capture must save")
	print("Main menu smoke passed. actions=%d responsive=3 branding=clean" % actions.size())
	quit(0)
