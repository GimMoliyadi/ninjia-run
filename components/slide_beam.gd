@tool
class_name SlideBeam
extends Area2D

signal player_contact(player: Node2D, damage: float)

const BeamMotion := preload("res://patterns/player_motion_profile.gd")
const BASE_SIZE := Vector2(BeamMotion.BODY_SIZE.x * 2.0, BeamMotion.SLIDE_HEIGHT)
const CHAIN_PITCH := 16.0
const CHAIN_WIDTH := 2.0
const CAP_HEIGHT := 5.0
const BRACKET_WIDTH := 8.0
const WARNING_SPACING := 22.0
const INK := Color("263633")
const FACE := Color("506255")
const EDGE := Color("9aab8b")
const WARNING := Color("d68d57")

@export var damage := 8.0
@export var size := BASE_SIZE:
	set(value):
		size = Vector2(maxf(1.0, value.x), maxf(1.0, value.y))
		if is_node_ready():
			_update_shape()
		queue_redraw()


func _ready() -> void:
	_update_shape()
	if not Engine.is_editor_hint():
		add_to_group("hazard")
		body_entered.connect(on_body_entered)


func _update_shape() -> void:
	var collider: CollisionShape2D = $CollisionShape2D
	var shape := RectangleShape2D.new()
	shape.size = size
	collider.shape = shape
	collider.position = size * 0.5


func on_body_entered(body: Node2D) -> void:
	if body.has_method("is_sliding"):
		player_contact.emit(body, damage)


func _draw() -> void:
	_draw_chains()
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	draw_rect(Rect2(3.0, CAP_HEIGHT, size.x - 6.0, size.y - CAP_HEIGHT * 2.0), FACE)
	draw_rect(Rect2(0.0, 0.0, size.x, CAP_HEIGHT), EDGE)
	for x in [0.0, size.x - BRACKET_WIDTH]:
		draw_rect(Rect2(x, 0.0, BRACKET_WIDTH, size.y), INK.lightened(0.12))
	var stripe_y := size.y - CAP_HEIGHT
	draw_rect(Rect2(0.0, stripe_y, size.x, CAP_HEIGHT), WARNING.darkened(0.2))
	for index in int(size.x / WARNING_SPACING):
		var x := BRACKET_WIDTH + index * WARNING_SPACING
		draw_polyline(PackedVector2Array([
			Vector2(x, stripe_y - 7.0), Vector2(x + 5.0, stripe_y - 2.0),
			Vector2(x + 10.0, stripe_y - 7.0),
		]), WARNING, 2.0, true)
	draw_rect(Rect2(Vector2.ZERO, size), INK, false, 1.5)


func _draw_chains() -> void:
	# 吊链只作支撑提示；承伤范围仅为短横梁的实体矩形。
	for x in [size.x * 0.2, size.x * 0.8]:
		draw_line(Vector2(x, -BeamMotion.GROUND_Y), Vector2(x, 0.0), INK, CHAIN_WIDTH, true)
		for index in int(BeamMotion.GROUND_Y / CHAIN_PITCH):
			var y := -index * CHAIN_PITCH
			draw_line(Vector2(x - 2.0, y - 5.0), Vector2(x + 2.0, y - 1.0), EDGE.darkened(0.25), 1.0, true)
