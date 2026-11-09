extends Button

const Simulation = preload("res://godot/scripts/simulation.gd")

var play: Dictionary
var slot = 0
var selected = false
var dimmed = false
var game


func configure(simulation, play_data: Dictionary, index: int, is_selected: bool, is_dimmed: bool) -> void:
	game = simulation
	play = play_data
	slot = index
	selected = is_selected
	dimmed = is_dimmed
	custom_minimum_size = Vector2(188, 132)
	flat = true
	focus_mode = Control.FOCUS_ALL
	queue_redraw()


func _point(value: Vector2, area: Rect2) -> Vector2:
	return Vector2(area.position.x + (value.x + 20.0) / 40.0 * area.size.x,
		area.position.y + (15.0 - value.y) / 24.0 * area.size.y)


func _stroke(points: Array, area: Rect2, color: Color, width: float, block: bool = false) -> void:
	if points.size() < 2:
		return
	var clipped = []
	for i in points.size():
		var point: Vector2 = points[i]
		if i > 0 and point.y > 15.0:
			var previous: Vector2 = points[i - 1]
			var t = (15.0 - previous.y) / (point.y - previous.y)
			clipped.append(previous.lerp(point, t))
			break
		clipped.append(point)
	if clipped.size() < 2:
		return
	var rendered = PackedVector2Array()
	for point in clipped:
		rendered.append(_point(point, area))
	draw_polyline(rendered, color, width, true)
	var end = rendered[-1]
	var direction = (end - rendered[-2]).normalized()
	if block:
		var normal = Vector2(-direction.y, direction.x) * 4.0
		draw_line(end - normal, end + normal, color, width + 0.4, true)
	else:
		var normal = Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([end, end - direction * 7.0 + normal * 3.0,
			end - direction * 7.0 - normal * 3.0]), color)


func _draw() -> void:
	if play.is_empty():
		return
	var opacity = 0.6 if dimmed else 1.0
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.07, 0.09, 0.93 * opacity))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.82, 0.1, opacity) if selected else Color(1, 1, 1, 0.4 * opacity),
		false, 3.0 if selected else 1.0)
	var area = Rect2(7, 7, size.x - 14, size.y - 47)
	draw_rect(area, Color(0.035, 0.14, 0.085, opacity))
	var line_y = _point(Vector2.ZERO, area).y
	draw_line(Vector2(area.position.x, line_y), Vector2(area.end.x, line_y), Color(1, 1, 1, 0.28 * opacity), 1.0)
	var yellow = Color(1, 0.85, 0.2, opacity)
	var orange = Color(1, 0.55, 0.2, opacity)
	var chalk = Color(0.9, 0.93, 0.95, 0.8 * opacity)
	for lane in Simulation.LANES:
		var assignment: Dictionary = play["slots"][lane]
		var start: Vector2 = Simulation.FORMATION[Simulation.LANE_POSITIONS[lane]]
		if assignment["role"] == "target":
			match assignment["route"]:
				"handoff":
					_stroke([start, Vector2(0.4, -5.8), Vector2(1.2, -1.5), Vector2(1.6, 6)], area, orange, 2.5)
				"toss":
					_stroke([Vector2(0, -4.5), Vector2(-3, -6.5)], area, chalk, 1.5)
					_stroke([start, Vector2(-3, -6.5), Vector2(-12, -2.5), Vector2(-14.5, 5)], area, orange, 2.5)
				_:
					var points = [start]
					points.append_array(game.route_waypoints(lane, assignment["route"]))
					_stroke(points, area, yellow, 1.8)
		elif assignment["role"] == "lead":
			_stroke([start, Vector2(game._lane_x(lane) * 0.3, 1.5)], area, chalk, 1.5, true)
		else:
			_stroke([start, start + Vector2(0, -1)], area, chalk, 1.5, true)
	if play["kind"] == "keeper":
		_stroke([Vector2(0, -4.5), Vector2(1.5, -1.5), Vector2(2.5, 7)], area, orange, 2.5)
	for position in Simulation.FORMATION:
		var p = _point(Simulation.FORMATION[position], area)
		if position in game.data["format"]["offense"]:
			if position == "qb":
				draw_circle(p, 4.0, yellow)
			else:
				draw_arc(p, 4.0, 0, TAU, 16, Color(0.52, 0.75, 1.0, opacity), 2.0, true)
		else:
			draw_line(p + Vector2(-4, -4), p + Vector2(4, 4), Color(1, 0.3, 0.25, opacity), 2.0)
			draw_line(p + Vector2(-4, 4), p + Vector2(4, -4), Color(1, 0.3, 0.25, opacity), 2.0)
	var font = get_theme_default_font()
	draw_rect(Rect2(10, 10, 20, 20), Color(1, 0.82, 0.1, opacity))
	draw_string(font, Vector2(10, 26), str(slot + 1), HORIZONTAL_ALIGNMENT_CENTER, 20, 16, Color.BLACK)
	var name: String = play["name"].to_upper()
	draw_string(font, Vector2(4, size.y - 23), name, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 15, Color(1, 1, 1, opacity))
	var kind: String = play["kind"].to_upper()
	draw_string(font, Vector2(4, size.y - 7), kind, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 11,
		Color(0.75, 0.8, 0.8, opacity))
