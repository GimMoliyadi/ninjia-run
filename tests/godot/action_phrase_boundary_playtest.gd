extends "res://tests/godot/action_phrase_playtest.gd"

const CYCLES := 2
const BOUNDARY_MAX_FRAMES := 9000
const PAUSE_FRAMES := 8
const FAST_FALL_LEAD := 0.28
const DOUBLE_JUMP_DELAY := 0.18
const RESTART_MAX_FRAMES := 600
const MODES := ["normal", "momentum", "double", "continuous"]
var mode := "normal"
var records: Array[Dictionary] = []
var seen := {}
var frame_number := 0
var cycle_size := 0
var run_damage := 0
var recovery_contacts := 0
var recovery_coins := 0
var second_jumps := 0
var peak_speed := 0.0
var peak_entry_speed := 0.0
var entry_peaks := {}
var first_jump_frame := -1
var pause_checked := false
var reclaimed := 0
var measured_phrases := 0
var measured_recoveries := 0
var phrase_min := INF
var phrase_max := 0.0
var recovery_min := INF
var recovery_max := 0.0
var continuous_target := -1
var finish_safe_seams := 0
var target_started := false
var target_damage := 0

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
	if mode not in MODES:
		failures.append("未知输入策略：" + mode)
	else:
		for seed in SEEDS:
			if mode == "continuous":
				for kind in PracticeRoute.ACTION_COMBINATIONS:
					continuous_target = kind
					await play_stream(seed)
			else:
				await play_stream(seed)
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)

func play_stream(seed: int) -> void:
	reset_measurements()
	world = World.instantiate()
	world.set_script(PracticeWorld)
	world.route_seed = seed
	root.add_child(world)
	current_scene = world
	player = world.player
	cycle_size = PracticeRoute.new(seed).build_cycle(0).size()
	player.damaged.connect(func(_amount: float):
		run_damage += 1
		for record in records:
			if target_started and record.kind == continuous_target and player.global_position.x >= record.entry and player.global_position.x < record.exit:
				target_damage += 1)
	player.state_changed.connect(func(_previous: int, state: int):
		if state == player.MovementState.SLIDE:
			record_action("slide"))
	player.jumped.connect(func(index: int):
		record_action("jump")
		if index == 1:
			first_jump_frame = frame_number
		else:
			second_jumps += 1)
	var input := PhysicsInput.new()
	input.step = drive
	world.add_child(input)
	var reached := false
	for frame in BOUNDARY_MAX_FRAMES:
		frame_number = frame
		await physics_frame
		await process_frame
		discover_chunks()
		measure_progress()
		if not pause_checked and records.size() > cycle_size and player.global_position.x >= records[cycle_size - 1].entry:
			await pause_stream()
		if records.size() > cycle_size * CYCLES and records[cycle_size * CYCLES].done:
			reached = true
			break
		if mode == "continuous" and target_started and target_damage > 0:
			break
		if not player.active:
			break
	release()
	check_trial(seed, reached)
	if mode != "continuous":
		await probe_restart(seed)
	paused = false
	world.free()
	await process_frame

func check_trial(seed: int, reached: bool) -> void:
	print("BOUNDARY seed=%d mode=%s reached=%s damage=%d recovery_contacts=%d recovery_coins=%d second_jumps=%d peak=%.2f entry_peak=%.2f phrases=%d [%.3f,%.3f] recoveries=%d [%.3f,%.3f] reclaimed=%d pause=%s" % [seed, mode, reached, run_damage, recovery_contacts, recovery_coins, second_jumps, peak_speed, peak_entry_speed, measured_phrases, phrase_min, phrase_max, measured_recoveries, recovery_min, recovery_max, reclaimed, pause_checked])
	if mode == "continuous":
		print("CONTINUOUS target=%s started=%s target_damage=%d" % [PracticeRoute.ChunkKind.keys()[continuous_target], target_started, target_damage])
		if not target_started or target_damage == 0:
			failures.append("连续跳不铲的负对照未命中指定组合：%d %d" % [seed, continuous_target])
	else:
		if not reached or run_damage > 0:
			failures.append("两轮真实流式练习路线未无伤完成：%d %s" % [seed, mode])
		if recovery_contacts > 0 or recovery_coins == 0:
			failures.append("喘息存在攻击接触或没有真实拾币")
		if measured_phrases != CYCLES * PracticeRoute.GROUP_COUNT * PracticeRoute.ENCOUNTERS_PER_GROUP or measured_recoveries != measured_phrases:
			failures.append("两轮组合/喘息没有完整实测")
		if reclaimed == 0 or not pause_checked or finish_safe_seams < CYCLES:
			failures.append("未覆盖正常回收、暂停恢复及两次 FINISH→SAFE")
		for record in records.slice(0, cycle_size * CYCLES):
			if record.spawned != record.expected or record.finished != record.runners:
				failures.append("流式障碍生成/Runner完成数不匹配")
		if mode == "double" and second_jumps == 0:
			failures.append("二段跳策略没有实际触发二段跳")
		if mode == "momentum":
			for kind in PracticeRoute.ACTION_COMBINATIONS:
				if entry_peaks.get(kind, 0.0) < Motion.Player.SLIDE_BURST_SPEED - Motion.Player.SURFACE_DRAG / PHYSICS_FPS:
					failures.append("组合未以可达峰速进入：%d" % kind)

func reset_measurements() -> void:
	records.clear()
	seen.clear()
	obstacles.clear()
	run_damage = 0
	recovery_contacts = 0
	recovery_coins = 0
	second_jumps = 0
	peak_speed = 0.0
	peak_entry_speed = 0.0
	entry_peaks.clear()
	first_jump_frame = -1
	pause_checked = false
	reclaimed = 0
	measured_phrases = 0
	measured_recoveries = 0
	phrase_min = INF
	phrase_max = 0.0
	recovery_min = INF
	recovery_max = 0.0
	finish_safe_seams = 0
	target_started = false
	target_damage = 0

func discover_chunks() -> void:
	for chunk: Node2D in world.active_chunks:
		var id := chunk.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		var index := records.size()
		var route := PracticeRoute.new(world.route_seed).build_cycle(index / cycle_size)
		var kind: int = route[index % cycle_size]
		var record := {"node": weakref(chunk), "entry": chunk.get_node("Entry").global_position.x,
			"exit": chunk.get_node("Exit").global_position.x, "kind": kind,
			"start": -1, "done": false, "freed": false, "coins": 0, "contacts": 0,
			"jump": 0, "slide": 0, "spawned": 0, "expected": 0, "finished": 0, "runners": 0}
		if kind == PracticeRoute.ChunkKind.SAFE and not records.is_empty() and records.back().kind == PracticeRoute.ChunkKind.FINISH:
			finish_safe_seams += 1
		if not records.is_empty() and not is_equal_approx(record.entry, records.back().exit):
			failures.append("真实流式 Entry/Exit 接缝错位")
		records.append(record)
		if chunk is MapModuleChunk:
			failures.append_array(chunk.debug_info().issues)
			for section in chunk.sections:
				for child in section.get_children():
					if child is Coin and kind == PracticeRoute.ChunkKind.SHORT_RECOVERY:
						child.collected.connect(func(_body: Node2D, _score: int, _energy: float):
							recovery_coins += 1
							record.coins += 1)
				for runner in section.runners:
					record.expected += runner.plan.events.size()
					record.runners += 1
					runner.finished.connect(func(): record.finished += 1)
					runner.event_spawned.connect(func(_event: PatternEvent, obstacle: Node2D):
						record.spawned += 1
						if obstacle.has_signal("player_contact"):
							obstacle.player_contact.connect(record_contact))
					for event in runner.plan.events:
						if event.preview_kind != PatternEvent.PreviewKind.DART:
							obstacles.append({"x": runner.global_position.x + event.position_offset.x,
								"end": runner.global_position.x + event.position_offset.x + event.preview_size.x,
								"slide": event.preview_kind == PatternEvent.PreviewKind.CEILING,
								"height": event.preview_size.y})
	obstacles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.x < b.x)

func record_contact(_body: Node2D, _amount: float) -> void:
	for record in records:
		if record.kind == PracticeRoute.ChunkKind.SHORT_RECOVERY and player.global_position.x >= record.entry and player.global_position.x < record.exit:
			recovery_contacts += 1
			record.contacts += 1

func measure_progress() -> void:
	peak_speed = maxf(peak_speed, player.velocity.x)
	for record in records:
		if record.node.get_ref() == null and not record.freed:
			record.freed = true
			reclaimed += 1
		if player.global_position.x < record.entry or record.done:
			continue
		if record.start < 0:
			record.start = frame_number
			if record.kind in PracticeRoute.ACTION_COMBINATIONS:
				peak_entry_speed = maxf(peak_entry_speed, player.velocity.x)
				entry_peaks[record.kind] = maxf(entry_peaks.get(record.kind, 0.0), player.velocity.x)
		if player.global_position.x < record.exit:
			continue
		record.done = true
		var seconds: float = (frame_number - record.start) / PHYSICS_FPS
		if record.kind in PracticeRoute.ACTION_COMBINATIONS:
			measured_phrases += 1
			phrase_min = minf(phrase_min, seconds)
			phrase_max = maxf(phrase_max, seconds)
			if mode != "continuous" and (seconds < 3.0 or seconds > 7.0 or record.jump == 0 or record.slide == 0):
				failures.append("实跑组合时长或跳/低身输入缺失：%s" % str(record))
		elif record.kind == PracticeRoute.ChunkKind.SHORT_RECOVERY:
			measured_recoveries += 1
			recovery_min = minf(recovery_min, seconds)
			recovery_max = maxf(recovery_max, seconds)
			if mode != "continuous" and (seconds < Motion.jump_time() or seconds > 1.5 or record.coins == 0):
				failures.append("真实喘息时长/拾币不合规：%.3f coins=%d" % [seconds, record.coins])

func pause_stream() -> void:
	release()
	var before := Vector3(player.global_position.x, player.global_position.y, world.arena_x)
	var timers := {}
	for chunk in world.active_chunks:
		if chunk is MapModuleChunk:
			for section in chunk.sections:
				for runner in section.runners:
					timers[runner] = runner.elapsed
	world.toggle_pause()
	for frame in PAUSE_FRAMES:
		await physics_frame
		await process_frame
	if before != Vector3(player.global_position.x, player.global_position.y, world.arena_x):
		failures.append("回收后的暂停仍推进玩家/世界")
	for runner in timers:
		if runner.elapsed != timers[runner]:
			failures.append("暂停仍推进距离型障碍")
	world.toggle_pause()
	# 暂停帧不计入移动经过时间。
	pause_checked = true

func probe_restart(seed: int) -> void:
	var old_chunks: Array = world.active_chunks.duplicate()
	world.toggle_pause()
	world.restart_run()
	if paused or world.energy != 0.0 or player.boost_speed != 0.0 or player.global_position != world.START_POSITION:
		failures.append("暂停重开未恢复状态：%d" % seed)
	records.clear()
	seen.clear()
	obstacles.clear()
	var before_damage := run_damage
	var completed := false
	for frame in RESTART_MAX_FRAMES:
		frame_number = frame
		await physics_frame
		await process_frame
		discover_chunks()
		measure_progress()
		if records.size() > 1 and records[1].done:
			completed = true
			break
	for chunk in old_chunks:
		if is_instance_valid(chunk):
			failures.append("重开后旧 Chunk 未回收")
	if not completed or run_damage != before_damage:
		failures.append("重开后首个组合未真实无伤完成")
	release()

func drive() -> void:
	if mode == "continuous":
		for record in records:
			if record.kind == continuous_target and player.global_position.x >= record.entry and player.global_position.x < record.exit:
				target_started = true
		if not target_started:
			super.drive()
			return
		release()
		if player.is_on_floor() or (player.jumps_used == 1 and player.velocity.y >= 0.0):
			press("jump")
		return
	if mode == "normal":
		super.drive()
		return
	release()
	var px: float = player.global_position.x
	var speed: float = player.run_speed + player.boost_speed
	if mode == "momentum" and player.is_on_floor() and not player.is_sliding():
		for record in records:
			if record.kind in PracticeRoute.ACTION_COMBINATIONS and record.entry > px and record.entry - px <= speed * Motion.Player.SLIDE_DURATION * 0.5:
				press("slide")
				return
	for obstacle in obstacles:
		if obstacle.end + Motion.BODY_SIZE.x * 0.5 < px:
			continue
		if obstacle.slide:
			if not player.is_on_floor() and obstacle.x - px < speed * FAST_FALL_LEAD and not player.fast_falling:
				press("slide")
			elif player.is_on_floor() and not player.is_sliding() and obstacle.x - px <= speed * SLIDE_LEAD_SECONDS:
				press("slide")
			return
		var height: float = Motion.GROUND_Y - player.global_position.y
		if mode == "double" and player.jumps_used == 1 and frame_number - first_jump_frame >= int(DOUBLE_JUMP_DELAY * PHYSICS_FPS):
			press("jump")
			return
		if height > obstacle.height and px >= obstacle.x - Motion.BODY_SIZE.x * 0.5:
			return
		if player.is_on_floor() and obstacle.x - Motion.BODY_SIZE.x * 0.5 - px <= speed * JUMP_LEAD_SECONDS:
			press("jump")
		elif mode == "momentum" and player.is_on_floor() and not player.is_sliding():
			press("slide")
		return

func record_action(action: String) -> void:
	for record in records:
		if player.global_position.x >= record.entry and player.global_position.x < record.exit:
			record[action] += 1
			break
