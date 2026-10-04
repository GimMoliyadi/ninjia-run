class_name PatternLayouts
extends RefCounted

const SPIKE := preload("res://scenes/Spike.tscn")
const DART := preload("res://patterns/scenes/Shuriken.tscn")
const CEILING := preload("res://scenes/SlideBeam.tscn")
const CeilingBody := preload("res://components/slide_beam.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const Event := preload("res://patterns/pattern_event.gd")
const Walls := preload("res://patterns/pattern_walls.gd")
const SPIKE_HEIGHT := 72.0
const DEFAULT_SPIKE_WIDTH := 24.0
const REACTION_MARGIN := 0.14
const MIN_SPEED_FACTOR := 0.85 * 0.92

static func build(data: ObstaclePatternData, level: int) -> Dictionary:
	var plan := {"events": [], "pits": [], "gaps": [], "recoveries": [], "notes": [], "issues": PackedStringArray()}
	var p := data.parameters
	match data.template:
		"CUSTOM":
			for event in data.events:
				plan.events.append(event.duplicate(true))
			plan.pits = data.pit_ranges.duplicate()
		"P01":
			var positions: Array = p.get("positions", [p.get("position", 520.0)])
			var widths: Array = p.get("spike_widths", [])
			var warning: float = p.get("warning_distance", 520.0)
			for index in positions.size():
				var width: float = widths[index] if index < widths.size() else p.get("spike_width", 24.0)
				var event := spike(positions[index], width * (1.0 + (level - 3) * 0.1))
				event.spawn_time = maxf(0.0, (event.position_offset.x - warning) / Motion.RUN_SPEED)
				plan.events.append(event)
			if warning < Motion.RUN_SPEED * 0.45:
				plan.issues.append("warning_distance 至少需要 0.45 秒的跑动距离")
		"P04":
			plan.events.append(dart(0, p.get("spawn_distance", 600.0), p.get("height", 80.0), p.get("speed", 240.0), p.get("direction", Vector2.LEFT)))
		"P08":
			var first_x: float = p.get("position", 520.0)
			var spacing := Motion.RUN_SPEED * (Motion.fast_fall_time(Motion.jump_height()) + REACTION_MARGIN)
			plan.events.append(spike(first_x, p.get("spike_width", 24.0)))
			plan.events.append(ceiling(first_x + spacing, p.get("ceiling_clearance", 100.0)))
			plan.notes.append("跳后急降间隔 %.0f px = 跑速 × (峰顶急降时间 + %.2fs 容错)" % [spacing, REACTION_MARGIN])
		"P14", "P15", "P16":
			Walls.append_wall(plan, p, level)
		"P17":
			append_gap_switch(plan, p, level)
		"P18":
			append_diagonal(plan, p, level)
		"P21":
			var spike_x: float = p.get("position", 520.0)
			var width: float = p.get("spike_width", 40.0)
			var contact_x := spike_x + width + Motion.RUN_SPEED * Motion.fast_fall_time(Motion.jump_height())
			var speed: float = p.get("speed", 240.0)
			plan.events.append(spike(spike_x, width))
			plan.events.append(dart(0, contact_x * (1.0 + speed / Motion.RUN_SPEED), p.get("height", 205.0), speed))
			plan.notes.append("顶部飞镖相遇点 %.0f px；地刺后预留峰顶急降距离，限制二段跳高度" % contact_x)
		"P22":
			append_pit_ceiling(plan, p, level)
		"P24":
			Walls.append_wall(plan, p, level)
			var contact_x := float(p.get("spawn_distance", 650.0)) * Motion.RUN_SPEED / (Motion.RUN_SPEED + float(p.get("wall_speed", 240.0)))
			var trap_x := contact_x + Motion.RUN_SPEED * Motion.jump_time() * float(p.get("landing_time_ratio", 0.75))
			plan.events.append(spike(trap_x, p.get("spike_width", 44.0)))
			plan.notes.append("落点陷阱 %.0fpx，按飞镖墙相遇点 + 0.75 次单跳时间定位；提前可见，建议二段跳延后落地" % trap_x)
		"P28":
			append_rhythm(plan, data, level)
		"P30":
			append_dart_sentence(plan, p, level)
	return plan

static func append_pit_ceiling(plan: Dictionary, p: Dictionary, level: int) -> void:
	var start: float = p.get("position", 520.0)
	var width := float(p.get("pit_width", Motion.RUN_SPEED * Motion.jump_time() * 0.35)) + (level - 3) * 5.0
	plan.pits.append(Vector2(start, start + width))
	var speed: float = p.get("speed", 220.0)
	var contact_x := start + width / 2.0
	plan.events.append(dart(0, contact_x * (1.0 + speed / Motion.RUN_SPEED), p.get("height", 190.0), speed))
	plan.notes.append("坑宽 %.0fpx，当前单跳跨度 %.0fpx；顶部飞镖限制过高路线，按下急降控制落点" % [width, Motion.RUN_SPEED * Motion.jump_time()])

static func append_rhythm(plan: Dictionary, data: ObstaclePatternData, level: int) -> void:
	var p := data.parameters
	var first_interval: float = p.get("first_interval", 0.35)
	var pause_duration: float = p.get("pause_duration", 1.4)
	var speed: float = p.get("speed", 240.0)
	var distance: float = p.get("spawn_distance", 650.0)
	plan.events.append(dart(0, distance, 80, speed))
	plan.events.append(dart(first_interval, distance, 95, speed))
	if data.final_pattern == null or data.final_pattern.template == "P28":
		plan.issues.append("P28 必须指定非 P28 的 final_pattern，禁止循环组合")
		return
	if first_interval <= 0 or pause_duration < 0.5 or pause_duration > 2.0:
		plan.issues.append("节奏间隔必须为正，Recovery 需要 0.5~2 秒")
	# 等最后一枚飞镖穿过角色范围后再开始留白；按最慢支持速度保守计算。
	var cleared := first_interval + (distance + Motion.BODY_SIZE.x + 22.0) / (Motion.RUN_SPEED + speed * data.speed_multiplier * MIN_SPEED_FACTOR)
	var offset := cleared + pause_duration + data.final_pattern.start_delay
	var final := build(data.final_pattern, level)
	if data.final_pattern.mirror and not data.final_pattern.supports_mirror:
		plan.issues.append("final_pattern 不支持镜像")
	if data.final_pattern.mirror:
		PatternModifier.apply(final, data.final_pattern, PatternModifier.Kind.NORMAL, RecoverySection.new())
	for event in final.events:
		event.speed *= data.final_pattern.speed_multiplier
		event.spawn_time += offset
		event.position_offset.x += offset * Motion.RUN_SPEED
		plan.events.append(event)
	for gap in final.gaps:
		gap.speed *= data.final_pattern.speed_multiplier
		gap.time += offset
		gap.rect.position.x += offset * Motion.RUN_SPEED
		plan.gaps.append(gap)
	for pit in final.pits:
		plan.pits.append(pit + Vector2.ONE * offset * Motion.RUN_SPEED)
	plan.issues.append_array(final.issues)
	plan.recoveries.append(Vector2(cleared, cleared + pause_duration))
	plan.notes.append("发射节奏：0s → %.2fs → %.2fs 空白 → %s" % [first_interval, pause_duration, data.final_pattern.pattern_name])

static func append_gap_switch(plan: Dictionary, p: Dictionary, level: int) -> void:
	var base_count: int = p.get("wall_count", 3)
	var count := clampi(base_count + (-1 if level <= 2 else (1 if level == 5 else 0)), 2, 6)
	var interval := float(p.get("wall_interval", 2.0)) + (3 - level) * 0.15
	var gaps: Array = p.get("gap_positions", [110.0, 165.0, 40.0, 130.0])
	if gaps.is_empty():
		return
	for index in count:
		Walls.append_wall(plan, p, level, index * interval, gaps[index % gaps.size()])
	plan.notes.append("%d 堵墙，间隔 %.2fs；净空 %.0fpx，换位序列为人工配置" % [count, interval, Walls.gap_size(p, level)])

# P30 —— 飞镖动作句（Dart Sentence）。
#
# 与 P04 的关键区别：
#   P04 只发射**一枚**飞镖，前后必然留下大量空白，
#   玩家体验是「跑 → 一个障碍 → 跑」。
#
#   P30 把**若干枚飞镖编排成一句话**：后一枚飞镖出现时，
#   玩家仍在处理前一枚所引发的动作（起跳 / 下落 / 换高度）。
#   因此玩家感受到的是一个连续的小场面，而不是依次参观障碍模板。
#
# 数据结构（parameters）：
#   "darts": Array[Dictionary]，每一项描述一枚飞镖：
#       {"height": float,             # 离地高度（px，正数向上）
#        "delay": float,              # 相对本 Pattern 开始的秒数
#        "distance": float}           # 出生点距玩家进入本 Pattern 的水平距离
#   "speed": float                    # 飞镖飞行速度（向左）
#
# 约束：
#   * 每一枚飞镖的反应窗口仍由 PatternCompiler.validate 统一校验。
#   * 相邻两枚飞镖的时间差必须落在「一个完整单跳滞空时间」附近，
#     才能形成连续动作而不是两道独立题目。这里给出显式提示，
#     真正的判据由编译器与设计检查工具负责。
static func append_dart_sentence(plan: Dictionary, p: Dictionary, level: int) -> void:
	var darts: Array = p.get("darts", [])
	if darts.is_empty():
		plan.issues.append("P30 至少需要一枚飞镖（darts 不能为空）")
		return
	var speed: float = p.get("speed", 200.0)
	var previous_delay := -1.0
	for index in darts.size():
		var dart_spec: Dictionary = darts[index]
		var height: float = dart_spec.get("height", 80.0)
		var delay: float = dart_spec.get("delay", 0.0)
		var distance: float = dart_spec.get(
			"distance",
			Motion.RUN_SPEED * delay + p.get("spawn_distance", 600.0)
		)
		if delay < previous_delay:
			plan.issues.append("P30 飞镖的 delay 必须单调递增（第 %d 枚）" % index)
		previous_delay = delay
		plan.events.append(dart(delay, distance, height, speed))
	# 连续动作判据必须用「相遇时刻」，而不是 delay。
	#
	# 相遇时刻 = delay + distance / RUN_SPEED（玩家跑到飞镖出生点的时间）。
	# 两枚飞镖的 delay 差可能是 1.6s，但只要相遇时刻只差 0.7s，
	# 玩家感受到的就是同一次操作里的两拍。
	# 早期版本误用 delay 差做判据，导致正确的动作句被误报为「退化成独立题目」。
	var jump_time: float = Motion.jump_time()
	var encounters: Array[float] = []
	for index in darts.size():
		var spec: Dictionary = darts[index]
		var d: float = spec.get("delay", 0.0)
		var dist: float = float(spec.get("distance", Motion.RUN_SPEED * d + p.get("spawn_distance", 600.0)))
		encounters.append(d + dist / Motion.RUN_SPEED)
	for index in range(1, encounters.size()):
		var gap: float = encounters[index] - encounters[index - 1]
		if gap < 0.25:
			plan.issues.append("P30 第 %d 与第 %d 枚飞镖相遇间隔 %.2fs，太密，玩家无法形成两次独立操作" % [index - 1, index, gap])
		elif gap > jump_time * 1.5:
			plan.issues.append("P30 第 %d 与第 %d 枚飞镖相遇间隔 %.2fs，超出单个跳跃周期（%.2fs），会退化成两道独立题目" % [index - 1, index, gap, jump_time])
	plan.notes.append(
		"%d 枚飞镖构成一个动作句；相遇间隔 %s；单跳周期 %.2fs，单跳跨度 %.0fpx"
		% [
			darts.size(),
			", ".join(encounters.map(func(e: float) -> String: return "%.2fs" % e)),
			jump_time,
			Motion.RUN_SPEED * jump_time,
		]
	)


static func append_diagonal(plan: Dictionary, p: Dictionary, level: int) -> void:
	var count: int = p.get("count", 5)
	var distance: float = p.get("spawn_distance", 650.0)
	var spacing: float = p.get("x_spacing", 45.0)
	var height: float = p.get("height", 85.0)
	var step: float = p.get("height_step", 30.0)
	for index in clampi(count + (1 if level >= 4 else 0), 2, 12):
		plan.events.append(dart(index * 0.12, distance + index * spacing, height + index * step, p.get("speed", 240.0)))

static func spike(x: float, width: float) -> PatternEvent:
	var event := Event.new()
	event.obstacle_scene = SPIKE
	event.position_offset = Vector2(x, 0)
	event.optional_parameters = {"scale": Vector2(width / DEFAULT_SPIKE_WIDTH, 1)}
	event.preview_kind = Event.PreviewKind.SPIKE
	event.preview_size = Vector2(width, SPIKE_HEIGHT)
	return event

static func ceiling(x: float, clearance: float) -> PatternEvent:
	var event := Event.new()
	event.obstacle_scene = CEILING
	event.position_offset = Vector2(x, -CeilingBody.BASE_SIZE.y - clearance)
	event.preview_kind = Event.PreviewKind.CEILING
	event.preview_size = CeilingBody.BASE_SIZE
	return event

static func dart(time: float, distance: float, height: float, speed: float, direction := Vector2.LEFT) -> PatternEvent:
	var event := Event.new()
	event.obstacle_scene = DART
	event.position_offset = Vector2(Motion.RUN_SPEED * time + distance, -height)
	event.spawn_time = time
	event.speed = speed
	event.direction = direction
	event.preview_kind = Event.PreviewKind.DART
	return event
