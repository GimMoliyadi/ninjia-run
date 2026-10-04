extends Bone2D

@export_enum("limb", "torso", "head", "weapon", "hip") var part := "limb"
@export var segment_length := 18.0
@export var thickness := 7.0

func _init() -> void:
	set_autocalculate_length_and_angle(false)

func _draw() -> void:
	match part:
		"head":
			draw_circle(Vector2.ZERO, 10.0, Color.BLACK)
			draw_line(Vector2(4, -1), Vector2(9, -2), Color(0.86, 0.85, 0.72), 2.0, true)
		"weapon":
			var tip := Vector2(0, 44)
			draw_line(Vector2(11, 3), Vector2.ZERO, Color("352f3c"), 6.0, true)
			draw_line(Vector2(0, -7), Vector2(0, 7), Color("b49349"), 4.0, true)
			draw_line(Vector2.ZERO, tip, Color("253c48"), 7.0, true)
			draw_line(Vector2.ZERO, tip, Color("e8f7f5"), 3.0, true)
		"hip":
			draw_circle(Vector2.ZERO, 7.0, Color.BLACK)
		_:
			draw_line(Vector2.ZERO, Vector2(segment_length, 0), Color.BLACK, thickness, true)
			if part == "limb":
				draw_circle(Vector2(segment_length, 0), thickness * 0.5, Color.BLACK)
