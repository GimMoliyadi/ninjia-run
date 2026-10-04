extends SceneTree

# 接线验证：确认 segment_darts 真的通过 PatternSection / PatternCompiler /
# PatternRunner 生成障碍，并且 Entry / Exit 与 Section 长度一致。

const Motion := preload("res://patterns/player_motion_profile.gd")

var failures := PackedStringArray()

func _init() -> void:
	await _run()

func _run() -> void:
	var world: Node = load("res://test_world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame

	var game = world
	var segment: Node = load("res://scenes/segment_darts.tscn").instantiate()
	# game.gd 通过 route 生成；这里直接检查它生成出来的 DARTS chunk。
	var found: Node = null
	await _advance_frames(30)
	for chunk in game.active_chunks:
		if chunk.get_script() == load("res://components/dart_encounter.gd"):
			found = chunk
			break

	if found == null:
		# 路线还没走到 DARTS：手动生成一个。
		segment.name = "SegmentDarts"
		root.add_child(segment)
		await process_frame
		found = segment
		_check_direct(found)
	else:
		_check_direct(found)

	world.queue_free()
	segment.free()
	await process_frame
	_finish()

func _check_direct(chunk: Node) -> void:
	var info: Dictionary = chunk.debug_info()
	_check(not info.is_empty(), "debug_info() 返回空")
	if info.is_empty():
		return
	print("segment    = %s" % info.segment)
	print("section    = %s" % info.section)
	print("sequence   = %s" % info.sequence)
	print("length     = %.0f px" % info.total_length)
	print("issues     = %d" % info.issues.size())
	for issue in info.issues:
		print("   ISSUE: %s" % issue)

	var entry: Node2D = chunk.get_node("Entry")
	var exit: Node2D = chunk.get_node("Exit")
	var section: Node2D = chunk.get_node("Section")
	var expected: float = float(section.position.x) + float(info.total_length)
	_check(absf(exit.position.x - expected) < 1.0,
		"Exit 位置未落在 Section 真实结尾: exit=%.0f expected=%.0f" % [exit.position.x, expected])
	print("entry.x    = %.0f" % entry.position.x)
	print("exit.x     = %.0f (expected %.0f)" % [exit.position.x, expected])

	# PatternRunner 必须真实存在并已挂上 plan。
	# 期望值从数据推导，而不是写死数字：每个非 Recovery 的 entry 都要有一个 Runner。
	# 这样以后调整 Dart_Introduction 的编排时，这个接线测试不需要跟着改常量。
	var section_data: PatternSectionData = section.data
	var expected_runners := 0
	for section_entry in section_data.entries:
		if section_entry is ObstaclePatternData:
			expected_runners += 1
	_check(section.runners.size() == expected_runners,
		"期望 %d 个 PatternRunner，实际 %d" % [expected_runners, section.runners.size()])
	print("runners    = %d" % section.runners.size())
	var total_events := 0
	for runner in section.runners:
		_check(not runner.plan.is_empty(), "%s 的 plan 为空" % runner.name)
		_check(runner.spawned_count == 0, "%s build 后不应已生成障碍" % runner.name)
		total_events += runner.plan.events.size()
	print("events     = %d" % total_events)

	# 地面必须覆盖整个 Section。
	var ground_width := 0.0
	for child in section.get_children():
		if child is StaticBody2D:
			for sub in child.get_children():
				if sub is CollisionShape2D and sub.shape is RectangleShape2D:
					ground_width += sub.shape.size.x
	print("ground     = %.0f px (section %.0f px)" % [ground_width, info.total_length])
	_check(ground_width >= info.total_length - 1.0,
		"地面未覆盖整个 Section: %.0f < %.0f" % [ground_width, info.total_length])

func _advance_frames(count: int) -> void:
	for i in count:
		await process_frame

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS  ok")
	else:
		print("  FAIL  ", message)
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("\nDart section wiring passed: pattern chain, Entry/Exit, ground coverage.")
		quit(0)
	else:
		print("\nDart section wiring FAILED (%d):" % failures.size())
		for f in failures:
			print("  - ", f)
		quit(1)
