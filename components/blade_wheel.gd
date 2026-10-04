extends "res://components/dart.gd"

const WheelMotion := preload("res://patterns/player_motion_profile.gd")
const WHEEL_RADIUS: float = WheelMotion.SLIDE_HEIGHT * 0.75
const WHEEL_SPEED_RATIO: float = 0.35
const WHEEL_TOOTH_COUNT: int = 12
const WHEEL_SPOKE_COUNT: int = 6
const WHEEL_ROOT_RATIO: float = 0.8
const WHEEL_METAL: Color = Color("293633")
const WHEEL_RIM: Color = Color("69766b")
const WHEEL_DANGER: Color = Color("d86634")
const WHEEL_HUB: Color = Color("c9bc81")

func _init() -> void:
	collision_radius = WHEEL_RADIUS
	velocity = Vector2.LEFT * WheelMotion.RUN_SPEED * WHEEL_SPEED_RATIO

func _draw() -> void:
	var teeth: PackedVector2Array = _wheel_outline()
	draw_colored_polygon(teeth, WHEEL_METAL)
	teeth.append(teeth[0])
	draw_polyline(teeth, WHEEL_DANGER, 1.5, true)
	draw_circle(Vector2.ZERO, collision_radius * 0.68, WHEEL_RIM)
	draw_circle(Vector2.ZERO, collision_radius * 0.55, WHEEL_METAL)
	_draw_wheel_hub()

func _wheel_outline() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for tooth: int in WHEEL_TOOTH_COUNT:
		for corner: int in 4:
			var angle: float = spin + (float(tooth) + float(corner) * 0.25) * TAU / WHEEL_TOOTH_COUNT
			var radius: float = collision_radius if corner == 1 or corner == 2 else collision_radius * WHEEL_ROOT_RATIO
			points.append(Vector2.from_angle(angle) * radius)
	return points

func _draw_wheel_hub() -> void:
	for spoke: int in WHEEL_SPOKE_COUNT:
		var direction: Vector2 = Vector2.from_angle(spin + float(spoke) * TAU / WHEEL_SPOKE_COUNT)
		draw_line(direction * collision_radius * 0.2, direction * collision_radius * 0.55, WHEEL_RIM, 2.0, true)
	draw_circle(Vector2.ZERO, collision_radius * 0.23, WHEEL_HUB)
	draw_circle(Vector2.ZERO, collision_radius * 0.1, WHEEL_METAL)
