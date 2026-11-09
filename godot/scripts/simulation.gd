extends RefCounted

const OpponentDrive = preload("res://godot/scripts/opponent_drive.gd")

const DT = 1.0 / 60.0
const HALF_WIDTH = 53.333 / 2.0
const GOAL_LINE = 110.0
const OWN_GOAL = 10.0
const KICKOFF = 35.0
const RADIUS = 0.42
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
var nested = false
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
var drive_runner = null
var drive_recap: Dictionary = {}
var home_stats = _empty_stats()
var away_stats = _empty_stats()


func _init(game_data: Dictionary = {}, home_team: Dictionary = {}, away_team: Dictionary = {},
		seed_value: int = 1, is_nested: bool = false) -> void:
	if game_data.is_empty():
		return
	data = game_data
	home = home_team
	away = away_team
	curves = data["curves"]
	nested = is_nested
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
			"down": false, "dive_ticks": 0, "recover": 0, "engaged": 0,
		})
	_reset_formation()


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
	if drive_runner != null:
		drive_runner.advance(36)
		if drive_runner.finished:
			_apply_opponent_drive(drive_runner.result)
			drive_runner = null
		return
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
			next_los = KICKOFF
			next_down = 1
			next_first_down = KICKOFF + 10.0
			message = "SELECT PLAY"
			_reset_formation()
		return
	if phase == "pre_snap":
		_rest_players()
		_step_pre_snap(input)
	elif phase == "live":
		_step_live(input)
	else:
		_rest_players()
		if phase_ticks >= 150:
			if quarter == 4 and clock <= 0.0 and drive_recap.is_empty():
				_end_game()
			elif halftime_due and drive_recap.is_empty():
				_start_halftime()
			else:
				_reset_formation()


func _pressed(input: Dictionary) -> bool:
	return not input.get("buttons", []).is_empty() or int(input.get("select", -1)) >= 0


func _step_pre_snap(input: Dictionary) -> void:
	if not drive_recap.is_empty():
		modal_ticks += 1
		phase_ticks = 0
		if modal_ticks >= 1800 or (modal_ticks >= 30 and _pressed(input)):
			drive_recap = {}
			modal_ticks = 0
			message = "SELECT PLAY"
			if quarter == 4 and clock <= 0.0:
				_end_game()
			elif halftime_due:
				_start_halftime()
		return
	var buttons: Array = input.get("buttons", [])
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
	offense_index = choices[index]


func _deal() -> void:
	var pool = range(data["offense"].size())
	choices = []
	while choices.size() < 3 and not pool.is_empty():
		var index = rng.randi_range(0, pool.size() - 1)
		choices.append(pool[index])
		pool.remove_at(index)
	chosen = -1


func _snap() -> void:
	defense_index = rng.randi_range(0, data["defense"].size() - 1)
	carrier = _player_index("qb")
	ball_state = "held"
	controlled = carrier
	phase = "live"
	phase_ticks = 0
	runner_phase = false
	thrown = false
	caught = false
	toss_target = -1
	loose_ticks = 0
	route_breaks.clear()
	drive_recap.clear()
	message = ""
	play_number += 1


func _step_live(input: Dictionary) -> void:
	var used = minf(clock, DT)
	clock -= used
	home_stats["seconds"] += used
	var intents = _ai_intents()
	if loose_ticks > 0:
		for p in players:
			if not p["down"]:
				intents[p["id"]] = {"move": (ball_spot - p["pos"]).normalized()}
	elif controlled >= 0:
		intents[controlled] = {
			"move": input.get("move", Vector2.ZERO),
			"turbo": input.get("turbo", false),
			"dive": "dive" in input.get("buttons", []),
		}
	_handle_qb_buttons(input.get("buttons", []))
	_update_exertion()
	_step_players(intents)
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
		p["exerting"] = key or (ball_state == "held" and p["id"] == carrier and
			(runner_phase or p["position"] != "qb"))


func _handle_qb_buttons(buttons: Array) -> void:
	var actions = available_actions()
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
		controlled = rb
		runner_phase = true
	elif "toss" in actions:
		var target: Vector2 = players[rb]["pos"] + players[rb]["vel"] * 0.25
		if target.y <= qb["pos"].y:
			_throw(target, rb, 14.0, 0.35)
			toss_target = rb
			controlled = -1


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
	controlled = -1


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
	if flight["elapsed"] < flight["duration"]:
		return
	ball_spot = flight["to"]
	ball_state = "loose"
	var target: int = flight["target"]
	if toss_target >= 0:
		if target == toss_target and not players[target]["down"] and players[target]["pos"].distance_to(ball_spot) <= 1.2:
			ball_state = "held"
			carrier = target
			controlled = target
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
		if p["dive_ticks"] > 0 and distance <= 1.5:
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
			_end_play("interception", players[nearest]["pos"])
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
				controlled = target
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
	if spot.y >= GOAL_LINE:
		_end_play("touchdown", spot)
		return
	if absf(spot.x) > HALF_WIDTH:
		_end_play("out_of_bounds", spot)
		return
	if spot.y <= OWN_GOAL:
		_end_play("safety", spot)
		return
	if spot.y > los:
		runner_phase = true
	if phase_ticks > 30 and message == "CATCH!":
		message = ""
	for defender in players:
		if defender["offense"] or defender["down"] or defender["recover"] > 0:
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
				controlled = -1
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
		if players[nearest]["offense"]:
			ball_state = "held"
			carrier = nearest
			controlled = nearest
			runner_phase = true
			message = "RECOVERED!"
		else:
			_end_play("fumble", ball_spot)
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
	for iteration in 32:
		var largest = 0.0
		for a in players.size():
			var pa: Dictionary = players[a]
			if pa["down"]:
				continue
			for b in range(a + 1, players.size()):
				var pb: Dictionary = players[b]
				if pb["down"]:
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
				var power_a = float(pa["ratings"]["power"])
				var power_b = float(pb["ratings"]["power"])
				var weight = power_b / (power_a + power_b)
				if pa["dive_ticks"] > 0 and pb["dive_ticks"] == 0:
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
		if p["id"] != controlled and not p["down"] and p["dive_ticks"] == 0:
			if p["offense"]:
				intent = _offense_intent(p, carrier_player)
			else:
				intent = _defense_intent(p, carrier_player)
		intents[p["id"]] = intent
	return intents


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
	_record_play(outcome, spot)
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
			home_score += 7
			message = "TOUCHDOWN!"
			_restart_drive()
			_begin_opponent_drive("touchdown", KICKOFF)
		"safety":
			away_score += 2
			message = "SAFETY!"
			_restart_drive()
			_begin_opponent_drive("safety", KICKOFF)
		"interception":
			message = "INTERCEPTED!"
			_restart_drive()
			var their_spot = 120.0 - spot.y
			_begin_opponent_drive("interception", 30.0 if their_spot <= OWN_GOAL else clampf(round(their_spot), 11, 109))
		"fumble":
			message = "FUMBLE!"
			_restart_drive()
			_begin_opponent_drive("fumble", clampf(round(120.0 - spot.y), 11, 109))
		"incomplete":
			message = text if not text.is_empty() else "INCOMPLETE"
			_advance_down(los)
		_:
			var label = "TACKLED"
			if outcome == "sack": label = "SACKED"
			if outcome == "out_of_bounds": label = "OUT OF BOUNDS"
			if outcome == "dive": label = "DIVE!"
			message = label + "  " + yards
			_advance_down(clampf(round(spot.y), 11, 109))
	if drive_runner == null:
		_advance_quarter()


func _record_play(outcome: String, spot: Vector2) -> void:
	var gain = int(round((GOAL_LINE if outcome == "touchdown" else spot.y) - los))
	if outcome == "interception":
		home_stats["pass_attempts"] += 1
		home_stats["interceptions"] += 1
		home_stats["turnovers"] += 1
	elif outcome == "incomplete":
		home_stats["pass_attempts"] += 1
	elif outcome == "sack" or (outcome == "safety" and not caught and not runner_phase):
		home_stats["sacks"] += 1
		home_stats["sack_yards"] += maxi(0, -gain)
	else:
		if caught:
			home_stats["pass_attempts"] += 1
			home_stats["completions"] += 1
			home_stats["pass_yards"] += gain
			if outcome == "touchdown":
				home_stats["pass_tds"] += 1
		else:
			home_stats["rush_attempts"] += 1
			home_stats["rush_yards"] += gain
			if outcome == "touchdown":
				home_stats["rush_tds"] += 1
		if outcome == "fumble":
			home_stats["turnovers"] += 1
		home_stats["longest"] = maxi(home_stats["longest"], gain)


func _advance_down(spot: float) -> void:
	if spot >= first_down:
		home_stats["first_downs"] += 1
		next_los = spot
		next_down = 1
		next_first_down = minf(spot + 10.0, GOAL_LINE)
		message += "  FIRST DOWN!"
	elif down >= 4:
		message += "  TURNOVER ON DOWNS"
		home_stats["turnovers"] += 1
		_restart_drive()
		_begin_opponent_drive("downs", 120.0 - spot)
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


func _begin_opponent_drive(trigger: String, start: float) -> void:
	if nested or (quarter == 4 and clock <= 0.0):
		return
	drive_runner = OpponentDrive.new(self, trigger, start)


func _apply_opponent_drive(result: Dictionary) -> void:
	away_score += result["opponent_points"]
	home_score += result["user_points"]
	for key in away_stats:
		if key == "longest":
			away_stats[key] = maxi(away_stats[key], result["stats"][key])
		else:
			away_stats[key] += result["stats"][key]
	if quarter < 3 and result["quarter"] >= 3:
		halftime_due = true
	quarter = result["quarter"]
	clock = result["clock"]
	next_los = result["resume_los"]
	next_down = 1
	next_first_down = minf(next_los + 10.0, GOAL_LINE)
	drive_recap = result
	modal_ticks = 0


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
	drive_recap.clear()
	message = "FINAL"


func start_new_game() -> void:
	home_score = 0
	away_score = 0
	quarter = 1
	clock = 180.0
	game_over = false
	halftime = false
	halftime_due = false
	drive_recap.clear()
	home_stats = _empty_stats()
	away_stats = _empty_stats()
	last_outcome = ""
	for p in players:
		p["health"] = 1.0
	message = "SELECT PLAY"
	_restart_drive()
	_reset_formation()


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
	los = next_los
	down = next_down
	first_down = next_first_down
	phase = "pre_snap"
	phase_ticks = 0
	controlled = _player_index("qb")
	runner_phase = false
	route_breaks.clear()
	for p in players:
		var offset: Vector2 = FORMATION[p["position"]]
		p["pos"] = Vector2(offset.x, clampf(los + offset.y, RADIUS, 120.0 - RADIUS))
		p["vel"] = Vector2.ZERO
		p["facing"] = 0.0 if p["offense"] else PI
		p["down"] = false
		p["dive_ticks"] = 0
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
	if message.is_empty() or message == "CATCH!":
		message = "SELECT PLAY"


func cpu_input() -> Dictionary:
	if game_over or halftime or not drive_recap.is_empty():
		return {"buttons": ["snap"]}
	if phase == "pre_snap":
		if chosen < 0:
			var best = 0
			var best_score = -INF
			for i in choices.size():
				var play: Dictionary = data["offense"][choices[i]]
				var passing = play["kind"] in ["pass", "playAction", "screen"]
				var score = rng.randf()
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
	var actions = available_actions()
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
	if ball_state == "held" and carrier == controlled:
		return _cpu_runner(players[carrier])
	return {}


func _cpu_runner(p: Dictionary) -> Dictionary:
	var best_direction = Vector2.UP
	var best_score = -INF
	for k in range(-5, 6):
		var angle = float(k) * 0.26
		var direction = Vector2(sin(angle), cos(angle))
		var clearance = 8.0
		for defender in players:
			if defender["offense"] or defender["down"]:
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
