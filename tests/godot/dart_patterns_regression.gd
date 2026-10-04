extends SceneTree

# DARTS Segment 在「不同跑速」下的通过性回归。
#
# 历史背景：
#   本测试原本验证 components/dart_encounter.gd 里手写的四波飞镖
#   （Pattern 枚举 / build_pattern() / wave_index / MAX_DARTS）。
#   那套实现已被 Pattern 系统取代：
#     正式路径 = game.gd → segment_darts → PatternSection
#              → Dart_Introduction.tres → PatternCompiler → PatternRunner → Dart。
#
#   因此这里保留测试意图（预警可见 / 飞镖数量有界 / 可无伤通过 / Restart 清场），
#   但改为驱动新的数据驱动实现，并额外覆盖 620 px/s（滑铲冲刺速度）。
#
# 与 dart_section_official_regression.gd 的分工：
#   - 那份验证「官方完整流程 + 与前后 Segment 的衔接 + 暂停/重开/泄漏」
#   - 这份只验证「不同跑速下的通过性与飞镖上限」

const Motion := preload("res://patterns/player_motion_profile.gd")
const DartScript := preload("res://components/dart_encounter.gd")
const PatternEventScript := preload("res://patterns/pattern_event.gd")

var failures: Array[String] = []
var game: Node
var player: Node2D

enum Threat { NONE, GAP, DART_OVER, DART_UNDER }

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for speed in [400.0, 620.0]:
		await run_section(speed)
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Dart patterns passed: bounded darts, visible gaps and no-damage passage at 400/620 px/s on the Pattern-driven segment.")
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run_section(speed: float) -> void:
	var world: Node = load("res://test_world.tscn").instantiate()
	root.add_child(world)
	game = world
	await _frames(6)

	game.route_seed = 20260900
	game.restart_run()
	await _frames(6)

	var darts: Node = _find_darts_chunk()
	check(darts != null, "固定种子的正式路线应以 DARTS 开场（CHUNK_SCENES[12]）")
	if darts == null:
		world.free()
		return

	var info: Dictionary = darts.debug_info()
	check(int(info.get("issues", PackedStringArray()).size()) == 0,
		"速度为 %s 时 Section 存在编译器 issue" % speed)

	var section: Node = darts.get_node_or_null("Section")
	check(section != null, "Section 子节点缺失")
	if section == null:
		world.free()
		return

	# 序列与 Runner 数量都从数据推导，避免重新编排 Section 后常量失效。
	var section_data: PatternSectionData = section.data
	var expected := PackedStringArray()
	var expected_runners := 0
	for section_entry in section_data.entries:
		if section_entry is ObstaclePatternData:
			expected.append(section_entry.template)
			expected_runners += 1
	check(PackedStringArray(str(info.get("sequence", "")).split(" → ")) == expected,
		"Pattern 序列不符: %s != %s" % [str(info.get("sequence", "")), str(expected)])

	# 飞镖来源必须是 PatternRunner（新架构），而不是 segment 自己造的波次。
	check(section.runners.size() == expected_runners,
		"期望 %d 个 PatternRunner，实际 %d" % [expected_runners, section.runners.size()])

	player = game.player
	player.damaged.connect(func(amount: float) -> void:
		var nearby: Array[String] = []
		for active_dart in get_nodes_in_group("dart"):
			if absf(active_dart.global_position.x - player.global_position.x) < 120.0:
				nearby.append("(%.0f,%.0f)" % [active_dart.global_position.x, active_dart.global_position.y])
		print("   DAMAGE %.0f at x=%.0f y=%.0f stage=%s nearby=%s" % [amount, player.global_position.x, player.global_position.y, str(darts.debug_info_at(player.global_position.x).get("stage", "")), str(nearby)])
	)
	player.set_run_speed(speed)
	var start_x: float = float(darts.get_node("Entry").global_position.x)
	var last_end := 0.0
	for runner in section.runners:
		last_end = maxf(last_end, float(runner.global_position.x) + float(runner.plan.length))
	var stop_x: float = last_end + 1.5 * speed

	# 把玩家放到入口，然后模拟一个「会读预警的玩家」。
	player.global_position = Vector2(start_x, float(player.global_position.y))
	for dart in get_nodes_in_group("dart"):
		if is_instance_valid(dart):
			dart.free()

	var spawned_any := false
	var max_darts := 0
	var warning_seen := false
	var guard := 0
	var reached_exit := false
	var step: float = speed / 60.0

	while float(player.global_position.x) < stop_x and guard < 6000:
		guard += 1
		player.global_position.x += step
		_drive(section, speed)
		# PatternRunner._draw 只有在预警窗口内才会画橙色圈；
		# 这里用「距离最近的飞镖事件 <= 0.8s」近似「预警已可见」。
		if _warning_visible(section, speed):
			warning_seen = true
		await physics_frame
		if section.runners.size() > 0:
			for runner in section.runners:
				if runner.spawned_count > 0:
					spawned_any = true
		max_darts = maxi(max_darts, get_nodes_in_group("dart").size())
		if float(player.global_position.x) >= last_end:
			reached_exit = true
			# 本测试只对 DARTS 这一段负责。
			# 越过 Section 结尾后玩家已经进入下一个 Segment，
			# 之后的伤害不属于本段的通过性判定。
			break
		if float(player.health) <= 0.0:
			break

	if float(player.health) < player.MAX_HP:
		print("   [%s] 结束 x=%.0f health=%.0f（本段共 %.0f px）" % [speed, float(player.global_position.x), float(player.health), last_end])
	check(spawned_any, "PatternRunner 从未生成任何障碍（速度 %s）" % speed)
	check(warning_seen, "整段没有出现过飞镖预警（速度 %s）" % speed)
	check(player.health == player.MAX_HP,
		"速度 %s 下应可无伤通过，实际 health=%s" % [speed, player.health])
	check(reached_exit, "玩家未走到本段最后一个 Pattern 的结尾（速度 %s）" % speed)
	check(max_darts <= 32, "飞镖同屏数量失控: %d（速度 %s）" % [max_darts, speed])

	game.restart_run()
	await _frames(4)
	check(get_nodes_in_group("dart").is_empty(), "Restart 必须清空场景里的飞镖（速度 %s）" % speed)

	world.free()
	await process_frame

# =========================================================
# 「会读预警的玩家」模型（与 dart_section_official_regression 保持一致）
# =========================================================

func _next_threat(section: Node, speed: float) -> Dictionary:
	var px: float = float(player.global_position.x)
	var best := {"kind": Threat.NONE, "x": INF, "target_y": NAN}
	for runner in section.runners:
		var plan: Dictionary = runner.plan
		if plan.is_empty() or not plan.issues.is_empty():
			continue
		var rx: float = float(runner.global_position.x)
		var ry: float = float(runner.global_position.y)
		for gap in plan.gaps:
			var wx: float = rx + float(gap.rect.position.x)
			var lead: float = wx - px
			var closing: float = speed + float(gap.speed)
			if lead < 0.0 or lead > closing * 1.2 or wx >= float(best.x):
				continue
			best = {
				"kind": Threat.GAP,
				"x": wx,
				"target_y": ry + float(gap.rect.position.y) + float(gap.rect.size.y) * 0.5,
			}
		for event in plan.events:
			if event.preview_kind != PatternEventScript.PreviewKind.DART or event.speed <= 0.0:
				continue
			var wx: float = rx + float(event.position_offset.x)
			var lead: float = wx - px
			var closing: float = speed + float(event.speed)
			# 把「刚刚擦身而过但仍在碰撞范围内」的飞镖也算进来。
			# 动作句里两枚飞镖只差 0.6s，玩家的正确反应是连着处理这两拍，
			# 而不是只处理最近的、落在前方的那一枚。
			if lead > closing * 2.0 or wx >= float(best.x):
				continue
			if lead < -260.0:
				continue
			var dart_center: float = ry + float(event.position_offset.y)
			var head_y: float = float(Motion.GROUND_Y) - float(Motion.BODY_SIZE.y)
			if dart_center > head_y:
				best = {"kind": Threat.DART_OVER, "x": wx, "target_y": NAN}
			else:
				best = {"kind": Threat.DART_UNDER, "x": wx, "target_y": NAN}
	return best

func _drive(section: Node, speed: float) -> void:
	var threat: Dictionary = _next_threat(section, speed)
	match int(threat.kind):
		Threat.GAP:
			_drive_to_y(float(threat.target_y), speed)
		Threat.DART_OVER:
			_jump_over(float(threat.x), speed)
		Threat.DART_UNDER:
			_duck_under(float(threat.x), speed)

func _drive_to_y(target_y: float, speed: float) -> void:
	var dz: float = target_y - float(player.global_position.y)
	if dz < -12.0:
		if player.is_on_floor():
			player.start_jump(Motion.JUMP_SPEED)
		elif float(player.velocity.y) > -60.0:
			player.start_jump(Motion.SECOND_JUMP_SPEED)
	elif dz > 24.0 and not player.is_on_floor():
		player.request_fast_fall()

func _jump_over(dart_x: float, speed: float) -> void:
	# 「会跳」的玩家：需要抬到飞镖顶部之上才起跳。
	# 抬升到越过贴地飞镖所需高度约需 0.35s，留 0.55s 提前量。
	#
	# 注意：P30 动作句里第二枚飞镖出现时玩家**可能仍在滞空**。
	# 这时不能简单 return —— 如果已经在空中且上升中，就是正确状态；
	# 如果已经在空中但在下落，必须用二段跳把身体重新抬起。
	var lead: float = dart_x - float(player.global_position.x)
	var time_left: float = lead / maxf(1.0, speed)
	if player.is_on_floor():
		if time_left <= 0.55:
			player.start_jump(Motion.JUMP_SPEED)
		return
	# 已在空中：只有「还在下落」且来不及了才补二段跳。
	if time_left <= 0.55 and float(player.velocity.y) > -60.0:
		player.start_jump(Motion.SECOND_JUMP_SPEED)

func _duck_under(dart_x: float, speed: float) -> void:
	# 「会蹲」的玩家：需要落地后下蹲，或在下落途中快速落地再蹲。
	var lead: float = dart_x - float(player.global_position.x)
	var time_left: float = lead / maxf(1.0, speed)
	if not player.is_on_floor():
		# 尽快落地：动作句里落点本身就是设计的一部分。
		player.request_fast_fall()
		return
	if time_left <= 0.75 and not player.is_sliding():
		player.start_slide()

# 近似判断「橙色预警圆已经可见」：PatternRunner._draw 的窗口是 0.8s。
func _warning_visible(section: Node, speed: float) -> bool:
	var px: float = float(player.global_position.x)
	for runner in section.runners:
		var plan: Dictionary = runner.plan
		if plan.is_empty() or runner.completed:
			continue
		var rx: float = float(runner.global_position.x)
		for index in range(runner.event_index, plan.events.size()):
			var event: PatternEvent = plan.events[index]
			if event.spawn_time - runner.elapsed > 0.8:
				continue
			# 事件位置相对 runner；玩家越接近，预警越可能已经在画。
			if absf(rx + float(event.position_offset.x) - px) <= speed * 0.8:
				return true
	return false

func _find_darts_chunk() -> Node:
	for chunk in game.active_chunks:
		if chunk != null and is_instance_valid(chunk) and chunk.get_script() == DartScript:
			return chunk
	return null

func _frames(count: int) -> void:
	for i in count:
		await physics_frame


