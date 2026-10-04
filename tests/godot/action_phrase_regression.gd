extends SceneTree

const World := preload("res://test_world.tscn")
const PracticeWorld := preload("res://tests/godot/action_phrase_practice_world.gd")
const PracticeRoute := PracticeWorld.PracticeRoute
const Motion := preload("res://patterns/player_motion_profile.gd")
const Compiler := preload("res://patterns/pattern_compiler.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")
const JumpWave := preload("res://patterns/jump_wave_layout.gd")
const Layouts := preload("res://patterns/pattern_layouts.gd")
var failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := World.instantiate()
	world.set_script(PracticeWorld)
	world.route_seed = 20261001
	root.add_child(world)
	var route := PracticeRoute.new(world.route_seed).build_cycle(0)
	while world.active_chunks.size() < route.size():
		world.spawn_chunk()
	var coin_layouts := {}
	for index in range(1, route.size() - 1):
		var chunk: MapModuleChunk = world.active_chunks[index]
		check(chunk.build_ready, "add_child 后必须同步完成 Exit")
		check(chunk.get_node("Entry").global_position.is_equal_approx(world.active_chunks[index - 1].get_node("Exit").global_position), "Entry/Exit 接缝")
		check(chunk.debug_info().issues.is_empty(), "组合编译失败")
		if route[index] == PracticeRoute.ChunkKind.SHORT_RECOVERY:
			check(chunk.sections[0].runners.is_empty(), "喘息含强制障碍")
			check(chunk.total_length / Motion.Player.SLIDE_BURST_SPEED >= Motion.jump_time(), "峰值速度喘息小于落地周期")
			check(chunk.total_length / Motion.RUN_SPEED <= 1.5, "喘息过长")
			var coins := PackedVector2Array()
			for child in chunk.sections[0].get_children():
				if child is Coin:
					check(child.position.x > 0.0 and child.position.x < chunk.total_length, "喘息金币越界")
					coins.append(child.position)
			check(coins.size() == 3, "喘息缺少低压力金币")
			coin_layouts[str(coins)] = true
		else:
			check(chunk.total_length / Motion.Player.SLIDE_BURST_SPEED >= 3.0 and chunk.total_length / Motion.RUN_SPEED <= 7.0, "实际速度边界长度不合规")
			check_geometry(chunk)
	check(coin_layouts.size() > 1, "喘息金币没有保留种子变化")
	await check_pause(world)
	world.restart_run()
	check(world.route_steps == route and world.player.active, "固定种子重开未恢复首圈")
	check(world.player.boost_speed == 0.0, "重开保留上一轮动量")
	check_nonflat_darts(world)
	world.free()
	for failure in failures:
		printerr(failure)
	print("Action phrase geometry/state regression: failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func check_geometry(chunk: MapModuleChunk) -> void:
	var jumping := false
	var sliding := false
	for section in chunk.sections:
		for runner in section.runners:
			for event in runner.plan.events:
				if event.obstacle_scene == JumpWave.SPIKES:
					jumping = jumping or event.preview_size.y > Motion.SLIDE_HEIGHT
				if event.obstacle_scene == JumpWave.PILLAR:
					jumping = jumping or event.preview_size.y > Motion.SLIDE_HEIGHT
				if event.obstacle_scene == Layouts.CEILING:
					var clearance: float = -event.position_offset.y - event.preview_size.y
					sliding = sliding or (clearance > Motion.SLIDE_HEIGHT and clearance < Motion.BODY_SIZE.y)
					check(clearance > Motion.SLIDE_HEIGHT and clearance < Motion.BODY_SIZE.y, "低梁站立可过或滑铲不可过")
			check(runner.plan.needs_manual_playtest, "自动测试不能关闭人工试玩标记")
			var data: ObstaclePatternData = section.data.entries[0].duplicate(true)
			data.duration = 8.0
			check(not Compiler.compile(data, 1, Modifier.Kind.NORMAL, RecoverySection.new()).issues.is_empty(), "超过7秒未拒绝")
			data.duration = 2.0
			check(not Compiler.compile(data, 1, Modifier.Kind.NORMAL, RecoverySection.new()).issues.is_empty(), "峰值速度不足3秒未拒绝")
	check(jumping and sliding, "实际几何未同时迫使跳跃和低身")
	if chunk.module_data.module_id == "Dart_Jump_Slide_Phrase":
		check(chunk.act_report.get("acts", 0) == 1, "MIXED theme 漏掉平地飞镖 ACT 检查")
		check(chunk.act_report.issues.is_empty() and chunk.act_report.notes.is_empty(), "混合组合 ACT 校验失败")

func check_pause(world: Node2D) -> void:
	await physics_frame
	await process_frame
	var runner: PatternRunner = world.active_chunks[1].sections[0].runners[0]
	var before_x: float = world.player.global_position.x
	var before_elapsed := runner.elapsed
	world.toggle_pause()
	for frame in 8:
		await physics_frame
		await process_frame
	check(world.player.global_position.x == before_x and runner.elapsed == before_elapsed, "暂停中玩家或距离型 Wave 推进")
	world.toggle_pause()
	await physics_frame
	await process_frame
	check(world.player.global_position.x > before_x, "恢复后玩家没有推进")

func check_nonflat_darts(world: Node2D) -> void:
	for path in ["res://scenes/segment_platform_dart_map.tscn", "res://scenes/segment_rope_map.tscn"]:
		var scene: PackedScene = load(path)
		var chunk: MapModuleChunk = scene.instantiate()
		world.add_child(chunk)
		var dart_count := 0
		for section in chunk.sections:
			for runner in section.runners:
				for event in runner.plan.events:
					dart_count += int(event.preview_kind == PatternEvent.PreviewKind.DART)
		check(dart_count > 0, "非平地隔离样例没有飞镖：" + path)
		check(chunk.act_report.is_empty(), "平台或绳索飞镖误用平地 ACT 覆盖检查：" + path)
		chunk.free()

func check(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)
