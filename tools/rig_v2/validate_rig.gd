extends SceneTree

const RIG_PATH := "res://visuals/rig_v2/visual_root_v2.tscn"
const TEST_PATH := "res://tests/rig_test.tscn"
const EXPECTED_BONE_COUNT := 51
const EXPECTED_MESH_COUNT := 14
const EXPECTED_RIGID_COUNT := 5
const WEIGHT_TOLERANCE := 0.0001
const POSE_BONES := ["", "Spine_01", "Chest", "Thigh_R", "Shin_R", "Toe_R", "Forearm_L", "Head"]
const ANCHOR_PARENTS := {
	"SwordGrip": "Hand_R",
	"ScabbardGripTarget": "Hand_L",
	"ScabbardAnchor": "Pelvis",
	"SheathedSwordSocket": "ScabbardAnchor",
}

var _errors: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var packed_rig := load(RIG_PATH) as PackedScene
	if packed_rig == null:
		_fail("V2 场景不能加载")
		_finish()
		return
	var rig := packed_rig.instantiate()
	root.add_child(rig)
	await process_frame
	var skeleton: Skeleton2D = rig.get_node("Skeleton2D")
	_check_bones(skeleton)
	var mesh_count := _check_meshes(rig.get_node("Skin"), skeleton)
	if mesh_count != EXPECTED_MESH_COUNT:
		_fail("柔性网格数量不正确")
	_check_attachments(skeleton)
	_check_poses(rig, skeleton)
	_check_test_scene()
	if _errors.is_empty():
		print("Rig V2 资源检查通过：%d 根骨骼、%d 个蒙皮区域、8 个测试姿态。未运行 Gameplay、回归测试或批量渲染。" % [skeleton.get_bone_count(), mesh_count])
	rig.queue_free()
	_finish()


func _check_bones(skeleton: Skeleton2D) -> void:
	if skeleton.get_bone_count() != EXPECTED_BONE_COUNT:
		_fail("Bone2D 数量不正确")
	for index in range(skeleton.get_bone_count()):
		var bone := skeleton.get_bone(index)
		if is_zero_approx(bone.rest.determinant()):
			_fail("骨骼 Rest 不可逆：%s" % bone.name)
		if not bone.transform.is_equal_approx(bone.rest):
			_fail("中性姿态与 Rest 不一致：%s" % bone.name)
		if not is_equal_approx(deg_to_rad(float(bone.get("bone_angle"))), bone.get_bone_angle()):
			_fail("TSCN bone_angle 为度，Bone2D API 为弧度：%s" % bone.name)
	var root_bone: Bone2D = skeleton.get_bone(0)
	if not Vector2.RIGHT.rotated(root_bone.get_bone_angle()).is_equal_approx(Vector2.UP):
		_fail("Root 骨段必须朝上，不能误把度属性改成弧度")


func _check_attachments(skeleton: Skeleton2D) -> void:
	for anchor_name in ANCHOR_PARENTS:
		var anchor := skeleton.find_child(anchor_name, true, false)
		if not anchor is Marker2D or anchor.get_parent().name != ANCHOR_PARENTS[anchor_name]:
			_fail("挂点位置不正确：%s" % anchor_name)
	var sprites := skeleton.find_children("*", "Sprite2D", true, false)
	if sprites.size() != EXPECTED_RIGID_COUNT:
		_fail("刚性区域数量不正确")
	for sprite in sprites:
		if sprite.texture == null:
			_fail("刚性区域没有贴图：%s" % sprite.name)
		if sprite.name == &"Sword":
			if sprite.visible or not sprite.get_meta("source_unavailable", false):
				_fail("不可见剑体没有保持隐藏占位")
			if sprite.get_parent().name != &"SheathedSwordSocket":
				_fail("Sword 没有独立挂点")
		elif sprite.name == &"Scabbard" and sprite.get_parent().name != &"ScabbardAnchor":
			_fail("Scabbard 没有独立挂点")


func _check_poses(rig: Node, skeleton: Skeleton2D) -> void:
	var animator: AnimationPlayer = rig.get_node("AnimationPlayer")
	if not animator.has_animation(&"rig_test") or animator.is_playing():
		_fail("rig_test 缺失或默认自动播放")
		return
	var animation_names := animator.get_animation_list()
	if animation_names.size() != 10 or not animation_names.has("RESET"):
		_fail("应保留 RESET、rig_test 与八个正式移动动作")
	for pose_index in range(POSE_BONES.size()):
		rig.preview_pose = pose_index
		if animator.current_animation_position != float(pose_index):
			_fail("测试姿态不能定位：%d" % pose_index)
		if pose_index > 0:
			var bone := skeleton.find_child(POSE_BONES[pose_index], true, false) as Bone2D
			if bone == null or is_zero_approx(bone.rotation):
				_fail("测试姿态没有驱动目标骨骼：%s" % POSE_BONES[pose_index])
	rig.preview_pose = 0
	_check_bones(skeleton)


func _check_test_scene() -> void:
	var packed_test := load(TEST_PATH) as PackedScene
	if packed_test == null:
		_fail("独立 rig_test 场景不能加载")
		return
	var test_scene := packed_test.instantiate()
	root.add_child(test_scene)
	var animator: AnimationPlayer = test_scene.get_node("Stage/VisualRoot_V2/AnimationPlayer")
	if animator.is_playing() or not test_scene.get_node("Stage/VisualRoot_V2").visible:
		_fail("独立测试场景没有默认暂停显示 V2")
	test_scene.queue_free()


func _check_meshes(skin: Node, skeleton: Skeleton2D) -> int:
	var mesh_count := 0
	for child in skin.get_children():
		if not child is Polygon2D:
			continue
		mesh_count += 1
		var mesh: Polygon2D = child
		if mesh.texture == null or mesh.get_node_or_null(mesh.skeleton) != skeleton:
			_fail("贴图或 Skeleton 绑定失效：%s" % mesh.name)
		if mesh.uv.size() != mesh.polygon.size() or mesh.internal_vertex_count == 0:
			_fail("UV 或细分网格失效：%s" % mesh.name)
		_check_weights(mesh, skeleton)
	return mesh_count


func _check_weights(mesh: Polygon2D, skeleton: Skeleton2D) -> void:
	var sums := PackedFloat32Array()
	sums.resize(mesh.polygon.size())
	var has_blend := false
	for bone_index in range(mesh.get_bone_count()):
		if not skeleton.get_node_or_null(mesh.get_bone_path(bone_index)) is Bone2D:
			_fail("权重引用缺失：%s" % mesh.name)
		var weights := mesh.get_bone_weights(bone_index)
		if weights.size() != sums.size():
			_fail("顶点与权重数量不一致：%s" % mesh.name)
			return
		for vertex_index in range(weights.size()):
			var weight := weights[vertex_index]
			sums[vertex_index] += weight
			has_blend = has_blend or (weight > WEIGHT_TOLERANCE and weight < 1.0 - WEIGHT_TOLERANCE)
	for total in sums:
		if absf(total - 1.0) > WEIGHT_TOLERANCE:
			_fail("顶点权重未归一化：%s" % mesh.name)
			break
	if not has_blend:
		_fail("柔性网格没有平滑权重：%s" % mesh.name)


func _fail(message: String) -> void:
	_errors.append(message)
	push_error(message)


func _finish() -> void:
	quit(0 if _errors.is_empty() else 1)
