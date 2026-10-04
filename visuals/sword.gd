extends Node2D

var combat: Node2D

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var progress := 0.0
	if is_instance_valid(combat) and combat.slash_remaining > 0.0:
		progress = 1.0 - combat.slash_remaining / combat.SWORD_DURATION
	var angle := lerpf(-1.3, 1.1, progress) if progress > 0.0 else -0.8
	var hand: Vector2 = get_parent().sword_hand_position()
	var direction := Vector2.from_angle(angle)
	draw_line(hand - direction * 12, hand, Color("352f3c"), 6.0, true)
	draw_line(hand - direction.orthogonal() * 7, hand + direction.orthogonal() * 7, Color("b49349"), 4.0, true)
	draw_line(hand, hand + direction * 52, Color("253c48"), 7.0, true)
	draw_line(hand, hand + direction * 52, Color("e8f7f5"), 3.0, true)
	if progress > 0.0:
		draw_arc(hand, 70, angle - 0.9, angle, 24, Color(0.3, 0.85, 0.94, 0.7), 8.0, true)
