extends SceneTree

# 正式关卡实跑：直接加载 run/main_scene 指向的 test_world.tscn，
# 让 game.gd 自己跑自己的 _physics_process，测试只做「观察与记录」。
#
# 与另外两份 DARTS 测试的分工：
#   - dart_section_official_regression.gd：验证调用链、衔接、暂停/重开/泄漏
#   - dart_patterns_regression.gd：验证不同跑速下的通过性
#   - 本测试：连续跑两遍正式流程，记录 Godot 控制台输出与运行时错误
#
# 通过 GODOT_DARTS_RUNS 环境变量可以改运行遍数，默认 2。

const DartScript := preload("res://components/dart_encounter.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const PatternEventScript := preload("res://patterns/pattern_event.gd")

var failures: Array[String] = []
var game: Node
var player: Node2D
var errors: Array[String] = []
var runs := 0

enum Threat { NONE, GAP, DART_OVER, DART_UNDER }

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var wanted := 2
	var env := OS.get_environment("GODOT_DARTS_RUNS")
	if not env.is_empty() and env.is_valid_int():
		wanted = maxi(1, int(env))

	var world: Node = load("res://test_world.tscn").instantiate()
	root.add_child(world)
	game = world
	current_scene = world
	await _frames(6)

	for index in wanted:
		runs += 1
		print("\n========== 正式实跑 #%d ==========" % (index + 1))
		await _one_run(index)

	world.free()
	await _frames(2)

	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("\nOfficial DARTS runs passed: %d run(s), no runtime error, section passable, seams clean." % runs)
	quit(0 if failures.is_empty() else 1)

func _one_run(index: int) -> void:
	# 此种子的第一张地图是 DARTS。
	game.route_seed = 20260900
	game.restart_run()
	await _frames(6)

	var darts: Node = _find_darts_chunk()
	_check(darts != null, "第 %d 遍：正式路线里没有 DARTS chunk" % (index + 1))
	if darts == null:
		return

	var info: Dictionary = darts.debug_info()
	print("  section   = %s" % str(info.get("section", "?")))
	print("  sequence  = %s" % str(info.get("sequence", "?")))
	print("  length    = %.0f px" % float(info.get("total_length", 0.0)))
	print("  issues    = %d" % int(info.get("issues", PackedStringArray()).size()))
	print("  stages    = %s" % str(_stage_list(info)))
	_check(int(info.get("issues", PackedStringArray()).size()) == 0,
		"第 %d 遍：Section 存在编译器 issue" % (index + 1))

	var section: Node = darts.get_node_or_null("Section")
	_check(section != null, "第 %d 遍：Section 子节点缺失" % (index + 1))
	if section == null:
		return

	player = game.player
	player.damaged.connect(func(amount: float) -> void:
		var nearby: Array[String] = []
		for active_dart in get_nodes_in_group("dart"):
			if absf(active_dart.global_position.x - player.global_position.x) < 120.0:
				nearby.append("(%.0f,%.0f)" % [active_dart.global_position.x, active_dart.global_position.y])
		print("  DAMAGE %.0f at x=%.0f y=%.0f stage=%s nearby=%s" % [amount, player.global_position.x, player.global_position.y, str(darts.debug_info_at(player.global_position.x).get("stage", "")), str(nearby)])
	, CONNECT_ONE_SHOT)
	var start_x: float = float(darts.get_node("Entry").global_position.x)
	var last_end := 0.0
	for runner in section.runners:
		last_end = maxf(last_end, float(runner.global_position.x) + float(runner.plan.length))
	var stop_x: float = last_end + 1.5 * float(Motion.RUN_SPEED)

	player.global_position = Vector2(start_x, float(player.global_position.y))
	for dart in get_nodes_in_group("dart"):
		if is_instance_valid(dart):
			dart.free()

	var spawned := 0
	var max_darts := 0
	var guard := 0
	var step: float = float(Motion.RUN_SPEED) / 60.0

	while float(player.global_position.x) < stop_x and guard < 5000:
		guard += 1
		player.global_position.x += step
		_drive(section)
		await physics_frame
		for runner in section.runners:
			if runner.spawned_count > 0:
				spawned += 1
				break
		max_darts = maxi(max_darts, get_nodes_in_group("dart").size())
		if float(player.health) <= 0.0:
			break

	print("  spawned   = %s   max live darts = %d   health = %.0f" % [
		spawned > 0, max_darts, float(player.health)
	])
	print("  runners   = %d, finished = %d" % [
		section.runners.size(), _finished_count(section)
	])
	_check(spawned > 0, "第 %d 遍：PatternRunner 没生成障碍" % (index + 1))
	_check(player.health == player.MAX_HP,
		"第 %d 遍：会读预警的玩家受伤了（health=%.0f）" % [index + 1, float(player.health)])
	_check(_finished_count(section) == section.runners.size(),
		"第 %d 遍：仍有 PatternRunner 未 finish" % (index + 1))

	await _frames(30)
	_check(get_nodes_in_group("dart").size() == 0,
		"第 %d 遍：越过 DARTS 后仍有飞镖残留" % (index + 1))

	var next: Node2D = _next_chunk_after(darts)
	if next != null:
		var entry: Node2D = next.get_node_or_null("Entry") as Node2D
		if entry != null:
			var gap: float = absf(
				float(entry.global_position.x) - float(darts.get_node("Exit").global_position.x)
			)
			print("  next      = %s, seam gap = %.2f px" % [next.name, gap])
			_check(gap < 0.5, "第 %d 遍：与下一段存在 %.1f px 缝隙" % [index + 1, gap])

	# 暂停 / 恢复。
	game.toggle_pause()
	await _frames(2)
	_check(self.paused, "第 %d 遍：暂停未生效" % (index + 1))
	game.toggle_pause()
	await _frames(2)
	_check(not self.paused, "第 %d 遍：恢复未生效" % (index + 1))

	# Restart 后必须干净重建。
	game.route_seed = 20260900
	game.restart_run()
	await _frames(6)
	var rebuilt: Node = _find_darts_chunk()
	_check(rebuilt != null, "第 %d 遍：Restart 后 DARTS 未重建" % (index + 1))
	_check(get_nodes_in_group("dart").is_empty(),
		"第 %d 遍：Restart 后场景里仍有飞镖" % (index + 1))
	print("  pause/restart ok, darts cleared = %s" % get_nodes_in_group("dart").is_empty())

# =========================================================
# 「会读预警的玩家」
# =========================================================

func _next_threat(section: Node) -> Dictionary:
	var px: float = float(player.global_position.x)
	var best := {"kind": Threat.NONE, "x": INF, "target_y": NAN}
	for runner in section.runners:
		var plan: Dictionary = runner.plan
		if plan.is_empty() or not plan.issues.is_empty():
			continue
		var rx: float = float(runner.global_position.x)
		var ry: float = float(runner.global_position.y)
		for gap in plan.gaps:
			var wx: float = rx + float(gap.rect.position.x)
			var lead: float = wx - px
			var closing: float = float(Motion.RUN_SPEED) + float(gap.speed)
			if lead < 0.0 or lead > closing * 1.2 or wx >= float(best.x):
				continue
			best = {
				"kind": Threat.GAP,
				"x": wx,
				"target_y": ry + float(gap.rect.position.y) + float(gap.rect.size.y) * 0.5,
			}
		for event in plan.events:
			if event.preview_kind != PatternEventScript.PreviewKind.DART or event.speed <= 0.0:
				continue
			var wx: float = rx + float(event.position_offset.x)
			var lead: float = wx - px
			var closing: float = float(Motion.RUN_SPEED) + float(event.speed)
			if lead < 0.0 or lead > closing * 2.0 or wx >= float(best.x):
				continue
			var dart_center: float = ry + float(event.position_offset.y)
			var head_y: float = float(Motion.GROUND_Y) - float(Motion.BODY_SIZE.y)
			if dart_center > head_y:
				best = {"kind": Threat.DART_OVER, "x": wx, "target_y": NAN}
			else:
				best = {"kind": Threat.DART_UNDER, "x": wx, "target_y": NAN}
	return best

func _drive(section: Node) -> void:
	var threat: Dictionary = _next_threat(section)
	match int(threat.kind):
		Threat.GAP:
			_drive_to_y(float(threat.target_y))
		Threat.DART_OVER:
			_jump_over(float(threat.x))
		Threat.DART_UNDER:
			_duck_under(float(threat.x))

func _drive_to_y(target_y: float) -> void:
	var dz: float = target_y - float(player.global_position.y)
	if dz < -12.0:
		if player.is_on_floor():
			player.start_jump(Motion.JUMP_SPEED)
		elif float(player.velocity.y) > -60.0:
			player.start_jump(Motion.SECOND_JUMP_SPEED)
	elif dz > 24.0 and not player.is_on_floor():
		player.request_fast_fall()

func _jump_over(dart_x: float) -> void:
	if not player.is_on_floor():
		return
	var lead: float = dart_x - float(player.global_position.x)
	if lead / float(Motion.RUN_SPEED) <= 0.55:
		player.start_jump(Motion.JUMP_SPEED)

func _duck_under(dart_x: float) -> void:
	if not player.is_on_floor():
		player.request_fast_fall()
		return
	var lead: float = dart_x - float(player.global_position.x)
	if lead / float(Motion.RUN_SPEED) <= 0.75 and not player.is_sliding():
		player.start_slide()

# =========================================================
# 工具
# =========================================================

func _stage_list(info: Dictionary) -> Array:
	var seen := {}
	for entry in info.get("info", []):
		var stage: String = str(entry.get("stage", ""))
		if not stage.is_empty():
			seen[stage] = true
	var out: Array = seen.keys()
	out.sort()
	return out

func _finished_count(section: Node) -> int:
	var n := 0
	for runner in section.runners:
		if runner.completed:
			n += 1
	return n

func _find_darts_chunk() -> Node:
	for chunk in game.active_chunks:
		if chunk != null and is_instance_valid(chunk) and chunk.get_script() == DartScript:
			return chunk
	return null

func _next_chunk_after(darts: Node) -> Node2D:
	var exit_x: float = float(darts.get_node("Exit").global_position.x)
	var best: Node2D = null
	var best_x := INF
	for chunk in game.active_chunks:
		if chunk == darts or not is_instance_valid(chunk):
			continue
		var entry: Node2D = chunk.get_node_or_null("Entry") as Node2D
		if entry == null:
			continue
		var dx: float = float(entry.global_position.x) - exit_x
		if dx >= -0.5 and dx < best_x:
			best_x = dx
			best = chunk
	return best

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  FAIL  ", message)
