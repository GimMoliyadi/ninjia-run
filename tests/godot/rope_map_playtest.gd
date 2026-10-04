extends SceneTree

const Motion := preload("res://patterns/player_motion_profile.gd")
const Layout := preload("res://patterns/rope_wave_layout.gd")
const Driver := preload("res://tests/rope_map/input_driver.gd")
const OUTPUT := "res://tests/artifacts/rope-map/"
var world: Node2D
var player: Node2D
var module: Node2D
var driver := Driver.new()
var failures := PackedStringArray()
var speed := Motion.RUN_SPEED
var capture_enabled := false
var damage := 0
var spawned := 0
var screen_spawns := 0
var jumps := 0
var entered_frame := -1
var captures := [3.0, 6.0, 11.0, 19.0, 25.0, 28.0, 34.0, 42.0, 51.0, 60.0, 65.0, 71.0]
var capture_index := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--capture":
			capture_enabled = true
		elif argument.begins_with("--speed="):
			speed = argument.trim_prefix("--speed=").to_float()
	world = load("res://tests/rope_map/RopeMapPractice.tscn").instantiate()
	world.route_seed = 20260913
	root.add_child(world)
	current_scene = world
	player = world.player
	player.set_run_speed(speed)
	module = world.active_chunks[1]
	check(module.total_length > 0.0 and module.sections.size() == 3, "模块未完整构建")
	driver.configure(module, player)
	failures.append_array(Layout.validate_route(driver.actions))
	for section in module.sections:
		for runner in section.runners:
			failures.append_array(runner.plan.issues)
			runner.event_spawned.connect(on_spawn)
	player.damaged.connect(on_damage)
	player.jumped.connect(func(_index: int) -> void: jumps += 1)
	if failures.is_empty():
		await play()
	finish()

func play() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var input := preload("res://tests/physics_input.gd").new()
	input.step = driver.advance
	world.add_child(input)
	if capture_enabled:
		await show_debug()
	var exit_x: float = module.get_node("Exit").global_position.x
	for frame in Engine.physics_ticks_per_second * 120:
		await physics_frame
		await process_frame
		if entered_frame < 0 and player.global_position.x >= module.global_position.x:
			entered_frame = Engine.get_physics_frames()
		var progress: float = (player.global_position.x - module.global_position.x) / Motion.RUN_SPEED
		if capture_enabled and capture_index < captures.size() and progress >= captures[capture_index]:
			await capture("%02d-%d.png" % [capture_index, int(speed)])
			capture_index += 1
		if not player.active or player.global_position.x >= exit_x:
			break
	check(player.active and player.global_position.x >= exit_x, "未存活到地图出口")
	check(damage == 0, "无技能路线受伤 %d 次" % damage)
	check(screen_spawns == 0, "障碍屏内出生 %d 次" % screen_spawns)
	# 翻面次数不再按固定条数写死。
	# 2026-09-22 绳索段重排为「波浪 → 地刺 → 横排」三段递进：
	# 波浪段一次切换、地刺段保持一侧、横排段连续错位，
	# 全图 18 次翻绳是有意编排的结果，不是旧版 40 次那种密集拍点。
	# 这里只守住「它仍然是一张需要持续上下切换的绳图」——
	# 平均每 4 秒至少完成一次翻绳；退化成一条平坦绳索通道就会失败。
	var flip_budget := int(module.total_length / Motion.RUN_SPEED / 4.0)
	check(driver.flips >= flip_budget, "没有连续上下翻绳 %d/%d" % [driver.flips, flip_budget])
	check(float(driver.rope_frames) / driver.total_frames > 0.7, "主要操作时间没有在绳上")
	var expected := 0
	var expected_jumps := 0
	for action in driver.actions:
		expected_jumps += int(action.kind == "jump")
	for section in module.sections:
		for runner in section.runners:
			expected += runner.plan.events.size()
	check(spawned == expected, "漏生成障碍 %d/%d" % [spawned, expected])
	check(jumps == expected_jumps, "未实际完成每次跳刺 %d/%d" % [jumps, expected_jumps])
	print("ROPE speed=%.0f length=%.0f duration=%.2f spawned=%d/%d flips=%d jumps=%d/%d rope=%.1f%% damage=%d screen_spawns=%d hp=%.1f" %
		[speed, module.total_length, float(Engine.get_physics_frames() - entered_frame) / Engine.physics_ticks_per_second,
		spawned, expected, driver.flips, jumps, expected_jumps, 100.0 * driver.rope_frames / driver.total_frames, damage, screen_spawns, player.health])
	if capture_enabled and not failures.is_empty():
		await capture("failure-%d.png" % int(speed))

func on_spawn(_event: PatternEvent, obstacle: Node2D) -> void:
	spawned += 1
	if (root.get_canvas_transform() * obstacle.global_position).x < root.get_visible_rect().end.x:
		screen_spawns += 1

func on_damage(_amount: float) -> void:
	damage += 1
	print("DAMAGE x=%.1f side=%d state=%d h=%.1f gate=%d" % [player.global_position.x - module.global_position.x, player.rope_side, player.movement_state, Motion.GROUND_Y - player.global_position.y, driver.index])

func show_debug() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.physical_keycode = KEY_F1
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	for frame in 3:
		await physics_frame
		await process_frame
	var released := InputEventKey.new()
	released.keycode = KEY_F1
	released.physical_keycode = KEY_F1
	Input.parse_input_event(released)
	check(world.debug_overlay.visible, "F1 没有显示地图信息")

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + filename)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func finish() -> void:
	driver.release()
	for failure in failures:
		printerr("FAIL: ", failure)
	world.free()
	quit(0 if failures.is_empty() else 1)
