class_name PatternSection
extends Node2D

const Compiler := preload("res://patterns/pattern_compiler.gd")
const Runner := preload("res://patterns/pattern_runner.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const CoinScene := preload("res://scenes/Coin.tscn")
const CoinTrajectory := preload("res://patterns/coin_trajectory_layout.gd")

# 常量名保持历史叫法，避免破坏既有调用点；它表示每个 Pattern 前/后的落地缓冲，
# 数值来自 PlayerMotionProfile，不是手写魔法数字。
const GROUND_THICKNESS := 80.0

# 金币离地高度。取玩家身高的一半左右，跑动中自然经过。
const COIN_HEIGHT := 34.0

# Recovery 段内金币的默认间距。
# 用单跳跨度的一半推导 —— 玩家无需额外操作即可依次吃到。
const COIN_SPACING_RATIO := 0.5
const COIN_ARC_STEP := 18.0
const COIN_EDGE_MARGIN := 20.0

var runners: Array[PatternRunner] = []
var section_length := 0.0
var coin_arc_height := 0.0
var coin_alignment := NAN
var coin_spacing_scale := 1.0

# 每个 Pattern 的调试信息：pattern_name / template / difficulty /
# modifier / stage / start_x / end_x / issues
var pattern_info: Array[Dictionary] = []

# 数据来源，仅用于调试展示；build() 之后被写入。
var data: PatternSectionData


func build(
	entries: Array[Resource],
	player: Node2D,
	difficulty: int,
	modifier: int,
	recovery: RecoverySection = null,
	build_ground_now := true
) -> void:
	# player 允许为 null：编译只依赖数据与 PlayerMotionProfile。
	# 运行时真正需要 player 的地方是 PatternRunner.spawn_event，
	# 调用方（Segment 的 advance）会在玩家进场后补上引用。
	if recovery == null:
		recovery = RecoverySection.new()
	runners.clear()
	pattern_info.clear()
	section_length = 0.0
	for entry_index in entries.size():
		var entry: Resource = entries[entry_index]
		if entry is RecoverySection:
			var distance: float = entry.distance(Motion.RUN_SPEED)
			add_ground(section_length, distance, "Recovery")
			add_coins(entry, section_length, distance)
			pattern_info.append({
				"kind": "recovery",
				"pattern_name": "",
				"display_name": "喘息" if entry.recovery_label.is_empty() else entry.recovery_label,
				"template": "",
				"difficulty": difficulty,
				"modifier": modifier,
				"stage": _stage_label(entry_index),
				"start_x": section_length,
				"end_x": section_length + distance,
				"issues": PackedStringArray(),
			})
			section_length += distance
		elif entry is ObstaclePatternData:
			var pattern: ObstaclePatternData = entry
			# 每个 Pattern 用自己保存的设计难度；入口难度作为兜底。
			var level: int = clampi(
				pattern.difficulty if pattern.difficulty > 0 else difficulty,
				1,
				5
			)
			var plan := Compiler.compile(pattern, level, modifier, recovery)
			var runner := Runner.new()
			runner.name = pattern.pattern_name
			runner.position.x = section_length
			add_child(runner)
			runner.configure(plan, player)
			runners.append(runner)
			pattern_info.append({
				"kind": "pattern",
				"pattern_name": pattern.pattern_name,
				"display_name": pattern.display_name if not pattern.display_name.is_empty() else pattern.pattern_name,
				"template": pattern.template,
				"difficulty": level,
				"modifier": modifier,
				"stage": _stage_label(entry_index),
				"start_x": section_length,
				"end_x": section_length + plan.length,
				"issues": plan.issues,
			})
			if build_ground_now:
				build_ground(plan, section_length)
			section_length += plan.length
		else:
			push_error("Section entries must be ObstaclePatternData or RecoverySection")
	if build_ground_now:
		add_route_coin_trails()


func _stage_label(entry_index: int) -> String:
	if data == null:
		return ""
	return data.stage_for(entry_index)


func build_ground(plan: Dictionary, offset: float) -> void:
	var cursor := 0.0
	for pit in plan.pits:
		add_ground(offset + cursor, pit.x - cursor)
		cursor = pit.y
	add_ground(offset + cursor, plan.length - cursor)


# 在 Recovery 段里铺一排金币，作为「这里可以喘息」的视觉提示。
# 金币是低压力内容：不接触也不会失败，只是提供路径引导与能量。
# 位置按 PlayerMotionProfile 推导，不写死像素。
func add_coins(entry: RecoverySection, start: float, width: float) -> void:
	if entry.coin_count <= 0 or width <= 0.0:
		return
	var count: int = entry.coin_count
	var spacing: float = entry.coin_spacing
	if spacing <= 0.0:
		spacing = Motion.RUN_SPEED * Motion.jump_time() * COIN_SPACING_RATIO
	# 金币均匀分布在 Recovery 段内，两端各留出一个间距的余量。
	var usable: float = maxf(0.0, width - spacing)
	var step: float = usable / float(maxi(1, count - 1)) if count > 1 else 0.0
	var first_x: float = start + spacing * 0.5 if count > 1 else start + width * 0.5
	if not is_nan(coin_alignment) and count > 1:
		var available: float = maxf(0.0, width - COIN_EDGE_MARGIN * 2.0)
		var trail_width: float = minf(spacing * coin_spacing_scale * float(count - 1), available)
		step = trail_width / float(count - 1)
		first_x = start + COIN_EDGE_MARGIN + (available - trail_width) * coin_alignment
	for index in count:
		var coin: Node2D = CoinScene.instantiate()
		var progress: float = float(index) / float(count - 1) if count > 1 else 0.5
		coin.position = Vector2(first_x + step * index, -COIN_HEIGHT - coin_arc_height * sin(PI * progress))
		add_child(coin)


func add_route_coin_trails() -> void:
	var points := CoinTrajectory.jump_points(runners, section_length)
	points.append_array(CoinTrajectory.rope_points(runners, section_length))
	for point in points:
		var coin: Node2D = CoinScene.instantiate()
		coin.position = point
		add_child(coin)


func add_ground(start: float, width: float, label := "Ground") -> void:
	if width <= 0.0:
		return
	var body := StaticBody2D.new()
	body.name = label
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, GROUND_THICKNESS)
	collider.shape = shape
	collider.position = Vector2(start + width / 2.0, GROUND_THICKNESS / 2.0)
	body.add_child(collider)
	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([
		Vector2(start, 0),
		Vector2(start + width, 0),
		Vector2(start + width, GROUND_THICKNESS),
		Vector2(start, GROUND_THICKNESS),
	])
	fill.color = Color("52664e") if label == "Recovery" else Color("293c32")
	body.add_child(fill)
	add_child(body)


func advance(delta: float, player: Node2D, progress_x: float = NAN) -> void:
	if is_nan(progress_x):
		progress_x = player.global_position.x
	for runner in runners:
		runner.player = player
		if runner.plan.get("distance_driven", false):
			runner.advance_distance(progress_x - runner.global_position.x)
		elif player.global_position.x >= runner.global_position.x + runner.plan.length:
			runner.finish()
		elif player.global_position.x >= runner.global_position.x:
			runner.advance(delta)


# =========================================================
# 调试信息（供正式游戏 F1 覆盖层使用）
# =========================================================

# 返回玩家当前所处的 pattern_info 条目；不在任何条目内时返回空字典。
func info_at(global_x: float) -> Dictionary:
	for info in pattern_info:
		if global_x >= global_position.x + float(info.start_x) and global_x < global_position.x + float(info.end_x):
			return info
	return {}


# 返回所有 pattern 条目的简短名称序列，例如 "P04_P04_P14_..." 风格的模板串。
func template_sequence() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for info in pattern_info:
		if info.kind == "pattern":
			parts.append(str(info.template))
	return " → ".join(parts)


func all_issues() -> PackedStringArray:
	var issues := PackedStringArray()
	for info in pattern_info:
		for issue in info.issues:
			issues.append("%s: %s" % [info.pattern_name if info.kind == "pattern" else "Recovery", issue])
	return issues
