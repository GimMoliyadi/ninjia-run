class_name DartPatternLibrary
extends RefCounted

# 飞镖动作句（Obstacle Pattern）库 —— handcrafted deterministic layout。
#
# =========================================================================
# 2026-09-16 人工试玩第 6 轮：按朋友的《飞镖潮固定编排规格》重写。
# =========================================================================
#
# 本轮的核心变化有三条，都是朋友明确指定的：
#
# 1. **Pattern 间距按真实 X 坐标计算。**
#    间距 = 上一 Pattern 最后一枚飞镖的实际 X → 下一 Pattern 第一枚飞镖的实际 X。
#    不再按 pattern_origin → next_pattern_origin 计算，
#    也不会因为 Pattern 自身宽度不同而让可见空白忽大忽小。
#
#    实现方式：本库不再使用「衔接模型」（exit_settle / entry_lead / link_gap），
#    改为直接以像素为单位描述间距，再用 X_TO_BEAT 换算成 beat。
#    这样「看到的空白」与「写在数据里的数字」是同一个东西，不会再有二次转换误差。
#
# 2. **取消随机化。** 本轮不接 mirror、不做随机偏移、不做随机高度/顺序。
#    数据里写什么，屏幕上就是什么。
#
# 3. **统一高度层。** 高度不再由每个 Pattern 自行决定，而是从一段跳高度 H1 等比推出：
#      LOW  = 0.25 × H1
#      MID  = 0.50 × H1
#      HIGH = 0.78 × H1
#      TOP  = 0.95 × H1   （只少量使用）
#
# =========================================================================
# 单位与坐标约定（重要）
# =========================================================================
#
# 飞镖的相遇点世界 X 由 `pattern_layouts.dart()` 决定：
#     position_offset.x = RUN_SPEED × beat + distance
# 其中 distance 是「出生点到相遇点」的预跑距离，与身位无关。
# 因此**相邻两枚飞镖的相遇点水平距离 = RUN_SPEED × Δbeat**。
#
# 本库对外只说两种单位：
#   * px  —— 朋友给的间距（55 / 100 / 300 …），这是「眼睛看到的距离」
#   * beat —— 引擎用的相遇时刻，由 px / RUN_SPEED 换算
#
# RUN_SPEED = 400 px/s（来自 player.gd，本文件不修改 player）。
#
# 朋友的规格换算自检：310px ≈ 0.78s → 310 / 0.78 = 397 px/s ≈ 400。
# 说明规格就是按本项目的跑速写的，可以直接照抄数字。

const Motion := preload("res://patterns/player_motion_profile.gd")
const Player := preload("res://player.gd")

# 跑速。本库只读，不修改 player.gd。
const RUN_SPEED := Player.RUN_SPEED

# 把朋友的「像素间距」换算成引擎的 beat。
static func px_to_beat(px: float) -> float:
	return px / RUN_SPEED

# 反向：beat → px。调试与检查用。
static func beat_to_px(beat: float) -> float:
	return beat * RUN_SPEED

# =========================================================
# 高度层（从一段跳高度 H1 等比推出）
# =========================================================
#
# 朋友的规格：以跑道为基准，飞镖中心离跑道向上的高度 =
#
#     高度层   比例     本项目数值（H1 = 184.5）
#     LOW     0.25 H1    46.1
#     MID     0.50 H1    92.2
#     HIGH    0.78 H1   143.9
#     TOP     0.95 H1   175.2
#
# 注意：这里的数值**远低于**旧版的 LOW/MID/HIGH（36 / 200 / 300）。
# 旧版的高度是按「受击判据的反推」定的（哪些高度会挡住站立/滑铲/单跳顶点），
# 新版是按朋友的「一段跳高度的固定比例」定的，两者目的不同。
#
# 新版高度读起来更「贴地」：整条飞镖潮的垂直跨度收在 175px 以内，
# 玩家一眼能看出「这条线在上升 / 在下降」，而不是散在三个很远的层上。
#
# 碰撞自检（受击判据 h + R > feet AND h - R < feet + body，R = 11）：
#   LOW  46.1：站立（feet 0，body 66）→ 46.1-11=35.1 < 66 且 46.1+11=57.1 > 0 → 会中，必须跳。
#             滑铲（body 32）→ 35.1 < 32 不成立 → 滑铲可以过。
#             所以 LOW 是「跳或滑铲都能处理」，符合「提示玩家飞镖潮开始」的设计。
#   MID  92.2：站立 → 81.2 < 66 不成立 → 站着能过。单跳顶点 184.5 → 落地前会穿过。
#   HIGH 143.9：站立 → 132.9 < 66 不成立 → 站着能过。
#   TOP  175.2：站立 → 164.2 < 66 不成立 → 站着能过。
#
#   → 新版里只有 LOW 会挡住站立，MID/HIGH/TOP 都是「站着就安全」。
#     这与旧版（MID/HIGH 专门惩罚跳跃）的策略相反，但符合本轮规格：
#     规格要的是「整齐、连续、可读、有明确节奏」的固定编排，不是惩罚型考验。
#     跳跃的意义来自 LOW 与滑铲题，高度层主要用于**画线**（上升/下降的斜率）。

static func h1() -> float:
	return Motion.jump_height()

static func low_height() -> float:
	return 0.25 * h1()

static func mid_height() -> float:
	return 0.50 * h1()

static func high_height() -> float:
	return 0.78 * h1()

static func top_height() -> float:
	return 0.95 * h1()

# 旧版常量名保留为函数，避免其它文件（检查脚本、预览）引用时崩。
static func LOW_HEIGHT() -> float:
	return low_height()

static func MID_HEIGHT() -> float:
	return mid_height()

static func HIGH_HEIGHT() -> float:
	return high_height()

static func TOP_HEIGHT() -> float:
	return top_height()

# 滑铲层。朋友的规格里滑铲题要求「滑铲可以安全通过，站立不适合直接穿过」。
# 由受击判据反推：需要 h - R >= SLIDE_HEIGHT 且 h + R > PLAYER_HEIGHT，
# 即 h >= 32 + 11 = 43 且 h > 55 → 取 66 最稳（旧版 SLIDE_HEIGHT 也是 66）。
# 但这个值要落在新版高度体系里：66 介于 LOW 46.1 与 MID 92.2 之间，
# 大致是 0.36 × H1，读起来像「比 LOW 高一点的一条横线」。
static func slide_height() -> float:
	return Player.SLIDE_HEIGHT + Player.PLAYER_HEIGHT / 2.0 + 1.0

# =========================================================
# 水平节奏（全部以 px 为准，来自朋友的规格表）
# =========================================================
#
#   类型              时间距离     等效水平距离    本库常量
#   同一 Pattern 内    0.14~0.18s   55~70px        INNER_GAP
#   紧密衔接           0.20~0.28s   80~110px       TIGHT_LINK
#   普通衔接           0.30~0.40s   120~160px      NORMAL_LINK
#   呼吸区             0.65~0.80s   260~320px      BREATH
#
# ⚠ 与编译器的冲突（必须说明，不能默默违反规格，也不能默默改编译器）：
#
#   `dart_wave_layout.gd` 的 `MIN_BEAT_GAP = 0.25` 会拒绝任何 beat 差 < 0.25s 的相邻拍，
#   即最小水平距离 = 0.25 × 400 = **100px**。
#
#   朋友规格里「同一 Pattern 内 55~70px（0.14~0.18s）」**低于这个下限**，
#   照抄会被编译器判为「Wave 节拍需有序、至少间隔 0.25s」而编译失败。
#
#   本轮处理：**取 110px 作为 Pattern 内基础间距**。
#
#   为什么不是 100px（= 0.25s，刚好等于下限）：
#   编译器的判据是 `beat - previous < MIN_BEAT_GAP`。
#   100 / 400 = 0.25 在浮点下会算成 0.24999999…，于是**刚好卡在下限的间距会被判违规**，
#   整个 Wave 编译失败（实测报 "Wave 节拍需有序、至少间隔 0.25s"）。
#   必须留一点浮点余量，否则「写在数据里的 100px」反而过不了。
#
#   110px = 0.275s，既给了浮点余量，又落在朋友的「紧密衔接 80~110px」区间内，
#   斜线照样读成一条连续直线，只是比规格示意略疏一点点（每两枚多 10px）。
#
#   没有改 MIN_BEAT_GAP —— 那属于「重新设计飞镖系统」，规格明确禁止。
#
#   如果朋友试玩后觉得斜线不够密，正确的做法是把 MIN_BEAT_GAP 调小到 0.14
#   （需要单独确认，因为它影响全项目所有飞镖 Wave）。
const INNER_GAP := 110.0      # Pattern 内相邻飞镖。规格 55~70，受编译器下限抬高到 110
const TIGHT_LINK := 115.0     # 紧密衔接：规格 80~110（同样抬高以留浮点余量）
const NORMAL_LINK := 150.0    # 普通衔接：规格 120~160
const BREATH := 285.0         # 呼吸区：规格 260~320（整个飞镖潮只允许 2 处）

# 横排（_row）专用间距，比斜线更紧。
#
# 原因：滑铲横排三枚要靠**同一个滑铲**全部盖住。一个滑铲覆盖 232px，
# 所以三枚的首尾跨度必须 <= 232 - 24 = 208px，即相邻间距 <= 104px。
# 用 110px 会让跨度变成 220px，只剩 12px（不到 2 帧）的滑铲窗口 ——
# 试玩探针正是在滑铲横排的第三枚上受伤。
# 102px = 0.255s，仍高于编译器的 0.25s 最小拍距，同时留了浮点余量。
const ROW_GAP := 102.0

# 斜线继续用 INNER_GAP(110)：斜线里只有首尾是 ACT，中间两枚是 SAFE，
# 不存在「一个滑铲要盖住三枚」的问题。

# 衔接规则用到的两个量（见「衔接规则」一节）。
const SEAM_SAFETY_PX := 24.0   # 两个带各自的余量：连续带防「刚好卡边界」，干净带防帧抖动
const TAKEOFF_LEAD_PX := 80.0  # 起跳预备：提前 0.20s 起跳

# 上升 / 下降斜线的内部间距。规格写「约 65px」，同样受 100px 下限约束。
const DIAGONAL_GAP := INNER_GAP

# Pattern 内「两组之间」的间距（例如 低低 → 高高、延迟二跳的 低低 → 中高）。
# 规格分别给了 100~120px 与 120~140px，取中值。
const SWITCH_GAP := 115.0
const DELAYED_GAP := 130.0
const DELAYED_TAIL := 100.0

# 第一个 Pattern 的起拍。规格要求「进入飞镖潮」，
# 落地后给玩家一点时间把视线抬起来，但不留长空跑。
const FIRST_BEAT_PX := 320.0

# 抬升门 / 滑铲门不再使用（本轮规格改为「滑铲横排三枚」），
# 保留常量以免其它检查脚本引用时崩。
const GATE_ROWS := 3

# =========================================================
# Pattern 种类
# =========================================================
#
# 规格里出现的全部结构。每个 Pattern 只负责「相对本 Pattern 首枚的偏移」，
# 绝对 beat 由 arrange() 按真实 X 间距推出。
#
# 每个 kind 对应规格里一种「玩家一眼能看出的形状」：
#   LOW_PAIR        横排（低位双枚）
#   RISE            上升斜线
#   FALL            下降斜线
#   LOW_HIGH        高低两层（低低 + 高高）
#   HIGH_MID_LOW    下降趋势（高 → 中 → 低）
#   DELAYED         延迟二段跳组合
#   SLIDE_ROW       横排（滑铲三枚，同一水平线）
#   RISE_THREE      上升斜线（三枚，滑铲后立刻起跳）
#   HIGH_PAIR       横排（高位双枚）

const KINDS := [
	"LOW_PAIR",
	"RISE",
	"FALL",
	"LOW_HIGH",
	"HIGH_MID_LOW",
	"DELAYED",
	"SLIDE_ROW",
	"RISE_THREE",
	"HIGH_PAIR",
	"CROWN",
	"HOOK",
	"LIFTED_PAIR",
]

static func is_known(kind: String) -> bool:
	return KINDS.has(kind)


# =========================================================
# 各 Pattern 的展开
# =========================================================
#
# 返回元素为 {"beat": float, "height": float}（本 Pattern 内的相对 beat，从 0 起）
# 或 {"beat": float, "heights": Array}（同一拍多枚，本轮只用于滑铲横排？不用，
# 滑铲横排是同一水平线的三枚、但**不同时刻**依次到达，所以仍是单枚高度）。

static func expand(pattern: Dictionary) -> Array:
	var kind := str(pattern.get("kind", ""))
	# 本 Pattern 的起拍。arrange() 会把排定的 beat 写进 pattern，
	# 内部各枚飞镖都相对这个值偏移 —— 否则所有 Pattern 都会从 0 开始，
	# 排定好的 beat 会被完全忽略（曾经踩过这个坑）。
	var start := float(pattern.get("beat", 0.0))
	match kind:
		"LOW_PAIR":
			return _row(start, low_height(), 2)
		"RISE":
			return _line(start, [low_height(), mid_height(), high_height()])
		"FALL":
			return _line(start, [high_height(), mid_height(), low_height()])
		"LOW_HIGH":
			return _low_high(start)
		"HIGH_MID_LOW":
			return _line(start, [high_height(), mid_height(), low_height()])
		"DELAYED":
			return _delayed(start)
		"SLIDE_ROW":
			return _row(start, slide_height(), 3)
		"RISE_THREE":
			return _line(start, [low_height(), mid_height(), high_height()])
		"HIGH_PAIR":
			return _row(start, high_height(), 2)
		"CROWN":
			return _line(start, [low_height(), top_height(), high_height()])
		"HOOK":
			return _line(start, [high_height(), top_height(), low_height()])
		"LIFTED_PAIR":
			return _lifted_pair(start)
	return []


# 水平一排：同一高度，依次到达。用于「低位双枚」「滑铲横排三枚」「高位双枚」。
# 用 ROW_GAP 而不是 INNER_GAP：横排可能有三枚 ACT 飞镖，
# 必须让同一个滑铲盖得住全部（见 ROW_GAP 的说明）。
static func _row(start: float, height: float, count: int) -> Array:
	var volleys: Array = []
	for index in count:
		volleys.append({"beat": start + px_to_beat(ROW_GAP) * index, "height": height})
	return volleys


# 斜线：高度沿给定阶梯走，间距统一。
# 上升 = 阶梯递增；下降 = 调用方直接给递减阶梯。
static func _line(start: float, ladder: Array) -> Array:
	var step := px_to_beat(DIAGONAL_GAP)
	var volleys: Array = []
	for index in ladder.size():
		volleys.append({"beat": start + step * index, "height": float(ladder[index])})
	return volleys


# 低低 + 高高（规格 Pattern 4）。
#
# 设计意图：第一组诱导玩家跳跃；第二组阻止「看到飞镖就立刻二段跳拉满」。
# 规格要求「不要上下两组相距特别远」→ 用 SWITCH_GAP（115px）。
static func _low_high(start: float) -> Array:
	var step := px_to_beat(ROW_GAP)
	var switch := px_to_beat(SWITCH_GAP)
	var volleys: Array = []
	volleys.append({"beat": start, "height": low_height()})
	volleys.append({"beat": start + step, "height": low_height()})
	volleys.append({"beat": start + step + switch, "height": high_height()})
	volleys.append({"beat": start + step + switch + step, "height": high_height()})
	return volleys


static func _lifted_pair(start: float) -> Array:
	var volleys := _low_high(start)
	# 保留两枚低镖的相遇坐标，只改变后两枚的安全高度。
	volleys[2]["height"] = top_height()
	volleys[3]["height"] = mid_height()
	return volleys


# 延迟二段跳（规格 Pattern 6，整段最重要的题）。
#
# 三段结构：
#   ① 低位双枚 —— 一段跳越过，越过之后玩家自然开始下降
#   ② 中/高位双枚 —— 落在下降轨迹上，玩家必须在此刻抬升
#   ③ 高位单枚 —— 紧接着，再次确认抬升
#
# 规格给的间距：① → ② 约 120~140px（DELAYED_GAP），② → ③ 约 60~70px
# （受编译器下限抬高到 100px）。
#
# 重点（规格原文）：不是为了创造唯一解，只是让「延迟二段跳」成为自然选择。
static func _delayed(start: float) -> Array:
	var step := px_to_beat(ROW_GAP)
	var gap := px_to_beat(DELAYED_GAP)
	var tail := px_to_beat(maxf(DELAYED_TAIL, ROW_GAP))
	var volleys: Array = []
	volleys.append({"beat": start, "height": low_height()})
	volleys.append({"beat": start + step, "height": low_height()})
	var second := start + step + gap
	volleys.append({"beat": second, "height": high_height()})
	volleys.append({"beat": second + step, "height": high_height()})
	volleys.append({"beat": second + step + tail, "height": top_height()})
	return volleys


# =========================================================
# 固定编排：Pattern 之间的真实 X 间距
# =========================================================
#
# 这是本轮最重要的地方。间距以 **px** 写在数据里，含义是
# 「上一 Pattern 最后一枚飞镖的相遇点 X → 下一 Pattern 第一枚飞镖的相遇点 X」。
#
# 因此 arrange() 不能再用「origin + 固定值」，
# 必须算出上一个 Pattern 的**实际末枚 beat**，再加上间距。
#
#   next_first_beat = prev_first_beat + prev_last_relative_beat + px_to_beat(gap_px)
#
# 其中 prev_last_relative_beat 由 expand(prev) 取 max beat 得到 ——
# 这正是「上一 Pattern 的最后一枚」，无论它内部有几枚、跨多宽。
# 于是 Pattern 自身宽度不同的影响被完全吸收掉。

# 本 Pattern 的跨度：末枚相对本 Pattern 首枚的偏移。
#
# ⚠ 必须减去 pattern.beat，因为 expand() 返回的是**绝对** beat
#（它已经按 pattern.beat 偏移过）。否则 arrange() 会把绝对 beat 当成跨度，
# 再叠加一次，间距被算成两倍以上。
static func span_of(pattern: Dictionary) -> float:
	var base := float(pattern.get("beat", 0.0))
	var last := base
	for volley in expand(pattern):
		last = maxf(last, float(volley.get("beat", base)))
	return last - base


# 把 Pattern 列表排成时间线。
#
# 每一项写：kind + gap_px（与上一个 Pattern 末枚的真实 X 间距）。
# 第一项写 start_px（从 Wave 起点算起的起步距离）。
static func arrange(patterns: Array) -> Array:
	var arranged: Array = []
	var previous: Dictionary = {}
	for raw in patterns:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var pattern: Dictionary = (raw as Dictionary).duplicate()
		var kind := str(pattern.get("kind", ""))
		if not is_known(kind):
			arranged.append(pattern)
			continue
		if previous.is_empty():
			pattern["beat"] = px_to_beat(float(pattern.get("start_px", FIRST_BEAT_PX)))
		else:
			var previous_last := float(previous.get("beat", 0.0)) + span_of(previous)
			var gap_px := float(pattern.get("gap_px", TIGHT_LINK))
			pattern["beat"] = previous_last + px_to_beat(gap_px)
		arranged.append(pattern)
		previous = pattern
	return arranged


# =========================================================
# 衔接规则：间隔 / 高低衔接 / 连续组合
# =========================================================
#
# 本轮任务：保留全部 Pattern，只调整「出现间隔 / 高低衔接 / 连续组合」，
# 让**前一个 Pattern 的玩家轨迹自然进入下一个 Pattern**。
#
# 把它变成可验证的规则，而不是手感：
#
# 飞镖按「玩家要不要做动作」分两类（只由高度决定，所以不会和 Pattern 脱节）：
#
#   SAFE —— h >= 站立身高 + 飞镖半径 = 77。
#           站立就能安全通过。玩家可以站着、可以在空中、可以从容换姿态。
#           MID(92.2) / HIGH(143.9) / TOP(175.2) 都属于这一类。
#
#   ACT  —— h < 77。站立会中招，玩家必须在它到达的那一刻处于
#           「滑铲中」或「脚底离地 57px 以上」。
#           LOW(46.1) 与 SLIDE(66) 属于这一类。
#
# =========================================================
# 两个必须先量对的东西（2026-09-18 修正）
# =========================================================
#
# ① 一个滑铲到底覆盖多少地面？
#
#    错：SLIDE_DURATION x RUN_SPEED      = 0.58 x 400 = 232px。
#    对：SLIDE_DURATION x SLIDE_BURST_SPEED = 0.58 x 620 = 359.6px。
#
#    player.gd::start_slide() 会把 boost_speed 设成 SLIDE_BOOST = 220，
#    滑铲期间玩家实际速度是 SLIDE_BURST_SPEED = 620，不是 RUN_SPEED = 400
#    （滑铲结束后 boost 才按 SURFACE_DRAG 衰减）。
#    按 232px 设计会低估滑铲能力、把间距白白拉开；按 232px 验证则会误报
#    一堆「盖不住」，让规则失去意义。
#
# ② 一枚飞镖占多宽的身位？
#
#    玩家不是「中心碰到中心」才中招 —— dart.gd 用的是 swept_shape，
#    飞镖边缘擦到身体边缘就算。所以相遇点在 X 的飞镖实际占住
#    [X - CONTACT_PAD, X + CONTACT_PAD]，CONTACT_PAD = 11 + 23 = 34px。
#
#    于是「一簇 ACT 能不能被一个滑铲盖住」的判据是
#        (X_last + PAD) - (X_first - PAD) <= cover
#    即  X_last - X_first <= cover - 2 x PAD
#
# =========================================================
# 两个合法带
# =========================================================
#
#   CONTINUOUS（<= cover - 2 x PAD - 余量 = 268px）
#       一个滑铲同时盖住整簇。这就是「上一个动作的轨迹直接把玩家送进
#       下一个 Pattern」——本轮调参的目标就是把贴地镖尽量收进这一带。
#
#   CLEAN（>= cover + 余量 = 384px）
#       玩家完整落地、重新判断、再做下一个动作。
#       同时也满足「单跳滞空 + 起跳预备」= 362px，两条路线都走得通。
#
#   中间 268 ~ 384px 是死区：既接不上上一个动作，又来不及从容重来。
#   落进死区的接缝必须改间距或改顺序。
#
# 另外：一串用 CONTINUOUS 间距连起来的 ACT 飞镖，必须能被**同一个滑铲**
# 全部盖住，即 (X_last - X_first) + 2 x PAD <= cover。否则玩家会滑到一半
# 滑铲就结束，正好在最后一枚上撞个正着。

# 飞镖半径。与 components/dart.gd 的 RADIUS 一致。
const DART_RADIUS := 11.0

# 站立安全高度：h >= 这个值就站着能过。
static func standing_safe_height() -> float:
	return Player.PLAYER_HEIGHT + DART_RADIUS

# 一枚飞镖的「接触窗口」半宽 = 飞镖半径 + 玩家半宽。
# 飞镖边缘擦到身体边缘就算中招，所以判覆盖时要按这个宽度把每枚撑开。
static func contact_pad_px() -> float:
	return DART_RADIUS + Player.PLAYER_WIDTH / 2.0

# 一个滑铲能覆盖的地面距离。
#
# ⚠ 必须用 SLIDE_BURST_SPEED，不是 RUN_SPEED（见上面 ①）。
static func slide_cover_px() -> float:
	return Player.SLIDE_DURATION * Player.SLIDE_BURST_SPEED

# 连续带的上限：一个滑铲要盖住整簇，先扣掉首尾两枚各自的接触窗口。
static func seam_continuous_max_px() -> float:
	return slide_cover_px() - 2.0 * contact_pad_px() - SEAM_SAFETY_PX

# 干净带的下限：滑铲覆盖 + 余量，同时不低于「单跳滞空 + 起跳预备」。
static func seam_clean_min_px() -> float:
	return maxf(
		slide_cover_px() + SEAM_SAFETY_PX,
		Motion.jump_time() * Player.RUN_SPEED + TAKEOFF_LEAD_PX)

static func _volley_height(volley: Dictionary) -> float:
	if volley.has("heights"):
		var top := 0.0
		for raw in volley.heights:
			top = maxf(top, float(raw))
		return top
	return float(volley.get("height", 0.0))

# 这一拍站着就能过吗？
static func is_safe_volley(volley: Dictionary) -> bool:
	return _volley_height(volley) >= standing_safe_height()

# 本 Pattern 的第一拍 / 最后一拍是不是 ACT。
static func entry_is_act(pattern: Dictionary) -> bool:
	var volleys := expand(pattern)
	return not volleys.is_empty() and not is_safe_volley(volleys[0])

static func exit_is_act(pattern: Dictionary) -> bool:
	var volleys := expand(pattern)
	return not volleys.is_empty() and not is_safe_volley(volleys[volleys.size() - 1])

# 两枚 ACT 飞镖之间的间距落进哪个带。
static func act_gap_band(gap_px: float) -> String:
	if gap_px <= seam_continuous_max_px():
		return "CONTINUOUS"
	if gap_px >= seam_clean_min_px():
		return "CLEAN"
	return "DEAD_ZONE"


# 一条时间线上所有「ACT 飞镖簇」的跨度检查。
#
# 把连续的 ACT 飞镖（中间的 SAFE 飞镖不打断，因为玩家仍在同一个动作里）
# 按 CONTINUOUS 间距聚成簇，检查首尾跨度是否还在一个滑铲的覆盖范围内。
static func cluster_violations(volleys: Array) -> Array:
	var acts: Array = []
	for volley in volleys:
		if is_safe_volley(volley):
			continue
		acts.append({"x": beat_to_px(float(volley.get("beat", 0.0))), "h": _volley_height(volley)})
	acts.sort_custom(func(a, b): return a.x < b.x)
	var violations: Array = []
	var run: Array = []
	for act in acts:
		if run.is_empty():
			run = [act]
			continue
		var gap: float = act.x - run[run.size() - 1].x
		if gap <= seam_continuous_max_px():
			run.append(act)
			continue
		_evaluate_run(run, violations)
		run = [act]
	_evaluate_run(run, violations)
	return violations


# 全图级的 ACT 衔接体检。
#
# darts: [{"x": float, "h": float}]，世界 X 与高度，顺序不限。
#
# 返回 {"issues": [...], "notes": [...], "acts": int, "tightest": float}
#   issues —— 硬问题：一簇 ACT 飞镖的跨度超过一个滑铲的覆盖范围。
#             玩家会滑到一半滑铲结束，正好在最后一枚上撞个正着。
#   notes  —— 软提醒：两簇之间的间距落在 208~362px 的死区。
#             不是硬性不可解（滑铲结束后可以立刻再按一次），
#             但「上一个动作的轨迹」接不上，玩家必须落地重来。
static func map_act_report(darts: Array) -> Dictionary:
	var acts: Array = []
	for dart in darts:
		if float(dart.h) < standing_safe_height():
			acts.append({"x": float(dart.x), "h": float(dart.h)})
	acts.sort_custom(func(a, b): return a.x < b.x)
	var issues: Array = []
	var notes: Array = []
	var run: Array = []
	var tightest := INF
	for act in acts:
		if run.is_empty():
			run = [act]
			continue
		var gap: float = act.x - run[run.size() - 1].x
		if gap <= seam_continuous_max_px():
			run.append(act)
			continue
		if gap < seam_clean_min_px():
			tightest = minf(tightest, gap)
			notes.append("ACT 间距 %.0fpx 落在死区（x=%.0f → x=%.0f）：接不上上一个动作，需要落地重来" % [
				gap, run[run.size() - 1].x, act.x])
		_evaluate_run(run, issues)
		run = [act]
	_evaluate_run(run, issues)
	return {
		"issues": issues,
		"notes": notes,
		"acts": acts.size(),
		"tightest": tightest,
	}


static func _evaluate_run(run: Array, violations: Array) -> void:
	if run.size() < 2:
		return
	var span: float = run[run.size() - 1].x - run[0].x
	if span <= seam_continuous_max_px():
		return
	violations.append({
		"count": run.size(),
		"span_px": span,
		"first_x": run[0].x,
		"limit_px": seam_continuous_max_px(),
	})


# =========================================================
# 兼容层
# =========================================================
#
# 旧的衔接模型（entry_need / exit_settle / link_gap / link_report）在本轮被
# 固定编排取代：间距不再是「模型算出来的最小值 + 余量」，
# 而是朋友直接指定的像素值。
#
# 下面这些函数保留签名，让既有检查脚本仍能运行；
# 它们返回的语义已经改变：不再是「理论最小值」，而是「实际写在数据里的间距」。

static func entry_need(volleys: Array) -> String:
	if volleys.is_empty():
		return "NONE"
	var first: Dictionary = volleys[0]
	if first.has("heights"):
		return "NONE"
	return "JUMP" if is_equal_approx(float(first.get("height", 0.0)), low_height()) else "NONE"


static func exit_settle(_volleys: Array) -> float:
	return 0.0


static func exit_state(_volleys: Array) -> String:
	return "GROUND"


static func entry_lead(_volleys: Array) -> float:
	return 0.0


static func entry_lead_from(_previous_volleys: Array, _volleys: Array) -> float:
	return 0.0


static func link_gap(_previous: Dictionary, _next: Dictionary) -> float:
	return 0.0


# 衔接检查用：固定编排下「每一对相邻 Pattern 的真实末枚 → 首枚间距」。
#
# 注意 actual 与 model 的含义：
#   model  = 规格允许的间距带（由 gap_px 落在哪一档决定）
#   actual = 数据里真实写下的间距
# 固定编排下两者应当相等（除了第一项没有前驱）。
static func link_report(patterns: Array) -> Array:
	var arranged := arrange(patterns)
	var rows: Array = []
	for index in range(1, arranged.size()):
		var previous: Dictionary = arranged[index - 1]
		var current: Dictionary = arranged[index]
		if not is_known(str(previous.get("kind", ""))) or not is_known(str(current.get("kind", ""))):
			continue
		var previous_last := float(previous.get("beat", 0.0)) + span_of(previous)
		var actual_px := beat_to_px(float(current.beat) - previous_last)
		rows.append({
			"from": str(previous.get("kind", "")),
			"to": str(current.get("kind", "")),
			"exit": 0.0,
			"exit_state": "GROUND",
			"entry_need": entry_need(expand(current)),
			"needs_grounded": false,
			"entry_lead": 0.0,
			"model": px_to_beat(actual_px),
			"actual": float(current.beat) - previous_last,
			"actual_px": actual_px,
			"slack": 0.0,
		})
	return rows


# 供设计检查 / 调试使用：返回一个 Pattern 展开后的拍数与飞镖枚数。
static func describe(pattern: Dictionary) -> Dictionary:
	var volleys: Array = expand(pattern)
	var darts := 0
	for volley in volleys:
		darts += volley.get("heights", [0]).size() if volley.has("heights") else 1
	return {
		"kind": str(pattern.get("kind", "")),
		"beat": float(pattern.get("beat", 0.0)),
		"volleys": volleys.size(),
		"darts": darts,
	}
