extends SceneTree

const PLAYER := preload("res://player.tscn")
const SEGMENT := preload("res://scenes/segment_rope.tscn")
const STEP := 1.0 / 60.0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func frame() -> void:
	await physics_frame
	await process_frame

func tap(action: String) -> void:
	Input.action_press(action)
	await frame()
	Input.action_release(action)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	world.add_child(SEGMENT.instantiate())
	var player: Variant = PLAYER.instantiate()
	world.add_child(player)
	player.set_run_speed(0.0)
	for jump_frames in [4, 14]:
		for down_frames in [1, 5, 12]:
			await check_air_return(player, jump_frames, down_frames)
	await check_repeated_reversals(player)
	world.free()
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Airborne rope reversal passed: early/late down interrupts and continuous top returns.")
	quit(0 if failures.is_empty() else 1)

func check_air_return(player: Variant, jump_frames: int, down_frames: int) -> void:
	player.reset_run(Vector2(700, 460))
	await frame()
	await frame()
	await tap("jump")
	for index in jump_frames:
		await frame()
	await tap("slide")
	for index in down_frames - 1:
		await frame()
	var previous_y: float = player.global_position.y
	var previous_angle: float = player.rope_flip_angle
	var max_angle_step: float = PI * PI * STEP / player.FLIP_DURATION + 0.1
	var top_y: float = player.rope_y_for_side(player.RopeSide.TOP)
	var max_step: float = maxf(absf(player.rope_y_for_side(player.RopeSide.BOTTOM) - previous_y), absf(top_y - previous_y)) * STEP / player.FLIP_DURATION + 0.1
	Input.action_press("jump")
	for index in 20:
		await frame()
		Input.action_release("jump")
		var current_y: float = player.global_position.y
		check(absf(current_y - previous_y) <= max_step, "Return must not teleport: jump=%s down=%s step=%s" % [jump_frames, down_frames, absf(current_y - previous_y)])
		check(absf(current_y - top_y) <= absf(previous_y - top_y) + 0.1, "Return must approach rope top without retreating to the airborne origin")
		check(absf(player.rope_flip_angle - previous_angle) <= max_angle_step, "Return rotation must remain continuous")
		previous_y = current_y
		previous_angle = player.rope_flip_angle
	check(player.rope_state == player.RopeState.ROPE_TOP, "Return must finish on rope top")
	check(player.movement_state == player.MovementState.ROPE, "One up tap must return without jumping again")

func check_repeated_reversals(player: Variant) -> void:
	player.reset_run(Vector2(700, 460))
	await frame()
	await frame()
	await tap("jump")
	for index in 14:
		await frame()
	for action in ["slide", "jump", "slide", "jump"]:
		var previous_y: float = player.global_position.y
		var target: int = player.RopeSide.BOTTOM if action == "slide" else player.RopeSide.TOP
		var max_step: float = absf(player.rope_y_for_side(target) - previous_y) * STEP / player.FLIP_DURATION + 0.1
		await tap(action)
		check(absf(player.global_position.y - previous_y) <= max_step, "Repeated reversals must continue from the current position")
	await frame()
	await tap("jump")
	for index in 14:
		await frame()
	check(player.movement_state == player.MovementState.AIRBORNE and player.jumps_used == 1, "Extra up tap must queue the first jump after returning to the top")
