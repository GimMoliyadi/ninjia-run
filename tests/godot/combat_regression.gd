extends SceneTree

const World := preload("res://test_world.tscn")
const SpikeScene := preload("res://scenes/Spike.tscn")
const BeamScene := preload("res://scenes/SlideBeam.tscn")
const Projectile := preload("res://components/ability_projectile.gd")
const Dart := preload("res://components/dart.gd")
var world: Node2D
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = World.instantiate()
	root.add_child(world)
	await physics_frame
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	check_health()
	await check_sword()
	await check_rasengan()
	await check_fireballs()
	await check_dart_collision()
	await check_pause_and_reset()
	await check_input()
	if failures.is_empty():
		print("Combat regression passed: health, sword, swept hits, homing, cooldowns, pause, death and reset.")
	else:
		for failure in failures:
			printerr(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func check_health() -> void:
	var player: Variant = world.player
	var bar: Node2D = player.get_node("HealthBar")
	check(not bar.visible, "Full health must hide the bar.")
	player.take_damage(12)
	check(bar.visible and player.health == 38, "Damage must immediately show the bar and update health.")
	player.take_damage(12)
	check(player.health == 38, "Invulnerability must prevent repeated contact damage.")
	player.heal(5)
	check(bar.visible and player.health == 43, "Partial healing must keep the bar visible.")
	player.heal(100)
	check(not bar.visible and player.health == 50, "Healing must clamp and hide at full health.")
	player.invulnerability_remaining = 0.0

func spawn_spike(offset: Vector2) -> Area2D:
	var spike: Area2D = SpikeScene.instantiate()
	world.add_child(spike)
	spike.global_position = world.player.body_collision.global_position + offset - Vector2(12, -36)
	return spike

func check_sword() -> void:
	var front := spawn_spike(Vector2(60, 0))
	var behind := spawn_spike(Vector2(-60, 0))
	var far := spawn_spike(Vector2(250, 0))
	var score_before: int = world.score
	world.combat.cast_sword()
	check(front.is_queued_for_deletion(), "Sword must destroy a nearby front target.")
	check(not behind.is_queued_for_deletion() and not far.is_queued_for_deletion(), "Sword must respect direction and range.")
	world.combat.cast_sword()
	world.combat.advance(0.05)
	check(world.score == score_before + 15, "Sword must award each target once and respect cooldown.")
	behind.queue_free()
	far.queue_free()
	await process_frame
	world.combat.reset()

func check_rasengan() -> void:
	var first := spawn_spike(Vector2(170, 0))
	var second := spawn_spike(Vector2(250, 0))
	var beam: Area2D = BeamScene.instantiate()
	world.add_child(beam)
	beam.global_position = world.player.global_position
	world.energy = 100.0
	world.cast_ninjutsu()
	check(world.combat.get_child_count() == 1 and world.energy == 0.0, "Ninjutsu must create a projectile and spend energy.")
	var ball: Variant = world.combat.get_child(0)
	var start: Vector2 = ball.global_position
	world.energy = 100.0
	world.cast_ninjutsu()
	check(world.combat.get_child_count() == 1 and world.energy == 100.0, "Cooldown must reject a duplicate without consuming energy.")
	# 螺旋丸寿命短于自身飞行距离，需要在回收前逐帧推进。
	for frame in 40:
		world.combat.advance(1.0 / 60.0)
		await process_frame
	check(ball.global_position.x > start.x, "Rasengan must move forward.")
	check(not is_instance_valid(first) and not is_instance_valid(second), "Rasengan must sweep and pierce both targets.")
	check(is_instance_valid(beam), "Structural beams must not be destroyed by abilities.")
	# 螺旋丸按 PROJECTILE_LIFETIME 回收；横穿所需时间由距离与速度决定。
	for frame in 300:
		world.combat.advance(1.0 / 60.0)
		await process_frame
	check(not is_instance_valid(ball), "Rasengan must expire.")
	beam.queue_free()
	await process_frame
	world.combat.reset()

func check_fireballs() -> void:
	world.combat.cast_fireballs()
	world.combat.cast_fireballs()
	check(world.combat.orbiting_fireball_count() == 3, "Weapon skill must maintain exactly three orbiting fireballs, including repeated input.")
	world.combat.advance(0.2)
	for slot in world.combat.orbit_slots:
		check(is_instance_valid(slot), "Orbit slots must persist while the skill is active.")
	var targets := [spawn_spike(Vector2(350, -90)), spawn_spike(Vector2(420, 0)), spawn_spike(Vector2(500, 80))]
	# 发射是持续的：每次发射都产生一颗独立的攻击火球，环绕槽位立即补上。
	for frame in 60:
		world.combat.advance(1.0 / 60.0)
		await process_frame
	check(world.combat.orbiting_fireball_count() == 3, "Orbiting count must stay at three after launching projectiles.")
	check(world.combat.live_projectile_count() > 0, "Launching must produce independent projectile fireballs.")
	for frame in 240:
		world.combat.advance(1.0 / 60.0)
		await process_frame
	check(not is_instance_valid(targets[0]) and not is_instance_valid(targets[1]) and not is_instance_valid(targets[2]), "Homing fireballs must actually hit targets.")
	check(world.combat.orbiting_fireball_count() == 3, "Orbit slots must keep running for the whole skill duration.")
	world.combat.reset()
	world.combat.cast_fireballs()
	for frame in 400:
		world.combat.advance(1.0 / 60.0)
	await process_frame
	check(world.combat.orbiting_fireball_count() == 0, "Skill duration must end the orbiting state.")
	check(world.combat.get_child_count() == 0, "Projectiles must finish their own lifetime after the skill ends.")

func check_dart_collision() -> void:
	world.player.invulnerability_remaining = 0.0
	var dart := Dart.new()
	world.add_child(dart)
	dart.global_position = world.player.body_collision.global_position + Vector2(100, 0)
	dart.previous_player_position = world.player.global_position
	dart.velocity = Vector2(-2000, 0)
	dart.advance(0.1, world.player)
	check(world.player.health == 40 and dart.is_queued_for_deletion(), "Fast darts must sweep across the player without tunneling.")
	await process_frame

func check_pause_and_reset() -> void:
	world.combat.reset()
	world.combat.cast_fireballs()
	world.toggle_pause()
	var position_before: Vector2 = world.player.global_position
	var cooldown_before: float = world.combat.fireball_cooldown
	await process_frame
	await process_frame
	check(paused and world.player.global_position == position_before, "Pause must freeze player movement.")
	check(world.combat.fireball_cooldown == cooldown_before, "Pause must freeze cooldowns.")
	world.player.invulnerability_remaining = 0.0
	world.player.take_damage(50)
	check(world.run_state == world.RunState.GAME_OVER and world.combat.get_child_count() == 0, "Death must stop the run and clear abilities.")
	world.restart_run()
	check(not paused and world.player.health == 50 and not world.player.get_node("HealthBar").visible, "Restart must restore health, hidden bar and running state.")
	check(world.combat.get_child_count() == 0 and world.combat.fireball_cooldown == 0.0, "Restart must clear projectiles and cooldowns.")
	check(get_nodes_in_group("dart").is_empty(), "Restart must remove old darts immediately.")

func press_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await physics_frame
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await physics_frame
	await process_frame

func check_input() -> void:
	world.set_physics_process(true)
	world.player.set_physics_process(true)
	world.player.set_run_speed(0.0)
	await press_key(KEY_J)
	# 正式游戏不再连接 sword_requested（剑是装备，不是独立近战技能）。
	check(world.combat.sword_cooldown == 0.0, "J must NOT activate a standalone sword skill in the official game.")
	await press_key(KEY_Q)
	check(world.combat.orbiting_fireball_count() == 3, "Q must activate three orbiting fireballs through the input map.")
	# 忍术需要满能量才能释放。
	world.energy = world.ENERGY_MAX
	await press_key(KEY_K)
	check(world.combat.get_child_count() == 4,
		"K must activate the Rasengan through the input map (3 orbit slots + 1 Rasengan), actual %d" % world.combat.get_child_count())
	await press_key(KEY_P)
	var cooldown: float = world.combat.fireball_cooldown
	var position: Vector2 = world.player.global_position
	await physics_frame
	await process_frame
	check(paused and world.combat.fireball_cooldown == cooldown and world.player.global_position == position, "P must freeze running physics and cooldowns.")
	await press_key(KEY_R)
	check(not paused and world.combat.get_child_count() == 0, "R must restart even while paused.")
