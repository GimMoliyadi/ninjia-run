extends StaticBody2D

@export var size: Vector2 = Vector2(184, 84)
@export var crumble_delay: float = 0.0
@export var crumble_over_pit: bool = false

const JOINT_HEIGHT: float = 36.0
const CAP_HEIGHT: float = 8.0
const TOP_CONTACT_DOT: float = 0.99
const DEBRIS_TIME: float = 0.28
const DEBRIS_COUNT: int = 7
const CRACK_COLOR: Color = Color("d86634")
const DEBRIS_COLOR: Color = Color("69766b")

enum State { STABLE, CRACKING, CRUMBLED }
var state: State = State.STABLE
var state_time: float = 0.0
var tracked_player: CharacterBody2D
var collider: CollisionShape2D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("jump_pillar")
	collider = CollisionShape2D.new()
	collider.name = "CollisionShape2D"
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = size
	collider.shape = shape
	collider.position = Vector2(size.x * 0.5, -size.y * 0.5)
	add_child(collider)
	set_physics_process(false)

func initialize(player: Node2D) -> void:
	if crumble_delay <= 0.0:
		return
	tracked_player = player as CharacterBody2D
	if not is_instance_valid(tracked_player):
		push_error("JumpPillar: 碎台需要 CharacterBody2D 玩家")
		return
	# 必须在玩家本帧 move_and_slide 后读取，不能拿上一帧接触推断落脚。
	process_physics_priority = tracked_player.process_physics_priority + 1
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(tracked_player):
		queue_free()
		return
	if not bool(tracked_player.get("active")) or is_queued_for_deletion():
		return
	match state:
		State.STABLE:
			if _has_top_contact():
				state = State.CRACKING
				state_time = 0.0
		State.CRACKING:
			state_time += delta
			if state_time >= crumble_delay:
				_collapse()
		State.CRUMBLED:
			state_time += delta
			if state_time >= DEBRIS_TIME:
				queue_free()
	if state != State.STABLE:
		queue_redraw()

func _has_top_contact() -> bool:
	for index: int in tracked_player.get_slide_collision_count():
		var contact: KinematicCollision2D = tracked_player.get_slide_collision(index)
		if contact.get_collider() == self and contact.get_normal().dot(Vector2.UP) >= TOP_CONTACT_DOT:
			return true
	return false

func _collapse() -> void:
	state = State.CRUMBLED
	state_time = 0.0
	collider.set_deferred("disabled", true)
	set_deferred("collision_layer", 0)

func _draw() -> void:
	if state == State.CRUMBLED:
		_draw_debris()
		return
	_draw_stone()
	if state == State.CRACKING:
		_draw_cracks()
	elif crumble_delay > 0.0:
		_draw_fragile_mark()

func _draw_stone() -> void:
	draw_rect(Rect2(0, -size.y, size.x, size.y), Color("394944"))
	draw_rect(Rect2(size.x - 12, -size.y, 12, size.y), Color("273933"))
	draw_rect(Rect2(0, -size.y, size.x, CAP_HEIGHT), Color("adbb89"))
	draw_line(Vector2(8, -size.y + 2), Vector2(size.x - 8, -size.y + 2), Color("e1d5a0"), 2)
	for index: int in int(size.y / JOINT_HEIGHT):
		var y: float = -index * JOINT_HEIGHT
		draw_line(Vector2(5, y), Vector2(size.x - 15, y), Color("52625a"), 2)
	var center: Vector2 = Vector2(size.x * 0.5, -size.y + 24)
	draw_polyline(PackedVector2Array([center + Vector2(-6, 4), center, center + Vector2(6, 4)]), Color("c9bc81"), 2, true)

func _draw_fragile_mark() -> void:
	var center := Vector2(size.x * 0.5, -size.y)
	var tint := CRACK_COLOR.darkened(0.25)
	draw_line(Vector2(4.0, -size.y + CAP_HEIGHT), Vector2(size.x - 4.0, -size.y + CAP_HEIGHT), tint, 2.0)
	draw_polyline(PackedVector2Array([
		center + Vector2(-size.x * 0.12, 2.0), center + Vector2(0.0, size.y * 0.18),
		center + Vector2(-size.x * 0.04, size.y * 0.34),
	]), tint, 1.5, true)

func _draw_cracks() -> void:
	var progress: float = clampf(state_time / crumble_delay, 0.0, 1.0)
	var color: Color = CRACK_COLOR
	color.a = 0.55 + progress * 0.45
	var top: Vector2 = Vector2(size.x * 0.5, -size.y)
	var split: Vector2 = top + Vector2(size.x * 0.08, size.y * 0.4)
	var crack: PackedVector2Array = PackedVector2Array([
		top, top + Vector2(-size.x * 0.1, size.y * 0.2), split,
		top + Vector2(-size.x * 0.06, size.y * 0.7), top + Vector2(size.x * 0.04, size.y),
	])
	draw_polyline(crack, color, 1.5 + progress * 1.5, true)
	draw_line(split, top + Vector2(size.x * 0.3, size.y * 0.3), color, 2.0, true)
	draw_line(split, top + Vector2(-size.x * 0.25, size.y * 0.6), color, 2.0, true)
	draw_rect(Rect2(6.0, -size.y - 5.0, (size.x - 12.0) * (1.0 - progress), 3.0), color)

func _draw_debris() -> void:
	var progress: float = clampf(state_time / DEBRIS_TIME, 0.0, 1.0)
	var color: Color = DEBRIS_COLOR
	color.a = 1.0 - progress
	for index: int in DEBRIS_COUNT:
		_draw_fragment(index, progress, color)

func _draw_fragment(index: int, progress: float, color: Color) -> void:
	var fraction: float = float(index) / float(DEBRIS_COUNT - 1)
	var start: Vector2 = Vector2(size.x * fraction, -size.y * (0.75 + float(index % 2) * 0.12))
	var drift: Vector2 = Vector2((fraction - 0.5) * size.x * 0.5, -size.y * 0.35) * progress
	var center: Vector2 = start + drift + Vector2.DOWN * size.y * 1.7 * progress * progress
	var radius: float = clampf(size.x / float(DEBRIS_COUNT * 6), 3.0, 7.0)
	var points: PackedVector2Array = PackedVector2Array()
	for corner: int in 3:
		var angle: float = float(index) * 0.8 + progress * TAU + float(corner) * TAU / 3.0
		points.append(center + Vector2.from_angle(angle) * radius)
	draw_colored_polygon(points, color)
