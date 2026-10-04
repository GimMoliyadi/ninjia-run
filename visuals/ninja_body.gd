extends Node2D

var ink_color := Color.BLACK
var phase := 0.0
var pose_mode := "run"
var falling := false
var skeleton_pose := false

func set_pose(new_phase: float, mode: String, is_falling: bool) -> void:
	phase = new_phase
	pose_mode = mode
	falling = is_falling
	$Neck.position = to_local($VisualRoot_V1/RunSkeleton/Hip/Torso/Head.global_position) + Vector2(-4, 8) if skeleton_pose or mode == "run" else head_position() + Vector2(-4, 8)
	queue_redraw()

func head_position() -> Vector2:
	if pose_mode == "double_jump_roll":
		return Vector2(6, -29)
	if pose_mode == "slide":
		return Vector2(20, -21)
	if pose_mode == "air":
		return Vector2(13, -57)
	if pose_mode == "idle":
		return Vector2(9, -57 + sin(phase) * 1.5)
	return Vector2(12, -57)

func is_attacking() -> bool:
	var sword := get_node_or_null("Sword")
	return sword != null and is_instance_valid(sword.combat) and sword.combat.slash_remaining > 0.0

func sword_hand_position() -> Vector2:
	if skeleton_pose:
		return to_local($VisualRoot_V1/RunSkeleton/Hip/Torso/UpperArm_R/Forearm_R/SwordGrip.global_position)
	if is_attacking():
		var sword := $Sword
		var attack_progress: float = 1.0 - sword.combat.slash_remaining / sword.combat.SWORD_DURATION
		return Vector2(18 + sin(attack_progress * PI) * 13, -32 - sin(attack_progress * PI) * 7)
	if pose_mode == "slide":
		return Vector2(27, -10)
	if pose_mode == "air":
		return Vector2(18, -34)
	if pose_mode == "idle":
		return Vector2(18, -32)
	return Vector2(18, -32)

func _draw() -> void:
	if skeleton_pose or pose_mode == "run":
		return
	if pose_mode == "double_jump_roll":
		draw_roll()
		return
	var head := head_position()
	var shoulder := head + Vector2(-4, 13)
	var hip := Vector2(-5, -27)
	if pose_mode == "slide":
		hip = Vector2(-12, -12)
		limb(hip, Vector2(5, -5), Vector2(33, -4), 8.0)
		limb(hip, Vector2(-25, -5), Vector2(-34, -3), 7.0)
	if pose_mode != "slide":
		draw_legs(hip)
	var free_hand := Vector2(-9, -31)
	if pose_mode == "air":
		free_hand = Vector2(-18, -42)
	elif pose_mode == "slide":
		free_hand = Vector2(7, -12)
	limb(shoulder, shoulder + (free_hand - shoulder) * 0.55 + Vector2(-4, 3), free_hand, 6.0)
	var hand := sword_hand_position()
	limb(shoulder, shoulder + (hand - shoulder) * 0.5 + Vector2(5, 7), hand, 6.0)
	var axis := (shoulder - hip).normalized()
	var side := Vector2(-axis.y, axis.x)
	draw_colored_polygon(PackedVector2Array([hip - side * 8, shoulder - side * 9, shoulder + side * 9, hip + side * 7]), ink_color)
	draw_circle(head, 10.0, ink_color)
	draw_line(head + Vector2(4, -1), head + Vector2(9, -2), Color(0.86, 0.85, 0.72), 2.0, true)

func draw_legs(hip: Vector2) -> void:
	if pose_mode == "air":
		limb(hip, Vector2(12, -22), Vector2(20, -10 if falling else -25), 8.0)
		limb(hip, Vector2(-18, -16), Vector2(-26, -3 if falling else -12), 7.0)
		return
	if pose_mode == "idle":
		limb(hip, Vector2(8, -15), Vector2(12, 0), 8.0)
		limb(hip, Vector2(-13, -15), Vector2(-17, 0), 7.0)
		return
func limb(start: Vector2, middle: Vector2, end: Vector2, thickness: float) -> void:
	draw_polyline(PackedVector2Array([start, middle, end]), ink_color, thickness, true)
	draw_circle(middle, thickness * 0.5, ink_color)
	draw_circle(end, thickness * 0.5, ink_color)

func draw_roll() -> void:
	draw_circle(Vector2(-3, -21), 11.0, ink_color)
	draw_circle(head_position(), 8.0, ink_color)
	limb(Vector2(-5, -19), Vector2(-10, -9), Vector2(2, -8), 7.0)
	limb(Vector2(1, -19), Vector2(11, -14), Vector2(6, -7), 7.0)
	limb(Vector2(5, -24), Vector2(12, -20), Vector2(6, -17), 5.0)
	draw_line(Vector2(9, -29), Vector2(13, -30), Color(0.86, 0.85, 0.72), 2.0, true)
