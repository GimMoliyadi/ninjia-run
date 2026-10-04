extends RefCounted

const Motion := preload("res://patterns/player_motion_profile.gd")
const Layouts := preload("res://patterns/pattern_layouts.gd")
const Walls := preload("res://patterns/pattern_walls.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")
const Library := preload("res://patterns/dart_pattern_library.gd")
const APPROACH_JUMPS := 2.0
const MIN_BEAT_GAP := 0.25
const EXIT_CLEARANCE := 0.3

# 自动延长 duration 时的浮点余量。
#
# 为什么需要它：末拍校验是 `beat > effective_duration - EXIT_CLEARANCE`，
# 而 effective_duration 又恰好是 `arrange_end + EXIT_CLEARANCE` ——
# 两者在浮点下可能算出同一个数（实测 2.0025 - 0.3 = 1.7025000000000001 > 1.7025），
# 于是「编排刚好需要这么长」的 Wave 会被自己判为「末拍没留出离场空间」，
# 整个 Wave 因为 issues 非空而**一枚飞镖都不发射**。
# 加 1ms 余量让不变式在浮点下也成立。
const DURATION_EPSILON := 0.001

static func compile(data: ObstaclePatternData, level: int, modifier: int, recovery: RecoverySection) -> Dictionary:
	var plan := {
		"events": [], "pits": [], "gaps": [], "recoveries": [], "notes": [],
		"issues": PackedStringArray(), "distance_driven": true,
		"patterns_arranged": [],
		"duration": data.duration, "length": data.duration * Motion.RUN_SPEED,
		"recovery_length": recovery.distance(Motion.RUN_SPEED), "needs_manual_playtest": true,
	}
	var speed: float = data.parameters.get("speed", 180.0)
	speed *= Modifier.speed_factor(data, modifier)
	var approach := Motion.jump_time() * APPROACH_JUMPS
	var volleys := collect_volleys(data.parameters, plan)
	if volleys.is_empty() or speed <= 0.0 or data.duration <= 0.0:
		plan.issues.append("飞镖 Wave 需要正时长、正速度和预编排的 volleys / patterns")
	if not Modifier.supported(data, modifier) or data.mirror:
		plan.issues.append("此飞镖 Wave 不支持所选变体")
# 有效时长 = max(作者声明的 duration, 编排真正需要的时长)。
#
# 编排所需的时长由 Pattern 顺序与固定间距唯一决定（见 dart_pattern_library.arrange），
# 而 data.duration 是作者手写的「期望时长」。两者不一致时以编排为准：
# 否则末拍会被截断。
# 这样「改 Pattern 顺序」不需要同步手改 duration，不会再出现两处真值。
#
# 2026-09-16 第 6 轮：改固定编排后，arrange_end 是精确值（不再是模型推算），
# 所以正常情况下 effective_duration 应当非常接近 arrange_end + EXIT_CLEARANCE。
	var arrange_end := 0.0
	for pattern in plan.get("patterns_arranged", []):
		arrange_end = maxf(arrange_end, float(pattern.get("beat", 0.0)) + Library.span_of(pattern))
	for volley in volleys:
		arrange_end = maxf(arrange_end, float(volley.get("beat", 0.0)))
	var effective_duration: float = maxf(data.duration, arrange_end + EXIT_CLEARANCE + DURATION_EPSILON)
	if effective_duration > data.duration + 0.001:
		plan.notes.append("编排需要 %.2fs，已从声明的 %.2fs 自动延长（末拍 %.2fs）" % [
			effective_duration, data.duration, arrange_end])
	plan["authored_duration"] = data.duration
	plan["duration"] = effective_duration
	# ⚠ length 必须跟着 effective_duration 走，不能留在 data.duration 上。
	#
	# length 决定这段 Wave 占多少地面、以及**下一段 Wave 从哪里开始**
	#（pattern_section.build: section_length += plan.length）。
	# 如果作者写的 duration 比编排实际需要的短，编排会被自动延长，
	# 但 length 若仍按作者值算，后面每一段 Wave 都会整体前移 ——
	# 于是「写在数据里的 Pattern 间距」和「屏幕上真实的间距」对不上，
	# 飞镖甚至会落到下一段 Wave 的地面上。
	plan["length"] = effective_duration * Motion.RUN_SPEED
	var previous := -INF
	for volley in volleys:
		var beat: float = volley.get("beat", -1.0)
		if beat < 0.0 or beat > effective_duration - EXIT_CLEARANCE or beat - previous < MIN_BEAT_GAP:
			plan.issues.append("Wave 节拍需有序、至少间隔 0.25s，末拍需留出离场空间")
		previous = beat
		append_volley(plan, volley, speed, approach, level)
	Modifier.apply(plan, data, modifier, recovery)
	plan.events.sort_custom(func(a: PatternEvent, b: PatternEvent) -> bool: return a.spawn_time < b.spawn_time)
	plan["threat_end"] = previous + EXIT_CLEARANCE
	plan["needed_length"] = plan.threat_end * Motion.RUN_SPEED
	plan["pattern_notes"] = describe_patterns(plan.get("patterns_arranged", []))

	# 真实 X 间距自检（2026-09-16 第 6 轮新增）。
	#
	# 朋友的规格要求：Pattern 间距必须按「上一 Pattern 最后一枚飞镖的实际 X
	# → 下一 Pattern 第一枚飞镖的实际 X」计算，而不是 pattern_origin → origin。
	#
	# 固定编排下 this 由 arrange() 保证，但必须能**验证** ——
	# 否则一旦有人在数据里写错 gap_px，或者 expand 的末枚算错，
	# 眼睛看到的空白就会和写下的数字不一致，而且没有任何提示。
	#
	# 这里按真实碰撞件的相遇点 X 复核每一个 Pattern 接缝，
	# 并把结果写进 plan 供 F1 覆盖层与检查脚本读取。
	plan["seams"] = _measure_seams(plan.get("patterns_arranged", []), plan)

	# ACT 衔接体检（2026-09-18 第 7 轮新增）。
	#
	# 把本 Wave 内所有「必须做动作」的飞镖（h < 77）按真实 X 排好，
	# 检查 (a) 一簇 ACT 飞镖能不能被同一个滑铲盖住，(b) 簇与簇之间的间距。
	# 跨 Wave / 跨 Section 的那部分由 MapModuleChunk 用同样的规则再查一遍。
	var report := Library.map_act_report(_act_darts(volleys))
	for issue in report.issues:
		plan.issues.append("ACT 飞镖簇跨度过长：%d 枚从 x=%.0f 起跨 %.0fpx，一个滑铲只能盖 %.0fpx" % [
			issue.count, issue.first_x, issue.span_px, issue.limit_px])
	for note in report.notes:
		plan.notes.append(note)

	return plan


# 把 volleys 转成衔接体检需要的 {x, h} 列表（x 是 Wave 内的相遇点 X）。
static func _act_darts(volleys: Array) -> Array:
	var darts: Array = []
	for volley in volleys:
		var x := float(volley.get("beat", 0.0)) * Motion.RUN_SPEED
		if volley.has("heights"):
			for raw_height in volley.heights:
				darts.append({"x": x, "h": float(raw_height)})
		else:
			darts.append({"x": x, "h": float(volley.get("height", 0.0))})
	return darts


# 按真实相遇点 X 复核每个 Pattern 接缝，并判定它落在哪个衔接带。
#
# 相遇点 X = beat × RUN_SPEED（见 pattern_layouts.dart：
# position_offset.x = RUN_SPEED × beat + distance，distance 是预跑距离，
# 与「两枚飞镖之间看得到的距离」无关）。
#
# 每行给出：上一个 Pattern 的末枚 X、下一个 Pattern 的首枚 X、两者之差（px），
# 以及衔接带判定（FREE / CONTINUOUS / CLEAN / DEAD_ZONE，见 dart_pattern_library）。
# 落进 DEAD_ZONE 会直接记成编译 issue。
static func _measure_seams(arranged: Array, plan: Dictionary) -> Array:
	var seams: Array = []
	for index in range(1, arranged.size()):
		var previous: Dictionary = arranged[index - 1]
		var current: Dictionary = arranged[index]
		var previous_last_beat := float(previous.get("beat", 0.0)) + Library.span_of(previous)
		var current_first_beat := float(current.get("beat", 0.0))
		var gap_px := (current_first_beat - previous_last_beat) * Motion.RUN_SPEED
		# 只有「上一句末枚是 ACT」且「下一句首枚是 ACT」时，间距才需要判带。
		# 只要有一边是 SAFE，玩家就能从容过渡，间距随便写。
		var band := "FREE"
		var both_act := Library.exit_is_act(previous) and Library.entry_is_act(current)
		if both_act:
			band = Library.act_gap_band(gap_px)
			if band == "DEAD_ZONE":
				plan.issues.append(
					"Pattern 接缝落在死区：%s → %s 间距 %.0fpx（应 <= %.0fpx 连成一个动作，或 >= %.0fpx 完整落地重来）" % [
						str(previous.get("kind", "")), str(current.get("kind", "")), gap_px,
						Library.seam_continuous_max_px(), Library.seam_clean_min_px()])
		seams.append({
			"from": str(previous.get("kind", "")),
			"to": str(current.get("kind", "")),
			"prev_last_x": previous_last_beat * Motion.RUN_SPEED,
			"next_first_x": current_first_beat * Motion.RUN_SPEED,
			"gap_px": gap_px,
			"band": band,
			"both_act": both_act,
			"ok": band != "DEAD_ZONE",
		})
	return seams


# 收集本 Wave 的所有「拍」。
#
# 两种数据源，可以混用：
#   * parameters.volleys  —— 直接给出每一拍（历史格式，继续支持）
#   * parameters.patterns —— 给出动作句（Pattern），
#                            由 DartPatternLibrary 展开成若干拍
#
# patterns 只需要写顺序、种类与「与上一句真实末枚的 X 间距（gap_px）」，
# beat 由 DartPatternLibrary.arrange 推出。
# 2026-09-16 第 6 轮起改为 handcrafted deterministic layout：
# 间距全部是朋友指定的像素值，不再走衔接模型，也不再随机化。
#
# 展开后统一按 beat 排序，后续的节拍校验与生成逻辑不需要区分来源。
static func collect_volleys(parameters: Dictionary, plan: Dictionary) -> Array:
	var volleys: Array = []
	for volley in parameters.get("volleys", []):
		volleys.append(volley)
	var arranged := Library.arrange(parameters.get("patterns", []))
	plan["patterns_arranged"] = arranged
	for pattern in arranged:
		var kind := str(pattern.get("kind", ""))
		if not Library.is_known(kind):
			plan.issues.append("未知的飞镖 Pattern 类型：%s" % kind)
			continue
		volleys.append_array(Library.expand(pattern))
	volleys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0))
	)
	return volleys

# 人类可读的动作句清单，供 F1 调试覆盖层与人工试玩反馈使用。
# 输入是已经排定 beat 的 patterns（见 collect_volleys）。
static func describe_patterns(arranged: Array) -> PackedStringArray:
	var notes := PackedStringArray()
	for pattern in arranged:
		var info := Library.describe(pattern)
		notes.append("%s @%.2fs (%d 拍 / %d 镖)" % [
			info.kind, info.beat, info.volleys, info.darts
		])
	return notes

static func append_volley(plan: Dictionary, volley: Dictionary, speed: float, approach: float, level: int) -> void:
	var beat: float = volley.get("beat", 0.0)
	var launch_time := beat - approach
	var distance := (Motion.RUN_SPEED + speed) * approach
	# beat 是固定相遇位置；出生点可以在 Wave 外，不能用它撑长地面。
	if volley.has("heights"):
		# 同一拍的多枚飞镖：上下门 / 竖排。
		# 列高只有 3 行（160px），上方或下方始终留着一整片安全区 ——
		# 与「整面竖墙」不同，后者只剩「跳过去 / 跳不过去」两种结果。
		for raw_height in volley.heights:
			append_single_dart(plan, launch_time, distance, float(raw_height), speed)
	elif volley.has("gap"):
		var gap: float = volley.gap
		var size: float = volley.get("gap_size", Motion.BODY_SIZE.y * 2.0)
		if size < Motion.BODY_SIZE.y + Walls.DART_RADIUS * 2.0:
			plan.issues.append("飞镖墙缺口不足以容纳角色与碰撞余量")
		if gap - size / 2.0 <= Walls.MIN_HEIGHT + Walls.DART_RADIUS:
			plan.issues.append("飞镖墙必须保留地面威胁，不能站立通过")
		if gap > Motion.double_jump_height() + Motion.BODY_SIZE.y / 2.0:
			plan.issues.append("飞镖墙缺口超过二段跳可达高度")
		Walls.append_wall(plan, {
			"safe_gap_position": gap, "safe_gap_size": size - (3 - level) * Walls.GAP_DIFFICULTY_STEP,
			"wall_speed": speed, "spawn_distance": distance,
		}, level, launch_time)
	else:
		append_single_dart(plan, launch_time, distance, volley.get("height", Motion.BODY_SIZE.y * 0.5), speed)

static func append_single_dart(plan: Dictionary, launch_time: float, distance: float, height: float, speed: float) -> void:
	if height < Walls.DART_RADIUS or height > Motion.double_jump_height() + Motion.BODY_SIZE.y:
		plan.issues.append("单飞镖高度超出可读的玩家活动范围")
	plan.events.append(Layouts.dart(launch_time, distance, height, speed))
