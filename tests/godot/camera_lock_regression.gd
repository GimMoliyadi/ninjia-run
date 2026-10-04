extends SceneTree

const PLAYER_SCENE := preload("res://player.tscn")
const CAMERA_SCRIPT := preload("res://dynamic_camera.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var player: Variant = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	player.position = Vector2(480, 240)
	var camera := Camera2D.new()
	camera.set_script(CAMERA_SCRIPT)
	camera.target = player
	root.add_child(camera)
	camera.set_process(false)
	check(camera.position.is_equal_approx(Vector2(630, 380)), "Camera must start 150px ahead at fixed Y")
	player.position.x += 600
	camera._process(1.0 / 60.0)
	check(camera.position.x > 630 and camera.position.x < 1230, "Camera follow must interpolate")
	player.velocity = Vector2(player.SLIDE_BURST_SPEED, 0)
	for frame in 120:
		camera._process(1.0 / 60.0)
	check(absf(camera.position.x - 1230) < 0.1 and camera.position.y == 380, "Camera follow did not settle")
	check(absf(camera.zoom.x - 0.85) < 0.001, "Fast movement must zoom out")
	player.velocity = Vector2.ZERO
	for frame in 120:
		camera._process(1.0 / 60.0)
	check(absf(camera.zoom.x - 1.0) < 0.001, "Slow movement must restore zoom")
	player.take_damage(1.0)
	check(camera.trauma > 0.0, "Damage did not trigger shake")
	camera._process(0.02)
	check(camera.offset.length() > 0.0, "Noise shake has no offset")
	player.reset_run(Vector2(140, 460))
	check(camera.trauma == 0.0 and camera.offset == Vector2.ZERO, "Restart did not clear shake")
	check(camera.position.is_equal_approx(Vector2(290, 380)), "Restart did not reset follow")
	camera.free()
	player.free()
	if failures == 0:
		print("Dynamic camera passed: leading follow, zoom, hit shake and restart")
	quit(1 if failures else 0)
