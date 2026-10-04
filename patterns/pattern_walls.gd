class_name PatternWalls
extends RefCounted

const Layouts := preload("res://patterns/pattern_event.gd")
const DART := preload("res://patterns/scenes/Shuriken.tscn")
const Motion := preload("res://patterns/player_motion_profile.gd")
const MIN_HEIGHT := 14.0
const MAX_HEIGHT := 310.0
const ROW_SPACING := 28.0
const DART_RADIUS := 11.0
const GAP_DIFFICULTY_STEP := 10.0

static func gap_size(parameters: Dictionary, level: int) -> float:
	return float(parameters.get("safe_gap_size", parameters.get("gap_size", 116.0))) + (3 - level) * GAP_DIFFICULTY_STEP

static func append_wall(plan: Dictionary, parameters: Dictionary, level: int, time := 0.0, gap_height := -1.0) -> void:
	var gap: float = parameters.get("safe_gap_position", 110.0) if gap_height < 0.0 else gap_height
	var size := gap_size(parameters, level)
	var speed: float = parameters.get("wall_speed", 240.0)
	var distance: float = parameters.get("spawn_distance", 650.0)
	var spawn_x := Motion.RUN_SPEED * time + distance
	plan.gaps.append({"rect": Rect2(spawn_x - DART_RADIUS, -gap - size / 2.0, DART_RADIUS * 2.0, size), "time": time, "speed": speed})
	for row in int((MAX_HEIGHT - MIN_HEIGHT) / ROW_SPACING) + 1:
		var height := MIN_HEIGHT + row * ROW_SPACING
		if absf(height - gap) < size / 2.0 + DART_RADIUS:
			continue
		var event := Layouts.new()
		event.obstacle_scene = DART
		event.spawn_time = time
		event.position_offset = Vector2(spawn_x, -height)
		event.speed = speed
		event.preview_kind = Layouts.PreviewKind.DART
		plan.events.append(event)
