extends SceneTree

const Data = preload("res://godot/scripts/data.gd")
const Simulation = preload("res://godot/scripts/simulation.gd")

var failures: Array = []
var data: Dictionary
var teams: Array


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error("FAIL: " + description)


func fresh(seed_value: int = 7, nested: bool = true):
	return Simulation.new(data, teams[0], teams[1], seed_value, nested)


func play_index(id: String) -> int:
	for i in data["offense"].size():
		if data["offense"][i]["id"] == id:
			return i
	return -1


func snap_play(sim, id: String) -> void:
	sim.offense_index = play_index(id)
	sim._snap()


func _run() -> void:
	data = Data.load_game_data()
	teams = Data.make_teams()
	check(not data.is_empty(), "shared playbooks and tuning load")
	check(teams.size() == 9, "all nine teams are present")
	if data.is_empty() or teams.size() < 2:
		_finish()
		return
	check(data["offense"].size() == 8 and data["defense"].size() == 6, "all shipped plays load")
	check(teams[0]["roster"].size() == 18 and teams[0]["roster"]["qb"]["name"].begins_with("Ryan "),
		"team roster matches the original catalog")
	var names = {}
	for team in teams:
		for position in team["roster"]:
			names[team["roster"][position]["name"]] = true
	check(names.size() == 162, "roster names remain unique")

	var sim = fresh()
	check(sim.players.size() == 18 and sim.choices.size() == 3, "9-on-9 formation and three play cards")
	check(sim.choices[0] != sim.choices[1] and sim.choices[1] != sim.choices[2] and
		sim.choices[0] != sim.choices[2], "play cards are distinct")
	sim.tick({"select": 0})
	check(sim.chosen == 0 and sim.phase == "pre_snap", "choosing a card does not snap")
	sim.tick({"buttons": ["snap"]})
	check(sim.phase == "live" and sim.carrier == sim._player_index("qb"), "snap gives the quarterback the ball")

	var auto = fresh()
	for unused in 600:
		auto.tick({})
	check(auto.phase == "live" and auto.chosen >= 0, "play clock chooses and snaps after ten seconds")

	var handoff = fresh()
	snap_play(handoff, "power_run")
	var qb = handoff._player_index("qb")
	var rb = handoff._player_index("rb")
	handoff.tick({"buttons": ["handoff"]})
	check(handoff.carrier == qb, "handoff requires the exchange window")
	handoff.players[rb]["pos"] = handoff.players[qb]["pos"] + Vector2(0, -1.0)
	handoff.tick({"buttons": ["handoff"]})
	check(handoff.carrier == rb and handoff.controlled == rb and handoff.runner_phase,
		"handoff transfers control to the running back")

	var toss = fresh()
	snap_play(toss, "toss_left")
	qb = toss._player_index("qb")
	rb = toss._player_index("rb")
	toss.players[rb]["pos"] = toss.players[qb]["pos"] + Vector2(-3, -2)
	toss.tick({"buttons": ["handoff"]})
	check(toss.ball_state == "flight" and toss.controlled == -1, "a toss uses a real ball flight")
	for unused in 90:
		if toss.ball_state != "flight":
			break
		toss.tick({})
	check(toss.ball_state == "held" and toss.carrier == rb and toss.runner_phase,
		"a caught toss transfers control")

	var passing = fresh()
	snap_play(passing, "spread_pass")
	check(passing.available_actions() == ["pass_left", "pass_center", "pass_right"],
		"available buttons follow the selected play")
	passing.tick({"buttons": ["pass_left"]})
	check(passing.ball_state == "flight" and passing.controlled == -1, "passing launches the ball")
	for unused in 240:
		if passing.ball_state != "flight":
			break
		passing.tick({})
	check(passing.ball_state != "flight", "pass flight resolves to a catch, breakup, or interception")

	var downs = fresh()
	snap_play(downs, "qb_keeper")
	downs._end_play("tackled", Vector2(0, 40))
	for unused in 150:
		downs.tick({})
	check(downs.phase == "pre_snap" and downs.down == 2 and downs.los == 40 and downs.first_down == 45,
		"spot, down, and line to gain survive the whistle")
	snap_play(downs, "qb_keeper")
	downs._end_play("tackled", Vector2(0, 47))
	for unused in 150:
		downs.tick({})
	check(downs.down == 1 and downs.los == 47 and downs.first_down == 57,
		"crossing the line to gain awards a first down")

	var scoring = fresh()
	snap_play(scoring, "qb_keeper")
	scoring._end_play("touchdown", Vector2(0, 110))
	check(scoring.home_score == 7 and scoring.last_outcome == "touchdown", "touchdowns award seven points")
	var final_game = fresh()
	final_game.quarter = 4
	final_game.clock = 0.0
	snap_play(final_game, "qb_keeper")
	final_game._end_play("tackled", Vector2(0, 36))
	for unused in 150:
		final_game.tick({})
	check(final_game.game_over, "the final gun ends the game after the play")

	var a = fresh(42)
	var b = fresh(42)
	for unused in 1800:
		a.tick(a.cpu_input())
		b.tick(b.cpu_input())
	check(a.phase == b.phase and a.home_score == b.home_score and a.los == b.los and
		a.players[0]["pos"] == b.players[0]["pos"] and a.ball_position() == b.ball_position(),
		"same seed and inputs reproduce the same simulation")

	var drive = fresh(123, false)
	snap_play(drive, "qb_keeper")
	drive._end_play("touchdown", Vector2(0, 110))
	for unused in 1500:
		if drive.drive_runner == null:
			break
		drive.tick({})
	check(drive.drive_runner == null and not drive.drive_recap.is_empty(), "opponent possession finishes with a recap")
	if not drive.drive_recap.is_empty():
		check(drive.drive_recap["plays"] > 0 and not drive.drive_recap["play_by_play"].is_empty(),
			"opponent recap contains real simulated plays")
		for unused in 150:
			drive.tick({})
		for unused in 30:
			drive.tick({})
		drive.tick({"buttons": ["snap"]})
		check(drive.drive_recap.is_empty(), "the recap can be dismissed before the next snap")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("Godot simulation tests passed.")
		quit(0)
	else:
		printerr("%d Godot simulation test(s) failed." % failures.size())
		quit(1)
