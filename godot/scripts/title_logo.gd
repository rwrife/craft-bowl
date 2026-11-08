extends SubViewportContainer

const LOGO_PATH = "res://App/BlockBowlLogo.obj"

var logo: MeshInstance3D
var time = 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(700, 240)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(900, 300)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var root = Node3D.new()
	viewport.add_child(root)
	var camera = Camera3D.new()
	camera.position = Vector3(0, 0, 3.6)
	camera.fov = 24
	camera.current = true
	root.add_child(camera)
	logo = MeshInstance3D.new()
	logo.mesh = _load_logo()
	root.add_child(logo)


func _process(delta: float) -> void:
	if logo == null:
		return
	time += delta
	logo.rotation.y = sin(time * 0.48) * 0.14
	logo.rotation.x = sin(time * 0.68) * 0.04


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
