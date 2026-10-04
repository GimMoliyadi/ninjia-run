class_name PatternModifier
extends RefCounted

enum Kind { NORMAL, FAST, SLOW, MIRRORED, DOUBLE, REVERSE }
const LABELS := ["NORMAL", "FAST", "SLOW", "MIRRORED", "DOUBLE", "REVERSE"]
const FAST_MULTIPLIER := 1.2
const SLOW_MULTIPLIER := 0.85
const MIRROR_HEIGHT := 160.0

static func supported(data: ObstaclePatternData, modifier: int) -> bool:
	if modifier in [Kind.FAST, Kind.SLOW]:
		return data.supports_speed
	if modifier == Kind.MIRRORED:
		return data.supports_mirror
	if modifier == Kind.REVERSE:
		return data.supports_reverse
	return true

static func speed_factor(data: ObstaclePatternData, modifier: int) -> float:
	var factor := FAST_MULTIPLIER if modifier == Kind.FAST else (SLOW_MULTIPLIER if modifier == Kind.SLOW else 1.0)
	return data.speed_multiplier * factor

static func apply(plan: Dictionary, data: ObstaclePatternData, modifier: int, recovery: RecoverySection) -> void:
	if data.mirror or modifier == Kind.MIRRORED:
		for event in plan.events:
			event.position_offset.y = -2.0 * MIRROR_HEIGHT - event.position_offset.y
			event.direction.y *= -1.0
		for gap in plan.gaps:
			gap.rect.position.y = -2.0 * MIRROR_HEIGHT - gap.rect.end.y
	if modifier == Kind.REVERSE:
		reverse_events(plan)
	if modifier == Kind.DOUBLE:
		double_pattern(plan, recovery)

static func reverse_events(plan: Dictionary) -> void:
	var last := 0.0
	var first := INF
	for event in plan.events:
		last = maxf(last, event.spawn_time)
		first = minf(first, event.spawn_time)
	for event in plan.events:
		var previous: float = event.spawn_time
		event.spawn_time = first + last - previous
		event.position_offset.x += (event.spawn_time - previous) * PlayerMotionProfile.RUN_SPEED
	for gap in plan.gaps:
		var previous: float = gap.time
		gap.time = first + last - previous
		gap.rect.position.x += (gap.time - previous) * PlayerMotionProfile.RUN_SPEED

static func double_pattern(plan: Dictionary, recovery: RecoverySection) -> void:
	var start := maxf(plan.duration, plan.length / PlayerMotionProfile.RUN_SPEED)
	var offset: float = start + recovery.duration
	var distance := offset * PlayerMotionProfile.RUN_SPEED
	for event in plan.events.duplicate():
		var copy: PatternEvent = event.duplicate(true)
		copy.spawn_time += offset
		copy.position_offset.x += distance
		plan.events.append(copy)
	for gap in plan.gaps.duplicate(true):
		gap.time += offset
		gap.rect.position.x += distance
		plan.gaps.append(gap)
	for pit in plan.pits.duplicate():
		plan.pits.append(pit + Vector2.ONE * distance)
	for window in plan.recoveries.duplicate():
		plan.recoveries.append(window + Vector2.ONE * offset)
	plan.recoveries.append(Vector2(start, offset))
	plan.duration += offset
	plan.length += distance
