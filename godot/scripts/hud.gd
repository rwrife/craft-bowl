extends Control

const PlayCard = preload("res://godot/scripts/play_card.gd")
const ControlPad = preload("res://godot/scripts/control_pad.gd")
const StatOverlay = preload("res://godot/scripts/stat_overlay.gd")
const TitleLogo = preload("res://godot/scripts/title_logo.gd")
const Simulation = preload("res://godot/scripts/simulation.gd")
const DevOverlay = preload("res://godot/scripts/dev_overlay.gd")

var app
var layer: Control
var pad
var stat_overlay
var score_home: Label
var score_away: Label
var score_clock: Label
var down_label: Label
var message_label: Label
var turbo_bar: ProgressBar
var health_bar: ProgressBar
var meters: HBoxContainer
var cards: VBoxContainer
var modal: Control
var dev_overlay
var controls_signature = ""
var managed_team = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	font.font_weight = 900
	theme = Theme.new()
	theme.default_font = font
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(application) -> void:
	app = application
	show_screen("title")


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func show_screen(screen: String) -> void:
	if pad != null and is_instance_valid(pad):
		pad.reset()
	pad = null
	stat_overlay = null
	_clear(layer)
	controls_signature = ""
	match screen:
		"title": _build_title()
		"team_select": _build_team_select()
		"manage": _build_management()
		"settings": _build_settings()
		"intro": _build_intro()
		"game": _build_game()
		_: push_error("Unknown app screen: " + screen)


func _full(control: Control, parent: Node = null) -> void:
	if parent == null:
		parent = layer
	parent.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _backdrop(alpha: float = 0.72) -> void:
	var background = ColorRect.new()
	background.color = Color(0.005, 0.01, 0.025, alpha)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(background)


func _style(color: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _button(text: String, color: Color, minimum: Vector2 = Vector2(220, 48)) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(color, Color("f5cd18")))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.17), Color.WHITE))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.2), Color("f5cd18")))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color.WHITE, 2))
	return button


func _label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _centered_box(width: float = 700) -> VBoxContainer:
	var center = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(center)
	var box = VBoxContainer.new()
	box.custom_minimum_size.x = width
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	return box


func _header(title: String) -> HBoxContainer:
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	var back = _button("< BACK", Color(0.1, 0.12, 0.17, 0.9), Vector2(110, 42))
	back.add_theme_font_size_override("font_size", 15)
	back.pressed.connect(app.set_screen.bind("title"))
	header.add_child(back)
	var label = _label(title, 28, Color("ffdb27"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var spacer = Control.new()
	spacer.custom_minimum_size.x = 110
	header.add_child(spacer)
	return header


func _build_title() -> void:
	_backdrop(0.52)
	var box = _centered_box(700)
	var logo = TitleLogo.new()
	box.add_child(logo)
	var kickoff = _button("KICKOFF", Color(0.04, 0.48, 0.87, 0.94), Vector2(700, 58))
	kickoff.pressed.connect(app.set_screen.bind("team_select"))
	box.add_child(kickoff)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var manage = _button("MANAGE TEAMS", Color(0.87, 0.43, 0.09, 0.94), Vector2(344, 58))
	manage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manage.pressed.connect(app.set_screen.bind("manage"))
	row.add_child(manage)
	var settings_button = _button("SETTINGS", Color(0.43, 0.46, 0.48, 0.94), Vector2(344, 58))
	settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_button.pressed.connect(app.set_screen.bind("settings"))
	row.add_child(settings_button)
	kickoff.grab_focus()


func _build_team_select() -> void:
	_backdrop()
	var box = _centered_box(780)
	box.add_child(_header("CHOOSE YOUR TEAM"))
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for i in app.teams.size():
		var team: Dictionary = app.teams[i]
		var tile = _button("%s\n%s\nOVR %d" % [team["abbr"], team["name"].to_upper(), team["overall"]],
			Color(team["primary"], 0.95), Vector2(250, 105))
		tile.add_theme_font_size_override("font_size", 17)
		tile.add_theme_stylebox_override("normal", _style(team["primary"], team["secondary"], 3))
		tile.pressed.connect(app.start_game.bind(i))
		grid.add_child(tile)


func _build_management() -> void:
	_backdrop(0.82)
	var box = _centered_box(920)
	box.add_child(_header("MANAGE TEAMS"))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var list_scroll = ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(285, 430)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(list_scroll)
	var team_list = VBoxContainer.new()
	team_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(team_list)
	for i in app.teams.size():
		var team: Dictionary = app.teams[i]
		var button = _button("%s   %s   %d" % [team["abbr"], team["city"], team["overall"]],
			team["primary"] if i == managed_team else Color(0.04, 0.06, 0.1, 0.9), Vector2(270, 42))
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_select_managed_team.bind(i))
		team_list.add_child(button)
	var roster_panel = PanelContainer.new()
	roster_panel.custom_minimum_size = Vector2(610, 430)
	var selected: Dictionary = app.teams[managed_team]
	roster_panel.add_theme_stylebox_override("panel", _style(Color(selected["primary"], 0.7), selected["secondary"], 3))
	row.add_child(roster_panel)
	var roster_box = VBoxContainer.new()
	roster_panel.add_child(roster_box)
	roster_box.add_child(_label("%s    OVR %d" % [selected["name"].to_upper(), selected["overall"]], 22))
	roster_box.add_child(_label("PLAYER                                      PWR    SPD    END    ABL", 13, Color("ffdc26")))
	var roster_scroll = ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_box.add_child(roster_scroll)
	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(rows)
	for position in app.data["format"]["offense"] + app.data["format"]["defense"]:
		var player: Dictionary = selected["roster"][position]
		var ratings: Dictionary = player["ratings"]
		var display = position.to_upper()
		if position.begins_with("lane"): display = "WR"
		if position in ["deL", "deR"]: display = "DE"
		if position in ["cbL", "cbR"]: display = "CB"
		var player_row = HBoxContainer.new()
		var player_name = _label("#%d  %s  %s" % [player["number"], display, player["name"]], 14)
		player_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_row.add_child(player_name)
		for rating in ["power", "speed", "endurance", "ability"]:
			var value = _label(str(ratings[rating]), 14)
			value.custom_minimum_size.x = 48
			player_row.add_child(value)
		rows.add_child(player_row)


func _select_managed_team(index: int) -> void:
	managed_team = index
	show_screen("manage")


func _build_settings() -> void:
	_backdrop(0.82)
	var box = _centered_box(600)
	box.add_child(_header("SETTINGS"))
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.03, 0.06, 0.92), Color(1, 1, 1, 0.45)))
	box.add_child(panel)
	var settings_box = VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 10)
	panel.add_child(settings_box)
	settings_box.add_child(_label("AUDIO", 20, Color("ffdb27")))
	for key in ["master", "music", "sfx", "crowd"]:
		var row = HBoxContainer.new()
		var name = _label(key.to_upper(), 16)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.custom_minimum_size.x = 120
		row.add_child(name)
		var slider = HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.01
		slider.value = app.settings[key]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_set_volume.bind(key))
		row.add_child(slider)
		var number = _label("%d" % int(slider.value * 100), 15)
		number.custom_minimum_size.x = 45
		row.add_child(number)
		slider.value_changed.connect(func(value): number.text = str(int(value * 100)))
		settings_box.add_child(row)
	settings_box.add_child(_label("VIDEO", 20, Color("ffdb27")))
	for key in ["shadows", "bloom", "dynamic_resolution"]:
		var toggle = CheckBox.new()
		toggle.text = key.to_upper().replace("_", " ")
		toggle.button_pressed = app.settings[key]
		toggle.add_theme_font_size_override("font_size", 16)
		toggle.toggled.connect(_set_toggle.bind(key))
		settings_box.add_child(toggle)


func _set_volume(value: float, key: String) -> void:
	app.set_setting(key, value)


func _set_toggle(value: bool, key: String) -> void:
	app.set_setting(key, value)


func _build_intro() -> void:
	_backdrop(0.65)
	var box = _centered_box(750)
	box.add_child(_label("TONIGHT'S MATCHUP", 24, Color("ffda24")))
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)
	for team in [app.game.home, app.game.away]:
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(280, 160)
		panel.add_theme_stylebox_override("panel", _style(Color(team["primary"], 0.95), team["secondary"], 4))
		var column = VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(column)
		column.add_child(_label(team["abbr"], 52, team["secondary"]))
		column.add_child(_label(team["name"].to_upper(), 18))
		if row.get_child_count() > 0:
			row.add_child(_label("VS", 32, Color("ffda24")))
		row.add_child(panel)
	box.add_child(_label("WARMING UP", 18))


func _score_cell(text: String, width: float, color: Color, font_size: int) -> Label:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 48)
	panel.add_theme_stylebox_override("panel", _style(color, Color.BLACK, 2))
	var label = _label(text, font_size)
	panel.add_child(label)
	return label


func _add_score_cell(row: HBoxContainer, text: String, width: float, color: Color, font_size: int) -> Label:
	var label = _score_cell(text, width, color, font_size)
	row.add_child(label.get_parent())
	return label


func _build_game() -> void:
	pad = ControlPad.new()
	_full(pad)
	pad.action_pressed.connect(_on_pad_action)
	pad.turbo_changed.connect(app.set_touch_turbo)
	stat_overlay = StatOverlay.new()
	stat_overlay.game = app.game
	stat_overlay.camera = app.stadium.camera
	_full(stat_overlay)
	var score = HBoxContainer.new()
	score.add_theme_constant_override("separation", 0)
	layer.add_child(score)
	score.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score.offset_left = -228
	score.offset_right = 228
	score.offset_top = 10
	score.offset_bottom = 58
	_add_score_cell(score, app.game.home["abbr"], 82, app.game.home["primary"], 20)
	score_home = _add_score_cell(score, "0", 70, Color("121827"), 26)
	score_clock = _add_score_cell(score, "Q1\n3:00", 92, Color("090b10"), 17)
	score_away = _add_score_cell(score, "0", 70, Color("121827"), 26)
	_add_score_cell(score, app.game.away["abbr"], 82, app.game.away["primary"], 20)
	var menu = _button("MENU", Color(0, 0, 0, 0.8), Vector2(80, 38))
	menu.add_theme_font_size_override("font_size", 15)
	menu.pressed.connect(app.return_to_title)
	layer.add_child(menu)
	menu.position = Vector2(18, 12)
	var down_panel = PanelContainer.new()
	down_panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.05, 0.1, 0.88), Color(0, 0, 0, 0), 0))
	layer.add_child(down_panel)
	down_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	down_panel.offset_left = -205
	down_panel.offset_right = -20
	down_panel.offset_top = 10
	down_panel.offset_bottom = 70
	down_label = _label("", 19, Color("ffdb25"))
	down_panel.add_child(down_label)
	message_label = _label("", 30, Color("ffdc2b"))
	layer.add_child(message_label)
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.offset_left = -390
	message_label.offset_right = 390
	message_label.offset_top = 80
	message_label.offset_bottom = 135
	meters = HBoxContainer.new()
	meters.alignment = BoxContainer.ALIGNMENT_CENTER
	meters.add_theme_constant_override("separation", 7)
	layer.add_child(meters)
	meters.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	meters.offset_left = -190
	meters.offset_right = 190
	meters.offset_top = -45
	meters.offset_bottom = -13
	meters.add_child(_label("TURBO", 14, Color("ffda24")))
	turbo_bar = _meter(Color("ffcf16"))
	meters.add_child(turbo_bar)
	meters.add_child(_label("HEALTH", 14, Color("48df66")))
	health_bar = _meter(Color("39d05e"))
	meters.add_child(health_bar)
	cards = VBoxContainer.new()
	cards.add_theme_constant_override("separation", 4)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(cards)
	cards.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cards.offset_left = -295
	cards.offset_right = 295
	cards.offset_top = -235
	cards.offset_bottom = -52
	modal = Control.new()
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(modal)
	dev_overlay = DevOverlay.new()
	layer.add_child(dev_overlay)
	dev_overlay.app = app
	refresh_game()


func _meter(color: Color) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(100, 14)
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _style(Color(0.08, 0.1, 0.15, 0.95), Color.WHITE, 1))
	bar.add_theme_stylebox_override("fill", _style(color, color, 0))
	return bar


func _on_pad_action(action: String) -> void:
	app.queue_action("handoff" if action == "toss" else action)


func refresh_game() -> void:
	if app.screen != "game" or pad == null:
		return
	var game = app.game
	stat_overlay.game = game
	dev_overlay.visible = app.show_dev_overlay
	score_home.text = str(game.home_score)
	score_away.text = str(game.away_score)
	var seconds = maxi(0, int(ceil(game.clock)))
	score_clock.text = "Q%d\n%d:%02d" % [game.quarter, int(seconds / 60), seconds % 60]
	var ordinal = ["1ST", "2ND", "3RD", "4TH"][clampi(game.down - 1, 0, 3)]
	var distance = "GOAL" if game.first_down >= Simulation.GOAL_LINE else str(maxi(1, int(round(game.first_down - game.los))))
	var yard = int(round(game.los - Simulation.OWN_GOAL))
	var spot = "MIDFIELD" if yard == 50 else ("OWN %d" % yard if yard < 50 else "OPP %d" % (100 - yard))
	down_label.text = "%s & %s\n%s" % [ordinal, distance, spot]
	message_label.text = game.message if game.message != "SELECT PLAY" else ""
	if game.drive_runner != null:
		message_label.text = "OPPONENT DRIVE..."
	var player = game.players[game.controlled] if game.controlled >= 0 else {}
	turbo_bar.value = player["turbo"] / player["capacity"] if not player.is_empty() else 0
	health_bar.value = player["health"] if not player.is_empty() else 0
	meters.visible = game.phase == "live"
	var signature = "%s:%d:%s:%s:%s:%s:%s:%s" % [
		game.phase, game.chosen, str(game.available_actions()), str(not game.drive_recap.is_empty()),
		str(game.game_over), str(game.halftime), str(game.drive_runner != null),
		str(app.paused) + ":" + str(app.show_dev_overlay),
	]
	if signature != controls_signature:
		controls_signature = signature
		_rebuild_game_controls()


func _rebuild_game_controls() -> void:
	var game = app.game
	_clear(cards)
	_clear(modal)
	var is_modal = not game.drive_recap.is_empty() or game.game_over or game.halftime or app.paused
	var actions = []
	if not is_modal and game.drive_runner == null:
		if game.phase == "pre_snap":
			if game.chosen >= 0:
				actions = ["snap"]
			cards.add_child(_label("SPD  /  END  /  ABL   x  HEALTH", 12, Color("e4edf4")))
			var row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 8)
			cards.add_child(row)
			for i in game.choices.size():
				var card = PlayCard.new()
				card.configure(game, game.data["offense"][game.choices[i]], i, game.chosen == i,
					game.chosen >= 0 and game.chosen != i)
				card.pressed.connect(app.select_play.bind(i))
				row.add_child(card)
		elif game.phase == "live":
			actions = game.available_actions()
			if actions.is_empty():
				actions = ["dive", "turbo"]
	pad.configure(not is_modal and game.drive_runner == null, actions)
	if app.paused:
		_show_modal("PAUSED", ["The game is paused."], "RESUME", app.toggle_pause)
	elif game.game_over:
		_show_game_summary("FINAL", true)
	elif game.halftime:
		_show_game_summary("HALFTIME", false)
	elif not game.drive_recap.is_empty():
		_show_drive_recap(game.drive_recap)


func _show_modal(title: String, lines: Array, button_text: String, callback: Callable, extra: Callable = Callable()) -> void:
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_full(shade, modal)
	var center = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(center, modal)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", _style(Color(0.025, 0.05, 0.09, 0.97), Color("ffcf20"), 3))
	center.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label(title, 30, Color("ffda20")))
	for line in lines:
		box.add_child(_label(str(line), 17))
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var button = _button(button_text, Color("2457d6"), Vector2(220, 45))
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(callback)
	buttons.add_child(button)
	if extra.is_valid():
		var menu = _button("MENU", Color("6b7079"), Vector2(150, 45))
		menu.add_theme_font_size_override("font_size", 17)
		menu.pressed.connect(extra)
		buttons.add_child(menu)
	button.grab_focus()


func _show_drive_recap(recap: Dictionary) -> void:
	var ending = str(recap["ending"]).to_upper().replace("_", " ")
	var lines = [
		"%s   %s" % [str(recap["trigger"]).to_upper().replace("_", " "), ending],
		"%d PLAYS   %+d YARDS   %d POINTS" % [recap["plays"], recap["yards"], recap["opponent_points"]],
	]
	var plays: Array = recap["play_by_play"]
	for i in range(maxi(0, plays.size() - 4), plays.size()):
		lines.append(plays[i])
	var own_yard = int(recap["resume_los"] - 10)
	lines.append("YOUR BALL  %s" % ("OWN %d" % own_yard if own_yard < 50 else "OPP %d" % (100 - own_yard)))
	_show_modal(str(recap["team"]).to_upper() + " DRIVE", lines, "CONTINUE", app.queue_action.bind("snap"))


func _show_game_summary(title: String, final_score: bool) -> void:
	var game = app.game
	var home: Dictionary = game.home_stats
	var away: Dictionary = game.away_stats
	var lines = [
		"%s  %d  -  %d  %s" % [game.home["abbr"], game.home_score, game.away_score, game.away["abbr"]],
		"FIRST DOWNS    %d  -  %d" % [home["first_downs"], away["first_downs"]],
		"PASS YARDS       %d  -  %d" % [home["pass_yards"], away["pass_yards"]],
		"RUSH YARDS       %d  -  %d" % [home["rush_yards"], away["rush_yards"]],
		"TURNOVERS        %d  -  %d" % [home["turnovers"], away["turnovers"]],
	]
	_show_modal(title, lines, "REMATCH" if final_score else "CONTINUE",
		app.queue_action.bind("snap"), app.return_to_title if final_score else Callable())
