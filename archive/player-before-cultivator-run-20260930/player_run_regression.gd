extends SceneTree

const PLAYER := preload("res://player.tscn")
const CYCLE_SAMPLES := 240
const MAX_FOOT_SPREAD := 20.2
const CONTACT_HEIGHT := -4.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var player := PLAYER.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var visual := player.get_node("PlayerVisual")
	var skeleton := visual.run_skeleton as Skeleton2D
	var animation := visual.run_animation as AnimationPlayer
	var hip := skeleton.get_node("Hip") as Bone2D
	var left := skeleton.get_node("Hip/Thigh_L") as Bone2D
	var right := skeleton.get_node("Hip/Thigh_R") as Bone2D
	var weapon := skeleton.get_node("Hip/Torso/UpperArm_R/Forearm_R/WeaponBone") as Bone2D
	var collision := player.get_node("BodyCollision") as CollisionShape2D
	var collision_size: Vector2 = collision.shape.size
	player.movement_state = player.MovementState.GROUNDED
	visual.update_pose(0.0)
	assert(skeleton.visible and animation.current_animation == "run")
	assert(not weapon.visible, "RUN must be unarmed")
	var run := animation.get_animation("run")
	assert(run.loop_mode == Animation.LOOP_LINEAR)
	await create_timer(0.14).timeout
	assert(animation.current_animation_position > 0.0)
	var ghosts := player.get_node("PlayerVisual/GhostSpawner")
	ghosts.spawn_ghost()
	assert(ghosts.get_child(0) is Skeleton2D)
	assert(ghosts.get_child(0).modulate.a <= 0.08, "RUN debugging ghost is too strong")
	for pose_index in 8:
		animation.seek(pose_index * 0.05, true)
		assert(absf(hip.position.y + 33.0) <= 1.01)
		assert(absf(left.rotation - right.rotation) < 0.8)
		assert(collision.shape.size == collision_size)
	assert(verify_run_geometry(skeleton, animation))
	assert(verify_passing(skeleton, animation))
	assert(not ghosts.get_child(0).get_node("Hip/Torso/UpperArm_R/Forearm_R/WeaponBone").visible)
	player.velocity.x = player.RUN_SPEED * 1.5
	visual.update_pose(0.0)
	assert(is_equal_approx(animation.speed_scale, 1.4))
	player.movement_state = player.MovementState.AIRBORNE
	visual.update_pose(0.0)
	assert(not skeleton.visible and not animation.is_playing())
	player.movement_state = player.MovementState.GROUNDED
	player.velocity.x = 0.0
	visual.update_pose(0.0)
	assert(not skeleton.visible)
	print("Player RUN regression passed: eight poses, hip, leg spread, weapon, collision and exit")
	quit()

func verify_run_geometry(skeleton: Skeleton2D, animation: AnimationPlayer) -> bool:
	var hip := skeleton.get_node("Hip") as Bone2D
	var torso := hip.get_node("Torso") as Bone2D
	var head := torso.get_node("Head") as Bone2D
	var weapon := torso.get_node("UpperArm_R/Forearm_R/WeaponBone") as Bone2D
	var feet: Array[Vector2] = []
	var maximum_spread := 0.0
	for sample in CYCLE_SAMPLES:
		animation.seek(sample * 0.4 / CYCLE_SAMPLES, true)
		feet.clear()
		for side in ["L", "R"]:
			var shin := hip.get_node("Thigh_%s/Shin_%s" % [side, side]) as Bone2D
			var foot := skeleton.to_local(shin.to_global(Vector2(shin.segment_length, 0)))
			feet.append(foot)
			assert(shin.rotation > 0.0, "Knee must fold backward with the knee pointing forward")
			assert(foot.y <= CONTACT_HEIGHT + 0.2, "Foot penetrated the floor")
			assert(foot.x - hip.position.x <= 9.2, "Overreaching front foot")
		maximum_spread = maxf(maximum_spread, absf(feet[0].x - feet[1].x))
		assert(maximum_spread <= MAX_FOOT_SPREAD, "Split stride")
		assert(absf(torso.global_rotation - skeleton.global_rotation + PI / 2.0 - deg_to_rad(12.0)) < 0.001)
		assert(absf(head.global_rotation - skeleton.global_rotation) < 0.001, "Head tilted")
		assert(not weapon.visible, "Weapon appeared during RUN")
		assert(absf(torso.rotation + PI / 2.0) < 0.001, "Torso bends relative to hip")
		var arm_left := torso.get_node("UpperArm_L") as Bone2D
		var arm_right := torso.get_node("UpperArm_R") as Bone2D
		assert(absf(arm_left.rotation + arm_right.rotation - 2.0 * (PI / 2.0 - hip.rotation + 1.55)) < 0.001, "Arms must alternate")
		for side in ["L", "R"]:
			var elbow := torso.get_node("UpperArm_%s/Forearm_%s" % [side, side]) as Bone2D
			assert(elbow.rotation < -1.3 and elbow.rotation > -1.8, "Elbow must stay naturally bent")
	print("RUN geometry: 240 samples; maximum foot spread = %.2f px" % maximum_spread)
	return true

func verify_passing(skeleton: Skeleton2D, animation: AnimationPlayer) -> bool:
	for side in ["L", "R"]:
		animation.seek(0.1 if side == "L" else 0.3, true)
		var hip := skeleton.get_node("Hip") as Bone2D
		var shin := hip.get_node("Thigh_%s/Shin_%s" % [side, side]) as Bone2D
		var foot := skeleton.to_local(shin.to_global(Vector2(shin.segment_length, 0)))
		assert(absf(foot.x - hip.position.x) < 1.1, "Swing foot must pass under hip")
		assert(foot.y < -10.0, "Swing foot must clear the ground")
	return true
