extends SubViewportContainer

const LOGO_PATH = "res://App/BlockBowlLogo.obj"

signal landed

const DROP_DELAY = 0.3
const DROP_TIME = 0.42

var logo: MeshInstance3D
var camera: Camera3D
var flash: OmniLight3D
var dust: CPUParticles3D
var time = 0.0
var has_landed = false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(1080, 430)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1350, 540)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var root = Node3D.new()
	viewport.add_child(root)
	camera = Camera3D.new()
	camera.position = Vector3(0, 0, 3.6)
	camera.fov = 16
	camera.current = true
	root.add_child(camera)
	logo = MeshInstance3D.new()
	logo.mesh = _load_logo()
	logo.visible = false
	root.add_child(logo)
	flash = OmniLight3D.new()
	flash.position = Vector3(0, 0.3, 1.6)
	flash.omni_range = 8.0
	flash.light_color = Color("fff1c2")
	flash.light_energy = 0.0
	root.add_child(flash)
	dust = CPUParticles3D.new()
	dust.emitting = false
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.amount = 120
	dust.lifetime = 0.9
	dust.position = Vector3(0, -0.5, 0.2)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.9, 0.05, 0.2)
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 75.0
	dust.initial_velocity_min = 1.2
	dust.initial_velocity_max = 2.8
	dust.gravity = Vector3(0, -4.0, 0)
	dust.damping_min = 1.5
	dust.damping_max = 3.0
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.4
	var fade = Gradient.new()
	fade.set_color(0, Color(1.0, 0.93, 0.7, 1.0))
	fade.set_color(1, Color(0.75, 0.68, 0.55, 0.0))
	dust.color_ramp = fade
	var chunk = BoxMesh.new()
	chunk.size = Vector3.ONE * 0.03
	var chunk_material = StandardMaterial3D.new()
	chunk_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chunk_material.vertex_color_use_as_albedo = true
	chunk_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chunk.material = chunk_material
	dust.mesh = chunk
	root.add_child(dust)


func _process(delta: float) -> void:
	if logo == null:
		return
	time += delta
	var fall = (time - DROP_DELAY) / DROP_TIME
	if fall < 0.0:
		return
	logo.visible = true
	if fall < 1.0:
		var drop = fall * fall * fall
		logo.position = Vector3(0, lerpf(0.35, 0.0, drop), lerpf(2.2, 0.0, drop))
		logo.rotation = Vector3(lerpf(-0.45, 0.0, drop), lerpf(0.4, 0.0, drop), lerpf(-0.12, 0.0, drop))
		logo.scale = Vector3.ONE
		return
	if not has_landed:
		has_landed = true
		dust.restart()
		dust.emitting = true
		landed.emit()
	var since = time - DROP_DELAY - DROP_TIME
	var wobble = exp(-7.5 * since) * cos(since * 26.0)
	logo.scale = Vector3(1.0 + 0.14 * wobble, 1.0 - 0.2 * wobble, 1.0 + 0.1 * wobble)
	logo.position = Vector3(0, -0.06 * maxf(wobble, 0.0), 0)
	var shake = 0.07 * exp(-8.0 * since)
	camera.position = Vector3(sin(since * 61.0) * shake, cos(since * 47.0) * shake, 3.6)
	flash.light_energy = 7.0 * exp(-9.0 * since)
	var idle = clampf((since - 0.6) / 1.2, 0.0, 1.0)
	logo.rotation.y = sin(since * 0.48) * 0.14 * idle
	logo.rotation.x = sin(since * 0.68) * 0.04 * idle
	logo.rotation.z = 0.0


func _load_logo() -> ArrayMesh:
	var file = FileAccess.open(LOGO_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open the title logo: " + error_string(FileAccess.get_open_error()))
		return null
	var positions = PackedVector3Array()
	var colors = PackedColorArray()
	var triangles: Array = []
	var minimum = Vector3(INF, INF, INF)
	var maximum = Vector3(-INF, -INF, -INF)
	for line in file.get_as_text().split("\n", false):
		var parts = line.strip_edges().split(" ", false)
		if parts.size() >= 4 and parts[0] == "v":
			var point = Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
			positions.append(point)
			minimum = minimum.min(point)
			maximum = maximum.max(point)
			if parts.size() >= 7:
				colors.append(Color(float(parts[4]), float(parts[5]), float(parts[6])))
			else:
				colors.append(Color.WHITE)
		elif parts.size() >= 4 and parts[0] == "f":
			var indices = []
			for i in range(1, parts.size()):
				indices.append(int(parts[i].split("/")[0]) - 1)
			for i in range(1, indices.size() - 1):
				triangles.append([indices[0], indices[i], indices[i + 1]])
	if positions.is_empty() or triangles.is_empty():
		push_error("The bundled title logo contains no geometry.")
		return null
	var center = (minimum + maximum) * 0.5
	var scale_factor = 1.0 / maxf(maximum.y - minimum.y, 0.0001)
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var vertex_colors = PackedColorArray()
	for triangle in triangles:
		if triangle[0] < 0 or triangle[1] < 0 or triangle[2] < 0 or \
				triangle[0] >= positions.size() or triangle[1] >= positions.size() or triangle[2] >= positions.size():
			push_error("The bundled title logo has an invalid face index.")
			return null
		var a = (positions[triangle[0]] - center) * scale_factor
		var b = (positions[triangle[1]] - center) * scale_factor
		var c = (positions[triangle[2]] - center) * scale_factor
		var normal = (b - a).cross(c - a).normalized()
		for index in triangle:
			vertices.append((positions[index] - center) * scale_factor)
			normals.append(normal)
			vertex_colors.append(colors[index])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = vertex_colors
	var result = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.surface_set_material(0, material)
	return result
