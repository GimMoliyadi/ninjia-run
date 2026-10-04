extends RefCounted

const RIG = preload("res://visuals/rig_v2/visual_root_v2.tscn")
const SoleProbe = preload("res://tests/godot/rig_action_sole_probe.gd")
const PIXEL_SCALE := 0.055
const GROUND_LIMIT := 0.055
const SLIDE_CEILING := -32.0
const ROLL_PIVOT := Vector2(0.0, -20.0)


static func run(root: Node, check: Callable) -> void:
	var rig: Node2D = RIG.instantiate()
	root.add_child(rig)
	var animator: AnimationPlayer = rig.get_node("AnimationPlayer")
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_check_arm_depth(rig, check)
	rig.set_action_mode(true)
	var skeleton: Skeleton2D = rig.get_node("Skeleton2D")
	var soles: Array = []
	for side in ["L", "R"]:
		soles.append(SoleProbe.new(rig.get_node("Skin/Leg_%s" % side), skeleton.find_child("Shin_%s" % side, true, false)))
	_check_ground_blends(rig, animator, soles, check)
	var meshes: Array = []
	for mesh in rig.get_node("Skin").get_children():
		meshes.append([mesh, SoleProbe.new(mesh)])
	var sprites: Array = []
	for sprite in rig.find_children("*", "Sprite2D", true, false):
		if sprite.visible:
			sprites.append([sprite, _sprite_contour(sprite)])
	_check_slide(rig, animator, meshes, sprites, check)
	_check_roll(rig, animator, meshes, sprites, check)
	rig.free()


static func _effective_z(item: CanvasItem) -> int:
	var depth := 0
	var current: Node = item
	while current is CanvasItem:
		depth += current.z_index
		if not current.z_as_relative:
			break
		current = current.get_parent()
	return depth


static func _arm_depth_errors(rig: Node2D) -> PackedStringArray:
	var errors := PackedStringArray()
	var skeleton: Skeleton2D = rig.get_node("Skeleton2D")
	var near_arm: Polygon2D = rig.get_node("Skin/Arm_L")
	var far_arm: Polygon2D = rig.get_node("Skin/Arm_R")
	var near_hand: Sprite2D = skeleton.find_child("Hand_L", true, false).get_node("Hand_L")
	var far_hand: Sprite2D = skeleton.find_child("Hand_R", true, false).get_node("Hand_R")
	var torso := _effective_z(rig.get_node("Skin/Torso"))
	var pelvis := _effective_z(rig.get_node("Skin/PelvisClothing"))
	var head := _effective_z(skeleton.find_child("HeadFace", true, false))
	if _effective_z(near_arm) <= maxi(torso, pelvis):
		errors.append("近景 Arm_L 不得被躯干/腰部吞掉")
	if _effective_z(near_hand) <= _effective_z(near_arm) or _effective_z(near_arm) >= head or _effective_z(near_hand) >= head:
		errors.append("近景臂与手必须连接在同一前景层，且不盖住头部")
	if _effective_z(far_arm) >= torso or _effective_z(far_hand) >= torso or _effective_z(far_hand) <= _effective_z(far_arm):
		errors.append("远景 Arm_R/Hand_R 必须共同位于躯干后方，不能手掌悬浮在前方")
	return errors


static func _check_arm_depth(rig: Node2D, check: Callable) -> void:
	var items: Array = rig.get_node("Skin").get_children() + rig.find_children("*", "Sprite2D", true, false)
	var neutral_depths: Array[int] = []
	for item in items:
		neutral_depths.append(item.z_index)
	rig.set_action_mode(true)
	check.call(_arm_depth_errors(rig).is_empty(), "；".join(_arm_depth_errors(rig)))
	var skeleton: Skeleton2D = rig.get_node("Skeleton2D")
	var near_arm: Polygon2D = rig.get_node("Skin/Arm_L")
	var far_arm: Polygon2D = rig.get_node("Skin/Arm_R")
	var near_hand: Sprite2D = skeleton.find_child("Hand_L", true, false).get_node("Hand_L")
	var far_hand: Sprite2D = skeleton.find_child("Hand_R", true, false).get_node("Hand_R")
	for item in [near_arm, near_hand, far_arm, far_hand]:
		var depth: int = item.z_index
		item.z_index = rig.get_node("Skin/Torso").z_index - 1 if item == near_arm or item == near_hand else rig.get_node("Skin/Torso").z_index + 1
		check.call(not _arm_depth_errors(rig).is_empty(), "绘制层级错误反例应失败：%s" % item.name)
		item.z_index = depth
	rig.set_action_mode(false)
	for index in range(items.size()):
		check.call(items[index].z_index == neutral_depths[index], "退出动作模式必须保留原中性分层：%s" % items[index].name)
	rig.set_action_mode(true)
	check.call(_arm_depth_errors(rig).is_empty(), "重复启停应恢复正式动作的前后臂/手层级")


static func _pose(rig: Node2D, animator: AnimationPlayer, name: StringName, time: float) -> void:
	rig.reset_actions()
	rig.play_action(name)
	animator.advance(0.05)
	animator.seek(time, true)


static func _check_ground_blends(rig: Node2D, animator: AnimationPlayer, soles: Array, check: Callable) -> void:
	var worst := -INF
	for phase in [0.0, 0.125, 0.25, 0.5, 0.75]:
		for reverse in [false, true]:
			var action: StringName = &"slide" if reverse else &"run"
			_pose(rig, animator, action, phase * animator.get_animation(action).length)
			rig.play_action(&"run" if reverse else &"slide")
			for step in range(10):
				animator.advance(0.005)
				var bottom: float = maxf(soles[0].height(), soles[1].height()) * PIXEL_SCALE
				bottom += rig.get_node("Skeleton2D").position.y * PIXEL_SCALE
				worst = maxf(worst, bottom)
	check.call(worst <= GROUND_LIMIT, "run↔slide 混合必须保持真实 alpha 鞋底不穿地")
	print("VISUAL blend sole max gamepx=%.5f" % worst)


static func _check_slide(rig: Node2D, animator: AnimationPlayer, meshes: Array, sprites: Array, check: Callable) -> void:
	var head_top := INF
	var coat_bottom := -INF
	var visible_top := INF
	var visible_bottom := -INF
	for time in [0.0, 0.145, 0.29, 0.435, 0.58]:
		_pose(rig, animator, &"slide", time)
		for entry in meshes:
			for point in entry[1].points():
				visible_top = minf(visible_top, point.y * PIXEL_SCALE)
				visible_bottom = maxf(visible_bottom, point.y * PIXEL_SCALE)
				if str(entry[0].name).begins_with("CoatBack") or str(entry[0].name).begins_with("ClothFront"):
					coat_bottom = maxf(coat_bottom, point.y * PIXEL_SCALE)
		for entry in sprites:
			for point in entry[1]:
				var local: Vector2 = rig.global_transform.affine_inverse() * entry[0].global_transform * point
				visible_top = minf(visible_top, local.y * PIXEL_SCALE)
				visible_bottom = maxf(visible_bottom, local.y * PIXEL_SCALE)
				if entry[0].name == &"HeadFace":
					head_top = minf(head_top, local.y * PIXEL_SCALE)
	check.call(is_finite(head_top) and head_top >= SLIDE_CEILING, "slide 头部 alpha 顶必须处于既有 -32px 低通道内")
	check.call(coat_bottom <= GROUND_LIMIT, "slide 衣片 alpha 不能穿过地面")
	check.call(visible_top >= SLIDE_CEILING and visible_bottom <= GROUND_LIMIT, "slide 完整可见轮廓必须处于 -32～0px 通道，不仅头部/鞋底")
	print("VISUAL slide head top=%.5f coat bottom=%.5f full contour=%.5f..%.5f gamepx" % [head_top, coat_bottom, visible_top, visible_bottom])


static func _check_roll(rig: Node2D, animator: AnimationPlayer, probes: Array, sprites: Array, check: Callable) -> void:
	var bottom := -INF
	for time in [0.04, 0.08, 0.12, 0.16, 0.20, 0.21, 0.24, 0.28]:
		_pose(rig, animator, &"double_jump", time)
		var rotation := Transform2D(TAU * time / 0.32, ROLL_PIVOT)
		for entry in probes:
			for point in entry[1].points():
				bottom = maxf(bottom, (rotation * (point * PIXEL_SCALE - ROLL_PIVOT)).y)
		for entry in sprites:
			for point in entry[1]:
				var local: Vector2 = rig.global_transform.affine_inverse() * entry[0].global_transform * point
				bottom = maxf(bottom, (rotation * (local * PIXEL_SCALE - ROLL_PIVOT)).y)
	check.call(bottom <= GROUND_LIMIT, "double_jump 外层原支点旋转后的真实可见轮廓不能穿地")
	print("VISUAL roll contour bottom=%.5f gamepx" % bottom)


static func _sprite_contour(sprite: Sprite2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	var image := sprite.texture.get_image()
	for x in range(image.get_width()):
		var first := -1
		var last := -1
		for y in range(image.get_height()):
			if image.get_pixel(x, y).a >= SoleProbe.ALPHA_THRESHOLD:
				if first < 0:
					first = y
				last = y
		if first >= 0:
			points.append(Vector2(x + 0.5, first + 0.5))
			points.append(Vector2(x + 0.5, last + 0.5))
	return points
