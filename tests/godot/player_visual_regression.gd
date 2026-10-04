extends SceneTree

const PLAYER := preload("res://player.tscn")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr(message)

func frames(count: int) -> void:
	for index in count:
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var player: Variant = PLAYER.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	player.position = Vector2(140, 460)
	var visual: Variant = player.get_node("PlayerVisual")
	await frames(2)
	check(not player.has_node("Sprite"), "Legacy sprite is still mounted")
	player.jumped.emit(1)
	await frames(5)
	check(visual.body.scale.y > 1.2 and visual.body.scale.x < 0.85, "Jump stretch missing")
	await frames(25)
	check(visual.body.scale.is_equal_approx(Vector2.ONE), "Jump stretch did not recover")
	player.landed.emit(700.0)
	await frames(5)
	check(visual.body.scale.y < 0.85 and visual.body.scale.x > 1.15, "Landing squash missing")
	player.movement_state = player.MovementState.SLIDE
	player.velocity = Vector2(540, 0)
	await frames(12)
	check(visual.ghosts.get_child_count() > 0, "Slide ghosts were not spawned")
	check(not visual.dust.emitting, "Dust must stop while sliding")
	var ghost: Node2D = visual.ghosts.get_child(0)
	var ghost_position := ghost.global_position
	player.position.x += 40
	await frames(1)
	check(ghost.global_position.is_equal_approx(ghost_position), "Ghost followed the player")
	player.movement_state = player.MovementState.AIRBORNE
	await frames(20)
	check(visual.ghosts.get_child_count() > 0, "Airborne overspeed ghosts missing")
	player.velocity.x = player.RUN_SPEED
	player.movement_state = player.MovementState.GROUNDED
	await frames(20)
	check(visual.ghosts.get_child_count() == 0, "Ghosts did not expire")
	check(visual.dust.emitting, "Ground running dust missing")
	player.movement_state = player.MovementState.AIRBORNE
	await frames(2)
	check(not visual.dust.emitting, "Dust must stop in air")
	player.reset_run(Vector2(0, 460))
	await frames(2)
	var scarf: Line2D = visual.scarf
	check(scarf.points[0].distance_to(scarf.get_parent().global_position) < 0.1, "Scarf anchor detached")
	for index in range(1, scarf.points.size()):
		check(scarf.points[index - 1].x - scarf.points[index].x >= scarf.WIND_SPACING - 0.1, "Scarf chain stretched after restart")
	check(visual.ghosts.get_child_count() == 0, "Restart left ghosts behind")
	player.free()
	if failures == 0:
		print("Visual regression passed: stretch, squash, fixed ghosts, cleanup, dust and scarf")
	quit(1 if failures else 0)
