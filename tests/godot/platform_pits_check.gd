extends SceneTree

const Motion := preload("res://patterns/player_motion_profile.gd")
const Layout := preload("res://patterns/jump_wave_layout.gd")
var failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check_threshold()
	var world: Node2D = load("res://tests/jump_map/JumpMapPractice.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	await process_frame
	var module: Node2D = world.active_chunks[1]
	check_ground(module)
	await check_left_behind(world, module)
	world.free()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("Platform pits check: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func check_threshold() -> void:
	var threshold := Motion.safe_double_jump_gap()
	check(threshold > 0.0, "可靠距离必须为正")
	check(Motion.safe_double_jump_gap(Motion.jump_height()) < threshold, "更高落点没有缩短安全距离")
	check(Motion.safe_double_jump_gap(Motion.double_jump_height()) == 0.0, "不可达柱高仍挖坑")
	var frame_distance := Motion.RUN_SPEED / Engine.physics_ticks_per_second
	var first_beat := 1.0
	var pillar_width_ratio := 4.0
	var pillar_width := Motion.BODY_SIZE.x * pillar_width_ratio
	for gap in [threshold - frame_distance, threshold, threshold + frame_distance]:
		var data := ObstaclePatternData.new()
		data.template = "JUMP_WAVE"
		data.start_delay = 0.0
		data.supports_speed = false
		# 多留一帧地面，避免恰好压在出口余量上的浮点舍入干扰坑阈值检查。
		var second_beat: float = first_beat + (pillar_width + gap) / Motion.RUN_SPEED
		data.duration = second_beat + (pillar_width + frame_distance) / Motion.RUN_SPEED + Layout.LANDING_MARGIN
		data.parameters = {"phrases": [
			{"pattern": "pillar", "beat": first_beat, "width_ratio": pillar_width_ratio, "height_ratio": 0.5},
			{"pattern": "pillar", "beat": second_beat, "width_ratio": pillar_width_ratio, "height_ratio": 0.5},
		]}
		var plan := Layout.compile(data, PatternModifier.Kind.NORMAL, RecoverySection.new())
		check(plan.issues.is_empty(), "阈值样例编译失败 gap=%.2f: %s" % [gap, "; ".join(plan.issues)])
		check(plan.events.size() == 2, "阈值样例必须保留两根柱子")
		check((not plan.pits.is_empty()) == (gap <= threshold), "阈值边界判断错误")
	print("Safe double-jump gap at equal height: %.2f px" % threshold)

func check_ground(module: Node2D) -> void:
	var platforms: Array[Dictionary] = []
	for section in module.sections:
		for runner in section.runners:
			for event in runner.plan.events:
				if event.obstacle_scene == Layout.PILLAR:
					platforms.append({"rect": Rect2(Vector2(runner.global_position.x + event.position_offset.x, 0), event.preview_size), "runner": runner})
	platforms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rect.position.x < b.rect.position.x)
	var pits := 0
	var flats := 0
	var seam_pits := 0
	for index in range(1, platforms.size()):
		var left: Rect2 = platforms[index - 1].rect
		var right: Rect2 = platforms[index].rect
		var gap := right.position.x - left.end.x
		var should_pit := gap <= Motion.safe_double_jump_gap(right.size.y - left.size.y)
		pits += int(should_pit)
		flats += int(not should_pit)
		seam_pits += int(should_pit and platforms[index - 1].runner != platforms[index].runner)
		for fraction in [0.25, 0.5, 0.75]:
			var x := lerpf(left.end.x, right.position.x, fraction)
			var query := PhysicsRayQueryParameters2D.create(Vector2(x, Motion.GROUND_Y - 1.0), Vector2(x, Motion.GROUND_Y + PatternSection.GROUND_THICKNESS), 1)
			var hit := module.get_world_2d().direct_space_state.intersect_ray(query)
			check(hit.is_empty() == should_pit, "柱间实际碰撞地面不符，pair=%d x=%.1f gap=%.1f" % [index, x, gap])
	check(pits > 0 and flats > 0 and seam_pits > 0, "没有覆盖坑、远距平地和跨 Wave 坑")
	print("Adjacent platforms: %d pits, %d flat gaps, %d pits cross Wave boundaries" % [pits, flats, seam_pits])

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func check_left_behind(world: Node2D, module: Node2D) -> void:
	var runner: Node2D = module.sections[1].runners[0]
	var pillar_x: float = runner.global_position.x + runner.plan.events[0].position_offset.x
	world.player.reset_run(Vector2(pillar_x - Motion.BODY_SIZE.x * 2.0, Motion.GROUND_Y))
	world.arena_x = world.player.global_position.x
	for frame in Engine.physics_ticks_per_second * 3:
		await physics_frame
		await process_frame
		if not world.player.active:
			break
	check(not world.player.active and world.run_state == world.RunState.GAME_OVER, "持续撞墙落后出屏后未结束游戏")
	world.restart_run()
	await process_frame
	check(world.player.active and not paused, "落后出屏失败后无法重开")
