extends SceneTree

const PLAYER := preload("res://player.tscn")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr(message)

func frame() -> void:
	await physics_frame
	await process_frame

func _initialize() -> void:
	call_deferred("run")

func flight(player: Variant, sliding: bool) -> float:
	player.reset_run(Vector2(140, 460))
	await frame()
	await frame()
	if sliding:
		player.start_slide()
		check(is_equal_approx(player.boost_speed, 220.0), "Slide did not fill momentum pool immediately")
		await frame()
	var start_x: float = player.position.x
	player.jump_buffer_remaining = player.JUMP_BUFFER_TIME
	await frame()
	if sliding:
		check(is_equal_approx(player.velocity.x, 620.0), "Slide jump did not inherit full velocity")
	for index in 120:
		await frame()
		if player.is_on_floor():
			if sliding:
				check(is_equal_approx(player.velocity.x, 620.0 - (index + 1) * player.AIR_DRAG / 60.0), "Air drag lost too much momentum")
			return player.position.x - start_x
	check(false, "Jump failed to land")
	return 0.0

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var floor_body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10000, 80)
	collision.shape = shape
	collision.position = Vector2(5000, 500)
	floor_body.add_child(collision)
	world.add_child(floor_body)
	var player: Variant = PLAYER.instantiate()
	world.add_child(player)
	var normal := await flight(player, false)
	var boosted := await flight(player, true)
	check(boosted > normal * 1.45, "Slide jump is not substantially longer")
	var landing_velocity: float = player.velocity.x
	await frame()
	check(player.velocity.x < landing_velocity and player.velocity.x > player.RUN_SPEED, "Landing speed must recover smoothly")
	for index in 30:
		await frame()
	check(is_equal_approx(player.velocity.x, player.RUN_SPEED), "Surface speed did not settle")
	player.start_slide()
	player.start_jump(player.JUMP_SPEED)
	var before_second_jump: float = player.velocity.x
	player.start_jump(player.SECOND_JUMP_SPEED)
	check(is_equal_approx(player.velocity.x, before_second_jump), "Second jump erased momentum")
	player.free()
	world.free()
	if failures == 0:
		print("Momentum passed: normal %.1fpx, slide jump %.1fpx, ratio %.2f" % [normal, boosted, boosted / normal])
	quit(1 if failures else 0)
