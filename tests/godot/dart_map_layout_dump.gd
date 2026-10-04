# 飞镖地图布局转储 —— 诊断工具（不是断言型测试，永远退出 0）。
#
# 用法：
#   Godot --headless --path . --fixed-fps 60 --script res://tests/godot/dart_map_layout_dump.gd
#
# 打印每个 Section / 每个 Wave 的：
#   * world_start（世界 X）、duration、飞镖枚数、编译期 issues
#   * 每枚飞镖的相遇点 X 与高度（h）
#   * 每条接缝的 gap_px 与 band（CONTINUOUS / CLEAN / FREE / DEAD_ZONE）
# 最后汇总全图 TOTAL darts 与 ACT 衔接体检（issues / notes / tightest）。
#
# 2026-09-18 用它在 §0.1 的覆盖带模型下调参：把「写下的间距」与
# 「屏幕上的间距」对齐后，靠这里的 seam band 找出死区接缝再改顺序。
extends SceneTree

const DartEncounter := preload("res://components/dart_encounter.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")

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
		print("no module")
		quit(1)
		return
	var approach := Motion.jump_time() * 2.0
	var darts := 0
	for section_index in module.sections.size():
		var section = module.sections[section_index]
		var section_data = module.module_data.sections[section_index]
		print("")
		print("=== Section %d  %s  world_start=%.0f  len=%.0f ===" % [
			section_index + 1, section_data.display_name, section.position.x, section.section_length])
		var wave_x: float = section.position.x
		for runner_index in section.runners.size():
			var runner = section.runners[runner_index]
			var plan: Dictionary = runner.plan
			var label := "?"
			if runner_index < section_data.entries.size():
				label = section_data.entries[runner_index].display_name
			print("  -- %-24s world_start=%7.0f  dur=%.3f  darts=%d  %s" % [
				label, wave_x, plan.get("duration", 0.0), plan.events.size(),
				"" if plan.issues.is_empty() else str(plan.issues)])
			var hits: Array = []
			for event in plan.events:
				var beat: float = event.spawn_time + approach
				hits.append({"x": wave_x + beat * Motion.RUN_SPEED, "h": -event.position_offset.y})
			hits.sort_custom(func(a, b): return a.x < b.x)
			var line := ""
			for hit in hits:
				darts += 1
				line += "%.0f:h%.0f  " % [hit.x, hit.h]
			print("       " + line)
			for seam in plan.get("seams", []):
				print("       seam %-16s -> %-16s gap=%6.1fpx  band=%s" % [
					seam.from, seam.to, seam.gap_px, seam.band])
			wave_x += plan.get("length", 0.0)
	print("")
	print("TOTAL darts=%d" % darts)
	var report: Dictionary = module.act_report
	print("ACT darts=%d  issues=%d  notes=%d  tightest=%s" % [
		report.get("acts", 0), report.get("issues", []).size(),
		report.get("notes", []).size(), str(report.get("tightest", 0.0))])
	for issue in report.get("issues", []):
		print("  ISSUE %d 枚从 x=%.0f 起跨 %.0fpx (limit %.0f)" % [
			issue.count, issue.first_x, issue.span_px, issue.limit_px])
	for note in report.get("notes", []):
		print("  NOTE  " + str(note))
	world.queue_free()
	await process_frame
	quit()
