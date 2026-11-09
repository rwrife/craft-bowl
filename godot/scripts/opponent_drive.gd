extends RefCounted

const OWN_GOAL = 10.0
const GOAL_LINE = 110.0
const KICKOFF = 35.0
const MAX_PLAYS = 40
const MAX_PLAY_TICKS = 60 * 25

var sim
var rng = RandomNumberGenerator.new()
var opponent_name = ""
var score_delta = 0
var trigger = ""
var start_los = KICKOFF
var los = KICKOFF
var first_down = KICKOFF + 10.0
var down = 1
var quarter = 1
var clock = 180.0
var seconds = 0.0
var plays = 0
var play_ticks = 0
var stage = "prepare"
var stats: Dictionary
var log: Array = []
var finished = false
var result: Dictionary = {}


func _init(match_sim, why: String, start: float) -> void:
	rng.seed = match_sim.rng.randi()
	opponent_name = match_sim.away["name"]
	score_delta = match_sim.away_score - match_sim.home_score
	trigger = why
	start_los = clampf(round(start), 11.0, 109.0)
	los = start_los
	first_down = minf(los + 10.0, GOAL_LINE)
	quarter = match_sim.quarter
	clock = match_sim.clock
	stats = match_sim._empty_stats()
	# The same simulation and playbooks drive the opposing offense against the user's defense.
	sim = match_sim.get_script().new(match_sim.data, match_sim.away, match_sim.home, rng.randi(), true)


func advance(budget: int) -> void:
	for unused in budget:
		if finished:
			return
		if stage == "prepare":
			_prepare_play()
		elif stage == "play":
			sim.tick(sim.cpu_input())
			play_ticks += 1
			if play_ticks >= MAX_PLAY_TICKS and sim.phase == "live":
				sim.force_whistle()
			if sim.phase != "live":
				_record_play()


func _prepare_play() -> void:
	if clock <= 0.0:
		if quarter == 1 or quarter == 3:
			quarter += 1
			clock = 180.0
		elif quarter == 2:
			quarter = 3
			clock = 180.0
			_finish("end_of_half", KICKOFF, 0, 0, los)
			return
		else:
			_finish("end_of_game", KICKOFF, 0, 0, los)
			return
	if plays >= MAX_PLAYS:
		_finish("downs", clampf(120.0 - los, 11, 109), 0, 0, los)
		return
	if down == 4:
		var kick_distance = int(round(GOAL_LINE - los)) + 17
		var trailing_late = quarter == 4 and clock < 75 and score_delta < 0
		var short_yardage = first_down - los <= 1.5 and los >= 55
		var go_for_it = (trailing_late and (score_delta < -3 or kick_distance > 52)) or (
			short_yardage and kick_distance > 45 and rng.randf() < 0.6)
		if not go_for_it and kick_distance <= 54:
			plays += 1
			_use_clock(5.0)
			var chance = clampf(1.02 - float(kick_distance - 18) * 0.018, 0.35, 0.97)
			if rng.randf() < chance:
				log.append("%s  %d YD FIELD GOAL IS GOOD" % [_situation(), kick_distance])
				_finish("field_goal", KICKOFF, 3, 0, los)
			else:
				log.append("%s  %d YD FIELD GOAL NO GOOD" % [_situation(), kick_distance])
				_finish("missed_field_goal", maxf(120.0 - (los - 7.0), 30.0), 0, 0, los)
			return
		if not go_for_it:
			plays += 1
			_use_clock(6.0)
			var distance = round(36.0 + rng.randf() * 16.0)
			var landing = los + distance
			if landing >= GOAL_LINE:
				log.append("%s  PUNT %d YDS  TOUCHBACK" % [_situation(), int(distance)])
				_finish("punt", 30.0, 0, 0, los)
			else:
				var returned = rng.randi_range(0, 11)
				log.append("%s  PUNT %d YDS  RETURN %d" % [_situation(), int(distance), returned])
				_finish("punt", clampf(120.0 - landing + returned, 11, 109), 0, 0, los)
			return
	sim.clock = 180.0
	sim.quarter = 1
	sim.setup_play(los, down, first_down)
	sim.tick(sim.cpu_input())
	sim.tick(sim.cpu_input())
	play_ticks = 0
	stage = "play"


func _record_play() -> void:
	plays += 1
	var outcome: String = sim.last_outcome
	var spot: Vector2 = sim.last_spot
	var gain = int(round((GOAL_LINE if outcome == "touchdown" else spot.y) - los))
	if outcome in ["incomplete", "interception"]:
		gain = 0
	if outcome == "safety":
		gain = int(round(OWN_GOAL - los))
	var runoff = 1.0 if outcome in ["incomplete", "out_of_bounds"] else 4.0 + rng.randf() * 5.0
	_use_clock(float(play_ticks) / 60.0 + runoff)
	stats["longest"] = maxi(stats["longest"], gain)
	var before = _situation()
	var signed_gain = "%+d" % gain
	if outcome == "interception":
		stats["pass_attempts"] += 1
		stats["interceptions"] += 1
		stats["turnovers"] += 1
		log.append(before + "  PASS INTERCEPTED")
		var user_spot = 120.0 - spot.y
		_finish("interception", 30.0 if user_spot <= OWN_GOAL else clampf(round(user_spot), 11, 109), 0, 0, los)
		return
	if outcome == "incomplete":
		stats["pass_attempts"] += 1
		log.append(before + "  INCOMPLETE PASS")
	elif outcome == "sack" or (outcome == "safety" and not sim.caught and not sim.runner_phase):
		stats["sacks"] += 1
		stats["sack_yards"] += maxi(0, -gain)
		log.append(before + "  SACKED  " + signed_gain)
	else:
		if sim.caught:
			stats["pass_attempts"] += 1
			stats["completions"] += 1
			stats["pass_yards"] += gain
			if outcome == "touchdown":
				stats["pass_tds"] += 1
			log.append(before + "  PASS  " + signed_gain)
		else:
			stats["rush_attempts"] += 1
			stats["rush_yards"] += gain
			if outcome == "touchdown":
				stats["rush_tds"] += 1
			log.append(before + "  RUN  " + signed_gain)
	if outcome == "fumble":
		stats["turnovers"] += 1
		log[-1] += "  FUMBLE"
		_finish("fumble", clampf(round(120.0 - spot.y), 11, 109), 0, 0, los)
		return
	if outcome == "safety":
		log[-1] += "  SAFETY"
		_finish("safety", KICKOFF, 0, 2, OWN_GOAL)
		return
	if outcome == "touchdown":
		log[-1] += "  TOUCHDOWN"
		_finish("touchdown", KICKOFF, 7, 0, GOAL_LINE)
		return
	var next_spot = los if outcome == "incomplete" else clampf(round(spot.y), 11, 109)
	if next_spot >= first_down:
		stats["first_downs"] += 1
		los = next_spot
		down = 1
		first_down = minf(los + 10.0, GOAL_LINE)
	elif down >= 4:
		stats["turnovers"] += 1
		log[-1] += "  TURNOVER ON DOWNS"
		_finish("downs", clampf(120.0 - next_spot, 11, 109), 0, 0, next_spot)
		return
	else:
		los = next_spot
		down += 1
	stage = "prepare"


func _use_clock(amount: float) -> void:
	seconds += amount
	stats["seconds"] += amount
	clock = maxf(0.0, clock - amount)


func _situation() -> String:
	var ordinal = ["1ST", "2ND", "3RD", "4TH"][clampi(down - 1, 0, 3)]
	var distance = "GOAL" if first_down >= GOAL_LINE else str(maxi(1, int(round(first_down - los))))
	return "%s&%s %s" % [ordinal, distance, _spot(int(round(los - OWN_GOAL)))]


func _spot(yard: int) -> String:
	if yard == 50:
		return "MIDFIELD"
	return "OWN %d" % yard if yard < 50 else "OPP %d" % (100 - yard)


func _finish(ending: String, resume: float, opponent_points: int, user_points: int, end_los: float) -> void:
	if clock <= 0.0 and quarter < 4:
		quarter += 1
		clock = 180.0
	result = {
		"team": opponent_name, "trigger": trigger, "ending": ending,
		"plays": plays, "yards": int(round(end_los - start_los)), "seconds": seconds,
		"start_yard": int(round(start_los - OWN_GOAL)), "end_yard": int(round(end_los - OWN_GOAL)),
		"resume_los": clampf(round(resume), 11, 109), "opponent_points": opponent_points,
		"user_points": user_points, "quarter": quarter, "clock": clock, "stats": stats,
		"play_by_play": log,
	}
	finished = true
