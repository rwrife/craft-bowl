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
	root.add_child(app)
	await process_frame
	app.start_game(0, false)
	await process_frame
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
