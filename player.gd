extends CharacterBody2D

signal ninjutsu_requested
signal fireball_requested
signal sword_requested
signal health_changed(current: float, maximum: float)
signal died
signal state_changed(previous: int, current: int)
signal jumped(jump_index: int)
signal landed(speed: float)
signal damaged(amount: float)
signal run_reset

enum MovementState { GROUNDED, AIRBORNE, SLIDE, ROPE }
enum RopeSide { TOP, BOTTOM }
enum RopeState { ROPE_TOP, FLIP_TO_BOTTOM, ROPE_BOTTOM, FLIP_TO_TOP }
enum AirState { NONE, FIRST_JUMP, DOUBLE_JUMP_ROLL, SECOND_JUMP, FALL }

const RUN_SPEED := 400.0
const SLIDE_BURST_SPEED := 620.0
const SLIDE_BOOST := SLIDE_BURST_SPEED - RUN_SPEED
const AIR_DRAG := 60.0
const SURFACE_DRAG := 600.0
const FLIP_DURATION := 0.18
const FLIP_BUFFER_TIME := 0.15
const ROPE_REENTRY_TOLERANCE := 2.0
const SLIDE_DURATION := 0.58
const JUMP_SPEED := -1120.0
const SECOND_JUMP_SPEED := -1080.0
const ASCENT_GRAVITY := 3400.0
const FALL_GRAVITY := 2600.0
const DOUBLE_JUMP_ROLL_DURATION := 0.32
const ROLL_WIDTH := 40.0
const ROLL_HEIGHT := 40.0
const FAST_FALL_SPEED := 1200.0
const COYOTE_TIME := 0.1
const JUMP_BUFFER_TIME := 0.15
const PLAYER_WIDTH := 46.0
const PLAYER_HEIGHT := 66.0
const SLIDE_HEIGHT := 32.0
const MAX_HP := 50.0
const INVULNERABILITY_TIME := 0.7
const HEALTH_REGEN_DELAY := 5.0
const HEALTH_REGEN_RATE := 2.0

@onready var body_collision: CollisionShape2D = $BodyCollision
@onready var rope_detector: Area2D = $RopeDetector
var movement_state := MovementState.AIRBORNE:
	set(value):
		if movement_state == value:
			return
		var previous := movement_state
		movement_state = value
		state_changed.emit(previous, value)

var rope_side := RopeSide.TOP
var boost_speed := 0.0
var preserve_boost := false
var flip_remaining := 0.0
var flip_buffer_remaining := 0.0
var down_buffer_remaining := 0.0
var rope_state := RopeState.ROPE_TOP
var rope_flip_progress := 0.0
var rope_flip_angle := 0.0
var rope_flip_start_y := 0.0
var rope_flip_start_progress := 0.0
var rope_flip_started_airborne := false
var slide_remaining := 0.0
var coyote_remaining := 0.0
var jump_buffer_remaining := 0.0
var queued_rope_jump_count := 0
var fast_falling := false
var landing_slide_queued := false
var jumps_used := 0
var air_state := AirState.FALL
var roll_remaining := 0.0
var roll_hitbox_active := false
var health := MAX_HP
var invulnerability_remaining := 0.0
var health_regen_delay_remaining := 0.0
var active := true
var rope: Area2D
var rope_reentry_locked := false
var airborne_rope_jump_active := false
var previous_physics_y := 0.0
var run_speed := RUN_SPEED

func _ready() -> void:
	body_collision.shape = body_collision.shape.duplicate()
	configure_standing_body()
	previous_physics_y = global_position.y
	velocity.x = run_speed

func _physics_process(delta: float) -> void:
	if not active:
		return
	var frame_start_y := global_position.y
	preserve_boost = false
	update_timers(delta)
	update_health_regeneration(delta)
	capture_jump_input()
	if Input.is_action_just_pressed("ninjutsu"):
		ninjutsu_requested.emit()
	if Input.is_action_just_pressed("fireball"):
		fireball_requested.emit()
	if Input.is_action_just_pressed("sword"):
		sword_requested.emit()
	if rope_reentry_locked and not is_touching_rope():
		rope_reentry_locked = false
	clear_airborne_rope_source_if_invalid()
	if movement_state == MovementState.AIRBORNE:
		try_start_airborne_rope_flip()
	if movement_state != MovementState.ROPE:
		try_attach_to_rope()
	match movement_state:
		MovementState.GROUNDED, MovementState.AIRBORNE:
			update_run(delta)
		MovementState.SLIDE:
			update_slide(delta)
		MovementState.ROPE:
			update_rope(delta)
	update_horizontal_momentum(delta)
	var landing_speed := velocity.y if not is_on_floor() else 0.0
	move_and_slide()
	if is_on_floor() and landing_speed > 0.0:
		landed.emit(landing_speed)
	if movement_state != MovementState.ROPE:
		if is_on_floor():
			airborne_rope_jump_active = false
			down_buffer_remaining = 0.0
			queued_rope_jump_count = 0
			rope = null
			roll_remaining = 0.0
			coyote_remaining = COYOTE_TIME
			jumps_used = 0
			if landing_slide_queued:
				start_slide()
			elif movement_state != MovementState.SLIDE:
				movement_state = MovementState.GROUNDED
			fast_falling = false
			consume_buffered_jump()
		elif movement_state != MovementState.SLIDE:
			movement_state = MovementState.AIRBORNE
	update_air_state()
	if movement_state == MovementState.AIRBORNE or movement_state == MovementState.GROUNDED:
		if roll_remaining <= 0.0 and body_collision.shape.size != Vector2(PLAYER_WIDTH, PLAYER_HEIGHT):
			try_restore_standing_body()
	previous_physics_y = frame_start_y

func update_horizontal_momentum(delta: float) -> void:
	var decay_delta := delta
	if movement_state == MovementState.ROPE:
		decay_delta = 0.0 if is_rope_flipping() else delta
	if not preserve_boost and movement_state != MovementState.SLIDE:
		var drag := AIR_DRAG if movement_state == MovementState.AIRBORNE else SURFACE_DRAG
		boost_speed = move_toward(boost_speed, 0.0, drag * decay_delta)
	velocity.x = run_speed + boost_speed

func update_timers(delta: float) -> void:
	roll_remaining = maxf(0.0, roll_remaining - delta)
	invulnerability_remaining = maxf(0.0, invulnerability_remaining - delta)
	health_regen_delay_remaining = maxf(0.0, health_regen_delay_remaining - delta)
	flip_buffer_remaining = maxf(0.0, flip_buffer_remaining - delta)
	down_buffer_remaining = maxf(0.0, down_buffer_remaining - delta)
	jump_buffer_remaining = maxf(0.0, jump_buffer_remaining - delta)
	if is_on_floor() and velocity.y >= 0.0 and movement_state != MovementState.ROPE:
		coyote_remaining = COYOTE_TIME
		jumps_used = 0
	else:
		coyote_remaining = maxf(0.0, coyote_remaining - delta)

func capture_jump_input() -> void:
	if Input.is_action_just_pressed("slide"):
		flip_buffer_remaining = FLIP_BUFFER_TIME
		down_buffer_remaining = FLIP_BUFFER_TIME
	if Input.is_action_just_pressed("jump"):
		jump_buffer_remaining = JUMP_BUFFER_TIME
		if movement_state == MovementState.ROPE and rope_state == RopeState.FLIP_TO_TOP:
			queued_rope_jump_count += 1

func update_run(delta: float) -> void:
	var grounded := is_on_floor() and velocity.y >= 0.0
	if Input.is_action_just_pressed("slide") and not grounded:
		request_fast_fall()
	if Input.is_action_just_pressed("slide") and grounded and jump_buffer_remaining <= 0.0:
		start_slide()
		update_slide(delta)
		return
	var started_jump := consume_buffered_jump()
	if started_jump or movement_state == MovementState.AIRBORNE or not is_on_floor():
		movement_state = MovementState.AIRBORNE
		apply_airborne_motion(delta)
	else:
		velocity.y = 0.0

func request_fast_fall() -> void:
	jump_buffer_remaining = 0.0
	flip_buffer_remaining = 0.0
	coyote_remaining = 0.0
	if fast_falling:
		landing_slide_queued = true
	else:
		fast_falling = true
		velocity.y = maxf(velocity.y, FAST_FALL_SPEED)

func clear_fast_fall() -> void:
	fast_falling = false
	landing_slide_queued = false

func update_slide(delta: float) -> void:
	if consume_buffered_jump():
		apply_airborne_motion(delta)
		return
	if not is_on_floor():
		finish_slide()
		apply_airborne_motion(delta)
		return
	slide_remaining = maxf(0.0, slide_remaining - delta)
	velocity.y = 0.0
	if slide_remaining <= 0.0:
		finish_slide()

func update_rope(delta: float) -> void:
	if not is_instance_valid(rope):
		detach_from_rope()
		update_run(delta)
		return
	if not rope_detector.overlaps_area(rope) and not is_rope_flipping():
		detach_from_rope()
		update_run(delta)
		return

	if not is_rope_flipping():
		match rope_state:
			RopeState.ROPE_TOP:
				if jump_buffer_remaining > 0.0:
					jump_buffer_remaining = 0.0
					if queued_rope_jump_count > 0:
						queued_rope_jump_count -= 1
					start_jump(JUMP_SPEED)
					if queued_rope_jump_count > 0:
						jump_buffer_remaining = JUMP_BUFFER_TIME
					apply_airborne_motion(delta)
					return
				if flip_buffer_remaining > 0.0 and start_rope_flip(RopeSide.BOTTOM):
					flip_buffer_remaining = 0.0
			RopeState.ROPE_BOTTOM:
				if jump_buffer_remaining > 0.0 and start_rope_flip(RopeSide.TOP):
					jump_buffer_remaining = 0.0
				elif flip_buffer_remaining > 0.0:
					flip_buffer_remaining = 0.0

	if is_rope_flipping():
		update_rope_flip_input()
		update_rope_flip(delta)
		return

	var rope_line: Line2D = rope.get_node("Line")
	var exit_x: float = rope_line.to_global(rope_line.points[-1]).x
	if global_position.x + PLAYER_WIDTH / 2.0 + (run_speed + boost_speed) * delta >= exit_x:
		rope_side = RopeSide.TOP
		rope_state = RopeState.ROPE_TOP
		rope_flip_progress = 0.0
		flip_remaining = 0.0
	velocity.y = 0.0
	global_position.y = rope.global_position.y + rope_offset()

func start_rope_flip(target_side: int) -> bool:
	if target_side == rope_side or is_rope_flipping():
		return false
	var target_y := rope_y_for_side(target_side)
	if test_move(global_transform, Vector2(0.0, target_y - global_position.y)):
		return false
	rope_flip_start_y = global_position.y
	rope_flip_started_airborne = movement_state == MovementState.AIRBORNE
	rope_state = RopeState.FLIP_TO_BOTTOM if target_side == RopeSide.BOTTOM else RopeState.FLIP_TO_TOP
	rope_flip_progress = 0.0 if target_side == RopeSide.BOTTOM else 1.0
	rope_flip_start_progress = rope_flip_progress
	rope_flip_angle = 0.0
	flip_remaining = FLIP_DURATION
	roll_remaining = DOUBLE_JUMP_ROLL_DURATION
	roll_hitbox_active = true
	body_collision.shape.size = Vector2(ROLL_WIDTH, ROLL_HEIGHT)
	body_collision.position.y = -ROLL_HEIGHT / 2.0
	air_state = AirState.DOUBLE_JUMP_ROLL
	velocity.y = 0.0
	preserve_boost = true
	return true

func update_rope_flip_input() -> void:
	if rope_state == RopeState.FLIP_TO_BOTTOM:
		if jump_buffer_remaining > 0.0:
			jump_buffer_remaining = 0.0
			reverse_rope_flip(RopeState.FLIP_TO_TOP)
		elif flip_buffer_remaining > 0.0:
			flip_buffer_remaining = 0.0
			down_buffer_remaining = 0.0
	else:
		if flip_buffer_remaining > 0.0:
			flip_buffer_remaining = 0.0
			down_buffer_remaining = 0.0
			jump_buffer_remaining = 0.0
			queued_rope_jump_count = 0
			reverse_rope_flip(RopeState.FLIP_TO_BOTTOM)
		elif jump_buffer_remaining > 0.0:
			jump_buffer_remaining = maxf(jump_buffer_remaining, flip_remaining)

func reverse_rope_flip(target_state: int) -> void:
	rope_flip_start_y = global_position.y
	rope_flip_start_progress = rope_flip_progress
	rope_state = target_state
	var target_progress := 1.0 if target_state == RopeState.FLIP_TO_BOTTOM else 0.0
	flip_remaining = FLIP_DURATION if rope_flip_started_airborne else FLIP_DURATION * absf(target_progress - rope_flip_start_progress)

func update_rope_flip(delta: float) -> void:
	var moving_down := rope_state == RopeState.FLIP_TO_BOTTOM
	var target_progress := 1.0 if moving_down else 0.0
	var duration := FLIP_DURATION if rope_flip_started_airborne else FLIP_DURATION * absf(target_progress - rope_flip_start_progress)
	flip_remaining = maxf(0.0, flip_remaining - delta)
	var travel_progress := 1.0 - flip_remaining / duration if duration > 0.0 else 1.0
	rope_flip_progress = lerpf(rope_flip_start_progress, target_progress, travel_progress)
	rope_flip_angle = PI * sin(PI * rope_flip_progress)
	roll_remaining = DOUBLE_JUMP_ROLL_DURATION * (1.0 - rope_flip_angle / TAU)
	velocity.y = 0.0
	var target_side := RopeSide.BOTTOM if moving_down else RopeSide.TOP
	global_position.y = lerpf(rope_flip_start_y, rope_y_for_side(target_side), travel_progress)
	if flip_remaining <= 0.0:
		finish_rope_flip(target_side)

func finish_rope_flip(target_side: int) -> void:
	rope_side = target_side
	rope_state = RopeState.ROPE_BOTTOM if target_side == RopeSide.BOTTOM else RopeState.ROPE_TOP
	if target_side == RopeSide.BOTTOM:
		jump_buffer_remaining = 0.0
		queued_rope_jump_count = 0
		jumps_used = 0
	rope_flip_progress = 1.0 if target_side == RopeSide.BOTTOM else 0.0
	rope_flip_angle = 0.0
	flip_remaining = 0.0
	roll_remaining = 0.0
	air_state = AirState.NONE
	rope_flip_started_airborne = false
	movement_state = MovementState.ROPE
	velocity.y = 0.0
	configure_standing_body()
	global_position.y = rope_y_for_side(target_side)

func is_rope_flipping() -> bool:
	return rope_state == RopeState.FLIP_TO_BOTTOM or rope_state == RopeState.FLIP_TO_TOP

func rope_y_for_side(side: int) -> float:
	return rope.global_position.y + (-safe_margin if side == RopeSide.TOP else PLAYER_HEIGHT + safe_margin)

func try_start_airborne_rope_flip() -> void:
	if down_buffer_remaining <= 0.0 or not can_air_flip_to_source_rope():
		return
	if not start_rope_flip(RopeSide.BOTTOM):
		return
	movement_state = MovementState.ROPE
	airborne_rope_jump_active = false
	down_buffer_remaining = 0.0

func clear_airborne_rope_source_if_invalid() -> void:
	if airborne_rope_jump_active and not can_air_flip_to_source_rope():
		airborne_rope_jump_active = false
		down_buffer_remaining = 0.0
		rope = null

func can_air_flip_to_source_rope() -> bool:
	if not airborne_rope_jump_active or not is_instance_valid(rope):
		return false
	var rope_line := rope.get_node_or_null("Line") as Line2D
	if rope_line == null or rope_line.points.size() < 2:
		return false
	var first_x := rope_line.to_global(rope_line.points[0]).x
	var last_x := rope_line.to_global(rope_line.points[-1]).x
	var left_x := minf(first_x, last_x)
	var right_x := maxf(first_x, last_x)
	return global_position.x + PLAYER_WIDTH / 2.0 >= left_x and global_position.x - PLAYER_WIDTH / 2.0 <= right_x

func consume_buffered_jump() -> bool:
	if jump_buffer_remaining <= 0.0:
		return false
	if movement_state == MovementState.ROPE:
		return false
	if jumps_used == 0 and (is_on_floor() or coyote_remaining > 0.0):
		start_jump(JUMP_SPEED)
		return true
	elif jumps_used == 1:
		start_jump(SECOND_JUMP_SPEED)
		queued_rope_jump_count = 0
		return true
	# 没有起跳就被迫进入空中：走下高台、被击退、或自然下坠到土狼时间过期。
	# 这种情况必须仍然给一次完整起跳，之后还能接二段跳，
	# 否则玩家会因为「没按过跳跃键」而在空中彻底失去控制权。
	elif jumps_used == 0:
		start_jump(JUMP_SPEED)
		return true
	return false

func apply_airborne_motion(delta: float) -> void:
	if velocity.y < 0.0:
		velocity.y += ASCENT_GRAVITY * delta
	else:
		velocity.y += FALL_GRAVITY * delta

func update_air_state() -> void:
	if is_rope_flipping():
		air_state = AirState.DOUBLE_JUMP_ROLL
	elif movement_state != MovementState.AIRBORNE:
		air_state = AirState.NONE
	elif roll_remaining > 0.0:
		air_state = AirState.DOUBLE_JUMP_ROLL
	elif velocity.y >= 0.0:
		air_state = AirState.FALL
	else:
		air_state = AirState.SECOND_JUMP if jumps_used == 2 else AirState.FIRST_JUMP

func start_jump(vertical_speed: float) -> void:
	var jumped_from_rope := movement_state == MovementState.ROPE and rope_state == RopeState.ROPE_TOP and is_instance_valid(rope)
	var keep_airborne_rope_jump := jumped_from_rope or airborne_rope_jump_active
	clear_fast_fall()
	preserve_boost = true
	flip_remaining = 0.0
	if keep_airborne_rope_jump and flip_buffer_remaining > 0.0:
		down_buffer_remaining = maxf(down_buffer_remaining, flip_buffer_remaining)
	elif not keep_airborne_rope_jump:
		flip_buffer_remaining = 0.0
		down_buffer_remaining = 0.0
	rope_reentry_locked = rope_reentry_locked or movement_state == MovementState.ROPE
	movement_state = MovementState.AIRBORNE
	airborne_rope_jump_active = keep_airborne_rope_jump
	if not keep_airborne_rope_jump:
		rope = null
	velocity.y = vertical_speed
	# 落地缓冲起跳后，is_on_floor() 要到下次移动才刷新。
	if jumped_from_rope:
		jumps_used = 1
	elif coyote_remaining > 0.0:
		jumps_used = 1
	else:
		jumps_used = min(jumps_used + 1, 2)
	coyote_remaining = 0.0
	jump_buffer_remaining = 0.0
	roll_remaining = DOUBLE_JUMP_ROLL_DURATION if jumps_used == 2 else 0.0
	if jumps_used == 2:
		roll_hitbox_active = true
		body_collision.shape.size = Vector2(ROLL_WIDTH, ROLL_HEIGHT)
		body_collision.position.y = -ROLL_HEIGHT / 2.0
	else:
		try_restore_standing_body()
	update_air_state()
	jumped.emit(jumps_used)

func start_slide() -> void:
	clear_fast_fall()
	roll_remaining = 0.0
	roll_hitbox_active = false
	air_state = AirState.NONE
	movement_state = MovementState.SLIDE
	slide_remaining = SLIDE_DURATION
	boost_speed = SLIDE_BOOST
	velocity.x = run_speed + boost_speed
	flip_buffer_remaining = 0.0
	down_buffer_remaining = 0.0
	queued_rope_jump_count = 0
	body_collision.shape.size = Vector2(PLAYER_WIDTH, SLIDE_HEIGHT)
	body_collision.position.y = -SLIDE_HEIGHT / 2.0

func finish_slide() -> void:
	movement_state = MovementState.GROUNDED if is_on_floor() else MovementState.AIRBORNE
	configure_standing_body()

func try_attach_to_rope() -> void:
	if rope_reentry_locked:
		return
	if roll_hitbox_active and not can_fit_standing_body():
		return
	for area in rope_detector.get_overlapping_areas():
		if area.is_in_group("rope"):
			var top_y := area.global_position.y - safe_margin
			var crossed_rope := previous_physics_y <= top_y and global_position.y >= top_y
			var missed_rope := global_position.y > top_y + ROPE_REENTRY_TOLERANCE and not crossed_rope
			if velocity.y < 0.0 or missed_rope:
				continue
			clear_fast_fall()
			preserve_boost = true
			rope = area
			movement_state = MovementState.ROPE
			roll_remaining = 0.0
			air_state = AirState.NONE
			rope_side = RopeSide.TOP
			rope_state = RopeState.ROPE_TOP
			configure_standing_body()
			jumps_used = 0
			queued_rope_jump_count = 0
			coyote_remaining = 0.0
			airborne_rope_jump_active = false
			velocity.y = 0.0
			global_position.y = top_y
			return

func detach_from_rope() -> void:
	flip_remaining = 0.0
	down_buffer_remaining = 0.0
	queued_rope_jump_count = 0
	roll_remaining = 0.0
	movement_state = MovementState.AIRBORNE
	airborne_rope_jump_active = false
	rope = null
	rope_state = RopeState.ROPE_TOP
	rope_flip_progress = 0.0
	rope_flip_angle = 0.0
	rope_flip_started_airborne = false
	coyote_remaining = COYOTE_TIME
	configure_standing_body()

func is_touching_rope() -> bool:
	for area in rope_detector.get_overlapping_areas():
		if area.is_in_group("rope"):
			return true
	return false

func rope_offset() -> float:
	# Keep either side clear of hazards whose collision ends at the rope line.
	return -safe_margin if rope_side == RopeSide.TOP else PLAYER_HEIGHT + safe_margin

func configure_standing_body() -> void:
	roll_hitbox_active = false
	body_collision.shape.size = Vector2(PLAYER_WIDTH, PLAYER_HEIGHT)
	body_collision.position.y = -PLAYER_HEIGHT / 2.0

func can_fit_standing_body() -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(PLAYER_WIDTH, PLAYER_HEIGHT)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = global_transform * Transform2D(0.0, Vector2(0, -PLAYER_HEIGHT / 2.0))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func try_restore_standing_body() -> void:
	# 每个物理帧重试；不能用超时强行扩张，把角色挤进窄缝墙体。
	if can_fit_standing_body():
		configure_standing_body()

func set_run_speed(new_speed: float) -> void:
	run_speed = new_speed

func is_sliding() -> bool:
	return movement_state == MovementState.SLIDE

func take_damage(amount: float) -> void:
	if amount <= 0.0 or invulnerability_remaining > 0.0 or not active:
		return
	health = maxf(0.0, health - amount)
	health_regen_delay_remaining = HEALTH_REGEN_DELAY
	health_changed.emit(health, MAX_HP)
	invulnerability_remaining = INVULNERABILITY_TIME
	damaged.emit(amount)
	if health <= 0.0:
		clear_fast_fall()
		roll_remaining = 0.0
		air_state = AirState.NONE
		try_restore_standing_body()
		active = false
		died.emit()

func heal(amount: float) -> void:
	if not active or amount <= 0.0:
		return
	health = minf(MAX_HP, health + amount)
	health_changed.emit(health, MAX_HP)

func update_health_regeneration(delta: float) -> void:
	if health_regen_delay_remaining > 0.0 or health >= MAX_HP:
		return
	heal(HEALTH_REGEN_RATE * delta)

func reset_run(start_position: Vector2) -> void:
	clear_fast_fall()
	roll_remaining = 0.0
	air_state = AirState.FALL
	global_position = start_position
	boost_speed = 0.0
	preserve_boost = false
	flip_remaining = 0.0
	flip_buffer_remaining = 0.0
	down_buffer_remaining = 0.0
	queued_rope_jump_count = 0
	rope_state = RopeState.ROPE_TOP
	rope_flip_progress = 0.0
	rope_flip_angle = 0.0
	rope_flip_start_y = 0.0
	rope_flip_start_progress = 0.0
	rope_flip_started_airborne = false
	velocity = Vector2(run_speed, 0.0)
	previous_physics_y = start_position.y
	movement_state = MovementState.AIRBORNE
	rope = null
	airborne_rope_jump_active = false
	rope_side = RopeSide.TOP
	slide_remaining = 0.0
	rope_reentry_locked = false
	jumps_used = 0
	health = MAX_HP
	invulnerability_remaining = 0.0
	health_regen_delay_remaining = 0.0
	coyote_remaining = 0.0
	jump_buffer_remaining = 0.0
	active = true
	configure_standing_body()
	health_changed.emit(health, MAX_HP)
	run_reset.emit()
