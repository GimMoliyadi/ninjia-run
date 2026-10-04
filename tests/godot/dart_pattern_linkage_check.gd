extends SceneTree

# 飞镖 Pattern 衔接回归。
#
# 只做一件事：验证每一个 Wave 里每一对相邻 Pattern 的「间隔」都不小于衔接模型
# 算出的理论最小值 —— 也就是「上一个 Pattern 落地恢复 + 下一个 Pattern 预备动作 + 余量」。
#
# 模型出处：patterns/dart_pattern_library.gd 的 entry_need / exit_settle / link_gap。
# 间隔不够 = 玩家会被上一句的轨迹直接送进下一句的飞镖里。

const DartEncounter := preload("res://components/dart_encounter.gd")
const Library := preload("res://patterns/dart_pattern_library.gd")
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
	if module == null:
		print("FAIL: 没有找到 Dart_Map_A")
		quit(1)
		return

	var checked := 0
	var tightest := INF
	var tightest_label := ""
	for section_index in module.sections.size():
		var section = module.sections[section_index]
		for runner in section.runners:
			var plan: Dictionary = runner.plan
			_check(plan.get("issues", []).is_empty(),
				"%s 编译失败：%s" % [plan.get("display_name", "?"), str(plan.get("issues", []))])
			var arranged: Array = plan.get("patterns_arranged", [])
			if arranged.is_empty():
				continue
			print("")
			print("── %s（%d 个 Pattern）" % [plan.get("display_name", "?"), arranged.size()])
			for pattern in arranged:
				var info := Library.describe(pattern)
				print("   %-10s @%6.2fs  %d 拍 / %d 镖" % [
					info.kind, info.beat, info.volleys, info.darts])
			for row in Library.link_report(arranged):
				checked += 1
				var label := "%s → %s" % [row.from, row.to]
				print("   衔接 %-22s 出口 %-6s(%+.2f) → 入口 %-11s(%+.2f)  模型 %.2f  实际 %.2f  余量 %+.2f" % [
					label, _exit_name(row.exit), row.exit,
					row.entry_need, row.entry_lead,
					row.model, row.actual, row.slack])
				if row.slack < tightest:
					tightest = row.slack
					tightest_label = label
				_check(row.slack >= -0.001,
					"%s 间隔不足：实际 %.2f < 模型 %.2f（玩家会被上一句的轨迹送进下一句）" % [
						label, row.actual, row.model])

	print("")
	print("衔接检查：%d 处，最紧的一处是 %s（余量 %+.2f）" % [checked, tightest_label, tightest])
	print("地图总长 %.0f px / %.1f s" % [module.total_length, module.total_length / Motion.RUN_SPEED])

	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("Dart Pattern 衔接检查通过。")
		quit(0)
	else:
		for failure in failures:
			print("FAIL: ", failure)
		quit(1)

func _exit_name(settle: float) -> String:
	if settle <= 0.06:
		return "GROUND"
	if settle < 0.60:
		return "AIR"
	return "GATE"

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
