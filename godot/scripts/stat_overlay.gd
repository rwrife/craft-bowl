extends Control

const Simulation = preload("res://godot/scripts/simulation.gd")

var game
var camera: Camera3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null or camera == null or game.game_over or game.halftime or not game.drive_recap.is_empty():
		return
	var shown = []
	if game.phase == "pre_snap":
		for lane in ["left", "center", "right", "backfield"]:
			if game.chosen < 0 or game.offense_play()["slots"][lane]["role"] == "target":
				shown.append(game._player_index(Simulation.LANE_POSITIONS[lane]))
	elif game.phase == "live" and game.runner_phase and game.carrier >= 0:
		shown.append(game.carrier)
	for index in shown:
		if index < 0:
			continue
		var player: Dictionary = game.players[index]
		var world_point = Vector3(player["pos"].x, 2.7, -player["pos"].y)
		if camera.is_position_behind(world_point):
			continue
		var point = get_global_transform_with_canvas().affine_inverse() * camera.unproject_position(world_point)
		var rect = Rect2(point + Vector2(-24, -4), Vector2(48, 9))
		draw_rect(rect.grow(2), Color.BLACK)
		draw_rect(rect, Color(0.9, 0.9, 0.9))
		var health: float = player["health"]
		var values = [player["ratings"]["speed"], player["ratings"]["endurance"], player["ratings"]["ability"]]
		var colors = [Color("32c5ed"), Color("5fe456"), Color("ffae25")]
		var x = rect.position.x + 1.0
		for i in 3:
			var width = 15.0 * float(values[i]) / 99.0 * health
			draw_rect(Rect2(x, rect.position.y + 1.0, width, 7), colors[i])
			x += 15.0
