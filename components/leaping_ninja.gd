extends Area2D

signal player_contact(player: Node2D, damage: float)

const Target := preload("res://components/combat_target.gd")
const BODY_SIZE := Vector2(44.0, 60.0)
const BODY_RADIUS := BODY_SIZE.x * 0.5
const LOW_JUMP_HEIGHT := 36.0
const FLIGHT_TIME := 0.72
const HIGH_JUMP_HEIGHT := 150.0
const STAND_LEAD_TIME := 0.55
const FALL_GRAVITY_RATIO := 1.5
const WARNING_TIME := 0.12
const STRETCH_TIME := 0.10
const REFERENCE_SPEED := 400.0
const ENTRY_MARGIN := 32.0
const EXIT_MARGIN := 80.0
const SLASH_TRIGGER_DISTANCE := 80.0
const SLASH_REACH := 42.0
const SLASH_HEIGHT := 27.0
const SLASH_RADIUS := 8.0
const SLASH_DURATION := 0.32
const COLLISION_STEP := 1.0 / 120.0
const DAMAGE := 15.0

@export_enum("low", "high") var jump_kind := "low"
@export var crossing_time := 1.25
@export var launch_delay := -1.0
@onready var body: Node2D = $Body
enum State { SPAWN, JUMP_IN, LAND, IDLE, ATTACK }
var state := State.SPAWN
var age := 0.0
var launch_time := 0.0
var flight_time := 0.0
var ascent_time := 0.0
var rise_gravity := 0.0
var velocity := Vector2.ZERO
var clock_scale := 1.0
var launched := false
var body_scale := Vector2.ONE
var crossing_position := Vector2.ZERO
var entry_position := Vector2.ZERO
var horizontal_speed := 0.0
var previous_player_position := Vector2.ZERO
var slash_started := -1.0
var contacted := false

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	add_to_group("hazard")
	add_to_group("destructible")
	add_to_group("leaping_ninja")
	body.ink_color = Color("413b4c") if jump_kind == "high" else Color("41302d")
	z_index = 3

func initialize(player: Node2D) -> void:
	collision_layer = 0
	crossing_position = global_position
	clock_scale = REFERENCE_SPEED / maxf(player.run_speed, player.velocity.x)
	flight_time = FLIGHT_TIME
	var height := HIGH_JUMP_HEIGHT if jump_kind == "high" else LOW_JUMP_HEIGHT
	ascent_time = flight_time / (1.0 + 1.0 / sqrt(FALL_GRAVITY_RATIO))
	rise_gravity = 2.0 * height / (ascent_time * ascent_time)
	launch_time = launch_delay if launch_delay >= 0.0 else maxf(WARNING_TIME, crossing_time * clock_scale - FLIGHT_TIME - STAND_LEAD_TIME)
	entry_position = Vector2(maxf(screen_edge(get_viewport_rect().size.x), crossing_position.x) + ENTRY_MARGIN, crossing_position.y)
	global_position = entry_position
	previous_player_position = player.global_position
	body_scale = body.scale
	update_pose()

func screen_edge(screen_x: float) -> float:
	return (get_canvas_transform().affine_inverse() * Vector2(screen_x, 0.0)).x

func launch() -> void:
	collision_layer = 2
	launched = true
	state = State.JUMP_IN
	entry_position.x = maxf(screen_edge(get_viewport_rect().size.x), crossing_position.x) + ENTRY_MARGIN
	global_position = entry_position
	horizontal_speed = (crossing_position.x - entry_position.x) / flight_time
	velocity = Vector2(horizontal_speed, -rise_gravity * ascent_time)

func advance(delta: float, player: Node2D) -> void:
	# Distance-driven runners pass reference-speed seconds, not wall-clock seconds.
	delta *= REFERENCE_SPEED / maxf(player.run_speed, player.velocity.x)
	var steps := maxi(1, ceili(delta / COLLISION_STEP))
	var player_start := previous_player_position
	for index in steps:
		var step := delta / steps
		var previous_age := age
		age += step
		if age < launch_time:
			continue
		if not launched:
			launch()
		var previous := global_position
		if state == State.JUMP_IN:
			move_jump(minf(step, age - launch_time))
		if state == State.LAND:
			state = State.IDLE
		var fraction := float(index + 1) / steps
		var sample_player := player_start.lerp(player.global_position, fraction)
		if state == State.IDLE and slash_started < 0.0:
			var approach: float = global_position.x - sample_player.x
			if approach >= 0.0 and approach <= SLASH_TRIGGER_DISTANCE:
				slash_started = age
				state = State.ATTACK
		if state == State.ATTACK and age - slash_started > SLASH_DURATION:
			state = State.IDLE
		var start_fraction := float(index) / steps
		if previous_age < launch_time:
			start_fraction = (launch_time - previous_age + index * step) / delta
		var last_player := player_start.lerp(player.global_position, start_fraction)
		check_contact(player, previous + player.global_position - last_player, global_position + player.global_position - sample_player)
	previous_player_position = player.global_position
	if launched and player.global_position.x > crossing_position.x + EXIT_MARGIN:
		queue_free()
	update_pose()

func move_jump(delta: float) -> void:
	global_position.x += velocity.x * delta
	if velocity.y < 0.0:
		var rise_step := minf(delta, -velocity.y / rise_gravity)
		global_position.y += velocity.y * rise_step + 0.5 * rise_gravity * rise_step * rise_step
		velocity.y += rise_gravity * rise_step
		delta -= rise_step
	if delta > 0.0:
		var gravity := rise_gravity * FALL_GRAVITY_RATIO
		global_position.y += velocity.y * delta + 0.5 * gravity * delta * delta
		velocity.y += gravity * delta
	if global_position.y >= crossing_position.y and velocity.y >= 0.0:
		global_position.x = crossing_position.x
		global_position.y = crossing_position.y
		velocity = Vector2.ZERO
		state = State.LAND

func check_contact(player: Node2D, previous: Vector2, current: Vector2) -> void:
	if contacted:
		return
	if is_slashing():
		var tip := Vector2(-BODY_RADIUS - SLASH_REACH, -SLASH_HEIGHT)
		var hand := Vector2(-13.0, -SLASH_HEIGHT)
		if Target.swept_shape(player.body_collision, previous + tip, current + tip, SLASH_RADIUS) or Target.swept_shape(player.body_collision, current + hand, current + tip, SLASH_RADIUS):
			contacted = true
	if contacted:
		player_contact.emit(player, DAMAGE)

func is_slashing() -> bool:
	return state == State.ATTACK

func update_pose() -> void:
	body.visible = launched
	var airborne := state == State.JUMP_IN
	var stretch := clampf((age - launch_time) / STRETCH_TIME, 0.0, 1.0)
	body.scale = body_scale * Vector2(0.9, 1.15).lerp(Vector2.ONE, stretch)
	body.set_pose(age * 16.0, "air" if airborne else "idle", velocity.y >= 0.0)
	queue_redraw()

func _draw() -> void:
	if not launched:
		if age >= launch_time - WARNING_TIME:
			var center := to_local(Vector2(screen_edge(get_viewport_rect().size.x - 12.0), crossing_position.y - BODY_SIZE.y * 0.5))
			var color := Color("829da4") if jump_kind == "high" else Color("c07d48")
			draw_line(center + Vector2(8, -12), center + Vector2(-8, 0), color, 4.0, true)
			draw_line(center + Vector2(-8, 0), center + Vector2(8, 12), color, 4.0, true)
		return
	var accent := Color("829da4") if jump_kind == "high" else Color("c07d48")
	draw_line(Vector2(-17, -55), Vector2(2, -55), accent, 4.0, true)
	draw_polyline(PackedVector2Array([Vector2(4, -52), Vector2(25, -49), Vector2(37, -55)]), accent, 5.0, true)
	if is_slashing():
		var swing := clampf((age - slash_started) / SLASH_DURATION, 0.0, 1.0)
		draw_arc(Vector2(-12, -SLASH_HEIGHT), SLASH_REACH + 10.0, PI - 0.65 + swing * 0.45, PI + 0.3 + swing * 0.45, 16, Color("e7dbac"), 4.0, true)
		draw_line(Vector2(-13, -SLASH_HEIGHT), Vector2(-BODY_RADIUS - SLASH_REACH, -SLASH_HEIGHT), Color("f1e8c7"), 3.0, true)
	else:
		draw_line(Vector2(7, -32), Vector2(28, -65), Color("afa797"), 3.0, true)
