extends RefCounted

const Motion := preload("res://patterns/player_motion_profile.gd")
const JumpWave := preload("res://patterns/jump_wave_layout.gd")
const Dart := preload("res://components/dart.gd")

const MINIMUM_COIN_CLEARANCE := 52.0
const COIN_RADIUS := 14.0
const SAFE_MARGIN := 64.0
const TRAIL_SPACING := 64.0
const PLATFORM_EDGE_MARGIN := 40.0
const PLATFORM_COIN_HEIGHT := Motion.BODY_SIZE.y
const SPIKE_APPROACH := Motion.RUN_SPEED * 0.3
const SPIKE_GROUP_GAP := Motion.RUN_SPEED * 0.4
const JUMP_COIN_HEIGHT := Motion.BODY_SIZE.y * 0.5
const JUMP_COIN_CLEARANCE := COIN_RADIUS + 6.0
const JUMP_FOOT_MARGIN := 4.0
const LANDING_EPSILON := 0.05

static func jump_points(runners: Array[PatternRunner], section_length: float) -> Array[Vector2]:
	var spikes: Array[Rect2] = []
	var platforms: Array[Rect2] = []
	var darts: Array[Vector2] = []
	for runner in runners:
		if not runner.plan.get("jump_layout", false):
			continue
		for event in runner.plan.events:
			if event.obstacle_scene == JumpWave.PILLAR or event.obstacle_scene == JumpWave.SPIKES:
				var obstacle := Rect2(
					Vector2(runner.position.x + event.position_offset.x, -event.preview_size.y),
					event.preview_size
				)
				if event.obstacle_scene == JumpWave.PILLAR:
					platforms.append(obstacle)
				else:
					spikes.append(obstacle)
			elif event.preview_kind == PatternEvent.PreviewKind.DART and event.speed > 0.0:
				darts.append(_dart_encounter(event, runner.position.x))
	spikes.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	platforms.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var hazards := spikes.duplicate()
	hazards.append_array(platforms)
	var points: Array[Vector2] = []
	_add_spike_trails(points, spikes, hazards, darts, section_length)
	_add_platform_trails(points, platforms, hazards, darts)
	return points

static func rope_points(runners: Array[PatternRunner], section_length: float) -> Array[Vector2]:
	var darts: Array[Vector2] = []
	var spikes: Array[Rect2] = []
	for runner in runners:
		if not runner.plan.has("rope_actions"):
			continue
		for event in runner.plan.events:
			if event.preview_kind == PatternEvent.PreviewKind.DART and event.speed > 0.0:
				darts.append(_dart_encounter(event, runner.position.x))
			elif event.preview_kind == PatternEvent.PreviewKind.SPIKE:
				var y_scale: float = event.optional_parameters.get("scale", Vector2.ONE).y
				var top: float = -event.preview_size.y if y_scale > 0.0 else 0.0
				spikes.append(Rect2(
					Vector2(runner.position.x + event.position_offset.x, top),
					event.preview_size
				))
	darts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var points: Array[Vector2] = []
	if darts.is_empty():
		return points
	var group: Array[Vector2] = [darts[0]]
	var start_extension := TRAIL_SPACING
	for index in range(1, darts.size()):
		if signf(darts[index].y) == signf(group.back().y) and darts[index].x - group.back().x <= SPIKE_GROUP_GAP:
			group.append(darts[index])
		else:
			var switches_side := signf(darts[index].y) != signf(group.back().y)
			_add_rope_line(points, group, spikes, darts, section_length, start_extension, 0.0 if switches_side else TRAIL_SPACING)
			group = [darts[index]]
			start_extension = 0.0 if switches_side else TRAIL_SPACING
	_add_rope_line(points, group, spikes, darts, section_length, start_extension, TRAIL_SPACING)
	return points

static func _dart_encounter(event: PatternEvent, runner_x: float) -> Vector2:
	var approach := (
		event.position_offset.x - Motion.RUN_SPEED * event.spawn_time
	) / (Motion.RUN_SPEED + event.speed)
	return Vector2(runner_x + Motion.RUN_SPEED * (event.spawn_time + approach), event.position_offset.y)

static func _add_rope_line(
	points: Array[Vector2], group: Array[Vector2], spikes: Array[Rect2],
	darts: Array[Vector2], section_length: float, start_extension: float, end_extension: float
) -> void:
	var start := maxf(0.0, group[0].x - start_extension)
	var end := minf(section_length, group.back().x + end_extension)
	if end <= start:
		return
	var count := clampi(ceili((end - start) / TRAIL_SPACING) + 1, 3, 9)
	var coin_y := -signf(group[0].y) * PLATFORM_COIN_HEIGHT
	for index in count:
		var x := lerpf(start, end, float(index) / float(count - 1))
		_append_clear(points, Vector2(x, coin_y), spikes, darts)

static func _add_spike_trails(
	points: Array[Vector2], spikes: Array[Rect2], hazards: Array[Rect2],
	darts: Array[Vector2], section_length: float
) -> void:
	if spikes.is_empty():
		return
	var group: Array[Rect2] = [spikes[0]]
	for index in range(1, spikes.size()):
		if spikes[index].position.x - group.back().end.x <= SPIKE_GROUP_GAP:
			group.append(spikes[index])
		else:
			_add_spike_arc(points, group, hazards, darts, section_length)
			group = [spikes[index]]
	_add_spike_arc(points, group, hazards, darts, section_length)

static func _add_spike_arc(
	points: Array[Vector2], group: Array[Rect2], hazards: Array[Rect2],
	darts: Array[Vector2], section_length: float
) -> void:
	var obstacle := group[0]
	for spike in group:
		obstacle = obstacle.merge(spike)
	var path := _obstacle_jump_path(obstacle, Vector2(0.0, section_length), hazards)
	if path.is_empty() and group.size() > 1:
		for spike in group:
			_append_jump_coins(points, _obstacle_jump_path(spike, Vector2(0.0, section_length), hazards), hazards, darts)
		return
	_append_jump_coins(points, path, hazards, darts)

static func obstacle_jump_trail(obstacle: Rect2, bounds: Vector2) -> Array[Vector2]:
	var hazards: Array[Rect2] = [obstacle]
	var points: Array[Vector2] = []
	_append_jump_coins(points, _obstacle_jump_path(obstacle, bounds, hazards), hazards, [])
	return points

static func _obstacle_jump_path(obstacle: Rect2, bounds: Vector2, hazards: Array[Rect2]) -> PackedVector2Array:
	for double_jump in [false, true]:
		var path := Motion.sample_jump_path(0.0, double_jump)
		if path.is_empty():
			continue
		var clearance_start := INF
		var clearance_end := -INF
		var apex := Vector2.ZERO
		for point in path:
			if point.y < apex.y:
				apex = point
			if point.y <= obstacle.position.y - JUMP_FOOT_MARGIN:
				clearance_start = minf(clearance_start, point.x)
				clearance_end = maxf(clearance_end, point.x)
		var earliest := maxf(bounds.x, obstacle.end.x + Motion.BODY_SIZE.x * 0.5 - clearance_end)
		var latest := minf(bounds.y - path[-1].x, obstacle.position.x - Motion.BODY_SIZE.x * 0.5 - clearance_start)
		if earliest > latest:
			continue
		var preferred := obstacle.get_center().x - apex.x
		for takeoff in [clampf(preferred, earliest, latest), earliest, latest]:
			var placed := _place_jump_path(path, Vector2(takeoff, 0.0))
			if _jump_path_clear(placed, hazards):
				return placed
	return PackedVector2Array()

static func _add_platform_trails(
	points: Array[Vector2], platforms: Array[Rect2],
	hazards: Array[Rect2], darts: Array[Vector2]
) -> void:
	var arcs: Array[PackedVector2Array] = []
	for index in range(platforms.size() - 1):
		var left := platforms[index]
		var right := platforms[index + 1]
		var has_dart := darts.any(func(dart: Vector2) -> bool:
			return dart.x >= left.end.x - SAFE_MARGIN and dart.x <= right.position.x + SAFE_MARGIN)
		var path := PackedVector2Array()
		if not has_dart and right.position.x - left.end.x >= TRAIL_SPACING:
			path = _platform_jump_path(left, right, hazards, darts)
		arcs.append(path)
		_append_jump_coins(points, path, hazards, darts)
	for index in platforms.size():
		var platform := platforms[index]
		var edge_margin := minf(PLATFORM_EDGE_MARGIN, platform.size.x * 0.12)
		var start := platform.position.x + edge_margin
		var end := platform.end.x - edge_margin
		if index > 0 and not arcs[index - 1].is_empty():
			start = maxf(start, arcs[index - 1][-1].x)
		if index < arcs.size() and not arcs[index].is_empty():
			end = minf(end, arcs[index][0].x)
		for dart in darts:
			if dart.x >= platform.position.x and dart.x <= platform.end.x:
				end = minf(end, dart.x - SAFE_MARGIN)
		if end <= start:
			continue
		var count := clampi(ceili((end - start) / TRAIL_SPACING) + 1, 3, 6)
		for step in count:
			var x := lerpf(start, end, float(step) / float(count - 1))
			_append_clear(points, Vector2(x, platform.position.y - JUMP_COIN_HEIGHT), hazards, darts, JUMP_COIN_CLEARANCE)

static func _platform_jump_path(left: Rect2, right: Rect2, hazards: Array[Rect2], darts: Array[Vector2]) -> PackedVector2Array:
	var left_margin := minf(Motion.BODY_SIZE.x * 0.5, left.size.x * 0.25)
	var right_margin := minf(Motion.BODY_SIZE.x * 0.5, right.size.x * 0.25)
	var takeoff_min := left.position.x + left_margin
	var boost := 0.0
	for dart in darts:
		var height := left.position.y - dart.y
		if dart.x >= left.position.x and dart.x <= left.end.x and height > Motion.SLIDE_HEIGHT + Dart.RADIUS and height < Motion.BODY_SIZE.y + Dart.RADIUS:
			boost = Motion.Player.SLIDE_BOOST
			takeoff_min = maxf(takeoff_min, dart.x + Dart.RADIUS + Motion.BODY_SIZE.x * 0.5)
	for double_jump in [false, true]:
		var path := Motion.sample_jump_path(right.position.y - left.position.y, double_jump, boost)
		if path.is_empty():
			continue
		var travel := path[-1].x
		var earliest := maxf(takeoff_min, right.position.x + right_margin - travel)
		var latest := minf(left.end.x - left_margin, right.end.x - right_margin - travel)
		if earliest > latest:
			continue
		for takeoff in [(earliest + latest) * 0.5, latest, earliest]:
			var placed := _place_jump_path(path, Vector2(takeoff, left.position.y))
			if _jump_path_clear(placed, hazards):
				return placed
	return PackedVector2Array()

static func _place_jump_path(path: PackedVector2Array, origin: Vector2) -> PackedVector2Array:
	var placed := PackedVector2Array()
	for point in path:
		placed.append(point + origin)
	return placed

static func _jump_path_clear(path: PackedVector2Array, hazards: Array[Rect2]) -> bool:
	if path.is_empty():
		return false
	for hazard in hazards:
		if hazard.end.x < path[0].x - Motion.BODY_SIZE.x * 0.5 or hazard.position.x > path[-1].x + Motion.BODY_SIZE.x * 0.5:
			continue
		for foot in path:
			var body := Rect2(foot - Vector2(Motion.BODY_SIZE.x * 0.5, Motion.BODY_SIZE.y), Motion.BODY_SIZE - Vector2(0.0, LANDING_EPSILON))
			if body.intersects(hazard):
				return false
	return true

static func _append_jump_coins(points: Array[Vector2], path: PackedVector2Array, hazards: Array[Rect2], darts: Array[Vector2]) -> void:
	if path.is_empty():
		return
	var sampled: Array[Vector2] = [path[0]]
	var last := path[0]
	var apex := path[0]
	for foot in path:
		if foot.y < apex.y:
			apex = foot
		if foot.distance_to(last) >= TRAIL_SPACING:
			sampled.append(foot)
			last = foot
	sampled.append(apex)
	sampled.append(path[-1])
	sampled.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for foot in sampled:
		_append_clear(points, foot - Vector2(0.0, JUMP_COIN_HEIGHT), hazards, darts, JUMP_COIN_CLEARANCE)

static func _append_clear(
	points: Array[Vector2], point: Vector2, hazards: Array[Rect2], darts: Array[Vector2],
	solid_clearance: float = MINIMUM_COIN_CLEARANCE
) -> void:
	for hazard in hazards:
		if distance_to_obstacle(point, hazard) < solid_clearance:
			return
	for dart in darts:
		if point.distance_to(dart) < MINIMUM_COIN_CLEARANCE + Dart.RADIUS:
			return
	for existing in points:
		if point.distance_to(existing) < TRAIL_SPACING * 0.5:
			return
	points.append(point)

static func distance_to_obstacle(point: Vector2, obstacle: Rect2) -> float:
	var closest := Vector2(
		clampf(point.x, obstacle.position.x, obstacle.end.x),
		clampf(point.y, obstacle.position.y, obstacle.end.y)
	)
	return point.distance_to(closest)
