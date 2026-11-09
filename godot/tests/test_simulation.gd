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


func fresh(seed_value: int = 7, skip_kickoff: bool = true):
	return Simulation.new(data, teams[0], teams[1], seed_value, skip_kickoff)


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

	_test_defense_and_kicks()

	_finish()


func settle(sim) -> void:
	for unused in 150:
		sim.tick({})


func _test_defense_and_kicks() -> void:
	var opening = fresh(123, false)
	check(opening.phase == "kickoff_ready" and opening.kickoff_home, "game starts ready to receive a kickoff")
	opening.tick({"buttons": ["snap"]})
	check(opening.phase == "live" and opening.kickoff_return and opening.ball_position() == Vector2(0, 20),
		"kickoff return begins on the receiving team's own ten")
	check(opening.controlled == opening.carrier, "user controls their kickoff returner")
	opening._end_play("tackled", Vector2(0, 38))
	settle(opening)
	check(opening.los == 38 and opening.down == 1 and opening.first_down == 48,
		"kickoff return spot starts first down without counting as a rushing play")
	check(opening.home_stats["rush_attempts"] == 0, "kickoff return is not an offensive rushing attempt")
	snap_play(opening, "qb_keeper")
	opening._end_play("touchdown", Vector2(0, 110))
	check(opening.series_recap["plays"] == 1 and opening.series_recap["yards"] == 72 and
		opening.series_recap["points"] == 7, "scoring recap contains only the current offensive series")
	settle(opening)
	check(opening.phase == "kickoff_ready" and not opening.kickoff_home, "scoring waits for ready to kick")
	for unused in 600:
		opening.tick({})
	check(opening.phase == "kickoff_ready", "kickoff readiness waits for an explicit action")
	opening.tick({"buttons": ["snap"]})
	check(not opening.offense_home and opening.controlled == opening._nearest_home(opening.ball_position()),
		"CPU receives the next kickoff and nearest home defender is active")
	var cpu_start = opening.ball_position()
	for unused in 60:
		opening.tick({})
	check(opening.ball_position().y > cpu_start.y, "CPU actively runs its kickoff return")
	opening._end_play("tackled", Vector2(0, 32))
	settle(opening)
	check(opening.choices.size() == 3, "defense offers exactly three formations")
	var formation_ids = []
	var middle_positions = []
	for i in 3:
		opening.choose(i)
		formation_ids.append(opening.defense_play()["id"])
		middle_positions.append(opening.players[opening._player_index("mlb")]["pos"])
	check(formation_ids == ["mlb_blitz", "man", "zone3"], "rush, man and zone lineups reuse shipped assignments")
	check(middle_positions[0] != middle_positions[1] and middle_positions[1] != middle_positions[2],
		"defensive lineup selection changes the on-field formation")
	opening.choose(1)
	opening.offense_index = play_index("spread_pass")
	opening._snap()
	check(opening.controlled == opening._player_index("mlb") and opening.defense_play()["id"] == "man",
		"CPU snap starts control on MLB and preserves the selected defensive scheme")
	check(opening.players[0]["name"] == teams[1]["roster"]["qb"]["name"] and
		opening.players[9]["name"] == teams[0]["roster"]["deL"]["name"], "opposing possession uses correct team rosters")
	var mlb = opening.controlled
	opening.tick({"move": Vector2.LEFT, "turbo": true, "buttons": ["jump"]})
	check(opening.players[mlb]["jump_ticks"] > 0 and opening.players[mlb]["turbo_active"],
		"controlled defender has jump and turbo")
	var target = opening._player_index("laneLeft")
	opening.players[opening._player_index("cbL")]["pos"] = opening.players[target]["pos"] + Vector2(0, 1)
	opening._pass("left")
	check(opening.controlled == opening._nearest_home(opening.flight["to"]) and opening.controlled >= 9,
		"CPU pass switches to the home defender nearest the intended receiver")
	opening.players[opening.controlled]["pos"] = opening.ball_position()
	opening.players[opening.controlled]["jump_ticks"] = 24
	opening.flight["peak"] = 0.1
	opening._step_ball()
	check(opening.phase == "dead" and opening.message == "JUMP BLOCK!", "jump can block a low pass during flight")

	var picked = fresh()
	snap_play(picked, "spread_pass")
	var defender = picked._player_index("cbL")
	picked.players[defender]["pos"] = Vector2(-8, 66)
	picked._start_return("interception", defender)
	check(picked.phase == "live" and picked.return_play and not picked.user_has_ball() and
		picked.controlled == picked._nearest_home(picked.ball_position()),
		"interception immediately switches user to nearest defender while CPU can return")
	check(picked.home_stats["interceptions"] == 1 and picked.home_stats["turnovers"] == 1,
		"interception is recorded once at the change of hands")
	picked._end_play("tackled", Vector2(-8, 60))
	settle(picked)
	check(not picked.offense_home and picked.los == 60 and picked.down == 1,
		"interception return ends in live defense at the mirrored field spot")
	check(picked.home_stats["pass_attempts"] == 1, "interception return does not double-count the pass")
	picked.offense_index = play_index("spread_pass")
	picked._snap()
	picked.players[defender]["pos"] = Vector2(0, 55)
	picked._start_return("interception", defender)
	check(picked.user_has_ball() and picked.controlled == defender, "user controls interception return against CPU offense")
	picked._end_play("touchdown", Vector2(0, 10))
	check(picked.home_score == 7 and picked.away_score == 0, "pick-six credits the correct team")
	settle(picked)
	check(not picked.kickoff_home and picked.phase == "kickoff_ready", "pick-six is followed by kicking to the CPU")
	var touchback = fresh()
	touchback._snap()
	touchback.players[9]["pos"] = Vector2(0, 115)
	touchback._start_return("interception", 9)
	check(touchback.phase == "dead" and touchback.next_los == 20 and touchback.away_score == 0,
		"interception in the end zone is a touchback, not an accidental safety")

	var stop = fresh()
	stop.setup_play(44, 4, 49)
	stop._snap()
	stop._end_play("tackled", Vector2(0, 46))
	settle(stop)
	check(not stop.offense_home and stop.los == 74 and stop.down == 1, "turnover on downs starts live defense at spot")
	stop.setup_play(70, 1, 80)
	stop.offense_index = play_index("qb_keeper")
	stop._snap()
	stop._end_play("touchdown", Vector2(0, 110))
	check(stop.away_score == 7 and stop.away_stats["rush_tds"] == 1 and stop.home_stats["rush_tds"] == 0,
		"CPU scoring and statistics are credited to the away team")

	var kicking = fresh()
	kicking.setup_play(70, 3, 80)
	check(kicking.kicking_actions().is_empty(), "special kicks are only offered on fourth down")
	kicking.setup_play(69, 4, 79)
	check(kicking.kicking_actions() == ["punt"], "outside opponent forty offers punt")
	kicking._kick("punt")
	check(not kicking.next_offense_home and kicking.next_los == 20, "long punt is capped at opponent ten")
	kicking._set_offense(true)
	kicking.setup_play(25, 4, 35)
	kicking._kick("punt")
	check(kicking.next_los == 45, "punt travels exactly fifty yards when not capped")
	kicking._set_offense(true)
	kicking.setup_play(70, 4, 80)
	var long_chance = kicking.field_goal_chance()
	check(kicking.kicking_actions() == ["field_goal"] and kicking.field_goal_distance() == 57,
		"opponent forty offers field goal with snap and end-zone distance included")
	kicking.setup_play(80, 4, 90)
	var medium_chance = kicking.field_goal_chance()
	kicking.setup_play(100, 4, 110)
	check(long_chance < medium_chance and medium_chance < kicking.field_goal_chance(),
		"field goal success decreases monotonically with distance")
	var made = 0
	var missed = 0
	for seed_value in 40:
		var kick = fresh(seed_value)
		kick.setup_play(70, 4, 80)
		kick._kick("field_goal")
		if kick.home_score == 3:
			made += 1
			settle(kick)
			check(kick.phase == "kickoff_ready" and not kick.kickoff_home, "made field goal awards three then a kickoff")
		else:
			missed += 1
			check(not kick.next_offense_home and kick.next_los == 57, "missed field goal transfers possession at kicking spot")
	check(made > 0 and missed > 0, "seeded field goal probability produces both makes and misses")

	var half = fresh()
	half.quarter = 2
	half.clock = 0
	half._snap()
	half._end_play("tackled", Vector2(0, 40))
	settle(half)
	check(half.halftime, "halftime still interrupts after the play")
	for unused in 90:
		half.tick({})
	half.tick({"buttons": ["snap"]})
	check(half.phase == "kickoff_ready" and not half.kickoff_home, "second half starts with CPU receiving")
	var fumble = fresh()
	fumble._snap()
	fumble.ball_state = "loose"
	fumble.ball_spot = Vector2(0, 54)
	fumble.loose_ticks = 90
	for p in fumble.players:
		p["pos"] = Vector2(20, 90)
	fumble.players[9]["pos"] = fumble.ball_spot
	fumble._resolve_loose_ball()
	check(fumble.return_play and fumble.carrier == 9 and fumble.home_stats["turnovers"] == 1,
		"defensive fumble recovery starts a live return and records a turnover")
	fumble._end_play("tackled", Vector2(0, 48))
	settle(fumble)
	check(not fumble.offense_home and fumble.los == 72, "fumble return sets the next possession spot")
	fumble.offense_index = play_index("qb_keeper")
	fumble._snap()
	fumble.tick({"buttons": ["dive"]})
	check(fumble.players[fumble.controlled]["dive_ticks"] > 0, "controlled defender can dive/tackle")

	var full_match = fresh(900, false)
	var possessions = {}
	for unused in 100000:
		full_match.tick(full_match.cpu_input())
		possessions[full_match.offense_home] = true
		if full_match.game_over:
			break
	check(full_match.game_over and full_match.quarter == 4 and full_match.clock <= 0,
		"four-quarter live match reaches the final whistle")
	check(possessions.size() == 2 and full_match.home_stats["rush_attempts"] + full_match.home_stats["pass_attempts"] > 0 and
		full_match.away_stats["rush_attempts"] + full_match.away_stats["pass_attempts"] > 0,
		"complete match plays and records both teams' real possessions")
	var health = fresh()
	health.players[0]["health"] = 0.2
	health._set_offense(false)
	check(health.players[0]["health"] == 1.0, "opposing QB does not inherit the user's QB exhaustion")
	for unused in 60:
		health._rest_players()
	health._set_offense(true)
	check(health.players[0]["health"] > 0.2 and health.players[0]["health"] < 1.0,
		"returning players retain their health and regenerate while on the sideline")


func _finish() -> void:
	if failures.is_empty():
		print("Godot simulation tests passed.")
		quit(0)
	else:
		printerr("%d Godot simulation test(s) failed." % failures.size())
		quit(1)
