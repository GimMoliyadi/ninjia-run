extends SceneTree

const PLAYER_SCENE := preload("res://player.tscn")
const GROUND_Y := 460.0
const PLAYER_START := Vector2(140.0, GROUND_Y)

func _initialize() -> void:
	var world := Node2D.new()
	root.add_child(world)
	add_ground(world)
	var player: CharacterBody2D = PLAYER_SCENE.instantiate()
	player.global_position = PLAYER_START
	world.add_child(player)

	await physics_frame
	await physics_frame
	var start_y: float = player.global_position.y
	player.jump_buffer_remaining = player.JUMP_BUFFER_TIME
	await physics_frame
	var rising_velocity: float = player.velocity.y
	if rising_velocity >= 0.0:
		printerr("Jump regression: buffered jump did not create upward velocity.")
		quit(1)
		return
	await physics_frame

	if player.global_position.y >= start_y:
		printerr("Jump regression: player did not leave the ground.")
		quit(1)
		return
	player.queue_free()
	await physics_frame
	var coyote_player: CharacterBody2D = PLAYER_SCENE.instantiate()
	coyote_player.global_position = Vector2(PLAYER_START.x, GROUND_Y - 160.0)
	world.add_child(coyote_player)
	await physics_frame
	coyote_player.coyote_remaining = coyote_player.COYOTE_TIME
	coyote_player.jump_buffer_remaining = coyote_player.JUMP_BUFFER_TIME
	await physics_frame
	if coyote_player.velocity.y >= 0.0:
		printerr("Jump regression: coyote-time jump did not create upward velocity.")
		quit(1)
		return
	print("Jump regression passed: buffered jump is consumed and the player leaves the ground.")
	quit(0)

func add_ground(parent: Node2D) -> void:
	var ground := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(1200.0, 80.0)
	collision.shape = shape
	collision.position = Vector2(600.0, GROUND_Y + 40.0)
	ground.add_child(collision)
	parent.add_child(ground)
