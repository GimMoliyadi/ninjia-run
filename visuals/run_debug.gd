extends Node2D

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	for node in get_parent().find_children("*", "Bone2D", true, false):
		var bone := node as Bone2D
		var start := to_local(bone.global_position)
		var end := to_local(bone.to_global(Vector2(bone.length, 0)))
		draw_line(start, end, Color(0.1, 1.0, 0.8), 0.7, true)
		draw_circle(start, 1.0, Color(1.0, 0.65, 0.15))
