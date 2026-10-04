extends CanvasGroup

const LIFETIME_SECONDS := 0.30
const INK_TINT := Color(0.63, 0.75, 0.78)
const START_OPACITY := 0.30
const FADE_POWER := 1.45
const GHOST_Z_INDEX := -100
const SMOKE_STRANDS := 2
const SMOKE_POINTS := 9
const SMOKE_LENGTH := 22.0
const SMOKE_DRIFT := 5.0
const SMOKE_LIFT := 3.0
const SMOKE_CURVE := 1.3
const SMOKE_WIDTH := 2.4

var frozen_rig: Node2D
var age_seconds := 0.0
var _direction := 1.0
var _smoke_lines: Array[Line2D] = []


func capture(source: Node2D, horizontal_velocity: float) -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_DISABLED
	# 正式背景在 CanvasLayer -2，负 z 只让残影退到真身后方。
	z_index = GHOST_Z_INDEX
	z_as_relative = false
	transform = source.global_transform
	_direction = signf(horizontal_velocity)
	# 不复制脚本、信号、组或实例化逻辑，只留下当前混合和鞋底校正后的原生绘制状态。
	frozen_rig = source.duplicate(0) as Node2D
	var animator := frozen_rig.get_node("AnimationPlayer")
	frozen_rig.remove_child(animator)
	animator.free()
	frozen_rig.transform = Transform2D.IDENTITY
	_disable_processing(frozen_rig)
	add_child(frozen_rig)
	_create_smoke(source)
	_update_fade()


func _disable_processing(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_disable_processing(child)


func _create_smoke(source: Node2D) -> void:
	var skeleton: Skeleton2D = source.get_node("Skeleton2D")
	var left_foot: Bone2D = skeleton.find_child("Foot_L", true, false)
	var right_foot: Bone2D = skeleton.find_child("Foot_R", true, false)
	var foot_position := (left_foot.global_position + right_foot.global_position) / 2.0
	var smoke := Node2D.new()
	smoke.name = &"FootSmoke"
	# 烟丝按游戏像素绘制，不再继承素材根节点的 0.055 缩放。
	smoke.transform = transform.affine_inverse() * Transform2D(0.0, foot_position)
	add_child(smoke)
	for strand in range(SMOKE_STRANDS):
		var line := Line2D.new()
		line.width = SMOKE_WIDTH / (strand + 1.0)
		line.antialiased = true
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(0.82, 0.91, 0.93, 0.42), Color(1, 1, 1, 0)])
		line.gradient = gradient
		smoke.add_child(line)
		_smoke_lines.append(line)
	_update_smoke(0.0)


func advance_snapshot(delta: float) -> bool:
	age_seconds = minf(age_seconds + delta, LIFETIME_SECONDS)
	_update_fade()
	_update_smoke(age_seconds / LIFETIME_SECONDS)
	return age_seconds >= LIFETIME_SECONDS


func _update_fade() -> void:
	var remaining := 1.0 - age_seconds / LIFETIME_SECONDS
	modulate = Color(INK_TINT, START_OPACITY * pow(remaining, FADE_POWER))


func _update_smoke(progress: float) -> void:
	for strand in range(_smoke_lines.size()):
		var points := PackedVector2Array()
		for index in range(SMOKE_POINTS):
			var amount := float(index) / (SMOKE_POINTS - 1)
			var length := SMOKE_LENGTH * (0.55 + progress * 0.45) * amount
			var lift := -SMOKE_LIFT * (sin(amount * PI) + progress * amount)
			var curl := sin(amount * TAU + strand * PI / 2.0) * SMOKE_CURVE
			points.append(Vector2(-_direction * (length + progress * SMOKE_DRIFT), lift + curl - strand * SMOKE_CURVE))
		_smoke_lines[strand].points = points
