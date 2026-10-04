@tool
class_name PatternPreview
extends Node2D

const Compiler := preload("res://patterns/pattern_compiler.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const PILLAR := preload("res://scenes/JumpPillar.tscn")
const CIRCLE_SEGMENTS := 32
const HAZARD_OUTLINE := Color("d86634")
const HAZARD_FILL := Color(0.95, 0.3, 0.2, 0.13)
const PLATFORM_FILL := Color(0.2, 0.45, 0.35, 0.25)
const PLATFORM_SURFACE := Color("adbb89")
@export var pattern: ObstaclePatternData
@export_range(1, 5) var difficulty := 3
@export_enum("NORMAL", "FAST", "SLOW", "MIRRORED", "DOUBLE", "REVERSE") var modifier := 0
var plan: Dictionary = {}
var runner: PatternRunner
var refresh_remaining := 0.0

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		refresh_remaining -= delta
		if pattern != null and refresh_remaining <= 0.0:
			plan = Compiler.compile(pattern, difficulty, modifier, RecoverySection.new())
			refresh_remaining = 0.5
	queue_redraw()

func _draw() -> void:
	if plan.is_empty():
		return
	draw_rect(Rect2(0, -320, plan.length, 320), Color(0.15, 0.35, 0.5, 0.4), false, 2)
	draw_rect(Rect2(0, -Motion.BODY_SIZE.y, plan.length, Motion.BODY_SIZE.y), Color(0.2, 0.55, 0.9, 0.07))
	for event in plan.events:
		draw_event(event)
	for gap in plan.gaps:
		var rect: Rect2 = gap.rect
		if is_instance_valid(runner) and runner.elapsed > gap.time:
			rect.position.x -= gap.speed * minf(3.5, runner.elapsed - gap.time)
		draw_rect(rect.grow_individual(10, 0, 10, 0), Color(0.1, 0.7, 0.45, 0.22))
	for pit in plan.pits:
		draw_rect(Rect2(pit.x, 0, pit.y - pit.x, 80), Color(0.95, 0.3, 0.15, 0.35))
	for window in plan.recoveries:
		draw_rect(Rect2(window.x * Motion.RUN_SPEED, -320, (window.y - window.x) * Motion.RUN_SPEED, 320), Color(0.6, 0.8, 0.3, 0.08))
	draw_reference_jump()

func draw_event(event: PatternEvent) -> void:
	if event.preview_kind == PatternEvent.PreviewKind.PLATFORM or event.obstacle_scene == PILLAR:
		draw_platform(event)
		return
	var point := event.position_offset
	match event.preview_kind:
		PatternEvent.PreviewKind.SPIKE:
			draw_rect(Rect2(point - Vector2(0, event.preview_size.y), event.preview_size), Color(0.95, 0.3, 0.2, 0.2))
		PatternEvent.PreviewKind.CEILING:
			draw_rect(Rect2(point, event.preview_size), HAZARD_FILL)
		PatternEvent.PreviewKind.BLADE_WHEEL:
			draw_blade_wheel(event)
		PatternEvent.PreviewKind.FALLING_BLADE:
			draw_falling_blade(event)
		_:
			draw_circle(point, 4.0, Color("cc6633"))
			draw_motion_arrow(point, event.direction, 40.0)

func draw_platform(event: PatternEvent) -> void:
	var rect := Rect2(event.position_offset - Vector2(0, event.preview_size.y), event.preview_size)
	var crumbling: bool = float(event.optional_parameters.get("crumble_delay", 0.0)) > 0.0
	draw_rect(rect, HAZARD_FILL if crumbling else PLATFORM_FILL)
	draw_rect(rect, HAZARD_OUTLINE if crumbling else PLATFORM_SURFACE, false, 1.5)
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0.0), PLATFORM_SURFACE, 3.0, true)

func draw_blade_wheel(event: PatternEvent) -> void:
	var radius := event.preview_size.x * 0.5
	var point := event.position_offset
	draw_circle(point, radius, HAZARD_FILL)
	draw_arc(point, radius, 0.0, TAU, CIRCLE_SEGMENTS, HAZARD_OUTLINE, 2.0, true)
	var closing := Motion.RUN_SPEED - event.speed * event.direction.normalized().x
	if event.speed <= 0.0 or closing <= 0.0:
		return
	var approach := (point.x - event.spawn_time * Motion.RUN_SPEED) / closing
	var encounter := point + event.direction.normalized() * event.speed * approach
	draw_line(point, encounter, HAZARD_OUTLINE, 1.0, true)
	draw_arc(encounter, radius, 0.0, TAU, CIRCLE_SEGMENTS, HAZARD_OUTLINE, 1.0, true)
	draw_motion_arrow(encounter, event.direction, radius)

func draw_falling_blade(event: PatternEvent) -> void:
	var radius := event.preview_size.x * 0.5
	var point := event.position_offset
	var drop_distance := event.preview_size.y - event.preview_size.x
	var landing := point + Vector2.DOWN * drop_distance
	var range_outline := HAZARD_OUTLINE
	range_outline.a = 0.4
	draw_rect(Rect2(point - Vector2(radius, 0.0), Vector2(event.preview_size.x, drop_distance)), HAZARD_FILL)
	for center: Vector2 in [point, landing]:
		draw_circle(center, radius, HAZARD_FILL)
		draw_arc(center, radius, 0.0, TAU, CIRCLE_SEGMENTS, HAZARD_OUTLINE, 2.0, true)
	for side: float in [-1.0, 1.0]:
		var inset := Vector2(side * radius, 0.0)
		draw_line(point + inset, landing + inset, range_outline, 1.0, true)
	draw_motion_arrow(point, Vector2.DOWN, drop_distance)

func draw_motion_arrow(point: Vector2, direction: Vector2, length: float) -> void:
	var unit := direction.normalized()
	var tip := point + unit * length
	var wing_length := minf(length * 0.25, 10.0)
	draw_line(point, tip, HAZARD_OUTLINE, 1.5, true)
	for side: float in [-1.0, 1.0]:
		draw_line(tip, tip - unit.rotated(side * 0.4) * wing_length, HAZARD_OUTLINE, 1.5, true)

func draw_reference_jump() -> void:
	var points := PackedVector2Array()
	var apex_time := -Motion.Player.JUMP_SPEED / Motion.Player.ASCENT_GRAVITY
	for index in 33:
		var time := Motion.jump_time() * index / 32.0
		var height := -Motion.Player.JUMP_SPEED * time - Motion.Player.ASCENT_GRAVITY * time * time / 2.0
		if time > apex_time:
			height = Motion.jump_height() - Motion.Player.FALL_GRAVITY * pow(time - apex_time, 2) / 2.0
		points.append(Vector2(180 + Motion.RUN_SPEED * time, -height))
	draw_polyline(points, Color(0.15, 0.5, 0.85, 0.6), 2.0, true)

