extends Node2D

const BAR_SIZE := Vector2(60, 8)
const HEAD_MARGIN := 18.0
var fraction := 1.0
@onready var player: Variant = get_parent()

func _ready() -> void:
	z_index = 20
	player.health_changed.connect(update_health)
	update_health(player.health, player.MAX_HP)

func update_health(current: float, maximum: float) -> void:
	fraction = clampf(current / maximum, 0.0, 1.0)
	visible = current < maximum
	queue_redraw()

func _process(_delta: float) -> void:
	position.y = player.body_collision.position.y - player.body_collision.shape.size.y / 2.0 - HEAD_MARGIN

func _draw() -> void:
	var origin := Vector2(-BAR_SIZE.x / 2.0, 0)
	draw_rect(Rect2(origin - Vector2(2, 2), BAR_SIZE + Vector2(4, 4)), Color("17232c"))
	draw_rect(Rect2(origin, BAR_SIZE), Color("633b3d"))
	draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * fraction, BAR_SIZE.y)), Color("f16c58"))
