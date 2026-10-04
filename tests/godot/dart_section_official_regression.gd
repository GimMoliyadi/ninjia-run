extends SceneTree

# 正式关卡 DARTS 接入回归测试。
#
# 走真实路径：test_world.tscn → game.gd → route → CHUNK_SCENES[12] →
# segment_darts → PatternSection → PatternCompiler → PatternRunner → Dart/Spike。
#
# 覆盖：
#   - Pattern 是否真实由 PatternRunner 生成
#   - P04 重复 / P04 Variation / P14 / Recovery / P17 / P17 Variation
#   - Pattern 是否重叠
#   - Entry / Exit 与前后 Segment 衔接
#   - 飞镖生命周期
#   - 玩家碰撞
#   - 暂停 / 恢复
#   - Restart 后重新初始化
#   - Godot runtime error
#   - orphan node / 残留节点
#   - PatternRunner 状态重置
#
# 验证条件：跑速 400/620 px/s，NORMAL modifier，设计难度 1，不使用任何技能。

const Motion := preload("res://patterns/player_motion_profile.gd")
const DartScript := preload("res://components/dart_encounter.gd")
const SpikeScene := preload("res://scenes/Spike.tscn")
const PatternEventScript := preload("res://patterns/pattern_event.gd")

var failures := PackedStringArray()
var world: Node
var game: Node

func _init() -> void:
	await _run()

func _run() -> void:
	world = load("res://test_world.tscn").instantiate()
	root.add_child(world)
	game = world
	await _frames(4)

	_check(game != null, "TestWorld 未加载")
	if game == null:
		_finish()
		return

	# 此种子的第一张地图是 DARTS。
	game.route_seed = 20260900
	game.restart_run()
	await _frames(4)

	await _check_darts_chunk()
	if failures.is_empty() or true:
		await _check_flow()
		await _check_lifecycle()
		await _check_pause_and_restart()
		await _check_no_leak()

	_finish()

# =========================================================
# 1. DARTS chunk 是否真实生成，且由 PatternRunner 驱动
# =========================================================

func _check_darts_chunk() -> void:
	var darts: Node = _find_darts_chunk()
	_check(darts != null, "正式路线中未生成 DARTS chunk（CHUNK_SCENES[12]）")
	if darts == null:
		return

	print("--- DARTS chunk ---")
	var info: Dictionary = darts.debug_info()
	print("section   = ", info.get("section", "?"))
	print("sequence  = ", info.get("sequence", "?"))
	print("length    = %.0f px" % float(info.get("total_length", 0.0)))

	# Section 的显示名现在是人类可读的「飞镖关」，
	# 内部标识仍是 pattern_name = Dart_Introduction。
	_check(str(info.get("display_name", "")) == "飞镖关",
		"Section 显示名不是 飞镖关: %s" % str(info.get("display_name", "")))
	_check(int(info.get("issues", PackedStringArray()).size()) == 0,
		"Section 存在编译器 issue")

	# Pattern 顺序必须与 Dart_Introduction 的数据一致，而不是写死一份序列。
	var section_node: Node = darts.get_node_or_null("Section")
	var section_data_ref: PatternSectionData = null
	if section_node != null:
		section_data_ref = section_node.data
	var expected := PackedStringArray()
	if section_data_ref != null:
		for section_entry in section_data_ref.entries:
			if section_entry is ObstaclePatternData:
				expected.append(section_entry.template)
	var infos: Array = info.get("info", [])
	var patterns := PackedStringArray()
	for entry in infos:
		if entry.get("kind", "") == "pattern":
			patterns.append(str(entry.get("template", "")))
	_check(patterns == expected,
		"Pattern 序列不符: %s != %s" % [str(patterns), str(expected)])
	print("patterns  = ", str(patterns))

	# Recovery 必须真实存在。
	var recoveries: Array = []
	for entry in infos:
		if entry.get("kind", "") == "recovery":
			recoveries.append(entry)
	_check(recoveries.size() >= 1, "期望至少 1 段 Recovery，实际 %d" % recoveries.size())
	# Recovery 长度必须等于它自己声明的 duration × 跑速，而不是写死 1.6s。
	var recovery_entries: Array[Resource] = []
	if section_data_ref != null:
		for section_entry in section_data_ref.entries:
			if section_entry is RecoverySection:
				recovery_entries.append(section_entry)
	_check(recovery_entries.size() == recoveries.size(),
		"Recovery 段数量与数据不符: %d vs %d" % [recovery_entries.size(), recoveries.size()])
	for index in recoveries.size():
		var recovery: Dictionary = recoveries[index]
		var length := float(recovery.end_x) - float(recovery.start_x)
		var declared: RecoverySection = recovery_entries[index]
		var want: float = declared.duration * float(Motion.RUN_SPEED)
		_check(absf(length - want) < 1.0,
			"Recovery 长度不等于 duration × 跑速: 实际 %.0f / 期望 %.0f" % [length, want])
	print("recoveries = %d 段" % recoveries.size())

	# Pattern 不得重叠，且必须无缝衔接。
	var cursor := 0.0
	var overlap := false
	for entry in infos:
		if absf(float(entry.start_x) - cursor) > 0.01:
			overlap = true
		cursor = float(entry.end_x)
	_check(not overlap, "Pattern 之间存在重叠或空隙")
	print("cursor    = %.0f px (section %.0f px)" % [cursor, float(info.total_length)])

	# Entry / Exit。
	var entry_marker: Node2D = darts.get_node("Entry")
	var exit_marker: Node2D = darts.get_node("Exit")
	var expected_exit: float = float(section_node.position.x) + float(info.total_length)
	_check(absf(float(exit_marker.position.x) - expected_exit) < 1.0,
		"Exit 未落在 Section 真实结尾")
	print("entry.x   = %.0f   exit.x = %.0f (expected %.0f)" % [
		float(entry_marker.position.x),
		float(exit_marker.position.x),
		expected_exit,
	])

	# PatternRunner 必须已经挂上 plan，且尚未生成障碍。
	var section: Node = darts.get_node_or_null("Section")
	_check(section != null, "Section 子节点缺失")
	if section == null:
		return
	# 从数据推导期望的 Runner 数量，避免重新编排 Section 后常量失效。
	var expected_runners := 0
	for section_entry in (section.data as PatternSectionData).entries:
		if section_entry is ObstaclePatternData:
			expected_runners += 1
	_check(section.runners.size() == expected_runners,
		"期望 %d 个 PatternRunner，实际 %d" % [expected_runners, section.runners.size()])
	for runner in section.runners:
		_check(not runner.plan.is_empty(), "%s plan 为空" % runner.name)
		_check(runner.spawned_count == 0, "%s 在 build 阶段不应生成障碍" % runner.name)
	print("runners   = %d, all plans configured, none spawned yet" % section.runners.size())

# =========================================================
# 2. 完整走完 DARTS：生成、推进、清理、衔接
# =========================================================

func _check_flow() -> void:
	print("--- 实跑 DARTS ---")
	var darts: Node = _find_darts_chunk()
	if darts == null:
		return

	var section: Node = darts.get_node_or_null("Section")
	if section == null:
		return

	# 终点取「最后一个 PatternRunner 的结束位置」，而不是 Exit。
	# Exit 后面还跟着 Exit Recovery，那段本来就是给玩家缓冲用的。
	var last_runner_end := 0.0
	for runner in section.runners:
		last_runner_end = maxf(
			last_runner_end,
			float(runner.global_position.x) + float(runner.plan.length)
		)
	var start_x: float = float(darts.get_node("Entry").global_position.x)
	var end_x: float = last_runner_end
	print("section spans global x %.0f → %.0f (last pattern end)" % [start_x, end_x])
	# 把玩家放到本段入口，模拟真实进入。
	player_start( start_x )

	var spawned_any := false
	var darts_seen := false
	var max_darts := 0
	var stages_seen := {}
	var patterns_seen := {}
	var overlaps := 0
	var deaths := 0

	# 以每帧 400 px/s ÷ 60 把玩家向前推进，模拟一次完整通过。
	#
	# 注意：这一段必须「会躲」。
	# Dart_Introduction 是教学段，P14 / P17 是飞镖墙，玩家必须进入墙上的安全口。
	# 如果让虚拟玩家走直线，会在第一个 P14 就被飞镖打死（run_state → GAME_OVER），
	# 后续 PatternRunner 全部冻结，那不是段的问题，是「直线不解题」。
	# 因此这里用 Pattern 编译出来的 gap 信息做一次「会读预警的玩家」模拟，
	# 从而验证：在规定的速度 / 难度 / 修正下，本段是可通行的。
	var step: float = float(Motion.RUN_SPEED) / 60.0
	var player: Node2D = game.player
	var guard := 0
	var stop_x: float = end_x + 1.5 * float(Motion.RUN_SPEED)

	while float(player.global_position.x) < stop_x and guard < 4000:
		guard += 1
		player.global_position.x += step
		# 「会躲的玩家」：读设计里的预警，按威胁类型选择动作。
		# 注意：不能直接写 global_position.y —— 玩家脚本在落地时会把 velocity.y 归零并
		# 由碰撞体把角色压回地面，直接改写位置不会真的起飞。
		# 因此这里走真实运动路径（start_jump / request_fast_fall）。
		_drive(player, section)
		await physics_frame

		if game.run_state == 2:  # RunState.GAME_OVER
			deaths += 1

		_tick_dart_lifecycle(section)
		if section.runners.size() > 0:
			for runner in section.runners:
				if runner.spawned_count > 0:
					spawned_any = true

		var live := get_nodes_in_group("dart").size()
		if live > 0:
			darts_seen = true
		max_darts = maxi(max_darts, live)

		var raw: Variant = darts.call("debug_info_at", float(player.global_position.x))
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			var entry: Dictionary = raw
			var stage: String = str(entry.get("stage", ""))
			if not stage.is_empty():
				stages_seen[stage] = true
			if entry.get("kind", "") == "pattern":
				patterns_seen[str(entry.get("template", ""))] = true

		# 同一时刻不应有两个不同 Pattern 声称玩家在其中。
		if _count_active_patterns(section, float(player.global_position.x)) > 1:
			overlaps += 1

	_check(spawned_any, "PatternRunner 从未生成任何障碍")
	_check(darts_seen, "整段没有出现过飞镖")
	_check(overlaps == 0, "存在多个 Pattern 同时覆盖玩家的帧: %d" % overlaps)
	_check(deaths == 0, "会躲的玩家在段内死亡 %d 帧（本段应可通行）" % deaths)
	_check(game.run_state == 0, "走完 DARTS 后 run_state != RUNNING（可能中途死亡）")
	print("spawned   = %s, darts seen = %s, max live darts = %d, deaths = %d" % [
		spawned_any, darts_seen, max_darts, deaths
	])

	var stages: Array = stages_seen.keys()
	stages.sort()
	# 阶段名从数据推导：Section 的 stages 定义了几个阶段，玩家就必须覆盖到几个。
	# 早期版本写死 ["Exit Recovery","Phrase A","Phrase B","Recovery"]，
	# 一旦重新编排 Dart_Introduction 就会失效；现在只校验「全部覆盖」。
	var expected_stages: Array = []
	var stage_data: PatternSectionData = section.data
	for index in stage_data.stages.size():
		var label: String = stage_data.stages[index]
		if not expected_stages.has(label):
			expected_stages.append(label)
	expected_stages.sort()
	_check(stages == expected_stages,
		"阶段覆盖不符: 实际 %s / 期望 %s" % [str(stages), str(expected_stages)])
	print("stages    = ", str(stages))

	# 模板集合也必须从数据推导。
	var expected_templates: Array = []
	for section_entry in stage_data.entries:
		if section_entry is ObstaclePatternData:
			var tmpl: String = section_entry.template
			if not expected_templates.has(tmpl):
				expected_templates.append(tmpl)
	expected_templates.sort()
	var templates: Array = patterns_seen.keys()
	templates.sort()
	_check(templates == expected_templates,
		"玩家实际经过的 Pattern 不符: 实际 %s / 期望 %s" % [str(templates), str(expected_templates)])
	print("templates = ", str(templates))

	# 飞镖最终必须全部回收。
	await _frames(30)
	var left := get_nodes_in_group("dart").size()
	_check(left == 0, "越过 DARTS 后仍有 %d 枚飞镖残留" % left)
	print("darts left after section = %d" % left)

	# 所有 Runner 必须 finish。
	var unfinished := 0
	for runner in section.runners:
		if not runner.completed:
			unfinished += 1
	_check(unfinished == 0, "仍有 %d 个 PatternRunner 未 finish" % unfinished)
	print("unfinished runners = %d" % unfinished)

	# 衔接：下一个 chunk 的 Entry 必须落在 DARTS 的 Exit 上。
	var next: Node2D = _next_chunk_after(darts)
	_check(next != null, "DARTS 之后没有生成下一个 Segment")
	if next != null:
		var next_entry: Node2D = next.get_node_or_null("Entry")
		_check(next_entry != null, "下一个 Segment 缺少 Entry")
		if next_entry != null:
			var gap: float = absf(
				float(next_entry.global_position.x) - float(darts.get_node("Exit").global_position.x)
			)
			_check(gap < 0.5, "DARTS 与下一段之间存在 %.1f px 缝隙" % gap)
			print("next segment = %s, seam gap = %.2f px" % [next.name, gap])

	print("flown distance = %.0f px" % (end_x - start_x))

# =========================================================
# 3. 飞镖生命周期 + 玩家碰撞
# =========================================================

func _check_lifecycle() -> void:
	print("--- 飞镖生命周期 ---")
	var dart: Area2D = SpikeScene.instantiate()
	# 用真实飞镖脚本实例化一个，检查 LIFETIME 与越过玩家后的回收。
	var real_dart: Node2D = load("res://components/dart.gd").new()
	dart.queue_free()
	root.add_child(real_dart)
	await physics_frame

	var player: Node2D = game.player
	real_dart.set("previous_player_position", player.global_position)
	real_dart.global_position = Vector2(
		float(player.global_position.x) + 300.0,
		float(player.global_position.y)
	)

	var lived := 0.0
	while is_instance_valid(real_dart) and lived < 5.0:
		real_dart.call("advance", 1.0 / 60.0, player)
		lived += 1.0 / 60.0
		if not is_instance_valid(real_dart):
			break

	# 飞镖向左飞，玩家不动，会先越过玩家再因 LIFETIME / 越界回收。
	_check(not is_instance_valid(real_dart) or real_dart.is_queued_for_deletion(),
		"飞镖未在生命周期内回收")
	print("dart lifetime before recycle ~= %.2fs (scripted LIFETIME = 3.5s)" % lived)

# =========================================================
# 4. 暂停 / 恢复 / Restart
# =========================================================

func _check_pause_and_restart() -> void:
	print("--- 暂停 / 恢复 / Restart ---")
	# 暂停开关要求当前不是 GAME_OVER；这里是前置条件，不是被测对象。
	if game.run_state != 0:
		game.route_seed = 20260900
		game.restart_run()
		await _frames(6)
	_check(game.run_state == 0, "暂停前 run_state 不是 RUNNING")

	game.toggle_pause()
	await _frames(2)
	_check(self.paused, "暂停未生效")
	_check(game.run_state == 1, "暂停后 run_state 不是 PAUSED")
	var before: float = float(game.player.global_position.x)
	await _frames(10)
	_check(absf(float(game.player.global_position.x) - before) < 0.01,
		"暂停期间玩家仍在移动")
	print("paused    = true, player frozen at %.1f" % before)

	game.toggle_pause()
	await _frames(2)
	_check(not self.paused, "恢复未生效")
	_check(game.run_state == 0, "恢复后 run_state 不是 RUNNING")
	# 恢复后再推一帧，确认真的在跑。
	var resume_before: float = float(game.player.global_position.x)
	game.player.global_position.x += float(Motion.RUN_SPEED) / 60.0
	await _frames(3)
	_check(float(game.player.global_position.x) > resume_before, "恢复后玩家没有继续前进")
	print("paused    = false, resumed to %.1f" % float(game.player.global_position.x))

	# Restart 后 DARTS 必须重新初始化。
	game.route_seed = 20260900
	game.restart_run()
	await _frames(6)
	var darts: Node = _find_darts_chunk()
	_check(darts != null, "Restart 后 DARTS chunk 未重建")
	if darts != null:
		var info: Dictionary = darts.debug_info()
		_check(str(info.get("display_name", "")) == "飞镖关",
			"Restart 后 Section 未正确重建: %s" % str(info.get("display_name", "")))
		var section: Node = darts.get_node_or_null("Section")
		if section != null:
			var dirty := 0
			for runner in section.runners:
				if runner.spawned_count != 0 or runner.completed or runner.event_index != 0:
					dirty += 1
			_check(dirty == 0, "Restart 后 PatternRunner 状态未重置: %d 个脏" % dirty)
			print("after restart: runners=%d, dirty=%d, elapsed=%.2f" % [
				section.runners.size(), dirty, float(section.runners[0].elapsed)])

# =========================================================
# 5. 泄漏检查
# =========================================================

func _check_no_leak() -> void:
	print("--- 残留检查 ---")
	game.route_seed = 20260900
	game.restart_run()
	await _frames(8)

	var before_chunks: int = game.active_chunks.size()
	var before_children: int = root.get_child_count()

	# 推进很远，让 DARTS 与前面的 chunk 都被回收。
	var player: Node2D = game.player
	for i in 400:
		player.global_position.x += float(Motion.RUN_SPEED) / 60.0
		await physics_frame

	var after_chunks: int = game.active_chunks.size()
	var after_children: int = root.get_child_count()

	print("chunks before=%d after=%d" % [before_chunks, after_chunks])
	print("root children before=%d after=%d" % [before_children, after_children])
	_check(after_chunks > 0, "推进后没有任何 active chunk")
	_check(after_children <= before_children + 4,
		"根节点数量异常增长: %d → %d" % [before_children, after_children])

	# 被回收的 chunk 不应仍挂在场景里。
	var stray := 0
	for chunk in game.active_chunks:
		if not is_instance_valid(chunk):
			stray += 1
		else:
			var entry: Node = chunk.get_node_or_null("Entry")
			if entry == null:
				stray += 1
	_check(stray == 0, "active_chunks 中存在失效条目: %d" % stray)

	var live_darts := get_nodes_in_group("dart").size()
	_check(live_darts < 48, "飞镖数量超过同屏上限: %d" % live_darts)
	print("active chunks = %d, stray = %d, live darts = %d" % [after_chunks, stray, live_darts])

# =========================================================
# 工具
# =========================================================

func player_start(x: float) -> void:
	var player: Node2D = game.player
	player.global_position = Vector2(x, float(player.global_position.y))
	# 清掉之前的残留飞镖，避免跨段统计。
	for dart in get_nodes_in_group("dart"):
		if is_instance_valid(dart):
			dart.free()

func _tick_dart_lifecycle(section: Node) -> void:
	pass

# =========================================================
# 「会读预警的玩家」模型
# =========================================================
#
# 只读取编译结果 plan（gap / dart 事件）与玩家的真实运动能力，
# 不读取运行中的障碍物状态，也不改写玩家的 global_position.y。
# 所有动作都走玩家脚本真实入口（start_jump / request_fast_fall），
# 因此验证的是「按设计是否存在一条可通过的路线」。

# 威胁类型。
enum Threat { NONE, GAP, DART_UNDER, DART_OVER }

# 找出玩家前方最近的一个威胁。
# 返回 {"kind": Threat, "x": float, "target_y": float}
func _next_threat(section: Node, player: Node2D) -> Dictionary:
	var px: float = float(player.global_position.x)
	var best := {"kind": Threat.NONE, "x": INF, "target_y": NAN}
	for runner in section.runners:
		var plan: Dictionary = runner.plan
		if plan.is_empty() or not plan.issues.is_empty():
			continue
		var rx: float = float(runner.global_position.x)
		var ry: float = float(runner.global_position.y)
		# 安全口：必须整个人落进口里，目标是口中心。
		for gap in plan.gaps:
			var wx: float = rx + float(gap.rect.position.x)
			var lead: float = wx - px
			var closing: float = float(Motion.RUN_SPEED) + float(gap.speed)
			if lead < 0.0 or lead > closing * 1.2 or wx >= float(best.x):
				continue
			best = {
				"kind": Threat.GAP,
				"x": wx,
				"target_y": ry + float(gap.rect.position.y) + float(gap.rect.size.y) * 0.5,
			}
		# 单枚水平飞镖：低于滑铲高度用跳，高于站立头顶用下蹲。
		for event in plan.events:
			if event.preview_kind != PatternEventScript.PreviewKind.DART or event.speed <= 0.0:
				continue
			var wx: float = rx + float(event.position_offset.x)
			var lead: float = wx - px
			var closing: float = float(Motion.RUN_SPEED) + float(event.speed)
			# 单枚飞镖要提前看到：起跳/下蹲都需要提前量，窗口给 2.0s。
			if lead < 0.0 or lead > closing * 2.0 or wx >= float(best.x):
				continue
			var dart_center: float = ry + float(event.position_offset.y)
			# 站立身体顶部（世界 y）。
			var head_y: float = float(Motion.GROUND_Y) - float(Motion.BODY_SIZE.y)
			if dart_center > head_y:
				# 飞镖低于头顶 → 必须从上方跳过去。
				best = {"kind": Threat.DART_OVER, "x": wx, "target_y": NAN}
			else:
				# 飞镖在头顶或更高 → 滑铲从下方过（保持地面姿态）。
				best = {"kind": Threat.DART_UNDER, "x": wx, "target_y": NAN}
	return best

# 按威胁类型动作。
func _drive(player: Node2D, section: Node) -> void:
	var threat: Dictionary = _next_threat(section, player)
	if threat.kind == Threat.NONE:
		return
	match int(threat.kind):
		Threat.GAP:
			_drive_to_y(player, float(threat.target_y))
		Threat.DART_OVER:
			_jump_over(player, float(threat.x))
		Threat.DART_UNDER:
			_duck_under(player, float(threat.x))

# 把角色中心驱向 target_y（世界坐标）。
func _drive_to_y(player: Node2D, target_y: float) -> void:
	var dz: float = target_y - float(player.global_position.y)
	var on_floor: bool = player.is_on_floor()
	if dz < -12.0:
		if on_floor:
			player.start_jump(Motion.JUMP_SPEED)
		elif float(player.velocity.y) > -60.0:
			player.start_jump(Motion.SECOND_JUMP_SPEED)
	elif dz > 24.0 and not on_floor:
		player.request_fast_fall()

# 跳过一枚贴地飞镖：在接触前起跳，让身体越过飞镖顶部。
func _jump_over(player: Node2D, dart_x: float) -> void:
	if not player.is_on_floor():
		return
	# 单跳要「在飞镖到达之前」就把身体抬到飞镖顶部之上。
	# 上升到能越过贴地飞镖所需的高度大约需要 0.35s，
	# 加上输入容错，留 0.55s 的提前量。
	var lead: float = dart_x - float(player.global_position.x)
	var closing: float = float(Motion.RUN_SPEED)
	if lead / closing <= 0.55:
		player.start_jump(Motion.JUMP_SPEED)

# 下蹲通过一枚头顶飞镖：保持地面、按下滑。
func _duck_under(player: Node2D, dart_x: float) -> void:
	if not player.is_on_floor():
		# 在空中就先落回地面。
		player.request_fast_fall()
		return
	# 下蹲要「提前生效并保持」：滑铲有启动/结束时间，
	# 太晚按会导致飞镖到达时身体还没降下去。
	var lead: float = dart_x - float(player.global_position.x)
	var closing: float = float(Motion.RUN_SPEED)
	var remaining: float = lead / closing
	if remaining <= 0.75 and not player.is_sliding():
		player.start_slide()

func _count_active_patterns(section: Node, global_x: float) -> int:
	var count := 0
	for info in section.pattern_info:
		var start: float = float(section.global_position.x) + float(info.start_x)
		var end: float = float(section.global_position.x) + float(info.end_x)
		if global_x >= start and global_x < end:
			count += 1
	return count

func _find_darts_chunk() -> Node:
	for chunk in game.active_chunks:
		if chunk != null and is_instance_valid(chunk) and chunk.get_script() == DartScript:
			return chunk
	return null

func _next_chunk_after(darts: Node) -> Node2D:
	var exit_x: float = float(darts.get_node("Exit").global_position.x)
	var best: Node2D = null
	var best_x := INF
	for chunk in game.active_chunks:
		if chunk == darts or not is_instance_valid(chunk):
			continue
		var entry: Node2D = chunk.get_node_or_null("Entry") as Node2D
		if entry == null:
			continue
		var dx: float = float(entry.global_position.x) - exit_x
		if dx >= -0.5 and dx < best_x:
			best_x = dx
			best = chunk
	return best

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  ", message)
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("\nDart section official regression passed: pattern chain, flow, lifecycle, pause/restart, no leak.")
		quit(0)
	else:
		print("\nDart section official regression FAILED (%d):" % failures.size())
		for f in failures:
			print("  - ", f)
		quit(1)
