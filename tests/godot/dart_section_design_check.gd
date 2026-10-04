extends SceneTree

# Dart_Introduction 设计检查工具。
#
# 它回答三个问题：
#   1. 每个场景/Pattern 编译出来多长、有多少事件、最小反应窗口是多久；
#   2. 玩家的「有效操作时间」与「纯跑动空白」各占多少；
#   3. 相邻障碍之间是否构成连续动作（时间间隔是否落在一个跳跃周期附近）。
#
# 这是设计计算，不进入正式游戏。
# 运行：
#   Godot --headless --path . --fixed-fps 60 --script tests/godot/dart_section_design_check.gd

const Compiler := preload("res://patterns/pattern_compiler.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")
const SECTION_PATH := "res://patterns/library/Dart_Introduction.tres"
const DART_LIFETIME := 3.5

func _init() -> void:
	var data: PatternSectionData = load(SECTION_PATH)
	if data == null:
		printerr("找不到 %s" % SECTION_PATH)
		quit(1)
		return

	print("=== %s (%s) ===" % [data.section_name, data.display_name])
	print("跑速 %.0f px/s | 单跳高度 %.1f | 单跳滞空 %.3fs | 单跳跨度 %.1f px | 二段总高 %.1f"
		% [Motion.RUN_SPEED, Motion.jump_height(), Motion.jump_time(),
		   Motion.RUN_SPEED * Motion.jump_time(), Motion.double_jump_height()])
	print("")
	print("entries = %d / stages = %d" % [data.entries.size(), data.stages.size()])

	var recovery := RecoverySection.new()
	var total := 0.0
	var total_dead := 0.0
	var total_recovery := 0.0
	var total_issues := 0
	var cursor := 0.0

	print("")
	print("%-4s %-16s %-24s %-5s %8s %7s %9s %8s %7s" % [
		"#", "stage", "display", "tmpl", "len", "events", "min_react", "dead", "issues"
	])
	for index in data.entries.size():
		var entry: Resource = data.entries[index]
		var stage: String = data.stage_for(index)
		if entry is RecoverySection:
			var d: float = entry.distance(Motion.RUN_SPEED)
			print("%-4d %-16s %-24s %-5s %8.0f %7s %9s %8s %7s" % [
				index, stage, entry.recovery_label if not entry.recovery_label.is_empty() else "喘息",
				"-", d, "-", "-", "(留白)", "0"
			])
			if entry.coin_count > 0:
				print("     金币 ×%d（低压力路径引导）" % entry.coin_count)
			total += d
			total_recovery += d
			cursor += d
			continue

		var pattern: ObstaclePatternData = entry
		var plan := Compiler.compile(pattern, pattern.difficulty, Modifier.Kind.NORMAL, recovery)
		var display: String = pattern.display_name if not pattern.display_name.is_empty() else pattern.pattern_name
		var reaction := _min_reaction(plan)
		var dead := _tail_dead(plan)
		total += plan.length
		total_dead += dead
		total_issues += plan.issues.size()
		print("%-4d %-16s %-24s %-5s %8.0f %7d %8.3fs %7.2fs %7d" % [
			index, stage, display, pattern.template,
			plan.length, plan.events.size(), reaction, dead / Motion.RUN_SPEED, plan.issues.size()
		])
		for issue in plan.issues:
			print("     ISSUE: %s" % issue)
		cursor += plan.length

	print("")
	print("总长            %.0f px  = %.1f s" % [total, total / Motion.RUN_SPEED])
	print("其中 Recovery   %.0f px  = %.1f s（设计留白）" % [total_recovery, total_recovery / Motion.RUN_SPEED])
	print("Pattern 尾段空白 %.0f px  = %.1f s（无意义空白，应尽量压掉）" % [total_dead, total_dead / Motion.RUN_SPEED])
	print("编译器 issues   %d" % total_issues)
	print("")

	_report_sentences(data, recovery)
	print("")
	total_issues += _validate_wave_design(data, recovery)
	var max_quiet: float = _max_quiet_time(data, recovery)
	total_issues += _expect(max_quiet <= 1.9, "关卡主体最大无威胁间隔不得超过 1.9s，实际 %.2fs" % max_quiet)
	_report_summary(total, total_dead, max_quiet)

	quit(0 if total_issues == 0 else 1)


# 相邻障碍之间是否构成连续动作。
#
# 只检查「动作句」模板（同一 Pattern 内有多个独立飞镖事件，且它们不是同时出现）。
# 飞镖墙的若干枚飞镖是同一瞬间的同一堵墙，属于一个障碍，不参与此判据。
# 判据：两枚飞镖的「相遇时刻」之差落在一个单跳滞空时间附近（<= 1.5 倍）。
func _report_sentences(data: PatternSectionData, recovery: RecoverySection) -> void:
	print("=== 连续动作检查（同一次操作是否串起多个障碍）===")
	var jump_time: float = Motion.jump_time()
	for index in data.entries.size():
		var entry: Resource = data.entries[index]
		if not (entry is ObstaclePatternData):
			continue
		var pattern: ObstaclePatternData = entry
		if pattern.template != "P30":
			continue
		var plan := Compiler.compile(pattern, pattern.difficulty, Modifier.Kind.NORMAL, recovery)
		if plan.events.size() < 2:
			continue
		var display: String = pattern.display_name if not pattern.display_name.is_empty() else pattern.pattern_name
		print("· %s" % display)
		var previous := -1.0
		for event in plan.events:
			# 相遇时刻 = spawn_time + 反应距离
			var encounter: float = event.spawn_time + (event.position_offset.x - event.spawn_time * Motion.RUN_SPEED) / maxf(1.0, Motion.RUN_SPEED)
			var height: float = -event.position_offset.y
			var verdict := ""
			if previous >= 0.0:
				var gap: float = encounter - previous
				if gap <= jump_time * 1.5:
					verdict = "  <- 间隔 %.2fs，在同一个跳跃周期内（连续动作）" % gap
				else:
					verdict = "  <- 间隔 %.2fs，超过跳跃周期 %.2fs（退化为独立题目）" % [gap, jump_time]
			print("     相遇 %.2fs  高度 %.0f%s" % [encounter, height, verdict])
			previous = encounter


func _validate_wave_design(data: PatternSectionData, recovery: RecoverySection) -> int:
	print("=== 飞镖潮结构回归 ===")
	var issues := 0
	var expected_stages := PackedStringArray([
		"Wave 1：单飞镖潮", "Wave 2：单飞镖加强", "短喘息",
		"Wave 3：成排飞镖潮", "Wave 4：成排飞镖加强",
		"Wave 5：混合高潮", "短出口",
	])
	issues += _expect(data.display_name == "飞镖关", "Section 显示名必须是 飞镖关")
	issues += _expect(data.stages == expected_stages, "Wave 名称或顺序不符")
	issues += _expect(data.stage_entries == PackedInt32Array([1, 1, 1, 1, 1, 4, 1]), "Wave 与 entries 映射不符")
	issues += _expect(data.entries.size() == 10, "DARTS 应由 10 个 entry 组成")

	var expected_templates := ["P30", "P30", "Recovery", "P17", "P17", "P30", "P17", "P30", "P14", "Recovery"]
	var expected_counts := [5, 6, 0, 4, 6, 3, 3, 2, 1, 0]
	for index in data.entries.size():
		var entry: Resource = data.entries[index]
		if entry is RecoverySection:
			issues += _expect(expected_templates[index] == "Recovery", "entry %d 应为 Recovery" % index)
			continue
		var pattern: ObstaclePatternData = entry
		issues += _expect(pattern.template == expected_templates[index], "entry %d 模板不符" % index)
		var plan := Compiler.compile(pattern, pattern.difficulty, Modifier.Kind.NORMAL, recovery)
		var actual_count: int = plan.gaps.size() if pattern.template in ["P14", "P17"] else plan.events.size()
		issues += _expect(actual_count == expected_counts[index], "%s 障碍数量应为 %d，实际 %d" % [pattern.display_name, expected_counts[index], actual_count])

	var wave_1: ObstaclePatternData = data.entries[0]
	var wave_2: ObstaclePatternData = data.entries[1]
	issues += _expect(_intervals_match(wave_1, [1.0, 0.95, 0.85, 0.75]), "Wave 1 节奏必须逐步收紧")
	issues += _expect(_intervals_match(wave_2, [0.78, 0.72, 0.66, 0.6, 0.56]), "Wave 2 节奏必须比 Wave 1 更紧")
	issues += _expect((data.entries[2] as RecoverySection).duration == 0.7, "短喘息必须为 0.7s")
	issues += _expect((data.entries[9] as RecoverySection).duration == 0.8, "短出口必须为 0.8s")
	print("飞镖潮结构问题：%d" % issues)
	return issues


func _intervals_match(pattern: ObstaclePatternData, expected: Array) -> bool:
	var darts: Array = pattern.parameters.get("darts", [])
	if darts.size() - 1 != expected.size():
		return false
	for index in range(1, darts.size()):
		var actual: float = float(darts[index].delay) - float(darts[index - 1].delay)
		if not is_equal_approx(actual, float(expected[index - 1])):
			return false
	return true


func _expect(condition: bool, message: String) -> int:
	if condition:
		return 0
	printerr("WAVE ISSUE: %s" % message)
	return 1


func _max_quiet_time(data: PatternSectionData, recovery: RecoverySection) -> float:
	var encounters: Array[float] = []
	var cursor := 0.0
	for entry in data.entries:
		if entry is RecoverySection:
			cursor += entry.distance(Motion.RUN_SPEED)
			continue
		var pattern: ObstaclePatternData = entry
		var plan := Compiler.compile(pattern, pattern.difficulty, Modifier.Kind.NORMAL, recovery)
		for event in plan.events:
			if event.speed <= 0.0:
				continue
			var distance: float = event.position_offset.x - event.spawn_time * Motion.RUN_SPEED
			var closing: float = Motion.RUN_SPEED - event.speed * event.direction.normalized().x
			encounters.append(0.9 + cursor / Motion.RUN_SPEED + event.spawn_time + distance / closing)
		cursor += float(plan.length)
	encounters.sort()
	var previous := 0.0
	var maximum := 0.0
	for encounter in encounters:
		if encounter - previous > 1.5:
			print("静默区间 %.2f–%.2f = %.2fs" % [previous, encounter, encounter - previous])
		maximum = maxf(maximum, encounter - previous)
		previous = encounter
	maximum = maxf(maximum, 0.9 + cursor / Motion.RUN_SPEED - previous)
	return maximum


func _report_summary(total: float, total_dead: float, max_quiet: float) -> void:
	print("")
	print("=== 节奏与留白总览 ===")
	print("原始版本（重做前）：14140 px = 35.4 s，Pattern 尾段空白 5680 px = 14.2 s")
	print("当前版本（重做后）：%.0f px = %.1f s，Pattern 尾段空白 %.0f px = %.1f s"
		% [total, total / Motion.RUN_SPEED, total_dead, total_dead / Motion.RUN_SPEED])
	print("最大连续无威胁间隔：%.2f s（含 0.9s 入口与设计 Recovery）" % max_quiet)
	print("压缩掉的无意义空白：%.0f px = %.1f s" % [5680.0 - total_dead, (5680.0 - total_dead) / Motion.RUN_SPEED])
	print("")
# Pattern 尾部「最后一个威胁结束」到「Pattern 结束」之间的空白。
func _tail_dead(plan: Dictionary) -> float:
	if plan.events.is_empty():
		return float(plan.length)
	var last_encounter := 0.0
	for event in plan.events:
		var encounter: float = event.spawn_time + (event.position_offset.x - event.spawn_time * Motion.RUN_SPEED) / maxf(1.0, Motion.RUN_SPEED)
		last_encounter = maxf(last_encounter, encounter)
	# 威胁结束后玩家还要跑过飞镖的生命周期尾巴才算真正结束。
	var cleared: float = (last_encounter + 0.6) * Motion.RUN_SPEED
	return maxf(0.0, float(plan.length) - cleared)


func _min_reaction(plan: Dictionary) -> float:
	var best := INF
	for event in plan.events:
		if event.speed <= 0:
			continue
		var distance: float = event.position_offset.x - event.spawn_time * Motion.RUN_SPEED
		var closing: float = Motion.RUN_SPEED - event.speed * event.direction.normalized().x
		if closing <= 0:
			continue
		best = minf(best, distance / closing)
	return best
