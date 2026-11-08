extends Node3D

const FIELD_WIDTH = 53.333
const CROWD_COLORS = [
	Color("2457d6"), Color("d92b35"), Color("f5b82e"), Color("b8c5d5"),
	Color("17223a"), Color("24a9b5"), Color("e77736"), Color("52678d"),
]
const SKIN_COLORS = [
	Color("f2c5a0"), Color("dba47e"), Color("ae7659"), Color("85533e"), Color("59382b"),
]

var camera: Camera3D
var key_light: DirectionalLight3D
var environment: WorldEnvironment
var line_of_scrimmage: MeshInstance3D
var first_down_line: MeshInstance3D
var ball: Node3D
var player_root: Node3D
var player_nodes: Array = []
var confetti: GPUParticles3D
var impact_sparks: GPUParticles3D
var turbo_trail: GPUParticles3D
var event_light: OmniLight3D
var sideline_root: Node3D
var sideline_groups: Array = []
var materials: Dictionary = {}
var focus = Vector2(0, 24)
var game = null
var elapsed = 0.0
var event_light_time = 0.0
var last_effect_play = -1
var shadows_enabled = true


func _ready() -> void:
	_build_environment()
	_build_field()
	_build_stadium()
	_build_ball()
	_build_effects()
	player_root = Node3D.new()
	add_child(player_root)
	sideline_root = Node3D.new()
	add_child(sideline_root)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = rad_to_deg(0.88)
	camera.near = 0.2
	camera.far = 400.0
	add_child(camera)


func set_game(simulation) -> void:
	game = simulation
	focus = Vector2(0, game.los - 11.0)
	last_effect_play = game.play_number
	turbo_trail.emitting = false
	for child in player_root.get_children():
		child.queue_free()
	player_nodes.clear()
	for child in sideline_root.get_children():
		child.queue_free()
	sideline_groups.clear()
	for p in game.players:
		var team: Dictionary = game.home if p["offense"] else game.away
		player_nodes.append(_make_player(p, team))
	_build_sideline(game.home, -1.0)
	_build_sideline(game.away, 1.0)
	_update_camera(1.0)
	update_view(0.0)


func set_video(shadows: bool, bloom: bool) -> void:
	shadows_enabled = shadows
	key_light.shadow_enabled = shadows
	environment.environment.glow_enabled = bloom


func update_view(delta: float) -> void:
	if game == null:
		return
	elapsed += delta
	_update_camera(delta)
	line_of_scrimmage.position.z = -game.los
	first_down_line.position.z = -game.first_down
	line_of_scrimmage.visible = game.phase != "dead"
	first_down_line.visible = game.phase != "dead"
	_update_effects(delta)
	_update_sidelines()
	for i in player_nodes.size():
		var p: Dictionary = game.players[i]
		var parts: Dictionary = player_nodes[i]
		var root: Node3D = parts["root"]
		root.position = Vector3(p["pos"].x, 0, -p["pos"].y)
		root.rotation.y = -p["facing"]
		root.rotation.x = -1.15 if p["down"] or p["dive_ticks"] > 0 else 0.0
		var speed = p["vel"].length()
		var swing = sin(elapsed * (8.0 + speed * 0.55) + float(i) * 0.7) * minf(speed / 9.0, 1.0) * 0.7
		parts["left_leg"].rotation.x = swing
		parts["right_leg"].rotation.x = -swing
		parts["left_arm"].rotation.x = -swing * 0.8
		parts["right_arm"].rotation.x = swing * 0.8
		parts["marker"].visible = game.phase == "live" and game.controlled == i
	var spot: Vector2 = game.ball_position()
	ball.position = Vector3(spot.x, game.ball_height(), -spot.y)
	if game.ball_state == "held" and game.carrier >= 0:
		var holder: Dictionary = game.players[game.carrier]
		ball.position += Vector3(0.32 * cos(holder["facing"]), 0.0, 0.32 * sin(holder["facing"]))
	ball.visible = game.ball_state != "dead" or game.phase == "live"


func _update_camera(delta: float) -> void:
	var desired: Vector2
	if game.phase == "pre_snap":
		desired = Vector2(0, game.los - 11.0)
	else:
		var ball_pos: Vector2 = game.ball_position()
		desired = Vector2(clampf(ball_pos.x * 0.7, -12, 12), ball_pos.y)
	var rate = 3.5 if game.phase == "live" else 2.0
	focus = focus.lerp(desired, clampf(delta * rate, 0.0, 1.0))
	camera.position = Vector3(focus.x, 9.0, -(focus.y - 15.0))
	camera.look_at(Vector3(focus.x, 0.8, -(focus.y + 16.0)), Vector3.UP)


func _material(color: Color, emissive: bool = false, transparent: bool = false) -> StandardMaterial3D:
	var key = color.to_html(true) + str(emissive) + str(transparent)
	if materials.has(key):
		return materials[key]
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if emissive:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.7
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = material
	return material


func _box(parent: Node, center: Vector3, size: Vector3, color: Color, emissive: bool = false) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color, emissive)
	instance.position = center
	parent.add_child(instance)
	return instance


func _build_environment() -> void:
	environment = WorldEnvironment.new()
	var world = Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = Color("02040b")
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color("65708e")
	world.ambient_light_energy = 0.22
	world.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.glow_enabled = true
	world.glow_intensity = 1.25
	world.glow_bloom = 0.18
	world.glow_hdr_threshold = 0.72
	world.fog_enabled = true
	world.fog_light_color = Color("111a2b")
	world.fog_light_energy = 0.32
	world.fog_density = 0.009
	world.fog_sky_affect = 0.15
	environment.environment = world
	add_child(environment)
	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-58, -28, 0)
	key_light.light_color = Color("aab8df")
	key_light.light_energy = 0.38
	key_light.shadow_enabled = true
	add_child(key_light)


func _build_field() -> void:
	_box(self, Vector3(0, -0.13, -60), Vector3(FIELD_WIDTH + 34, 0.25, 136), Color("25462d"))
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * 32.0, 0.008, -60), Vector3(10.0, 0.03, 120), Color("2c5938"))
	for i in 24:
		var color = Color("399f42") if i % 2 == 0 else Color("328e39")
		_box(self, Vector3(0, 0.005, -(float(i) * 5.0 + 2.5)), Vector3(FIELD_WIDTH, 0.025, 5), color)
	_box(self, Vector3(0, 0.025, -5), Vector3(FIELD_WIDTH, 0.025, 10), Color("2251a3"))
	_box(self, Vector3(0, 0.025, -115), Vector3(FIELD_WIDTH, 0.025, 10), Color("2351a3"))
	var marks = []
	for yard in range(10, 111, 5):
		marks.append({"pos": Vector3(0, 0.055, -yard), "size": Vector3(FIELD_WIDTH, 0.025, 0.14)})
	for yard in range(11, 110):
		if yard % 5 == 0:
			continue
		for x in [-9.2, 9.2]:
			marks.append({"pos": Vector3(x, 0.06, -yard), "size": Vector3(0.9, 0.025, 0.09)})
			marks.append({"pos": Vector3(signf(x) * 25.9, 0.06, -yard), "size": Vector3(0.65, 0.025, 0.09)})
	_add_multibox(marks, Color("f4f4e8"))
	for x in [-FIELD_WIDTH / 2.0, FIELD_WIDTH / 2.0]:
		_box(self, Vector3(x, 0.055, -60), Vector3(0.16, 0.025, 120), Color("f6f7ed"))
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * 34.8, 0.06, -60), Vector3(0.12, 0.025, 58), Color("e1e4dc"))
		for z in [-47.0, -73.0]:
			_box(self, Vector3(side * 32.5, 0.045, z), Vector3(0.18, 0.025, 0.18), Color("ffd740"))
	line_of_scrimmage = _box(self, Vector3.ZERO, Vector3(FIELD_WIDTH, 0.035, 0.18), Color(0.1, 0.75, 1.0, 0.65))
	line_of_scrimmage.material_override = _material(Color(0.1, 0.75, 1.0, 0.65), false, true)
	first_down_line = _box(self, Vector3.ZERO, Vector3(FIELD_WIDTH, 0.035, 0.18), Color(1.0, 0.8, 0.1, 0.65))
	first_down_line.material_override = _material(Color(1.0, 0.8, 0.1, 0.65), false, true)
	line_of_scrimmage.position.y = 0.08
	first_down_line.position.y = 0.09


func _add_multibox(entries: Array, color: Color) -> void:
	var mesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = entries.size()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		multimesh.set_instance_transform(i, Transform3D(Basis().scaled(entry["size"]), entry["pos"]))
	var instance = MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _build_stadium() -> void:
	var concrete = Color("242a3a")
	var fascia = Color("101524")
	var seats = []
	var generator = RandomNumberGenerator.new()
	generator.seed = 9328
	for side in [-1.0, 1.0]:
		for row in 36:
			var upper = row >= 18
			var x = 38.5 + float(row) * 0.9
			var height = 0.9 + minf(float(row), 17.0) * 0.55
			if upper:
				x = 52.3 + float(row - 18) * 0.9
				height = 12.35 + float(row - 18) * 0.8
			var length = 146.0 if upper else 128.0
			_box(self, Vector3(side * (x + 0.45), height * 0.5, 4.0 - length * 0.5),
				Vector3(0.9, height, length), concrete.darkened(0.12 if row % 2 else 0.0))
			for along in (124 if upper else 108):
				var z = 2.0 - float(along) * 1.16
				var palette = generator.randi_range(0, CROWD_COLORS.size() - 1)
				seats.append({"pos": Vector3(side * (x + 0.45), height, z),
					"color": CROWD_COLORS[palette], "palette": palette, "row": row,
					"skin": SKIN_COLORS[generator.randi_range(0, SKIN_COLORS.size() - 1)]})
		_box(self, Vector3(side * 36.9, 0.6, -60), Vector3(0.6, 1.2, 128), fascia)
		for panel in 16:
			var color: Color = CROWD_COLORS[(panel + int(side + 1.0) * 3) % CROWD_COLORS.size()]
			_box(self, Vector3(side * 36.55, 0.65, 2.0 - panel * 8.0),
				Vector3(0.08, 0.65, 7.3), color.lightened(0.3), true)
		_box(self, Vector3(side * 52.1, 12.55, -60), Vector3(0.45, 0.8, 146), Color("29d8f2"), true)
		for support in 8:
			var support_z = -9.0 - float(support) * 14.5
			_box(self, Vector3(side * 51.8, 6.2, support_z),
				Vector3(0.8, 12.4, 0.9), fascia)
		for corner in [-1.0]:
			var corner_piece = _box(self,
				Vector3(side * 43.5, 8.2, -60.0 + corner * 67.0),
				Vector3(13.0, 1.4, 13.0), concrete)
			corner_piece.rotation.y = side * corner * PI / 4.0
		for z in [-8.0, -55.0, -105.0]:
			_light_bank(Vector3(side * 73.5, 35, z), true)
			_spotlight(Vector3(side * 70.0, 35.0, z), Vector3(0.0, 0.0, z), Color("dce8ff"))
	for row in 30:
		var upper = row >= 16
		var distance = 125.0 + float(row) * 0.9
		var height = 0.9 + minf(float(row), 15.0) * 0.55
		if upper:
			distance = 136.0 + float(row - 16) * 0.9
			height = 11.0 + float(row - 16) * 0.8
		var width = 135.0 if upper else 95.0
		_box(self, Vector3(0, height * 0.5, -distance), Vector3(width, height, 0.9),
			concrete.darkened(0.12 if row % 2 else 0.0))
		for along in (120 if upper else 84):
			var x = -width * 0.5 + 0.5 + float(along) * 1.12
			var palette = generator.randi_range(0, CROWD_COLORS.size() - 1)
			seats.append({"pos": Vector3(x, height, -distance),
				"color": CROWD_COLORS[palette], "palette": palette, "row": row,
				"skin": SKIN_COLORS[generator.randi_range(0, SKIN_COLORS.size() - 1)]})
	_box(self, Vector3(0, 11.5, -136.5), Vector3(119, 0.8, 0.35), Color("f15b32"), true)
	_build_jumbotron()
	for x in [-37.0, 37.0]:
		_light_bank(Vector3(x, 29, -153), false)
		_spotlight(Vector3(x, 29.0, -151.0), Vector3(x * 0.15, 0.0, -105.0), Color("d8e5ff"))
	_build_crowd(seats)
	for z in [-121.0, 1.0]:
		var yellow = Color("ffc819")
		_box(self, Vector3(0, 1.5, z), Vector3(0.35, 3, 0.35), yellow)
		_box(self, Vector3(0, 3.05, z), Vector3(6.2, 0.2, 0.2), yellow)
		for x in [-3.08, 3.08]:
			_box(self, Vector3(x, 6.5, z), Vector3(0.17, 7, 0.17), yellow)


func _build_jumbotron() -> void:
	var frame = Color("101827")
	var screen = Color("15374a")
	var z = -156.0
	for x in [-8.0, 8.0]:
		_box(self, Vector3(x, 12.5, z - 1.0), Vector3(1.4, 25.0, 1.4), frame)
	_box(self, Vector3(0, 30.0, z), Vector3(24.0, 11.0, 1.4), frame)
	_box(self, Vector3(0, 30.2, z + 0.74), Vector3(22.4, 9.6, 0.08), screen, true)
	_box(self, Vector3(0, 35.9, z + 0.2), Vector3(24.6, 0.5, 1.6), Color("29d8f2"), true)
	var lines = [
		["BLOCK BOWL  •  GAME DAY", 128, 0.014, 32.6, Color("e9f8ff")],
		["HOME  00  :  00  AWAY", 96, 0.015, 29.6, Color("ffd66b")],
		["KICKOFF  •  DEFEND YOUR TURF  •  KICKOFF", 56, 0.011, 26.8, Color("66efff")],
	]
	for line in lines:
		var label = Label3D.new()
		label.text = line[0]
		label.font_size = line[1]
		label.pixel_size = line[2]
		label.modulate = line[4]
		label.position = Vector3(0, line[3], z + 0.8)
		add_child(label)


func _light_bank(center: Vector3, side_facing: bool) -> void:
	_box(self, Vector3(center.x, center.y * 0.5, center.z), Vector3(0.6, center.y, 0.6), Color("171b27"))
	var frame_size = Vector3(0.6, 3.2, 8.0) if side_facing else Vector3(8.0, 3.2, 0.6)
	_box(self, center, frame_size, Color("202633"))
	for i in 5:
		var offset = (float(i) - 2.0) * 1.5
		var lamp_pos = center + (Vector3(0, 0, offset) if side_facing else Vector3(offset, 0, 0))
		var lamp_size = Vector3(0.75, 1.2, 1.2) if side_facing else Vector3(1.2, 1.2, 0.75)
		_box(self, lamp_pos, lamp_size, Color("fff7d5"), true)


func _spotlight(position: Vector3, target: Vector3, color: Color) -> void:
	var light = SpotLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = 17.0
	light.spot_range = 112.0
	light.spot_angle = 68.0
	light.spot_angle_attenuation = 1.25
	light.shadow_enabled = false
	add_child(light)
	light.look_at(target, Vector3.UP)


func _build_crowd(seats: Array) -> void:
	var close_seats: Array = []
	var medium_seats: Array = []
	var far_groups: Array = []
	for unused in CROWD_COLORS.size():
		far_groups.append([])
	for seat in seats:
		if seat["row"] < 4:
			close_seats.append(seat)
		elif seat["row"] < 15:
			medium_seats.append(seat)
		else:
			far_groups[seat["palette"]].append(seat)
	_add_crowd_part(close_seats, Vector3(0.44, 0.58, 0.28), Vector3(0, 0.88, 0), "shirt")
	_add_crowd_part(close_seats, Vector3(0.3, 0.32, 0.28), Vector3(0, 1.36, 0), "skin")
	_add_crowd_part(close_seats, Vector3(0.74, 0.16, 0.27), Vector3(0, 1.08, 0), "shirt")
	_add_crowd_part(close_seats, Vector3(0.19, 0.43, 0.24), Vector3(-0.12, 0.35, 0), "pants")
	_add_crowd_part(close_seats, Vector3(0.19, 0.43, 0.24), Vector3(0.12, 0.35, 0), "pants")
	_add_crowd_part(close_seats, Vector3(0.22, 0.1, 0.3), Vector3(-0.12, 0.08, -0.035), "shoe")
	_add_crowd_part(close_seats, Vector3(0.22, 0.1, 0.3), Vector3(0.12, 0.08, -0.035), "shoe")
	_add_crowd_part(medium_seats, Vector3(0.42, 0.54, 0.26), Vector3(0, 0.84, 0), "shirt")
	_add_crowd_part(medium_seats, Vector3(0.28, 0.3, 0.26), Vector3(0, 1.3, 0), "skin")
	_add_crowd_part(medium_seats, Vector3(0.4, 0.48, 0.24), Vector3(0, 0.34, 0), "pants")
	for palette in far_groups.size():
		_add_crowd_billboards(far_groups[palette], palette)


func _crowd_brightness(position: Vector3) -> float:
	var outside_x = maxf(absf(position.x) - FIELD_WIDTH / 2.0, 0.0)
	var outside_z = maxf(absf(position.z + 60.0) - 60.0, 0.0)
	var stand_distance = Vector2(outside_x, outside_z).length()
	var fade = clampf((stand_distance - 5.0) / 55.0, 0.0, 0.58)
	fade += clampf(position.y / 45.0, 0.0, 0.24)
	return 1.0 - fade


func _add_crowd_part(seats: Array, size: Vector3, offset: Vector3, color_key: String) -> void:
	if seats.is_empty():
		return
	var mesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = seats.size()
	for i in seats.size():
		var seat: Dictionary = seats[i]
		var seat_position: Vector3 = seat["pos"]
		multimesh.set_instance_transform(
			i, Transform3D(Basis().scaled(size), seat_position + offset))
		var color: Color
		match color_key:
			"skin": color = seat["skin"]
			"pants": color = seat["color"].darkened(0.7)
			"shoe": color = Color("10121a")
			_: color = seat["color"]
		multimesh.set_instance_color(i, color * _crowd_brightness(seat_position))
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	var crowd = MultiMeshInstance3D.new()
	crowd.multimesh = multimesh
	crowd.material_override = material
	crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crowd)


func _add_crowd_billboards(seats: Array, palette: int) -> void:
	if seats.is_empty():
		return
	var image = Image.create(12, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var shirt: Color = CROWD_COLORS[palette]
	var skin = Color("e2ad87")
	var pants = Color("596071")
	var dark = Color("222a37")
	image.fill_rect(Rect2i(3, 1, 6, 5), skin)
	image.fill_rect(Rect2i(3, 1, 6, 1), dark)
	image.fill_rect(Rect2i(4, 3, 1, 1), dark)
	image.fill_rect(Rect2i(7, 3, 1, 1), dark)
	image.fill_rect(Rect2i(3, 6, 6, 6), shirt)
	image.fill_rect(Rect2i(1, 7, 2, 5), shirt.darkened(0.12))
	image.fill_rect(Rect2i(9, 7, 2, 5), shirt.darkened(0.12))
	image.fill_rect(Rect2i(3, 12, 6, 4), pants)
	image.fill_rect(Rect2i(3, 16, 2, 4), pants.darkened(0.12))
	image.fill_rect(Rect2i(7, 16, 2, 4), pants.darkened(0.12))
	image.fill_rect(Rect2i(3, 20, 2, 2), dark)
	image.fill_rect(Rect2i(7, 20, 2, 2), dark)
	var texture = ImageTexture.create_from_image(image)
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.75, 1.5)
	var material = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = seats.size()
	for i in seats.size():
		var seat: Dictionary = seats[i]
		var seat_position: Vector3 = seat["pos"]
		multimesh.set_instance_transform(i, Transform3D(Basis(), seat_position + Vector3(0, 0.76, 0)))
		var brightness = _crowd_brightness(seat_position)
		multimesh.set_instance_color(i, Color(brightness, brightness, brightness))
	var crowd = MultiMeshInstance3D.new()
	crowd.multimesh = multimesh
	crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crowd)


func _build_sideline(team: Dictionary, side: float) -> void:
	var bench = Color("17202a")
	_box(sideline_root, Vector3(side * 36.2, 0.32, -60), Vector3(1.15, 0.58, 24), bench)
	for z in [-70.0, -50.0]:
		_box(sideline_root, Vector3(side * 36.2, 0.13, z), Vector3(1.25, 0.22, 0.45), Color("303846"))
	var players: Array = []
	var rng = RandomNumberGenerator.new()
	rng.seed = 7741 if side < 0 else 1934
	var attempts = 0
	while players.size() < 32 and attempts < 4000:
		attempts += 1
		var candidate = Vector3(side * rng.randf_range(28.6, 32.4), 0, -rng.randf_range(31.0, 89.0))
		var crowded = false
		for other in players:
			if other["position"].distance_to(candidate) < 0.95:
				crowded = true
				break
		if crowded or (absf(candidate.x) > 31.0 and candidate.z < -46.5 and candidate.z > -73.5):
			continue
		players.append({
			"position": candidate,
			"phase": rng.randf_range(0.0, TAU),
			"facing": rng.randf_range(-0.55, 0.55),
			"skin": SKIN_COLORS[rng.randi_range(0, SKIN_COLORS.size() - 1)],
		})
	_build_sideline_multimeshes(team, side, players, false)
	var coaches: Array = []
	for i in 3:
		coaches.append({
			"position": Vector3(side * 34.2, 0, -44.0 - float(i) * 16.0),
			"phase": float(i) * 2.1 + side,
			"skin": SKIN_COLORS[(i + 2) % SKIN_COLORS.size()],
		})
	_build_sideline_multimeshes(team, side, coaches, true)


func _build_sideline_multimeshes(
	team: Dictionary, side: float, members: Array, coaches: bool
) -> void:
	var pants: Color = Color("111825") if coaches else team["primary"].darkened(0.62)
	var parts: Array
	if coaches:
		parts = [
			{"size": Vector3(0.58, 0.76, 0.36), "offset": Vector3(0, 1.04, 0), "color": Color("26334a")},
			{"size": Vector3(0.38, 0.38, 0.38), "offset": Vector3(0, 1.78, 0), "color": "skin"},
			{"size": Vector3(0.48, 0.12, 0.44), "offset": Vector3(0, 1.99, 0), "color": team["secondary"]},
			{"size": Vector3(0.2, 0.48, 0.23), "offset": Vector3(-0.4, 1.1, 0), "color": Color("26334a"), "arm": -1},
			{"size": Vector3(0.2, 0.48, 0.23), "offset": Vector3(0.4, 1.1, 0), "color": Color("26334a"), "arm": 1},
			{"size": Vector3(0.24, 0.54, 0.25), "offset": Vector3(-0.17, 0.34, 0), "color": pants},
			{"size": Vector3(0.24, 0.54, 0.25), "offset": Vector3(0.17, 0.34, 0), "color": pants},
			{"size": Vector3(0.2, 0.28, 0.035), "offset": Vector3(0.24, 1.08, -0.22), "color": Color("dce5ed")},
		]
	else:
		parts = [
			{"size": Vector3(0.62, 0.72, 0.38), "offset": Vector3(0, 1.04, 0), "color": team["primary"]},
			{"size": Vector3(0.82, 0.18, 0.44), "offset": Vector3(0, 1.43, 0), "color": team["primary"]},
			{"size": Vector3(0.52, 0.16, 0.34), "offset": Vector3(0, 0.68, 0), "color": pants},
			{"size": Vector3(0.38, 0.38, 0.38), "offset": Vector3(0, 1.78, 0), "color": "skin"},
			{"size": Vector3(0.46, 0.37, 0.44), "offset": Vector3(0, 1.81, 0), "color": team["primary"]},
			{"size": Vector3(0.08, 0.025, 0.43), "offset": Vector3(0, 2.01, 0), "color": team["secondary"]},
			{"size": Vector3(0.2, 0.52, 0.23), "offset": Vector3(-0.43, 1.11, 0), "color": team["primary"], "arm": -1},
			{"size": Vector3(0.2, 0.52, 0.23), "offset": Vector3(0.43, 1.11, 0), "color": team["primary"], "arm": 1},
			{"size": Vector3(0.24, 0.54, 0.25), "offset": Vector3(-0.17, 0.34, 0), "color": pants},
			{"size": Vector3(0.24, 0.54, 0.25), "offset": Vector3(0.17, 0.34, 0), "color": pants},
			{"size": Vector3(0.26, 0.13, 0.34), "offset": Vector3(-0.17, 0.08, -0.05), "color": Color("10121a")},
			{"size": Vector3(0.26, 0.13, 0.34), "offset": Vector3(0.17, 0.08, -0.05), "color": Color("10121a")},
		]
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.82
	var group_parts: Array = []
	for part in parts:
		var mesh = BoxMesh.new()
		mesh.size = Vector3.ONE
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = members.size()
		for i in members.size():
			var member: Dictionary = members[i]
			var color: Color
			if typeof(part["color"]) == TYPE_STRING:
				color = member["skin"]
			else:
				color = part["color"]
			multimesh.set_instance_color(i, color)
		var instance = MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sideline_root.add_child(instance)
		group_parts.append({"multimesh": multimesh, "part": part})
	sideline_groups.append({
		"side": side,
		"members": members,
		"parts": group_parts,
	})


func _update_sidelines() -> void:
	var cheering = game.phase == "live"
	for group in sideline_groups:
		var side: float = group["side"]
		var members: Array = group["members"]
		for group_part in group["parts"]:
			var multimesh: MultiMesh = group_part["multimesh"]
			var part: Dictionary = group_part["part"]
			var offset: Vector3 = part["offset"]
			var size: Vector3 = part["size"]
			for i in members.size():
				var member: Dictionary = members[i]
				var phase: float = member["phase"]
				var cheer = maxf(0.0, sin(elapsed * 5.2 + phase)) if cheering else 0.0
				var position: Vector3 = member["position"]
				position.x += cos(elapsed * 0.85 + phase) * 0.025
				position.y += sin(elapsed * 1.8 + phase) * 0.035 + cheer * 0.16
				position.z += sin(elapsed * 0.9 + phase) * 0.06
				var yaw = -side * PI / 2.0 + member.get("facing", 0.0) + sin(elapsed * 1.4 + phase) * 0.025
				var rotation = Basis(Vector3.UP, yaw)
				var part_offset = offset
				var part_rotation = Basis()
				if part.has("arm"):
					var arm_side: float = part["arm"]
					part_offset.y += cheer * 0.16
					part_rotation = Basis(Vector3.BACK, -arm_side * cheer * 0.75)
				var transform = Transform3D(
					rotation * part_rotation * Basis().scaled(size),
					position + rotation * part_offset)
				multimesh.set_instance_transform(i, transform)


func _make_player(p: Dictionary, team: Dictionary) -> Dictionary:
	var root = Node3D.new()
	player_root.add_child(root)
	var primary: Color = team["primary"]
	var secondary: Color = team["secondary"]
	var pants = primary.darkened(0.62)
	var skin: Color = SKIN_COLORS[p["id"] % SKIN_COLORS.size()]
	_box(root, Vector3(0, 1.31, 0), Vector3(0.72, 0.55, 0.44), primary)
	_box(root, Vector3(0, 1.58, 0), Vector3(1.0, 0.24, 0.54), primary)
	_box(root, Vector3(0, 1.04, 0), Vector3(0.68, 0.18, 0.4), pants)
	_box(root, Vector3(0, 1.94, 0), Vector3(0.48, 0.45, 0.49), primary)
	_box(root, Vector3(0, 2.18, 0), Vector3(0.1, 0.035, 0.51), secondary)
	_box(root, Vector3(0, 1.86, -0.25), Vector3(0.34, 0.22, 0.035), skin)
	_box(root, Vector3(0, 1.8, -0.30), Vector3(0.4, 0.045, 0.08), Color("d7dce5"))
	var limbs = {}
	for side in [-1, 1]:
		var side_name = "left" if side < 0 else "right"
		var arm = Node3D.new()
		arm.position = Vector3(side * 0.47, 1.55, 0)
		root.add_child(arm)
		_box(arm, Vector3(0, -0.17, 0), Vector3(0.22, 0.35, 0.24), primary)
		_box(arm, Vector3(0, -0.47, 0), Vector3(0.2, 0.3, 0.2), skin)
		limbs[side_name + "_arm"] = arm
		var leg = Node3D.new()
		leg.position = Vector3(side * 0.17, 0.96, 0)
		root.add_child(leg)
		_box(leg, Vector3(0, -0.23, 0), Vector3(0.27, 0.46, 0.29), pants)
		_box(leg, Vector3(0, -0.66, 0), Vector3(0.24, 0.4, 0.24), secondary)
		_box(leg, Vector3(0, -0.91, -0.06), Vector3(0.28, 0.13, 0.38), Color("10121a"))
		limbs[side_name + "_leg"] = leg
	var number = Label3D.new()
	number.text = str(p["number"])
	number.font_size = 64
	number.pixel_size = 0.006
	number.outline_size = 8
	number.modulate = secondary
	number.outline_modulate = pants
	number.position = Vector3(0, 1.34, 0.235)
	number.no_depth_test = false
	root.add_child(number)
	var marker = MeshInstance3D.new()
	var ring = TorusMesh.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 0.58
	marker.mesh = ring
	marker.material_override = _material(Color("ffda28"), true)
	marker.position.y = 0.06
	root.add_child(marker)
	limbs["root"] = root
	limbs["marker"] = marker
	return limbs


func _build_ball() -> void:
	ball = Node3D.new()
	add_child(ball)
	_box(ball, Vector3.ZERO, Vector3(0.22, 0.22, 0.38), Color("71391a"))
	_box(ball, Vector3(0, 0.12, 0), Vector3(0.035, 0.025, 0.15), Color("f5ecdb"))


func _build_effects() -> void:
	confetti = _particles(160, 2.5, Color("ffdc42"), 0.16, true, 5.0, 11.0, 10.0)
	impact_sparks = _turf_kickup()
	turbo_trail = _particles(32, 0.38, Color("42caff"), 0.1, false, 1.0, 3.5, 1.0)
	event_light = OmniLight3D.new()
	event_light.light_color = Color("55dfff")
	event_light.light_energy = 0.0
	event_light.omni_range = 12.0
	event_light.shadow_enabled = false
	add_child(event_light)


func _particles(
	amount: int, lifetime: float, color: Color, size: float, one_shot: bool,
	speed_min: float, speed_max: float, gravity: float
) -> GPUParticles3D:
	var particles = GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = one_shot
	particles.explosiveness = 0.92 if one_shot else 0.0
	particles.emitting = false
	particles.local_coords = true
	particles.visibility_aabb = AABB(Vector3(-24, -24, -24), Vector3(48, 48, 48))
	var process = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.3
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 180.0 if one_shot else 32.0
	process.initial_velocity_min = speed_min
	process.initial_velocity_max = speed_max
	process.gravity = Vector3(0.0, -gravity, 0.0)
	process.scale_min = 0.65
	process.scale_max = 1.25
	process.hue_variation_min = -0.38 if one_shot else -0.08
	process.hue_variation_max = 0.38 if one_shot else 0.08
	process.color = color
	particles.process_material = process
	var block = BoxMesh.new()
	block.size = Vector3.ONE * size
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	block.material = material
	particles.draw_pass_1 = block
	add_child(particles)
	return particles


func _turf_kickup() -> GPUParticles3D:
	var particles = GPUParticles3D.new()
	particles.amount = 26
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.emitting = false
	particles.local_coords = true
	particles.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 8, 12))
	var process = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.45
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 38.0
	process.initial_velocity_min = 1.6
	process.initial_velocity_max = 3.6
	process.gravity = Vector3(0.0, -14.0, 0.0)
	process.damping_min = 0.6
	process.damping_max = 1.4
	process.angular_velocity_min = -360.0
	process.angular_velocity_max = 360.0
	process.scale_min = 0.5
	process.scale_max = 1.1
	var colors = Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.45, 0.7, 1.0])
	colors.colors = PackedColorArray([
		Color("4a3322"), Color("5e4029"), Color("2f6b33"), Color("3b8a3f"),
	])
	var ramp = GradientTexture1D.new()
	ramp.gradient = colors
	process.color_initial_ramp = ramp
	var fade = Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(0.7, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var fade_texture = CurveTexture.new()
	fade_texture.curve = fade
	process.scale_curve = fade_texture
	particles.process_material = process
	var clod = BoxMesh.new()
	clod.size = Vector3.ONE * 0.09
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	clod.material = material
	particles.draw_pass_1 = clod
	add_child(particles)
	return particles


func _update_effects(delta: float) -> void:
	var turbo = false
	if game.phase == "live" and game.controlled >= 0:
		var runner: Dictionary = game.players[game.controlled]
		turbo = runner["turbo_active"]
		var velocity: Vector2 = runner["vel"]
		var trail = Vector3(runner["pos"].x, 0.75, -runner["pos"].y)
		if velocity.length_squared() > 0.1:
			trail -= Vector3(velocity.x, 0.0, -velocity.y).normalized() * 0.75
		turbo_trail.position = trail
	turbo_trail.emitting = turbo
	if game.phase == "dead" and game.last_outcome != "" and game.play_number != last_effect_play:
		last_effect_play = game.play_number
		var impact = Vector3(game.last_spot.x, 0.7, -game.last_spot.y)
		event_light.position = impact
		if game.last_outcome == "touchdown":
			confetti.position = Vector3(0.0, 0.8, -game.last_spot.y)
			confetti.restart()
			confetti.emitting = true
			event_light.light_color = Color("ffdb43")
			event_light.omni_range = 22.0
			event_light_time = 0.45
		else:
			impact_sparks.position = Vector3(impact.x, 0.05, impact.z)
			impact_sparks.restart()
			impact_sparks.emitting = true
	if event_light_time > 0.0:
		event_light_time = maxf(0.0, event_light_time - delta)
		event_light.light_energy = 8.0 * event_light_time / 0.45
	else:
		event_light.light_energy = 0.0
