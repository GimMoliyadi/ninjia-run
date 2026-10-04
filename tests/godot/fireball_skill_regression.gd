extends SceneTree

# 武器主动技能（持续型环绕火球）架构回归。
#
# 验证的不变量：
#   1. 技能激活后 orbiting_fireball_count() == 3
#   2. 发射一次后 orbiting_fireball_count() == 3
#   3. 连续发射多次后 orbiting_fireball_count() == 3
#   4. 每轮只射出一颗火球（不是三颗同时倾泻）
#   5. 射速由全队共享的 FIREBALL_LAUNCH_INTERVAL 决定，且不随环绕数量放大
#   6. 技能结束后停止新的发射与环绕补充
#   7. 已经发射出去的攻击火球按自己的生命周期正常结束
#   8. restart 后环绕槽位与攻击火球状态清空
#
# 运行：
#   Godot --headless --path . --fixed-fps 60 --script tests/godot/fireball_skill_regression.gd

const World := preload("res://test_world.tscn")
const SpikeScene := preload("res://scenes/Spike.tscn")
const Projectile := preload("res://components/ability_projectile.gd")
const Orbit := preload("res://components/orbit_fireball.gd")

var world: Node2D
var failures: Array[String] = []
var spikes: Array[Area2D] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = World.instantiate()
	root.add_child(world)
	await physics_frame
	world.set_physics_process(false)
	world.player.set_physics_process(false)

	await check_activation()
	await check_repeat_input()
	await check_no_target_orbit()
	await check_persistent_orbit_while_launching()
	await check_skill_end()
	await check_restart()

	if failures.is_empty():
		print("Fireball skill regression passed: 3 persistent orbit slots, one fireball per round at a shared cadence, bounded simultaneous projectiles, clean restart.")
	else:
		for failure in failures:
			printerr(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func step(delta: float) -> void:
	world.combat.advance(delta)

func orbit_count() -> int:
	return int(world.combat.orbiting_fireball_count())

func projectile_count() -> int:
	return int(world.combat.live_projectile_count())

func spawn_targets(count: int) -> void:
	var origin: Vector2 = world.player.body_collision.global_position
	for index in count:
		var spike: Area2D = SpikeScene.instantiate()
		world.add_child(spike)
		spike.global_position = origin + Vector2(320 + index * 130, 0)
		spikes.append(spike)

func clear_targets() -> void:
	for spike in spikes:
		if is_instance_valid(spike):
			spike.queue_free()
	spikes.clear()


# 1. 激活后立即有 3 颗环绕火球。
func check_activation() -> void:
	world.combat.reset()
	world.cast_weapon_skill()
	check(orbit_count() == Projectile.FIREBALL_COUNT,
		"技能激活后环绕火球数必须为 3，实际 %d" % orbit_count())
	check(projectile_count() == 0,
		"激活瞬间不应立刻产生攻击火球，实际 %d" % projectile_count())
	check(bool(world.combat.is_fireball_skill_active()),
		"激活后技能状态必须为进行中")
	check(int(world.combat.fireballs_launched) == 0,
		"激活瞬间累计发射数必须为 0")


# 2. 重复输入不叠加槽位，环绕数仍为 3。
func check_repeat_input() -> void:
	# 冷却未结束时再次触发不应改变任何状态。
	world.cast_weapon_skill()
	check(orbit_count() == Projectile.FIREBALL_COUNT,
		"冷却期间重复输入后环绕火球数必须仍为 3，实际 %d" % orbit_count())
	# 绕过冷却直接调用，模拟技能时长 > 冷却时的重复激活。
	world.combat.fireball_cooldown = 0.0
	world.cast_weapon_skill()
	check(orbit_count() == Projectile.FIREBALL_COUNT,
		"重复激活后环绕火球数必须仍为 3，实际 %d" % orbit_count())


# 3. 没有可攻击目标时，三颗环绕火球保持环绕，不发射也不消失。
func check_no_target_orbit() -> void:
	clear_targets()
	await process_frame
	world.combat.reset()
	world.cast_weapon_skill()
	for frame in 120:
		step(1.0 / 60.0)
	await process_frame
	check(orbit_count() == Projectile.FIREBALL_COUNT,
		"没有目标时环绕火球数必须仍为 3，实际 %d" % orbit_count())
	check(int(world.combat.fireballs_launched) == 0,
		"没有目标时不应发射攻击火球，实际 %d" % int(world.combat.fireballs_launched))


# 4. 发射一次后环绕数仍为 3。
# 5. 连续发射多次后环绕数仍为 3。
# 6. 每轮只射出一颗，射速由全队共享的间隔决定。
func check_persistent_orbit_while_launching() -> void:
	spawn_targets(40)
	await process_frame
	world.combat.reset()
	world.cast_weapon_skill()

	# 第一轮开火：推进到第一次发射。
	step(1.0 / 60.0)
	check(int(world.combat.fireballs_launched) == 1,
		"技能激活后第一轮必须射出一颗火球，实际 %d" % int(world.combat.fireballs_launched))
	check(orbit_count() == Projectile.FIREBALL_COUNT,
		"发射一次后环绕火球数必须仍为 3，实际 %d" % orbit_count())

	# 连续发射：记录射速与同屏弹数峰值。
	var min_orbit := orbit_count()
	var max_orbit := orbit_count()
	var max_projectiles := projectile_count()
	var window := 2.0
	var steps := int(window * 60.0)
	for frame in steps:
		step(1.0 / 60.0)
		min_orbit = mini(min_orbit, orbit_count())
		max_orbit = maxi(max_orbit, orbit_count())
		max_projectiles = maxi(max_projectiles, projectile_count())
	check(min_orbit == Projectile.FIREBALL_COUNT and max_orbit == Projectile.FIREBALL_COUNT,
		"技能持续期间环绕火球数必须恒为 3，实际区间 [%d, %d]" % [min_orbit, max_orbit])

	# 射速：约 window / FIREBALL_LAUNCH_INTERVAL 发，允许 ±2 的帧对齐误差。
	# 关键点是它**不随环绕数量放大**——旧实现（每槽位各自 0.18s 冷却）
	# 会在这个窗口里射出约 33 颗。
	var launched_total := int(world.combat.fireballs_launched)
	var expected := window / Projectile.FIREBALL_LAUNCH_INTERVAL
	check(absf(float(launched_total) - expected) <= 2.0,
		"%.1fs 内应射出约 %.0f 颗（每轮一颗），实际 %d" % [window, expected, launched_total])
	check(launched_total <= int(expected) + 2,
		"射速不得高于全队共享节奏（旧弹幕行为），实际 %d" % launched_total)

	# 同屏弹数必须有界：一轮一颗，且飞行时间有限。
	check(max_projectiles <= 6,
		"同屏攻击火球峰值应有界（每轮一颗），实际峰值 %d" % max_projectiles)
	check(bool(world.combat.is_fireball_skill_active()),
		"技能应仍在进行中")


# 7. 技能结束后：停止发射 + 结束环绕视觉，但已发射的攻击弹正常收尾。
func check_skill_end() -> void:
	# 推进到技能时间结束。
	var guard := 0.0
	while bool(world.combat.is_fireball_skill_active()) and guard < 8.0:
		step(1.0 / 60.0)
		guard += 1.0 / 60.0
	check(not bool(world.combat.is_fireball_skill_active()),
		"技能时长结束后技能状态必须为结束")
	check(orbit_count() == 0,
		"技能结束后环绕火球必须结束，实际 %d" % orbit_count())

	var launched_at_end := int(world.combat.fireballs_launched)
	for frame in 120:
		step(1.0 / 60.0)
	check(int(world.combat.fireballs_launched) == launched_at_end,
		"技能结束后不得再发射新的攻击火球（结束前 %d，结束后 %d）"
		% [launched_at_end, int(world.combat.fireballs_launched)])
	check(orbit_count() == 0,
		"技能结束后环绕火球数必须保持 0")

	# 攻击弹继续按自己的生命周期独立收尾，最终全部消失。
	var remaining_seen := 0
	for frame in 420:
		step(1.0 / 60.0)
		remaining_seen = maxi(remaining_seen, projectile_count())
	await process_frame
	check(projectile_count() == 0,
		"技能结束后已发射的攻击火球必须在生命周期内全部回收，实际剩 %d" % projectile_count())
	check(int(world.combat.fireballs_launched) == launched_at_end,
		"攻击火球自行收尾期间不得产生新的发射")


# 8. restart 后状态清空。
func check_restart() -> void:
	world.combat.reset()
	world.cast_weapon_skill()
	check(orbit_count() == Projectile.FIREBALL_COUNT, "重开前技能应能正常激活")
	world.restart_run()
	await process_frame
	check(orbit_count() == 0, "restart 后环绕槽位必须清空，实际 %d" % orbit_count())
	check(projectile_count() == 0, "restart 后攻击火球必须清空，实际 %d" % projectile_count())
	check(int(world.combat.fireballs_launched) == 0,
		"restart 后累计发射数必须归零，实际 %d" % int(world.combat.fireballs_launched))
	check(not bool(world.combat.is_fireball_skill_active()),
		"restart 后技能状态必须为非激活")
	check(float(world.combat.fireball_cooldown) == 0.0,
		"restart 后武器技能冷却必须归零")
	check(get_nodes_in_group("ability_projectile").is_empty(),
		"restart 后不得残留任何 ability_projectile 节点")
