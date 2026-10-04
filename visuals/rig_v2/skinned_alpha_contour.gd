extends RefCounted

const ALPHA_THRESHOLD := 16.0 / 255.0
const MESH_SPACING := 24.0
const SOLE_BAND_DEPTH := 2.0

var _mesh: Polygon2D
var _skeleton: Skeleton2D
var _samples: Array[Dictionary] = []
var _contact_samples: Array[Dictionary] = []
var _bones: Array[Bone2D] = []
var _rest_inverses: Array[Transform2D] = []
var _weights: Array[PackedFloat32Array] = []


func _init(mesh: Polygon2D, knee: Bone2D = null) -> void:
	_mesh = mesh
	_skeleton = mesh.get_node(mesh.skeleton)
	var image := mesh.texture.get_image()
	var size := image.get_size()
	var grid_size := Vector2i(maxi(2, ceili(size.x / MESH_SPACING)), maxi(2, ceili(size.y / MESH_SPACING)))
	var indices := {}
	for index in range(mesh.uv.size()):
		indices[Vector2i((mesh.uv[index] * Vector2(grid_size) / Vector2(size)).round())] = index
	var first_row := ceili(knee.get_skeleton_rest().origin.y - mesh.polygon[0].y) if knee != null else 0
	var contour := _alpha_contour(image, first_row)
	assert(not contour.is_empty(), "视觉网格缺少可采样的 alpha 轮廓")
	var bottom := -INF
	for point in contour:
		bottom = maxf(bottom, point.y)
	for point in contour:
		var sample := _mesh_sample(point, size, grid_size, indices)
		_samples.append(sample)
		if point.y >= bottom - SOLE_BAND_DEPTH:
			_contact_samples.append(sample)
	for index in range(mesh.get_bone_count()):
		var bone: Bone2D = _skeleton.get_node(mesh.get_bone_path(index))
		_bones.append(bone)
		_rest_inverses.append(bone.get_skeleton_rest().affine_inverse())
		_weights.append(mesh.get_bone_weights(index))


func height() -> float:
	var maximum := -INF
	for point in points():
		maximum = maxf(maximum, point.y)
	return maximum


func contact() -> Vector2:
	var vertices := _deformed_vertices()
	var center := Vector2.ZERO
	for sample in _contact_samples:
		center += _sample_point(vertices, sample)
	return center / _contact_samples.size()


func points() -> PackedVector2Array:
	var vertices := _deformed_vertices()
	var contour := PackedVector2Array()
	for sample in _samples:
		contour.append(_sample_point(vertices, sample))
	return contour


func _deformed_vertices() -> PackedVector2Array:
	var vertices := PackedVector2Array()
	vertices.resize(_mesh.polygon.size())
	var skeleton_inverse := _skeleton.global_transform.affine_inverse()
	for bone_index in range(_bones.size()):
		var deformation := skeleton_inverse * _bones[bone_index].global_transform * _rest_inverses[bone_index]
		for index in range(vertices.size()):
			var weight: float = _weights[bone_index][index]
			if weight > 0.0:
				vertices[index] += (deformation * _mesh.polygon[index]) * weight
	return vertices


func _sample_point(vertices: PackedVector2Array, sample: Dictionary) -> Vector2:
	var triangle: Vector3i = sample["indices"]
	var weights: Vector3 = sample["weights"]
	return vertices[triangle.x] * weights.x + vertices[triangle.y] * weights.y + vertices[triangle.z] * weights.z


func _alpha_contour(image: Image, first_row: int) -> Array[Vector2]:
	var edges := {}
	var size := image.get_size()
	for y in range(first_row, size.y):
		var first := -1
		var last := -1
		for x in range(size.x):
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				if first < 0:
					first = x
				last = x
		if first >= 0:
			edges[Vector2i(first, y)] = true
			edges[Vector2i(last, y)] = true
	for x in range(size.x):
		var first := -1
		var last := -1
		for y in range(first_row, size.y):
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				if first < 0:
					first = y
				last = y
		if first >= 0:
			edges[Vector2i(x, first)] = true
			edges[Vector2i(x, last)] = true
	var points: Array[Vector2] = []
	for edge in edges:
		points.append(Vector2(edge) + Vector2(0.5, 0.5))
	return points


func _mesh_sample(point: Vector2, size: Vector2i, grid_size: Vector2i, indices: Dictionary) -> Dictionary:
	var grid := point * Vector2(grid_size) / Vector2(size)
	var cell := Vector2i(mini(grid_size.x - 1, int(grid.x)), mini(grid_size.y - 1, int(grid.y)))
	var fraction := grid - Vector2(cell)
	if fraction.x + fraction.y <= 1.0:
		return {"indices": Vector3i(indices[cell], indices[cell + Vector2i.RIGHT], indices[cell + Vector2i.DOWN]), "weights": Vector3(1.0 - fraction.x - fraction.y, fraction.x, fraction.y)}
	return {"indices": Vector3i(indices[cell + Vector2i.RIGHT], indices[cell + Vector2i.ONE], indices[cell + Vector2i.DOWN]), "weights": Vector3(1.0 - fraction.y, fraction.x + fraction.y - 1.0, 1.0 - fraction.x)}
