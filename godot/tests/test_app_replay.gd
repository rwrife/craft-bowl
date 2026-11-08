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
