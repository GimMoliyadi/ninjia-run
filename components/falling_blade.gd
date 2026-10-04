extends Area2D

signal player_contact(player: Node2D, damage: float)

const BladeMotion := preload("res://patterns/player_motion_profile.gd")
const BladeTarget := preload("res://components/combat_target.gd")
const BLADE_RADIUS: float = BladeMotion.SLIDE_HEIGHT * 0.9
# GDScript 常量不能调用 jump_height()，这里使用其同一运动公式。
const START_HEIGHT: float = BladeMotion.JUMP_SPEED * BladeMotion.JUMP_SPEED / (2.0 * BladeMotion.Player.ASCENT_GRAVITY) * 1.6
const FLOOR_CLEARANCE: float = BladeMotion.SLIDE_HEIGHT + 8.0
const DROP_DISTANCE: float = START_HEIGHT - FLOOR_CLEARANCE - BLADE_RADIUS
const WARNING_TIME: float = 0.75
const DROP_TIME: float = 0.09
const HOLD_TIME: float = 0.40
const TRIGGER_DISTANCE: float = BladeMotion.Player.SLIDE_BURST_SPEED * (WARNING_TIME + DROP_TIME * 0.5)
const EXIT_MARGIN: float = BLADE_RADIUS + BladeMotion.BODY_SIZE.x
const DAMAGE: float = 10.0
const SPIN_SPEED: float = 12.0
const BLADE_TOOTH_COUNT: int = 10
const HANGER_HEIGHT: float = BLADE_RADIUS * 1.5
const VIEW_MARGIN: float = 8.0
const METAL_COLOR: Color = Color("293633")
const EDGE_COLOR: Color = Color("788174")
const WARNING_COLOR: Color = Color("d86634")
const HUB_COLOR: Color = Color("c9bc81")

enum State { HANGING, WARNING, DROPPING, HOLDING, FINISHED }
var state: State = State.HANGING
var state_time: float = 0.0
var spin: float = 0.0
var hanging_position: Vector2 = Vector2.ZERO
var previous_player_position: Vector2 = Vector2.ZERO
var contacted: bool = false
var initialized: bool = false

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	add_to_group("hazard")
	add_to_group("destructible")
	var collider: CollisionShape2D = $CollisionShape2D
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = BLADE_RADIUS
	collider.shape = shape
	z_index = 3

func initialize(player: Node2D) -> void:
	if initialized:
		return
	hanging_position = global_position
	previous_player_position = player.global_position
	initialized = true
	queue_redraw()

func advance(delta: float, player: Node2D) -> void:
	if not initialized or state == State.FINISHED or is_queued_for_deletion():
		return
	# 距离推进传入基础跑速折算秒数，换回实秒，滑铲不能压缩预告。
	var seconds: float = delta * BladeMotion.RUN_SPEED / maxf(BladeMotion.RUN_SPEED, maxf(player.run_speed, player.velocity.x))
	var previous: Vector2 = global_position
	match state:
		State.HANGING:
			_try_start_warning(player)
		State.WARNING:
			_advance_warning(seconds)
		State.DROPPING:
			_advance_drop(seconds)
			_check_contact(player, previous)
		State.HOLDING:
			_check_contact(player, previous)
			state_time += seconds
			if state_time >= HOLD_TIME:
				_finish()
	previous_player_position = player.global_position
	if player.global_position.x > hanging_position.x + EXIT_MARGIN:
		_finish()
	queue_redraw()

func _try_start_warning(player: Node2D) -> void:
	var approach: float = hanging_position.x - player.global_position.x
	if approach < 0.0 or approach > TRIGGER_DISTANCE or not _warning_is_visible():
		return
	state = State.WARNING
	state_time = 0.0

func _advance_warning(delta: float) -> void:
	if not _warning_is_visible():
		return
	state_time += delta
	if state_time >= WARNING_TIME:
		state = State.DROPPING
		state_time = 0.0

func _advance_drop(delta: float) -> void:
	state_time = minf(state_time + delta, DROP_TIME)
	var progress: float = state_time / DROP_TIME
	global_position = hanging_position + Vector2.DOWN * DROP_DISTANCE * progress * progress
	spin += delta * SPIN_SPEED
	if state_time >= DROP_TIME:
		state = State.HOLDING
		state_time = 0.0

func _check_contact(player: Node2D, previous: Vector2) -> void:
	if contacted:
		return
	var player_motion: Vector2 = player.global_position - previous_player_position
	if BladeTarget.swept_shape(player.body_collision, previous + player_motion, global_position, BLADE_RADIUS):
		contacted = true
		player_contact.emit(player, DAMAGE)

func _warning_is_visible() -> bool:
	var canvas: Transform2D = get_canvas_transform()
	var view: Rect2 = get_viewport_rect().grow(-VIEW_MARGIN)
	var blade: Vector2 = canvas * hanging_position
	var floor_point: Vector2 = canvas * (hanging_position + Vector2.DOWN * START_HEIGHT)
	var extent: Vector2 = Vector2(BLADE_RADIUS, BLADE_RADIUS) * canvas.get_scale().abs()
	var blade_bounds: Rect2 = Rect2(blade - extent, extent * 2.0)
	var floor_left: Vector2 = floor_point - Vector2(extent.x, 0.0)
	var floor_right: Vector2 = floor_point + Vector2(extent.x, 0.0)
	return view.encloses(blade_bounds) and view.has_point(floor_left) and view.has_point(floor_right)

func _finish() -> void:
	state = State.FINISHED
	queue_free()

func _draw() -> void:
	if not initialized or state == State.FINISHED:
		return
	_draw_hanger()
	if state != State.HANGING:
		_draw_landing_warning()
	_draw_blade()

func _draw_hanger() -> void:
	var anchor: Vector2 = to_local(hanging_position) + Vector2.UP * HANGER_HEIGHT
	var beam_half: float = BLADE_RADIUS * 0.6
	draw_line(anchor + Vector2(-beam_half, 0.0), anchor + Vector2(beam_half, 0.0), EDGE_COLOR, 4.0, true)
	draw_line(anchor, Vector2.UP * BLADE_RADIUS, EDGE_COLOR, 2.0, true)
	draw_circle(anchor, BLADE_RADIUS * 0.1, HUB_COLOR)

func _draw_landing_warning() -> void:
	var floor_point: Vector2 = to_local(hanging_position + Vector2.DOWN * START_HEIGHT)
	var landing: Vector2 = floor_point + Vector2.UP * (FLOOR_CLEARANCE + BLADE_RADIUS)
	var progress: float = clampf(state_time / WARNING_TIME, 0.0, 1.0) if state == State.WARNING else 1.0
	var color: Color = WARNING_COLOR
	color.a = 0.55 + progress * 0.4
	draw_line(floor_point + Vector2(-BLADE_RADIUS, -3.0), floor_point + Vector2(BLADE_RADIUS, -3.0), color, 3.0, true)
	draw_line(floor_point + Vector2.UP * 5.0, landing + Vector2.DOWN * BLADE_RADIUS, color, 1.0, true)
	draw_arc(landing, BLADE_RADIUS, 0.0, TAU, 24, color, 2.0, true)
	_draw_warning_arrow(landing + Vector2.UP * (BLADE_RADIUS + 12.0), color)

func _draw_warning_arrow(point: Vector2, color: Color) -> void:
	var half_width: float = BLADE_RADIUS * 0.25
	draw_polyline(PackedVector2Array([point + Vector2(-half_width, -half_width), point, point + Vector2(half_width, -half_width)]), color, 3.0, true)

func _draw_blade() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for tooth: int in BLADE_TOOTH_COUNT:
		var angle: float = spin + float(tooth) * TAU / BLADE_TOOTH_COUNT
		points.append(Vector2.from_angle(angle) * BLADE_RADIUS)
		points.append(Vector2.from_angle(angle + TAU / BLADE_TOOTH_COUNT * 0.65) * BLADE_RADIUS * 0.72)
	draw_colored_polygon(points, METAL_COLOR)
	points.append(points[0])
	draw_polyline(points, WARNING_COLOR if state != State.HANGING else EDGE_COLOR, 1.5, true)
	draw_arc(Vector2.ZERO, BLADE_RADIUS * 0.5, 0.0, TAU, 24, EDGE_COLOR, 2.0, true)
	draw_circle(Vector2.ZERO, BLADE_RADIUS * 0.18, HUB_COLOR)
	draw_circle(Vector2.ZERO, BLADE_RADIUS * 0.08, METAL_COLOR)
