extends SceneTree

const Motion := preload("res://patterns/player_motion_profile.gd")
const Layout := preload("res://patterns/ninja_wave_layout.gd")
const Driver := preload("res://tests/ninja_map/input_driver.gd")
const TerrainDriver := preload("res://tests/jump_map/input_driver.gd")
const OUTPUT := "res://tests/artifacts/ninja-map/"
var world: Node2D
var player: Node2D
var module: Node2D
var driver := Driver.new()
var terrain_driver := TerrainDriver.new()
var failures := PackedStringArray()
var speed := Motion.RUN_SPEED
var capture_enabled := false
var damage := 0
var spawned := 0
var jumps := 0
var slides := 0
var entered_frame := -1
var captures := [1.5, 3.6, 27.5, 49.0, 67.0]
var capture_index := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--capture":
			capture_enabled = true
		elif argument.begins_with("--speed="):
			speed = argument.trim_prefix("--speed=").to_float()
	world = load("res://tests/ninja_map/NinjaMapPractice.tscn").instantiate()
	world.route_seed = 20260914
	root.add_child(world)
	current_scene = world
	player = world.player
	player.set_run_speed(speed)
	module = world.active_chunks[1]
	check(module.total_length > 0.0 and module.sections.size() == 3, "地图必须完整构建 3 Section")
	driver.configure(module, player)
	terrain_driver.configure(module, player)
	failures.append_array(Layout.validate_route(driver.actions))
	var wave_count := 0
	for section in module.sections:
		wave_count += section.runners.size()
		for runner in section.runners:
			failures.append_array(runner.plan.issues)
			runner.event_spawned.connect(on_spawn)
	check(wave_count == 4 and driver.actions.size() == 11, "忍者遭遇段缺少预期的阵型或地刺")
	player.damaged.connect(on_damage)
	player.jumped.connect(func(_index: int) -> void: jumps += 1)
	player.state_changed.connect(func(_previous: int, current: int) -> void:
		if current == player.MovementState.SLIDE:
			slides += 1)
	if failures.is_empty():
		await play()
	finish()

func play() -> void:
	var input := preload("res://tests/physics_input.gd").new()
	input.step = drive_input
	world.add_child(input)
	if capture_enabled:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
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
	check(damage == 0, "无战斗技能路线受伤 %d 次" % damage)
	check(driver.index == driver.actions.size(), "未执行每个跳滑动作")
	check(slides == driver.slides, "忍者下滑动作未实际完成")
	var expected := 0
	for section in module.sections:
		for runner in section.runners:
			expected += runner.plan.events.size()
	check(spawned == expected, "漏生成机关 %d/%d" % [spawned, expected])
	print("NINJA speed=%.0f length=%.0f duration=%.2f spawned=%d/%d jumps=%d slides=%d damage=%d hp=%.1f" %
		[speed, module.total_length, float(Engine.get_physics_frames() - entered_frame) / Engine.physics_ticks_per_second,
		spawned, expected, jumps, slides, damage, player.health])
	if capture_enabled and not failures.is_empty():
		await capture("failure-%d.png" % int(speed))

func on_spawn(_event: PatternEvent, _obstacle: Node2D) -> void:
	spawned += 1

func drive_input() -> void:
	terrain_driver.advance()
	driver.advance()

func on_damage(_amount: float) -> void:
	damage += 1
	var action: Dictionary = driver.actions[mini(driver.index, driver.actions.size() - 1)]
	print("DAMAGE x=%.1f state=%d h=%.1f action=%d next=%s@%.1f" % [player.global_position.x - module.global_position.x, player.movement_state, Motion.GROUND_Y - player.global_position.y, driver.index, action.kind, action.x - module.global_position.x])

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
	key = InputEventKey.new()
	key.keycode = KEY_F1
	key.physical_keycode = KEY_F1
	Input.parse_input_event(key)
	check(world.debug_overlay.visible, "F1 没有显示地图信息")

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + filename)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func finish() -> void:
	driver.release()
	terrain_driver.release()
	for failure in failures:
		printerr("FAIL: ", failure)
	world.free()
	quit(0 if failures.is_empty() else 1)
