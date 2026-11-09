extends Control

signal action_pressed(action: String)
signal turbo_changed(held: bool)

var movement = Vector2.ZERO
var enabled = false
var actions: Array = []
var stick_id = -999
var active_actions: Dictionary = {}
var mouse_stick = false
var mouse_action = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func configure(is_enabled: bool, context_actions: Array) -> void:
	if enabled and (not is_enabled or actions != context_actions):
		reset()
	enabled = is_enabled
	actions = context_actions
	queue_redraw()


func reset() -> void:
	movement = Vector2.ZERO
	stick_id = -999
	mouse_stick = false
	mouse_action = ""
	active_actions.clear()
	turbo_changed.emit(false)
	queue_redraw()


func _stick_center() -> Vector2:
	return Vector2(112, size.y - 112)


func _action_center(index: int) -> Vector2:
	var spacing = 80.0
	return Vector2(size.x - 60.0 - float(actions.size() - 1 - index) * spacing, size.y - 75.0)


func _action_at(point: Vector2) -> String:
	for i in actions.size():
		if point.distance_to(_action_center(i)) <= 37.0:
			return actions[i]
	return ""


func _move_stick(point: Vector2) -> void:
	var offset = (point - _stick_center()).limit_length(54.0) / 54.0
	movement = Vector2(offset.x, -offset.y)
	queue_redraw()


func _press_action(action: String) -> void:
	if action == "turbo":
		turbo_changed.emit(true)
	else:
		action_pressed.emit(action)


func _release_action(action: String) -> void:
	if action == "turbo":
		turbo_changed.emit(false)


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var local = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed:
			if stick_id == -999 and local.distance_to(_stick_center()) <= 80:
				stick_id = event.index
				_move_stick(local)
				get_viewport().set_input_as_handled()
			else:
				var action = _action_at(local)
				if not action.is_empty():
					active_actions[event.index] = action
					_press_action(action)
					get_viewport().set_input_as_handled()
		else:
			if event.index == stick_id:
				stick_id = -999
				movement = Vector2.ZERO
				queue_redraw()
				get_viewport().set_input_as_handled()
			if active_actions.has(event.index):
				_release_action(active_actions[event.index])
				active_actions.erase(event.index)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == stick_id:
		_move_stick(get_global_transform_with_canvas().affine_inverse() * event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != -1:
		var local = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed:
			if local.distance_to(_stick_center()) <= 80:
				mouse_stick = true
				_move_stick(local)
				get_viewport().set_input_as_handled()
			else:
				mouse_action = _action_at(local)
				if not mouse_action.is_empty():
					_press_action(mouse_action)
					get_viewport().set_input_as_handled()
		else:
			if mouse_stick:
				mouse_stick = false
				movement = Vector2.ZERO
				queue_redraw()
				get_viewport().set_input_as_handled()
			if not mouse_action.is_empty():
				_release_action(mouse_action)
				mouse_action = ""
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and mouse_stick:
		_move_stick(get_global_transform_with_canvas().affine_inverse() * event.position)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if not enabled:
		return
	var center = _stick_center()
	draw_circle(center, 78, Color(0, 0, 0, 0.24))
	draw_arc(center, 78, 0, TAU, 64, Color(1, 1, 1, 0.45), 2.0, true)
	draw_circle(center + Vector2(movement.x, -movement.y) * 54.0, 30, Color(1, 1, 1, 0.55))
	var font = get_theme_default_font()
	for i in actions.size():
		var action: String = actions[i]
		var center_action = _action_center(i)
		var color = Color("2267d9")
		var label = action.to_upper().replace("_", " ")
		match action:
			"pass_left": color = Color("159dd2")
			"pass_center": color = Color("cda425")
			"pass_right": color = Color("cc4099")
			"handoff": color = Color("32a356")
			"dive": color = Color("b73737")
			"turbo": color = Color("df8c21")
		draw_circle(center_action, 34, Color(color, 0.82))
		draw_arc(center_action, 34, 0, TAU, 48, Color(1, 1, 1, 0.8), 2.0, true)
		var label_size = 12 if label.length() > 5 else 16
		draw_string(font, center_action + Vector2(-34, 5), label, HORIZONTAL_ALIGNMENT_CENTER, 68,
			label_size, Color.WHITE)
