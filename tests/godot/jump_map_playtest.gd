extends SceneTree

const Driver := preload("res://tests/jump_map/input_driver.gd")
const NinjaDriver := preload("res://tests/ninja_map/input_driver.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const OUTPUT := "res://tests/artifacts/jump-map/"
const MAX_FRAMES := 7200
var world: Node2D
var player: Node2D
var module: Node2D
var driver := Driver.new()
var ninja_driver := NinjaDriver.new()
var failures := PackedStringArray()
var damage_count := 0
var spawned := 0
var screen_spawns := 0
var pillar_landings := 0
var blocked_frames := 0
var captures := [3.0, 10.0, 19.0, 24.0, 28.0, 35.0, 45.0, 54.0, 63.0, 68.0, 71.5]
var capture_index := 0
var capture_enabled := false
var speed := Motion.RUN_SPEED
var peak_speed := 0.0
var entered_frame := -1
var capture_tag := ""
var bump_enabled := false
var bump_frames := 0
var bump_start := Vector2.ZERO
var bump_camera_x := 0.0
var bump_wave_time := 0.0
var bump_max_lag := 0.0
var bump_recovered := false
var bump_waiting := true
const BUMP_HOLD_FRAMES := 18

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--capture":
			capture_enabled = true
		elif argument == "--boost":
			driver.boost_enabled = true
		elif argument == "--bump":
			bump_enabled = true
			driver.boost_enabled = true
		elif argument.begins_with("--speed="):
			speed = argument.trim_prefix("--speed=").to_float()
	world = load("res://tests/jump_map/JumpMapPractice.tscn").instantiate()
	world.route_seed = 20260913
	root.add_child(world)
	current_scene = world
	player = world.player
	player.set_run_speed(speed)
	for chunk in world.active_chunks:
		if "module_data" in chunk and chunk.module_data.module_id == "Jump_Map_A":
			module = chunk
	if module == null:
		printerr("Jump_Map_A 没有进入正式游戏驱动")
		world.free()
		quit(1)
		return
	if module.total_length <= 0.0 or module.sections.size() != 3:
		failures.append("地图没有完整构建")
	driver.configure(module, player)
	ninja_driver.configure(module, player)
	player.damaged.connect(on_damage)
	player.landed.connect(on_landed)
	for section in module.sections:
		for runner in section.runners:
			runner.event_spawned.connect(on_spawn)
			failures.append_array(runner.plan.issues)
	if not failures.is_empty():
		finish()
		return
	if capture_enabled:
		await show_debug_overlay()
	capture_tag = str(int(speed)) + ("-boost" if driver.boost_enabled else "")
	if bump_enabled:
		capture_tag += "-bump"
	var input := preload("res://tests/physics_input.gd").new()
	input.step = drive_input
	world.add_child(input)
	await play()
	finish()

func play() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var exit_x: float = module.get_node("Exit").global_position.x
	for frame in MAX_FRAMES:
		await physics_frame
		await process_frame
		peak_speed = maxf(peak_speed, player.velocity.x)
		if entered_frame < 0 and player.global_position.x >= module.global_position.x:
			entered_frame = Engine.get_physics_frames()
		if player.velocity.x < speed * 0.5:
			blocked_frames += 1
		if bump_enabled:
			bump_max_lag = maxf(bump_max_lag, world.arena_x - player.global_position.x)
			if capture_enabled and (bump_frames == 1 or bump_frames == BUMP_HOLD_FRAMES):
				await capture("bump-%02d.png" % bump_frames)
			if not bump_recovered and bump_frames == BUMP_HOLD_FRAMES + 1 and world.arena_x - player.global_position.x < Motion.BODY_SIZE.x:
				bump_recovered = true
				print("BUMP recovered: max_lag=%.1f current_lag=%.1f" % [bump_max_lag, world.arena_x - player.global_position.x])
				if capture_enabled:
					await capture("bump-recovered.png")
		var progress: float = (player.global_position.x - module.global_position.x) / Motion.RUN_SPEED
		if capture_enabled and capture_index < captures.size() and progress >= captures[capture_index]:
			await capture("%02d-%s.png" % [capture_index, capture_tag])
			capture_index += 1
		if not player.active or player.global_position.x >= exit_x:
			break
	if player.global_position.x < exit_x:
		failures.append("未到达地图出口")
	if damage_count > 0:
		failures.append("无技能输入路线受伤 %d 次" % damage_count)
	if blocked_frames > 0 and not bump_enabled:
		failures.append("柱侧阻挡 %d 帧" % blocked_frames)
	if bump_enabled and (bump_frames <= BUMP_HOLD_FRAMES or not bump_recovered):
		failures.append("没有完成撞台、补跳和追赶")
	if screen_spawns > 0:
		failures.append("有 %d 个障碍在屏内生成" % screen_spawns)
	var expected := 0
	for section in module.sections:
		for runner in section.runners:
			expected += runner.plan.events.size()
			if not runner.completed or runner.get_child_count() > 0:
				failures.append("出口仍残留 Wave 障碍")
	if spawned != expected:
		failures.append("障碍生成不完整 %d/%d" % [spawned, expected])
	if driver.boost_enabled and (driver.boost_presses == 0 or peak_speed < Motion.Player.SLIDE_BURST_SPEED):
		failures.append("未实际触发滑铲加速")
	print("BOOST presses=%d peak_speed=%.0f" % [driver.boost_presses, peak_speed])
	print("Actual map traversal: %.2fs" % [float(Engine.get_physics_frames() - entered_frame) / Engine.physics_ticks_per_second])
	print("JUMP_MAP speed=%.0f length=%.0f duration=%.2f spawned=%d/%d damage=%d landings=%d blocked=%d screen_spawns=%d hp=%.1f" %
		[speed, module.total_length, module.total_length / speed, spawned, expected, damage_count, pillar_landings, blocked_frames, screen_spawns, player.health])
	if capture_enabled and not failures.is_empty():
		await capture("failure-%d.png" % int(speed))

func drive_input() -> void:
	if not bump_enabled or not bump_waiting:
		driver.advance()
		ninja_driver.advance()
		return
	var first_pillar: float = module.sections[1].runners[0].global_position.x + module.sections[1].runners[0].plan.events[0].position_offset.x
	if player.global_position.x < first_pillar - Motion.RUN_SPEED:
		driver.advance()
		ninja_driver.advance()
		return
	driver.release()
	if player.velocity.x > 0.0:
		return
	if bump_frames == 0:
		bump_start = Vector2(player.global_position.x, world.arena_x)
		bump_camera_x = world.dynamic_camera.global_position.x
		bump_wave_time = module.sections[1].runners[0].elapsed
	bump_frames += 1
	if bump_frames > BUMP_HOLD_FRAMES:
		var camera_travel: float = world.dynamic_camera.global_position.x - bump_camera_x
		var arena_travel: float = world.arena_x - bump_start.y
		if absf(player.global_position.x - bump_start.x) > 1.0 or arena_travel < Motion.BODY_SIZE.x or camera_travel < Motion.BODY_SIZE.x:
			failures.append("撞墙时玩家或竞技场/镜头推进不符合预期")
		if module.sections[1].runners[0].elapsed <= bump_wave_time:
			failures.append("撞墙时 Wave 停止推进")
		print("BUMP player_travel=%.2f arena_travel=%.1f camera_travel=%.1f" % [player.global_position.x - bump_start.x, arena_travel, camera_travel])
		bump_waiting = false
		driver.advance()
		ninja_driver.advance()

func on_damage(_amount: float) -> void:
	damage_count += 1
	print("DAMAGE x=%.1f height=%.1f wave=%s" % [player.global_position.x - module.global_position.x, Motion.GROUND_Y - player.global_position.y, module.debug_info_at(player.global_position.x).get("wave", "")])

func on_landed(_speed: float) -> void:
	if player.global_position.y < Motion.GROUND_Y - 2.0:
		pillar_landings += 1

func on_spawn(_event: PatternEvent, obstacle: Node2D) -> void:
	spawned += 1
	if (root.get_canvas_transform() * obstacle.global_position).x < root.get_visible_rect().end.x:
		screen_spawns += 1

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + filename)

func show_debug_overlay() -> void:
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
	released.pressed = false
	Input.parse_input_event(released)
	if not world.debug_overlay.visible:
		failures.append("F1 没有打开调试信息")

func finish() -> void:
	driver.release()
	ninja_driver.release()
	for failure in failures:
		printerr("FAIL: ", failure)
	world.free()
	quit(0 if failures.is_empty() else 1)
