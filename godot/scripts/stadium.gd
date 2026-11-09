extends Node3D

const Simulation = preload("res://godot/scripts/simulation.gd")
const FIELD_WIDTH = 53.333
const CROWD_COLORS = [
	Color("2457d6"), Color("d92b35"), Color("f5b82e"), Color("b8c5d5"),
	Color("17223a"), Color("24a9b5"), Color("e77736"), Color("52678d"),
]
const SKIN_COLORS = [
	Color("f2c5a0"), Color("dba47e"), Color("ae7659"), Color("85533e"), Color("59382b"),
]
const HAIR_COLORS = [
	Color("2b1c12"), Color("5a3a20"), Color("111114"), Color("c9a15a"), Color("8a4b22"),
]
const ADS = [
	"BLOCK COLA", "PIXEL PIZZA", "CUBE MOTORS", "CRAFT BANK",
	"VOXEL WIRELESS", "REDSTONE ENERGY", "DIAMOND AIR", "OBSIDIAN INSURANCE",
]
const AD_COLORS = [
	Color("c3262f"), Color("1f6fd1"), Color("e09a12"), Color("2a9a48"), Color("7a3cc9"), Color("e0571f"),
]
const STAND_INNER_SIDE = 38.6
const STAND_INNER_END = 127.6
const LOWER_ROWS = 26
const UPPER_ROWS = 26
const SEAT_PITCH = 0.95
const TUNNEL_X = 26.0
const SHAFT_SHADER = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.75, 0.82, 1.0, 1.0);
uniform float strength = 0.11;
varying float along;
void vertex() {
	along = clamp(0.5 - VERTEX.y / max(1.0, 0.0001), 0.0, 1.0);
}
void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	float fade = smoothstep(0.0, 0.18, along) * (1.0 - smoothstep(0.55, 1.0, along));
	float shimmer = 0.85 + 0.15 * sin(TIME * 0.7 + along * 9.0);
	ALBEDO = tint.rgb;
	ALPHA = clamp(strength * edge * fade * shimmer, 0.0, 1.0);
}
"""
const MIST_SHADER = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.42, 0.5, 0.66, 1.0);
uniform float strength = 0.16;
varying float seed;
void vertex() {
	seed = INSTANCE_CUSTOM.x;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV - 0.5;
	float radial = 1.0 - smoothstep(0.12, 0.5, length(uv));
	vec2 drift = UV * 3.0 + vec2(TIME * 0.025, TIME * 0.012) + vec2(seed * 13.0);
	float wisps = noise(drift) * 0.65 + noise(drift * 2.3) * 0.35;
	ALBEDO = tint.rgb;
	ALPHA = clamp(strength * radial * (0.35 + wisps), 0.0, 1.0);
}
"""
const VIGNETTE_SHADER = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float d = length(c * vec2(1.2, 1.0));
	vec2 shift = c * 0.0025 * smoothstep(0.2, 0.75, d);
	vec3 col = vec3(texture(screen_texture, uv + shift).r, texture(screen_texture, uv).g, texture(screen_texture, uv - shift).b);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col += vec3(0.025, 0.008, -0.02) * smoothstep(0.45, 1.0, luma);
	col += vec3(-0.01, 0.004, 0.022) * (1.0 - smoothstep(0.0, 0.3, luma));
	float shade = smoothstep(0.3, 0.82, d);
	float top = smoothstep(-0.2, -0.5, c.y) * 0.25;
	col = mix(col, vec3(0.004, 0.007, 0.02), clamp(shade * 0.7 + top, 0.0, 0.85));
	float grain = fract(sin(dot(floor(FRAGCOORD.xy) + fract(TIME * 7.0) * vec2(113.0, 71.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	col += grain * 0.03;
	COLOR = vec4(col, 1.0);
}
"""
const FLARE_SHADER = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.86, 0.92, 1.0, 1.0);
uniform float strength = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	float r = length(uv);
	float core = exp(-r * r * 70.0);
	float halo = exp(-r * r * 7.0) * 0.32;
	float streak = exp(-abs(uv.y) * 70.0) * (1.0 - smoothstep(0.0, 1.0, abs(uv.x))) * 0.7;
	float spike = exp(-abs(uv.x) * 80.0) * (1.0 - smoothstep(0.0, 0.55, abs(uv.y))) * 0.3;
	float twinkle = 0.9 + 0.1 * sin(TIME * 2.7 + NODE_POSITION_WORLD.x * 0.4 + NODE_POSITION_WORLD.z * 0.2);
	vec3 streak_tint = vec3(0.6, 0.78, 1.0);
	ALBEDO = tint.rgb * (core + halo + spike) + streak_tint * streak;
	ALPHA = clamp((core + halo + streak + spike) * strength * twinkle, 0.0, 1.0);
}
"""
const FLASH_SHADER = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float rate = 0.05;
varying float flash;
void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	float t = TIME * 0.45 + seed * 97.0;
	float id = floor(t);
	float h = fract(sin(id * 12.9898 + seed * 78.233) * 43758.5453);
	flash = h < rate ? max(0.0, 1.0 - fract(t) * 16.0) : 0.0;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= flash;
}
void fragment() {
	vec2 uv = (UV - 0.5) * 2.0;
	float r = length(uv);
	float glow = exp(-r * r * 9.0) + exp(-abs(uv.y) * 40.0) * (1.0 - abs(uv.x)) * 0.5;
	ALBEDO = vec3(1.0, 0.97, 0.9);
	ALPHA = clamp(glow * flash * 1.4, 0.0, 1.0);
}
"""
const POOL_SHADER = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
varying vec3 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float pool(vec2 p, vec2 c, vec2 r) {
	vec2 d = (p - c) / r;
	return exp(-dot(d, d));
}
void fragment() {
	vec2 p = world.xz;
	float light = 0.0;
	for (int i = 0; i < 3; i++) {
		float z = i == 0 ? -15.0 : (i == 1 ? -62.0 : -110.0);
		light += pool(p, vec2(-9.0, z), vec2(17.0, 15.0));
		light += pool(p, vec2(9.0, z), vec2(17.0, 15.0));
	}
	light += pool(p, vec2(-7.5, -88.0), vec2(15.0, 14.0)) + pool(p, vec2(7.5, -88.0), vec2(15.0, 14.0));
	light += pool(p, vec2(0.0, -38.0), vec2(14.0, 12.0)) * 0.7;
	float f = 0.58 + 0.3 * clamp(light, 0.0, 1.0);
	f *= 1.0 - 0.16 * smoothstep(27.0, 46.0, abs(p.x));
	f *= 1.0 - 0.12 * smoothstep(-122.0, -150.0, p.y);
	ALBEDO = vec3(0.0, 0.004, 0.012);
	ALPHA = clamp(1.0 - f, 0.0, 0.5);
}
"""
const BLOB_SHADER = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 0.5;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(0.15, 1.0, r));
}
"""
const CROWD_SHADER = """
shader_type spatial;
render_mode world_vertex_coords;

uniform float excitement = 0.0;

void vertex() {
	float wave = max(0.0, sin(TIME * 7.5 + INSTANCE_CUSTOM.x * 6.2831853));
	VERTEX.y += excitement * INSTANCE_CUSTOM.y * wave * 0.32;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""

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
var firework_pool: Array = []
var firework_queue: Array = []
var firework_index = 0
var pyro_jets: Array = []
var pyro_time = 0.0
var sideline_root: Node3D
var sideline_groups: Array = []
var materials: Dictionary = {}
var pixel_textures: Dictionary = {}
var focus = Vector2(0, 24)
var game = null
var elapsed = 0.0
var warmup_elapsed = -1.0
var event_light_time = 0.0
var last_effect_play = -1
var shadows_enabled = true
var stand_seats: Array = []
var dressing_root: Node3D
var dressing_key = ""
var clock_labels: Array = []
var jumbo_title: Label3D
var jumbo_score: Label3D
var jumbo_clock: Label3D
var last_clock_text = ""
var crowd_material: ShaderMaterial
var shaft_material: ShaderMaterial
var mist_material: ShaderMaterial
var mist_root: Node3D
var flare_material: ShaderMaterial
var flash_material: ShaderMaterial
var blob_material: ShaderMaterial
var blob_mesh: QuadMesh
var stadium_spots: Array = []
var follow_spot: SpotLight3D
var light_show_time = 0.0
var light_show_color = Color.WHITE
var officials: Array = []
var official_root: Node3D
var chain_sticks: Array = []
var down_box: Node3D
var down_box_label: Label3D
var chain_links: MeshInstance3D
var cheerleaders: Array = []
var excitement = 0.0
var down_marker: Node3D
var down_marker_label: Label3D


func _ready() -> void:
	crowd_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = CROWD_SHADER
	crowd_material.shader = shader
	dressing_root = Node3D.new()
	add_child(dressing_root)
	shaft_material = ShaderMaterial.new()
	var shaft_shader = Shader.new()
	shaft_shader.code = SHAFT_SHADER
	shaft_material.shader = shaft_shader
	shaft_material.render_priority = 2
	mist_material = ShaderMaterial.new()
	var mist_shader = Shader.new()
	mist_shader.code = MIST_SHADER
	mist_material.shader = mist_shader
	mist_material.render_priority = 1
	flare_material = _shader_material(FLARE_SHADER, 3)
	flash_material = _shader_material(FLASH_SHADER, 3)
	blob_material = _shader_material(BLOB_SHADER, 1)
	blob_mesh = QuadMesh.new()
	blob_mesh.size = Vector2.ONE
	blob_mesh.orientation = PlaneMesh.FACE_Y
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
	_build_atmosphere()
	_build_game_day()


func set_game(simulation) -> void:
	game = simulation
	warmup_elapsed = -1.0
	focus = Vector2(0, game.los - 11.0)
	last_effect_play = game.play_number
	turbo_trail.emitting = false
	for child in player_root.get_children():
		child.queue_free()
	player_nodes.clear()
	for child in sideline_root.get_children():
		child.queue_free()
	sideline_groups.clear()
	var key = "%s|%s" % [game.home["abbr"], game.away["abbr"]]
	if key != dressing_key:
		dressing_key = key
		last_clock_text = ""
		_build_dressing()
	for p in game.players:
		var is_home: bool = p["offense"] == game.offense_home
		var team: Dictionary = game.home if is_home else game.away
		player_nodes.append(_make_player(p, team, not is_home))
	_build_sideline(game.home, -1.0)
	_build_sideline(game.away, 1.0)
	_build_cheerleaders(game.home, game.away)
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
	var warming_up = warmup_elapsed >= 0.0
	official_root.visible = not warming_up
	line_of_scrimmage.visible = not warming_up and game.phase != "dead"
	first_down_line.visible = not warming_up and game.phase != "dead"
	_update_effects(delta)
	_update_game_day(delta)
	_update_sidelines()
	_update_displays()
	var target = 0.72 if warming_up else 0.12
	if game.phase == "live":
		target = 1.0
	elif game.phase == "dead" and game.last_outcome == "touchdown":
		target = 1.6
	excitement = lerpf(excitement, target, clampf(delta * 3.0, 0.0, 1.0))
	crowd_material.set_shader_parameter("excitement", excitement)
	down_marker.visible = not warming_up and game.phase == "pre_snap"
	down_marker.position = Vector3(0, 0, -(game.los - 6.5))
	if down_marker.visible:
		var ordinal = ["1st", "2nd", "3rd", "4th"][clampi(game.down - 1, 0, 3)]
		var distance = "Goal" if game.first_down >= Simulation.GOAL_LINE else str(maxi(1, int(round(game.first_down - game.los))))
		down_marker_label.text = "%s & %s" % [ordinal, distance]
	for i in player_nodes.size():
		var p: Dictionary = game.players[i]
		var parts: Dictionary = player_nodes[i]
		var root: Node3D = parts["root"]
		var jump_height = sin(PI * float(p["jump_ticks"]) / 24.0) * 1.15
		root.position = Vector3(p["pos"].x, jump_height, -p["pos"].y)
		root.rotation.y = -p["facing"]
		root.rotation.x = -1.15 if p["down"] or p["dive_ticks"] > 0 else 0.0
		if warming_up:
			var is_home: bool = p["offense"] == game.offense_home
			var team_index = i % 9
			var row = int(team_index / 5)
			var column = team_index % 5 - 2
			var yard_line = (38.0 if is_home else 68.0) + float(row) * (-2.2 if is_home else 2.2)
			jump_height = maxf(0.0, sin(warmup_elapsed * 7.0 + float(team_index) * 0.7)) * 0.8
			root.position = Vector3(float(column) * 2.4, jump_height, -yard_line)
			root.rotation = Vector3(0, 0 if is_home else PI, 0)
		var speed = 3.0 if warming_up else p["vel"].length()
		var swing = sin(elapsed * (8.0 + speed * 0.55) + float(i) * 0.7) * minf(speed / 9.0, 1.0) * 0.7
		parts["left_leg"].rotation.x = swing
		parts["right_leg"].rotation.x = -swing
		parts["left_arm"].rotation.x = -swing * 0.8
		parts["right_arm"].rotation.x = swing * 0.8
		if warming_up:
			parts["left_arm"].rotation.x = -PI * jump_height / 0.8
			parts["right_arm"].rotation.x = -PI * jump_height / 0.8
		elif p["jump_ticks"] > 0:
			parts["left_arm"].rotation.x = PI
			parts["right_arm"].rotation.x = PI
		parts["marker"].visible = not warming_up and game.phase == "live" and game.controlled == i
		var shadow: MeshInstance3D = parts["shadow"]
		shadow.position = Vector3(root.position.x, 0.088, root.position.z)
		if p["down"] or p["dive_ticks"] > 0:
			shadow.position += root.basis * Vector3(0, 0, -0.9)
			shadow.scale = Vector3(1.0, 1.0, 1.9)
		else:
			shadow.scale = Vector3.ONE
	var spot: Vector2 = game.ball_position()
	ball.position = Vector3(spot.x, game.ball_height(), -spot.y)
	if game.ball_state == "held" and game.carrier >= 0:
		var holder: Dictionary = game.players[game.carrier]
		ball.position += Vector3(0.32 * cos(holder["facing"]), 0.0, 0.32 * sin(holder["facing"]))
	ball.visible = not warming_up and (game.ball_state != "dead" or game.phase == "live")


func _update_camera(delta: float) -> void:
	if warmup_elapsed >= 0.0:
		var spotlight_home = warmup_elapsed < 2.5
		var local_time = warmup_elapsed if spotlight_home else warmup_elapsed - 2.5
		var pan = lerpf(-11.0, 11.0, clampf(local_time / 2.5, 0.0, 1.0))
		var team_y = 38.0 if spotlight_home else 68.0
		var camera_y = team_y + (10.0 if spotlight_home else -10.0)
		camera.fov = rad_to_deg(0.72)
		camera.position = Vector3(pan, 3.4, -camera_y)
		camera.look_at(Vector3(pan * 0.25, 1.2, -team_y), Vector3.UP)
		return
	camera.fov = rad_to_deg(0.88)
	var desired: Vector2
	if game.kickoff_return and game.ball_state == "flight":
		desired = game.flight["to"]
	elif game.phase == "pre_snap":
		desired = Vector2(0, game.los - 11.0)
	else:
		var ball_pos: Vector2 = game.ball_position()
		desired = Vector2(clampf(ball_pos.x * 0.7, -12, 12), ball_pos.y)
	var rate = 3.5 if game.phase == "live" else 2.0
	focus = focus.lerp(desired, clampf(delta * rate, 0.0, 1.0))
	camera.position = Vector3(focus.x, 14.5, -(focus.y - 16.0))
	camera.look_at(Vector3(focus.x, 0.8, -(focus.y + 19.0)), Vector3.UP)


func _pixel_texture(kind: String) -> ImageTexture:
	if pixel_textures.has(kind):
		return pixel_textures[kind]
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var image = Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var value = rng.randf_range(0.86, 1.0)
			var tint = Color(1, 1, 1)
			match kind:
				"grass":
					value = rng.randf_range(0.82, 1.0)
					if rng.randf() < 0.07:
						value = 0.74
					tint = Color(rng.randf_range(0.94, 1.0), 1.0, rng.randf_range(0.88, 0.96))
				"concrete":
					value = rng.randf_range(0.82, 0.98)
					if x == 0 or y == 0:
						value = 0.66
				"fabric":
					value = rng.randf_range(0.9, 1.0) - (0.06 if (x + y) % 4 == 0 else 0.0)
			image.set_pixel(x, y, Color(value * tint.r, value * tint.g, value * tint.b))
	image.generate_mipmaps()
	var texture = ImageTexture.create_from_image(image)
	pixel_textures[kind] = texture
	return texture


func _apply_pixels(material: BaseMaterial3D, kind: String) -> void:
	material.albedo_texture = _pixel_texture(kind)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.uv1_triplanar = true
	match kind:
		"grass":
			material.uv1_world_triplanar = true
			material.uv1_scale = Vector3.ONE * 0.55
		"concrete":
			material.uv1_world_triplanar = true
			material.uv1_scale = Vector3.ONE * 0.5
		_:
			material.uv1_scale = Vector3.ONE * 1.25


func _material(color: Color, emissive: bool = false, transparent: bool = false, kind: String = "block") -> StandardMaterial3D:
	var key = color.to_html(true) + str(emissive) + str(transparent) + kind
	if materials.has(key):
		return materials[key]
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if kind == "grass":
		material.roughness = 0.58
		material.metallic_specular = 0.5
	if not emissive and not transparent and kind != "":
		_apply_pixels(material, kind)
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


func _box(parent: Node, center: Vector3, size: Vector3, color: Color, emissive: bool = false, kind: String = "block") -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color, emissive, false, kind)
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
	world.fog_light_color = Color("16223a")
	world.fog_light_energy = 0.42
	world.fog_density = 0.0125
	world.fog_sky_affect = 0.25
	world.fog_height = 9.0
	world.fog_height_density = 0.022
	world.adjustment_enabled = true
	world.adjustment_contrast = 1.12
	world.adjustment_saturation = 1.08
	environment.environment = world
	add_child(environment)
	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-58, -28, 0)
	key_light.light_color = Color("aab8df")
	key_light.light_energy = 0.38
	key_light.shadow_enabled = true
	add_child(key_light)


func _build_field() -> void:
	_box(self, Vector3(0, -0.13, -49), Vector3(FIELD_WIDTH + 34, 0.25, 158), Color("2f5a38"), false, "grass")
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * 32.0, 0.008, -60), Vector3(10.0, 0.03, 120), Color("376b42"), false, "grass")
	for i in 24:
		var color = Color("38a043") if i % 2 == 0 else Color("308e3a")
		_box(self, Vector3(0, 0.005, -(float(i) * 5.0 + 2.5)), Vector3(FIELD_WIDTH, 0.025, 5), color, false, "grass")
	_build_field_details()
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * (FIELD_WIDTH / 2.0 + 0.9), 0.05, -60), Vector3(1.8, 0.025, 123.6), Color("eef0ea"))
		_box(self, Vector3(0, 0.05, -60 + side * 60.9), Vector3(FIELD_WIDTH + 3.6, 0.025, 1.8), Color("eef0ea"))
	for yard in range(20, 101, 10):
		var number = str(yard - 10 if yard <= 60 else 110 - yard)
		for side in [-1.0, 1.0]:
			var label = Label3D.new()
			label.text = number
			label.font_size = 128
			label.pixel_size = 0.02
			label.modulate = Color("eef0ea")
			label.outline_size = 0
			label.shaded = true
			label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			label.transform = Transform3D(
				Basis(Vector3.UP, side * PI / 2.0) * Basis(Vector3.RIGHT, -PI / 2.0),
				Vector3(side * (FIELD_WIDTH / 2.0 - 7.6), 0.07, -yard))
			add_child(label)
	down_marker = Node3D.new()
	add_child(down_marker)
	_box(down_marker, Vector3(0, 0.1, 0), Vector3(6.2, 0.04, 2.4), Color("10141f"))
	_box(down_marker, Vector3(0, 0.105, -1.0), Vector3(6.2, 0.04, 0.5), Color("ffd21f"), true)
	down_marker_label = Label3D.new()
	down_marker_label.font_size = 128
	down_marker_label.pixel_size = 0.009
	down_marker_label.outline_size = 0
	down_marker_label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	down_marker_label.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0.13, 0.25))
	down_marker.add_child(down_marker_label)
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


func _build_field_details() -> void:
	var orange = Color("ff7a1a")
	for x in [-FIELD_WIDTH / 2.0, FIELD_WIDTH / 2.0]:
		for z in [0.0, -10.0, -110.0, -120.0]:
			_box(self, Vector3(x, 0.32, z), Vector3(0.14, 0.6, 0.14), orange)
			_box(self, Vector3(x, 0.45, z), Vector3(0.15, 0.08, 0.15), Color("f2f2f2"))
	var arrows: Array = []
	for yard in range(20, 101, 10):
		if yard == 60:
			continue
		var toward = 1.0 if yard < 60 else -1.0
		for side in [-1.0, 1.0]:
			var x = side * (FIELD_WIDTH / 2.0 - 7.6)
			var tip = -float(yard) + toward * 2.3
			for step in 3:
				var width = 0.5 - float(step) * 0.16
				arrows.append({"pos": Vector3(x, 0.07, tip - toward * float(step) * 0.16), "size": Vector3(width, 0.02, 0.16)})
	for z in [-12.0, -108.0]:
		arrows.append({"pos": Vector3(0, 0.06, z), "size": Vector3(0.9, 0.025, 0.12)})
	_add_multibox(arrows, Color("eef0ea"))
	for z in [-121.0, 1.0]:
		_box(self, Vector3(0, 1.2, z), Vector3(0.7, 2.4, 0.7), Color("1d2a4a"))
		_box(self, Vector3(0, 2.35, z), Vector3(0.74, 0.1, 0.74), Color("ffc819"))
		for x in [-3.08, 3.08]:
			_box(self, Vector3(x, 10.15, z), Vector3(0.1, 0.1, 0.1), Color("ffc819"))
			_box(self, Vector3(x + 0.18, 10.0, z), Vector3(0.3, 0.12, 0.04), orange, true)
	for side in [-1.0, 1.0]:
		var bench_x = side * 36.9
		for z in [-52.0, -58.0, -64.0, -70.0]:
			_box(self, Vector3(bench_x, 0.36, z), Vector3(0.62, 0.72, 0.62), orange)
			_box(self, Vector3(bench_x, 0.76, z), Vector3(0.66, 0.08, 0.66), Color("f2f2f2"))
		for z in [-48.5, -71.5]:
			_box(self, Vector3(bench_x + side * 0.4, 0.45, z), Vector3(1.2, 0.08, 2.2), Color("cfd5df"))
			for leg_z in [-0.9, 0.9]:
				_box(self, Vector3(bench_x + side * 0.4, 0.21, z + leg_z), Vector3(1.0, 0.42, 0.06), Color("4b5263"))
			for cup in 6:
				_box(self, Vector3(bench_x + side * 0.4 + (float(cup % 2) - 0.5) * 0.4, 0.57, z + (float(cup / 2) - 1.0) * 0.5),
					Vector3(0.12, 0.16, 0.12), Color("e9edf2"))
		for z in [-55.0, -66.0]:
			_box(self, Vector3(side * 37.6, 1.0, z), Vector3(0.9, 2.0, 0.9), Color("2a3140"))
			_box(self, Vector3(side * 37.6 - side * 0.46, 1.25, z), Vector3(0.04, 0.9, 0.7), Color("ff6a2a"), true)
		_box(self, Vector3(side * 35.8, 1.25, -40.5), Vector3(0.1, 2.5, 2.4), Color("e4e8ee"))
		_box(self, Vector3(side * 35.8, 0.04, -40.5), Vector3(1.6, 0.08, 2.6), Color("23293a"))
	for x in [-20.0, -14.0, -7.5, 8.0, 15.0, 21.0]:
		var spot = Vector3(x, 0.0, -124.0 - absf(x) * 0.03)
		_box(self, spot + Vector3(0, 0.42, 0), Vector3(0.5, 0.5, 0.36), Color("22252e"))
		_box(self, spot + Vector3(0, 0.86, 0), Vector3(0.34, 0.34, 0.34), SKIN_COLORS[int(absf(x)) % SKIN_COLORS.size()])
		_box(self, spot + Vector3(0, 1.06, 0), Vector3(0.38, 0.1, 0.38), Color("15171d"))
		_box(self, spot + Vector3(0, 0.12, -0.2), Vector3(0.46, 0.24, 0.5), Color("2c3240"))
		_box(self, spot + Vector3(0, 0.82, 0.3), Vector3(0.24, 0.24, 0.3), Color("0d0f14"))
		_box(self, spot + Vector3(0, 0.82, 0.68), Vector3(0.16, 0.16, 0.5), Color("e5e7ea"))
		_box(self, spot + Vector3(0, 0.82, 0.94), Vector3(0.12, 0.12, 0.02), Color("65c8ff"), true)


func _add_multibox(entries: Array, color: Color, kind: String = "block") -> void:
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
	instance.material_override = _material(color, false, false, kind)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _stand_row(row: int) -> Dictionary:
	if row < LOWER_ROWS:
		return {"out": float(row) * 0.9, "depth": 0.9, "height": 2.4 + float(row) * 0.58, "base": 0.0}
	var upper_row = float(row - LOWER_ROWS)
	return {"out": 20.5 + upper_row * 0.95, "depth": 0.95, "height": 22.5 + upper_row * 0.9, "base": 20.0}


func _new_seat(rng: RandomNumberGenerator, position: Vector3, yaw: float, row: int) -> Dictionary:
	return {
		"pos": position,
		"yaw": yaw,
		"row": row,
		"palette": rng.randi_range(0, CROWD_COLORS.size() - 1),
		"pick": rng.randf(),
		"skin": SKIN_COLORS[rng.randi_range(0, SKIN_COLORS.size() - 1)],
		"hair": HAIR_COLORS[rng.randi_range(0, HAIR_COLORS.size() - 1)],
		"style": rng.randi_range(0, 3),
		"pose": [0, 0, 0, 1, 2, 3][rng.randi_range(0, 5)],
		"finger": rng.randf() < 0.14,
		"phase": rng.randf(),
		"jump": rng.randf_range(0.35, 1.0),
		"empty": rng.randf() < 0.05,
		"lod": rng.randf(),
	}


func _build_stadium() -> void:
	var concrete = Color("2b3143")
	var dark = Color("121725")
	var rng = RandomNumberGenerator.new()
	rng.seed = 9328
	stand_seats.clear()
	var stairs: Array = []
	var chairs: Array = []
	var nosing: Array = []
	var rails: Array = []
	var total_rows = LOWER_ROWS + UPPER_ROWS
	for side in [-1.0, 1.0]:
		for row in total_rows:
			var info = _stand_row(row)
			var out: float = info["out"]
			var depth: float = info["depth"]
			var height: float = info["height"]
			var base: float = info["base"]
			var x = side * (STAND_INNER_SIDE + out + depth * 0.5)
			var z_far = -(STAND_INNER_END + out + depth)
			var z_near = 26.0
			_box(self, Vector3(x, (base + height) * 0.5, (z_near + z_far) * 0.5),
				Vector3(depth, height - base, z_near - z_far), concrete.darkened(0.14 if row % 2 else 0.0), false, "concrete")
			nosing.append({"pos": Vector3(side * (STAND_INNER_SIDE + out + 0.04), height + 0.02, (z_near + z_far) * 0.5),
				"size": Vector3(0.1, 0.06, z_near - z_far)})
			var column = 0
			var z = z_near - 0.6
			while z > -(STAND_INNER_END + out):
				var slot = column % 32
				var seat_z = z
				column += 1
				z -= SEAT_PITCH
				if slot == 15 or slot == 31:
					stairs.append({"pos": Vector3(x, height + 0.05, seat_z), "size": Vector3(depth, 0.1, SEAT_PITCH)})
					if row % 2 == 0:
						rails.append({"pos": Vector3(x, height + 0.5, seat_z), "size": Vector3(0.06, 0.9, 0.06)})
						rails.append({"pos": Vector3(x, height + 0.95, seat_z), "size": Vector3(depth * 2.0, 0.06, 0.07)})
					if slot == 15 and row == 12:
						_vomitory(Vector3(side * (STAND_INNER_SIDE + 11.7), 0, seat_z), true)
					continue
				if row >= 11 and row <= 14 and slot >= 12 and slot <= 18:
					continue
				stand_seats.append(_new_seat(rng, Vector3(x, height, seat_z), side * PI / 2.0, row))
				chairs.append({"pos": Vector3(x + side * 0.36, height + 0.3, seat_z), "size": Vector3(0.08, 0.5, 0.64)})
	for row in total_rows:
		var info = _stand_row(row)
		var out: float = info["out"]
		var depth: float = info["depth"]
		var height: float = info["height"]
		var base: float = info["base"]
		var z = -(STAND_INNER_END + out + depth * 0.5)
		var half = STAND_INNER_SIDE + out
		var color = concrete.darkened(0.14 if row % 2 else 0.0)
		var spans = [[-half, half]]
		if row <= 8:
			spans = [[-half, TUNNEL_X - 4.6], [TUNNEL_X + 4.6, half]]
		for span in spans:
			_box(self, Vector3((span[0] + span[1]) * 0.5, (base + height) * 0.5, z),
				Vector3(span[1] - span[0], height - base, depth), color, false, "concrete")
			nosing.append({"pos": Vector3((span[0] + span[1]) * 0.5, height + 0.02, z + depth * 0.5 - 0.04),
				"size": Vector3(span[1] - span[0], 0.06, 0.1)})
		var count = int((half * 2.0 - 1.0) / SEAT_PITCH)
		var start = -float(count - 1) * SEAT_PITCH * 0.5
		for column in count:
			var seat_x = start + float(column) * SEAT_PITCH
			var slot = column % 32
			if slot == 15 or slot == 31:
				stairs.append({"pos": Vector3(seat_x, height + 0.05, z), "size": Vector3(SEAT_PITCH, 0.1, depth)})
				if row % 2 == 0:
					rails.append({"pos": Vector3(seat_x, height + 0.5, z), "size": Vector3(0.06, 0.9, 0.06)})
					rails.append({"pos": Vector3(seat_x, height + 0.95, z), "size": Vector3(0.07, 0.06, depth * 2.0)})
				continue
			if row <= 9 and absf(seat_x - TUNNEL_X) < 5.6:
				continue
			stand_seats.append(_new_seat(rng, Vector3(seat_x, height, z), PI, row))
			chairs.append({"pos": Vector3(seat_x, height + 0.3, z - 0.36), "size": Vector3(0.64, 0.5, 0.08)})
	_add_multibox(stairs, Color("59627a"), "concrete")
	_add_multibox(chairs, Color("1d2b50"), "fabric")
	_add_multibox(nosing, Color("8d96ab"))
	_add_multibox(rails, Color("a8b0c0"))
	_build_suites_and_rails()
	_team_tunnel(TUNNEL_X)
	var top_out = 20.5 + float(UPPER_ROWS) * 0.95
	var back_length = 26.0 + STAND_INNER_END + top_out + 1.0
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * (STAND_INNER_SIDE + top_out + 0.5), 26.0, 26.0 - back_length * 0.5),
			Vector3(1.0, 52.0, back_length), dark)
		_box(self, Vector3(side * (STAND_INNER_SIDE + 20.25), 21.25, 26.0 - (back_length - 24.0) * 0.5),
			Vector3(0.5, 2.6, back_length - 24.0), dark)
		_box(self, Vector3(side * (STAND_INNER_SIDE + 37.5), 52.5, 26.0 - back_length * 0.5),
			Vector3(17.0, 1.0, back_length), dark)
		var strip_length = 26.0 + STAND_INNER_END + 29.2
		_box(self, Vector3(side * (STAND_INNER_SIDE + 29.2), 51.85, 26.0 - strip_length * 0.5),
			Vector3(0.4, 0.3, strip_length), Color("dfe9ff"), true)
		for light_z in [-15.0, -62.0, -110.0]:
			var lamp = Vector3(side * (STAND_INNER_SIDE + 29.4), 50.6, light_z)
			_light_bank(lamp, true)
			_spotlight(lamp, Vector3(-side * 8.0, 0.0, light_z), Color("dce8ff"))
	var end_half = STAND_INNER_SIDE + top_out + 1.0
	_box(self, Vector3(0, 26.0, -(STAND_INNER_END + top_out + 0.5)), Vector3(end_half * 2.0, 52.0, 1.0), dark)
	_box(self, Vector3(0, 21.25, -(STAND_INNER_END + 20.25)), Vector3((STAND_INNER_SIDE + 20.5) * 2.0, 2.6, 0.5), dark)
	_box(self, Vector3(0, 52.5, -(STAND_INNER_END + 37.5)), Vector3(end_half * 2.0, 1.0, 17.0), dark)
	_box(self, Vector3(0, 51.85, -(STAND_INNER_END + 29.2)), Vector3((STAND_INNER_SIDE + 29.4) * 2.0, 0.3, 0.4), Color("dfe9ff"), true)
	for light_x in [-30.0, 30.0]:
		var lamp = Vector3(light_x, 50.6, -(STAND_INNER_END + 29.4))
		_light_bank(lamp, false)
		_spotlight(lamp, Vector3(light_x * 0.25, 0.0, -95.0), Color("d8e5ff"))
	_build_jumbotron()
	for z in [-121.0, 1.0]:
		var yellow = Color("ffc819")
		_box(self, Vector3(0, 1.5, z), Vector3(0.35, 3, 0.35), yellow)
		_box(self, Vector3(0, 3.05, z), Vector3(6.2, 0.2, 0.2), yellow)
		for x in [-3.08, 3.08]:
			_box(self, Vector3(x, 6.5, z), Vector3(0.17, 7, 0.17), yellow)


func _build_suites_and_rails() -> void:
	var lower_top = _stand_row(LOWER_ROWS - 1)
	var suite_out: float = lower_top["out"] + 1.0
	var glass = _material(Color(0.62, 0.8, 1.0, 0.18), false, true)
	var windows: Array = []
	var mullions: Array = []
	for side in [-1.0, 1.0]:
		var x = side * (STAND_INNER_SIDE + suite_out)
		var length = 26.0 + STAND_INNER_END + suite_out
		var mid_z = 26.0 - length * 0.5
		_box(self, Vector3(x + side * 0.4, 18.5, mid_z), Vector3(0.8, 3.1, length), Color("151b2a"), false, "concrete")
		windows.append({"pos": Vector3(x - side * 0.02, 18.6, mid_z), "size": Vector3(0.05, 1.6, length)})
		var z = 25.0
		while z > -(STAND_INNER_END + suite_out):
			mullions.append({"pos": Vector3(x - side * 0.06, 18.6, z), "size": Vector3(0.08, 1.7, 0.14)})
			z -= 3.2
		var rail_x = side * (STAND_INNER_SIDE + 20.45)
		var rail_length = 26.0 + STAND_INNER_END + 20.5
		var glass_panel = _box(self, Vector3(rail_x, 23.15, 26.0 - rail_length * 0.5), Vector3(0.05, 0.9, rail_length), Color.WHITE)
		glass_panel.material_override = glass
		_box(self, Vector3(rail_x, 23.62, 26.0 - rail_length * 0.5), Vector3(0.1, 0.07, rail_length), Color("b7bfcf"))
	var end_z = -(STAND_INNER_END + suite_out)
	var end_width = (STAND_INNER_SIDE + suite_out) * 2.0
	_box(self, Vector3(0, 18.5, end_z - 0.4), Vector3(end_width, 3.1, 0.8), Color("151b2a"), false, "concrete")
	windows.append({"pos": Vector3(0, 18.6, end_z + 0.02), "size": Vector3(end_width, 1.6, 0.05)})
	var x_step = -end_width * 0.5
	while x_step < end_width * 0.5:
		mullions.append({"pos": Vector3(x_step, 18.6, end_z + 0.06), "size": Vector3(0.14, 1.7, 0.08)})
		x_step += 3.2
	var end_rail_z = -(STAND_INNER_END + 20.45)
	var end_glass = _box(self, Vector3(0, 23.15, end_rail_z), Vector3((STAND_INNER_SIDE + 20.5) * 2.0, 0.9, 0.05), Color.WHITE)
	end_glass.material_override = glass
	_box(self, Vector3(0, 23.62, end_rail_z), Vector3((STAND_INNER_SIDE + 20.5) * 2.0, 0.07, 0.1), Color("b7bfcf"))
	var window_mesh = BoxMesh.new()
	window_mesh.size = Vector3.ONE
	var window_multi = MultiMesh.new()
	window_multi.transform_format = MultiMesh.TRANSFORM_3D
	window_multi.mesh = window_mesh
	window_multi.instance_count = windows.size()
	for i in windows.size():
		window_multi.set_instance_transform(i, Transform3D(Basis().scaled(windows[i]["size"]), windows[i]["pos"]))
	var window_instance = MultiMeshInstance3D.new()
	window_instance.multimesh = window_multi
	window_instance.material_override = _material(Color("ffd9a0"), true)
	add_child(window_instance)
	_add_multibox(mullions, Color("0b0f18"))


func _vomitory(front: Vector3, side_stand: bool) -> void:
	var side = signf(front.x)
	var size = Vector3(3.6, 2.6, 6.4) if side_stand else Vector3(6.4, 2.6, 3.6)
	_box(self, Vector3(front.x, 9.2, front.z), size, Color("05070c"))
	_box(self, Vector3(front.x - side * 1.8, 10.6, front.z), Vector3(0.3, 0.3, 6.8), Color("6c7590"))
	for edge in [-3.3, 3.3]:
		_box(self, Vector3(front.x, 9.4, front.z + edge), Vector3(3.6, 3.0, 0.3), Color("3b4256"))


func _team_tunnel(tunnel_x: float) -> void:
	var front = -(STAND_INNER_END - 1.7)
	var back = -(STAND_INNER_END + 8.6)
	var center = (front + back) * 0.5
	var length = front - back
	var concrete = Color("272d3e")
	for edge in [-1.0, 1.0]:
		_box(self, Vector3(tunnel_x + edge * 4.6, 3.65, center), Vector3(1.8, 7.3, length), concrete)
	_box(self, Vector3(tunnel_x, 6.6, center), Vector3(7.4, 1.4, length), concrete)
	_box(self, Vector3(tunnel_x, 0.02, center), Vector3(7.4, 0.04, length), Color("1c202b"))
	_box(self, Vector3(tunnel_x, 2.95, back + 0.2), Vector3(7.4, 5.9, 0.4), Color("27324c"), true)
	_box(self, Vector3(tunnel_x, 5.82, center), Vector3(0.35, 0.1, length - 0.6), Color("fff1c9"), true)


func _build_jumbotron() -> void:
	var frame = Color("0e1422")
	var z = -(STAND_INNER_END + 20.5) + 1.2
	_box(self, Vector3(0, 29.5, z), Vector3(32.0, 13.0, 1.4), frame)
	_box(self, Vector3(0, 29.5, z + 0.74), Vector3(30.0, 11.0, 0.08), Color("0f2436"), true)
	_box(self, Vector3(0, 36.25, z + 0.2), Vector3(32.4, 0.5, 1.6), Color("29d8f2"), true)
	_box(self, Vector3(0, 22.75, z + 0.2), Vector3(32.4, 0.5, 1.6), Color("29d8f2"), true)
	for x in [-12.0, 12.0]:
		_box(self, Vector3(x, 44.5, z - 0.6), Vector3(0.25, 16.0, 0.25), Color("1b2130"))
	jumbo_title = _jumbo_label("BLOCK BOWL", 128, 0.02, Vector3(0, 33.3, z + 0.8), Color("e9f8ff"))
	jumbo_score = _jumbo_label("HOME 0 - 0 AWAY", 128, 0.022, Vector3(0, 29.4, z + 0.8), Color("ffd66b"))
	jumbo_clock = _jumbo_label("Q1  3:00", 96, 0.02, Vector3(0, 25.6, z + 0.8), Color("66efff"))


func _jumbo_label(text: String, font_size: int, pixel_size: float, position: Vector3, color: Color) -> Label3D:
	var label = Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.position = position
	add_child(label)
	return label


func _light_bank(center: Vector3, side_facing: bool) -> void:
	var frame_size = Vector3(0.6, 2.6, 9.0) if side_facing else Vector3(9.0, 2.6, 0.6)
	_box(self, center, frame_size, Color("202633"))
	for i in 6:
		var offset = (float(i) - 2.5) * 1.45
		for level in [-0.6, 0.6]:
			var lamp_pos = center + (Vector3(0, level, offset) if side_facing else Vector3(offset, level, 0))
			var lamp_size = Vector3(0.75, 0.95, 1.15) if side_facing else Vector3(1.15, 0.95, 0.75)
			_box(self, lamp_pos, lamp_size, Color("fff7d5"), true)
	var flare = MeshInstance3D.new()
	var flare_quad = QuadMesh.new()
	flare_quad.size = Vector2(30, 30)
	flare.mesh = flare_quad
	flare.material_override = flare_material
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inward = Vector3(-signf(center.x) * 1.8, -0.6, 0) if side_facing else Vector3(0, -0.6, 1.8)
	flare.position = center + inward
	add_child(flare)


func _build_atmosphere() -> void:
	var vignette_layer = CanvasLayer.new()
	vignette_layer.layer = -1
	add_child(vignette_layer)
	var vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette_material = ShaderMaterial.new()
	var vignette_shader = Shader.new()
	vignette_shader.code = VIGNETTE_SHADER
	vignette_material.shader = vignette_shader
	vignette.material = vignette_material
	vignette_layer.add_child(vignette)
	var motes = GPUParticles3D.new()
	motes.amount = 900
	motes.lifetime = 14.0
	motes.preprocess = 14.0
	motes.visibility_aabb = AABB(Vector3(-60, -2, -100), Vector3(120, 50, 200))
	motes.position = Vector3(0, 0, -60)
	var mote_process = ParticleProcessMaterial.new()
	mote_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mote_process.emission_box_extents = Vector3(48, 18, 82)
	mote_process.emission_shape_offset = Vector3(0, 19, 0)
	mote_process.direction = Vector3(0.3, -0.1, 0.2)
	mote_process.spread = 180.0
	mote_process.initial_velocity_min = 0.05
	mote_process.initial_velocity_max = 0.35
	mote_process.gravity = Vector3(0.05, -0.02, 0)
	mote_process.turbulence_enabled = true
	mote_process.turbulence_noise_strength = 0.4
	mote_process.turbulence_noise_scale = 6.0
	var twinkle = Gradient.new()
	twinkle.set_color(0, Color(0.85, 0.9, 1.0, 0.0))
	twinkle.add_point(0.25, Color(0.85, 0.9, 1.0, 0.5))
	twinkle.add_point(0.75, Color(1.0, 0.95, 0.85, 0.45))
	twinkle.set_color(twinkle.get_point_count() - 1, Color(1.0, 0.95, 0.85, 0.0))
	var twinkle_texture = GradientTexture1D.new()
	twinkle_texture.gradient = twinkle
	mote_process.color_ramp = twinkle_texture
	motes.process_material = mote_process
	var mote_mesh = QuadMesh.new()
	mote_mesh.size = Vector2.ONE * 0.09
	var mote_material = StandardMaterial3D.new()
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mote_material.vertex_color_use_as_albedo = true
	var mote_gradient = Gradient.new()
	mote_gradient.set_color(0, Color(1, 1, 1, 1))
	mote_gradient.set_color(1, Color(1, 1, 1, 0))
	var mote_texture = GradientTexture2D.new()
	mote_texture.gradient = mote_gradient
	mote_texture.fill = GradientTexture2D.FILL_RADIAL
	mote_texture.fill_from = Vector2(0.5, 0.5)
	mote_texture.fill_to = Vector2(1.0, 0.5)
	mote_texture.width = 32
	mote_texture.height = 32
	mote_material.albedo_texture = mote_texture
	mote_mesh.material = mote_material
	motes.draw_pass_1 = mote_mesh
	add_child(motes)
	mist_root = Node3D.new()
	add_child(mist_root)
	var rng = RandomNumberGenerator.new()
	rng.seed = 5521
	var mist_mesh = QuadMesh.new()
	mist_mesh.size = Vector2.ONE
	mist_mesh.orientation = PlaneMesh.FACE_Y
	var mist_multi = MultiMesh.new()
	mist_multi.transform_format = MultiMesh.TRANSFORM_3D
	mist_multi.use_custom_data = true
	mist_multi.mesh = mist_mesh
	mist_multi.instance_count = 46
	for i in mist_multi.instance_count:
		var size = rng.randf_range(26.0, 48.0)
		var spot: Vector3
		if i < 18:
			spot = Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(0.6, 2.2), -rng.randf_range(-8.0, 130.0))
		else:
			var side = -1.0 if i % 2 == 0 else 1.0
			spot = Vector3(side * rng.randf_range(36.0, 52.0), rng.randf_range(5.0, 24.0), -rng.randf_range(-10.0, 140.0))
			if i % 7 == 0:
				spot = Vector3(rng.randf_range(-45.0, 45.0), rng.randf_range(5.0, 26.0), -rng.randf_range(126.0, 150.0))
		var basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(size, 1.0, size * rng.randf_range(0.5, 0.9)))
		mist_multi.set_instance_transform(i, Transform3D(basis, spot))
		mist_multi.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var mist = MultiMeshInstance3D.new()
	mist.multimesh = mist_multi
	mist.material_override = mist_material
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mist_root.add_child(mist)
	for spot in [Vector3(26, 3.2, -126.0), Vector3(-38.0, 18.6, -60.0), Vector3(38.0, 18.6, -60.0), Vector3(0, 18.6, -130.0)]:
		var glow = OmniLight3D.new()
		glow.position = spot
		glow.light_color = Color("ffb867")
		glow.light_energy = 1.6 if spot.y < 10.0 else 1.1
		glow.omni_range = 14.0 if spot.y < 10.0 else 22.0
		glow.shadow_enabled = false
		add_child(glow)
	var rim = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-14, 180, 0)
	rim.light_color = Color("6f86c9")
	rim.light_energy = 0.32
	rim.shadow_enabled = false
	add_child(rim)


func _light_shaft(origin: Vector3, target: Vector3, width: float) -> void:
	var length = origin.distance_to(target)
	var cone = CylinderMesh.new()
	cone.top_radius = width * 0.25
	cone.bottom_radius = width * 2.6
	cone.height = 1.0
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var shaft = MeshInstance3D.new()
	shaft.mesh = cone
	shaft.material_override = shaft_material
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var forward = (target - origin).normalized()
	var axis_y = -forward
	var axis_x = axis_y.cross(Vector3.FORWARD if absf(axis_y.z) < 0.9 else Vector3.RIGHT).normalized()
	var axis_z = axis_x.cross(axis_y).normalized()
	var radial_scale = length / 70.0
	shaft.transform = Transform3D(
		Basis(axis_x * radial_scale * 6.0, axis_y * length, axis_z * radial_scale * 6.0),
		(origin + target) * 0.5)
	add_child(shaft)


func _spotlight(position: Vector3, target: Vector3, color: Color) -> void:
	_light_shaft(position, target, 1.0)
	var light = SpotLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = 13.0
	light.spot_range = 150.0
	light.spot_angle = 62.0
	light.spot_angle_attenuation = 1.2
	light.shadow_enabled = false
	add_child(light)
	light.look_at(target, Vector3.UP)
	stadium_spots.append({"light": light, "color": color})


func _build_dressing() -> void:
	for child in dressing_root.get_children():
		child.queue_free()
	clock_labels.clear()
	var home: Dictionary = game.home
	var away: Dictionary = game.away
	var home_color: Color = home["primary"]
	var away_color: Color = away["primary"]
	var home_name = ("%s %s" % [home["city"], home["nickname"]]).to_upper()
	var away_name = ("%s %s" % [away["city"], away["nickname"]]).to_upper()
	for z in [-5.0, -115.0]:
		_box(dressing_root, Vector3(0, 0.03, z), Vector3(FIELD_WIDTH, 0.025, 10), home_color.darkened(0.18))
		var nickname = String(home["nickname"]).to_upper()
		_flat_label(nickname, Vector3(0, 0.07, z), minf(0.052, 40.0 / (float(nickname.length()) * 80.0)), Color("f4f4ee"), 0.0)
	var logo = _box(dressing_root, Vector3(0, 0.035, -60), Vector3(7.5, 0.02, 7.5), home_color)
	logo.rotation.y = PI / 4.0
	_box(dressing_root, Vector3(0, 0.04, -60), Vector3(6.3, 0.02, 6.3), home_color.darkened(0.3)).rotation.y = PI / 4.0
	_flat_label(home["abbr"], Vector3(0, 0.075, -60), 0.028, home["secondary"].lightened(0.2), 0.0)
	var wall = Color("121827")
	var cap = Color("4c566f")
	var wall_length = 26.0 + STAND_INNER_END
	for side in [-1.0, 1.0]:
		_box(dressing_root, Vector3(side * (STAND_INNER_SIDE - 0.85), 1.3, 26.0 - wall_length * 0.5),
			Vector3(1.7, 2.6, wall_length), wall)
		_box(dressing_root, Vector3(side * (STAND_INNER_SIDE - 0.85), 2.66, 26.0 - wall_length * 0.5),
			Vector3(1.8, 0.12, wall_length), cap)
		var yaw = -side * PI / 2.0
		for i in 15:
			var z = 21.2 - float(i) * 9.6
			var center = Vector3(side * (STAND_INNER_SIDE - 1.73), 1.3, z)
			if i == 3 or i == 8 or i == 13:
				clock_labels.append(_ad_panel(center, 9.0, 1.9, yaw, Color("05070b"), "Q1  3:00", Color("ffb627")))
			elif i % 4 == 0:
				_ad_panel(center, 9.0, 1.9, yaw, home_color.darkened(0.25), home_name, Color("f6f6f6"))
			elif i % 4 == 2:
				_ad_panel(center, 9.0, 1.9, yaw, away_color.darkened(0.25), away_name, Color("f6f6f6"))
			else:
				var ad = (i + int(side + 1.0)) % ADS.size()
				_ad_panel(center, 9.0, 1.9, yaw, AD_COLORS[ad % AD_COLORS.size()].darkened(0.2), ADS[ad], Color("fff8e6"))
		var ribbon_length = 26.0 + STAND_INNER_END + 20.5
		var ribbon_x = side * (STAND_INNER_SIDE + 19.98)
		_box(dressing_root, Vector3(ribbon_x, 21.25, 26.0 - ribbon_length * 0.5),
			Vector3(0.06, 2.1, ribbon_length), home_color.darkened(0.55), true)
		for i in 6:
			var z = 12.0 - float(i) * 27.0
			var text = home_name if i % 2 == 0 else ADS[(i * 3 + int(side + 1.0)) % ADS.size()]
			_panel_label(Vector3(ribbon_x - side * 0.05, 21.25, z), text, 1.5, 22.0, yaw, Color("dff6ff"))
	var end_z = -(STAND_INNER_END - 0.85)
	var segments = [
		[-STAND_INNER_SIDE, TUNNEL_X - 4.6], [TUNNEL_X + 4.6, STAND_INNER_SIDE],
	]
	for segment in segments:
		var width = segment[1] - segment[0]
		var mid = (segment[0] + segment[1]) * 0.5
		_box(dressing_root, Vector3(mid, 1.3, end_z), Vector3(width, 2.6, 1.7), wall)
		_box(dressing_root, Vector3(mid, 2.66, end_z), Vector3(width, 0.12, 1.8), cap)
	var end_front = -(STAND_INNER_END - 1.73)
	_ad_panel(Vector3(-11.0, 1.3, end_front), 19.0, 1.9, 0.0, home_color.darkened(0.25), home_name, Color("f6f6f6"))
	clock_labels.append(_ad_panel(Vector3(0, 1.3, end_front + 0.01), 3.2, 1.9, 0.0, Color("05070b"), "Q1  3:00", Color("ffb627")))
	_ad_panel(Vector3(11.0, 1.3, end_front), 19.0, 1.9, 0.0, AD_COLORS[0].darkened(0.2), ADS[0], Color("fff8e6"))
	_ad_panel(Vector3(-26.0, 1.3, end_front), 9.0, 1.9, 0.0, away_color.darkened(0.25), away_name, Color("f6f6f6"))
	for x in [-34.8, 34.8]:
		_ad_panel(Vector3(x, 1.3, end_front), 7.0, 1.9, 0.0, AD_COLORS[2].darkened(0.2), ADS[3], Color("fff8e6"))
	var end_ribbon_z = -(STAND_INNER_END + 19.98)
	_box(dressing_root, Vector3(0, 21.25, end_ribbon_z), Vector3((STAND_INNER_SIDE + 20.5) * 2.0, 2.1, 0.06),
		home_color.darkened(0.55), true)
	for x in [-38.0, 38.0]:
		_panel_label(Vector3(x, 21.25, end_ribbon_z + 0.05), home_name, 1.5, 34.0, 0.0, Color("dff6ff"))
	for edge in [-1.0, 1.0]:
		_box(dressing_root, Vector3(TUNNEL_X + edge * 4.15, 3.3, end_front + 0.1), Vector3(0.9, 6.6, 0.5), home_color)
	_box(dressing_root, Vector3(TUNNEL_X, 7.0, end_front + 0.1), Vector3(9.2, 1.4, 0.5), home_color.darkened(0.15))
	_panel_label(Vector3(TUNNEL_X, 7.0, end_front + 0.37), String(home["nickname"]).to_upper(), 1.0, 8.4, 0.0, home["secondary"].lightened(0.35))
	_box(dressing_root, Vector3(TUNNEL_X, 6.2, end_front + 0.36), Vector3(8.0, 0.12, 0.08), Color("fff3c8"), true)
	_build_crowd(home, away)


func _flat_label(text: String, position: Vector3, pixel_size: float, color: Color, yaw: float) -> Label3D:
	var label = Label3D.new()
	label.text = text
	label.font_size = 128
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI / 2.0), position)
	dressing_root.add_child(label)
	return label


func _panel_label(position: Vector3, text: String, height: float, width: float, yaw: float, color: Color) -> Label3D:
	var label = Label3D.new()
	label.text = text
	var font_size = 22
	label.font_size = font_size
	label.pixel_size = minf(height * 0.6 / font_size, width * 0.9 / (maxf(float(text.length()), 1.0) * font_size * 0.62))
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.alpha_scissor_threshold = 0.45
	label.modulate = color
	label.outline_size = 0
	label.position = position
	label.rotation.y = yaw
	dressing_root.add_child(label)
	return label


func _ad_panel(center: Vector3, width: float, height: float, yaw: float, color: Color, text: String, text_color: Color) -> Label3D:
	var panel = _box(dressing_root, center, Vector3(width, height, 0.06), color, true)
	panel.rotation.y = yaw
	return _panel_label(center + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.05), text, height, width, yaw, text_color)


func _update_displays() -> void:
	var seconds = maxi(0, int(ceil(game.clock)))
	var clock_text = "Q%d  %d:%02d" % [game.quarter, int(seconds / 60), seconds % 60]
	var score_text = "%s %d - %d %s" % [game.home["abbr"], game.home_score, game.away_score, game.away["abbr"]]
	if clock_text == last_clock_text and score_text == jumbo_score.text:
		return
	last_clock_text = clock_text
	for label in clock_labels:
		label.text = clock_text
	jumbo_clock.text = clock_text
	jumbo_score.text = score_text
	jumbo_title.text = String(game.home["nickname"]).to_upper()


func _crowd_color_index(seat: Dictionary) -> int:
	var pick: float = seat["pick"]
	if pick < 0.36:
		return CROWD_COLORS.size()
	if pick < 0.46:
		return CROWD_COLORS.size() + 1
	if pick < 0.54:
		return CROWD_COLORS.size() + 2
	if pick < 0.64:
		return CROWD_COLORS.size() + 3
	return seat["palette"]


func _build_crowd(home: Dictionary, away: Dictionary) -> void:
	var colors: Array = CROWD_COLORS.duplicate()
	colors.append_array([home["primary"], home["secondary"], Color("eef0f2"), away["primary"]])
	var close_seats: Array = []
	var medium_seats: Array = []
	var far_groups: Array = []
	for unused in colors.size():
		far_groups.append([])
	for seat in stand_seats:
		if seat["empty"]:
			continue
		var row: int = seat["row"]
		var lod: float = seat["lod"]
		# Randomly dither each tier boundary so detail falls off fan by fan instead of row by row.
		var close_limit = 2.0 + lod * 6.0
		var medium_limit = 9.0 + fmod(lod * 7.31, 1.0) * 12.0
		if float(row) < close_limit and fmod(lod * 13.7, 1.0) > float(row) * 0.09:
			close_seats.append(seat)
		elif float(row) < medium_limit or (row < LOWER_ROWS and fmod(lod * 29.3, 1.0) < 0.12):
			medium_seats.append(seat)
		else:
			far_groups[_crowd_color_index(seat)].append(seat)
	_add_crowd_people(close_seats, true, colors, home["secondary"])
	_add_crowd_people(medium_seats, false, colors, home["secondary"])
	for index in far_groups.size():
		_add_crowd_billboards(far_groups[index], colors[index])


func _crowd_brightness(position: Vector3) -> float:
	var outside_x = maxf(absf(position.x) - FIELD_WIDTH / 2.0, 0.0)
	var outside_z = maxf(absf(position.z + 60.0) - 60.0, 0.0)
	var stand_distance = Vector2(outside_x, outside_z).length()
	var fade = clampf((stand_distance - 8.0) / 60.0, 0.0, 0.5)
	fade += clampf(position.y / 55.0, 0.0, 0.22)
	return 1.0 - fade


func _person_parts(seat: Dictionary, shirt: Color, detailed: bool, accent: Color) -> Array:
	var skin: Color = seat["skin"]
	var hair: Color = seat["hair"]
	var pick: float = seat["pick"]
	var pants = Color("2b3550") if pick > 0.5 else shirt.darkened(0.7)
	var style: int = seat["style"]
	var pose: int = seat["pose"]
	var hidden = [Vector3.ZERO, Vector3.ZERO, shirt]
	var up = [pose == 1 or pose == 3, pose == 2 or pose == 3]
	var parts: Array = []
	parts.append([Vector3(0.46, 0.66, 0.24), Vector3(0, 1.01, 0), shirt])
	parts.append([Vector3(0.44, 0.44, 0.44), Vector3(0, 1.57, 0), skin])
	if style == 2:
		parts.append([Vector3(0.47, 0.13, 0.47), Vector3(0, 1.82, 0), shirt])
	elif style == 3:
		parts.append([Vector3(0.45, 0.05, 0.45), Vector3(0, 1.8, 0), hair])
	else:
		parts.append([Vector3(0.47, 0.11, 0.47), Vector3(0, 1.81, 0), hair])
	if not detailed:
		parts.append([Vector3(0.44, 0.68, 0.24), Vector3(0, 0.34, 0), pants])
		for i in 2:
			var side = -1.0 if i == 0 else 1.0
			var y = 1.67 if up[i] else 1.01
			parts.append([Vector3(0.22, 0.66, 0.22), Vector3(side * 0.34, y, 0), shirt])
		return parts
	if style == 0 or style == 1:
		var back_height = 0.3 if style == 0 else 0.46
		parts.append([Vector3(0.47, back_height, 0.06), Vector3(0, 1.79 - back_height * 0.5, 0.215), hair])
	else:
		parts.append(hidden)
	if style == 2:
		parts.append([Vector3(0.4, 0.04, 0.16), Vector3(0, 1.77, -0.29), shirt.darkened(0.25)])
	else:
		parts.append(hidden)
	for side in [-1.0, 1.0]:
		parts.append([Vector3(0.1, 0.07, 0.02), Vector3(side * 0.1, 1.6, -0.225), Color("f4f4f4")])
	for side in [-1.0, 1.0]:
		parts.append([Vector3(0.05, 0.07, 0.03), Vector3(side * 0.075, 1.6, -0.228), Color("1f2033")])
	parts.append([Vector3(0.16, 0.035, 0.02), Vector3(0, 1.46, -0.225), Color("6b3a32")])
	if pick < 0.6:
		parts.append([Vector3(0.465, 0.08, 0.245), Vector3(0, 1.16, 0), shirt.lightened(0.45)])
	else:
		parts.append(hidden)
	for i in 2:
		var side = -1.0 if i == 0 else 1.0
		var sleeve_y = 1.49 if up[i] else 1.19
		var forearm_y = 1.82 if up[i] else 0.86
		parts.append([Vector3(0.22, 0.3, 0.22), Vector3(side * 0.34, sleeve_y, 0), shirt])
		parts.append([Vector3(0.21, 0.36, 0.21), Vector3(side * 0.34, forearm_y, 0), skin])
	for side in [-1.0, 1.0]:
		parts.append([Vector3(0.22, 0.6, 0.23), Vector3(side * 0.11, 0.38, 0), pants])
	for side in [-1.0, 1.0]:
		parts.append([Vector3(0.23, 0.1, 0.28), Vector3(side * 0.11, 0.05, -0.025), Color("15161c")])
	if seat["finger"] and up[1]:
		parts.append([Vector3(0.18, 0.42, 0.08), Vector3(0.34, 2.2, 0), accent])
	else:
		parts.append(hidden)
	return parts


func _add_crowd_people(seats: Array, detailed: bool, colors: Array, accent: Color) -> void:
	if seats.is_empty():
		return
	var mesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	var part_count = 20 if detailed else 6
	var multimeshes: Array = []
	for j in part_count:
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = mesh
		multimesh.instance_count = seats.size()
		multimeshes.append(multimesh)
		var crowd = MultiMeshInstance3D.new()
		crowd.multimesh = multimesh
		crowd.material_override = crowd_material
		crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dressing_root.add_child(crowd)
	for i in seats.size():
		var seat: Dictionary = seats[i]
		var seat_position: Vector3 = seat["pos"]
		var basis = Basis(Vector3.UP, seat["yaw"])
		var brightness = _crowd_brightness(seat_position)
		var custom = Color(seat["phase"], seat["jump"], 0.0, 0.0)
		var parts = _person_parts(seat, colors[_crowd_color_index(seat)], detailed, accent)
		for j in part_count:
			var part: Array = parts[j]
			var multimesh: MultiMesh = multimeshes[j]
			var color: Color = part[2]
			multimesh.set_instance_transform(i, Transform3D(basis * Basis().scaled(part[0]), seat_position + basis * part[1]))
			multimesh.set_instance_color(i, Color(color.r * brightness, color.g * brightness, color.b * brightness))
			multimesh.set_instance_custom_data(i, custom)


func _add_crowd_billboards(seats: Array, shirt: Color) -> void:
	if seats.is_empty():
		return
	var image = Image.create(12, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
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
	mesh.size = Vector2(0.85, 1.7)
	var material = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
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
		multimesh.set_instance_transform(i, Transform3D(Basis(), seat_position + Vector3(0, 0.86, 0)))
		var brightness = _crowd_brightness(seat_position) * 0.82
		multimesh.set_instance_color(i, Color(brightness, brightness, brightness))
	var crowd = MultiMeshInstance3D.new()
	crowd.multimesh = multimesh
	crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dressing_root.add_child(crowd)


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
	var jersey: Color = Color("eef0f2") if side > 0.0 else team["primary"]
	var pants: Color = Color("111825") if coaches else (Color("d5d9e0") if side > 0.0 else team["primary"].darkened(0.62))
	var trim: Color = team["primary"] if side > 0.0 else team["secondary"]
	var helmet: Color = team["primary"].darkened(0.2) if side > 0.0 else team["primary"]
	var mask = Color("c9ced8")
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
			{"size": Vector3(0.62, 0.72, 0.38), "offset": Vector3(0, 1.04, 0), "color": jersey},
			{"size": Vector3(0.82, 0.18, 0.44), "offset": Vector3(0, 1.43, 0), "color": jersey},
			{"size": Vector3(0.52, 0.16, 0.34), "offset": Vector3(0, 0.68, 0), "color": pants},
			{"size": Vector3(0.38, 0.38, 0.38), "offset": Vector3(0, 1.78, 0), "color": "skin"},
			{"size": Vector3(0.84, 0.05, 0.18), "offset": Vector3(0, 1.43, 0), "color": trim},
			{"size": Vector3(0.46, 0.37, 0.44), "offset": Vector3(0, 1.81, 0), "color": helmet},
			{"size": Vector3(0.08, 0.025, 0.45), "offset": Vector3(0, 2.0, 0), "color": trim},
			{"size": Vector3(0.38, 0.035, 0.06), "offset": Vector3(0, 1.72, -0.24), "color": mask},
			{"size": Vector3(0.38, 0.035, 0.06), "offset": Vector3(0, 1.8, -0.24), "color": mask},
			{"size": Vector3(0.2, 0.52, 0.23), "offset": Vector3(-0.43, 1.11, 0), "color": jersey, "arm": -1},
			{"size": Vector3(0.2, 0.52, 0.23), "offset": Vector3(0.43, 1.11, 0), "color": jersey, "arm": 1},
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


func _make_player(p: Dictionary, team: Dictionary, away: bool) -> Dictionary:
	var root = Node3D.new()
	player_root.add_child(root)
	var primary: Color = team["primary"]
	var secondary: Color = team["secondary"]
	var jersey = Color("eef0f2") if away else primary
	var pants = Color("d5d9e0") if away else primary.darkened(0.62)
	var trim = primary if away else secondary
	var helmet = primary.darkened(0.2) if away else primary
	var mask = Color("c9ced8")
	var skin: Color = SKIN_COLORS[p["id"] % SKIN_COLORS.size()]
	_box(root, Vector3(0, 1.31, 0), Vector3(0.72, 0.55, 0.44), jersey)
	_box(root, Vector3(0, 1.58, 0), Vector3(1.0, 0.24, 0.54), jersey)
	_box(root, Vector3(0, 1.58, 0), Vector3(1.02, 0.06, 0.2), trim)
	_box(root, Vector3(0, 1.04, 0), Vector3(0.68, 0.18, 0.4), pants)
	_box(root, Vector3(0, 1.94, 0), Vector3(0.5, 0.46, 0.52), helmet)
	_box(root, Vector3(0, 2.18, 0), Vector3(0.1, 0.035, 0.53), trim)
	_box(root, Vector3(0, 1.88, -0.25), Vector3(0.34, 0.24, 0.035), skin)
	_box(root, Vector3(0, 1.8, -0.3), Vector3(0.42, 0.04, 0.07), mask)
	_box(root, Vector3(0, 1.9, -0.3), Vector3(0.42, 0.04, 0.07), mask)
	for x in [-0.11, 0.11]:
		_box(root, Vector3(x, 1.85, -0.3), Vector3(0.04, 0.16, 0.07), mask)
	var dark = Color("13151c")
	_box(root, Vector3(0, 1.72, 0), Vector3(0.84, 0.08, 0.5), jersey.darkened(0.08))
	_box(root, Vector3(0, 1.71, -0.2), Vector3(0.26, 0.06, 0.1), dark)
	_box(root, Vector3(0, 0.96, 0), Vector3(0.7, 0.07, 0.42), dark)
	_box(root, Vector3(0, 0.96, -0.215), Vector3(0.12, 0.06, 0.02), Color("c9ced8"))
	_box(root, Vector3(0, 1.31, -0.225), Vector3(0.6, 0.03, 0.02), jersey.darkened(0.12))
	for x in [-0.26, 0.26]:
		_box(root, Vector3(x, 1.94, 0), Vector3(0.02, 0.09, 0.09), dark)
		_box(root, Vector3(x * 0.6, 1.74, -0.22), Vector3(0.05, 0.12, 0.05), dark)
	for x in [-0.08, 0.08]:
		_box(root, Vector3(x, 1.95, -0.272), Vector3(0.08, 0.025, 0.01), dark)
	_box(root, Vector3(0, 2.05, -0.27), Vector3(0.44, 0.07, 0.02), helmet.darkened(0.25))
	_box(root, Vector3(0, 1.94, 0.27), Vector3(0.18, 0.12, 0.02), trim)
	var limbs = {}
	for side in [-1, 1]:
		var side_name = "left" if side < 0 else "right"
		var arm = Node3D.new()
		arm.position = Vector3(side * 0.47, 1.55, 0)
		root.add_child(arm)
		_box(arm, Vector3(0, -0.17, 0), Vector3(0.22, 0.35, 0.24), jersey)
		_box(arm, Vector3(0, -0.3, 0), Vector3(0.23, 0.06, 0.25), trim)
		_box(arm, Vector3(0, -0.45, 0), Vector3(0.2, 0.26, 0.2), skin)
		_box(arm, Vector3(0, -0.4, 0), Vector3(0.21, 0.05, 0.21), Color("e8ebef"))
		_box(arm, Vector3(0, -0.55, 0), Vector3(0.215, 0.05, 0.215), trim)
		_box(arm, Vector3(0, -0.63, 0), Vector3(0.22, 0.12, 0.22), Color("16181f"))
		_box(arm, Vector3(0, -0.02, 0), Vector3(0.3, 0.12, 0.3), jersey.darkened(0.05))
		_box(arm, Vector3(side * 0.09, 0.02, 0), Vector3(0.12, 0.08, 0.26), trim)
		limbs[side_name + "_arm"] = arm
		var leg = Node3D.new()
		leg.position = Vector3(side * 0.17, 0.96, 0)
		root.add_child(leg)
		_box(leg, Vector3(0, -0.23, 0), Vector3(0.27, 0.46, 0.29), pants)
		var sock: Color = trim if not away else jersey
		_box(leg, Vector3(0, -0.66, 0), Vector3(0.24, 0.4, 0.24), sock)
		_box(leg, Vector3(0, -0.6, 0), Vector3(0.245, 0.06, 0.245), primary if not away else trim)
		_box(leg, Vector3(0, -0.4, -0.12), Vector3(0.22, 0.14, 0.08), pants.lightened(0.12))
		_box(leg, Vector3(side * 0.135, -0.22, 0), Vector3(0.02, 0.42, 0.06), trim)
		_box(leg, Vector3(0, -0.82, 0), Vector3(0.25, 0.06, 0.25), Color("eceff2"))
		_box(leg, Vector3(0, -0.91, -0.06), Vector3(0.28, 0.13, 0.38), Color("10121a"))
		_box(leg, Vector3(0, -0.975, -0.06), Vector3(0.29, 0.03, 0.39), Color("f2f2f2"))
		_box(leg, Vector3(side * 0.141, -0.9, -0.06), Vector3(0.01, 0.05, 0.22), trim)
		limbs[side_name + "_leg"] = leg
	for facing in [0.0, PI]:
		var number = Label3D.new()
		number.text = str(p["number"])
		number.font_size = 64
		number.pixel_size = 0.0062
		number.outline_size = 8
		number.modulate = trim
		number.outline_modulate = jersey.darkened(0.5) if not away else Color("1a1d26")
		number.position = Vector3(0, 1.34, 0.235 if facing == 0.0 else -0.235)
		number.rotation.y = facing
		number.no_depth_test = false
		root.add_child(number)
	for side in [-1.0, 1.0]:
		var shoulder = Label3D.new()
		shoulder.text = str(p["number"])
		shoulder.font_size = 48
		shoulder.pixel_size = 0.0036
		shoulder.outline_size = 0
		shoulder.modulate = trim
		shoulder.transform = Transform3D(Basis(Vector3.FORWARD, side * PI / 2.0), Vector3(side * 0.505, 1.6, 0))
		root.add_child(shoulder)
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
	limbs["shadow"] = _blob(player_root, 1.5, 0.55)
	return limbs


func _shader_material(code: String, priority: int) -> ShaderMaterial:
	var material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = code
	material.shader = shader
	material.render_priority = priority
	return material


func _blob(parent: Node3D, size: float, strength: float) -> MeshInstance3D:
	var blob = MeshInstance3D.new()
	blob.mesh = blob_mesh
	var material: ShaderMaterial = blob_material
	if not is_equal_approx(strength, 0.5):
		material = blob_material.duplicate()
		material.set_shader_parameter("strength", strength)
	blob.material_override = material
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.scale = Vector3.ONE
	blob.mesh = blob_mesh
	blob.transform = Transform3D(Basis().scaled(Vector3(size, 1.0, size)), Vector3(0, 0.088, 0))
	parent.add_child(blob)
	return blob


func _build_game_day() -> void:
	var pool = MeshInstance3D.new()
	var pool_quad = QuadMesh.new()
	pool_quad.size = Vector2(FIELD_WIDTH + 34.0, 158.0)
	pool_quad.orientation = PlaneMesh.FACE_Y
	pool.mesh = pool_quad
	pool.material_override = _shader_material(POOL_SHADER, 0)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.position = Vector3(0, 0.075, -49)
	add_child(pool)
	var rng = RandomNumberGenerator.new()
	rng.seed = 90210
	var flash_spots: Array = []
	var occupied: Array = []
	for seat in stand_seats:
		if not seat["empty"]:
			occupied.append(seat)
	for i in mini(1100, occupied.size()):
		var seat: Dictionary = occupied[rng.randi_range(0, occupied.size() - 1)]
		flash_spots.append(seat["pos"] + Vector3(0, 1.45, 0))
	for x in [-20.0, -14.0, -7.5, 8.0, 15.0, 21.0]:
		for repeat in 6:
			flash_spots.append(Vector3(x, 0.95, -123.0 - absf(x) * 0.03))
	var flash_quad = QuadMesh.new()
	flash_quad.size = Vector2(2.4, 2.4)
	var flashes = MultiMesh.new()
	flashes.transform_format = MultiMesh.TRANSFORM_3D
	flashes.use_custom_data = true
	flashes.mesh = flash_quad
	flashes.instance_count = flash_spots.size()
	for i in flash_spots.size():
		flashes.set_instance_transform(i, Transform3D(Basis(), flash_spots[i]))
		flashes.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var flash_instance = MultiMeshInstance3D.new()
	flash_instance.multimesh = flashes
	flash_instance.material_override = flash_material
	flash_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_instance.extra_cull_margin = 4.0
	add_child(flash_instance)
	follow_spot = SpotLight3D.new()
	follow_spot.light_color = Color("fff0d2")
	follow_spot.light_energy = 0.0
	follow_spot.spot_range = 90.0
	follow_spot.spot_angle = 6.5
	follow_spot.spot_angle_attenuation = 0.6
	follow_spot.shadow_enabled = false
	follow_spot.position = Vector3(0, 48, -60)
	add_child(follow_spot)
	official_root = Node3D.new()
	add_child(official_root)
	var roles = [
		{"base": Vector2(-3.0, -13.0), "follow": 0.6},
		{"base": Vector2(2.0, 7.0), "follow": 0.5},
		{"base": Vector2(-(FIELD_WIDTH / 2.0 + 1.2), 0.0), "follow": 0.0, "sideline": true},
		{"base": Vector2(FIELD_WIDTH / 2.0 + 1.2, 0.0), "follow": 0.0, "sideline": true},
		{"base": Vector2(-(FIELD_WIDTH / 2.0 - 1.5), 18.0), "follow": 0.2},
		{"base": Vector2(FIELD_WIDTH / 2.0 - 1.5, 18.0), "follow": 0.2},
		{"base": Vector2(1.0, 24.0), "follow": 0.35},
	]
	for i in roles.size():
		var figure = _figure(official_root, Color("f4f4f2"), Color("f0f0ec"), Color("111318"), Color("111318") if i != 0 else Color("f4f4f2"), SKIN_COLORS[(i * 2 + 1) % SKIN_COLORS.size()], true)
		figure.merge(roles[i])
		figure["pos"] = Vector3(roles[i]["base"].x, 0, -(24.0 + roles[i]["base"].y))
		figure["phase"] = float(i) * 1.7
		officials.append(figure)
	var chain_color = Color("ff7a1a")
	for i in 3:
		var crew = _figure(official_root, Color("ffd21f"), Color("1b1f2a"), Color("1b1f2a"), Color("1b1f2a"), SKIN_COLORS[(i + 3) % SKIN_COLORS.size()], false)
		var pole = Node3D.new()
		crew["root"].add_child(pole)
		pole.position = Vector3(-0.42, 0, -0.1)
		_box(pole, Vector3(0, 1.35, 0), Vector3(0.08, 2.7, 0.08), Color("e8e8e8"))
		if i < 2:
			_box(pole, Vector3(0, 2.75, 0), Vector3(0.34, 0.3, 0.12), chain_color, true)
		else:
			_box(pole, Vector3(0, 2.85, 0), Vector3(0.5, 0.5, 0.12), Color("15171d"))
			down_box_label = Label3D.new()
			down_box_label.text = "1"
			down_box_label.font_size = 64
			down_box_label.pixel_size = 0.006
			down_box_label.outline_size = 0
			down_box_label.modulate = Color("ffd21f")
			down_box_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			down_box_label.position = Vector3(0, 2.85, 0)
			pole.add_child(down_box_label)
		crew["pos"] = Vector3(FIELD_WIDTH / 2.0 + 0.95, 0, -24.0)
		crew["phase"] = float(i)
		chain_sticks.append(crew)
	chain_links = MeshInstance3D.new()
	var link_mesh = BoxMesh.new()
	link_mesh.size = Vector3.ONE
	chain_links.mesh = link_mesh
	chain_links.material_override = _material(Color("c9ced8"))
	chain_links.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	official_root.add_child(chain_links)
	var operator = _figure(official_root, Color("20242e"), Color("20242e"), Color("15171d"), Color("15171d"), SKIN_COLORS[1], false)
	var rig = Node3D.new()
	operator["root"].add_child(rig)
	_box(rig, Vector3(0.32, 1.86, -0.05), Vector3(0.26, 0.3, 0.62), Color("15171d"))
	_box(rig, Vector3(0.32, 1.86, -0.45), Vector3(0.18, 0.18, 0.24), Color("2b2f3a"))
	_box(rig, Vector3(0.32, 1.86, -0.58), Vector3(0.14, 0.14, 0.02), Color("65c8ff"), true)
	_box(rig, Vector3(0.32, 2.05, 0.15), Vector3(0.06, 0.06, 0.06), Color("ff2020"), true)
	_box(rig, Vector3(0.32, 1.86, 0.32), Vector3(0.2, 0.22, 0.1), Color("2b2f3a"))
	operator["pos"] = Vector3(-(FIELD_WIDTH / 2.0 + 2.0), 0, -24.0)
	operator["phase"] = 0.0
	operator["camera"] = true
	officials.append(operator)
	for side in [-1.0, 1.0]:
		var net = Vector3(side * 34.6, 0, -80.0)
		for z in [-1.4, 1.4]:
			_box(self, net + Vector3(0, 1.4, z), Vector3(0.1, 2.8, 0.1), Color("2a2f3a"))
		_box(self, net + Vector3(0, 2.8, 0), Vector3(0.1, 0.1, 2.9), Color("2a2f3a"))
		var mesh_panel = _box(self, net + Vector3(0, 1.45, 0), Vector3(0.03, 2.7, 2.7), Color(0.05, 0.06, 0.08, 0.55))
		mesh_panel.material_override = _material(Color(0.05, 0.06, 0.08, 0.55), false, true)
		_box(self, net + Vector3(side * 0.6, 0.06, 0), Vector3(1.2, 0.12, 2.8), Color("1d2333"))
		var cart = Vector3(side * 35.6, 0, -101.0)
		_box(self, cart + Vector3(0, 0.62, 0), Vector3(1.5, 0.5, 2.8), Color("2c3a52"))
		_box(self, cart + Vector3(0, 1.0, -0.65), Vector3(1.4, 0.42, 0.9), Color("e9edf2"))
		_box(self, cart + Vector3(0, 1.9, 0.0), Vector3(1.5, 0.08, 2.0), Color("2c3a52"))
		for corner in [Vector3(-0.68, 0, -0.9), Vector3(0.68, 0, -0.9), Vector3(-0.68, 0, 0.9), Vector3(0.68, 0, 0.9)]:
			_box(self, cart + corner + Vector3(0, 1.45, 0), Vector3(0.06, 0.9, 0.06), Color("15171d"))
			_box(self, cart + corner + Vector3(0, 0.28, 0), Vector3(0.22, 0.56, 0.56), Color("101218"))
		_box(self, cart + Vector3(0, 0.7, -1.41), Vector3(1.2, 0.14, 0.03), Color("ffe08a"), true)
		_box(self, cart + Vector3(0, 1.12, 1.15), Vector3(1.2, 0.4, 0.3), Color("2c3a52"))


func _figure(parent: Node3D, shirt: Color, pants: Color, socks: Color, hat: Color, skin: Color, stripes: bool) -> Dictionary:
	var root = Node3D.new()
	parent.add_child(root)
	var dark = Color("111318")
	_box(root, Vector3(0, 1.3, 0), Vector3(0.58, 0.62, 0.34), shirt)
	if stripes:
		for x in [-0.21, -0.07, 0.07, 0.21]:
			_box(root, Vector3(x, 1.3, 0), Vector3(0.05, 0.63, 0.35), dark)
	_box(root, Vector3(0, 0.98, 0), Vector3(0.56, 0.1, 0.32), dark)
	_box(root, Vector3(0, 1.79, 0), Vector3(0.36, 0.36, 0.36), skin)
	_box(root, Vector3(0, 2.0, 0), Vector3(0.4, 0.1, 0.4), hat)
	_box(root, Vector3(0, 1.97, -0.27), Vector3(0.32, 0.04, 0.16), hat)
	for x in [-0.08, 0.08]:
		_box(root, Vector3(x, 1.82, -0.185), Vector3(0.06, 0.05, 0.01), dark)
	var parts = {"root": root}
	for side in [-1, 1]:
		var side_name = "left" if side < 0 else "right"
		var arm = Node3D.new()
		arm.position = Vector3(side * 0.4, 1.56, 0)
		root.add_child(arm)
		_box(arm, Vector3(0, -0.12, 0), Vector3(0.19, 0.26, 0.21), shirt)
		if stripes:
			_box(arm, Vector3(0, -0.12, 0), Vector3(0.2, 0.05, 0.22), dark)
		_box(arm, Vector3(0, -0.4, 0), Vector3(0.17, 0.32, 0.18), skin)
		parts[side_name + "_arm"] = arm
		var leg = Node3D.new()
		leg.position = Vector3(side * 0.15, 0.94, 0)
		root.add_child(leg)
		_box(leg, Vector3(0, -0.25, 0), Vector3(0.24, 0.5, 0.26), pants)
		_box(leg, Vector3(0, -0.66, 0), Vector3(0.22, 0.32, 0.22), socks)
		_box(leg, Vector3(0, -0.88, -0.05), Vector3(0.24, 0.12, 0.34), dark)
		parts[side_name + "_leg"] = leg
	_blob(root, 1.2, 0.5)
	return parts


func _build_cheerleaders(home: Dictionary, away: Dictionary) -> void:
	cheerleaders.clear()
	var rng = RandomNumberGenerator.new()
	rng.seed = 4242
	for side in [-1.0, 1.0]:
		var team: Dictionary = home if side < 0.0 else away
		var top: Color = team["primary"]
		var skirt: Color = team["secondary"]
		var pom: Color = team["secondary"].lightened(0.25)
		for end_z in [-5.0, -115.0]:
			for i in 5:
				var root = Node3D.new()
				sideline_root.add_child(root)
				var spot = Vector3(side * (28.6 + float(i % 2) * 1.3 + rng.randf_range(-0.2, 0.2)), 0, end_z + (float(i) - 2.0) * 1.35)
				root.position = spot
				root.rotation.y = -side * PI / 2.0 + rng.randf_range(-0.25, 0.25)
				var skin: Color = SKIN_COLORS[rng.randi_range(0, SKIN_COLORS.size() - 1)]
				var hair: Color = HAIR_COLORS[rng.randi_range(0, HAIR_COLORS.size() - 1)]
				_box(root, Vector3(0, 1.3, 0), Vector3(0.48, 0.44, 0.28), top)
				_box(root, Vector3(0, 1.36, -0.145), Vector3(0.3, 0.06, 0.01), skirt)
				_box(root, Vector3(0, 0.96, 0), Vector3(0.56, 0.26, 0.36), skirt)
				_box(root, Vector3(0, 0.96, 0), Vector3(0.57, 0.04, 0.37), Color("f4f4f2"))
				_box(root, Vector3(0, 1.72, 0), Vector3(0.34, 0.34, 0.34), skin)
				_box(root, Vector3(0, 1.9, 0.02), Vector3(0.36, 0.12, 0.36), hair)
				_box(root, Vector3(0, 1.72, 0.2), Vector3(0.14, 0.34, 0.1), hair)
				_box(root, Vector3(0, 1.94, 0.19), Vector3(0.18, 0.06, 0.04), skirt)
				var arms: Array = []
				for arm_side in [-1.0, 1.0]:
					var arm = Node3D.new()
					arm.position = Vector3(arm_side * 0.31, 1.5, 0)
					root.add_child(arm)
					_box(arm, Vector3(0, -0.28, 0), Vector3(0.14, 0.5, 0.14), skin)
					_box(arm, Vector3(0, -0.58, 0), Vector3(0.36, 0.3, 0.36), pom, true)
					arms.append(arm)
				var legs: Array = []
				for leg_side in [-1.0, 1.0]:
					var leg = Node3D.new()
					leg.position = Vector3(leg_side * 0.12, 0.84, 0)
					root.add_child(leg)
					_box(leg, Vector3(0, -0.36, 0), Vector3(0.15, 0.68, 0.16), skin)
					_box(leg, Vector3(0, -0.78, -0.04), Vector3(0.18, 0.14, 0.28), Color("f4f4f2"))
					legs.append(leg)
				_blob(sideline_root, 1.1, 0.45).position = Vector3(spot.x, 0.088, spot.z)
				cheerleaders.append({
					"root": root, "arms": arms, "legs": legs, "base": spot,
					"phase": rng.randf_range(0.0, TAU), "routine": rng.randi_range(0, 2),
				})


func _animate_figure(figure: Dictionary, target: Vector3, look: Vector3, delta: float, rate: float) -> void:
	var root: Node3D = figure["root"]
	var previous: Vector3 = figure["pos"]
	var next = previous.lerp(target, clampf(delta * rate, 0.0, 1.0))
	figure["pos"] = next
	root.position = next
	var speed = next.distance_to(previous) / maxf(delta, 0.001)
	var heading = look - next
	if Vector2(heading.x, heading.z).length() > 0.3:
		var yaw = atan2(-heading.x, -heading.z)
		root.rotation.y = lerp_angle(root.rotation.y, yaw, clampf(delta * 6.0, 0.0, 1.0))
	var stride = minf(speed / 5.0, 1.0)
	var swing = sin(elapsed * (7.0 + speed * 0.8) + figure["phase"]) * stride * 0.75
	figure["left_leg"].rotation.x = swing
	figure["right_leg"].rotation.x = -swing
	if figure.has("camera"):
		figure["left_arm"].rotation.x = -1.2
		figure["right_arm"].rotation.x = -1.4
	else:
		figure["left_arm"].rotation.x = -swing * 0.8
		figure["right_arm"].rotation.x = swing * 0.8


func _update_game_day(delta: float) -> void:
	if delta <= 0.0:
		delta = 1.0
	var los: float = game.los
	var ball2: Vector2 = game.ball_position()
	var ball3 = Vector3(ball2.x, 0, -ball2.y)
	var live: bool = game.phase == "live"
	var advance = maxf(0.0, ball2.y - los) if live else 0.0
	for figure in officials:
		var target: Vector3
		if figure.has("camera"):
			var track = ball2.y if live else los
			target = Vector3(-(FIELD_WIDTH / 2.0 + 2.0), 0, -clampf(track, -5.0, 115.0))
		else:
			var base: Vector2 = figure["base"]
			var x = base.x
			var y = los + base.y + advance * 0.85
			if live and not figure.get("sideline", false):
				x = lerpf(base.x, ball2.x, figure["follow"] * 0.5)
			if figure.get("sideline", false):
				y = ball2.y if live else los
			target = Vector3(clampf(x, -(FIELD_WIDTH / 2.0 + 2.0), FIELD_WIDTH / 2.0 + 2.0), 0, -clampf(y, -8.0, 128.0))
		_animate_figure(figure, target, ball3 if live else Vector3(target.x * 0.2, 0, -los), delta, 2.4 if live else 1.4)
	var stick_y = [game.first_down - 10.0, game.first_down, los]
	for i in chain_sticks.size():
		var crew: Dictionary = chain_sticks[i]
		var target = Vector3(FIELD_WIDTH / 2.0 + 0.95, 0, -clampf(stick_y[i], 0.0, 120.0))
		_animate_figure(crew, target, Vector3(0, 0, target.z), delta, 1.6)
	var first_stick: Vector3 = chain_sticks[0]["pos"]
	var second_stick: Vector3 = chain_sticks[1]["pos"]
	var chain_x = FIELD_WIDTH / 2.0 + 0.95
	var chain_len = maxf(0.1, absf(second_stick.z - first_stick.z))
	chain_links.transform = Transform3D(Basis().scaled(Vector3(0.04, 0.04, chain_len)), Vector3(chain_x - 0.3, 0.55, (first_stick.z + second_stick.z) * 0.5))
	down_box_label.text = str(clampi(game.down, 1, 4))
	var energy_target = 0.0
	if live and game.controlled >= 0:
		var runner: Dictionary = game.players[game.controlled]
		var aim = Vector3(runner["pos"].x, 0.0, -runner["pos"].y)
		follow_spot.position = follow_spot.position.lerp(aim + Vector3(-20.0, 46.0, 14.0), clampf(delta * 4.0, 0.0, 1.0))
		follow_spot.look_at(aim, Vector3.UP)
		energy_target = 5.5
	follow_spot.light_energy = lerpf(follow_spot.light_energy, energy_target, clampf(delta * 3.0, 0.0, 1.0))
	var flash_rate = 0.04 + excitement * 0.09
	if light_show_time > 0.0:
		flash_rate = 0.5
	flash_material.set_shader_parameter("rate", flash_rate)
	if light_show_time > 0.0:
		light_show_time = maxf(0.0, light_show_time - delta)
		var beat = int(elapsed * 7.0)
		for i in stadium_spots.size():
			var entry: Dictionary = stadium_spots[i]
			var light: SpotLight3D = entry["light"]
			var on_team = (beat + i) % 2 == 0
			light.light_color = light_show_color.lightened(0.1) if on_team else Color("fff4d8")
			var strobe = 0.08 if (beat + i) % 3 == 0 else 1.25
			light.light_energy = 13.0 * strobe * (0.7 + 0.3 * absf(sin(elapsed * 11.0 + float(i) * 1.3)))
		flare_material.set_shader_parameter("tint", light_show_color.lightened(0.35) if beat % 2 == 0 else Color("ffffff"))
		flare_material.set_shader_parameter("strength", 0.7 + 0.6 * absf(sin(elapsed * 11.0)))
		var world: Environment = environment.environment
		var pulse = absf(sin(elapsed * 9.0))
		var fade_out = clampf(light_show_time / 0.8, 0.0, 1.0)
		world.fog_light_color = Color("16223a").lerp(light_show_color, (0.35 + 0.35 * pulse) * fade_out)
		world.ambient_light_color = Color("65708e").lerp(light_show_color.lightened(0.2), 0.6 * pulse * fade_out)
		world.ambient_light_energy = 0.22 + 0.5 * pulse * fade_out
		world.adjustment_brightness = 1.0 + (0.16 if beat % 2 == 0 else -0.1) * fade_out
		if light_show_time <= 0.0:
			for entry in stadium_spots:
				entry["light"].light_color = entry["color"]
				entry["light"].light_energy = 13.0
			flare_material.set_shader_parameter("tint", Color(0.86, 0.92, 1.0))
			flare_material.set_shader_parameter("strength", 1.0)
			world.fog_light_color = Color("16223a")
			world.ambient_light_color = Color("65708e")
			world.ambient_light_energy = 0.22
			world.adjustment_brightness = 1.0
	var hype = clampf(excitement, 0.0, 1.6)
	for cheer in cheerleaders:
		var phase: float = cheer["phase"]
		var root: Node3D = cheer["root"]
		var bounce = maxf(0.0, sin(elapsed * (4.0 + hype * 2.0) + phase))
		var base: Vector3 = cheer["base"]
		root.position.y = base.y + bounce * (0.06 + hype * 0.22)
		var arms: Array = cheer["arms"]
		var legs: Array = cheer["legs"]
		match cheer["routine"]:
			0:
				arms[0].rotation.z = -2.6 * bounce - 0.3
				arms[1].rotation.z = 2.6 * bounce + 0.3
			1:
				arms[0].rotation.z = -1.4 - sin(elapsed * 6.0 + phase) * 1.1
				arms[1].rotation.z = 1.4 - sin(elapsed * 6.0 + phase) * 1.1
			_:
				arms[0].rotation.x = -3.0 * bounce
				arms[1].rotation.x = -3.0 * maxf(0.0, sin(elapsed * (4.0 + hype * 2.0) + phase + PI))
		legs[0].rotation.x = -bounce * hype * 0.5
		legs[1].rotation.x = bounce * hype * 0.2


func _build_ball() -> void:
	ball = Node3D.new()
	add_child(ball)
	_box(ball, Vector3.ZERO, Vector3(0.22, 0.22, 0.38), Color("71391a"))
	_box(ball, Vector3(0, 0.12, 0), Vector3(0.035, 0.025, 0.15), Color("f5ecdb"))


func _build_effects() -> void:
	confetti = _particles(160, 2.5, Color("ffdc42"), 0.16, true, 5.0, 11.0, 10.0)
	impact_sparks = _turf_kickup()
	turbo_trail = _particles(18, 0.3, Color("42caff"), 0.055, false, 0.6, 1.8, 0.6)
	var trail_process: ParticleProcessMaterial = turbo_trail.process_material
	var fade = Gradient.new()
	fade.set_color(0, Color(0.55, 0.88, 1.0, 0.42))
	fade.set_color(1, Color(0.55, 0.88, 1.0, 0.0))
	var ramp = GradientTexture1D.new()
	ramp.gradient = fade
	trail_process.color = Color.WHITE
	trail_process.color_ramp = ramp
	var trail_material: StandardMaterial3D = (turbo_trail.draw_pass_1 as BoxMesh).material
	trail_material.albedo_color = Color.WHITE
	trail_material.vertex_color_use_as_albedo = true
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.emission_enabled = false
	_build_fireworks()
	event_light = OmniLight3D.new()
	event_light.light_color = Color("55dfff")
	event_light.light_energy = 0.0
	event_light.omni_range = 12.0
	event_light.shadow_enabled = false
	add_child(event_light)


func _build_fireworks() -> void:
	for i in 10:
		var burst = GPUParticles3D.new()
		burst.amount = 140
		burst.lifetime = 1.9
		burst.one_shot = true
		burst.explosiveness = 0.97
		burst.emitting = false
		burst.local_coords = false
		burst.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
		var process = ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.4
		process.spread = 180.0
		process.initial_velocity_min = 9.0
		process.initial_velocity_max = 13.0
		process.damping_min = 3.5
		process.damping_max = 5.0
		process.gravity = Vector3(0, -4.5, 0)
		var shrink = Curve.new()
		shrink.add_point(Vector2(0, 1))
		shrink.add_point(Vector2(0.7, 0.75))
		shrink.add_point(Vector2(1, 0))
		var shrink_texture = CurveTexture.new()
		shrink_texture.curve = shrink
		process.scale_curve = shrink_texture
		burst.process_material = process
		var block = BoxMesh.new()
		block.size = Vector3.ONE * 0.32
		var material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		block.material = material
		burst.draw_pass_1 = block
		add_child(burst)
		var flash = OmniLight3D.new()
		flash.omni_range = 45.0
		flash.light_energy = 0.0
		flash.shadow_enabled = false
		burst.add_child(flash)
		firework_pool.append({"node": burst, "flash": flash, "time": 0.0})
	for x in [-FIELD_WIDTH / 2.0 - 1.5, FIELD_WIDTH / 2.0 + 1.5]:
		for z in [-123.0, 3.0]:
			var jet = _particles(60, 0.9, Color("ffb23a"), 0.14, false, 9.0, 14.0, 9.0)
			var jet_process: ParticleProcessMaterial = jet.process_material
			jet_process.spread = 8.0
			jet.position = Vector3(x, 0.3, z)
			_box(self, Vector3(x, 0.2, z), Vector3(0.7, 0.4, 0.7), Color("1a1d26"))
			pyro_jets.append(jet)


func _launch_fireworks(home_color: Color, away_color: Color) -> void:
	var palette = [home_color.lightened(0.25), Color("ffd84a"), Color("ffffff"), Color("ff4a6e"), Color("49e6ff"), Color("8aff5a")]
	var rng = RandomNumberGenerator.new()
	rng.seed = game.play_number * 31 + 7
	firework_queue.clear()
	for i in 16:
		var side = -1.0 if i % 2 == 0 else 1.0
		var spot = Vector3(side * rng.randf_range(10.0, 48.0), rng.randf_range(34.0, 58.0), -rng.randf_range(20.0, 150.0))
		if i % 5 == 4:
			spot = Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(40.0, 60.0), -rng.randf_range(135.0, 155.0))
		firework_queue.append({"time": float(i) * 0.28 + rng.randf_range(0.0, 0.2), "pos": spot, "color": palette[rng.randi_range(0, palette.size() - 1)]})
	pyro_time = 2.6


func _update_fireworks(delta: float) -> void:
	for i in range(firework_queue.size() - 1, -1, -1):
		var shot: Dictionary = firework_queue[i]
		shot["time"] -= delta
		if shot["time"] > 0.0:
			continue
		firework_queue.remove_at(i)
		var slot: Dictionary = firework_pool[firework_index % firework_pool.size()]
		firework_index += 1
		var burst: GPUParticles3D = slot["node"]
		var color: Color = shot["color"]
		var process: ParticleProcessMaterial = burst.process_material
		process.color = Color(color.r * 2.4, color.g * 2.4, color.b * 2.4)
		burst.position = shot["pos"]
		burst.restart()
		burst.emitting = true
		var flash: OmniLight3D = slot["flash"]
		flash.light_color = color
		slot["time"] = 0.5
	for slot in firework_pool:
		slot["time"] = maxf(0.0, slot["time"] - delta)
		slot["flash"].light_energy = 6.0 * slot["time"] / 0.5
	pyro_time = maxf(0.0, pyro_time - delta)
	for jet in pyro_jets:
		jet.emitting = pyro_time > 0.0


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
			_launch_fireworks(game.home["primary"], game.away["primary"])
			light_show_time = 4.5
			light_show_color = game.home["primary"]
			event_light.light_color = Color("ffdb43")
			event_light.omni_range = 22.0
			event_light_time = 0.45
		else:
			impact_sparks.position = Vector3(impact.x, 0.05, impact.z)
			impact_sparks.restart()
			impact_sparks.emitting = true
	_update_fireworks(delta)
	if event_light_time > 0.0:
		event_light_time = maxf(0.0, event_light_time - delta)
		event_light.light_energy = 8.0 * event_light_time / 0.45
	else:
		event_light.light_energy = 0.0
