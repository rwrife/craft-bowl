extends Node

const Data = preload("res://godot/scripts/data.gd")
const Simulation = preload("res://godot/scripts/simulation.gd")
const Stadium = preload("res://godot/scripts/stadium.gd")
const HUD = preload("res://godot/scripts/hud.gd")
const TITLE_MUSIC = preload("res://App/TitleMusic.mp3")
const CROWD = preload("res://App/Crowd.mp3")
const WHISTLE = preload("res://App/Whistle.mp3")
const CHEERS = [
	preload("res://App/Cheer.mp3"),
	preload("res://App/Cheer2.mp3"),
	preload("res://App/Cheer3.mp3"),
]
const SETTINGS_PATH = "user://block_bowl_settings.cfg"
const DEFAULT_SETTINGS = {
	"master": 0.85, "music": 0.7, "sfx": 0.9, "crowd": 0.8,
	"shadows": true, "bloom": true, "dynamic_resolution": true,
}

var data: Dictionary
var teams: Array
var game
var stadium
var ui
var screen = "title"
var settings = DEFAULT_SETTINGS.duplicate()
var paused = false
var slow_motion = false
var autopilot = false
var show_dev_overlay = false
var touch_turbo = false
var pending_actions: Array = []
var pending_select = -1
var intro_elapsed = 0.0
var music_player: AudioStreamPlayer
var crowd_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var random = RandomNumberGenerator.new()
var resolution_timer = 0.0
var resolution_scale = 1.0
var screenshot_path = ""
var screenshot_frames = 0
var force_autopilot = false
var audio_enabled = true
var physics_accumulator = 0.0
var active_seed = 1
var active_home_index = 0
var active_away_index = 3
var game_inputs: Array = []
var recording = false
var saved_recording: Dictionary = {}
var playback_active = false
var playback_cursor = 0
var replay_status = "idle"
var debug_touch_ids: Dictionary = {}
var debug_touch_triggered = false


func _ready() -> void:
	_setup_window()
	_setup_input()
	_load_settings()
	data = Data.load_game_data()
	if data.is_empty():
		_show_startup_error("Game data could not be loaded. See the Godot log for details.")
		return
	teams = Data.make_teams()
	random.randomize()
	game = Simulation.new(data, teams[0], teams[3], 1)
	stadium = Stadium.new()
	add_child(stadium)
	stadium.set_game(game)
	stadium.set_video(settings["shadows"], settings["bloom"])
	_setup_audio()
	ui = HUD.new()
	add_child(ui)
	ui.setup(self)
	_parse_arguments()


static func startup_window_size(display_size: Vector2i) -> Vector2i:
	var units = floori(minf(display_size.x * 0.75 / 16.0, display_size.y * 0.75 / 9.0))
	return Vector2i(16, 9) * units


func _setup_window() -> void:
	if not OS.has_feature("pc") or DisplayServer.get_name() == "headless":
		return
	var window = get_window()
	if window.mode != Window.MODE_WINDOWED:
		return
	var current_screen = window.current_screen
	var display_size = DisplayServer.screen_get_size(current_screen)
	window.size = startup_window_size(display_size)
	window.position = DisplayServer.screen_get_position(current_screen) + (display_size - window.size) / 2


func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null


func _show_startup_error(text: String) -> void:
	push_error(text)
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 24)
	add_child(label)


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--autostart":
			start_game(0, false)
		elif argument == "--autopilot":
			force_autopilot = true
		elif argument == "--dev-overlay":
			show_dev_overlay = true
		elif argument.begins_with("--screenshot="):
			screenshot_path = argument.trim_prefix("--screenshot=")
	if show_dev_overlay and screen == "game":
		ui.refresh_game()


func _process(delta: float) -> void:
	if game == null:
		return
	if screen == "intro":
		intro_elapsed += delta
		stadium.warmup_elapsed = intro_elapsed
		if intro_elapsed >= 5.0:
			set_screen("game")
		else:
			ui.refresh_intro()
	stadium.update_view(delta)
	if screen == "game":
		ui.refresh_game()
	_update_crowd_volume()
	_update_resolution(delta)
	if not screenshot_path.is_empty():
		screenshot_frames += 1
		if screenshot_frames >= 120:
			var image = get_viewport().get_texture().get_image()
			if image == null:
				push_error("Could not capture the Godot viewport.")
				get_tree().quit(1)
			else:
				var error = image.save_png(screenshot_path)
				if error != OK:
					push_error("Could not save screenshot: " + error_string(error))
					get_tree().quit(1)
				else:
					print("Saved screenshot to " + screenshot_path)
					get_tree().quit()


func _physics_process(_delta: float) -> void:
	if game == null or paused or screen == "intro":
		return
	physics_accumulator += _delta * (0.25 if slow_motion else 1.0)
	if physics_accumulator < Simulation.DT:
		return
	physics_accumulator -= Simulation.DT
	var input = {}
	if playback_active:
		if playback_cursor >= saved_recording["inputs"].size():
			playback_active = false
			replay_status = "verified" if _game_checksum(game) == saved_recording["checksum"] else "mismatch"
			paused = true
			return
		input = saved_recording["inputs"][playback_cursor].duplicate(true)
		playback_cursor += 1
	elif screen == "game" and not force_autopilot and not autopilot:
		var movement = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		movement.y = -movement.y
		if ui.pad != null and ui.pad.movement.length() > 0.01:
			movement = ui.pad.movement
		input = {
			"move": movement,
			"turbo": Input.is_action_pressed("turbo") or touch_turbo,
			"buttons": pending_actions.duplicate(),
			"select": pending_select,
		}
	else:
		input = game.cpu_input()
	pending_actions.clear()
	pending_select = -1
	if screen == "game":
		game_inputs.append(input.duplicate(true))
	var before = game.phase
	var was_over = game.game_over
	var before_home = game.offense_home
	game.tick(input)
	if game.offense_home != before_home:
		stadium.set_game(game)
	if playback_active and playback_cursor >= saved_recording["inputs"].size():
		playback_active = false
		replay_status = "verified" if _game_checksum(game) == saved_recording["checksum"] else "mismatch"
		paused = true
	if screen == "game" and before in ["live", "pre_snap"] and game.phase == "dead":
		_play_sfx(WHISTLE)
		if game.last_outcome in ["touchdown", "interception", "fumble", "safety", "sack"] or \
				"FIRST DOWN" in game.message or "TURNOVER ON DOWNS" in game.message:
			_play_cheer()
	if screen == "game" and not was_over and game.game_over:
		_play_cheer()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			debug_touch_ids[event.index] = true
			if debug_touch_ids.size() >= 3 and not debug_touch_triggered:
				debug_touch_triggered = true
				show_dev_overlay = not show_dev_overlay
				if screen == "game" and ui != null:
					ui.refresh_game()
				get_viewport().set_input_as_handled()
				return
		else:
			debug_touch_ids.erase(event.index)
			if debug_touch_ids.is_empty():
				debug_touch_triggered = false
	if event.is_action_pressed("toggle_dev_overlay"):
		show_dev_overlay = not show_dev_overlay
		if screen == "game" and ui != null:
			ui.refresh_game()
		get_viewport().set_input_as_handled()
		return
	if screen != "game" or game == null:
		return
	if event.is_action_pressed("pause_game"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if paused:
		return
	if game.phase == "pre_snap" and game.offense_home:
		for kick in game.kicking_actions():
			if event.is_action_pressed(kick):
				queue_action(kick)
				get_viewport().set_input_as_handled()
				return
	if game.phase == "live" and not game.user_has_ball() and event.is_action_pressed("jump"):
		queue_action("jump")
		get_viewport().set_input_as_handled()
		return
	for action in ["pass_left", "pass_center", "pass_right", "handoff", "dive", "snap",
			"next_play", "previous_play"]:
		if event.is_action_pressed(action):
			queue_action(action)
			get_viewport().set_input_as_handled()
			return
	for index in 3:
		if event.is_action_pressed("select_%d" % (index + 1)):
			select_play(index)
			get_viewport().set_input_as_handled()
			return


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == "game" and game != null:
		touch_turbo = false
		pending_actions.clear()
		pending_select = -1
		if ui != null and ui.pad != null:
			ui.pad.reset()
		paused = true


func _add_action(name: String, keys: Array = [], buttons: Array = [], axes: Array = []) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.25)
	for key in keys:
		var event = InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(name, event)
	for button in buttons:
		var event = InputEventJoypadButton.new()
		event.device = -1
		event.button_index = button
		InputMap.action_add_event(name, event)
	for axis in axes:
		var event = InputEventJoypadMotion.new()
		event.device = -1
		event.axis = axis[0]
		event.axis_value = axis[1]
		InputMap.action_add_event(name, event)


func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_add_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add_action("pass_left", [KEY_J], [JOY_BUTTON_X])
	_add_action("pass_center", [KEY_K], [JOY_BUTTON_A])
	_add_action("pass_right", [KEY_L], [JOY_BUTTON_B])
	_add_action("handoff", [KEY_H], [JOY_BUTTON_Y])
	_add_action("snap", [KEY_ENTER, KEY_KP_ENTER])
	_add_action("dive", [KEY_U], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("jump", [KEY_I], [JOY_BUTTON_Y])
	_add_action("field_goal", [KEY_F], [JOY_BUTTON_X])
	_add_action("punt", [KEY_G], [JOY_BUTTON_B])
	_add_action("turbo", [KEY_SPACE], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_add_action("pause_game", [KEY_P, KEY_ESCAPE], [JOY_BUTTON_START])
	_add_action("toggle_dev_overlay", [KEY_QUOTELEFT], [JOY_BUTTON_BACK])
	_add_action("select_1", [KEY_1])
	_add_action("select_2", [KEY_2])
	_add_action("select_3", [KEY_3])
	_add_action("next_play", [], [JOY_BUTTON_LEFT_SHOULDER])
	_add_action("previous_play")


func set_screen(next_screen: String) -> void:
	screen = next_screen
	stadium.warmup_elapsed = intro_elapsed if screen == "intro" else -1.0
	pending_actions.clear()
	pending_select = -1
	touch_turbo = false
	ui.show_screen(screen)
	stadium.update_view(0.0)


func start_game(team_index: int, show_intro: bool = true) -> void:
	if team_index < 0 or team_index >= teams.size():
		push_error("Invalid team selection: %d" % team_index)
		return
	var opponent = random.randi_range(0, teams.size() - 2)
	if opponent >= team_index:
		opponent += 1
	active_home_index = team_index
	active_away_index = opponent
	active_seed = random.randi()
	game = Simulation.new(data, teams[team_index], teams[opponent], active_seed)
	stadium.set_game(game)
	game_inputs.clear()
	paused = false
	slow_motion = false
	autopilot = false
	recording = false
	saved_recording.clear()
	playback_active = false
	replay_status = "idle"
	intro_elapsed = 0.0
	_play_crowd()
	set_screen("intro" if show_intro else "game")


func return_to_title() -> void:
	paused = false
	slow_motion = false
	force_autopilot = false
	autopilot = false
	recording = false
	playback_active = false
	game = Simulation.new(data, teams[0], teams[3], random.randi())
	stadium.set_game(game)
	_play_title()
	set_screen("title")


func queue_action(action: String) -> void:
	if screen == "game" and not paused and action not in pending_actions:
		pending_actions.append(action)


func select_play(index: int) -> void:
	if screen == "game" and not paused:
		pending_select = index


func set_touch_turbo(held: bool) -> void:
	touch_turbo = held


func toggle_pause() -> void:
	paused = not paused
	touch_turbo = false
	pending_actions.clear()
	pending_select = -1


func toggle_slow_motion() -> void:
	slow_motion = not slow_motion


func toggle_autopilot() -> void:
	autopilot = not autopilot
	pending_actions.clear()
	pending_select = -1


func toggle_recording() -> void:
	if recording:
		recording = false
		saved_recording = {
			"home": active_home_index,
			"away": active_away_index,
			"seed": active_seed,
			"inputs": game_inputs.duplicate(true),
			"checksum": _game_checksum(game),
		}
		replay_status = "recorded %d ticks" % game_inputs.size()
	else:
		playback_active = false
		recording = true
		replay_status = "recording"
	if ui != null and screen == "game":
		ui.refresh_game()


func play_recording() -> void:
	if saved_recording.is_empty():
		return
	active_home_index = saved_recording["home"]
	active_away_index = saved_recording["away"]
	active_seed = saved_recording["seed"]
	game = Simulation.new(data, teams[active_home_index], teams[active_away_index], active_seed)
	stadium.set_game(game)
	paused = false
	slow_motion = false
	autopilot = false
	recording = false
	playback_cursor = 0
	playback_active = true
	replay_status = "replaying"
	pending_actions.clear()
	pending_select = -1
	if ui != null:
		ui.refresh_game()


func verify_recording() -> void:
	if saved_recording.is_empty():
		return
	var replay_game = Simulation.new(
		data, teams[saved_recording["home"]], teams[saved_recording["away"]], saved_recording["seed"])
	for input in saved_recording["inputs"]:
		replay_game.tick(input)
	var matches = _game_checksum(replay_game) == saved_recording["checksum"]
	replay_status = "verified" if matches else "mismatch"
	print("Godot replay verification %s (%d ticks)." % [
		"passed" if matches else "failed", saved_recording["inputs"].size(),
	])
	if ui != null and screen == "game":
		ui.refresh_game()


func _game_checksum(simulation) -> String:
	var player_state: Array = []
	for player in simulation.players:
		var position: Vector2 = player["pos"]
		var velocity: Vector2 = player["vel"]
		player_state.append([
			position.x, position.y, velocity.x, velocity.y, player["health"], player["turbo"],
			player["facing"], player["down"], player["recover"], player["jump_ticks"],
		])
	var state = [
		simulation.tick_count, simulation.rng.state, simulation.phase, simulation.phase_ticks,
		simulation.los, simulation.first_down, simulation.down, simulation.home_score, simulation.away_score,
		simulation.quarter, simulation.clock, simulation.game_over, simulation.play_number,
		simulation.choices, simulation.chosen, simulation.offense_index, simulation.defense_index,
		simulation.controlled, simulation.control_assist_ticks, simulation.runner_phase, simulation.ball_state, simulation.carrier,
		simulation.ball_spot.x, simulation.ball_spot.y, simulation.message, player_state,
		simulation.offense_home, simulation.next_offense_home, simulation.return_play, simulation.kickoff_return, simulation.kickoff_home,
		simulation.series_home, simulation.series_stats, simulation.series_plays, simulation.series_recap,
		simulation.home_stats, simulation.away_stats, simulation.flight, simulation.loose_ticks,
		simulation.next_los, simulation.next_down, simulation.next_first_down,
		simulation.scrimmage_recorded, simulation.benched_health,
	]
	var context = HashingContext.new()
	var error = context.start(HashingContext.HASH_SHA256)
	if error != OK:
		push_error("Could not start replay checksum: " + error_string(error))
		return ""
	error = context.update(JSON.stringify(state, "", true).to_utf8_buffer())
	if error != OK:
		push_error("Could not update replay checksum: " + error_string(error))
		return ""
	return context.finish().hex_encode()


func _load_settings() -> void:
	var config = ConfigFile.new()
	var error = config.load(SETTINGS_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		push_error("Could not load settings: " + error_string(error))
		return
	for key in DEFAULT_SETTINGS:
		var value = config.get_value("settings", key, DEFAULT_SETTINGS[key])
		if typeof(value) != typeof(DEFAULT_SETTINGS[key]):
			push_error("Invalid saved setting: " + key)
			continue
		settings[key] = value


func set_setting(key: String, value) -> void:
	if not DEFAULT_SETTINGS.has(key) or typeof(value) != typeof(DEFAULT_SETTINGS[key]):
		push_error("Invalid setting: " + key)
		return
	settings[key] = clampf(value, 0.0, 1.0) if value is float else value
	var config = ConfigFile.new()
	for setting in settings:
		config.set_value("settings", setting, settings[setting])
	var error = config.save(SETTINGS_PATH)
	if error != OK:
		push_error("Could not save settings: " + error_string(error))
	stadium.set_video(settings["shadows"], settings["bloom"])
	_apply_audio_volumes()
	if not settings["dynamic_resolution"]:
		resolution_scale = 1.0
		get_viewport().scaling_3d_scale = resolution_scale


func _make_audio_player(stream: AudioStream, loop: bool) -> AudioStreamPlayer:
	var player = AudioStreamPlayer.new()
	player.stream = stream.duplicate()
	if player.stream is AudioStreamMP3:
		player.stream.loop = loop
	add_child(player)
	return player


func _setup_audio() -> void:
	if DisplayServer.get_name() == "headless":
		audio_enabled = false
		return
	music_player = _make_audio_player(TITLE_MUSIC, true)
	crowd_player = _make_audio_player(CROWD, true)
	sfx_player = _make_audio_player(WHISTLE, false)
	_apply_audio_volumes()
	_play_title()


func _apply_audio_volumes() -> void:
	if music_player == null:
		return
	music_player.volume_db = linear_to_db(maxf(0.0001, settings["master"] * settings["music"]))
	sfx_player.volume_db = linear_to_db(maxf(0.0001, settings["master"] * settings["sfx"]))
	_update_crowd_volume()


func _update_crowd_volume() -> void:
	if crowd_player == null:
		return
	var selection = screen == "game" and game.phase == "pre_snap"
	var volume: float = settings["master"] * settings["crowd"] * (0.75 if selection else 1.0)
	crowd_player.volume_db = linear_to_db(maxf(0.0001, volume))


func _play_title() -> void:
	if not audio_enabled:
		return
	crowd_player.stop()
	if not music_player.playing:
		music_player.play()


func _play_crowd() -> void:
	if not audio_enabled:
		return
	music_player.stop()
	if not crowd_player.playing:
		crowd_player.play()


func _play_sfx(stream: AudioStream) -> void:
	if not audio_enabled:
		return
	sfx_player.stream = stream
	sfx_player.play()


func play_thud() -> void:
	if not audio_enabled:
		return
	var rate = 22050
	var samples = int(rate * 0.55)
	var data = PackedByteArray()
	data.resize(samples * 2)
	var noise = RandomNumberGenerator.new()
	noise.seed = 4411
	var phase = 0.0
	for i in samples:
		var t = float(i) / rate
		phase += TAU * lerpf(95.0, 38.0, minf(t / 0.3, 1.0)) / rate
		var body = sin(phase) * exp(-t * 7.5)
		var crack = noise.randf_range(-1.0, 1.0) * exp(-t * 45.0) * 0.55
		data.encode_s16(i * 2, int(clampf(body + crack, -1.0, 1.0) * 30000.0))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	var player = _make_audio_player(stream, false)
	player.volume_db = linear_to_db(maxf(0.0001, settings["master"] * settings["sfx"])) + 3.0
	player.finished.connect(player.queue_free)
	player.play()


func _play_cheer() -> void:
	if not audio_enabled:
		return
	var player = _make_audio_player(CHEERS[random.randi_range(0, CHEERS.size() - 1)], false)
	player.volume_db = linear_to_db(maxf(0.0001, settings["master"] * settings["sfx"]))
	player.finished.connect(player.queue_free)
	player.play()


func _update_resolution(delta: float) -> void:
	if not settings["dynamic_resolution"] or screen != "game":
		return
	resolution_timer += delta
	if resolution_timer < 2.0:
		return
	resolution_timer = 0.0
	var fps = Engine.get_frames_per_second()
	if fps < 50:
		resolution_scale = maxf(0.7, resolution_scale - 0.05)
	elif fps > 58:
		resolution_scale = minf(1.0, resolution_scale + 0.05)
	get_viewport().scaling_3d_scale = resolution_scale
