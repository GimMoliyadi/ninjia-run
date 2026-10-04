extends RefCounted

const PREVIEW = preload("res://tests/rig_action_chain.tscn")
const TIME_TOLERANCE := 0.00001


static func run(root: Node, check: Callable) -> void:
	var preview: Node2D = PREVIEW.instantiate()
	root.add_child(preview)
	preview.set_process(false)
	check.call(preview.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "独立预览必须使用 MANUAL 动画时钟")
	check.call(not _contains_character_body(preview), "预览不能实例化真实 Player 或 CharacterBody2D")
	_check_pause_replay(preview, check)
	_check_large_delta(preview, check)
	_check_whole_chain(preview, check)
	_check_bottom_world(preview, check)
	preview.free()


static func _check_pause_replay(preview: Node2D, check: Callable) -> void:
	preview.advance_preview(2.45)
	var frozen := _snapshot(preview)
	preview.toggle_pause()
	preview.advance_preview(8.0)
	check.call(_snapshot(preview) == frozen, "暂停必须同时冻结动画时间、视觉升降、转角和镜像")
	preview.toggle_pause()
	preview.advance_preview(0.04)
	check.call(_snapshot(preview) != frozen, "恢复必须继续动画和升降")
	preview.orientation.scale = Vector2(-1.0, -1.0)
	preview.orientation.rotation = PI
	preview.action_pivot.rotation = PI
	preview.rig.position = Vector2(10.0, 20.0)
	preview.toggle_pause()
	preview.replay()
	check.call(not preview.paused and preview.stage_index == 0 and preview.stage_elapsed == 0.0, "R 必须从待机清时间并解除暂停")
	check.call(preview.visual_anchor.position == Vector2.ZERO and preview.orientation.position == Vector2.ZERO and preview.orientation.scale == Vector2.ONE and preview.orientation.rotation == 0.0, "R 必须清升降和所有镜像")
	check.call(preview.action_pivot.position == Vector2.ZERO and preview.action_pivot.rotation == 0.0 and preview.rig.position == Vector2.ZERO, "R 必须清外层支点及反向平移")
	check.call(preview.animation_player.current_animation == &"idle" and preview.animation_player.current_animation_position == 0.0, "R 必须重播首动作")


static func _check_large_delta(preview: Node2D, check: Callable) -> void:
	preview.replay()
	for index in range(273):
		preview.advance_preview(0.01)
	var small_steps := _snapshot(preview)
	preview.replay()
	preview.advance_preview(2.73)
	var large_step := _snapshot(preview)
	check.call(large_step[0] == small_steps[0] and absf(large_step[1] - small_steps[1]) < TIME_TOLERANCE, "大 delta 不得丢失阶段余时")
	check.call(large_step[2] == small_steps[2] and absf(large_step[3] - small_steps[3]) < TIME_TOLERANCE and large_step[4].is_equal_approx(small_steps[4]), "大 delta 必须与分段推进得到相同动作时钟和升降")
	var starts: Array[StringName] = []
	preview.animation_player.animation_started.connect(func(name: StringName) -> void: starts.append(name))
	preview.replay()
	starts.clear()
	var full_seconds := 0.0
	var expected: Array[StringName] = []
	var previous: StringName = &"idle"
	for stage in preview.STAGES:
		full_seconds += stage["seconds"]
		if stage["action"] != previous:
			expected.append(stage["action"])
			previous = stage["action"]
	preview.advance_preview(full_seconds + 0.07)
	check.call(starts == expected, "跨完整链大 delta 必须依次消费所有动作，而非跳到末尾")
	check.call(preview.stage_index == 0 and absf(preview.stage_elapsed - 0.07) < TIME_TOLERANCE and absf(preview.animation_player.current_animation_position - 0.07) < TIME_TOLERANCE, "跨完整链后必须保留新周期的余时")


static func _check_whole_chain(preview: Node2D, check: Callable) -> void:
	preview.replay()
	var actions := {}
	var bottom_seen := false
	var flip_seen := false
	for index in range(preview.STAGES.size()):
		var stage: Dictionary = preview.STAGES[index]
		var duration: float = stage["seconds"]
		preview.advance_preview(duration * 0.5)
		actions[preview.animation_player.current_animation] = true
		check.call(preview.stage_index == index, "连续预览阶段顺序不能跳跃")
		if stage.get("flip", false):
			flip_seen = true
			check.call(preview.orientation.scale.y == 1.0 and is_equal_approx(preview.action_pivot.rotation, PI), "预览绳索分支应沿原进度函数转动，不在 Root 写翻滚")
			check.call(is_equal_approx(preview.visual_anchor.position.y - preview.rope_line.position.y, 33.0), "翻转中点必须模拟 Player +66*side_progress 下移")
		if stage.get("bottom", false):
			bottom_seen = true
			check.call(preview.orientation.scale.y == -1.0 and preview.orientation.position.y == -66.0, "预览应显示绳索下方镜像分支")
		preview.advance_preview(duration * 0.5)
	check.call(actions.size() == 8 and actions.has(&"land") and actions.has(&"slide") and actions.has(&"double_jump"), "独立预览必须连续展示所有八动作")
	check.call(bottom_seen and flip_seen, "独立预览必须包含绳索上下与翻转分支")


static func _check_bottom_world(preview: Node2D, check: Callable) -> void:
	preview.replay()
	var seconds := 0.0
	for stage in preview.STAGES:
		if stage.get("bottom", false):
			seconds += float(stage["seconds"]) * 0.5
			break
		seconds += stage["seconds"]
	preview.advance_preview(seconds)
	var skeleton: Skeleton2D = preview.rig.get_node("Skeleton2D")
	var head: Bone2D = skeleton.find_child("Head", true, false)
	var rope_y: float = preview.rope_line.to_global(preview.rope_line.points[0]).y
	check.call(head.global_position.y > rope_y and head.global_position.y < 540.0, "绳下头部最终世界坐标必须在 RopeLine 下方且仍在视口内")
	check.call(preview.visual_anchor.position.y - preview.rope_line.position.y == 66.0, "绳下预览必须模拟 Player 真实 +66 下移")
	print("VISUAL rope world line=%.5f head=%.5f anchor delta=%.5f" % [rope_y, head.global_position.y, preview.visual_anchor.position.y - preview.rope_line.position.y])


static func _snapshot(preview: Node2D) -> Array:
	return [preview.stage_index, preview.stage_elapsed, preview.animation_player.current_animation,
		preview.animation_player.current_animation_position, preview.visual_anchor.position,
		preview.orientation.transform, preview.action_pivot.transform, preview.rig.position]


static func _contains_character_body(node: Node) -> bool:
	if node is CharacterBody2D:
		return true
	for child in node.get_children():
		if _contains_character_body(child):
			return true
	return false
