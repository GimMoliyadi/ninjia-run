extends RefCounted

const Motion := preload("res://patterns/player_motion_profile.gd")
const Event := preload("res://patterns/pattern_event.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")
const SPIKES := preload("res://scenes/SpikeStrip.tscn")
const PILLAR := preload("res://scenes/JumpPillar.tscn")
const LOOKAHEAD_JUMPS := 3.5
const SPIKE_HEIGHT := 72.0
const LANDING_MARGIN := 0.25

static func compile(data: ObstaclePatternData, modifier: int, recovery: RecoverySection) -> Dictionary:
	var plan := {
		"events": [], "pits": [], "gaps": [], "recoveries": [], "notes": [],
		"issues": PackedStringArray(), "distance_driven": true, "jump_layout": true,
		"duration": data.duration, "length": data.duration * Motion.RUN_SPEED,
		"recovery_length": recovery.distance(Motion.RUN_SPEED), "needs_manual_playtest": true,
	}
	if modifier != Modifier.Kind.NORMAL or data.mirror or not is_zero_approx(data.start_delay):
		plan.issues.append("跳跃 Wave 使用固定空间编排，不支持时间、镜像变体")
	var phrases: Array = data.parameters.get("phrases", [])
	if data.duration <= 0.0 or phrases.is_empty():
		plan.issues.append("跳跃 Wave 必须有正时长与有序 Pattern")
	for phrase in phrases:
		append_phrase(plan, phrase)
	plan.events.sort_custom(func(a: PatternEvent, b: PatternEvent) -> bool: return a.position_offset.x < b.position_offset.x)
	var end := 0.0
	for event in plan.events:
		if event.position_offset.x < end or event.position_offset.x + event.preview_size.x > plan.length - Motion.RUN_SPEED * LANDING_MARGIN:
			plan.issues.append("障碍重叠或没有留出 Wave 出口落地余量")
		end = event.position_offset.x + event.preview_size.x
	plan["threat_end"] = end / Motion.RUN_SPEED
	plan["needed_length"] = end
	carve_platform_pits([plan], PackedFloat64Array([0.0]))
	return plan

static func carve_platform_pits(plans: Array[Dictionary], offsets: PackedFloat64Array) -> void:
	var platforms: Array[Rect2] = []
	var under_platform_pits: Array[Vector2] = []
	for index in plans.size():
		plans[index].pits.clear()
		for event in plans[index].events:
			if event.obstacle_scene == PILLAR:
				var platform := Rect2(Vector2(offsets[index] + event.position_offset.x, 0), event.preview_size)
				platforms.append(platform)
				if event.optional_parameters.get("crumble_over_pit", false):
					under_platform_pits.append(Vector2(platform.position.x, platform.end.x))
	platforms.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	for index in range(1, platforms.size()):
		var previous := platforms[index - 1]
		var current := platforms[index]
		var gap := current.position.x - previous.end.x
		var safe_gap := Motion.safe_double_jump_gap(current.size.y - previous.size.y)
		if gap > 0.0 and (gap <= safe_gap or is_equal_approx(gap, safe_gap)):
			carve_gap(plans, offsets, Vector2(previous.end.x, current.position.x))
	# 拼接会重建 pits；坑上碎台必须从事件参数恢复，不能依赖上一轮的临时坑。
	for pit in under_platform_pits:
		carve_gap(plans, offsets, pit)
	for plan in plans:
		merge_pits(plan)

static func merge_pits(plan: Dictionary) -> void:
	plan.pits.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = []
	for pit in plan.pits:
		if merged.is_empty() or pit.x > merged.back().y:
			merged.append(pit)
		else:
			var previous: Vector2 = merged.back()
			merged[merged.size() - 1] = Vector2(previous.x, maxf(previous.y, pit.y))
	plan.pits = merged

static func carve_gap(plans: Array[Dictionary], offsets: PackedFloat64Array, gap: Vector2) -> void:
	for index in plans.size():
		var local_gap := Vector2(maxf(0.0, gap.x - offsets[index]), minf(plans[index].length, gap.y - offsets[index]))
		if local_gap.y <= local_gap.x:
			continue
		plans[index].pits.append(local_gap)
		# 挖掉地面后同步移除坑内地刺，避免悬空刺带仍伪装成落脚地面。
		plans[index].events = plans[index].events.filter(func(event: PatternEvent) -> bool:
			return event.obstacle_scene != SPIKES or event.position_offset.x + event.preview_size.x <= local_gap.x or event.position_offset.x >= local_gap.y)

static func append_phrase(plan: Dictionary, phrase: Dictionary) -> void:
	var x: float = float(phrase.get("beat", 0.0)) * Motion.RUN_SPEED
	var width: float = float(phrase.get("width_ratio", 1.0)) * Motion.BODY_SIZE.x
	match str(phrase.get("pattern", "")):
		"single_spike":
			append_obstacle(plan, x, Vector2(width, SPIKE_HEIGHT), false)
		"spike_pair":
			var spacing := width + Motion.BODY_SIZE.x * float(phrase.get("spacing_ratio", 0.7))
			append_obstacle(plan, x, Vector2(width, SPIKE_HEIGHT), false)
			append_obstacle(plan, x + spacing, Vector2(width, SPIKE_HEIGHT), false)
		"pillar":
			append_obstacle(plan, x, Vector2(width, Motion.jump_height() * float(phrase.get("height_ratio", 0.6))), true, phrase)
		"pillar_chain", "mixed_chain":
			append_chain(plan, phrase, x, width)
		_:
			plan.issues.append("未知跳跃 Pattern: %s" % phrase.get("pattern", ""))

static func append_chain(plan: Dictionary, phrase: Dictionary, x: float, width: float) -> void:
	var heights: Array = phrase.get("heights", [0.6, 1.1, 0.7])
	var gap := Motion.RUN_SPEED * Motion.jump_time() * float(phrase.get("gap_ratio", 0.45))
	for index in heights.size():
		var at := x + index * (width + gap)
		append_obstacle(plan, at, Vector2(width, Motion.jump_height() * float(heights[index])), true, phrase)
		if phrase.pattern == "mixed_chain" and index < heights.size() - 1:
			var inset := Motion.BODY_SIZE.x * 0.25
			append_obstacle(plan, at + width + inset, Vector2(gap - 2.0 * inset, SPIKE_HEIGHT), false)

static func append_obstacle(plan: Dictionary, x: float, size: Vector2, pillar: bool, phrase: Dictionary = {}) -> PatternEvent:
	if size.x <= 0.0 or size.y <= 0.0 or x < 0.0:
		plan.issues.append("障碍必须有正尺寸且在 Wave 内")
	if size.y > Motion.double_jump_height() - Motion.BODY_SIZE.y * 0.5:
		plan.issues.append("柱高超过二段跳的保守可达范围")
	if not pillar and size.x + Motion.BODY_SIZE.x > Motion.RUN_SPEED * Motion.jump_time():
		plan.issues.append("刺带过宽，没有基准单跳路径")
	var event := Event.new()
	event.obstacle_scene = PILLAR if pillar else SPIKES
	event.position_offset = Vector2(x, 0)
	event.spawn_time = x / Motion.RUN_SPEED - Motion.jump_time() * LOOKAHEAD_JUMPS
	event.optional_parameters = {"size": size}
	if pillar:
		configure_crumble(plan, event, phrase)
	event.preview_kind = Event.PreviewKind.PLATFORM if pillar else Event.PreviewKind.SPIKE
	event.preview_size = size
	plan.events.append(event)
	return event

static func configure_crumble(plan: Dictionary, event: PatternEvent, phrase: Dictionary) -> void:
	var delay_ratio: float = float(phrase.get("crumble_delay_ratio", 0.0))
	if not is_finite(delay_ratio) or delay_ratio < 0.0:
		plan.issues.append("碎台延迟比例必须为有限非负数")
	if phrase.has("crumble_delay_ratio"):
		event.optional_parameters["crumble_delay"] = delay_ratio * Motion.jump_time()
	if phrase.has("crumble_over_pit"):
		var over_pit: bool = bool(phrase.crumble_over_pit)
		event.optional_parameters["crumble_over_pit"] = over_pit
		if over_pit and delay_ratio <= 0.0:
			plan.issues.append("坑上碎台必须设置正的 crumble_delay_ratio")
