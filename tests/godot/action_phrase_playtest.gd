extends SceneTree

const World := preload("res://test_world.tscn")
const PracticeWorld := preload("res://tests/godot/action_phrase_practice_world.gd")
const PracticeRoute := PracticeWorld.PracticeRoute
const Motion := preload("res://patterns/player_motion_profile.gd")
const PhysicsInput := preload("res://tests/physics_input.gd")
const SEEDS := [20260909, 20260913, 20261001]
const MAX_FRAMES := 6000
const PHYSICS_FPS := 60.0
const CAPTURE_FRAME := 420
const SLIDE_LEAD_SECONDS := 0.16
const JUMP_LEAD_SECONDS := 0.24
const LANDING_HEIGHT_TOLERANCE := 2.0
var world: Node2D
var player: Node2D
var obstacles: Array[Dictionary] = []
var held := ""
var damages := 0
var jumps := 0
var slides := 0
var platform_landings := 0
var failures := PackedStringArray()
var timing := {}
var trials := {}
var jump_enabled := true
var capture_enabled := false
var spawned := 0
var expected_spawns := 0
var completed_runners := 0
var expected_runners := 0
var slide_enabled := true

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		capture_enabled = capture_enabled or argument == "--capture"
		jump_enabled = jump_enabled and argument != "--no-jump"
		slide_enabled = slide_enabled and argument != "--no-slide"
	for seed in SEEDS:
		await play(seed)
	if not jump_enabled or not slide_enabled:
		if damages == 0:
			failures.append("删去必要动作仍然无伤，组合没有真实操作要求")
		else:
			print("必要动作负对照通过：禁用 jump=", not jump_enabled, " slide=", not slide_enabled, " damage=", damages)
	else:
		if damages > 0 or jumps == 0 or slides == 0 or platform_landings == 0:
			failures.append("技能关闭的练习路线未无伤完成跳、铲、落台")
		if spawned != expected_spawns or completed_runners != expected_runners:
			failures.append("真实障碍未完整生成或 Runner 未回收")
	for failure in failures:
		printerr(failure)
	print("ACTION_PHRASES seeds=%d damage=%d jump=%d slide=%d platform_landings=%d spawned=%d/%d runners=%d/%d timings=%s" % [SEEDS.size(), damages, jumps, slides, platform_landings, spawned, expected_spawns, completed_runners, expected_runners, str(trials)])
	quit(0 if failures.is_empty() else 1)

func play(seed: int) -> void:
	world = World.instantiate()
	world.set_script(PracticeWorld)
	world.route_seed = seed
	root.add_child(world)
	current_scene = world
	player = world.player
	var route := PracticeRoute.new(seed).build_cycle(0)
	while world.active_chunks.size() < route.size():
		world.spawn_chunk()
	var chunks: Array[Node2D] = world.active_chunks.duplicate()
	var end_x: float = chunks.back().get_node("Entry").global_position.x
	obstacles.clear()
	timing.clear()
	collect_obstacles(chunks)
	player.damaged.connect(func(_amount: float):
		damages += 1
		print("DAMAGE x=", player.global_position.x, " y=", player.global_position.y))
	player.landed.connect(func(_speed: float):
		if player.global_position.y < Motion.GROUND_Y - LANDING_HEIGHT_TOLERANCE:
			platform_landings += 1)
	var input := PhysicsInput.new()
	input.step = drive
	world.add_child(input)
	await run_frames(seed, route, chunks, end_x)
	if player.global_position.x < end_x and jump_enabled and slide_enabled:
		failures.append("练习首圈未到达收尾区")
	release()
	paused = false
	world.free()
	await process_frame

func collect_obstacles(chunks: Array[Node2D]) -> void:
	for chunk in chunks:
		if not chunk is MapModuleChunk:
			continue
		failures.append_array(chunk.debug_info().issues)
		failures.append_array(chunk.act_report.get("notes", []))
		for section in chunk.sections:
			for runner in section.runners:
				expected_runners += 1
				expected_spawns += runner.plan.events.size()
				runner.event_spawned.connect(func(_event: PatternEvent, _obstacle: Node2D): spawned += 1)
				runner.finished.connect(func(): completed_runners += 1)
				for event in runner.plan.events:
					if event.preview_kind == PatternEvent.PreviewKind.DART:
						continue
					obstacles.append({"x": runner.global_position.x + event.position_offset.x,
						"end": runner.global_position.x + event.position_offset.x + event.preview_size.x,
						"slide": event.preview_kind == PatternEvent.PreviewKind.CEILING,
						"height": event.preview_size.y})
	obstacles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.x < b.x)

func run_frames(seed: int, route: Array[int], chunks: Array[Node2D], end_x: float) -> void:
	for frame in MAX_FRAMES:
		await physics_frame
		await process_frame
		record_timings(seed, route, chunks, frame)
		if capture_enabled and seed == SEEDS[0] and frame == CAPTURE_FRAME:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/artifacts/action-phrase.png")
		if player.global_position.x >= end_x or not player.active:
			break

func record_timings(seed: int, route: Array[int], chunks: Array[Node2D], frame: int) -> void:
	for index in range(1, chunks.size() - 1):
		var chunk: Node2D = chunks[index]
		if not is_instance_valid(chunk):
			continue
		var key := str(index)
		if player.global_position.x >= chunk.get_node("Entry").global_position.x and not timing.has(key):
			timing[key] = frame
		if timing.has(key) and player.global_position.x >= chunk.get_node("Exit").global_position.x and not trials.has(str(seed) + key):
			var seconds: float = (frame - timing[key]) / PHYSICS_FPS
			trials[str(seed) + key] = seconds
			if jump_enabled and slide_enabled:
				if route[index] in PracticeRoute.ACTION_COMBINATIONS and (seconds < 3.0 or seconds > 7.0):
					failures.append("实际组合时间越界：%.2f" % seconds)
				if route[index] == PracticeRoute.ChunkKind.SHORT_RECOVERY and (seconds < Motion.jump_time() or seconds > 1.5):
					failures.append("实际喘息没有覆盖一个落地周期：%.2f" % seconds)

func drive() -> void:
	release()
	var px: float = player.global_position.x
	var speed: float = player.run_speed + player.boost_speed
	for obstacle in obstacles:
		if obstacle.end + Motion.BODY_SIZE.x * 0.5 < px:
			continue
		if obstacle.slide:
			if slide_enabled and player.is_on_floor() and not player.is_sliding() and obstacle.x - px <= speed * SLIDE_LEAD_SECONDS:
				press("slide")
			return
		var height: float = Motion.GROUND_Y - player.global_position.y
		if height > obstacle.height and px >= obstacle.x - Motion.BODY_SIZE.x * 0.5:
			return
		if jump_enabled and player.is_on_floor() and obstacle.x - Motion.BODY_SIZE.x * 0.5 - px <= speed * JUMP_LEAD_SECONDS:
			press("jump")
		return

func press(action: String) -> void:
	Input.action_press(action)
	held = action
	if action == "jump":
		jumps += 1
	else:
		slides += 1

func release() -> void:
	if not held.is_empty():
		Input.action_release(held)
		held = ""
