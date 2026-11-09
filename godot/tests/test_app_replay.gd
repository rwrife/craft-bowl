extends SceneTree

const Simulation = preload("res://godot/scripts/simulation.gd")

var failures: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error("FAIL: " + description)


func has_keyboard_binding(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return true
	return false


func has_controller_binding(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


func _run() -> void:
	var app = load("res://godot/main.tscn").instantiate()
	var display_sizes = [
		Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
		Vector2i(3440, 1440), Vector2i(1280, 1024), Vector2i(1080, 1920),
		Vector2i(1366, 768), Vector2i(800, 600),
	]
	for display_size in display_sizes:
		var window_size = app.startup_window_size(display_size)
		check(window_size.x > 0 and window_size.y > 0, "startup window has positive dimensions")
		check(window_size.x * 9 == window_size.y * 16, "startup window is exactly 16:9")
		check(window_size.x <= display_size.x * 0.75 and window_size.y <= display_size.y * 0.75,
			"startup window fits within 75 percent of both display dimensions")
		check((window_size.x + 16) > display_size.x * 0.75 or
			(window_size.y + 9) > display_size.y * 0.75,
			"startup window is the largest exact 16:9 size within the display limit")
	check(app.startup_window_size(Vector2i(1920, 1080)) == Vector2i(1440, 810),
		"1080p displays start at 1440 by 810")
	root.add_child(app)
	await process_frame
	if OS.has_feature("pc") and DisplayServer.get_name() != "headless":
		var window = app.get_window()
		if window.mode == Window.MODE_WINDOWED:
			var display_size = DisplayServer.screen_get_size(window.current_screen)
			check(window.size == app.startup_window_size(display_size),
				"desktop startup applies the size for the current display")
			check(window.position == DisplayServer.screen_get_position(window.current_screen) +
				(display_size - window.size) / 2, "desktop startup centers the window on its display")
	app.start_game(0, false)
	await process_frame
	app.show_dev_overlay = true
	app.ui.refresh_game()
	check(app.ui.dev_overlay.visible, "developer overlay is available in-game")
	check(has_keyboard_binding("move_up") and has_keyboard_binding("pass_left"),
		"keyboard movement and action bindings are registered")
	check(has_controller_binding("move_up") and has_controller_binding("pass_left") and
		has_controller_binding("turbo"), "gamepad movement, buttons, and trigger are registered")
	var sideline_player_groups = 0
	for group in app.stadium.sideline_groups:
		if group["members"].size() == 32:
			sideline_player_groups += 1
			for member in group["members"]:
				var yard_line = -member["position"].z
				check(yard_line >= 30.0 and yard_line <= 90.0,
					"sideline players stay grouped between the 20-yard lines")
	check(sideline_player_groups == 2, "both teams field 32 grouped sideline players")
	var pad = app.ui.pad
	pad.configure(true, ["turbo"])
	var touch = InputEventScreenTouch.new()
	touch.index = 3
	touch.pressed = true
	touch.position = pad.get_global_transform_with_canvas() * pad._action_center(0)
	pad._input(touch)
	check(app.touch_turbo, "touch action buttons deliver held turbo input")
	touch.pressed = false
	pad._input(touch)
	touch = InputEventScreenTouch.new()
	touch.index = 4
	touch.pressed = true
	var stick = pad._stick_center()
	touch.position = pad.get_global_transform_with_canvas() * stick
	pad._input(touch)
	var drag = InputEventScreenDrag.new()
	drag.index = 4
	drag.position = pad.get_global_transform_with_canvas() * (stick + Vector2(40, 0))
	pad._input(drag)
	check(pad.movement.x > 0.5, "touch stick delivers directional movement")
	touch.pressed = false
	pad._input(touch)
	var existing_ticks = app.game_inputs.size()
	app.toggle_recording()
	for unused in 240:
		app._physics_process(Simulation.DT + 0.00001)
	app.toggle_recording()
	var recorded_ticks = app.saved_recording.get("inputs", []).size()
	check(recorded_ticks == existing_ticks + 240, "recording stores a complete tick history")
	app.verify_recording()
	check(app.replay_status == "verified", "headless re-simulation verifies the final state")
	app.play_recording()
	for unused in recorded_ticks + 2:
		app._physics_process(Simulation.DT + 0.00001)
	check(app.replay_status == "verified" and app.paused, "playback reaches and verifies the recorded state")
	app.game._snap()
	app.game._end_play("tackled", app.game.players[0]["pos"])
	app.stadium.update_view(Simulation.DT)
	check(app.stadium.impact_sparks.emitting, "tackles trigger arcade impact sparks")
	app.game._snap()
	app.game._end_play("touchdown", Vector2(0, 110))
	app.stadium.update_view(Simulation.DT)
	check(app.stadium.confetti.emitting, "touchdowns trigger a confetti burst")
	app.queue_free()
	app = null
	await process_frame
	await process_frame
	if failures.is_empty():
		print("Godot app replay tests passed.")
		quit(0)
	else:
		printerr("%d Godot app replay test(s) failed." % failures.size())
		quit(1)
