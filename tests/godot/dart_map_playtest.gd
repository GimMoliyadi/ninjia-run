extends SceneTree

const Motion := preload("res://patterns/player_motion_profile.gd")
const Dart := preload("res://components/dart.gd")
const OUTPUT := "res://tests/artifacts/dart-map/"
const SEED := 20260913
const MAX_FRAMES := 6500
const CONTACT_MARGIN := Motion.BODY_SIZE.x * 0.5 + Dart.RADIUS
var world: Node2D
var player: Node2D
var module: Node2D
var groups: Array[Dictionary] = []
var failures := PackedStringArray()
var damage_count := 0
var spawned := 0
var screen_spawns := 0
var max_live := 0
var speed := Motion.RUN_SPEED
var capture_enabled := false
var boost_enabled := false
var last_slide := -130
var slide_count := 0
# 滑铲输入次数（直接统计 press("slide")，与 boost 路径无关）。
var slide_inputs := 0
var pause_checked := false
var next_capture := 0
var capture_times := [3.0, 11.0, 19.0, 23.0, 28.0, 37.0, 46.0, 54.0, 64.0, 69.0, 72.3]
var held_action := ""
# 当前输入还要保持几帧（0 表示本帧结束时释放）。
var hold_frames := 0
var last_jump := -100
var frame_number := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--capture":
			capture_enabled = true
		elif argument == "--boost":
			boost_enabled = true
		elif argument.begins_with("--speed="):
			speed = argument.trim_prefix("--speed=").to_float()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = load("res://tests/dart_map/DartMapPractice.tscn").instantiate()
	world.route_seed = SEED
	root.add_child(world)
	current_scene = world
	player = world.player
	player.set_run_speed(speed)
	player.damaged.connect(on_damage)
	for chunk in world.active_chunks:
		if "module_data" in chunk:
			module = chunk
			break
	if module == null:
		printerr("正式路线没有飞镖模块")
		quit(1)
		return
	collect_groups()
	var exit_x: float = module.get_node("Exit").global_position.x
	for frame in MAX_FRAMES:
		frame_number = frame
		if not held_action.is_empty():
			hold_frames -= 1
			if hold_frames <= 0:
				Input.action_release(held_action)
				held_action = ""
		try_boost()
		drive()
		await physics_frame
		await process_frame
		if not pause_checked and spawned > 20:
			await check_pause()
		max_live = maxi(max_live, get_nodes_in_group("dart").size())
		var progress: float = (player.global_position.x - module.global_position.x) / Motion.RUN_SPEED
		if capture_enabled and next_capture < capture_times.size() and progress >= capture_times[next_capture]:
			await capture("%02d-%03d.png" % [next_capture, int(speed)])
			next_capture += 1
		if not player.active:
			failures.append("角色死亡，未完成地图")
			if capture_enabled:
				await capture("death-%03d.png" % int(speed))
			break
		if player.global_position.x >= exit_x:
			break
	if player.global_position.x < exit_x:
		failures.append("未到达模块出口")
	var expected := 0
	for section in module.sections:
		for runner in section.runners:
			expected += runner.plan.events.size()
			if runner.spawned_count != runner.plan.events.size():
				failures.append("漏波 %s: %d/%d" % [runner.name, runner.spawned_count, runner.plan.events.size()])
	if screen_spawns > 0:
		failures.append("发现 %d 枚屏内出生飞镖" % screen_spawns)
	if damage_count > 0:
		failures.append("无技能输入路线受伤 %d 次" % damage_count)
	print("MAP speed=%.0f length=%.0f duration=%.2f reached=%.0f spawned=%d/%d screen_spawns=%d max_live=%d damage=%d hp=%.1f" %
		[speed, module.total_length, module.total_length / speed, player.global_position.x, spawned, expected, screen_spawns, max_live, damage_count, player.health])
	print("FRAMES loop_iterations=%d  player_x=%.1f  实际模拟帧=%d  比值=%.2f" % [
		frame_number, player.global_position.x, int(Engine.get_physics_frames()),
		float(Engine.get_physics_frames()) / maxf(1.0, float(frame_number))])
	# slide_count 只在 try_boost() 里累加，而 try_boost() 受 boost_enabled 控制
	# （默认 false）。所以 boost 路线关闭时 slide_count 恒为 0，
	# 不能当成「没滑铲过」——真正的滑铲次数看 slide_inputs。
	print("SLIDES inputs=%d  boost_path=%d(boost_enabled=%s)" % [
		slide_inputs, slide_count, str(boost_enabled)])
	if player.active and player.global_position.x >= exit_x:
		await check_restart()
	for failure in failures:
		printerr("FAIL: ", failure)
	if not held_action.is_empty():
		Input.action_release(held_action)
	world.free()
	quit(0 if failures.is_empty() else 1)

func collect_groups() -> void:
	for section in module.sections:
		for runner in section.runners:
			runner.event_spawned.connect(on_spawn)
			var batches := {}
			for event in runner.plan.events:
				var key: float = event.spawn_time
				if not batches.has(key):
					# 相遇位置：飞镖从 position_offset.x 以 speed 向左飞，
					# 玩家以 RUN_SPEED 向右跑，两者在世界坐标相遇。
					#   玩家 x(t) = R·t
					#   飞镖 x(t) = po - s·t
					#   相遇 => t = po / (R + s)，相遇世界 x = t · R
					# 旧实现误写成 (po + s·key) / (1 + s/R)，分母少乘了 R，
					# 算出的相遇点会跑到几十万像素之外，试玩 AI 因此全程朝错误位置
					# 起跳 / 滑铲，在任何关卡改动下都必然受伤。
					var closing: float = Motion.RUN_SPEED + event.speed
					var meet_x: float = event.position_offset.x / closing * Motion.RUN_SPEED
					batches[key] = {"x": runner.global_position.x + meet_x, "speed": event.speed, "heights": [], "runner": runner}
				batches[key].heights.append(-event.position_offset.y)
			for batch in batches.values():
				batch.heights.sort()
				groups.append(batch)
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.x < b.x)

func drive() -> void:
	# 正在保持按住时不要重复决策：否则会在同一拍反复改写输入，
	# 把已经生效的滑铲 / 起跳打断。
	if hold_frames > 0:
		return
	var px: float = player.global_position.x
	var current_speed: float = maxf(Motion.RUN_SPEED, player.velocity.x)
	for batch in groups:
		var time: float = (batch.x - px) / current_speed
		var margin: float = CONTACT_MARGIN / ((1.0 + batch.speed / Motion.RUN_SPEED) * current_speed)
		if time < -margin:
			continue
		if time > 0.75:
			return
		# 同一个 batch 只处理一次：处理过就跳过。
		#
		# 旧实现每帧重新决策，导致同一枚飞镖在进入 0.75s 窗口后会被
		# 反复 press("slide")，而 start_slide() 每次都会把 slide_remaining
		# 重置成 0.58s —— 滑铲被无限续期，玩家永久保持下蹲（速度还更快），
		# 于是撞上后面所有飞镖。表现为「无论怎么改关卡，受伤位置完全不变」。
		if batch.get("handled", false):
			continue
		# 每帧只允许「动手」一次（起跳 / 滑铲），但「保持姿态」类判断
		# （中高位飞镖要求待在地面）必须对**每一个** batch 都生效。
		#
		# 旧实现里所有分支都以 return 收尾，等于每帧只能看一个 batch。
		# RISE / FALL 这类阶梯（96 → 152 → 200，间隔约 0.21s）里，
		# 前面那一节会把整帧占掉，后面的节次被饿死到贴脸才轮到，
		# 于是「本来站着就安全」的中高位飞镖反而因为玩家还在前一次
		# 起跳的空中而被撞 —— x=2811 / 3564 / 4537 的三次伤都是这个形状。
		var acted: bool = false
		var heights: Array = batch.heights
		# 单枚飞镖且「站着会撞、滑铲能躲」→ 必须滑铲。
		#
		# 受击判据（与 pattern_compiler.dart_hits_body 一致）：
		#   飞镖高度 h 会打到「身体顶面高度 b」的身体，当 h ∈ [b - RADIUS, b + RADIUS + 体型高度]
		#   站立体型高 66 → 撞上条件 h <= 66 + 11 = 77
		#   滑铲体型高 32 → 撞上条件 h <= 32 + 11 = 43
		# 所以 h ∈ (43, 77] 这一层是「只能滑铲」。
		#
		# 旧实现写成 h > BODY_SIZE.y + RADIUS（即 > 77），恰好把这一层排除掉了，
		# 滑铲分支永远不触发，胸前高度的飞镖必经伤。
		if heights.size() == 1 \
				and heights[0] <= Motion.BODY_SIZE.y + Dart.RADIUS \
				and heights[0] > Motion.SLIDE_HEIGHT + Dart.RADIUS:
			# 滑铲必须在「飞镖到达的那一刻」仍然有效。
			# 滑铲持续 0.58s，所以起手时机要让它覆盖 t=0 前后，
			# 而不是一进入 0.75s 窗口就按下（那会让滑铲在飞镖到达前就结束）。
			if not acted and player.is_on_floor() and time > 0.05 and time < 0.42:
				press("slide")
				batch["handled"] = true
				acted = true
			continue
		# 多枚同拍（上下门 / 竖排）：找列与列之间的缺口，钻过去。
		if heights.size() > 1:
			var minimum: float = heights[0]
			var maximum := INF
			for index in range(1, heights.size()):
				if heights[index] - heights[index - 1] > Motion.BODY_SIZE.y + Dart.RADIUS * 2.0:
					minimum = heights[index - 1] + Dart.RADIUS + 5.0
					maximum = heights[index] - Motion.BODY_SIZE.y - Dart.RADIUS - 5.0
					break
			# 缺口在下方（低位安全门）→ 滑铲；缺口在上方 → 起跳。
			if not acted and player.is_on_floor() and time > 0.05 and time < 0.42 \
					and minimum <= Motion.SLIDE_HEIGHT:
				press("slide")
				batch["handled"] = true
				acted = true
				continue
			if not acted and player.is_on_floor() and time > 0.0 and time <= 0.55:
				press("jump")
				batch["handled"] = true
				acted = true
			continue
		# 中位 / 高位飞镖（h > 77）：站着本来就是安全的，
		# 起跳反而会把脚底送进受击区间（单跳顶点 184.5 正落在 h=200 的区间里）。
		# 所以这类飞镖的正确解法是「保持地面」，不是跳。
		#
		# 这一支是「姿态」而非「动作」：不能因为它 return 就跳过后面的 batch。
		# 若此刻在空中就要主动落地（下落比上升安全），但同样不能抢占动手名额。
		if heights[0] > Motion.BODY_SIZE.y + Dart.RADIUS:
			if batch.get("grounded_ok", false):
				continue
			batch["grounded_ok"] = true
			if not player.is_on_floor() and time < 0.55 and not player.fast_falling:
				press("slide")
				# 这里不设 handled：落地动作要在随后几帧继续确认，
				# 直到真的 on_floor 为止。
			continue
		# 通过高度 = 飞镖高度 + 飞镖半径 + 身高（脚底必须高过飞镖上沿再让出身位）。
		# 判据与 player.gd 的真实受击一致：飞镖 h 会打到脚底高度 f ∈ (h-11, h+77)。
		# 所以安全条件是 f >= h + 77，留一点余量取 +82。
		var safe_feet: float = heights[0] + Motion.BODY_SIZE.y + Dart.RADIUS + 5.0
		# 起跳决策必须看「相遇那一刻的预测高度」，而不是「提前量够不够」。
		# 旧实现只看 lead（0.24 / 0.34s），再在飞镖接近时补二跳，
		# 结果常在上升半途被飞镖追上 —— 玩家脚底只到 79，而 h=66 需要 > 77。
		if not acted and player.is_on_floor() and time > 0.0 and time <= 0.55:
			if _jump_clears(time, safe_feet):
				press("jump")
				batch["handled"] = true
				acted = true
			continue
		if not acted and not player.is_on_floor() and player.jumps_used < 2 \
				and time > 0.0 and time <= 0.40:
			# 已在空中但仍会在相遇时被撞到 → 用二段跳把轨迹抬起来。
			if not _jump_clears(time, safe_feet) and frame_number - last_jump > 6:
				var with_second := predicted_height_after_jump(time, true)
				if with_second >= safe_feet:
					press("jump")
					batch["handled"] = true
					acted = true
			continue

# 从当前状态起跳（或已在空中）后，time 秒时的预测脚底高度。
# second 为 true 时把二段跳立刻用掉。
func predicted_height_after_jump(time: float, second := false) -> float:
	var height: float = Motion.GROUND_Y - player.global_position.y
	var velocity: float = player.velocity.y
	if second:
		velocity = player.SECOND_JUMP_SPEED
	var steps := maxi(1, int(ceil(time * 60.0)))
	var step := time / steps
	for index in steps:
		velocity += (player.ASCENT_GRAVITY if velocity < 0.0 else player.FALL_GRAVITY) * step
		height -= velocity * step
	return maxf(0.0, height)

# 现在起跳，能否在相遇时（time 秒后）把脚底抬到 target 以上。
func _jump_clears(time: float, target: float) -> bool:
	if player.is_on_floor():
		var h: float = Motion.GROUND_Y - player.global_position.y
		var v: float = player.JUMP_SPEED
		var steps := maxi(1, int(ceil(time * 60.0)))
		var step := time / steps
		for index in steps:
			v += (player.ASCENT_GRAVITY if v < 0.0 else player.FALL_GRAVITY) * step
			h -= v * step
		return h >= target
	return predicted_height_after_jump(time) >= target

func predicted_height(time: float) -> float:
	var height: float = Motion.GROUND_Y - player.global_position.y
	var velocity: float = player.velocity.y
	var steps := maxi(1, int(ceil(time * 60.0)))
	var step := time / steps
	for index in steps:
		velocity += (player.ASCENT_GRAVITY if velocity < 0.0 else player.FALL_GRAVITY) * step
		height -= velocity * step
	return maxf(0.0, height)

func press(action: String) -> void:
	if action == "slide" and player.fast_falling:
		return
	if action == "slide":
		slide_inputs += 1
	Input.action_press(action)
	held_action = action
	# 输入需要保持几帧才可靠：
	#   * jump  需要让 jump_buffer 有机会被 consume_buffered_jump 取走；
	#   * slide 要求 grounded 且 jump_buffer_remaining <= 0，
	#     若上一拍的跳跃缓冲还没消化完，单帧输入会被直接丢掉
	#     （旧实现每帧强制释放，滑铲因此在最关键的一拍静默失效）。
	hold_frames = 3
	if action == "jump":
		last_jump = frame_number

func on_spawn(_event: PatternEvent, obstacle: Node2D) -> void:
	spawned += 1
	var point := root.get_canvas_transform() * obstacle.global_position
	if point.x - Dart.RADIUS <= root.get_visible_rect().end.x:
		screen_spawns += 1

func on_damage(_amount: float) -> void:
	damage_count += 1
	print("DAMAGE x=%.1f height=%.1f stage=%s" % [player.global_position.x, Motion.GROUND_Y - player.global_position.y, module.debug_info_at(player.global_position.x).get("stage", "")])
	print("  [DBG] on_floor=%s vel=%s slide=%.2f jumpbuf=%.2f held=%d" % [
		str(player.is_on_floor()), str(player.velocity), player.slide_remaining,
		player.jump_buffer_remaining, hold_frames])
	for b in groups:
		var t: float = (b.x - player.global_position.x) / Motion.RUN_SPEED
		if t > -0.35 and t < 0.5:
			print("  [DBG]   邻 batch x=%.1f h=%s t=%+.3f" % [b.x, str(b.heights), t])

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + filename)

func try_boost() -> void:
	if not boost_enabled or not player.is_on_floor() or frame_number - last_slide < 130:
		return
	for batch in groups:
		var time: float = (batch.x - player.global_position.x) / maxf(Motion.RUN_SPEED, player.velocity.x)
		if time < -0.1:
			continue
		if time > 0.6:
			press("slide")
			last_slide = frame_number
			slide_count += 1
		return

func check_pause() -> void:
	pause_checked = true
	var before: Vector2 = player.global_position
	var clocks: Array[float] = []
	for section in module.sections:
		for runner in section.runners:
			clocks.append(runner.elapsed)
	world.toggle_pause()
	for index in 4:
		await process_frame
	if player.global_position != before:
		failures.append("暂停期间玩家仍移动")
	var index := 0
	for section in module.sections:
		for runner in section.runners:
			if runner.elapsed != clocks[index]:
				failures.append("暂停期间 Wave 仍推进")
			index += 1
	world.toggle_pause()

func check_restart() -> void:
	var expected_length: float = module.total_length
	if not get_nodes_in_group("dart").is_empty():
		failures.append("出口仍残留飞镖")
	if not held_action.is_empty():
		Input.action_release(held_action)
		held_action = ""
	world.restart_run()
	await physics_frame
	await process_frame
	var rebuilt: Node = null
	for chunk in world.active_chunks:
		if "module_data" in chunk:
			rebuilt = chunk
			break
	if rebuilt == null or rebuilt.total_length != expected_length:
		failures.append("重开没有还原完整地图")
	if not get_nodes_in_group("dart").is_empty():
		failures.append("重开残留飞镖")
	print("PAUSE/EXIT/RESTART checked")
