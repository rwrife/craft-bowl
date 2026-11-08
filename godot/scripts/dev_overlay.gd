extends Control

var app
var stats: Label
var record_button: Button
var replay_button: Button
var verify_button: Button
var pause_button: Button
var slow_button: Button
var autopilot_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel = PanelContainer.new()
	panel.position = Vector2(16, 62)
	panel.size = Vector2(350, 280)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.025, 0.05, 0.94)
	style.border_color = Color("ffdb27")
	style.set_border_width_all(2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title = Label.new()
	title.text = "DEVELOPER"
	title.add_theme_color_override("font_color", Color("ffdb27"))
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	stats = Label.new()
	stats.add_theme_font_size_override("font_size", 13)
	stats.add_theme_color_override("font_color", Color("e6edf5"))
	box.add_child(stats)
	var row = HBoxContainer.new()
	box.add_child(row)
	pause_button = _button("PAUSE")
	pause_button.pressed.connect(_toggle_pause)
	row.add_child(pause_button)
	slow_button = _button("¼×")
	slow_button.pressed.connect(_toggle_slow_motion)
	row.add_child(slow_button)
	autopilot_button = _button("AUTO")
	autopilot_button.pressed.connect(_toggle_autopilot)
	row.add_child(autopilot_button)
	var replay_row = HBoxContainer.new()
	box.add_child(replay_row)
	record_button = _button("RECORD")
	record_button.pressed.connect(_toggle_recording)
	replay_row.add_child(record_button)
	replay_button = _button("REPLAY")
	replay_button.pressed.connect(_play_recording)
	replay_row.add_child(replay_button)
	verify_button = _button("VERIFY")
	verify_button.pressed.connect(_verify_recording)
	replay_row.add_child(verify_button)
	var video_row = HBoxContainer.new()
	box.add_child(video_row)
	var shadows = _button("SHADOWS")
	shadows.pressed.connect(_toggle_setting.bind("shadows"))
	video_row.add_child(shadows)
	var bloom = _button("BLOOM")
	bloom.pressed.connect(_toggle_setting.bind("bloom"))
	video_row.add_child(bloom)
	var resolution = _button("DYN RES")
	resolution.pressed.connect(_toggle_setting.bind("dynamic_resolution"))
	video_row.add_child(resolution)
	visible = false


func _process(_delta: float) -> void:
	if app == null or stats == null:
		return
	var players = 0 if app.game == null else app.game.players.size()
	var phase = "n/a" if app.game == null else app.game.phase
	var tick = 0 if app.game == null else app.game.tick_count
	stats.text = "FPS %d   DRAWS %d\n%s PLAYERS   %s   TICK %d\nREPLAY: %s\nRESOLUTION: %.0f%%" % [
		Engine.get_frames_per_second(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		str(players), phase.to_upper(), tick, app.replay_status,
		app.resolution_scale * 100.0,
	]
	record_button.text = "STOP REC" if app.recording else "RECORD"
	pause_button.text = "RESUME" if app.paused else "PAUSE"
	slow_button.text = "1×" if app.slow_motion else "¼×"
	autopilot_button.text = "AUTO ✓" if app.autopilot else "AUTO"
	replay_button.disabled = app.saved_recording.is_empty() or app.recording
	verify_button.disabled = app.saved_recording.is_empty() or app.recording


func _button(text: String) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(82, 34)
	button.add_theme_font_size_override("font_size", 12)
	return button


func _toggle_pause() -> void:
	app.toggle_pause()


func _toggle_slow_motion() -> void:
	app.toggle_slow_motion()


func _toggle_autopilot() -> void:
	app.toggle_autopilot()


func _toggle_recording() -> void:
	app.toggle_recording()


func _play_recording() -> void:
	app.play_recording()


func _verify_recording() -> void:
	app.verify_recording()


func _toggle_setting(key: String) -> void:
	app.set_setting(key, not app.settings[key])
