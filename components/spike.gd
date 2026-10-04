class_name Spike
extends Area2D

signal player_contact(player: Node2D, damage: float)

@export var damage := 12.0
@export var size := Vector2(24.0, 72.0)

const SPIKE_COLOR := Color("293a39")
const EDGE_COLOR := Color("d18459")
const BASE_COLOR := Color("67463c")
const TOOTH_WIDTH := 24.0

func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var collider := CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	collider.shape = shape
	collider.position = Vector2(size.x * 0.5, -size.y * 0.5)
	add_child(collider)
	add_to_group("hazard")
	add_to_group("destructible")
	body_entered.connect(on_body_entered)
	queue_redraw()

func _draw() -> void:
	var count := maxi(1, int(ceil(size.x / TOOTH_WIDTH)))
	var step := size.x / count
	draw_rect(Rect2(0, -6, size.x, 6), BASE_COLOR)
	for index in count:
		var left := index * step
		var tip := Vector2(left + step * 0.5, -size.y)
		draw_colored_polygon(PackedVector2Array([Vector2(left, 0), tip, Vector2(left + step, 0)]), SPIKE_COLOR)
		draw_line(tip, Vector2(left + step * 0.5 + step * 0.2, -3), EDGE_COLOR, 1.5, true)

func on_body_entered(body: Node2D) -> void:
	if not is_queued_for_deletion() and body.has_method("take_damage"):
		player_contact.emit(body, damage)
