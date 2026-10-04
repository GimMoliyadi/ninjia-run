extends SceneTree

const PLAYER := preload("res://player.tscn")
const SEGMENT := preload("res://scenes/segment_rope.tscn")
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr(message)

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var segment := SEGMENT.instantiate()
	world.add_child(segment)
	var player: Variant = PLAYER.instantiate()
	player.position = Vector2(300, 460)
	world.add_child(player)
	await frames(30)
	check(player.movement_state == player.MovementState.ROPE, "Ground entry failed to attach")
	check(absf(player.position.y - 460.0) < 0.1, "Rope top is not aligned")
	player.set_run_speed(0.0)
	var top_center: float = player.body_collision.global_position.y
	var orientation: Node2D = player.get_node("PlayerVisual/Orientation")
	var top_visual_y: float = orientation.to_global(Vector2(0, -33)).y
	Input.action_press("slide")
	await frames(1)
	Input.action_release("slide")
	await frames(12)
	check(player.rope_side == player.RopeSide.BOTTOM, "Flip did not enter bottom")
	check(absf(player.position.y - 526.0) < 0.1, "Hanging foot position is incorrect")
	check(is_equal_approx(player.body_collision.global_position.y - top_center, player.PLAYER_HEIGHT + 2.0 * player.safe_margin), "Collider did not move one body height")
	check(orientation.scale.y < 0.0, "Rope bottom must show upside-down running")
	var rope_y: float = segment.get_node("Rope").global_position.y
	check(is_equal_approx(orientation.to_global(Vector2(0, -33)).y - rope_y, rope_y - top_visual_y), "Visual feet are not mirrored around the rope")
	check(is_zero_approx(player.velocity.y), "Gravity interferes with rope attachment")
	Input.action_press("slide")
	await frames(1)
	Input.action_release("slide")
	await frames(12)
	check(player.rope_side == player.RopeSide.BOTTOM, "Down on the bottom lane must not flip upward")
	Input.action_press("jump")
	await frames(1)
	Input.action_release("jump")
	check(player.rope_side == player.RopeSide.TOP and player.movement_state == player.MovementState.ROPE, "Jump on bottom must only return to the top lane")
	check(player.jumps_used == 0 and is_zero_approx(player.velocity.y), "Returning to top must not spend an airborne jump")
	Input.action_press("jump")
	await frames(1)
	Input.action_release("jump")
	await frames(12)
	check(player.movement_state == player.MovementState.AIRBORNE and player.velocity.y < 0.0, "Rope jump failed")
	check(player.jumps_used == 1, "A second rapid tap during the flip must start the first jump")
	await frames(2)
	check(player.movement_state == player.MovementState.AIRBORNE, "Jump immediately reattached")
	player.reset_run(Vector2(1900, 460))
	await frames(4)
	Input.action_press("slide")
	await frames(1)
	Input.action_release("slide")
	player.set_run_speed(player.RUN_SPEED)
	await frames(85)
	check(player.position.x > 2350.0 and absf(player.position.y - 460.0) < 1.0, "Hanging exit failed: position=%s state=%s" % [player.position, player.movement_state])
	for obstacle_name in ["SpikeA", "SpikeB", "SpikeC"]:
		var obstacle: Node2D = segment.get_node("Rope/" + obstacle_name)
		check(is_equal_approx(obstacle.global_position.y, 460.0), "Obstacle root is floating above rope")
		var collision: CollisionShape2D = obstacle.get_node("CollisionShape2D")
		var base := collision.to_global(Vector2(0.0, collision.shape.size.y / 2.0))
		check(is_equal_approx(base.y, 460.0), "Obstacle collider base is not on rope")
	var query := PhysicsRayQueryParameters2D.create(Vector2(1300, 470), Vector2(1300, 1000), 1)
	check(world.get_world_2d().direct_space_state.intersect_ray(query).is_empty(), "Pit still has a hidden floor")
	world.free()
	if not failed:
		print("Rope regression passed: entry, both flips, collider, gravity, jump and exit.")
	quit(1 if failed else 0)



