extends SceneTree

const PLAYER := preload("res://player.tscn")
const CYCLE_SAMPLES := 240
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)

func run() -> void:
	var player := PLAYER.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var visual: Node2D = player.get_node("PlayerVisual")
	visual.set_process(false)
	player.movement_state = player.MovementState.GROUNDED
	visual.update_pose(0.0)
	var rig: Skeleton2D = visual.run_skeleton
	var animation: AnimationPlayer = visual.run_animation
	check(rig.visible and animation.current_animation == "run", "RUN not selected")
	check(rig.find_children("*", "Bone2D", true, false).size() == 17, "Expected 17 articulated bones")
	check(rig.find_children("*", "Polygon2D", true, false).size() == 18, "Expected 18 separate cutouts")
	check(rig.find_children("*Weapon*", "", true, false).is_empty(), "RUN must be unarmed")
	check(not visual.scarf.visible, "Legacy scarf must not cover the reference hair")
	verify_animation(animation)
	verify_geometry(rig, animation)
	verify_passing(rig, animation)
	verify_integration(player, visual)
	for failure in failures:
		printerr(failure)
	print("Cultivator RUN regression: 240 samples, loop, feet, posture, passing, debug, collision, state exits; failures=", failures.size())
	player.free()
	quit(1 if not failures.is_empty() else 0)

func verify_animation(player: AnimationPlayer) -> void:
	var animation := player.get_animation("run")
	check(is_equal_approx(animation.length, 0.64), "RUN duration")
	check(animation.loop_mode == Animation.LOOP_LINEAR, "RUN must loop")
	for track in animation.get_track_count():
		check(animation.track_get_key_count(track) == 9, "Eight poses plus matching closing key")
		check(animation.track_get_key_value(track, 0) == animation.track_get_key_value(track, 8), "Loop seam mismatch")
		check(animation.track_get_interpolation_type(track) == Animation.INTERPOLATION_LINEAR, "Avoid angle overshoot")
	player.seek(0.0, true)
	var hip: Bone2D = player.get_parent().get_node("Hip")
	var start := hip.position
	player.seek(0.04, true)
	check(not hip.position.is_equal_approx(start), "Pose interpolation is frozen")

func sole_height(rig: Skeleton2D, foot: Bone2D) -> float:
	var art := foot.get_node("BootFoot") as Polygon2D
	var bottom := -INF
	for vertex in art.polygon:
		bottom = maxf(bottom, rig.to_local(art.to_global(vertex)).y)
	return bottom

func verify_geometry(rig: Skeleton2D, animation: AnimationPlayer) -> void:
	var hip := rig.get_node("Hip") as Bone2D
	var torso := hip.get_node("Torso") as Bone2D
	var head := torso.get_node("Head") as Bone2D
	var highest_sole := -INF
	var spread := 0.0
	for sample in CYCLE_SAMPLES:
		animation.seek(sample * 0.64 / CYCLE_SAMPLES, true)
		check(absf(hip.position.y + 33.0) <= 1.01, "Hip bounce exceeds two pixels")
		check(absf(rad_to_deg(torso.global_rotation) + 63.435) < 0.01, "Torso folds at the waist")
		check(absf(head.global_rotation) < 0.001, "Head must remain level")
		var left := hip.get_node("Thigh_L") as Bone2D
		var right := hip.get_node("Thigh_R") as Bone2D
		check(absf(left.rotation - right.rotation) < deg_to_rad(90), "Split stride")
		var feet: Array[Vector2] = []
		for side in ["L", "R"]:
			var shin := hip.get_node("Thigh_%s/Shin_%s" % [side,side]) as Bone2D
			var foot := shin.get_node("Foot_" + side) as Bone2D
			check(shin.rotation >= deg_to_rad(19.9) and shin.rotation <= deg_to_rad(110.1), "Knee hyperextension")
			highest_sole = maxf(highest_sole, sole_height(rig, foot))
			feet.append(rig.to_local(foot.global_position))
			var forearm := torso.get_node("UpperArm_%s/Forearm_%s" % [side,side]) as Bone2D
			check(forearm.rotation < deg_to_rad(-40) and forearm.rotation > deg_to_rad(-130), "Rigid or overfolded arm")
		spread = maxf(spread, absf(feet[0].x - feet[1].x))
	check(highest_sole <= 0.3, "Foot penetrates ground: %.3f" % highest_sole)
	check(spread < 42.0, "Feet exceed compact reference silhouette")
	for index in [0,1,2,4,5,6]:
		animation.seek(index * 0.08, true)
		var side := "R" if index < 4 else "L"
		var foot := hip.get_node("Thigh_%s/Shin_%s/Foot_%s" % [side,side,side]) as Bone2D
		check(absf(sole_height(rig, foot)) < 1.0, "Stance foot floats at pose %d" % index)
	print("Sole max y=%.3f px; ankle spread=%.3f px" % [highest_sole, spread])

func verify_passing(rig: Skeleton2D, animation: AnimationPlayer) -> void:
	for side in ["L", "R"]:
		animation.seek(0.16 if side == "L" else 0.48, true)
		var hip := rig.get_node("Hip") as Bone2D
		var foot := hip.get_node("Thigh_%s/Shin_%s/Foot_%s" % [side,side,side]) as Bone2D
		var ankle := rig.to_local(foot.global_position)
		check(absf(ankle.x - hip.position.x) < 1.0, "Swing ankle must pass below hip")
		check(sole_height(rig, foot) < -4.0, "Swing boot drags on ground")

func verify_integration(player: CharacterBody2D, visual: Node2D) -> void:
	var collision := player.get_node("BodyCollision") as CollisionShape2D
	check(collision.shape.size == Vector2(46,66) and collision.position == Vector2(0,-33), "Main collision changed")
	check(player.RUN_SPEED == 400.0, "Physics speed changed")
	visual.show_run_bones = true
	visual.hide_run_effects = true
	player.velocity.x = player.RUN_SPEED * 1.5
	visual.update_pose(0.0)
	check(visual.run_skeleton.get_node("BoneDebug").visible, "Bone debug switch")
	check(not visual.dust.emitting and not visual.ghosts.emitting, "Effects debug switch")
	check(is_equal_approx(visual.run_animation.speed_scale, 1.4), "Animation speed clamp")
	visual.ghosts.spawn_ghost()
	check(visual.ghosts.get_child_count() == 0, "Debug mode spawned a ghost")
	visual.hide_run_effects = false
	visual.update_pose(0.0)
	visual.ghosts.spawn_ghost()
	check(visual.ghosts.get_child(0) is Skeleton2D, "RUN ghost must use the new rig")
	player.landed.emit(700.0)
	visual.update_pose(0.0)
	check(visual.body.scale == Vector2.ONE, "Landing deformed RUN artwork")
	player.movement_state = player.MovementState.AIRBORNE
	visual.update_pose(0.0)
	check(not visual.run_skeleton.visible and not visual.run_animation.is_playing(), "Air exit")
	player.movement_state = player.MovementState.GROUNDED
	player.velocity.x = 0.0
	visual.update_pose(0.0)
	check(not visual.run_skeleton.visible, "Idle exit")
