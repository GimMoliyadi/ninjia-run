extends SceneTree

const Stub = preload("res://tests/godot/rig_action_state_stub.gd")
const Visual = preload("res://visuals/rig_v2/player_visual_v2.tscn")
const Spawner = preload("res://visuals/rig_v2/ghost_spawner_v2.gd")
const Snapshot = preload("res://visuals/rig_v2/ghost_snapshot_v2.gd")
const VersionSwitch = preload("res://visuals/visual_version_switch.gd")
const BindingChecks = preload("res://tests/godot/rig_action_binding_checks.gd")

class Actor extends Stub:
	signal died

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("GHOST: " + message)


func _fixture() -> Actor:
	var actor := Actor.new()
	root.add_child(actor)
	actor.position = Vector2(140.0, 460.0)
	var visual: Node2D = Visual.instantiate()
	actor.add_child(visual)
	visual.set_process(false)
	visual.ghosts.set_process(false)
	visual.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	visual.reset_visual()
	visual.animation_player.advance(0.05)
	return actor


func run() -> void:
	_check_thresholds()
	_check_frozen_snapshot()
	_check_group_compositing()
	_check_blends_and_mirrors()
	_check_emission_limits()
	_check_lifetime_and_pause()
	_check_death_reset_and_versions()
	await _check_idle_order()
	print("GHOST_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _check_thresholds() -> void:
	var actor := _fixture()
	var visual: Node2D = actor.get_child(0)
	var ghosts: Node2D = visual.ghosts
	for speed in [actor.RUN_SPEED, actor.RUN_SPEED * Spawner.SPEED_THRESHOLD]:
		actor.velocity.x = speed
		ghosts._process(Spawner.INTERVAL_SECONDS)
		check(not ghosts.emitting and ghosts.get_child_count() == 0, "常速和阈值相等时不得发射")
	for state in [actor.MovementState.SLIDE, actor.MovementState.GROUNDED, actor.MovementState.AIRBORNE]:
		actor.movement_state = state
		actor.velocity = Vector2(620.0, -200.0)
		var before := actor.snapshot()
		visual.update_pose()
		visual.animation_player.advance(0.02)
		ghosts._process(Spawner.INTERVAL_SECONDS)
		check(ghosts.emitting and ghosts.get_child_count() > 0, "超速滑铲/滑铲后跑步/空中继承动量均应发射：%d" % state)
		check(actor.snapshot() == before, "选姿、发射和寿命更新不能写 Player 状态")
	actor.active = false
	var count: int = ghosts.ghost_count
	ghosts._process(Spawner.INTERVAL_SECONDS)
	check(not ghosts.emitting and ghosts.ghost_count == count, "非 active 角色不得发射")
	actor.active = true
	actor.velocity.x = -620.0
	check(ghosts.emitting, "水平超速判定应使用绝对速度")
	actor.free()


func _check_frozen_snapshot() -> void:
	var actor := _fixture()
	var visual: Node2D = actor.get_child(0)
	actor.velocity.x = 620.0
	visual.update_pose()
	visual.animation_player.advance(0.083)
	visual.rig.add_to_group(&"live_character")
	var before := actor.snapshot()
	var ghost: CanvasGroup = visual.ghosts.spawn_ghost()
	check(ghost != null and ghost.top_level, "残影必须使用世界锚定外壳")
	check(ghost.frozen_rig.transform == Transform2D.IDENTITY, "副本根必须归一，避免重复 0.055 缩放")
	check(ghost.global_transform.is_equal_approx(visual.rig.global_transform), "外壳必须承接完整素材世界变换")
	check(_same_pose(visual.rig, ghost.frozen_rig), "冻结快照必须逐骨骼/蒙皮/挂骨 Sprite 匹配当前姿势")
	check(_native_only(ghost.frozen_rig), "副本不得保留脚本/信号/组/AnimationPlayer 或处理逻辑")
	check(ghost.frozen_rig.texture_filter == visual.rig.texture_filter, "副本必须继承真身纹理滤镜")
	check(_max_depth(ghost.frozen_rig) < _min_draw_depth(visual.rig), "所有残影部件必须排在整个真身后方")
	check(_background_layer() < 0, "正式背景必须低于角色和残影所在 CanvasLayer")
	var frozen_signature := _pose_signature(ghost.frozen_rig)
	var anchored_transform := ghost.global_transform
	actor.position += Vector2(180.0, -70.0)
	actor.rotation = 0.3
	actor.scale = Vector2(1.2, 0.8)
	visual.animation_player.advance(0.11)
	check(_pose_signature(ghost.frozen_rig) == frozen_signature, "源动画/位置/缩放变化不得带动冻结骨骼")
	check(ghost.global_transform.is_equal_approx(anchored_transform), "角色移动及父变换变化不得移动残影")
	actor.position = before[-1]
	actor.rotation = 0.0
	actor.scale = Vector2.ONE
	check(actor.snapshot() == before, "残影捕获本身不得写任何 Player 状态")
	actor.free()
	check(not is_instance_valid(ghost), "退出树必须同步清理世界残影")


func _check_group_compositing() -> void:
	var actor := _fixture()
	var visual: Node2D = actor.get_child(0)
	actor.velocity.x = 620.0
	var ghost: CanvasGroup = visual.ghosts.spawn_ghost()
	var group_depth := _effective_depth(ghost)
	for item in ghost.find_children("*", "CanvasItem", true, false):
		if item is Polygon2D or item is Sprite2D or item is Line2D:
			check(_effective_depth(item) == group_depth, "人物和烟丝必须进入同一CanvasGroup深度桶：%s" % item.name)
	check(ghost.modulate == Color.WHITE, "整体色调不能向部件传播再重复合成")
	check(is_equal_approx(ghost.self_modulate.a, Snapshot.START_OPACITY), "残影透明度只能在最终合成时应用一次")
	actor.free()


func _check_blends_and_mirrors() -> void:
	var actor := _fixture()
	var visual: Node2D = actor.get_child(0)
	actor.velocity.x = 620.0
	for pose in ["run_to_slide", "slide_to_run", "rope_bottom", "rope_flip", "air_roll"]:
		actor.movement_state = actor.MovementState.GROUNDED
		actor.air_state = actor.AirState.NONE
		actor.flipping = false
		actor.roll_hitbox_active = false
		visual.reset_visual()
		visual.animation_player.advance(0.083)
		_apply_pose(actor, visual, pose)
		var before := actor.snapshot()
		visual.update_pose()
		visual.animation_player.advance(0.017)
		var ghost: CanvasGroup = visual.ghosts.spawn_ghost()
		check(_same_pose(visual.rig, ghost.frozen_rig), "混合/镜像/旋转必须精确捕获而非 seek 重建：" + pose)
		check(_same_skin(visual.rig, ghost.frozen_rig), "源和副本的实际蒙皮世界顶点必须一致：" + pose)
		check(actor.snapshot() == before, "混合/镜像捕获不得写 Player：" + pose)
		visual.ghosts.clear_ghosts()
	actor.free()


func _apply_pose(actor: Actor, visual: Node2D, pose: String) -> void:
	match pose:
		"run_to_slide":
			actor.movement_state = actor.MovementState.SLIDE
		"slide_to_run":
			actor.movement_state = actor.MovementState.SLIDE
			visual.update_pose()
			visual.animation_player.advance(0.08)
			actor.movement_state = actor.MovementState.GROUNDED
		"rope_bottom":
			actor.movement_state = actor.MovementState.ROPE
			actor.rope_side = actor.RopeSide.BOTTOM
		"rope_flip":
			actor.movement_state = actor.MovementState.ROPE
			actor.flipping = true
			actor.rope_flip_progress = 0.5
			actor.rope_flip_angle = PI
			actor.roll_hitbox_active = true
		"air_roll":
			actor.movement_state = actor.MovementState.AIRBORNE
			actor.air_state = actor.AirState.DOUBLE_JUMP_ROLL
			actor.roll_remaining = actor.DOUBLE_JUMP_ROLL_DURATION * 0.25
			actor.roll_hitbox_active = true


func _check_emission_limits() -> void:
	var actor := _fixture()
	var visual: Node2D = actor.get_child(0)
	var ghosts: Node2D = visual.ghosts
	actor.velocity.x = 620.0
	ghosts._process(Spawner.INTERVAL_SECONDS / 2.0)
	check(ghosts.get_child_count() == 0, "不到发射间隔不得生成残影")
	ghosts._process(Spawner.INTERVAL_SECONDS / 2.0)
	check(ghosts.get_child_count() == 1, "跨越发射间隔只生成一影")
	var oldest := ghosts.get_child(0)
	for index in range(Spawner.MAX_LIVE_GHOSTS):
		ghosts.spawn_ghost()
	check(ghosts.get_child_count() == Spawner.MAX_LIVE_GHOSTS and not is_instance_valid(oldest), "最大存活数必须固定并同步淘汰最旧影")
	var count: int = ghosts.ghost_count
	ghosts._process(0.20)
	check(ghosts.ghost_count == count + 1 and ghosts.get_child_count() <= Spawner.MAX_LIVE_GHOSTS, "低 FPS 不能一次补发多个同位置影")
	ghosts._process(0.001)
	check(ghosts.ghost_count == count + 1, "卡顿后的短帧不能补发欠账")
	ghosts._process(2.0)
	check(ghosts.get_child_count() == 1 and ghosts.ghost_count == count + 2, "极大 delta 应清旧影且仅留下一个新影")
	actor.free()


func _check_lifetime_and_pause() -> void:
	var actor := _fixture()
	var visual: Node2D = actor.get_child(0)
	var ghosts: Node2D = visual.ghosts
	actor.velocity.x = 620.0
	var ghost: CanvasGroup = ghosts.spawn_ghost()
	actor.velocity.x = actor.RUN_SPEED
	ghosts._process(Snapshot.LIFETIME_SECONDS / 2.0)
	check(ghosts.get_child_count() == 1 and ghost.modulate.a > 0.0 and ghost.modulate.a < Snapshot.START_OPACITY, "恢复常速应保留旧影并渐淡")
	var age: float = ghost.age_seconds
	var opacity := ghost.modulate.a
	var transform := ghost.global_transform
	var count: int = ghosts.ghost_count
	actor.velocity.x = 620.0
	paused = true
	ghosts._process(1.0)
	check(ghost.age_seconds == age and ghost.modulate.a == opacity and ghost.global_transform == transform and ghosts.ghost_count == count, "暂停必须同时冻结寿命/烟丝/发射")
	check(ghosts.spawn_ghost() == null, "暂停时手动请求也不得发射")
	paused = false
	actor.velocity.x = actor.RUN_SPEED
	ghosts._process(Snapshot.LIFETIME_SECONDS / 2.0 + 0.0001)
	check(ghosts.get_child_count() == 0 and not is_instance_valid(ghost), "恢复后应按剩余寿命同步到期")
	actor.free()


func _check_death_reset_and_versions() -> void:
	var actor := Actor.new()
	root.add_child(actor)
	actor.died.connect(_pause_immediately)
	var visual: Node2D = Visual.instantiate()
	actor.add_child(visual)
	visual.set_process(false)
	visual.ghosts.set_process(false)
	actor.velocity.x = 620.0
	var ghost: CanvasGroup = visual.ghosts.spawn_ghost()
	actor.active = false
	actor.died.emit()
	check(paused and visual.ghosts.get_child_count() == 0 and not is_instance_valid(ghost), "died 首个监听者立刻暂停也必须同步清影")
	paused = false
	actor.active = true
	visual.ghosts.spawn_ghost()
	actor.run_reset.emit()
	check(visual.ghosts.get_child_count() == 0 and visual.ghosts.elapsed == 0.0, "run_reset 必须同步清影及发射计时")
	_check_versions(actor, visual)
	visual.ghosts.spawn_ghost()
	var last_ghost: Node = visual.ghosts.get_child(0)
	visual.free()
	check(not is_instance_valid(last_ghost) and actor.get_signal_connection_list(&"run_reset").is_empty(), "包装退出树必须清影并断开信号")
	check(actor.get_signal_connection_list(&"died").size() == 1, "退出后只保留测试死亡暂停监听，V2不得泄漏回调")
	actor.free()


func _pause_immediately() -> void:
	paused = true


func _check_versions(actor: Actor, visual: Node2D) -> void:
	var legacy := BindingChecks.LegacyVisual.new()
	legacy.name = &"PlayerVisual"
	actor.add_child(legacy)
	var switch := VersionSwitch.new()
	actor.add_child(switch)
	visual.ghosts.spawn_ghost()
	var before := actor.snapshot()
	switch.visual_version = 0
	check(not visual.visual_enabled and visual.ghosts.get_child_count() == 0 and not visual.ghosts.emitting, "切 V1 必须同步清影并禁发")
	check(visual.ghosts.spawn_ghost() == null and not actor.is_connected(&"died", visual.ghosts.clear_ghosts), "V1不得接入V2死亡回调或接受发射")
	switch.visual_version = 1
	visual.set_visual_enabled(true)
	check(visual.visual_enabled and visual.ghosts.spawn_ghost() != null, "切回 V2 必须能够重新发射")
	check(actor.get_signal_connection_list(&"died").size() == 2, "重复启用不得重复连接 died")
	check(actor.snapshot() == before, "版本切换和清影只能修改视觉状态")
	switch.free()
	legacy.free()


func _check_idle_order() -> void:
	var actor := _fixture()
	var visual: Node2D = actor.get_child(0)
	visual.set_process(true)
	visual.ghosts.set_process(true)
	visual.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	actor.velocity.x = 620.0
	actor.movement_state = actor.MovementState.SLIDE
	visual.ghosts.elapsed = Spawner.INTERVAL_SECONDS
	await process_frame
	await create_timer(0.0).timeout
	var ghost: Node = visual.ghosts.get_child(visual.ghosts.get_child_count() - 1)
	check(visual.process_priority < visual.animation_player.process_priority and visual.animation_player.process_priority < visual.ghosts.process_priority, "真实帧必须包装→AnimationPlayer→快照排序")
	check(visual.visual_animation == &"slide" and _same_pose(visual.rig, ghost.frozen_rig), "真实 idle 帧快照必须等混合及 mixer_applied 校正完成")
	check(_same_skin(visual.rig, ghost.frozen_rig), "真实 idle 帧源与快照蒙皮世界顶点必须一致")
	visual.ghosts.set_process(false)
	visual.set_process(false)
	visual.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.free()


func _same_pose(source: Node2D, frozen: Node2D) -> bool:
	for node in source.find_children("*", "Node2D", true, false):
		var copy: Node2D = frozen.get_node(source.get_path_to(node))
		if not node.transform.is_equal_approx(copy.transform) or not node.global_transform.is_equal_approx(copy.global_transform):
			return false
		if node is Bone2D and node.rest != copy.rest:
			return false
		if node is Polygon2D and (node.polygon != copy.polygon or node.uv != copy.uv or node.texture != copy.texture):
			return false
		if node is Sprite2D and (node.texture != copy.texture or node.offset != copy.offset):
			return false
	return true


func _native_only(node: Node) -> bool:
	if node.get_script() != null or not node.get_groups().is_empty() or node is AnimationMixer or node.is_processing() or node.is_physics_processing():
		return false
	for child in node.get_children():
		if not _native_only(child):
			return false
	return true


func _pose_signature(rig: Node2D) -> Array:
	var signature: Array = [rig.global_transform]
	for node in rig.find_children("*", "Node2D", true, false):
		signature.append(node.transform)
		signature.append(node.global_transform)
	return signature


func _same_skin(source: Node2D, frozen: Node2D) -> bool:
	for mesh in source.get_node("Skin").get_children():
		if not mesh is Polygon2D:
			continue
		var copy: Polygon2D = frozen.get_node(source.get_path_to(mesh))
		if copy.get_node(copy.skeleton) != frozen.get_node("Skeleton2D") or copy.get_bone_count() != mesh.get_bone_count():
			return false
		for vertex in [0, int(mesh.polygon.size() / 2), mesh.polygon.size() - 1]:
			if not _skin_point(mesh, vertex).is_equal_approx(_skin_point(copy, vertex)):
				return false
	return true


func _skin_point(mesh: Polygon2D, vertex: int) -> Vector2:
	var skeleton: Skeleton2D = mesh.get_node(mesh.skeleton)
	var result := Vector2.ZERO
	for index in range(mesh.get_bone_count()):
		var bone: Bone2D = skeleton.get_node(mesh.get_bone_path(index))
		var weight := mesh.get_bone_weights(index)[vertex]
		result += bone.global_transform * bone.get_skeleton_rest().affine_inverse() * mesh.polygon[vertex] * weight
	return result


func _effective_depth(item: CanvasItem) -> int:
	var depth := item.z_index
	var parent := item.get_parent() as CanvasItem
	if item.z_as_relative and parent != null:
		depth += _effective_depth(parent)
	return depth


func _max_depth(rig: Node2D) -> int:
	var depth := _effective_depth(rig)
	for item in rig.find_children("*", "CanvasItem", true, false):
		depth = maxi(depth, _effective_depth(item))
	return depth


func _min_draw_depth(rig: Node2D) -> int:
	var depth := 4096
	for item in rig.find_children("*", "CanvasItem", true, false):
		if item is Sprite2D or item is Polygon2D:
			depth = mini(depth, _effective_depth(item))
	return depth


func _background_layer() -> int:
	var state: SceneState = load("res://test_world.tscn").get_state()
	for index in range(state.get_node_count()):
		if state.get_node_name(index) != &"Background":
			continue
		for property in range(state.get_node_property_count(index)):
			if state.get_node_property_name(index, property) == &"layer":
				return state.get_node_property_value(index, property)
	return 0
