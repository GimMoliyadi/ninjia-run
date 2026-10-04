extends SceneTree

const MODULE := preload("res://scenes/segment_rope_map.tscn")
const PLAYER := preload("res://player.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var module := MODULE.instantiate()
	world.add_child(module)
	var platforms: Array[Vector2] = []
	for section in module.sections:
		for child in section.get_children():
			if not child is StaticBody2D:
				continue
			var collider: CollisionShape2D = child.get_child(0)
			var left: float = collider.global_position.x - collider.shape.size.x * 0.5
			var right: float = collider.global_position.x + collider.shape.size.x * 0.5
			if left > module.global_position.x and right < module.get_node("Exit").global_position.x:
				platforms.append(Vector2(left, right))
	check(not platforms.is_empty(), "Expected an interior recovery platform")
	for span in platforms:
		var left_connected := false
		var right_connected := false
		for child in module.get_children():
			if not child is Area2D or not child.is_in_group("rope"):
				continue
			var line: Line2D = child.get_node("Line")
			var start: float = line.to_global(line.points[0]).x
			var end: float = line.to_global(line.points[-1]).x
			check(end <= span.x or start >= span.y, "Rope overlaps platform %s" % span)
			left_connected = left_connected or is_equal_approx(end, span.x)
			right_connected = right_connected or is_equal_approx(start, span.y)
		check(left_connected and right_connected, "Ropes must connect to both platform edges")
		await check_crossing(world, span, false)
		await check_crossing(world, span, true)
	world.free()
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Rope platform regression passed: no overlap, both edges connected, top/bottom crossings.")
	quit(0 if failures.is_empty() else 1)

func check_crossing(world: Node2D, span: Vector2, bottom: bool) -> void:
	var player := PLAYER.instantiate()
	player.position = Vector2(span.x - 200.0, 460.0)
	world.add_child(player)
	await frames(4)
	check(player.movement_state == player.MovementState.ROPE, "Approach must attach to rope")
	if bottom:
		Input.action_press("slide")
		await frames(1)
		Input.action_release("slide")
		await frames(12)
		check(player.rope_side == player.RopeSide.BOTTOM, "Approach must start below rope")
	var grounded := false
	for index in 180:
		await frames(1)
		if player.position.x > span.x + player.PLAYER_WIDTH and player.position.x < span.y - player.PLAYER_WIDTH:
			grounded = grounded or player.movement_state == player.MovementState.GROUNDED
		if player.position.x > span.y + player.PLAYER_WIDTH:
			break
	check(grounded, "Player must run on platform instead of remaining attached")
	check(player.position.x > span.y and player.movement_state == player.MovementState.ROPE,
		"Player must reattach after platform: %s state=%s" % [player.position, player.movement_state])
	check(absf(player.position.y - 460.0) < 1.0, "Crossing must stay at platform height")
	player.free()

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
