extends SceneTree
const PLAYER := preload("res://player.tscn")
const SEGMENT := preload("res://scenes/segment_rope.tscn")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr(message)
func frame() -> void:
	await physics_frame
	await process_frame
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	world.add_child(SEGMENT.instantiate())
	var player: Variant = PLAYER.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	for state in [player.MovementState.GROUNDED, player.MovementState.AIRBORNE, player.MovementState.ROPE]:
		player.movement_state = state
		player.boost_speed = 220.0
		player.update_horizontal_momentum(0.1)
		var expected := 214.0 if state == player.MovementState.AIRBORNE else 160.0
		check(is_equal_approx(player.boost_speed, expected), "Incorrect state decay")
		check(is_equal_approx(player.velocity.x, 400.0 + expected), "Horizontal formula disagrees with pool")
	player.reset_run(Vector2(650, 460))
	await frame()
	await frame()
	player.boost_speed = 220.0
	player.flip_buffer_remaining = 0.09
	player.set_physics_process(true)
	await frame()
	check(player.movement_state == player.MovementState.ROPE, "Failed to attach to real rope")
	check(player.rope_side == player.RopeSide.BOTTOM, "Pre-entry flip input was lost")
	check(is_equal_approx(player.boost_speed, 220.0), "Rope entry consumed momentum")
	var previous_side: int = player.rope_side
	var flips := 0
	for tick in 40:
		if player.flip_remaining > 0.0 and player.flip_remaining < 0.06:
			player.flip_buffer_remaining = player.FLIP_BUFFER_TIME
		await frame()
		if player.rope_side != previous_side:
			flips += 1
			previous_side = player.rope_side
		check(is_equal_approx(player.boost_speed, 220.0), "Continuous flip lost momentum")
	check(flips >= 3, "Buffered flips did not chain")
	player.flip_buffer_remaining = 0.0
	for tick in 18:
		await frame()
	check(player.boost_speed < 220.0, "Momentum freeze persisted after flip finished")
	var before: float = player.boost_speed
	player.jump_buffer_remaining = player.JUMP_BUFFER_TIME
	await frame()
	check(player.movement_state == player.MovementState.AIRBORNE and player.velocity.y < 0.0, "Rope jump failed")
	check(is_equal_approx(player.boost_speed, before), "Rope jump consumed momentum")
	player.reset_run(Vector2(140, 460))
	check(player.boost_speed == 0.0 and player.flip_remaining == 0.0 and player.flip_buffer_remaining == 0.0, "Reset left momentum or flip timers")
	world.free()
	if failures == 0:
		print("Boost pool passed: decay rates, entry buffer, chained flip freeze, resume, rope jump and reset")
	quit(1 if failures else 0)
