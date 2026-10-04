extends SceneTree

const TestScene := preload("res://tests/jump/JumpTest.tscn")
const ROUTES := [
	{"first_x": 480.0, "hold": 1},
	{"first_x": 450.0, "hold": 24},
	{"first_x": 520.0, "hold": 24, "second_x": 690.0, "second_hold": 20},
	{"first_x": 420.0, "hold": 1, "second_x": 495.0, "second_hold": 8},
	{"first_x": 450.0, "hold": 24, "second_x": 610.0, "second_hold": 6, "down_x": 670.0}
]
var test: Node2D
var failures: Array[String] = []
var captured: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func frame() -> void:
	await physics_frame
	await process_frame

func run() -> void:
	test = TestScene.instantiate()
	test.enable_runtime_bridge = false
	root.add_child(test)
	current_scene = test
	for index in ROUTES.size():
		var result := await attempt(index, ROUTES[index])
		print("COURSE %d: %s" % [index + 1, result])
		if not result.passed:
			failures.append("JumpTest %d route failed" % (index + 1))
		if index == 3 and (not result.compact_in_gap or not result.waiting_in_gap or not result.restored):
			failures.append("Gap must use compact body and restore after exit")
	var no_second := await attempt(2, {"first_x": 520.0, "hold": 24})
	if no_second.passed:
		failures.append("Long gap should require the second jump")
	var no_roll := await attempt(3, {"first_x": 500.0, "hold": 24})
	if no_roll.passed:
		failures.append("Normal collider must not fit the roll corridor")
	paused = false
	test.free()
	Input.action_release("jump")
	Input.action_release("slide")
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Jump courses passed: five real input routes, including compact gap and safe exit")
	quit(0 if failures.is_empty() else 1)

func attempt(index: int, route: Dictionary) -> Dictionary:
	test.select_case(index)
	await frame()
	test.toggle_pause()
	var first := false
	var second := false
	var down := false
	var release_at := -1
	var compact_in_gap := false
	var restored := false
	var waiting_in_gap := false
	for tick in 260:
		if tick == release_at:
			Input.action_release("jump")
		if not first and test.player.position.x >= route.first_x:
			Input.action_press("jump")
			first = true
			release_at = tick + route.hold
		elif first and not second and test.player.position.x >= route.get("second_x", INF):
			Input.action_press("jump")
			second = true
			release_at = tick + route.get("second_hold", 20)
		if not down and test.player.position.x >= route.get("down_x", INF):
			Input.action_press("slide")
			down = true
		await frame()
		if index == 3 and OS.get_cmdline_user_args().has("--capture"):
			await capture_roll()
		if index == 3 and test.player.position.x > 620 and test.player.position.x < 720:
			compact_in_gap = compact_in_gap or test.player.roll_hitbox_active
			waiting_in_gap = waiting_in_gap or (test.player.roll_hitbox_active and test.player.roll_remaining <= 0)
		if index == 3 and test.player.position.x > 780:
			restored = restored or not test.player.roll_hitbox_active
		if test.finished:
			break
	var result := {"passed": test.player.position.x > test.END_X, "x": test.player.position.x, "y": test.player.position.y,
		"compact_in_gap": compact_in_gap, "waiting_in_gap": waiting_in_gap, "restored": restored}
	Input.action_release("jump")
	Input.action_release("slide")
	return result

func capture_roll() -> void:
	var label := ""
	if test.player.roll_remaining > 0 and test.player.position.x > 535:
		label = "jump-roll"
	elif test.player.roll_hitbox_active and test.player.roll_remaining <= 0 and test.player.position.x > 620:
		label = "jump-gap-wait"
	elif not test.player.roll_hitbox_active and test.player.position.x > 780:
		label = "jump-gap-exit"
	if label.is_empty() or captured.has(label):
		return
	captured[label] = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/%s.png" % label)
