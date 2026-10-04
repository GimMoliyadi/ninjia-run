extends SceneTree

const Player := preload("res://player.tscn")
const Segment := preload("res://scenes/segment_rope.tscn")
const Dart := preload("res://components/dart.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func frame() -> void:
	await physics_frame
	await process_frame

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	world.add_child(Segment.instantiate())
	var player: Variant = Player.instantiate()
	world.add_child(player)
	player.reset_run(Vector2(700, 460))
	player.set_run_speed(0.0)
	await frame()
	await frame()
	check(player.movement_state == player.MovementState.ROPE, "Player must attach to the rope.")
	var visual: Node2D = player.get_node("PlayerVisual")
	var orientation: Node2D = visual.get_node("Orientation")
	for destination in [player.RopeSide.BOTTOM, player.RopeSide.TOP]:
		var previous_position: Vector2 = player.global_position
		if destination == player.RopeSide.BOTTOM:
			player.flip_buffer_remaining = player.FLIP_BUFFER_TIME
		else:
			player.jump_buffer_remaining = player.JUMP_BUFFER_TIME
		await frame()
		check(player.rope_side == destination, "Input must select the opposite rope side.")
		player.set_physics_process(false)
		for progress in [1.0, 0.75, 0.5, 0.25, 0.0]:
			player.flip_remaining = progress * player.FLIP_DURATION
			visual.update_pose(0.0)
			check(is_zero_approx(orientation.rotation), "Flip must not rotate in the screen plane.")
			check(is_equal_approx(orientation.scale.x, 1.0), "Flip must not widen the silhouette.")
			check(absf(orientation.global_position.y - 460.0) < 0.1, "Projection pivot must stay on the rope.")
			if progress == 0.5:
				check(absf(orientation.scale.y) < 0.001, "Halfway through the flip must show an edge-on projection.")
		var target_sign := -1.0 if destination == player.RopeSide.BOTTOM else 1.0
		check(is_equal_approx(orientation.scale.y, target_sign), "Flip must finish in the correct orientation.")
		player.flip_remaining = player.FLIP_DURATION * 0.5
		check_darts(world, player, previous_position)
		player.flip_remaining = 0.0
		check_darts(world, player, previous_position)
		player.set_physics_process(true)
		await frame()
	world.free()
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Rope flip projection passed: both directions, fixed width, rope pivot, no teleport sweep damage and target-side collisions preserved.")
	quit(0 if failures.is_empty() else 1)

func check_darts(world: Node2D, player: Variant, previous_position: Vector2) -> void:
	player.health = player.MAX_HP
	player.invulnerability_remaining = 0.0
	var old_side_dart := Dart.new()
	world.add_child(old_side_dart)
	old_side_dart.global_position = previous_position + Vector2(0, -player.PLAYER_HEIGHT / 2.0)
	old_side_dart.previous_player_position = previous_position
	old_side_dart.velocity = Vector2.ZERO
	old_side_dart.advance(1.0 / 60.0, player)
	check(player.health == player.MAX_HP, "Changing sides must not sweep through old-side darts.")
	old_side_dart.queue_free()
	var target_side_dart := Dart.new()
	world.add_child(target_side_dart)
	target_side_dart.global_position = player.body_collision.global_position
	target_side_dart.previous_player_position = previous_position
	target_side_dart.velocity = Vector2.ZERO
	target_side_dart.advance(1.0 / 60.0, player)
	check(player.health == player.MAX_HP - Dart.DAMAGE, "Actual target-side contact must still damage during a flip.")
	target_side_dart.queue_free()
