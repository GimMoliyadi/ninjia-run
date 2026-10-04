extends RefCounted

const RIG = preload("res://visuals/rig_v2/visual_root_v2.tscn")
const RunChecks = preload("res://tests/godot/rig_action_run_checks.gd")
const ACTIONS := {
	&"idle": [1.2, true], &"run": [RunChecks.CYCLE_SECONDS, true],
	&"jump_start": [0.09, false], &"jump_up": [0.3, true],
	&"double_jump": [0.32, false], &"fall": [0.3, true],
	&"land": [0.12, false], &"slide": [0.58, true],
}
const TRACK_COUNT := 53
const COM_REST_Y := -803.0


static func run(root: Node, check: Callable) -> void:
	var rig: Node2D = RIG.instantiate()
	root.add_child(rig)
	var animator: AnimationPlayer = rig.get_node("AnimationPlayer")
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skeleton: Skeleton2D = rig.get_node("Skeleton2D")
	check.call(rig.scale.is_equal_approx(Vector2(0.055, 0.055)), "素材根缩放必须为 0.055")
	check.call(not animator.is_playing(), "原始 Rig 默认必须暂停")
	var paths := _expected_paths(skeleton)
	var common_paths: Array[NodePath] = []
	for track in range(animator.get_animation(&"RESET").get_track_count()):
		common_paths.append(animator.get_animation(&"RESET").track_get_path(track))
	check.call(common_paths.size() == TRACK_COUNT and common_paths.all(func(path: NodePath) -> bool: return common_paths.count(path) == 1), "共同轨必须恰有 53 个唯一的骨骼/COM 路径")
	for name in [&"RESET", &"rig_test"] + ACTIONS.keys():
		check.call(animator.has_animation(name), "缺少动作 %s" % name)
		if animator.has_animation(name):
			_check_tracks(animator.get_animation(name), paths, common_paths, check)
	for name in ACTIONS:
		var animation := animator.get_animation(name)
		if animation == null:
			continue
		check.call(is_equal_approx(animation.length, ACTIONS[name][0]), "%s 时长不符" % name)
		check.call(animation.loop_mode == (Animation.LOOP_LINEAR if ACTIONS[name][1] else Animation.LOOP_NONE), "%s 循环模式不符" % name)
		if ACTIONS[name][1]:
			for track in range(TRACK_COUNT):
				check.call(is_equal_approx(animation.track_get_key_value(track, 0), animation.track_get_key_value(track, animation.track_get_key_count(track) - 1)), "%s 循环轨首尾不闭合" % name)
	_check_connections(animator, check)
	_check_transition_profiles(animator, check)
	rig.set_action_mode(true)
	RunChecks.run(rig, skeleton, animator, check)
	_check_playback(rig, skeleton, animator, check)
	rig.free()


static func _expected_paths(skeleton: Skeleton2D) -> Array[NodePath]:
	var paths: Array[NodePath] = []
	for index in range(skeleton.get_bone_count()):
		paths.append(NodePath("Skeleton2D/%s:rotation" % skeleton.get_path_to(skeleton.get_bone(index))))
	var com := skeleton.find_child("COM", true, false)
	for axis in ["x", "y"]:
		paths.append(NodePath("Skeleton2D/%s:position:%s" % [skeleton.get_path_to(com), axis]))
	return paths


static func _check_tracks(animation: Animation, paths: Array[NodePath], common_paths: Array[NodePath], check: Callable) -> void:
	check.call(animation.get_track_count() == TRACK_COUNT, "%s 必须恰有 53 条轨" % animation.resource_name)
	for track in range(animation.get_track_count()):
		check.call(animation.track_get_type(track) == Animation.TYPE_VALUE, "不允许 method 或其他非数值轨")
		check.call(track < common_paths.size() and animation.track_get_path(track) == common_paths[track] and paths.has(animation.track_get_path(track)), "动作共同轨路径不一致或含 Gameplay 轨")
		var count := animation.track_get_key_count(track)
		check.call(count > 0, "动作轨不能没有关键帧")
		for key in range(count):
			var value: Variant = animation.track_get_key_value(track, key)
			check.call(typeof(value) == TYPE_FLOAT and is_finite(value), "动作关键帧必须为有限浮点，包括零值")
			if track == 0:
				check.call(value == 0.0, "整身翻滚不得写入 Root")


static func _check_connections(animator: AnimationPlayer, check: Callable) -> void:
	var connections := [
		[&"run", false, &"jump_start"], [&"jump_start", true, &"jump_up"],
		[&"jump_up", false, &"fall"], [&"fall", false, &"land"],
		[&"land", true, &"run"], [&"double_jump", false, &"jump_up"], [&"double_jump", true, &"jump_up"],
	]
	for connection in connections:
		var first := animator.get_animation(connection[0])
		var second := animator.get_animation(connection[2])
		for track in range(TRACK_COUNT):
			var key := first.track_get_key_count(track) - 1 if connection[1] else 0
			check.call(is_equal_approx(first.track_get_key_value(track, key), second.track_get_key_value(track, 0)), "非循环进出端点不连续：%s→%s" % [connection[0], connection[2]])
	for name in [&"jump_start", &"land"]:
		var animation := animator.get_animation(name)
		check.call(not is_equal_approx(animation.track_get_key_value(52, 0), animation.track_get_key_value(52, animation.track_get_key_count(52) - 1)), "%s 不应被错误强制首尾闭合" % name)


static func _check_transition_profiles(animator: AnimationPlayer, check: Callable) -> void:
	var jump := animator.get_animation(&"jump_start")
	var land := animator.get_animation(&"land")
	var double_jump := animator.get_animation(&"double_jump")
	check.call(jump.value_track_interpolate(52, 0.035) > jump.value_track_interpolate(52, 0.0) + 60.0, "起跳必须经历下蹲蓄力，而非单姿态")
	check.call(jump.value_track_interpolate(52, 0.065) < jump.value_track_interpolate(52, 0.035) - 80.0, "起跳必须从蓄力转到蹬伸")
	check.call(land.value_track_interpolate(52, 0.03) > land.value_track_interpolate(52, 0.0) + 100.0, "落地必须有缓冲压缩")
	check.call(land.value_track_interpolate(52, 0.12) < land.value_track_interpolate(52, 0.03) - 60.0, "落地必须恢复支撑姿态")
	check.call(double_jump.value_track_interpolate(52, 0.16) > double_jump.value_track_interpolate(52, 0.0) + 40.0, "二段跳必须经历收膝，再回到空中姿态")


static func _check_playback(rig: Node2D, skeleton: Skeleton2D, animator: AnimationPlayer, check: Callable) -> void:
	rig.reset_actions()
	var com: Bone2D = skeleton.find_child("COM", true, false)
	check.call(com.position == Vector2(0.0, COM_REST_Y), "RESET 必须恢复 COM 纵向 restY=-803")
	rig.play_action(&"run")
	animator.advance(0.13)
	var elapsed := animator.current_animation_position
	rig.play_action(&"run", 1.4)
	check.call(is_equal_approx(animator.current_animation_position, elapsed) and is_equal_approx(animator.speed_scale, 1.4), "同动作调速不得重启")
	var previous_com := com.position
	rig.play_action(&"jump_start")
	check.call(com.position == previous_com, "跨动作不能先归零")
	animator.advance(0.025)
	check.call(com.position != Vector2(0.0, COM_REST_Y), "0.05s 混合过程中不能回到中性 rest")
	var action_time := animator.current_animation_position
	rig.preview_pose = 4
	check.call(animator.current_animation == &"jump_start" and animator.current_animation_position == action_time, "测试姿态与正式动作必须互斥")
	rig.set_action_mode(false)
	rig.reset_actions()
	check.call(com.position.y == COM_REST_Y and not animator.is_playing(), "rig_test 必须恢复 COM.y 并暂停")
