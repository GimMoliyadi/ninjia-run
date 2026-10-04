extends RefCounted

const Motion := preload("res://patterns/player_motion_profile.gd")
const Layouts := preload("res://patterns/pattern_layouts.gd")
const Dart := preload("res://components/dart.gd")
const SPIKE := preload("res://scenes/SpikeStrip.tscn")
const DART_SPEED := Motion.RUN_SPEED * 0.45
const APPROACH_JUMPS := 2.5
const SPIKE_HEIGHT := 72.0
const BURST_INTERVAL := Motion.Player.FLIP_DURATION * 0.5

# =========================================================
# 绳索段自己的编排数据（2026-09-22）
# =========================================================
#
# 这一层只服务绳索地图，**不改动通用飞镖生成器**
# （patterns/dart_pattern_library.gd 是飞镖潮的正式生成器，保持原样）。
#
# 之前的绳索动作组只有「同高度连镖」一种形状，表达不了本轮需要的两种设计语言：
#
#   * 波浪飞镖 —— 每一枚飞镖各占一个高度，连起来是一条斜线，作用是
#                 「把玩家从一侧引到另一侧」，即引导翻面节奏。
#   * 横排飞镖 —— 同一高度、更紧的间距连成一整条，作用是
#                 「明确封锁一条路线」。
#
# 于是给 gate 增加两个**可选**字段，含义都留在数据里：
#
#   spacing : float   同一组连镖之间的秒数（默认沿用历史值 BURST_INTERVAL）
#   heights : Array   每一枚飞镖的高度比例（相对玩家身高）。
#
# heights 语义（2026-09-23 起统一为带符号，旧的全正写法已随绳索 Wave 数据重排移除）：
#
#   正 = 绳上方，负 = 绳下方，height = 身高 × 该值。
#   一条斜列因此可以在同一个 gate 里从绳上连续排到绳下（穿越绳线的完整斜线），
#   而不是拆成上下两个 cluster。省略 heights 时沿用历史的两档比例，
#   符号跟随封锁侧。
#
# 斜列波浪语言（2026-09-23 等距重排后生效）：
#
#   * 整列严格等距：相邻飞镖的 heights 步长完全一致（含跨绳那一档），
#     等时间间隔下飞镖在空中自然连成一条从头到尾等距的斜线；
#   * 绳线恰好穿过某一对相邻飞镖之间「普通缝隙」的正中——该两枚高度互为相反数，
#     玩家就借这道缝完成穿绳翻面，不存在为翻面挖出来的大空洞；
#   * 斜列 gate 的 safe_side 只作 route 记录用（统一写下绳侧 1）：
#     波浪语言里翻面全部发生在列内跨绳缝中，组与组之间不需要翻面窗口。
#
# 两者都只影响绳索段自己的出生位置编排，不引入新机制、不改障碍行为、
# 不改碰撞与伤害。count 上限从 5 放宽到 8，因为横排要读成「一整条」而不是
# 「几枚飞镖」，5 枚撑不满一条可读的封锁线。
#
# 波列拼接（2026-09-23：斜列波之间不再留停顿，连成一条波浪形阵列）：
#
#   * 转折那一枚飞镖（波峰 / 波谷）只由**前一波**给出，后一波从转折的下一档开始，
#     两波之间因此不会出现「同一高度连着两枚」的平顶；
#   * 波原点 = 上一波**最后一枚飞镖的相遇位置**，即本波 `duration` 等于
#     本波末枚相遇的 beat；于是下一波首枚相遇恰好落在波原点后一个 spacing；
#   * 结果：整段相遇时间轴是严格等距的一条折线，「写进数据的时长」与
#     「屏幕上的飞镖间距」是同一个数。
#     改 count / spacing / heights 时必须同步重算该波 `duration`，
#     否则折线会在接缝处被拉开或挤紧。
#   * 波原点因此与「本波飞镖的出生范围」无关，可以落在上一波飞镖仍在飞的区间里；
#     Runner 按玩家绝对进度推进，重叠不影响出生时刻（见 pattern_runner.advance_distance）。
const MAX_BURST_COUNT := 8
const MIN_SPACING := 0.06
const MAX_SPACING := 0.40
# 贴绳死区：翻面时玩家身体扫过绳线全带，|高度| 小于此值的飞镖无论站在哪侧、
# 何时翻面都会撞上，斜列数据里禁止出现。
const FLIP_DEAD_ZONE := 16.0
# 绳下可视深度：相机随玩家垂移（offset -80、无 limit），站上绳时画面最低约到
# 绳下 190px，留余量后取此值；再深的飞镖玩家根本看不见，属于无预警的暗箭。
const MAX_BELOW_DEPTH := 180.0

static func compile(data: ObstaclePatternData, modifier: int, recovery: RecoverySection) -> Dictionary:
	var length := data.duration * Motion.RUN_SPEED
	var plan := {
		"events": [], "pits": [Vector2(0, length)], "gaps": [], "recoveries": [], "notes": [],
		"issues": PackedStringArray(), "distance_driven": true, "rope_actions": [],
		"duration": data.duration, "length": length, "recovery_length": recovery.distance(Motion.RUN_SPEED),
		"needs_manual_playtest": true,
	}
	if modifier != PatternModifier.Kind.NORMAL or data.mirror or not is_zero_approx(data.start_delay):
		plan.issues.append("绳索 Wave 只使用预编排的 NORMAL 空间节拍")
	var gates: Array = data.parameters.get("gates", [])
	if gates.is_empty() or data.duration <= 0.0:
		plan.issues.append("绳索 Wave 必须有时长与有序动作组")
	for gate in gates:
		append_gate(plan, gate)
	plan.events.sort_custom(func(a: PatternEvent, b: PatternEvent) -> bool: return a.spawn_time < b.spawn_time)
	plan.issues.append_array(validate_route(plan.rope_actions))
	return plan

static func append_gate(plan: Dictionary, gate: Dictionary) -> void:
	var kind := str(gate.get("kind", "darts"))
	var beat := float(gate.get("beat", -1.0))
	var safe_side := int(gate.get("safe_side", 0))
	var count := int(gate.get("count", 3)) if kind != "spikes" else 0
	var width := Motion.BODY_SIZE.x * float(gate.get("width_ratio", 1.0))
	var spacing := clampf(float(gate.get("spacing", BURST_INTERVAL)), MIN_SPACING, MAX_SPACING)
	var heights: Array = gate.get("heights", [])
	if kind not in ["darts", "spikes", "mixed_flip", "jump"] or safe_side not in [0, 1] or count < 0 or count > MAX_BURST_COUNT:
		plan.issues.append("绳索动作组类型、上下侧或连镖数无效")
		return
	if beat < 0.0 or beat >= plan.duration - Motion.rope_flip_window() or width <= 0.0:
		plan.issues.append("绳索动作组超出 Wave 或没有出口余量")
	if kind == "darts" and not heights.is_empty():
		validate_diagonal_heights(plan, heights)
	if kind == "jump":
		safe_side = 0
	var blocked_side := 1 - safe_side
	if count > 0:
		append_darts(plan, beat, blocked_side, count, int(gate.get("rows", 1)), spacing, heights)
	if kind != "darts":
		append_spike(plan, beat, 0 if kind == "jump" else blocked_side, width)
	var contact_margin := (Motion.BODY_SIZE.x * 0.5 + Dart.RADIUS) / (1.0 + DART_SPEED / Motion.RUN_SPEED)
	if kind != "darts":
		contact_margin = maxf(contact_margin, (width + Motion.BODY_SIZE.x) * 0.5)
	plan.rope_actions.append({
		"kind": kind, "x": beat * Motion.RUN_SPEED, "safe_side": safe_side,
		"danger_start": beat * Motion.RUN_SPEED - contact_margin,
		"danger_end": (beat + maxi(0, count - 1) * spacing) * Motion.RUN_SPEED + contact_margin,
	})

static func append_darts(plan: Dictionary, beat: float, side: int, count: int, rows: int, spacing: float, heights: Array = []) -> void:
	if rows not in [1, 2]:
		plan.issues.append("绳侧飞镖只支持一层或两层")
		return
	var approach := Motion.jump_time() * APPROACH_JUMPS
	var distance := (Motion.RUN_SPEED + DART_SPEED) * approach
	for index in count:
		for row in rows:
			var height := _dart_height(side, row, rows, heights, index)
			plan.events.append(Layouts.dart(beat + index * spacing - approach, distance, height, DART_SPEED))

static func _dart_height(side: int, row: int, rows: int, heights: Array, index: int) -> float:
	if heights.is_empty():
		var ratio := 0.5 if rows == 1 else (0.32 if row == 0 else 0.8)
		return Motion.BODY_SIZE.y * ratio * (1.0 if side == 0 else -1.0)
	# 带符号 heights：正 = 绳上方、负 = 绳下方，一条斜列自身跨绳；
	# 封锁侧不再改写符号（等时间间隔下飞镖在空中自然连成等距斜线）。
	return Motion.BODY_SIZE.y * float(heights[index % heights.size()])

static func validate_diagonal_heights(plan: Dictionary, heights: Array) -> void:
	if heights.size() < 5:
		plan.issues.append("绳索斜列至少 5 枚飞镖才读得出一整条斜线")
		return
	var step: float = float(heights[1]) - float(heights[0])
	if is_zero_approx(step):
		plan.issues.append("绳索斜列步长为 0，不构成斜线")
		return
	for index in range(1, heights.size() - 1):
		var next_step: float = float(heights[index + 1]) - float(heights[index])
		if not is_equal_approx(next_step, step):
			plan.issues.append("绳索斜列相邻步长不一致（%.4f 与 %.4f），整列必须严格等距" % [step, next_step])
			return
	var crossing := false
	for index in range(heights.size() - 1):
		var upper: float = float(heights[index])
		var lower: float = float(heights[index + 1])
		if upper * lower < 0.0 and is_equal_approx(upper, -lower):
			crossing = true
			break
	if not crossing:
		plan.issues.append("绳索斜列没有正中跨绳的普通缝隙（相邻两枚高度须互为相反数）")
		return
	for entry in heights:
		var height := Motion.BODY_SIZE.y * float(entry)
		if absf(height) < FLIP_DEAD_ZONE:
			plan.issues.append("绳索斜列有飞镖贴绳（|高度| < %.0fpx），翻面过程必撞" % FLIP_DEAD_ZONE)
			return
		if height < -MAX_BELOW_DEPTH:
			plan.issues.append("绳索斜列有飞镖沉出可视下缘（绳下最深 %.0fpx）" % MAX_BELOW_DEPTH)
			return

static func append_spike(plan: Dictionary, beat: float, side: int, width: float) -> void:
	var event := PatternEvent.new()
	event.obstacle_scene = SPIKE
	event.position_offset = Vector2(beat * Motion.RUN_SPEED - width * 0.5, 0)
	event.spawn_time = beat - Motion.jump_time() * APPROACH_JUMPS - Motion.BODY_SIZE.x / Motion.RUN_SPEED
	event.preview_kind = PatternEvent.PreviewKind.SPIKE
	event.preview_size = Vector2(width, SPIKE_HEIGHT)
	event.optional_parameters = {"size": event.preview_size, "scale": Vector2(1, 1 if side == 0 else -1)}
	plan.events.append(event)

static func validate_route(actions: Array) -> PackedStringArray:
	var issues := PackedStringArray()
	for index in range(1, actions.size()):
		var previous: Dictionary = actions[index - 1]
		var current: Dictionary = actions[index]
		var spacing: float = (current.x - previous.x) / Motion.Player.SLIDE_BURST_SPEED
		if spacing <= 0.0:
			issues.append("绳索动作必须按位置严格递增")
		if current.safe_side != previous.safe_side:
			var free_time: float = (current.danger_start - previous.danger_end) / Motion.Player.SLIDE_BURST_SPEED
			var required := Motion.rope_flip_window()
			if current.kind == "jump":
				required += Motion.ROPE_JUMP_LEAD
			if free_time < required:
				issues.append("相邻上下威胁之间没有完整翻绳/起跳窗口：%.2f < %.2fs" % [free_time, required])
		if previous.kind == "jump":
			var required := Motion.jump_time() - Motion.ROPE_JUMP_LEAD + Motion.rope_flip_window()
			if spacing < required:
				issues.append("跳刺后没有落回绳再翻面的时间：%.2f < %.2fs" % [spacing, required])
	return issues
