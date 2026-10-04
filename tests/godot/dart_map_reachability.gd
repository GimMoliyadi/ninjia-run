extends SceneTree

# 飞镖地图「可达性」分析（不依赖任何试玩 AI）。
#
# 问的问题：对每一枚飞镖，在它到达玩家所在 x 的那一刻，玩家脚底高度 f
# 必须落在哪个区间才安全？这些区间之间能不能用玩家真实的运动能力串起来？
#
# 受击判据（与 player.gd / pattern_compiler.dart_hits_body 一致）：
#   飞镖高度 h 命中脚底 f  <=>  h ∈ (f - RADIUS, f + RADIUS + BODY)
#   => 不安全当 (h > f - 11) 且 (h < f + 11 + 66) = (h - 77 < f < h + 11)
#   => 安全当 f <= h - 77  或  f >= h + 11
#
# 关卡里所有飞镖的高度都是「层」（36 / 66 / 96 / 152 / 200 / 300），
# 所以对每枚飞镖，安全工作高度是两段：
#   LOW  : f <= h - 77   （压低身体 —— 站着或滑铲）
#   HIGH : f >= h + 11   （抬过飞镖 —— 起跳）
#
# 关键：滑铲能把身体压到 0（脚底不变，但体型从 66 缩到 32），
# 所以「站立安全」的实际判据要用体型高度，而不是脚底高度。
# 这里把两者都算出来：
#   stand_safe : h <= f + 11        (体型 66：h 打到 f..f+77)
#   slide_safe : h <= f + 11        (体型 32：h 打到 f..f+43)
# 统一成「身体顶面」b = f + body_h：安全当 h < b - 11 或 h > b + 11。
# 于是站立时 b = f + 66，滑铲时 b = f + 32。

const Motion := preload("res://patterns/player_motion_profile.gd")
const Dart := preload("res://components/dart.gd")
const Player := preload("res://player.gd")
const SEED := 20260913

var world: Node2D
var player: Node2D
var module: Node2D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://tests/dart_map/DartMapPractice.tscn").instantiate()
	world.route_seed = SEED
	root.add_child(world)
	current_scene = world
	player = world.player
	for chunk in world.active_chunks:
		if "module_data" in chunk:
			module = chunk
			break
	await physics_frame
	await physics_frame

	# 收集所有飞镖：与 dart_map_playtest.collect_groups 完全一致的相遇坐标算法。
	#
	# 玩家 x(t) = R·t；飞镖从 runner 本地的 position_offset.x 以 speed 向左飞。
	#   x_dart(t) = runner_x + po - s·t
	#   相遇 => t = po / (R + s)，世界 x = runner_x + t·R
	# 注意 runner.global_position.x 是「相对 section」的，必须先取 global，
	# 否则各 section 的偏移会互相污染（曾把 161 枚飞镖排成乱序）。
	var entries: Array = []
	for section in module.sections:
		for runner in section.runners:
			var runner_x: float = runner.global_position.x
			for event in runner.plan.events:
				var closing: float = Motion.RUN_SPEED + event.speed
				if closing <= 0.0:
					continue
				var meet_t: float = event.position_offset.x / closing
				entries.append({
					"x": runner_x + meet_t * Motion.RUN_SPEED,
					"t": meet_t,
					"h": -event.position_offset.y,
					"section": section.name,
				})
	entries.sort_custom(func(a, b): return a.x < b.x)

	print("共 %d 枚飞镖，按相遇时刻排列。" % entries.size())
	print("")
	print("序号  相遇x     相遇t     高度h   站立安全?  滑铲安全?  需起跳?  相邻间隔")
	var prev_x := 0.0
	var problems := 0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var h: float = e.h
		# 站立：身体顶面在 66，飞镖打不到当 h < -11（不可能）或 h > 77。
		var stand_safe: bool = h > JSON_RANGE_TOP
		# 滑铲：顶面 32，安全当 h > 43。
		var slide_safe: bool = h > SLIDE_RANGE_TOP
		var need_jump: bool = not slide_safe
		var gap: float = e.x - prev_x
		prev_x = e.x
		print("%4d  %8.1f  %7.3f  %7.1f  %9s  %9s  %8s  %7.1f"
			% [i, e.x, e.t, h, str(stand_safe), str(slide_safe), str(need_jump), gap])

	print("")
	print("（站立安全 = h > 77；滑铲安全 = h > 43；两者都 false = 必须起跳抬过）")
	print("")

	# ── 真正的可解性判据：模拟一条「最省力」的轨迹，逐步检查每枚飞镖 ──
	#
	# 不能用「间隔 < 单跳周期」当判据 —— 那太粗：两枚 h=36 相隔 0.2s
	# 用**同一次**起跳就能同时躲过，它们根本不冲突。
	#
	# 正确的问法是：存在不存在一条轨迹，让玩家在每枚飞镖到达时脚底都安全？
	# 这里用贪心搜索：每个时刻只在「必须动」时动，动作只允许 跳 / 滑 / 不动，
	# 并用真实的运动学前推。若贪心找不到解，再报「需要人工确认」。
	var t_end: float = entries[entries.size() - 1].x / Motion.RUN_SPEED
	var findings := simulate_greedy(entries, t_end)
	print("")
	if findings.is_empty():
		print("可解性模拟：无冲突 —— 存在一条不受伤的轨迹。")
	else:
		print("可解性模拟：发现 %d 处可疑（贪心轨迹在这些点受伤）：" % findings.size())
		for line in findings:
			print("  " + line)
	quit(0)

# 贪心前推：以 1/60s 步长推进，每步选一个动作（不动 / 跳 / 滑），
# 目标是在所有飞镖的到达时刻保持脚底安全。返回失败点列表。
func simulate_greedy(entries: Array, t_end: float) -> Array:
	var dt := 1.0 / 60.0
	var feet := 0.0
	var vy := 0.0
	var on_floor := true
	var slide_left := 0.0
	var jumps_used := 0
	var t := 0.0
	var next_dart := 0
	var failures: Array = []
	# 简化：记录每个 dt 是否处于滑铲（体型 32）。
	while t <= t_end + 0.5:
		# 该不该动作？看最近一枚飞镖。
		var action := "none"
		while next_dart < entries.size() and entries[next_dart].x / Motion.RUN_SPEED < t:
			next_dart += 1
		if next_dart < entries.size():
			var e: Dictionary = entries[next_dart]
			var arrive: float = e.x / Motion.RUN_SPEED
			var h: float = e.h
			var body: float = BODY_SLIDE if slide_left > 0.0 else BODY_STAND
			var danger: bool = hits(h, feet, body)
			# 动作窗口：不能太早（滑铲会在飞镖到达前结束），也不能太晚。
			var lead: float = arrive - t
			if danger and lead > 0.0 and lead < 0.45:
				# 站立会中招时，先看滑铲能不能救（滑铲把体型从 66 压到 32）。
				var slide_ok: bool = not hits(h, feet, BODY_SLIDE)
				if on_floor and slide_ok and slide_left <= 0.0:
					action = "slide"
				elif on_floor and jumps_used == 0:
					action = "jump"
				elif not on_floor and jumps_used < 2:
					action = "jump"
		match action:
			"slide":
				slide_left = Player.SLIDE_DURATION
				# 滑铲期间脚底不变，但体型变矮。
			"jump":
				vy = Player.JUMP_SPEED if jumps_used == 0 else Player.SECOND_JUMP_SPEED
				jumps_used += 1
				on_floor = false
		# 积分
		if slide_left > 0.0:
			slide_left = maxf(0.0, slide_left - dt)
		vy += (Player.ASCENT_GRAVITY if vy < 0.0 else Player.FALL_GRAVITY) * dt
		feet -= vy * dt
		if feet <= 0.0:
			feet = 0.0
			vy = 0.0
			if not on_floor:
				on_floor = true
				jumps_used = 0
		# 检查这一时刻有没有飞镖到达
		for e in entries:
			var arrive: float = e.x / Motion.RUN_SPEED
			if absf(arrive - t) < dt * 0.5:
				var body: float = BODY_SLIDE if slide_left > 0.0 else BODY_STAND
				if hits(e.h, feet, body):
					var label := "h=%.0f x=%.0f t=%.3f 脚底=%.1f 体型=%.0f"
					failures.append(label % [e.h, e.x, arrive, feet, body])
		t += dt
	return failures

# 命中判据（唯一真值来源：pattern_compiler.dart_hits_body）。
#
# 玩家身体占据 [feet, feet + body]（脚底到头顶），飞镖占据 [h - r, h + r]。
# 区间相交 => 命中。
#   h + r > feet      且      h - r < feet + body
# 等价写法（更直观）：
#   飞镖上沿高过脚底  AND  飞镖下沿低于头顶
func hits(h: float, feet: float, body: float) -> bool:
	return h + Dart.RADIUS > feet and h - Dart.RADIUS < feet + body

const BODY_STAND := 66.0
const BODY_SLIDE := 32.0
const SLIDE_RANGE_TOP := 43.0
const JSON_RANGE_TOP := 77.0
