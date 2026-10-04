class_name PatternCompiler
extends RefCounted

const Layouts := preload("res://patterns/pattern_layouts.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const Player := preload("res://player.gd")
const DartWave := preload("res://patterns/dart_wave_layout.gd")
const JumpWave := preload("res://patterns/jump_wave_layout.gd")
const RopeWave := preload("res://patterns/rope_wave_layout.gd")
const PlatformDartWave := preload("res://patterns/platform_dart_wave_layout.gd")
const NinjaWave := preload("res://patterns/ninja_wave_layout.gd")
const ActionPhrase := preload("res://patterns/action_phrase_layout.gd")
const MIN_REACTION_TIME := 0.45
const GAP_MARGIN := 22.0
const PROJECTILE_LIFETIME := 3.5
# 飞镖碰撞半径；用于「水平飞镖是否留出可读空间」的空间验证。
# 与 components/dart.gd 的 RADIUS 保持一致。
const DART_CLEARANCE_RADIUS := 11.0

static func compile(data: ObstaclePatternData, difficulty: int, modifier: int, recovery: RecoverySection) -> Dictionary:
	if data.template == "ACTION_PHRASE":
		return ActionPhrase.compile(data, modifier, recovery)
	if data.template == "PLATFORM_DART_WAVE":
		return PlatformDartWave.compile(data, modifier, recovery)
	if data.template == "NINJA_WAVE":
		return NinjaWave.compile(data, modifier, recovery)
	if data.template == "ROPE_WAVE":
		return RopeWave.compile(data, modifier, recovery)
	if data.template == "DART_WAVE":
		return DartWave.compile(data, difficulty, modifier, recovery)
	if data.template == "JUMP_WAVE":
		return JumpWave.compile(data, modifier, recovery)
	var plan := Layouts.build(data, clampi(difficulty, 1, 5))
	plan["needs_manual_playtest"] = true
	if data.duration <= 0 or data.length <= 0 or data.start_delay < 0 or data.speed_multiplier <= 0:
		plan.issues.append("Pattern 时长、长度和速度倍率必须为正，延迟不能为负")
	if recovery.duration < 0.5 or recovery.duration > 2.0:
		plan.issues.append("Recovery 时长必须为 0.5~2 秒")
	if not Modifier.supported(data, modifier) or (data.mirror and not data.supports_mirror):
		plan.issues.append("此模板不支持所选空间/顺序变换")
	var factor := Modifier.speed_factor(data, modifier) * (1.0 + (clampi(difficulty, 1, 5) - 3) * 0.04)
	for event in plan.events:
		event.speed *= factor
		event.spawn_time += data.start_delay
		event.position_offset.x += data.start_delay * Motion.RUN_SPEED
	for gap in plan.gaps:
		gap.rect.position.x += data.start_delay * Motion.RUN_SPEED
		gap.time += data.start_delay
		gap.speed *= factor
	for index in plan.pits.size():
		plan.pits[index] += Vector2.ONE * data.start_delay * Motion.RUN_SPEED
	for index in plan.recoveries.size():
		plan.recoveries[index] += Vector2.ONE * data.start_delay
	# 布局层可能已经把 duration 抬到「编排真正需要的时长」（见 dart_wave_layout.gd），
	# 这里必须沿用那个值，不能用 data.duration 覆盖回去。
	# 手写 data.duration 只是作者地板，编排才是真值。
	plan["duration"] = data.start_delay + maxf(data.duration, float(plan.get("duration", 0.0)))
	for event in plan.events:
		plan.duration = maxf(plan.duration, event.spawn_time + PROJECTILE_LIFETIME + 0.1 if event.speed > 0 else event.position_offset.x / Motion.RUN_SPEED + 0.8)
	# ---- 长度推导（消灭「无意义空白」）----
	#
	# 旧实现：plan.length = max(data.length, plan.duration * RUN_SPEED)。
	# 问题：ObstaclePatternData 的 duration 默认 4.0 秒、length 默认 1800px，
	# 于是**任何**模板（哪怕只有一枚飞镖、威胁只持续 2 秒）都会被拉长到 4.5 秒 / 1800px，
	# 尾巴上留下大段没有威胁的空白。玩家体验就是「跑 → 一个障碍 → 跑很久」，
	# 这正是 Dart_Introduction 显得「只是在参观障碍模板」的结构性原因。
	#
	# 新实现：先算出「最后一个威胁真正结束的时刻」，把它换算成距离作为
	# 该 Pattern 的最小长度；data.length / data.duration 退化为**可选地板**，
	# 只有作者显式要留白（例如刻意制造节奏空隙）时才需要调高。
	#
	# 威胁结束时刻 = 该障碍不再影响玩家的时间：
	#   * 移动障碍（飞镖 / 飞镖墙）：玩家「相遇」该障碍的时刻 + 一点缓冲。
	#     相遇之后玩家已经把它甩在身后，不需要完整的 PROJECTILE_LIFETIME。
	#     早期版本错误地加上整个生命周期，反而把动作句拉得更长。
	#   * 静止障碍：玩家跑过它所需时间 + 一点缓冲。
	var threat_end := 0.0
	for event in plan.events:
		var passed: float
		if event.speed > 0.0:
			var closing: float = Motion.RUN_SPEED - event.speed * event.direction.normalized().x
			var distance: float = event.position_offset.x - event.spawn_time * Motion.RUN_SPEED
			var reaction: float = distance / maxf(1.0, closing)
			passed = event.spawn_time + reaction + 0.45
		else:
			passed = event.position_offset.x / Motion.RUN_SPEED + 0.3
		# 长度必须同时覆盖「出生点在 Pattern 内」与「相遇后仍有余量」。
		# 移动障碍的出生点由 position_offset.x 决定，往往比相遇时刻更靠后
		#（飞镖出生在玩家前方，玩家要先跑到它才相遇）。
		var spawn_extent: float = event.position_offset.x / Motion.RUN_SPEED + 0.1
		threat_end = maxf(threat_end, maxf(passed, spawn_extent))
	for pit in plan.pits:
		threat_end = maxf(threat_end, pit.y / Motion.RUN_SPEED + 0.3)
	for gap in plan.gaps:
		threat_end = maxf(threat_end, (gap.rect.position.x + gap.rect.size.x) / Motion.RUN_SPEED + 0.3)
	var needed: float = threat_end * Motion.RUN_SPEED
	plan["threat_end"] = threat_end
	plan["needed_length"] = needed
	# 只有显式提供 duration / length 地板时才额外留白。
	var explicit_floor: float = maxf(data.length, data.duration * Motion.RUN_SPEED)
	plan["length"] = maxf(needed, explicit_floor) if data.duration > 4.0 or data.length > 1800.0 else needed
	plan["recovery_length"] = recovery.distance(Motion.RUN_SPEED)
	if plan.issues.is_empty():
		Modifier.apply(plan, data, modifier, recovery)
	plan.events.sort_custom(func(a: PatternEvent, b: PatternEvent) -> bool: return a.spawn_time < b.spawn_time)
	validate(plan)
	return plan

# 复刻 components/combat_target.gd::swept_shape 的判定：
# 玩家碰撞盒在 vertical_offset 处，grow(DART_CLEARANCE_RADIUS) 后
# 是否与「水平飞行的飞镖」所在水平带相交。
# dart_y 为飞镖中心的 y；玩家站立时脚底在 y = 0（高度空间以地面为 0）。
static func dart_hits_body(dart_y: float, vertical_offset: float) -> bool:
	var body_top: float = -Motion.BODY_SIZE.y + vertical_offset
	var rect := Rect2(Vector2(0.0, body_top), Vector2(Motion.BODY_SIZE.x, Motion.BODY_SIZE.y))
	var grown := rect.grow(DART_CLEARANCE_RADIUS)
	var seg_y: float = dart_y
	return grown.has_point(Vector2(grown.position.x - 1.0, seg_y)) \
		or grown.has_point(Vector2(grown.end.x + 1.0, seg_y))

static func validate(plan: Dictionary) -> void:
	if plan.events.is_empty():
		plan.issues.append("Pattern 没有事件")
	for event in plan.events:
		if event.obstacle_scene == null or event.spawn_time < 0 or event.speed < 0:
			plan.issues.append("事件缺少场景或时间/速度为负")
		if event.speed > 0 and event.direction.is_zero_approx():
			plan.issues.append("移动事件必须提供非零方向")
		var distance: float = event.position_offset.x - event.spawn_time * Motion.RUN_SPEED
		var closing_speed: float = Motion.RUN_SPEED - event.speed * event.direction.normalized().x
		if event.speed > 0 and (closing_speed <= 0 or distance / maxf(1.0, closing_speed) < MIN_REACTION_TIME):
			plan.issues.append("预计反应时间小于 0.45 秒")
		if event.preview_kind == PatternEvent.PreviewKind.SPIKE and (event.preview_size.x <= 0 or event.preview_size.x + Motion.BODY_SIZE.x > Motion.RUN_SPEED * Motion.jump_time()):
			plan.issues.append("地刺宽度需为正且不能超过单跳跨度减碰撞箱宽度")
		if event.position_offset.x + event.preview_size.x > plan.length:
			plan.issues.append("出生点超出 Pattern 长度")
	plan.pits.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var last_pit_end := 0.0
	for pit in plan.pits:
		if pit.x < last_pit_end:
			plan.issues.append("坑范围不能重叠")
		last_pit_end = pit.y
		if pit.x < 0 or pit.y <= pit.x or pit.y > plan.length:
			plan.issues.append("坑范围必须在 Pattern 内且起点小于终点")
		if pit.y - pit.x + Motion.BODY_SIZE.x > Motion.RUN_SPEED * Motion.jump_time():
			plan.issues.append("坑宽加碰撞箱超过完整单跳跨度")
	for gap in plan.gaps:
		if gap.rect.size.y < Motion.BODY_SIZE.y + GAP_MARGIN:
			plan.issues.append("安全口小于角色高度加 22px 容错")
		var height: float = -gap.rect.get_center().y
		if height > Motion.double_jump_height() + Motion.BODY_SIZE.y / 2.0:
			plan.issues.append("安全口中心超过理论二段跳可达高度")
	# 水平飞镖的空间可达性验证。
	#
	# 只做一条最保守、无歧义的检查：
	# 这枚飞镖必须能被玩家的「某一种姿态」碰到，
	# 否则它在任何情况下都只是背景装饰，属于参数失误。
	#
	# 姿态集合 = 站立 / 下蹲 / 单跳顶点 / 二段跳顶点。
	#
	# 注意：这里**不**要求「站立一定会撞到」。
	# P21 / P22 这类模板的顶部飞镖是「天花板」，作用是限制玩家跳太高，
	# 站立时本来就碰不到它 —— 那是正确设计，不是失误。
	#
	# 该检查默认关闭：它是「关卡设计守则」，不是「数据合法性」。
	# 由 dart_section_design_check 等设计工具显式打开，
	# 避免影响 library 下既有模板的合法性判定。
	if plan.get("check_dart_reachability", false) and plan.gaps.is_empty():
		for event in plan.events:
			if event.preview_kind != PatternEvent.PreviewKind.DART or event.speed <= 0.0:
				continue
			var dart_y: float = event.position_offset.y
			var reachable: bool = false
			for offset in [
				0.0,
				Motion.BODY_SIZE.y - Player.SLIDE_HEIGHT,
				-Motion.jump_height(),
				-Motion.double_jump_height(),
			]:
				if dart_hits_body(dart_y - offset, 0.0):
					reachable = true
					break
			if not reachable:
				plan.issues.append(
					"飞镖高度 %.0f 在任何玩家姿态下都无法被碰到" % -dart_y
				)
