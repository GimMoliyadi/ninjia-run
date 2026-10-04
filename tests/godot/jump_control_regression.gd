extends SceneTree

const PlayerScene := preload("res://player.tscn")
var failures: Array[String] = []
var player: Variant
var world: Node2D
var jump_indices: Array[int] = []

func _initialize() -> void:
	call_deferred("run")

func frame() -> void:
	await physics_frame
	await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func reset(at := Vector2(140, 460)) -> void:
	Input.action_release("jump")
	Input.action_release("slide")
	player.reset_run(at)
	await frame()
	await frame()

func run() -> void:
	world = Node2D.new()
	root.add_child(world)
	add_block(Rect2(-500, 460, 10000, 80))
	player = PlayerScene.instantiate()
	world.add_child(player)
	player.jumped.connect(func(index: int) -> void: jump_indices.append(index))
	var heights: Array[float] = []
	for hold_frames in [1, 4, 8, 12, 24]:
		heights.append(await measure_height(hold_frames))
	for index in range(1, heights.size()):
		check(absf(heights[index] - heights[0]) < 0.1, "tap and hold must produce the same full jump")
	check(heights[0] >= 170 and heights[0] <= 190, "tap height must match the reference's approximate viewport-normalized range")
	print("JUMP_HEIGHTS frames=[1,4,8,12,24] px=", heights)
	await check_release_velocity()
	await check_second_jump()
	await check_second_height(heights[0])
	await check_clearance()
	await check_buffer_and_coyote()
	await check_walk_off_coyote()
	await check_forced_air_jump()
	await check_roll_interruptions()
	await check_rapid_jumps()
	world.free()
	Input.action_release("jump")
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Jump control passed: full-height tap, near-equal second jump, slower fall, roll, safe hitbox restoration, buffer, coyote and forced-air jump")
	quit(0 if failures.is_empty() else 1)

func measure_height(hold_frames: int) -> float:
	await reset()
	var peak := 0.0
	var apex_frame := 0
	Input.action_press("jump")
	for index in 100:
		if index == hold_frames:
			Input.action_release("jump")
		await frame()
		if 460.0 - player.position.y > peak:
			peak = 460.0 - player.position.y
			apex_frame = index
		if index > 2 and player.is_on_floor():
			check(float(apex_frame + 1) / 60.0 >= 0.28 and float(apex_frame + 1) / 60.0 <= 0.35, "takeoff to apex must stay near the reference's 0.3 seconds")
			check(float(index - apex_frame) / 60.0 >= 0.32, "natural descent should allow time to choose a fast fall")
			print("FLIGHT hold_frames=%d total=%.3fs descent=%.3fs" % [hold_frames, float(index + 1) / 60.0, float(index - apex_frame) / 60.0])
			break
	return peak

func check_release_velocity() -> void:
	await reset()
	Input.action_press("jump")
	await frame()
	var before: float = player.velocity.y
	Input.action_release("jump")
	await frame()
	check(is_equal_approx(player.velocity.y - before, player.ASCENT_GRAVITY / 60.0), "release must not change upward acceleration")

func check_rapid_jumps() -> void:
	await reset(Vector2(140, 400))
	player.position.y = 455
	player.coyote_remaining = 0.0
	player.jumps_used = 2
	player.velocity.y = 600
	jump_indices.clear()
	Input.action_press("jump")
	await frame()
	check(jump_indices == [1], "landing must consume the buffered jump immediately")
	Input.action_release("jump")
	Input.action_press("jump")
	await frame()
	check(jump_indices == [1, 2], "a tap immediately after buffered landing must be a second jump")
	Input.action_release("jump")
	await frame()
	Input.action_press("jump")
	await frame()
	check(jump_indices == [1, 2], "rapid taps must not grant a third jump")
	Input.action_release("jump")
	await reset()
	jump_indices.clear()
	Input.action_press("jump")
	for index in 100:
		await frame()
	check(jump_indices == [1], "holding jump through landing must not auto-repeat")
	check(is_equal_approx(player.velocity.x, player.RUN_SPEED), "jumping must preserve automatic run speed")
	Input.action_release("jump")

func check_second_height(first_height: float) -> void:
	await reset(Vector2(140, 160))
	player.jumps_used = 1
	player.velocity.y = 600
	var start_y: float = player.position.y
	var height := 0.0
	Input.action_press("jump")
	await frame()
	Input.action_release("jump")
	for index in 45:
		height = maxf(height, start_y - player.position.y)
		await frame()
		if player.velocity.y >= 0:
			break
	check(height > first_height * 0.9 and height < first_height, "second jump should be slightly lower than first")
	print("SECOND_JUMP rise=%.2fpx first=%.2fpx" % [height, first_height])

func check_second_jump() -> void:
	await reset(Vector2(140, 160))
	player.jumps_used = 1
	player.velocity.y = 600
	jump_indices.clear()
	Input.action_press("jump")
	await frame()
	check(player.velocity.y < -600, "double jump must reverse a fast descent")
	check(jump_indices == [2], "visual jump signal must identify second jump")
	check(player.air_state == player.AirState.DOUBLE_JUMP_ROLL, "second jump must enter roll")
	check(player.body_collision.shape.size == Vector2(40, 40), "roll hitbox missing")
	var visual: Variant = player.get_node("PlayerVisual")
	check(visual.body.pose_mode == "double_jump_roll", "tucked pose missing")
	var maximum_angle := 0.0
	for index in 22:
		await frame()
		maximum_angle = maxf(maximum_angle, visual.action_pivot.rotation)
		check(is_zero_approx(visual.orientation.rotation), "roll must not rotate Orientation")
	check(maximum_angle > TAU * 0.9, "roll must complete approximately 360 degrees")
	check(not player.roll_hitbox_active and not player.is_on_floor(), "roll should restore in open air before landing")
	check(player.body_collision.shape.size == Vector2(46, 66), "normal hitbox not restored")
	Input.action_release("jump")

func check_clearance() -> void:
	await reset(Vector2(140, 180))
	player.set_run_speed(0)
	player.set_physics_process(false)
	player.jumps_used = 1
	player.start_jump(player.SECOND_JUMP_SPEED)
	var roof := add_block(Rect2(100, 120, 120, 12))
	await frame()
	player.roll_remaining = 0
	player.try_restore_standing_body()
	check(player.roll_hitbox_active, "must not expand inside low roof")
	check(not player.can_fit_standing_body(), "clearance query missed solid roof")
	player.position.x = 250
	player.set_physics_process(true)
	player.velocity = Vector2.ZERO
	await frame()
	check(not player.roll_hitbox_active, "must retry and restore immediately after leaving roof")
	check(absf(player.position.x - 250) < 0.1, "restoration must not teleport horizontally")
	roof.free()
	player.set_run_speed(player.RUN_SPEED)

func check_buffer_and_coyote() -> void:
	await reset(Vector2(140, 440))
	player.jumps_used = 2
	player.velocity.y = 200
	jump_indices.clear()
	Input.action_press("jump")
	for index in 10:
		await frame()
		if not jump_indices.is_empty():
			break
	check(jump_indices == [1] and player.velocity.y < 0, "landing buffer must start a fresh first jump")
	Input.action_release("jump")
	await reset(Vector2(140, 360))
	player.coyote_remaining = player.COYOTE_TIME
	jump_indices.clear()
	Input.action_press("jump")
	await frame()
	check(jump_indices == [1] and player.velocity.y < 0, "coyote must remain first jump")
	Input.action_release("jump")

func add_block(rect: Rect2) -> StaticBody2D:
	var block := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	collision.position = rect.get_center()
	block.add_child(collision)
	world.add_child(block)
	return block

func check_walk_off_coyote() -> void:
	await reset(Vector2(9460, 460))
	for index in 20:
		await frame()
		if not player.is_on_floor():
			break
	check(not player.is_on_floor(), "coyote fixture must walk off the floor edge")
	await frame()
	await frame()
	jump_indices.clear()
	Input.action_press("jump")
	await frame()
	check(jump_indices == [1] and player.velocity.y < 0, "real ledge coyote jump failed")
	Input.action_release("jump")

func check_forced_air_jump() -> void:
	# 没按过跳跃、也不是土狼时间内：从高台自然走落、土狼时间彻底过期之后，
	# 仍然必须给一次完整起跳，并且起跳之后还能接二段跳。
	# 否则玩家会因为「没按过跳跃键」而在空中彻底失去控制权。
	await reset(Vector2(9460, 460))
	for index in 20:
		await frame()
		if not player.is_on_floor():
			break
	check(not player.is_on_floor(), "forced-air fixture must walk off the floor edge")
	for index in 30:
		await frame()
	check(player.jumps_used == 0, "forced-air: player must not have used any jump")
	check(player.coyote_remaining <= 0.0, "forced-air: coyote window must already be over")
	check(player.velocity.y > 0.0, "forced-air: player must be falling")
	jump_indices.clear()
	Input.action_press("jump")
	await frame()
	check(jump_indices == [1] and player.velocity.y < 0, "forced-air first jump failed")
	check(player.jumps_used == 1, "forced-air first jump must consume exactly one jump")
	Input.action_release("jump")
	await frame()
	Input.action_press("jump")
	await frame()
	check(jump_indices == [1, 2], "forced-air second jump failed")
	Input.action_release("jump")

func check_roll_interruptions() -> void:
	await reset(Vector2(140, 380))
	player.jumps_used = 1
	player.start_jump(player.SECOND_JUMP_SPEED)
	player.velocity.y = player.FAST_FALL_SPEED
	for index in 10:
		await frame()
		if player.is_on_floor():
			break
	check(player.is_on_floor() and player.roll_remaining == 0, "landing must interrupt roll")
	check(not player.roll_hitbox_active, "landing in open space must restore normal body")
	await reset(Vector2(140, 200))
	player.jumps_used = 1
	player.start_jump(player.SECOND_JUMP_SPEED)
	player.reset_run(Vector2(140, 460))
	await frame()
	var visual: Variant = player.get_node("PlayerVisual")
	check(not player.roll_hitbox_active and player.roll_remaining == 0, "reset must clear roll")
	check(visual.action_pivot.rotation == 0 and visual.body.scale == Vector2.ONE, "reset must clear visual action")
	check(visual.scarf.get_current_anchor_pos().distance_to(visual.body.get_node("Neck").global_position) < 0.1, "scarf must follow actual transformed Neck")
