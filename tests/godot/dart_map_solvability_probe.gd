extends SceneTree

# 飞镖地图「可解性探针」。
#
# 目的：把「关卡本身可不可解」与「试玩 AI 开得好不好」分开。
#
# 做法：不复用 dart_map_playtest.gd 那套窗口启发式（0.05~0.42 / 0.75s 之类），
# 而是每一帧直接读**真实存在的飞镖**，按 player.gd 的真实受击判据，
# 判断「当前姿态在未来 T 秒内会不会被打到」，只在会打到时做最小的姿态调整。
#
# 判据（与 pattern_compiler.dart_hits_body 一致）：
#   飞镖高度 h 命中脚底高度 f 的玩家 <=> h ∈ (f - RADIUS, f + RADIUS + 体型高度)
#   站立 体型高 66 -> 危险 当 h <= 77
#   滑铲 体型高 32 -> 危险 当 h <= 43
#
# 输出：无伤通过 / 受伤位置 + 当时的真实场面。
# 若本探针无伤通过而 dart_map_playtest.gd 受伤，则说明是 AI 的问题，不是关卡的问题。

const Motion := preload("res://patterns/player_motion_profile.gd")
const Dart := preload("res://components/dart.gd")
const Player := preload("res://player.gd")
const SEED := 20260913
const MAX_FRAMES := 12000
const BODY := 66.0
const SLIDE_BODY := 32.0
# 一簇滑铲题要能被「一个滑铲」盖住，起手时刻必须卡在
# [末枚相遇点 - 覆盖距离, 首枚相遇点] 这个窗口里。
# 窗口两端各留一点余量：60fps 一帧玩家就跨 7~10px，刚好卡边界必翻车。
const SLIDE_MARGIN_PX := 8.0

var world: Node2D
var player: Node2D
var module: Node2D
var failures := PackedStringArray()
var damage_log: Array[String] = []
var frame_number := 0
var held_action := ""
var hold_frames := 0
var last_slide_frame := -1000
var last_jump_frame := -1000
var trace_frames := 0
# 记录窗口：玩家跑到这个 x 之后开始逐帧打印（粗调用）。
var trace_armed := true
# 记录窗口：玩家跑到这个 x 之后开始逐帧打印（粗调用）。
var trace_trigger_x := 0.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--trace="):
			trace_trigger_x = argument.trim_prefix("--trace=").to_float()
	world = load("res://tests/dart_map/DartMapPractice.tscn").instantiate()
	world.route_seed = SEED
	root.add_child(world)
	current_scene = world
	player = world.player
	player.damaged.connect(on_damage)
	for chunk in world.active_chunks:
		if "module_data" in chunk:
			module = chunk
			break
	if module == null:
		printerr("正式路线没有飞镖模块")
		quit(1)
		return
	await physics_frame
	await physics_frame

	var exit_x: float = module.get_node("Exit").global_position.x
	while frame_number < MAX_FRAMES:
		frame_number += 1
		# 在第一处受伤（x≈2181，胸前 h=66）之前开一段滚动记录。
		if trace_trigger_x > 0.0 and trace_armed and player.global_position.x >= trace_trigger_x:
			trace_armed = false
			trace_frames = 260
		step()
		await physics_frame
		if not player.active or player.global_position.x >= exit_x:
			break

	print("")
	print("MAP length=%d reached=%.1f frames=%d damage=%d hp=%.1f"
		% [module.total_length, player.global_position.x, frame_number,
			damage_log.size(), player.health])
	for line in damage_log:
		print(line)
	if damage_log.is_empty():
		print("SOLVABLE: 无伤通过。")
	else:
		print("UNSOLVED: 仍有 %d 次受伤。" % damage_log.size())
		failures.append("探针受伤 %d 次" % damage_log.size())
	quit(0 if failures.is_empty() else 1)

func step() -> void:
	if trace_frames > 0:
		trace_frames -= 1
		trace_line("(hold)" if hold_frames > 0 else "")
	if hold_frames > 0:
		hold_frames -= 1
		if hold_frames == 0 and held_action != "":
			Input.action_release(held_action)
			held_action = ""
		return

	var threat := imminent_threat()
	match threat:
		"MUST_SLIDE":
			do_action("slide")
		"WAIT_SLIDE":
			# 威胁已在滑铲射程内但还太早，先什么都别做；
			# 若此刻在空中就尽早落地，确保窗口打开时能滑出去。
			if not player.is_on_floor() and not player.fast_falling:
				do_action("slide")
		"MUST_JUMP":
			do_action("jump")
		"STAY_DOWN":
			# 中高位飞镖：站着安全，但如果此刻在空中，就尽快落地。
			if not player.is_on_floor() and not player.fast_falling:
				do_action("slide")
		"MUST_AIR":
			# 低位飞镖但已经来不及起跳 -> 用二段跳把自己抬过危险带。
			if player.jumps_used < 2:
				do_action("jump")
	if trace_frames > 0:
		print("      -- threat=%s" % threat)

# 从当前状态起跳后 t 秒时玩家脚底离地高度（不含二段跳）。
# 与 player.gd 的重力积分保持一致：上升用 ASCENT_GRAVITY，下落用 FALL_GRAVITY。
func feet_after_jump(t: float) -> float:
	if not player.is_on_floor():
		return current_feet()
	var vy: float = Player.JUMP_SPEED
	return integrate(0.0, vy, t)

# 当前脚底高度，不做任何预测。
func current_feet() -> float:
	return Motion.GROUND_Y - player.global_position.y

func integrate(start_height: float, start_vy: float, t: float) -> float:
	var h: float = start_height
	var vy: float = start_vy
	var steps := maxi(1, int(ceil(t * 60.0)))
	var step := t / float(steps)
	for _i in steps:
		vy += (Player.ASCENT_GRAVITY if vy < 0.0 else Player.FALL_GRAVITY) * step
		h -= vy * step
	return h

func trace_line(threat: String) -> void:
	print("  [T%04d] x=%.1f feet=%.1f vy=%.1f floor=%s state=%d slide=%.3f bodyh=%.0f flipbuf=%.2f %s"
		% [frame_number, player.global_position.x,
			Motion.GROUND_Y - player.global_position.y,
			player.velocity.y, str(player.is_on_floor()), player.movement_state,
			player.slide_remaining, player.body_collision.shape.size.y,
			player.flip_buffer_remaining, threat])
	for dart in live_darts():
		var dx: float = dart.global_position.x - player.global_position.x
		if absf(dx) < 220.0:
			print("      dart h=%.1f dx=%+.1f t=%.3f"
				% [Motion.GROUND_Y - dart.global_position.y, dx,
					dx / (Motion.RUN_SPEED + absf(dart.velocity.x))])

func do_action(action: String) -> void:
	if action == "slide":
		if frame_number - last_slide_frame < 6:
			if trace_frames > 0:
				print("      >> slide SKIPPED by cooldown (last=%d)" % last_slide_frame)
			return
		last_slide_frame = frame_number
	else:
		if frame_number - last_jump_frame < 4:
			if trace_frames > 0:
				print("      >> jump SKIPPED by cooldown (last=%d)" % last_jump_frame)
			return
		last_jump_frame = frame_number
	if trace_frames > 0:
		print("      >> PRESS %s (floor=%s vy=%.1f slide_left=%.2f jumpbuf=%.2f)"
			% [action, str(player.is_on_floor()), player.velocity.y,
				player.slide_remaining, player.jump_buffer_remaining])
	Input.action_press(action)
	held_action = action
	hold_frames = 3

# 未来 LOOKAHEAD 秒内，最紧迫的威胁要求什么姿态。
#
# 滑铲单独处理：它的覆盖是「一段地面距离」，不是「一段时间」，
# 而且 player.gd 在滑铲期间会把玩家速度从 RUN_SPEED 提到 SLIDE_BURST_SPEED，
# 所以必须按相遇点 X 判断能不能一次盖住整簇（见 _slide_decision）。
func imminent_threat() -> String:
	# 非滑铲威胁的观察窗：够近才反应。
	const LOOKAHEAD := 0.62
	# 滑铲簇的观察窗必须明显更长。
	#
	# 原因：判断「一个滑铲能不能盖住整簇」必须知道整簇的末枚在哪。
	# 窗口太短就只看到簇的一半，于是把「半簇的末枚」当成整簇末枚，
	# 提前按下滑铲 —— 滑铲在真正的末枚到达前就结束了。
	# 这是滑铲横排反复受伤的第二个原因（第一个是不知道滑铲提速）。
	#
	# 取 2.0s（= 800px 玩家位移）可以保证：一旦「该按了」成立，
	# 整簇必定已完整可见。推导：
	#   设可见末枚 x_last，真实末枚 x_end，同一簇内 x_end - x_last <= cover。
	#   条件 px >= x_last - cover 成立时 x_last - px <= cover，
	#   于是 x_end - px <= 2 x cover = 720px < 800px，x_end 一定也在窗口内。
	const SLIDE_LOOKAHEAD := 2.0
	var px: float = player.global_position.x
	var worst := "NONE"
	var worst_time := INF
	var slide_x: Array[float] = []

	for dart in live_darts():
		var dx: float = dart.global_position.x - px
		if dx < 0.0:
			continue
		# 飞镖沿 velocity.x 向左飞（负值），玩家以 RUN_SPEED 向右。
		# ⚠ closing 必须用 RUN_SPEED（引擎编排的基准速度），不是玩家当前速度：
		#   飞镖的推进由 PatternRunner 按 progress_x / RUN_SPEED 推导，
		#   所以「相遇点世界 X」与玩家实际跑多快无关。
		var dart_speed: float = absf(dart.velocity.x)
		var closing: float = Motion.RUN_SPEED + dart_speed
		if closing <= 0.0:
			continue
		var t: float = dx / closing
		var h: float = feet_height_of(dart)
		if is_slide_able(h):
			# 相遇点 X = 玩家再跑 RUN_SPEED x t 的地方。
			if t <= SLIDE_LOOKAHEAD:
				slide_x.append(px + Motion.RUN_SPEED * t)
			continue
		if t > LOOKAHEAD:
			continue
		var need := posture_for(h, t)
		if need == "NONE":
			continue
		if t < worst_time:
			worst_time = t
			worst = need
	# 需要抬高身体的威胁优先：滑铲解决不了它，先处理。
	if worst != "NONE":
		return worst
	if slide_x.is_empty():
		return "NONE"
	slide_x.sort()
	return _slide_decision(slide_x)


# 一枚飞镖的「接触窗口」半宽。
#
# 玩家不是「中心碰到中心」才中招：dart.gd 用 swept_shape，
# 飞镖边缘擦到身体边缘就算。所以相遇点在 X 的飞镖实际占住 [X-PAD, X+PAD]。
func contact_pad() -> float:
	return Dart.RADIUS + Player.PLAYER_WIDTH / 2.0


# 一个滑铲覆盖的地面距离。
#
# ⚠ 不能按 SLIDE_DURATION x RUN_SPEED（= 232px）算 —— 这是错的，
#   而且正是滑铲横排第三枚反复受伤的根因。
#   player.gd::start_slide() 会把 boost_speed 设成 SLIDE_BOOST = 220，
#   滑铲期间玩家实际速度是 SLIDE_BURST_SPEED = 620，不是 RUN_SPEED = 400。
#   一个滑铲真正盖住的是 0.58 x 620 = 360px。
#
#   实测（本探针 trace）：滑铲剩余 0.397s 时玩家在 x=4043.7，
#   滑铲结束时玩家在 x=4291.5 —— 0.397s 走了 247.8px → 624 px/s，与 620 吻合。
func slide_cover_px() -> float:
	return Player.SLIDE_DURATION * Player.SLIDE_BURST_SPEED


# 滑铲能过、站立会中 -> 这一枚只能靠滑铲（或跳到脚底够高）处理。
#
# 注意这里按「地面站立」为基准判断，与玩家当前姿态无关 ——
# 因为要判的是「到达那一刻」能不能用滑铲解决，
# 而不是「此刻在空中所以不算数」。用当前脚底高度会让空中漏掉整簇。
func is_slide_able(h: float) -> bool:
	return h <= BODY + Dart.RADIUS and h > SLIDE_BODY + Dart.RADIUS


# 这一簇滑铲题，现在该不该按下滑铲。
#
# 按下时玩家在 x_p，滑铲覆盖 [x_p, x_p + cover]。
# 第 i 枚飞镖的接触窗口是 [X_i - PAD, X_i + PAD]。
# 一次盖住整簇 <=> x_p <= X_first - PAD 且 x_p + cover >= X_last + PAD。
# 起手越晚，滑铲尾巴伸得越远，所以取「最晚还能盖住末枚接触窗口」的那一刻：
#   x_p = X_last + PAD - cover
# 早于这个时刻按下去，滑铲会在末枚到达前结束 —— 这正是旧版探针的毛病：
# 它一看到 t <= 0.45 就按，白白浪费掉 0.45s 的覆盖。
func _slide_decision(sorted_x: Array) -> String:
	var cover: float = slide_cover_px()
	var pad: float = contact_pad()
	var px: float = player.global_position.x
	if not player.is_on_floor() or player.velocity.y < 0.0:
		# 空中按 slide 是「快速下落 + 落地自动滑铲」，先落下来再说。
		return "WAIT_SLIDE"
	# 只看玩家马上要面对的第一簇：一旦出现「一个滑铲盖不住」的缺口就断开。
	var first_x: float = sorted_x[0]
	var last_x: float = first_x
	for index in range(1, sorted_x.size()):
		if sorted_x[index] - last_x > cover - 2.0 * pad - SLIDE_MARGIN_PX:
			break
		last_x = sorted_x[index]
	if (last_x - first_x) + 2.0 * pad > cover - SLIDE_MARGIN_PX:
		# 一簇太长，一个滑铲盖不住：按得越晚覆盖越靠前，剩下的交给下一个滑铲。
		return "MUST_SLIDE" if px >= first_x - pad - 40.0 else "WAIT_SLIDE"
	if px < last_x + pad - cover + SLIDE_MARGIN_PX:
		return "WAIT_SLIDE"
	return "MUST_SLIDE"


# 给定飞镖高度 h 和到达时间 t，玩家该做什么。
#
# 能滑铲过去的飞镖不会走到这里 —— imminent_threat 已经用 is_slide_able
# 把它们单独收进滑铲簇了。所以剩下的只有两种：
#   h 低到滑铲也躲不过 -> 必须把身体抬起来（起跳 / 二段跳）
#   h 高到站着就安全   -> 什么都不用做
func posture_for(h: float, t: float) -> String:
	var feet: float = Motion.GROUND_Y - player.global_position.y
	var airborne: bool = not player.is_on_floor()

	# 站立会撞吗？会撞的高度带是 h <= feet + BODY + RADIUS
	if h <= feet + BODY + Dart.RADIUS:
		# 滑铲也撞 -> 必须抬高身体。
		if airborne:
			return "MUST_AIR"
		# 站着也来不及 -> 起跳。但必须先确认「跳到 t 时刻真的能过」，
		# 否则会在上升半途被飞镖追上（实测 vy=-1063 的新跳仍会中招）。
		var safe_feet: float = h + BODY + Dart.RADIUS + 5.0
		if feet_after_jump(t) >= safe_feet:
			return "MUST_JUMP"
		# 单跳不够，但若已经在空中就还能用二段跳抬上去。
		if airborne:
			return "MUST_AIR"
		# 单跳也不够 —— 这是 200 / 300 层（罚顶点）的典型情况：
		# 此时起跳是错的，留在原地反而更安全。
		return "STAY_DOWN"
	# 站立就安全（中高位）。
	return "STAY_DOWN"

func live_darts() -> Array:
	var out: Array = []
	for node in get_nodes_in_group("dart"):
		if is_instance_valid(node):
			out.append(node)
	return out

func feet_height_of(dart: Node2D) -> float:
	# 高度一律「从地面往上量」：跟 dart_map_playtest / player_motion_profile 一致。
	return Motion.GROUND_Y - dart.global_position.y

func on_damage(_amount: float) -> void:
	var px: float = player.global_position.x
	var feet: float = Motion.GROUND_Y - player.global_position.y
	var near := []
	for dart in live_darts():
		var dx: float = dart.global_position.x - px
		if absf(dx) < 90.0:
			near.append("h=%.1f dx=%+.1f" % [Motion.GROUND_Y - dart.global_position.y, dx])
	damage_log.append("DAMAGE x=%.1f feet=%.1f vy=%.1f floor=%s near=[%s]"
		% [px, feet, player.velocity.y, str(player.is_on_floor()), ", ".join(near)])
