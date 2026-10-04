extends Area2D

const Target := preload("res://components/combat_target.gd")
const RADIUS := 11.0
const DAMAGE := 10.0
const LIFETIME := 3.5
@export var collision_radius: float = RADIUS
var velocity := Vector2.LEFT * 280.0
var age := 0.0
var spin := 0.0
var previous_player_position := Vector2.ZERO

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	add_to_group("hazard")
	add_to_group("destructible")
	add_to_group("dart")
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	var shape := CircleShape2D.new()
	shape.radius = collision_radius
	collider.shape = shape
	add_child(collider)
	z_index = 3

func advance(delta: float, player: Node2D) -> void:
	var previous := global_position
	global_position += velocity * delta
	age += delta
	spin += delta * 12.0
	var player_motion := player.global_position - previous_player_position
	# 换侧是瞬时切换碰撞位置，不能把绳子两侧之间补成受击路径。
	if player.movement_state == player.MovementState.ROPE and absf(player_motion.y) > player.PLAYER_HEIGHT / 2.0:
		player_motion.y = 0.0
	previous_player_position = player.global_position
	if Target.swept_shape(player.body_collision, previous + player_motion, global_position, collision_radius):
		player.take_damage(DAMAGE)
		queue_free()
	if age >= LIFETIME or global_position.x < player.global_position.x - 220.0:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var points := PackedVector2Array()
	for index in 8:
		points.append(Vector2.from_angle(spin + index * TAU / 8.0) * (collision_radius if index % 2 == 0 else collision_radius * 0.35))
	draw_colored_polygon(points, Color("243545"))
	points.append(points[0])
	draw_polyline(points, Color("ec8b52"), 1.5, true)
	draw_circle(Vector2.ZERO, collision_radius * (2.5 / RADIUS), Color("dfe6cc"))
