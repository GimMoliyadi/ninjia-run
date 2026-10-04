class_name PlayerMotionProfile
extends RefCounted

const Player := preload("res://player.gd")
const RUN_SPEED := Player.RUN_SPEED
const JUMP_SPEED := Player.JUMP_SPEED
const SECOND_JUMP_SPEED := Player.SECOND_JUMP_SPEED
const BODY_SIZE := Vector2(Player.PLAYER_WIDTH, Player.PLAYER_HEIGHT)
const SLIDE_HEIGHT := Player.SLIDE_HEIGHT
const GROUND_Y := 460.0
const ROPE_JUMP_LEAD := Player.FLIP_DURATION + Player.FLIP_BUFFER_TIME * 0.5
const JUMP_PATH_STEP_MARGIN := 4

static func rope_flip_window() -> float:
	return Player.FLIP_DURATION + Player.JUMP_BUFFER_TIME

static func jump_height() -> float:
	return Player.JUMP_SPEED * Player.JUMP_SPEED / (2.0 * Player.ASCENT_GRAVITY)

static func jump_time() -> float:
	return -Player.JUMP_SPEED / Player.ASCENT_GRAVITY + sqrt(2.0 * jump_height() / Player.FALL_GRAVITY)

static func double_jump_height() -> float:
	return jump_height() + Player.SECOND_JUMP_SPEED * Player.SECOND_JUMP_SPEED / (2.0 * Player.ASCENT_GRAVITY)

static func safe_double_jump_gap(height_difference: float = 0.0) -> float:
	var fall_height := double_jump_height() - height_difference
	if fall_height < BODY_SIZE.y * 0.5:
		return 0.0
	var ascent_time := -(JUMP_SPEED + SECOND_JUMP_SPEED) / Player.ASCENT_GRAVITY
	var flight_time := ascent_time + sqrt(2.0 * fall_height / Player.FALL_GRAVITY)
	# 在首跳顶点补二跳；预留一个身宽及输入缓冲时间，避免用极限擦边距离挖坑。
	return maxf(0.0, RUN_SPEED * (flight_time - Player.JUMP_BUFFER_TIME) - BODY_SIZE.x)

static func fast_fall_time(height: float) -> float:
	return (sqrt(Player.FAST_FALL_SPEED * Player.FAST_FALL_SPEED + 2.0 * Player.FALL_GRAVITY * height) - Player.FAST_FALL_SPEED) / Player.FALL_GRAVITY

static func sample_jump_path(landing_y: float = 0.0, double_jump: bool = false, initial_boost: float = 0.0) -> PackedVector2Array:
	var step_seconds := 1.0 / float(Engine.physics_ticks_per_second)
	var path := PackedVector2Array([Vector2.ZERO])
	var position := Vector2.ZERO
	var vertical_speed: float = JUMP_SPEED
	var boost := initial_boost
	var second_jump_pending := double_jump
	var step_limit := _jump_path_step_limit(landing_y, double_jump, step_seconds)
	for step in range(step_limit):
		var jumped := step == 0
		if second_jump_pending and step > 0 and vertical_speed + Player.ASCENT_GRAVITY * step_seconds >= 0.0:
			vertical_speed = SECOND_JUMP_SPEED
			second_jump_pending = false
			jumped = true
		# 与 update_run 一致：跳跃先赋速，再更新重力，最后积分位置。
		var gravity: float = Player.ASCENT_GRAVITY if vertical_speed < 0.0 else Player.FALL_GRAVITY
		vertical_speed += gravity * step_seconds
		if not jumped:
			boost = move_toward(boost, 0.0, Player.AIR_DRAG * step_seconds)
		var next_position := position + Vector2(RUN_SPEED + boost, vertical_speed) * step_seconds
		if vertical_speed > 0.0:
			if position.y > landing_y:
				return PackedVector2Array()
			if next_position.y >= landing_y:
				var landing_fraction := (landing_y - position.y) / (next_position.y - position.y)
				var landing_position := position.lerp(next_position, landing_fraction)
				landing_position.y = landing_y
				path.append(landing_position)
				return path
		path.append(next_position)
		position = next_position
	return PackedVector2Array()

static func _jump_path_step_limit(landing_y: float, double_jump: bool, step_seconds: float) -> int:
	var ascent_time := -JUMP_SPEED / Player.ASCENT_GRAVITY
	# 每次赋速最多比连续公式多移动一个物理步，落差上界要包含这段位移。
	var height_bound := jump_height() - JUMP_SPEED * step_seconds
	if double_jump:
		ascent_time += -SECOND_JUMP_SPEED / Player.ASCENT_GRAVITY
		height_bound = double_jump_height() - (JUMP_SPEED + SECOND_JUMP_SPEED) * step_seconds
	var fall_height := maxf(0.0, height_bound + landing_y)
	var fall_time := sqrt(2.0 * fall_height / Player.FALL_GRAVITY)
	return int(ceil((ascent_time + fall_time) / step_seconds)) + JUMP_PATH_STEP_MARGIN
