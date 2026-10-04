extends SceneTree

const Menu = preload("res://main_menu.tscn")
const PhysicsInput = preload("res://tests/physics_input.gd")
const FRAME_COUNT := 150
const JUMP_FRAME := 30
const SLIDE_FRAME := 84
const CAPTURE_DIRECTORY := "res://tests/artifacts/run-pose"
const CAPTURE_FRAMES := {12: "run", 40: "jump", 65: "fall", 94: "slide", 125: "boost-run"}

var _tick := 0
var _held: StringName = &""
var _errors := PackedStringArray()
var _capture_enabled := false


func _initialize() -> void:
	_capture_enabled = OS.get_cmdline_user_args().has("--capture")
	call_deferred("_run")


func _run() -> void:
	if _capture_enabled and DisplayServer.get_name() == "headless":
		printerr("连续跑姿截图需要真实渲染器，不能使用 --headless。")
		quit(1)
		return
	await _start_from_menu()
	if not _errors.is_empty():
		_finish()
		return
	var world: Node2D = current_scene
	var player: CharacterBody2D = world.get_node("Player")
	var visual: Node2D = player.get_node("PlayerVisual_V2")
	var driver := PhysicsInput.new()
	driver.step = _drive
	world.add_child(driver)
	var actions := {}
	var boost_run_seen := false
	for frame in range(FRAME_COUNT):
		await physics_frame
		await process_frame
		# process_frame 先于各节点 _process，须等本帧视觉更新后再比对步频。
		await create_timer(0.0).timeout
		actions[visual.visual_animation] = true
		if visual.visual_animation == &"run" and player.velocity.x > player.RUN_SPEED:
			boost_run_seen = true
			_check(is_equal_approx(visual.animation_player.speed_scale, player.velocity.x / player.RUN_SPEED), "真实 Player 加速跑时步频未匹配移动速度")
		if _capture_enabled and CAPTURE_FRAMES.has(frame):
			await _capture(CAPTURE_FRAMES[frame])
	_release_input()
	for action in [&"run", &"jump_start", &"jump_up", &"fall", &"land", &"slide"]:
		_check(actions.has(action), "真实输入未经过动作：%s" % action)
	_check(boost_run_seen, "滑铲后未观察到带动量的跑步")
	_check(visual.visible and not player.get_node("PlayerVisual").visible, "实跑必须使用 V2 而不是旧视觉")
	print("RUN_PLAYTEST actions=%s boost_run=%s capture=%s" % [actions.keys(), boost_run_seen, _capture_enabled])
	world.queue_free()
	await process_frame
	_finish()


func _start_from_menu() -> void:
	var menu: Control = Menu.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame
	var button: Button = menu.get_node("Center/Panel/Margin/Content/StartButton")
	button.grab_focus()
	if _capture_enabled:
		await _capture("menu")
	var accept := InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.physical_keycode = KEY_ENTER
	accept.pressed = true
	# 投递到本游戏视口，不依赖并行测试窗口的操作系统焦点。
	root.push_input(accept)
	await process_frame
	accept = accept.duplicate()
	accept.pressed = false
	root.push_input(accept)
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path == "res://test_world.tscn", "激活首页开始按钮后未进入正式游戏")


func _drive() -> void:
	_release_input()
	_tick += 1
	if _tick == JUMP_FRAME:
		_held = &"jump"
	elif _tick == SLIDE_FRAME:
		_held = &"slide"
	if not _held.is_empty():
		Input.action_press(_held)


func _release_input() -> void:
	if not _held.is_empty():
		Input.action_release(_held)
		_held = &""


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path(CAPTURE_DIRECTORY)
	var error := DirAccess.make_dir_recursive_absolute(directory)
	_check(error == OK, "无法创建跑姿截图目录")
	if error == OK:
		error = root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
		_check(error == OK, "无法保存截图：%s" % label)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _finish() -> void:
	for error in _errors:
		printerr(error)
	print("Run pose playtest passed." if _errors.is_empty() else "Run pose playtest failed.")
	quit(0 if _errors.is_empty() else 1)
