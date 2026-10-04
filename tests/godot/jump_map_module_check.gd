extends SceneTree

const Route := preload("res://components/rhythm_route_generator.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
var failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://tests/jump_map/JumpMapPractice.tscn").instantiate()
	world.route_seed = 20260913
	root.add_child(world)
	await process_frame
	await check_f1(world)
	check(world.route_steps[1] != Route.ChunkKind.SAFE, "热身后必须进入完整地图")
	var module: Node2D
	var previous: Node2D
	for index in world.route_steps.size():
		while world.active_chunks.size() <= index:
			check(world.spawn_chunk(), "正式路由无法创建跳跃地图")
		if world.route_steps[index] == Route.ChunkKind.JUMP_MAP:
			module = world.active_chunks[index]
			previous = world.active_chunks[index - 1]
			break
	if module == null:
		check(false, "正式路由缺少跳跃地图")
		world.free()
		quit(1)
		return
	check(module.module_data.module_id == "Jump_Map_A", "正式场景索引指向错误模块")
	check(module.get_node("Entry").global_position.is_equal_approx(previous.get_node("Exit").global_position), "跳跃地图入口接缝错位")
	check_module(module, world)
	check_repeat(module, world)
	await check_lifecycle(module, world)
	world.free()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("Jump Map Module check: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func check_module(module: Node2D, world: Node) -> void:
	check(module.sections.size() == 3, "应有三个 Section")
	check(module.total_length / Motion.RUN_SPEED <= 90.0, "常速时长超过90秒")
	check(module.total_length / Motion.Player.SLIDE_BURST_SPEED >= 20.0, "高速时长不足20秒")
	var length := 0.0
	var waves := 0
	var spikes := 0
	var pillars := 0
	var ninjas := 0
	for section in module.sections:
		check(is_equal_approx(section.position.x, length), "Section 接缝错位")
		length += section.section_length
		check(section.all_issues().is_empty(), "存在编译问题")
		for runner in section.runners:
			waves += 1
			if runner.plan.has("distance_driven"):
				check(runner.plan.distance_driven, "Wave 未提前确定空间布局")
			var info: Dictionary = module.debug_info_at(runner.global_position.x + 1.0)
			check(not info.wave.is_empty() and not info.section.is_empty(), "F1 缺少自然语言名称")
			var label: String = world._format_pattern_debug(module.debug_info(), module, runner.global_position.x + 1.0)
			check(label.contains("Map: 踏石 · 棘林") and label.contains("Wave: " + info.wave), "F1 未显示当前地图和波次")
			for event in runner.plan.events:
				if runner.plan.has("ninja_actions"):
					ninjas += 1
					continue
				if runner.plan.get("jump_layout", false):
					check(event.position_offset.x - event.spawn_time * Motion.RUN_SPEED > 900.0, "%s 障碍前瞻不足" % runner.name)
				if event.preview_kind == PatternEvent.PreviewKind.OTHER:
					pillars += 1
				else:
					spikes += 1
	check(waves == 10 and spikes == 9 and pillars == 10 and ninjas == 9, "混合地图的波次或障碍数量错误")
	check(is_equal_approx(length, module.total_length), "总长与 Section 不一致")
	check(is_equal_approx(length, module.get_node("Exit").position.x), "出口与真实总长不一致")
	print("Jump: waves=%d spikes=%d pillars=%d length=%.0f" % [waves, spikes, pillars, length])

func check_repeat(module: Node2D, world: Node) -> void:
	var repeated: Node2D = load("res://scenes/segment_jump_map.tscn").instantiate()
	repeated.position = module.get_node("Exit").global_position - Vector2(0, Motion.GROUND_Y)
	world.add_child(repeated)
	check(repeated.get_node("Entry").global_position.is_equal_approx(module.get_node("Exit").global_position), "重复拼接不连续")
	check(is_equal_approx(repeated.total_length, module.total_length), "重复构建改变了地图长度")
	repeated.free()

func check_lifecycle(module: Node2D, world: Node) -> void:
	var runner: Node = module.sections[0].runners[0]
	runner.advance_distance(0.0)
	var obstacle: Node = runner.get_child(0)
	var before: Vector2 = world.player.global_position
	var elapsed: float = runner.elapsed
	var arena_before: float = world.arena_x
	world.toggle_pause()
	for frame in 8:
		await process_frame
	check(world.player.global_position == before and runner.elapsed == elapsed, "暂停时角色或 Wave 仍推进")
	check(world.arena_x == arena_before, "暂停时竞技场仍推进")
	world.toggle_pause()
	check(not paused, "无法恢复游戏")
	world.restart_run()
	await process_frame
	check(not is_instance_valid(module) and not is_instance_valid(obstacle), "重开残留旧地图或障碍")
	check(world.player.health == world.player.MAX_HP, "重开没有恢复角色状态")
	check(absf(world.arena_x - world.player.global_position.x) <= Motion.BODY_SIZE.x, "重开没有清除竞技场领先距离")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func check_f1(world: Node) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.physical_keycode = KEY_F1
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	for frame in 3:
		await physics_frame
		await process_frame
	check(world.debug_overlay.visible, "F1 输入未打开调试覆盖层")
	var released := InputEventKey.new()
	released.keycode = KEY_F1
	released.physical_keycode = KEY_F1
	Input.parse_input_event(released)
