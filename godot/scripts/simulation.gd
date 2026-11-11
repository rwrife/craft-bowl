extends RefCounted

const DT = 1.0 / 60.0
const HALF_WIDTH = 53.333 / 2.0
const GOAL_LINE = 110.0
const OWN_GOAL = 10.0
const KICKOFF = 35.0
const RADIUS = 0.42
const DEFENSIVE_TURBO_BONUS = 1.10
const DEFENSIVE_DIVE_BONUS = 1.15
const LANES = ["left", "center", "right", "backfield"]
const LANE_POSITIONS = {
	"left": "laneLeft", "center": "laneCenter", "right": "laneRight", "backfield": "rb",
}
const FORMATION = {
	"qb": Vector2(0, -4.5), "rb": Vector2(0, -7),
	"laneLeft": Vector2(-17, -1), "laneCenter": Vector2(7, -1.5), "laneRight": Vector2(17, -1),
	"lt": Vector2(-3.1, -1), "lg": Vector2(-1.05, -1), "rg": Vector2(1.05, -1), "rt": Vector2(3.1, -1),
	"deL": Vector2(-2.6, 1.1), "nt": Vector2(0, 1.1), "deR": Vector2(2.6, 1.1),
	"mlb": Vector2(0, 5), "olb": Vector2(7.5, 4.5), "cbL": Vector2(-17, 6),
	"cbR": Vector2(17, 6), "fs": Vector2(-6, 14), "ss": Vector2(6, 12),
}

var data: Dictionary
var home: Dictionary
var away: Dictionary
var curves: Dictionary
var players: Array = []
var rng = RandomNumberGenerator.new()
var tick_count = 0

var phase = "pre_snap"
var phase_ticks = 0
var los = KICKOFF
var first_down = KICKOFF + 10.0
var down = 1
var next_los = KICKOFF
var next_first_down = KICKOFF + 10.0
var next_down = 1
var home_score = 0
var away_score = 0
var quarter = 1
var clock = 180.0
var game_over = false
var halftime = false
var halftime_due = false
var modal_ticks = 0
var play_number = 0
var choices: Array = []
var chosen = -1
var offense_index = 0
var defense_index = 0
var controlled = -1
var control_assist_ticks = 0
var runner_phase = false
var message = "SELECT PLAY"
var last_outcome = ""
var last_spot = Vector2.ZERO
var thrown = false
var caught = false
var route_breaks: Dictionary = {}

var ball_state = "dead"
var carrier = -1
var ball_spot = Vector2.ZERO
var flight: Dictionary = {}
var loose_ticks = 0
var toss_target = -1
var home_stats = _empty_stats()
var away_stats = _empty_stats()
var offense_home = true
var next_offense_home = true
var return_play = false
var kickoff_return = false
var kickoff_home = true
var series_stats = _empty_stats()
var series_plays = 0
var series_home = true
var series_recap: Dictionary = {}
var scrimmage_recorded = false
var benched_health: Dictionary = {}


func _init(game_data: Dictionary = {}, home_team: Dictionary = {}, away_team: Dictionary = {},
		seed_value: int = 1, skip_kickoff: bool = false) -> void:
	if game_data.is_empty():
		return
	data = game_data
	home = home_team
	away = away_team
	curves = data["curves"]
	rng.seed = seed_value
	var positions: Array = data["format"]["offense"] + data["format"]["defense"]
	for i in positions.size():
		var position: String = positions[i]
		var team = home if i < 9 else away
		var profile: Dictionary = team["roster"][position]
		var ratings: Dictionary = profile["ratings"].duplicate()
		var capacity = _curve("turboCapacityMin", "turboCapacityMax", _rating(ratings, "endurance"))
		players.append({
			"id": i, "position": position, "offense": i < 9, "number": profile["number"],
			"name": profile["name"], "ratings": ratings, "pos": Vector2.ZERO, "vel": Vector2.ZERO,
			"facing": 0.0 if i < 9 else PI, "health": 1.0, "turbo": capacity,
			"capacity": capacity, "cooldown": 0.0, "turbo_active": false, "exerting": false,
			"down": false, "dive_ticks": 0, "jump_ticks": 0, "recover": 0, "engaged": 0,
		})
	_reset_formation()
	if not skip_kickoff:
		_prepare_kickoff(true)


static func _empty_stats() -> Dictionary:
	return {
		"pass_attempts": 0, "completions": 0, "pass_yards": 0, "pass_tds": 0,
		"interceptions": 0, "sacks": 0, "sack_yards": 0, "rush_attempts": 0,
		"rush_yards": 0, "rush_tds": 0, "first_downs": 0, "longest": 0,
		"turnovers": 0, "seconds": 0.0,
	}


func _rating(ratings: Dictionary, key: String) -> float:
	return (float(ratings[key]) - 1.0) / 98.0


func _curve(low: String, high: String, amount: float) -> float:
	return lerpf(float(curves[low]), float(curves[high]), amount)


func _ability(p: Dictionary) -> float:
	return _rating(p["ratings"], "ability") * lerpf(float(curves["exhaustedAbilityFactor"]), 1.0, p["health"])


func _player_index(position: String) -> int:
	for p in players:
		if p["position"] == position:
			return p["id"]
	return -1


func offense_play() -> Dictionary:
	return data["offense"][offense_index]


func defense_play() -> Dictionary:
	return data["defense"][defense_index]


func ball_position() -> Vector2:
	if ball_state == "held" and carrier >= 0:
		return players[carrier]["pos"]
	if ball_state == "flight":
		var t = clampf(flight["elapsed"] / flight["duration"], 0.0, 1.0)
		var delta: Vector2 = flight["to"] - flight["from"]
		var direction = delta.normalized()
		return flight["from"] + delta * t + Vector2(-direction.y, direction.x) * \
			flight["wobble"] * sin(TAU * t) * sin(PI * t)
	return ball_spot


func ball_height() -> float:
	if ball_state == "flight":
		var t = clampf(flight["elapsed"] / flight["duration"], 0.0, 1.0)
		return 1.15 + 4.0 * float(flight["peak"]) * t * (1.0 - t)
	return 1.15 if ball_state == "held" else 0.14


func available_actions() -> Array:
	if not user_has_ball():
		return []
	return _qb_actions()


func user_has_ball() -> bool:
	return offense_home != return_play


func _stats() -> Dictionary:
	return home_stats if offense_home else away_stats


func _qb_actions() -> Array:
	if phase != "live" or runner_phase or ball_state != "held" or carrier < 0:
		return []
	var qb: Dictionary = players[carrier]
	if qb["position"] != "qb" or qb["pos"].y >= los:
		return []
	var slots: Dictionary = offense_play()["slots"]
	var result = []
	for lane in ["left", "center", "right"]:
		if slots[lane]["role"] == "target":
			result.append("pass_" + lane)
	if slots["backfield"]["role"] == "target":
		var route: String = slots["backfield"]["route"]
		if route == "handoff" or route == "toss":
			result.append(route)
	return result


func tick(input: Dictionary = {}) -> void:
	phase_ticks += 1
	if game_over:
		_rest_players()
		if _pressed(input) and phase_ticks >= 90:
			start_new_game()
		return
	if halftime:
		modal_ticks += 1
		if _pressed(input) and modal_ticks >= 90:
			halftime = false
			halftime_due = false
			_prepare_kickoff(false)
		return
	if phase == "kickoff_ready":
		_rest_players()
		if _pressed(input):
			_start_kickoff()
		return
	if phase == "pre_snap":
		_rest_players()
		_step_pre_snap(input)
	elif phase == "live":
		_step_live(input)
	else:
		_rest_players()
		if phase_ticks >= 150:
			if quarter == 4 and clock <= 0.0:
				_end_game()
			elif halftime_due:
				_start_halftime()
			elif not series_recap.is_empty():
				phase = "kickoff_ready"
				phase_ticks = 0
			else:
				_reset_formation()


func _pressed(input: Dictionary) -> bool:
	return not input.get("buttons", []).is_empty() or int(input.get("select", -1)) >= 0


func _step_pre_snap(input: Dictionary) -> void:
	var buttons: Array = input.get("buttons", [])
	if offense_home and "field_goal" in buttons and "field_goal" in kicking_actions():
		_kick("field_goal")
		return
	if offense_home and "punt" in buttons and "punt" in kicking_actions():
		_kick("punt")
		return
	var was_chosen = chosen >= 0
	var selection = int(input.get("select", -1))
	if selection >= 0 and selection < choices.size():
		choose(selection)
	if not was_chosen:
		for i in 3:
			if ["pass_left", "pass_center", "pass_right"][i] in buttons:
				choose(i)
				break
	if "next_play" in buttons:
		choose((chosen + 1) % choices.size())
	if "previous_play" in buttons:
		choose((chosen + choices.size() - 1) % choices.size())
	if chosen >= 0 and ("snap" in buttons or (was_chosen and (
			"pass_left" in buttons or "pass_center" in buttons or "pass_right" in buttons or "handoff" in buttons))):
		_snap()
	elif phase_ticks >= 600:
		if chosen < 0:
			choose(rng.randi_range(0, choices.size() - 1))
		_snap()


func choose(index: int) -> void:
	if index < 0 or index >= choices.size():
		push_error("Invalid play-card selection: %d" % index)
		return
	chosen = index
	if offense_home:
		offense_index = choices[index]
	else:
		defense_index = choices[index]
		_position_defense()


func _deal() -> void:
	if not offense_home:
		choices = []
		for id in ["mlb_blitz", "man", "zone3"]:
			for i in data["defense"].size():
				if data["defense"][i]["id"] == id:
					choices.append(i)
		chosen = -1
		offense_index = rng.randi_range(0, data["offense"].size() - 1)
		return
	var pool = range(data["offense"].size())
	choices = []
	while choices.size() < 3 and not pool.is_empty():
		var index = rng.randi_range(0, pool.size() - 1)
		choices.append(pool[index])
		pool.remove_at(index)
	chosen = -1


func _snap() -> void:
	if not offense_home and not kicking_actions().is_empty():
		_kick(kicking_actions()[0])
		return
	if offense_home:
		defense_index = rng.randi_range(0, data["defense"].size() - 1)
	_position_defense()
	carrier = _player_index("qb")
	ball_state = "held"
	controlled = carrier if offense_home else _player_index("mlb")
	control_assist_ticks = 0
	phase = "live"
	phase_ticks = 0
	runner_phase = false
	return_play = false
	kickoff_return = false
	scrimmage_recorded = false
	thrown = false
	caught = false
	toss_target = -1
	loose_ticks = 0
	route_breaks.clear()
	message = ""
	play_number += 1


func _step_live(input: Dictionary) -> void:
	if kickoff_return and ball_state == "flight":
		_step_ball()
		tick_count += 1
		return
	var used = minf(clock, DT)
	clock -= used
	var possession_stats = home_stats if user_has_ball() else away_stats
	possession_stats["seconds"] += used
	series_stats["seconds"] += used
	_update_defensive_control()
	var intents = _ai_intents()
	if loose_ticks > 0:
		for p in players:
			if not p["down"]:
				intents[p["id"]] = {"move": (ball_spot - p["pos"]).normalized()}
	if controlled >= 0:
		var intent: Dictionary = intents[controlled]
		if control_assist_ticks == 0:
			intent["move"] = input.get("move", Vector2.ZERO)
		intent["turbo"] = input.get("turbo", false) or intent.get("turbo", false)
		intent["dive"] = "dive" in input.get("buttons", []) or intent.get("dive", false)
		intent["jump"] = "jump" in input.get("buttons", [])
	if control_assist_ticks > 0:
		control_assist_ticks -= 1
	if not offense_home and not return_play:
		var cpu = _cpu_offense_input()
		if carrier >= 0:
			intents[carrier] = cpu
		_handle_qb_buttons(cpu.get("buttons", []))
	elif offense_home and not return_play and not kickoff_return:
		_handle_qb_buttons(input.get("buttons", []))
	_update_exertion()
	_step_players(intents)
	if not user_has_ball() and controlled >= 0 and players[controlled]["dive_ticks"] > 0:
		_set_controlled(_nearest_home(ball_position()), true)
	_step_ball()
	if phase != "live":
		return
	if loose_ticks > 0:
		_resolve_loose_ball()
	else:
		_resolve_carrier()


func _update_exertion() -> void:
	var slots: Dictionary = offense_play()["slots"]
	for p in players:
		var lane = _position_lane(p["position"])
		var key = not lane.is_empty() and slots[lane]["role"] == "target"
		if p["position"] == "qb" and offense_play()["kind"] == "keeper":
			key = true
		p["exerting"] = not p["offense"] or p["id"] == controlled or key or (ball_state == "held" and p["id"] == carrier and
			(runner_phase or p["position"] != "qb"))


func _handle_qb_buttons(buttons: Array) -> void:
	var actions = _qb_actions()
	if actions.is_empty():
		return
	for lane in ["left", "center", "right"]:
		var action = "pass_" + lane
		if action in buttons and action in actions:
			_pass(lane)
			return
	if "handoff" not in buttons:
		return
	var rb = _player_index("rb")
	var qb: Dictionary = players[carrier]
	if "handoff" in actions and qb["pos"].distance_to(players[rb]["pos"]) <= 2.2:
		carrier = rb
		_control_ball()
		runner_phase = true
	elif "toss" in actions:
		var target: Vector2 = players[rb]["pos"] + players[rb]["vel"] * 0.25
		if target.y <= qb["pos"].y:
			_throw(target, rb, 14.0, 0.35)
			toss_target = rb
			_control_flight(rb)


func _pass(lane: String) -> void:
	var receiver = _player_index(LANE_POSITIONS[lane])
	if receiver < 0:
		return
	var qb: Dictionary = players[carrier]
	var r: Dictionary = players[receiver]
	var arm: Dictionary = curves.get("qbArm", {"min": 18.0, "max": 26.0})
	var speed = lerpf(float(arm["min"]), float(arm["max"]), _rating(qb["ratings"], "power"))
	var aim: Vector2 = r["pos"]
	for unused in 2:
		var travel = qb["pos"].distance_to(aim) / speed
		aim = r["pos"] + r["vel"] * travel
	var pressured = false
	for defender in players:
		if not defender["offense"] and not defender["down"] and defender["pos"].distance_to(qb["pos"]) < 2.5:
			pressured = true
			break
	var accuracy = _ability(qb)
	var spread = (1.0 - accuracy) * (0.6 + qb["pos"].distance_to(aim) * 0.06)
	if pressured:
		spread += 1.5
	aim += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spread
	aim.x = clampf(aim.x, -HALF_WIDTH + 0.5, HALF_WIDTH - 0.5)
	aim.y = clampf(aim.y, 0.5, 119.5)
	var distance = qb["pos"].distance_to(aim)
	_throw(aim, receiver, speed, 0.6 + distance * 0.07)
	if pressured:
		flight["wobble"] = 0.35
	thrown = true
	_control_flight(receiver)


func _throw(target: Vector2, receiver: int, speed: float, peak: float) -> void:
	var origin = ball_position()
	flight = {
		"from": origin, "to": target, "target": receiver, "elapsed": 0.0,
		"duration": maxf(0.2, origin.distance_to(target) / speed), "peak": peak, "wobble": 0.0,
	}
	ball_state = "flight"
	carrier = -1


func _step_ball() -> void:
	if ball_state != "flight":
		return
	flight["elapsed"] += DT
	if kickoff_return:
		if flight["elapsed"] >= flight["duration"]:
			carrier = flight["target"]
			ball_state = "held"
			caught = true
			_control_ball()
			message = "CAUGHT! KICKOFF RETURN!"
		return
	if toss_target < 0 and ball_height() <= 3.2:
		for p in players:
			if not p["offense"] and not p["down"] and p["jump_ticks"] > 0 and p["pos"].distance_to(ball_position()) < 1.5:
				_end_play("incomplete", ball_position(), "JUMP BLOCK!")
				return
	if flight["elapsed"] < flight["duration"]:
		return
	ball_spot = flight["to"]
	ball_state = "loose"
	var target: int = flight["target"]
	if toss_target >= 0:
		if target == toss_target and not players[target]["down"] and players[target]["pos"].distance_to(ball_spot) <= 1.2:
			ball_state = "held"
			carrier = target
			_control_ball()
			runner_phase = true
			message = ""
		else:
			loose_ticks = 90
			message = "LOOSE BALL!"
		toss_target = -1
		return
	_resolve_catch(ball_spot, target)


func _resolve_catch(spot: Vector2, target: int) -> void:
	var nearest = -1
	var nearest_distance = INF
	for p in players:
		if p["offense"] or p["down"]:
			continue
		var distance = p["pos"].distance_to(spot)
		if (p["dive_ticks"] > 0 or p["jump_ticks"] > 0) and distance <= 1.5:
			_end_play("incomplete", spot, "SWATTED!")
			return
		if distance < nearest_distance:
			nearest = p["id"]
			nearest_distance = distance
	var receiver_distance = players[target]["pos"].distance_to(spot) if target >= 0 else INF
	if nearest >= 0 and nearest_distance < 1.2 and nearest_distance < receiver_distance:
		if rng.randf() < 0.12 + 0.3 * _ability(players[nearest]):
			carrier = nearest
			ball_state = "held"
			_start_return("interception", nearest)
		else:
			_end_play("incomplete", spot, "BROKEN UP!")
		return
	if target >= 0 and not players[target]["down"]:
		var receiver: Dictionary = players[target]
		var ability = _ability(receiver)
		var reach = 1.2 + 0.9 * ability + (0.6 if receiver["dive_ticks"] > 0 else 0.0)
		if receiver_distance < reach:
			var chance = clampf(float(curves.get("catchBaseChance", 0.70)) + 0.38 * ability
				- (float(curves.get("contestedCatchPenalty", 0.42)) if nearest_distance < 2.2 else 0.0)
				- receiver_distance * float(curves.get("catchDistancePenaltyPerYard", 0.08)), 0.25, 0.98)
			if rng.randf() < chance:
				carrier = target
				ball_state = "held"
				_control_ball()
				runner_phase = true
				caught = true
				message = "CATCH!"
				return
			_end_play("incomplete", spot, "DROPPED!")
			return
	_end_play("incomplete", spot)


func _resolve_carrier() -> void:
	if ball_state != "held" or carrier < 0:
		return
	var c: Dictionary = players[carrier]
	var spot: Vector2 = c["pos"]
	if (not return_play and spot.y >= GOAL_LINE) or (return_play and spot.y <= OWN_GOAL):
		_end_play("touchdown", spot)
		return
	if absf(spot.x) > HALF_WIDTH:
		_end_play("out_of_bounds", spot)
		return
	if (not return_play and spot.y <= OWN_GOAL) or (return_play and spot.y >= GOAL_LINE):
		_end_play("safety", spot)
		return
	if spot.y > los:
		runner_phase = true
	if phase_ticks > 30 and message == "CATCH!":
		message = ""
	for defender in players:
		if defender["offense"] == c["offense"] or defender["down"] or defender["recover"] > 0:
			continue
		var diving: bool = defender["dive_ticks"] > 0
		var reach = 1.5 if diving else 0.95
		if defender["pos"].distance_to(spot) >= reach:
			continue
		var edge = float(defender["ratings"]["power"] - c["ratings"]["power"]) / 98.0
		var chance = clampf(0.72 + 0.35 * edge - 0.25 * _rating(c["ratings"], "speed") * c["health"]
			+ (0.1 if diving else 0.0), 0.35, 0.95)
		if rng.randf() < chance:
			if diving and edge >= 0.35 and rng.randf() < float(curves.get("bigHitFumbleChance", 0.02)):
				ball_state = "loose"
				ball_spot = spot
				c["down"] = true
				c["recover"] = 45
				carrier = -1
				_set_controlled(_nearest_home(spot))
				loose_ticks = 90
				message = "FUMBLE!"
				return
			var sack = c["position"] == "qb" and spot.y < los and not caught and not runner_phase
			_end_play("sack" if sack else "tackled", spot)
			return
		defender["recover"] = 40
		defender["vel"] *= 0.2
		c["vel"] *= 0.6
		message = "BROKEN TACKLE!"


func _resolve_loose_ball() -> void:
	var nearest = -1
	var distance = 1.2
	for p in players:
		if p["down"]:
			continue
		var d = p["pos"].distance_to(ball_spot)
		if d <= distance and (nearest < 0 or d < distance):
			nearest = p["id"]
			distance = d
	if nearest >= 0:
		ball_state = "held"
		carrier = nearest
		if players[nearest]["offense"] != (not return_play):
			_start_return("fumble", nearest)
		else:
			_control_ball()
			runner_phase = true
			message = "RECOVERED!"
		loose_ticks = 0
		return
	loose_ticks -= 1
	if loose_ticks == 0:
		_end_play("fumble", ball_spot)


func _rest_players() -> void:
	for p in players:
		var endurance = _rating(p["ratings"], "endurance")
		p["health"] = minf(1.0, p["health"] + _curve("regenMin", "regenMax", endurance) * DT)
		p["vel"] = Vector2.ZERO
	tick_count += 1


func _step_players(intents: Array) -> void:
	for p in players:
		var intent: Dictionary = intents[p["id"]]
		if p["jump_ticks"] > 0:
			p["jump_ticks"] -= 1
		if intent.get("jump", false) and p["jump_ticks"] == 0 and not p["down"] and p["recover"] == 0:
			p["jump_ticks"] = 24
		if p["down"]:
			p["vel"] = Vector2.ZERO
			if p["recover"] > 0:
				p["recover"] -= 1
				if p["recover"] == 0:
					p["down"] = false
			_step_health(p, p["exerting"], false, false)
			continue
		if p["dive_ticks"] > 0:
			_step_health(p, p["exerting"], false, false)
			p["vel"] *= 0.965
			p["pos"] += p["vel"] * DT
			p["dive_ticks"] -= 1
			if p["dive_ticks"] == 0:
				p["down"] = true
				p["vel"] = Vector2.ZERO
				if p["id"] == carrier and ball_state == "held":
					_end_play("dive", p["pos"])
				else:
					p["recover"] = 45
			continue
		if intent.get("dive", false) and p["recover"] == 0:
			var direction = Vector2(sin(p["facing"]), cos(p["facing"]))
			var speed = maxf(p["vel"].length(), 4.0) * lerpf(0.8, 1.0, p["health"]) + 1.5 + 2.0 * _ability(p)
			if p["id"] == controlled and not user_has_ball():
				speed *= DEFENSIVE_DIVE_BONUS
			p["vel"] = direction * speed
			p["dive_ticks"] = 16 + int(10.0 * _ability(p))
			continue
		var recovering: bool = p["recover"] > 0
		if recovering:
			p["recover"] -= 1
		if p["engaged"] > 0:
			p["engaged"] -= 1
		var desired: Vector2 = intent.get("move", Vector2.ZERO).limit_length(1.0)
		var before: Vector2 = p["vel"].normalized()
		var cutting = before != Vector2.ZERO and desired != Vector2.ZERO and before.dot(desired) < 0.5
		var steered = desired
		if p["vel"].length() > 0.3 and desired != Vector2.ZERO:
			var heading = atan2(before.x, before.y)
			var wanted = atan2(desired.x, desired.y)
			var difference = wrapf(wanted - heading, -PI, PI)
			var turn_rate = _curve("turnRateMin", "turnRateMax", _rating(p["ratings"], "speed"))
			var angle = heading + clampf(difference, -turn_rate * DT, turn_rate * DT)
			steered = Vector2(sin(angle), cos(angle)) * desired.length()
		var carrying = ball_state == "held" and p["id"] == carrier
		p["turbo_active"] = intent.get("turbo", false) and p["turbo"] > 0 and not recovering
		_step_health(p, p["exerting"] or p["turbo_active"], carrying, cutting and p["vel"].length() > 2)
		if p["turbo_active"]:
			p["turbo"] = maxf(0.0, p["turbo"] - DT)
			p["cooldown"] = curves["turboRechargeDelay"]
		elif p["cooldown"] > 0.0:
			p["cooldown"] -= DT
		else:
			p["turbo"] = minf(p["capacity"], p["turbo"] + float(curves["turboRechargePerSecond"]) * DT)
		var speed_rating = _rating(p["ratings"], "speed")
		var vmax = _curve("topSpeedMin", "topSpeedMax", speed_rating) * \
			lerpf(float(curves["exhaustedSpeedFactor"]), 1.0, p["health"])
		if p["turbo_active"]:
			vmax *= curves["turboSpeedMultiplier"]
			if p["id"] == controlled and not user_has_ball():
				vmax *= DEFENSIVE_TURBO_BONUS
		if p["engaged"] > 0:
			vmax *= 0.7 if carrying else 0.45
		if recovering:
			vmax *= 0.35
		var acceleration = _curve("accelMin", "accelMax", speed_rating) * lerpf(0.75, 1.0, p["health"]) * DT
		var change: Vector2 = steered * vmax - p["vel"]
		p["vel"] += change.limit_length(acceleration)
		p["pos"] += p["vel"] * DT
		if p["vel"].length() > 0.3:
			p["facing"] = atan2(p["vel"].x, p["vel"].y)
	_resolve_collisions()
	tick_count += 1


func _step_health(p: Dictionary, exerting: bool, carrying: bool, cutting: bool) -> void:
	var endurance = _rating(p["ratings"], "endurance")
	if exerting:
		var drain = _curve("playDrainMin", "playDrainMax", endurance)
		if carrying:
			drain += _curve("carryDrainMin", "carryDrainMax", endurance)
		if cutting:
			drain *= float(curves["cutDrainMultiplier"])
		if p["turbo_active"]:
			drain *= float(curves["turboDrainMultiplier"])
		p["health"] = maxf(0.0, p["health"] - drain * DT)
	else:
		p["health"] = minf(1.0, p["health"] + _curve("regenMin", "regenMax", endurance) * DT)


func _resolve_collisions() -> void:
	var reported = {}
	# ponytail: fixed cap for 18-player corner piles; profile before increasing roster size.
	for iteration in 128:
		var largest = 0.0
		for a in players.size():
			var pa: Dictionary = players[a]
			for b in range(a + 1, players.size()):
				var pb: Dictionary = players[b]
				if pa["down"] and pb["down"]:
					continue
				var delta: Vector2 = pb["pos"] - pa["pos"]
				var distance = delta.length()
				if distance >= RADIUS * 2.0:
					continue
				var overlap = RADIUS * 2.0 - distance
				largest = maxf(largest, overlap)
				if pa["offense"] != pb["offense"] and not reported.has(a * 100 + b):
					reported[a * 100 + b] = true
					pa["engaged"] = 8
					pb["engaged"] = 8
				var normal = delta / distance if distance > 0.0001 else Vector2.from_angle(float((a * 7 + b * 13) % 24) * PI / 12.0)
				if pa["down"] != pb["down"]:
					var fixed: Vector2 = pa["pos"] if pa["down"] else pb["pos"]
					var free: Vector2 = pb["pos"] if pa["down"] else pa["pos"]
					var away: Vector2 = normal if pa["down"] else -normal
					var bounds = Rect2(Vector2(-HALF_WIDTH - 1.5 + RADIUS, RADIUS),
						Vector2(HALF_WIDTH * 2.0 + 3.0 - RADIUS * 2.0, 120.0 - RADIUS * 2.0))
					var pushed = free + away * overlap
					var obstructed = false
					for c in players.size():
						if c == a or c == b or not players[c]["down"]:
							continue
						if pushed.distance_to(players[c]["pos"]) < RADIUS * 2.0 - 0.005:
							obstructed = true
							break
					if distance <= 0.0001 or not bounds.has_point(pushed) or obstructed:
						# ponytail: choose unobstructed escape for pinned contacts; widen to full continuous solver if rosters expand.
						var best = Vector2.INF
						var best_overlap = INF
						for axis in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
							var candidate: Vector2 = fixed + axis * (RADIUS * 2.0 + 0.0001)
							if not bounds.has_point(candidate):
								continue
							var worst = 0.0
							for c in players.size():
								if c == (b if pa["down"] else a):
									continue
								worst = maxf(worst, RADIUS * 2.0 - candidate.distance_to(players[c]["pos"]))
							if worst < best_overlap:
								best_overlap = worst
								best = candidate
						if best != Vector2.INF:
							(pb if pa["down"] else pa)["pos"] = best
							continue
				var power_a = float(pa["ratings"]["power"])
				var power_b = float(pb["ratings"]["power"])
				var weight = power_b / (power_a + power_b)
				if pa["down"]:
					weight = 0.0
				elif pb["down"]:
					weight = 1.0
				elif pa["dive_ticks"] > 0 and pb["dive_ticks"] == 0:
					weight = 0.0
				elif pb["dive_ticks"] > 0 and pa["dive_ticks"] == 0:
					weight = 1.0
				pa["pos"] -= normal * overlap * weight
				pb["pos"] += normal * overlap * (1.0 - weight)
		for p in players:
			var old: Vector2 = p["pos"]
			var clamped = Vector2(clampf(old.x, -HALF_WIDTH - 1.5 + RADIUS, HALF_WIDTH + 1.5 - RADIUS),
				clampf(old.y, RADIUS, 120.0 - RADIUS))
			if clamped.x != old.x:
				p["vel"].x = 0
			if clamped.y != old.y:
				p["vel"].y = 0
			p["pos"] = clamped
		if largest < 0.00001:
			break


func _position_lane(position: String) -> String:
	for lane in LANES:
		if LANE_POSITIONS[lane] == position:
			return lane
	return ""


func _lane_x(lane: String) -> float:
	if lane == "left":
		return -53.333 / 3.0
	if lane == "right":
		return 53.333 / 3.0
	return 0.0


func route_waypoints(lane: String, route: String) -> Array:
	var x = 7.0 if lane == "center" else _lane_x(lane)
	match route:
		"deep": return [Vector2(x, 32)]
		"mid": return [Vector2(x, 10), Vector2(x * 0.45, 15)]
		"short": return [Vector2(x, 5.5)]
		"flat": return [Vector2(14 if lane == "backfield" else x * 1.2, 1.5)]
		"screen": return [Vector2(x * 0.8, -2.5)]
	return []


func _go(p: Dictionary, target: Vector2, arrive: float = 1.0, turbo: bool = false, scale: float = 1.0) -> Dictionary:
	var delta: Vector2 = target - p["pos"]
	var distance = delta.length()
	var amount = clampf((distance - 0.25) / maxf(arrive, 0.01), 0.0, 1.0)
	return {"move": delta.normalized() * amount * scale, "turbo": turbo}


func _pursue(p: Dictionary, target: Dictionary) -> Dictionary:
	var distance: float = p["pos"].distance_to(target["pos"])
	var aim: Vector2 = target["pos"] + target["vel"] * clampf(distance / 8.0, 0.0, 1.0)
	var intent = _go(p, aim, 0.2, distance < 7.0)
	var away: Vector2 = (target["pos"] - p["pos"]).normalized()
	var fleeing = target["vel"].normalized().dot(away) > 0.5 and target["vel"].length() > 3.0
	if distance > 1.1 and distance < 2.1 and fleeing and p["recover"] == 0:
		intent["dive"] = true
	return intent


func _ai_intents() -> Array:
	var intents = []
	intents.resize(players.size())
	var has_carrier = ball_state == "held" and carrier >= 0
	var carrier_player: Dictionary = players[carrier] if has_carrier else {}
	for p in players:
		var intent = {}
		if (p["id"] != controlled or control_assist_ticks > 0) and not p["down"] and p["dive_ticks"] == 0:
			if (return_play or kickoff_return) and not carrier_player.is_empty():
				if p["id"] == carrier:
					intent = _cpu_runner(p)
				elif p["offense"] != carrier_player["offense"]:
					intent = _pursue(p, carrier_player)
				else:
					intent = _return_block(p, carrier_player)
			elif p["offense"]:
				intent = _offense_intent(p, carrier_player)
			else:
				intent = _defense_intent(p, carrier_player)
		intents[p["id"]] = intent
	return intents


func _return_block(p: Dictionary, ball_carrier: Dictionary) -> Dictionary:
	var nearest = -1
	var distance = INF
	for opponent in players:
		if opponent["offense"] == p["offense"] or opponent["down"]:
			continue
		var score: float = opponent["pos"].distance_to(p["pos"]) + opponent["pos"].distance_to(ball_carrier["pos"])
		if score < distance:
			distance = score
			nearest = opponent["id"]
	return _go(p, players[nearest]["pos"], 0.4) if nearest >= 0 else {}


func _offense_intent(p: Dictionary, ball_carrier: Dictionary) -> Dictionary:
	if ball_state == "flight" and flight["target"] == p["id"]:
		return _go(p, flight["to"], 0.5)
	if not ball_carrier.is_empty() and p["id"] == ball_carrier["id"]:
		return {}
	var lane = _position_lane(p["position"])
	if not lane.is_empty() and not runner_phase:
		var slot: Dictionary = offense_play()["slots"][lane]
		if slot["role"] == "target":
			if lane == "backfield" and slot["route"] in ["handoff", "toss"]:
				return _go(p, Vector2(-3 if slot["route"] == "toss" else 0, los - 6.5), 1.0)
			var waypoints = route_waypoints(lane, slot["route"])
			if not waypoints.is_empty():
				var point: Vector2 = waypoints[-1]
				if waypoints.size() > 1 and not route_breaks.has(p["id"]):
					var stem: Vector2 = waypoints[0] + Vector2(0, los)
					if p["pos"].distance_to(stem) < 1.0 or (
							absf(p["pos"].x - stem.x) <= 2.0 and p["pos"].y >= stem.y
					) or (phase_ticks >= 84 and p["pos"].distance_to(stem) < 3.0):
						route_breaks[p["id"]] = true
					else:
						return _go(p, stem, 1.5)
				return _go(p, point + Vector2(0, los), 1.5)
		elif slot["role"] == "lead":
			return _go(p, Vector2(_lane_x(lane) * 0.3, los + 1.5), 1.0)
	if p["position"] == "qb" or ball_carrier.is_empty():
		return {}
	var threat = {}
	var best = INF
	for defender in players:
		if defender["offense"] or defender["down"]:
			continue
		var to_me: float = defender["pos"].distance_to(p["pos"])
		if to_me >= 9.0:
			continue
		var score: float = defender["pos"].distance_to(ball_carrier["pos"]) + to_me * 0.8
		if score < best:
			best = score
			threat = defender
	if threat.is_empty():
		return _go(p, ball_carrier["pos"] + Vector2(0, 4), 2.0)
	var spot: Vector2 = threat["pos"] + (ball_carrier["pos"] - threat["pos"]).normalized() * 0.7
	return _go(p, spot, 0.4)


func _defense_intent(p: Dictionary, ball_carrier: Dictionary) -> Dictionary:
	if ball_state == "flight":
		if p["pos"].distance_to(flight["to"]) < 12.0:
			return _go(p, flight["to"], 0.3, true)
		if flight["target"] >= 0:
			return _pursue(p, players[flight["target"]])
	if ball_carrier.is_empty():
		return {}
	var qb_has_ball = ball_carrier["position"] == "qb" and ball_carrier["pos"].y < los + 0.5
	if runner_phase or not qb_has_ball:
		return _pursue(p, ball_carrier)
	var assignment: String = defense_play()["assignments"].get(p["position"], "rush")
	var parts = assignment.split(":")
	match parts[0]:
		"rush": return _pursue(p, ball_carrier)
		"spy": return _go(p, Vector2(ball_carrier["pos"].x, los + 4.5), 1.0)
		"runFill": return _pursue(p, players[_player_index("rb")])
		"man":
			var lane: String = parts[1]
			var receiver = _player_index(LANE_POSITIONS[lane])
			if receiver >= 0 and offense_play()["slots"][lane]["role"] == "target":
				var r: Dictionary = players[receiver]
				return _go(p, r["pos"] + r["vel"] * 0.25 + Vector2(0, 1.2), 0.5)
			return _zone(p, lane, 7.0)
		"zone": return _zone(p, parts[1], 7.0)
		"deepZone": return _zone(p, parts[1], 16.0)
	return {}


func _zone(p: Dictionary, lane: String, depth: float) -> Dictionary:
	var home_point = Vector2(_lane_x(lane), los + depth)
	var threat = {}
	for r in players:
		if not r["offense"] or _position_lane(r["position"]).is_empty():
			continue
		var in_lane = absf(r["pos"].x - _lane_x(lane)) < (53.333 / 3.0) * 0.6
		var in_depth = r["pos"].y > los and absf(r["pos"].y - home_point.y) < 9.0
		if in_lane and in_depth and (threat.is_empty() or r["pos"].y > threat["pos"].y):
			threat = r
	if not threat.is_empty():
		return _go(p, threat["pos"] + Vector2(0, 1.5), 1.0, false, 0.9)
	return _go(p, home_point, 1.5, false, 0.85)


func receiver_openness(index: int) -> float:
	var receiver: Dictionary = players[index]
	var lead: Vector2 = receiver["pos"] + receiver["vel"] * 0.4
	var origin: Vector2 = flight["from"] if ball_state == "flight" else ball_position()
	var route = lead - origin
	var length_squared = route.length_squared()
	var best = 6.0
	var threats = 0
	for defender in players:
		if defender["offense"] or defender["down"]:
			continue
		best = minf(best, defender["pos"].distance_to(lead))
		if length_squared > 1.0:
			var projection: float = (defender["pos"] - origin).dot(route) / length_squared
			if projection >= 0.5 and projection <= 1.0:
				var clearance: float = defender["pos"].distance_to(origin + route * projection)
				best = minf(best, clearance * 2.0 + 0.5)
				if clearance < 2.5:
					threats += 1
	return maxf(0.0, best - maxf(0.0, float(threats - 1)) * 0.5)


func _end_play(outcome: String, spot: Vector2, text: String = "") -> void:
	if phase != "live":
		return
	var scoring_home = user_has_ball()
	var was_return = return_play
	var was_kickoff = kickoff_return
	if not was_return and not was_kickoff and not scrimmage_recorded:
		_record_series_play(outcome, spot)
	last_outcome = outcome
	last_spot = spot
	phase = "dead"
	phase_ticks = 0
	loose_ticks = 0
	toss_target = -1
	if carrier >= 0 and ball_state == "held":
		players[carrier]["down"] = outcome not in ["touchdown", "out_of_bounds"]
	ball_state = "dead"
	ball_spot = spot
	carrier = -1
	for p in players:
		p["exerting"] = false
	var gain = int(round(spot.y - los))
	var yards = ("%+d YDS" % gain)
	match outcome:
		"touchdown":
			_add_points(scoring_home, 7)
			message = "TOUCHDOWN!"
			_finish_series("TOUCHDOWN", 7)
			_prepare_kickoff(not scoring_home, false)
		"safety":
			_add_points(not scoring_home, 2)
			message = "SAFETY!"
			_finish_series("SAFETY", 0)
			_prepare_kickoff(not scoring_home, false)
		"interception":
			message = "INTERCEPTED - TOUCHBACK" if text == "TOUCHBACK" else "INTERCEPTED!"
			_switch_possession(not offense_home, 120.0 - spot.y)
		"fumble":
			message = "FUMBLE!"
			_switch_possession(not scoring_home, 120.0 - spot.y if not was_return else spot.y)
		"incomplete":
			message = text if not text.is_empty() else "INCOMPLETE"
			_advance_down(los)
		_:
			var label = "TACKLED"
			if outcome == "sack": label = "SACKED"
			if outcome == "out_of_bounds": label = "OUT OF BOUNDS"
			if outcome == "dive": label = "DIVE!"
			message = label + "  " + yards
			if was_return:
				_switch_possession(scoring_home, 120.0 - spot.y)
			elif was_kickoff:
				next_los = clampf(round(spot.y), 11, 109)
				next_down = 1
				next_first_down = minf(next_los + 10.0, GOAL_LINE)
			else:
				_advance_down(clampf(round(spot.y), 11, 109))
	return_play = false
	kickoff_return = false
	_advance_quarter()


func _record_series_play(outcome: String, spot: Vector2) -> void:
	scrimmage_recorded = true
	var before = _stats().duplicate()
	_record_play(outcome, spot)
	series_plays += 1
	for key in series_stats:
		if key == "longest":
			series_stats[key] = maxi(series_stats[key], int(round(spot.y - los)))
		elif key != "seconds":
			series_stats[key] += _stats()[key] - before[key]


func _record_play(outcome: String, spot: Vector2) -> void:
	var stats = _stats()
	var gain = int(round((GOAL_LINE if outcome == "touchdown" else spot.y) - los))
	if outcome == "interception":
		stats["pass_attempts"] += 1
		stats["interceptions"] += 1
		stats["turnovers"] += 1
	elif outcome == "incomplete":
		stats["pass_attempts"] += 1
	elif outcome == "sack" or (outcome == "safety" and not caught and not runner_phase):
		stats["sacks"] += 1
		stats["sack_yards"] += maxi(0, -gain)
	else:
		if caught:
			stats["pass_attempts"] += 1
			stats["completions"] += 1
			stats["pass_yards"] += gain
			if outcome == "touchdown":
				stats["pass_tds"] += 1
		else:
			stats["rush_attempts"] += 1
			stats["rush_yards"] += gain
			if outcome == "touchdown":
				stats["rush_tds"] += 1
		if outcome == "fumble":
			stats["turnovers"] += 1
		stats["longest"] = maxi(stats["longest"], gain)


func _advance_down(spot: float) -> void:
	if spot >= first_down:
		_stats()["first_downs"] += 1
		series_stats["first_downs"] += 1
		next_los = spot
		next_down = 1
		next_first_down = minf(spot + 10.0, GOAL_LINE)
		message += "  FIRST DOWN!"
	elif down >= 4:
		message += "  TURNOVER ON DOWNS"
		_stats()["turnovers"] += 1
		_switch_possession(not offense_home, 120.0 - spot)
	else:
		next_los = spot
		next_down = down + 1
		next_first_down = first_down


func _restart_drive() -> void:
	next_los = KICKOFF
	next_down = 1
	next_first_down = KICKOFF + 10.0


func _advance_quarter() -> void:
	if clock > 0.0:
		return
	if quarter < 4:
		if quarter == 2:
			halftime_due = true
		quarter += 1
		clock = 180.0
	else:
		message += "  -  FINAL"


func _add_points(for_home: bool, points: int) -> void:
	if for_home:
		home_score += points
	else:
		away_score += points


func _set_offense(for_home: bool) -> void:
	next_offense_home = for_home
	if offense_home == for_home:
		return
	for p in players:
		var key = ("home:" if p["offense"] == offense_home else "away:") + p["position"]
		benched_health[key] = {"health": p["health"], "tick": tick_count}
	offense_home = for_home
	# Field coordinates always point upfield for the team taking the next snap.
	for p in players:
		var team = home if p["offense"] == offense_home else away
		var profile: Dictionary = team["roster"][p["position"]]
		p["ratings"] = profile["ratings"].duplicate()
		p["number"] = profile["number"]
		p["name"] = profile["name"]
		p["capacity"] = _curve("turboCapacityMin", "turboCapacityMax", _rating(p["ratings"], "endurance"))
		var key = ("home:" if p["offense"] == offense_home else "away:") + p["position"]
		p["health"] = 1.0
		if benched_health.has(key):
			var state: Dictionary = benched_health[key]
			var regen = _curve("regenMin", "regenMax", _rating(p["ratings"], "endurance"))
			p["health"] = minf(1.0, state["health"] + float(tick_count - state["tick"]) * DT * regen)


func _new_series() -> void:
	series_stats = _empty_stats()
	series_plays = 0
	series_home = offense_home


func _switch_possession(for_home: bool, spot: float) -> void:
	next_offense_home = for_home
	next_los = clampf(round(spot), 20.0 if spot <= OWN_GOAL else 11.0, 109.0)
	next_down = 1
	next_first_down = minf(next_los + 10.0, GOAL_LINE)
	_new_series()
	series_home = for_home


func _finish_series(ending: String, points: int) -> void:
	series_recap = {
		"team": (home if series_home else away)["abbr"], "ending": ending,
		"plays": series_plays, "yards": series_stats["pass_yards"] + series_stats["rush_yards"] - series_stats["sack_yards"],
		"points": points, "stats": series_stats.duplicate(),
	}


func _prepare_kickoff(receive_home: bool, ready: bool = true) -> void:
	kickoff_home = receive_home
	if ready:
		phase = "kickoff_ready"
		phase_ticks = 0
		message = "KICKOFF"


func _start_kickoff() -> void:
	_set_offense(kickoff_home)
	series_recap.clear()
	_new_series()
	next_los = OWN_GOAL + 10.0
	next_down = 1
	next_first_down = next_los + 10.0
	_reset_formation()
	phase = "live"
	kickoff_return = true
	runner_phase = true
	thrown = false
	caught = false
	loose_ticks = 0
	var receiver = _player_index("rb")
	for p in players:
		if p["id"] == receiver:
			p["pos"] = Vector2(0, OWN_GOAL + 10.0)
		elif p["offense"]:
			p["pos"] = Vector2(float(p["id"] - 4) * 5.0, 27.0 + float(p["id"] % 2) * 4.0)
		else:
			p["pos"] = Vector2(float(p["id"] - 13) * 5.0, 48.0 + float(p["id"] % 2) * 5.0)
	carrier = -1
	ball_state = "flight"
	flight = {
		"from": Vector2(0, 65), "to": players[receiver]["pos"], "target": receiver,
		"elapsed": 0.0, "duration": 1.5, "peak": 6.0, "wobble": 0.0,
	}
	controlled = receiver if offense_home else -1
	control_assist_ticks = 0
	message = "KICK INCOMING!"


func _nearest_home(spot: Vector2) -> int:
	var nearest = -1
	var distance = INF
	for p in players:
		if p["offense"] != offense_home or p["down"] or p["dive_ticks"] > 0:
			continue
		var d: float = p["pos"].distance_squared_to(spot)
		if d < distance:
			distance = d
			nearest = p["id"]
	return nearest


func _control_ball() -> void:
	_set_controlled(carrier if user_has_ball() else _nearest_home(ball_position()))


func _control_flight(target: int) -> void:
	_set_controlled(-1 if offense_home else _nearest_home(players[target]["pos"] + players[target]["vel"] * flight["duration"]))


func _update_defensive_control() -> void:
	if user_has_ball() or control_assist_ticks > 0:
		return
	if runner_phase or return_play or kickoff_return or ball_state in ["flight", "loose"]:
		_set_controlled(_nearest_home(ball_position()))


func _set_controlled(index: int, immediate: bool = false) -> void:
	if user_has_ball():
		control_assist_ticks = 0
	elif index != controlled:
		if control_assist_ticks > 0 and not immediate:
			return
		control_assist_ticks = 60 if index >= 0 else 0
	controlled = index


func _start_return(outcome: String, holder: int) -> void:
	if outcome == "interception" and players[holder]["pos"].y >= GOAL_LINE:
		_end_play("interception", players[holder]["pos"], "TOUCHBACK")
		return
	if not return_play and not kickoff_return and not scrimmage_recorded:
		_record_series_play(outcome, players[holder]["pos"])
	var switching_to_home = players[holder]["offense"] == offense_home
	if switching_to_home != series_home:
		series_home = switching_to_home
		series_stats = _empty_stats()
		series_plays = 0
	return_play = not players[holder]["offense"]
	kickoff_return = false
	carrier = holder
	ball_state = "held"
	runner_phase = true
	_control_ball()
	message = "INTERCEPTED! RETURN!" if outcome == "interception" else "FUMBLE RECOVERED! RETURN!"


func kicking_actions() -> Array:
	if phase != "pre_snap" or down != 4:
		return []
	return ["field_goal"] if los >= GOAL_LINE - 40.0 else ["punt"]


func field_goal_distance() -> int:
	return int(round(GOAL_LINE - los)) + 17


func field_goal_chance() -> float:
	return clampf(1.02 - float(field_goal_distance() - 18) * 0.018, 0.05, 0.97)


func _kick(kind: String) -> void:
	if kind not in kicking_actions():
		push_error("Kick is not available in this down and field position: " + kind)
		return
	phase = "dead"
	phase_ticks = 0
	series_plays += 1
	var used = minf(clock, 5.0)
	clock -= used
	_stats()["seconds"] += used
	series_stats["seconds"] += used
	ball_state = "dead"
	carrier = -1
	ball_spot = Vector2(0, los)
	if kind == "field_goal":
		if rng.randf() < field_goal_chance():
			_add_points(offense_home, 3)
			last_outcome = "field_goal"
			message = "%d YD FIELD GOAL GOOD!" % field_goal_distance()
			_finish_series("FIELD GOAL", 3)
			_prepare_kickoff(not offense_home, false)
		else:
			last_outcome = "missed_field_goal"
			message = "%d YD FIELD GOAL NO GOOD" % field_goal_distance()
			_switch_possession(not offense_home, 120.0 - (los - 7.0))
	else:
		last_outcome = "punt"
		var landing = minf(los + 50.0, GOAL_LINE - 10.0)
		message = "PUNT  %d YDS" % int(landing - los)
		_switch_possession(not offense_home, 120.0 - landing)
	last_spot = ball_spot
	_advance_quarter()


func _position_defense() -> void:
	for p in players:
		if p["offense"]:
			continue
		var offset: Vector2 = FORMATION[p["position"]]
		var assignment: String = defense_play()["assignments"].get(p["position"], "rush")
		if assignment == "rush" and p["position"] in ["mlb", "olb", "ss"]:
			offset.y = 2.5
		elif assignment.begins_with("man:"):
			offset.x = FORMATION[LANE_POSITIONS[assignment.get_slice(":", 1)]].x
			offset.y = 3.5
		elif assignment.begins_with("zone:"):
			offset.x = _lane_x(assignment.get_slice(":", 1))
			offset.y = 7.0
		elif assignment.begins_with("deepZone:"):
			offset.x = _lane_x(assignment.get_slice(":", 1))
			offset.y = 16.0
		p["pos"] = Vector2(offset.x, clampf(los + offset.y, RADIUS, 120.0 - RADIUS))


func _start_halftime() -> void:
	halftime = true
	halftime_due = false
	modal_ticks = 0
	message = "HALFTIME"


func _end_game() -> void:
	game_over = true
	phase = "dead"
	phase_ticks = 0
	controlled = -1
	series_recap.clear()
	message = "FINAL"


func start_new_game() -> void:
	home_score = 0
	away_score = 0
	quarter = 1
	clock = 180.0
	game_over = false
	halftime = false
	halftime_due = false
	home_stats = _empty_stats()
	away_stats = _empty_stats()
	last_outcome = ""
	series_recap.clear()
	_set_offense(true)
	benched_health.clear()
	_new_series()
	for p in players:
		p["health"] = 1.0
	message = "SELECT PLAY"
	_restart_drive()
	_reset_formation()
	_prepare_kickoff(true)


func setup_play(line: float, next_play_down: int, first: float) -> void:
	next_los = line
	next_down = next_play_down
	next_first_down = first
	message = ""
	_reset_formation()


func force_whistle() -> void:
	if phase == "live":
		if loose_ticks > 0:
			_end_play("fumble", ball_spot)
		else:
			_end_play("tackled", ball_position())


func _reset_formation() -> void:
	_set_offense(next_offense_home)
	los = next_los
	down = next_down
	first_down = next_first_down
	phase = "pre_snap"
	phase_ticks = 0
	controlled = _player_index("qb" if offense_home else "mlb")
	control_assist_ticks = 0
	runner_phase = false
	return_play = false
	kickoff_return = false
	route_breaks.clear()
	for p in players:
		var offset: Vector2 = FORMATION[p["position"]]
		p["pos"] = Vector2(offset.x, clampf(los + offset.y, RADIUS, 120.0 - RADIUS))
		p["vel"] = Vector2.ZERO
		p["facing"] = 0.0 if p["offense"] else PI
		p["down"] = false
		p["dive_ticks"] = 0
		p["jump_ticks"] = 0
		p["recover"] = 0
		p["engaged"] = 0
		p["exerting"] = false
		p["turbo"] = p["capacity"]
		p["turbo_active"] = false
		p["cooldown"] = 0.0
	ball_state = "dead"
	carrier = -1
	ball_spot = Vector2(0, los)
	_deal()
	_position_defense()
	if message.is_empty() or message == "CATCH!":
		message = "SELECT PLAY"


func cpu_input() -> Dictionary:
	if game_over or halftime or phase == "kickoff_ready":
		return {"buttons": ["snap"]}
	if phase == "pre_snap":
		if chosen < 0:
			if not offense_home:
				return {"select": play_number % 3}
			var best = 0
			var best_score = -INF
			for i in choices.size():
				var play: Dictionary = data["offense"][choices[i]]
				var passing = play["kind"] in ["pass", "playAction", "screen"]
				var score = float((play_number * 7 + choices[i] * 3) % 11) / 11.0
				if first_down - los >= 7 and down >= 2 and passing: score += 0.7
				if first_down - los <= 3 and not passing: score += 0.6
				if GOAL_LINE - los <= 10 and play["kind"] == "run": score += 0.3
				if play["kind"] == "playAction" and down == 1: score += 0.25
				if score > best_score:
					best_score = score
					best = i
			return {"select": best}
		return {"buttons": ["snap"]}
	if phase != "live":
		return {}
	if not user_has_ball() and controlled >= 0:
		if ball_state == "flight":
			var intent = _go(players[controlled], flight["to"], 0.3, true)
			intent["jump"] = players[controlled]["pos"].distance_to(ball_position()) < 1.5
			return intent
		if carrier >= 0:
			return _pursue(players[controlled], players[carrier])
		return {}
	return _cpu_offense_input()


func _cpu_offense_input() -> Dictionary:
	var actions = _qb_actions()
	if not actions.is_empty():
		if offense_play()["kind"] == "keeper":
			return _cpu_runner(players[carrier])
		if ("handoff" in actions or "toss" in actions) and offense_play()["kind"] == "run":
			return {"buttons": ["handoff"]} if phase_ticks >= 5 else {}
		var best_action = ""
		var best_score = -INF
		var best_open = 0.0
		for lane in ["left", "center", "right"]:
			var action = "pass_" + lane
			if action not in actions:
				continue
			var receiver = _player_index(LANE_POSITIONS[lane])
			var openness = receiver_openness(receiver)
			var depth = clampf(players[receiver]["pos"].y - los, -3.0, 25.0)
			var score = minf(openness, 6.0) + depth * 0.12
			if score > best_score:
				best_score = score
				best_action = action
				best_open = openness
		if phase_ticks >= 40 and (best_open >= 2.8 or phase_ticks >= 110):
			if not best_action.is_empty():
				return {"buttons": [best_action]}
			return _cpu_runner(players[carrier])
		return {"move": Vector2(0, -0.6) if players[carrier]["pos"].y > los - 7 else Vector2.ZERO}
	if ball_state == "held" and carrier >= 0:
		return _cpu_runner(players[carrier])
	return {}


func _cpu_runner(p: Dictionary) -> Dictionary:
	var best_direction = Vector2.UP
	var best_score = -INF
	for k in range(-5, 6):
		var angle = float(k) * 0.26
		var direction = Vector2(sin(angle), cos(angle) * (-1.0 if return_play else 1.0))
		var clearance = 8.0
		for defender in players:
			if defender["offense"] == p["offense"] or defender["down"]:
				continue
			var relative: Vector2 = defender["pos"] - p["pos"]
			var along = relative.dot(direction)
			if along <= -1.0 or along >= 10.0:
				continue
			var perpendicular = (relative - direction * along).length()
			clearance = minf(clearance, perpendicular + maxf(0.0, along) * 0.3)
		if absf(p["pos"].x + direction.x * 6.0) > HALF_WIDTH - 1.5:
			clearance -= 4.0
		var score = clearance + cos(angle) * 2.0
		if score > best_score:
			best_score = score
			best_direction = direction
	return {"move": best_direction, "turbo": true}
