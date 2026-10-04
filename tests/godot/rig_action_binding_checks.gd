extends RefCounted

const Stub = preload("res://tests/godot/rig_action_state_stub.gd")
const VISUAL = preload("res://visuals/rig_v2/player_visual_v2.tscn")
const VersionSwitch = preload("res://visuals/visual_version_switch.gd")
const SoleProbe = preload("res://tests/godot/rig_action_sole_probe.gd")
const RunChecks = preload("res://tests/godot/rig_action_run_checks.gd")
const SUPPORT_WORLD_DRIFT_LIMIT := 0.1

class LegacyVisual extends Node2D:
	var visual_enabled := true
	var animator := AnimationPlayer.new()

	func _init() -> void:
		add_child(animator)

	func set_visual_enabled(enabled: bool) -> void:
		visual_enabled = enabled
		visible = enabled
		process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		if not enabled:
			animator.pause()


static func run(root: Node, check: Callable) -> void:
	var stub := Stub.new()
	root.add_child(stub)
	var visual: Node2D = VISUAL.instantiate()
	stub.add_child(visual)
	visual.set_process(false)
	var animator: AnimationPlayer = visual.animation_player
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	check.call(visual.scale == Vector2.ONE and visual.orientation.scale == Vector2.ONE, "包装必须使用未缩放游戏像素空间")
	_check_priority(stub, visual, check)
	_check_run_speed_tracking(stub, visual, check)
	_check_run_flight_state(stub, visual, check)
	_check_wrapper_ground(stub, visual, check)
	_check_pending(stub, visual, check)
	_check_repeat_event(stub, visual, check)
	_check_repeat_land_and_priority(stub, visual, check)
	_check_rope(stub, visual, check)
	_check_signals(stub, visual, check)
	_check_versions(stub, visual, check)
	visual.free()
	check.call(stub.get_signal_connection_list(&"jumped").is_empty() and stub.get_signal_connection_list(&"landed").is_empty() and stub.get_signal_connection_list(&"run_reset").is_empty(), "退出树必须断开 Player 信号")
	stub.free()
	_check_standalone(root, check)
	_check_scene_paths(check)


static func _expect_pose(stub: Node2D, visual: Node2D, action: StringName, check: Callable) -> void:
	var before: Array = stub.snapshot()
	visual.update_pose()
	check.call(visual.visual_animation == action, "状态优先级错误：预期 %s，实际 %s" % [action, visual.visual_animation])
	check.call(stub.snapshot() == before, "V2 只能读取 Player 状态，不能写入")
	check.call(visual.rig.get_node("Skeleton2D/Root").rotation == 0.0, "整身转角必须在外层处理")
	check.call(is_equal_approx(visual.animation_player.speed_scale, absf(stub.velocity.x) / stub.RUN_SPEED if action == &"run" else 1.0), "run 步频须跟随实际水平速度，其他动作保持原速")


static func _check_priority(stub: Node2D, visual: Node2D, check: Callable) -> void:
	_expect_pose(stub, visual, &"run", check)
	stub.velocity.x = 900.0
	_expect_pose(stub, visual, &"run", check)
	stub.velocity.x = 0.0
	_expect_pose(stub, visual, &"idle", check)
	stub.movement_state = stub.MovementState.SLIDE
	stub.flipping = true
	stub.air_state = stub.AirState.DOUBLE_JUMP_ROLL
	stub.active = false
	_expect_pose(stub, visual, &"idle", check)
	stub.active = true
	_expect_pose(stub, visual, &"slide", check)
	stub.movement_state = stub.MovementState.AIRBORNE
	stub.flipping = false
	stub.roll_hitbox_active = true
	stub.roll_remaining = stub.DOUBLE_JUMP_ROLL_DURATION / 2.0
	stub.velocity = Vector2(900.0, 100.0)
	_expect_pose(stub, visual, &"double_jump", check)
	check.call(is_equal_approx(visual.action_pivot.rotation, PI) and visual.action_pivot.position.y == -20.0 and visual.rig.position.y == 20.0, "二段翻滚必须以游戏像素支点旋转，不受 0.055 缩放污染")
	stub.air_state = stub.AirState.FALL
	stub.roll_hitbox_active = false
	_expect_pose(stub, visual, &"fall", check)
	stub.velocity.y = -100.0
	_expect_pose(stub, visual, &"jump_up", check)
	stub.velocity.y = 0.0
	_expect_pose(stub, visual, &"fall", check)


static func _check_run_speed_tracking(stub: Node2D, visual: Node2D, check: Callable) -> void:
	stub.active = true
	stub.flipping = false
	stub.roll_hitbox_active = false
	stub.movement_state = stub.MovementState.GROUNDED
	stub.air_state = stub.AirState.NONE
	stub.velocity = Vector2(stub.RUN_SPEED, 0.0)
	visual.reset_visual()
	visual.animation_player.advance(RunChecks.BLEND_SECONDS)
	var origin := stub.position
	var skeleton: Skeleton2D = visual.rig.get_node("Skeleton2D")
	for side in range(2):
		var side_name: String = ["L", "R"][side]
		var sole := SoleProbe.new(visual.rig.get_node("Skin/Leg_%s" % side_name), skeleton.find_child("Shin_%s" % side_name, true, false))
		for speed in [120.0, 400.0, 500.0, 560.0, 620.0, 900.0]:
			stub.velocity.x = speed
			var elapsed: float = visual.animation_player.current_animation_position
			_expect_pose(stub, visual, &"run", check)
			check.call(is_equal_approx(visual.animation_player.current_animation_position, elapsed), "同一跑步动作变速不能重启动画")
			for fps in [30.0, 60.0, 120.0]:
				_check_speed_support(stub, visual, sole, side, fps, check)
	stub.position = origin


static func _check_speed_support(stub: Node2D, visual: Node2D, sole: RefCounted, side: int, fps: float, check: Callable) -> void:
	var animator: AnimationPlayer = visual.animation_player
	var skeleton: Skeleton2D = visual.rig.get_node("Skeleton2D")
	var cycle: float = animator.get_animation(&"run").length
	var contact_seconds := cycle * RunChecks.SUPPORT_FRACTION
	animator.seek(side * cycle / 2.0 + contact_seconds * 0.05, true)
	var planted: Vector2 = visual.rig.to_global(sole.contact() + skeleton.position)
	var remaining := contact_seconds * 0.9 / animator.speed_scale
	var maximum_drift := 0.0
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / fps)
		stub.position.x += stub.velocity.x * step
		visual.update_pose()
		animator.advance(step)
		var current: Vector2 = visual.rig.to_global(sole.contact() + skeleton.position)
		maximum_drift = maxf(maximum_drift, absf(current.x - planted.x))
		remaining -= step
	check.call(maximum_drift <= SUPPORT_WORLD_DRIFT_LIMIT, "run %.0fpx/s、%.0fFPS 的 %d 侧支撑脚世界滑移 %.5fpx 超标" % [stub.velocity.x, fps, side, maximum_drift])


static func _check_run_flight_state(stub: Node2D, visual: Node2D, check: Callable) -> void:
	stub.active = true
	stub.flipping = false
	stub.roll_hitbox_active = false
	stub.movement_state = stub.MovementState.GROUNDED
	stub.air_state = stub.AirState.NONE
	stub.velocity = Vector2(stub.RUN_SPEED, 0.0)
	visual.reset_visual()
	var actor_state: Array = stub.snapshot()
	visual.animation_player.advance(RunChecks.BLEND_SECONDS)
	var skeleton: Skeleton2D = visual.rig.get_node("Skeleton2D")
	var soles: Array = []
	for side in ["L", "R"]:
		soles.append(SoleProbe.new(visual.rig.get_node("Skin/Leg_%s" % side), skeleton.find_child("Shin_%s" % side, true, false)))
	var flight_keys := 0
	var state_preserved := true
	for key in range(RunChecks.KEY_INTERVALS):
		visual.animation_player.seek(RunChecks.CYCLE_SECONDS * key / RunChecks.KEY_INTERVALS, true)
		visual.update_pose()
		state_preserved = state_preserved and stub.snapshot() == actor_state and visual.visual_animation == &"run"
		if maxf(soles[0].height(), soles[1].height()) + skeleton.position.y < -RunChecks.KEY_TOLERANCE:
			flight_keys += 1
	check.call(state_preserved and flight_keys > 0, "run 视觉腾空不得切换 Actor GROUNDED/空中状态、速度、位置或 jump 动作")
	print("VISUAL run flight keys=%d, Actor state preserved=%s, GROUNDED=%s velocity=%s (read-only stub; not real Player)" % [flight_keys, state_preserved, stub.movement_state == stub.MovementState.GROUNDED, stub.velocity])


static func _check_wrapper_ground(stub: Node2D, visual: Node2D, check: Callable) -> void:
	stub.active = true
	stub.flipping = false
	stub.roll_hitbox_active = false
	stub.air_state = stub.AirState.NONE
	stub.velocity = Vector2(400.0, 0.0)
	var skeleton: Skeleton2D = visual.rig.get_node("Skeleton2D")
	var soles: Array = []
	for side in ["L", "R"]:
		soles.append(SoleProbe.new(visual.rig.get_node("Skin/Leg_%s" % side), skeleton.find_child("Shin_%s" % side, true, false)))
	var bottom := -INF
	for phase in [0.0, 0.25, 0.5, 0.75]:
		stub.movement_state = stub.MovementState.GROUNDED
		visual.reset_visual()
		visual.animation_player.advance(0.05)
		visual.animation_player.seek(phase * visual.animation_player.get_animation(&"run").length, true)
		for state in [stub.MovementState.SLIDE, stub.MovementState.GROUNDED]:
			stub.movement_state = state
			var actor_state: Array = stub.snapshot()
			visual.update_pose()
			visual.animation_player.advance(0.025)
			var source_bottom: float = maxf(soles[0].height(), soles[1].height()) + skeleton.position.y
			bottom = maxf(bottom, visual.rig.to_global(Vector2(0.0, source_bottom)).y - stub.global_position.y)
			check.call(stub.snapshot() == actor_state, "混合接地校正不能修改 Actor 世界位置/速度/状态")
	check.call(bottom <= 0.055, "正式 wrapper 的 run↔slide 世界鞋底必须同样不穿地")
	print("VISUAL wrapper blend world sole max=%.5f gamepx" % bottom)


static func _check_pending(stub: Node2D, visual: Node2D, check: Callable) -> void:
	var previous: StringName = visual.visual_animation
	stub.landed.emit(600.0)
	check.call(visual.land_pending and visual.visual_animation == previous, "landed 只能记录 pending，不能立即播放落地")
	stub.movement_state = stub.MovementState.AIRBORNE
	stub.air_state = stub.AirState.FIRST_JUMP
	stub.velocity.y = -300.0
	stub.jumped.emit(1)
	_expect_pose(stub, visual, &"jump_start", check)
	check.call(not visual.land_pending and visual.jump_start_pending, "缓冲起跳必须清除落地 pending")
	visual.animation_player.advance(0.1)
	check.call(not visual.jump_start_pending, "jump_start 实际结束必须只清视觉 pending")
	_expect_pose(stub, visual, &"jump_up", check)
	stub.jumped.emit(1)
	_expect_pose(stub, visual, &"jump_start", check)
	stub.landed.emit(80.0)
	stub.movement_state = stub.MovementState.GROUNDED
	stub.air_state = stub.AirState.NONE
	stub.velocity = Vector2(400.0, 0.0)
	_expect_pose(stub, visual, &"land", check)
	visual.animation_player.advance(0.13)
	check.call(not visual.land_pending, "land 实际结束必须清视觉 pending")
	_expect_pose(stub, visual, &"run", check)
	stub.landed.emit(600.0)
	stub.movement_state = stub.MovementState.SLIDE
	_expect_pose(stub, visual, &"slide", check)
	check.call(not visual.land_pending, "落地后滑铲必须打断 land")
	stub.movement_state = stub.MovementState.AIRBORNE
	stub.air_state = stub.AirState.DOUBLE_JUMP_ROLL
	stub.jumped.emit(2)
	_expect_pose(stub, visual, &"double_jump", check)
	check.call(not visual.jump_start_pending, "二段跳不能保留一段起跳 pending")


static func _check_repeat_event(stub: Node2D, visual: Node2D, check: Callable) -> void:
	stub.flipping = false
	stub.active = true
	stub.air_state = stub.AirState.FIRST_JUMP
	stub.movement_state = stub.MovementState.AIRBORNE
	stub.velocity = Vector2(400.0, -300.0)
	visual.reset_visual()
	stub.jumped.emit(1)
	visual.update_pose()
	visual.animation_player.advance(0.06)
	visual.update_pose()
	check.call(is_equal_approx(visual.animation_player.current_animation_position, 0.06), "普通同动作绘制帧不得重启")
	var com: Bone2D = visual.rig.get_node("Skeleton2D").find_child("COM", true, false)
	var current_pose := com.position
	stub.jumped.emit(1)
	visual.update_pose()
	visual.animation_player.advance(0.0)
	check.call(com.position.is_equal_approx(current_pose), "同名事件重播必须从当前姿态过渡，不能先归零")
	visual.animation_player.advance(0.06)
	stub.landed.emit(80.0)
	stub.jumped.emit(1)
	visual.animation_player.advance(0.031)
	visual.update_pose()
	check.call(visual.visual_animation == &"jump_start" and visual.jump_start_pending, "旧 jump_start 结束不能清掉绘制前的新同名事件")
	check.call(is_zero_approx(visual.animation_player.current_animation_position), "最终绘制选择同名非循环动作时必须消费一次重播")
	visual.animation_player.advance(0.02)
	visual.update_pose()
	check.call(is_equal_approx(visual.animation_player.current_animation_position, 0.02), "已消费的新事件不得逐帧重播")
	print("VISUAL repeat jump action=%s time=%.5f pending=%s" % [visual.visual_animation, visual.animation_player.current_animation_position, visual.jump_start_pending])


static func _check_repeat_land_and_priority(stub: Node2D, visual: Node2D, check: Callable) -> void:
	stub.movement_state = stub.MovementState.GROUNDED
	stub.air_state = stub.AirState.NONE
	stub.velocity = Vector2(400.0, 0.0)
	stub.landed.emit(80.0)
	visual.update_pose()
	visual.animation_player.advance(0.08)
	stub.landed.emit(90.0)
	visual.animation_player.advance(0.041)
	visual.update_pose()
	check.call(visual.visual_animation == &"land" and visual.land_pending and is_zero_approx(visual.animation_player.current_animation_position), "旧 land 结束不能吞掉新的同名落地事件")
	for state in ["inactive", "slide", "fall"]:
		stub.active = state != "inactive"
		stub.movement_state = stub.MovementState.SLIDE if state == "slide" else stub.MovementState.AIRBORNE
		stub.velocity.y = 100.0
		stub.jumped.emit(1)
		stub.landed.emit(80.0)
		stub.jumped.emit(1)
		visual.update_pose()
		var expected: StringName = &"idle" if state == "inactive" else (&"slide" if state == "slide" else &"fall")
		check.call(visual.visual_animation == expected and not visual.jump_start_pending and not visual.jump_replay_requested and not visual.land_pending and not visual.land_replay_requested, "新 pending 不得抢占 %s 优先状态或遗留重播" % state)
	stub.active = true


static func _check_rope(stub: Node2D, visual: Node2D, check: Callable) -> void:
	stub.landed.emit(100.0)
	stub.movement_state = stub.MovementState.ROPE
	stub.air_state = stub.AirState.NONE
	stub.rope_side = stub.RopeSide.BOTTOM
	_expect_pose(stub, visual, &"run", check)
	check.call(not visual.land_pending and visual.orientation.scale.y == -1.0 and visual.orientation.position.y == -66.0, "绳索下方必须清 land 并外层镜像")
	stub.flipping = true
	stub.rope_flip_progress = 0.5
	stub.rope_flip_angle = PI
	stub.roll_hitbox_active = true
	stub.landed.emit(100.0)
	_expect_pose(stub, visual, &"double_jump", check)
	check.call(not visual.land_pending and visual.orientation.position.y == -33.0 and visual.orientation.scale.y == 1.0 and is_equal_approx(visual.action_pivot.rotation, PI), "绳索翻转须读取原进度/转角且不继承下方镜像")
	stub.flipping = false
	stub.roll_hitbox_active = false
	stub.rope_side = stub.RopeSide.TOP
	_expect_pose(stub, visual, &"run", check)
	check.call(visual.orientation.scale == Vector2.ONE and visual.action_pivot.rotation == 0.0, "绳索翻回上方必须清外层转角与镜像")


static func _check_signals(stub: Node2D, visual: Node2D, check: Callable) -> void:
	visual.set_visual_enabled(false)
	check.call(not visual.visible and not visual.animation_player.is_playing() and visual.process_mode == Node.PROCESS_MODE_DISABLED, "关闭 V2 必须隐藏、停动画和停处理")
	check.call(stub.get_signal_connection_list(&"jumped").is_empty() and not visual.animation_player.animation_finished.is_connected(visual.on_animation_finished), "关闭 V2 必须断开信号")
	visual.on_jump(1)
	visual.on_land(100.0)
	visual.on_animation_finished(&"land")
	visual.reset_visual()
	check.call(not visual.jump_start_pending and not visual.land_pending and visual.visual_animation == &"", "关闭后的信号回调必须 guard")
	visual.set_visual_enabled(true)
	visual.set_visual_enabled(true)
	check.call(stub.get_signal_connection_list(&"jumped").size() == 1, "重复启用不得重复连接信号")
	stub.run_reset.emit()
	check.call(visual.orientation.scale == Vector2.ONE and visual.action_pivot.rotation == 0.0 and not visual.land_pending, "run_reset 必须清理外层与 pending")


static func _check_versions(stub: Node2D, visual: Node2D, check: Callable) -> void:
	visual.name = &"PlayerVisual_V2"
	var legacy := LegacyVisual.new()
	legacy.name = &"PlayerVisual"
	stub.add_child(legacy)
	var switch := VersionSwitch.new()
	stub.add_child(switch)
	check.call(visual.visual_enabled and not legacy.visual_enabled and not legacy.visible, "默认版本须启 V2 停 V1")
	switch.visual_version = 0
	check.call(legacy.visual_enabled and legacy.visible and not visual.visual_enabled and not visual.visible and not visual.animation_player.is_playing(), "切 V1 须完整停 V2")
	switch.visual_version = 1
	check.call(visual.visual_enabled and visual.visible and not legacy.visual_enabled and legacy.process_mode == Node.PROCESS_MODE_DISABLED, "切 V2 须完整停旧视觉包装")
	switch.free()
	legacy.free()


static func _check_standalone(root: Node, check: Callable) -> void:
	var parent := Node2D.new()
	root.add_child(parent)
	var visual: Node2D = VISUAL.instantiate()
	parent.add_child(visual)
	visual.set_visual_enabled(false)
	visual.set_visual_enabled(true)
	visual.update_pose()
	check.call(visual.visual_animation == &"" and not visual.animation_player.is_playing(), "独立包装没有 Player 状态或信号时必须安全暂停")
	visual.free()
	parent.free()


static func _check_scene_paths(check: Callable) -> void:
	var state: SceneState = load("res://player.tscn").get_state()
	var paths: Array[String] = []
	for index in range(state.get_node_count()):
		paths.append(str(state.get_node_path(index)).trim_prefix("./"))
	check.call(paths.has("PlayerVisual/Orientation/ActionPivot/Body/VisualRoot_V1/RunSkeleton"), "V1 备份路径必须保留")
	check.call(paths.has("PlayerVisual/Orientation/ActionPivot/Body/Sword"), "原 Sword Gameplay 路径必须保留")
	check.call(paths.has("PlayerVisual_V2"), "Player 场景必须接入 V2 包装实例")
