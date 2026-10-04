extends SceneTree

const Player := preload("res://player.tscn")
const Floor := preload("res://scenes/segment_safe.tscn")
var failures: Array[String] = []
var player: Variant

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func frame() -> void:
	await physics_frame
	await process_frame

func tap(action: String) -> void:
	Input.action_press(action)
	await frame()
	Input.action_release(action)

func launch() -> void:
	player.reset_run(Vector2(140, 460))
	await frame()
	await frame()
	Input.action_press("jump")
	for index in 7:
		await frame()
	Input.action_release("jump")
	check(not player.is_on_floor() and player.velocity.y < 0.0, "Setup must still be ascending.")

func land() -> void:
	for index in 120:
		await frame()
		if player.is_on_floor():
			return
	check(false, "Fast fall must collide with the floor.")

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	world.add_child(Floor.instantiate())
	player = Player.instantiate()
	world.add_child(player)
	await launch()
	var horizontal_speed: float = player.velocity.x
	await tap("slide")
	check(player.velocity.y >= player.FAST_FALL_SPEED, "First down must immediately cancel upward motion.")
	check(player.velocity.x == horizontal_speed, "Fast fall must preserve horizontal speed.")
	await land()
	check(not player.is_sliding() and not player.fast_falling, "One down must land standing.")
	check(absf(player.position.y - 460.0) < 0.1, "Fast fall must not tunnel through ground.")

	await launch()
	await tap("slide")
	await frame()
	await tap("slide")
	check(player.landing_slide_queued and not player.is_on_floor(), "Second down before landing must queue slide.")
	await land()
	check(player.is_sliding(), "Slide must start on the landing frame.")
	check(player.body_collision.shape.size.y == player.SLIDE_HEIGHT, "Landing slide must immediately use the low collider.")
	check(player.velocity.x == player.run_speed + player.SLIDE_BOOST, "Landing slide must immediately gain horizontal speed.")
	check(not player.landing_slide_queued, "Landing must consume the queued action once.")

	await launch()
	await tap("slide")
	await frame()
	await tap("slide")
	await tap("jump")
	check(player.velocity.y < 0.0 and player.jumps_used == 2, "Second jump must cancel fast fall.")
	check(not player.fast_falling and not player.landing_slide_queued, "Second jump must clear the slide queue.")
	await land()
	check(not player.is_sliding(), "Cancelled queue must not trigger later.")

	await launch()
	Input.action_press("slide")
	await land()
	check(not player.is_sliding(), "Holding down must not count as a second press.")
	Input.action_release("slide")
	await frame()
	await tap("slide")
	check(player.is_sliding(), "A new down after landing must start slide.")
	player.fast_falling = true
	player.landing_slide_queued = true
	player.take_damage(player.MAX_HP)
	check(not player.fast_falling and not player.landing_slide_queued, "Death must clear pending actions.")
	player.fast_falling = true
	player.landing_slide_queued = true
	player.reset_run(Vector2(140, 460))
	check(not player.fast_falling and not player.landing_slide_queued, "Restart must clear pending actions.")
	world.free()
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Fast fall passed: immediate cancellation, double-down landing slide, collision, jump cancellation, hold handling and reset.")
	quit(0 if failures.is_empty() else 1)
