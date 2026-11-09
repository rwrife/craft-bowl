extends SceneTree

const OUTPUT = "res://WindowsStore/screenshots"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var error = DirAccess.make_dir_recursive_absolute(OUTPUT)
	if error != OK:
		push_error("Cannot create screenshot directory: " + error_string(error))
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	var app = load("res://godot/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	if app.game == null:
		push_error("The game could not start.")
		quit(1)
		return
	app.set_physics_process(false)
	app.audio_enabled = false
	app.random.seed = 20261108
	app.start_game(0, false)
	app.game.tick({"select": 0, "buttons": ["snap"]})
	for tick in 45:
		app.game.tick(app.game.cpu_input())
	if app.game.phase != "live":
		push_error("Expected live gameplay for the gameplay screenshot.")
		quit(1)
		return
	if not await _save("01-gameplay.png"):
		return
	app.random.seed = 20261108
	app.start_game(0, false)
	if not await _save("02-play-selection.png"):
		return
	app.set_screen("team_select")
	if not await _save("03-teams.png"):
		return
	app.set_screen("manage")
	if not await _save("04-roster.png"):
		return
	app.return_to_title()
	if not await _save("05-title.png"):
		return
	quit()


func _save(filename: String) -> bool:
	for frame in 120:
		await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	if image == null or image.get_size() != Vector2i(1920, 1080):
		push_error("Expected a 1920x1080 viewport capture for " + filename)
		quit(1)
		return false
	image.convert(Image.FORMAT_RGB8)
	var path = OUTPUT.path_join(filename)
	var error = image.save_png(path)
	if error != OK:
		push_error("Cannot save " + path + ": " + error_string(error))
		quit(1)
		return false
	print("Saved " + path)
	return true
