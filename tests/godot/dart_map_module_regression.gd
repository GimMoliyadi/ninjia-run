extends SceneTree

const DartEncounter := preload("res://components/dart_encounter.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")

var failures := PackedStringArray()

func _init() -> void:
	await _run()

func _run() -> void:
	var world: Node = load("res://tests/dart_map/DartMapPractice.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame

	var module: Node = null
	for chunk in world.active_chunks:
		if chunk.get_script() == DartEncounter:
			module = chunk
			break
	_check(module != null, "正式游戏没有生成 Dart_Map_A")
	if module == null:
		_finish()
		return

	_check(module.build_ready, "Dart_Map_A 构建未完成")
	_check(module.module_data.module_id == "Dart_Map_A", "加载了错误的 Map Module")
	_check(module.sections.size() == 3, "Dart_Map_A 必须包含 3 个 Section")
	_check(module.total_length > 0.0, "Map Module 总长度无效")
	_check(absf(module.get_node("Exit").position.x - module.total_length) < 0.5,
		"Module Exit 没有落在真实总长度")

	# 全图 ACT 衔接体检（见 components/map_module_chunk.gd::_check_act_continuity）。
	#
	# 这一条是本轮任务的验收点：相邻的「必须做动作」的飞镖要么被同一个滑铲
	# 连起来（<= 268px），要么干净地分开（>= 384px），不允许落在死区里。
	# 死区不会让关卡变成不可解，但会逼出帧级操作 —— 而「自然衔接」正是本轮的目标。
	#
	# ⚠ 必须先确认体检**真的跑了**再断言它没报问题。
	# `_check_act_continuity()` 有一道 theme 门（非 DARTS 直接 return），
	# 一旦门把 Dart_Map_A 也挡住，act_report 会是 `{}`，
	# 下面两条 `get(..., []).is_empty()` 就会**平凡通过** ——
	# 检查被静默关掉却显示绿色，比检查报错更危险。
	_check(module.act_report.get("acts", 0) >= 20,
		"ACT 衔接体检没有真正执行（只看到 %d 枚 ACT 飞镖）" % module.act_report.get("acts", 0))
	_check(module.act_report.get("issues", []).is_empty(),
		"飞镖衔接存在物理上盖不住的贴地簇：%s" % str(module.act_report.get("issues", [])))
	_check(module.act_report.get("notes", []).is_empty(),
		"飞镖衔接落进死区：%s" % str(module.act_report.get("notes", [])))

	for index in range(1, module.sections.size()):
		var previous = module.sections[index - 1]
		var current = module.sections[index]
		var expected_x: float = previous.position.x + previous.section_length
		_check(absf(current.position.x - expected_x) < 0.5,
			"Section %d 接缝不连续" % (index + 1))

	var repeats: Node2D = load("res://scenes/segment_darts.tscn").instantiate()
	repeats.position = module.get_node("Exit").global_position - Vector2(0, Motion.GROUND_Y)
	world.add_child(repeats)
	_check(repeats.get_node("Entry").global_position.is_equal_approx(module.get_node("Exit").global_position),
		"重复模块 Entry 没有与上一模块 Exit 对齐")
	_check(is_equal_approx(repeats.total_length, module.total_length), "重复模块长度不一致")
	# ⚠ 时长守卫的口径（2026-09-18 第 7 轮重新标定）
	#
	# 旧口径是给「程序化长模块」标定的：<= 90s@400（90 秒守卫）
	# 与 >= 45s@620（与 tests/godot/jump_map_module_check.gd 共用的模板标准，
	# 跳跃地图模板见 docs/JUMP_MAP_TEMPLATE.md：28,800px / 46.45s@620）。
	#
	# 飞镖地图在第 6 轮被改成**固定人工编排**的 8 段结构，
	# 总长从 34,400px 收到 8,035px（20.1s@400 / 13.0s@620）。
	# 这是有意的设计（朋友的规格：整齐、连续、可读、有明确节奏），
	# 所以 45s@620 这条已经不再适用。
	#
	# 改法：把下限从「防太短」改成「防截断」—— 8 段全部在位就不会低于 16s@400。
	# 上限 90 秒守卫保留不变。
	var normal_seconds: float = module.total_length / Motion.RUN_SPEED
	_check(normal_seconds >= 16.0, "飞镖地图被截断：常速 %.1fs < 16s" % normal_seconds)
	_check(normal_seconds <= 90.0, "常速模块超过90秒（%.1fs）" % normal_seconds)
	var event_total := 0
	# 动作句计数：同一个 beat 上的多枚飞镖（上下门 / 竖排）算一次遭遇。
	# 旧实现按「飞镖事件数」断言 >200，那个阈值是按飞镖墙标定的
	# （一堵墙 = 11 行 = 11 个事件）。改用动作句后每枚飞镖都是独立遭遇，
	# 事件数与遭遇数不再等价，因此这里同时统计两者。
	var beat_total := 0
	var wave_total := 0
	for section in module.sections:
		_check(section.all_issues().is_empty(), "Wave 编译失败")
		for runner in section.runners:
			_check(runner.plan.get("distance_driven", false), "正式飞镖 Wave 未使用距离节拍")
			_check(runner.event_index == 0, "预编排应在起飞前完成")
			wave_total += 1
			event_total += runner.plan.events.size()
			var beats := {}
			for event in runner.plan.events:
				beats[snappedf(event.spawn_time, 0.001)] = true
			beat_total += beats.size()
	# 固定编排是 8 段 / 43 枚。留出余量，只防「少了一大段」。
	_check(wave_total >= 8, "完整飞镖地图缺少 Wave（只有 %d 段）" % wave_total)
	_check(event_total >= 40, "完整飞镖地图缺少持续波次（飞镖事件 %d）" % event_total)
	_check(beat_total >= 40, "完整飞镖地图缺少持续遭遇（节拍 %d）" % beat_total)
	repeats.free()

	var info: Dictionary = module.debug_info()
	print("map         = %s (%s)" % [info.map, info.map_id])
	print("sections    = %d" % module.sections.size())
	for index in module.sections.size():
		var section = module.sections[index]
		print("  %d. %s: %.0f px" % [index + 1, module.module_data.sections[index].display_name, section.section_length])
	print("total       = %.0f px" % module.total_length)
	print("duration    = %.1f s at %.0f px/s" % [module.total_length / Motion.RUN_SPEED, Motion.RUN_SPEED])
	print("module exit = %.0f" % module.get_node("Exit").position.x)

	world.queue_free()
	await process_frame
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func _finish() -> void:
	if failures.is_empty():
		print("Dart Map Module regression passed.")
		quit(0)
	else:
		quit(1)
