extends "res://components/map_module_chunk.gd"

const RopeWave := preload("res://patterns/rope_wave_layout.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const ROPE_WIDTH := 8.0
const DETECTOR_HEIGHT := 14.0
# 平台与绳索跨度的端点判定余量。
# 端点正好重合不算「穿过」：入口地面刚好到绳索起点、出口平台刚好从绳索终点开始，
# 这两处本来就要衔接，不能断绳。
const SPAN_EPSILON := 0.5

func _build_ground() -> void:
	var entry_length := Motion.RUN_SPEED * (Motion.jump_time() + Motion.Player.FLIP_BUFFER_TIME)
	sections[0].runners[0].plan.pits[0].x = entry_length
	super._build_ground()
	var last_section: PatternSection = sections.back()
	var last_runner: PatternRunner = last_section.runners.back()
	var rope_end: float = last_section.position.x + last_runner.position.x + last_runner.plan.length
	build_rope(entry_length, rope_end)
	var actions: Array = []
	for section in sections:
		for runner in section.runners:
			for action in runner.plan.rope_actions:
				var located: Dictionary = action.duplicate()
				for key in ["x", "danger_start", "danger_end"]:
					located[key] += section.position.x + runner.position.x
				actions.append(located)
	for issue in RopeWave.validate_route(actions):
		push_error("绳索地图跨 Wave 动作窗口：" + issue)

# 绳索跨度内被平台占住的区间（世界 X），按起点排序。
#
# 绳索段的地面平台是真正能落脚的地面，不是装饰：绳子从它上方穿过去，
# 玩家会被绳一直扣在平台上方，平台永远踩不到 —— 两套状态互相打架。
# 所以这些区间不铺绳子：绳索分成若干段，玩家跑上平台，再回到绳上。
# 平台因此保持在原本的高度（和绳索、入口地面同一水平），不需要为绳索让位。
#
# 判据只看几何：与绳线同一高度带、且与绳索跨度真正相交。
# 入口地面 / 出口平台都只与绳索端点重合，被 SPAN_EPSILON 排除。
func platform_spans(rope_start: float, rope_end: float) -> Array[Vector2]:
	var rope_y: float = entry.position.y
	var spans: Array[Vector2] = []
	for section in sections:
		for child in section.get_children():
			if not (child is StaticBody2D):
				continue
			var collider: CollisionShape2D = null
			for node in child.get_children():
				if node is CollisionShape2D:
					collider = node
					break
			if collider == null or not (collider.shape is RectangleShape2D):
				continue
			var shape: RectangleShape2D = collider.shape
			var top_y: float = section.position.y + collider.position.y - shape.size.y * 0.5
			if top_y > rope_y or top_y + shape.size.y < rope_y:
				continue
			var center_x: float = section.position.x + collider.position.x
			var left := center_x - shape.size.x * 0.5
			var right := center_x + shape.size.x * 0.5
			if right <= rope_start + SPAN_EPSILON or left >= rope_end - SPAN_EPSILON:
				continue
			spans.append(Vector2(maxf(left, rope_start), minf(right, rope_end)))
	spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return spans

func build_rope(start: float, end: float) -> void:
	var cursor := start
	var index := 1
	for span in platform_spans(start, end):
		build_rope_segment(cursor, span.x, index)
		index += 1
		cursor = span.y
	build_rope_segment(cursor, end, index)

func build_rope_segment(start: float, end: float, index: int) -> void:
	if end - start <= SPAN_EPSILON:
		return
	var rope := Area2D.new()
	rope.name = "Rope" if index == 1 else "Rope%d" % index
	rope.position = Vector2(start, entry.position.y)
	rope.collision_layer = 2
	rope.collision_mask = 0
	rope.add_to_group("rope")
	var line := Line2D.new()
	line.name = "Line"
	line.points = PackedVector2Array([Vector2.ZERO, Vector2(end - start, 0)])
	line.width = ROPE_WIDTH
	line.default_color = Color("d2a749")
	rope.add_child(line)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(end - start, DETECTOR_HEIGHT)
	collider.shape = shape
	collider.position.x = (end - start) * 0.5
	rope.add_child(collider)
	add_child(rope)
