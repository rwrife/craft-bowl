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
	app.start_game(0)
	app.set_process(false)
	app.set_physics_process(false)
	var warmup_checksum: String = app._game_checksum(app.game)
	check(app.screen == "intro" and app.stadium.warmup_elapsed == 0.0 and
		app.stadium.camera.position.is_equal_approx(Vector3(-11, 3.4, -48)),
		"warm-up starts with a close camera on the home team")
	check(app.ui.intro_label.text == "%s WARMING UP" % app.game.home["name"].to_upper(),
		"warm-up banner highlights the home team first")
	check(not app.stadium.ball.visible and not app.stadium.line_of_scrimmage.visible and
		not app.stadium.first_down_line.visible and not app.stadium.down_marker.visible and
		not app.stadium.official_root.visible,
		"warm-up hides the ball and gameplay markers")
	var home_root: Node3D = app.stadium.player_nodes[0]["root"]
	var starting_height = home_root.position.y
	app._process(1.25)
	check(is_equal_approx(app.stadium.camera.position.x, 0.0) and home_root.position.y > starting_height,
		"home camera pans while the rendered players jump")
	var away_root: Node3D = app.stadium.player_nodes[9]["root"]
	check(is_equal_approx(home_root.position.z, -38.0) and is_equal_approx(away_root.position.z, -68.0),
		"both warm-up teams occupy the iOS-style two-row formations")
	app._physics_process(Simulation.DT)
	check(app._game_checksum(app.game) == warmup_checksum,
		"warm-up poses and camera do not move simulation players or start the kickoff")
	app._process(1.25)
	check(app.ui.intro_label.text == "%s WARMING UP" % app.game.away["name"].to_upper() and
		app.stadium.camera.position.is_equal_approx(Vector3(-11, 3.4, -58)),
		"second half of the warm-up spotlights the opponent from the opposite side")
	app._process(1.25)
	check(is_equal_approx(app.stadium.camera.position.x, 0.0),
		"opponent camera also pans across its jumping players")
	app._process(1.25)
	check(app.screen == "game" and app.stadium.warmup_elapsed < 0.0 and
		app.game.phase == "kickoff_ready" and app.game.clock == 180.0,
		"five-second warm-up restores gameplay and waits for kickoff readiness")
	check(home_root.position.is_equal_approx(Vector3(app.game.players[0]["pos"].x, 0, -app.game.players[0]["pos"].y)) and
		is_equal_approx(app.stadium.camera.fov, rad_to_deg(0.88)) and app.stadium.official_root.visible,
		"warm-up completion restores simulation poses and the broadcast camera")
	app.set_process(true)
	app.set_physics_process(true)
	app.start_game(0, false)
	await process_frame
	check(app.stadium.warmup_elapsed < 0.0, "autostart and replay can still skip the warm-up")
	app.show_dev_overlay = true
	app.ui.refresh_game()
	check(app.ui.dev_overlay.visible, "developer overlay is available in-game")
	check(has_keyboard_binding("move_up") and has_keyboard_binding("pass_left"),
		"keyboard movement and action bindings are registered")
	check(has_controller_binding("move_up") and has_controller_binding("pass_left") and
		has_controller_binding("turbo"), "gamepad movement, buttons, and trigger are registered")
	check(has_controller_binding("jump") and has_keyboard_binding("jump") and has_controller_binding("field_goal"),
		"defensive jump and kicking controls are registered")
	check(app.game.phase == "kickoff_ready" and not app.ui.pad.enabled, "opening kickoff shows a ready modal")
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
	app.autopilot = true
	app.toggle_recording()
	for unused in 6000:
		app._physics_process(Simulation.DT + 0.00001)
	app.toggle_recording()
	var recorded_ticks = app.saved_recording.get("inputs", []).size()
	check(recorded_ticks == existing_ticks + 6000, "recording stores a complete live-match tick history")
	check(app.game.play_number > 3 and app.game.home_stats["pass_attempts"] + app.game.home_stats["rush_attempts"] > 0,
		"autopilot plays actual scrimmage possessions after the kickoff")
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
	app.autopilot = false
	app.paused = false
	app.game._set_offense(false)
	app.game.setup_play(50, 1, 60)
	app.game.choose(1)
	app.game.offense_index = 0
	app.game._snap()
	app.stadium.set_game(app.game)
	app.ui.refresh_game()
	check(app.ui.pad.actions == ["dive", "jump", "turbo"], "touch defense exposes tackle, jump and turbo")
	var jump_button = InputEventJoypadButton.new()
	jump_button.button_index = JOY_BUTTON_Y
	jump_button.pressed = true
	app.pending_actions.clear()
	app._input(jump_button)
	check(app.pending_actions == ["jump"], "defense Y button jumps instead of handing off")
	app.game._set_offense(true)
	app.game.setup_play(70, 4, 80)
	app.ui.refresh_game()
	var kick_button = InputEventJoypadButton.new()
	kick_button.button_index = JOY_BUTTON_X
	kick_button.pressed = true
	app.pending_actions.clear()
	app._input(kick_button)
	check(app.pending_actions == ["field_goal"], "fourth-down X button kicks instead of selecting a pass")
	app.game.setup_play(69, 4, 79)
	kick_button.button_index = JOY_BUTTON_B
	app.pending_actions.clear()
	app._input(kick_button)
	check(app.pending_actions == ["punt"], "fourth-down B button punts instead of selecting a pass")
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
