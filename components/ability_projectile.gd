extends Node2D

const Target := preload("res://components/combat_target.gd")
enum Kind { RASENGAN, FIREBALL }
const RASENGAN_RADIUS := 58.0
const FIREBALL_RADIUS := 13.0
const RASENGAN_SPEED := 950.0
const FIREBALL_SPEED := 780.0
const ORBIT_RADIUS := 62.0
const FIREBALL_COUNT := 3
const ORBIT_TIME := 0.55

# 武器主动技能期间，全队统一的发射间隔：每隔这么久射出一颗火球。
#
# 这是「角色」的射速，不是「每个槽位」的射速——三个环绕槽位共享同一个节奏，
# 每轮只由一个槽位开火，而不是三颗同时倾泻。因此：
#   实际射速 = 1 / FIREBALL_LAUNCH_INTERVAL 发/秒
# 0.42s ≈ 2.4 发/秒，节奏清晰，屏幕上的攻击火球可读。
const FIREBALL_LAUNCH_INTERVAL := 0.42

# 兼容旧名（三发齐射的旧用法），新代码不要使用。
const LAUNCH_INTERVAL := FIREBALL_LAUNCH_INTERVAL
const SEEK_RANGE := 650.0
const TURN_SPEED := 5.0
const LIFETIME := 4.0
const LOST_TARGET_TIME := 0.65
const EXPLOSION_RADIUS := 42.0
const EXPLOSION_TIME := 0.18
const TRAIL_COUNT := 7
const MAX_PLAYER_DISTANCE := 1600.0

signal destroyed_target(location: Vector2)
var kind := Kind.RASENGAN
var player: Node2D
var orbit_index := 0
var age := 0.0

# 已经发射出去、独立飞行和攻击的火球（Projectile Fireball）。
# 由 OrbitSlot（components/orbit_fireball.gd）在发射时置为 true；
# 三发齐射的旧用法仍通过 orbit_time 自行起飞。
var flying := false

# 发射时锁定的初始目标。由 OrbitSlot 在实例化后写入，
# 使弹体脱离槽位的第一帧就已经朝目标飞行，而不是先绕一圈。
var initial_target: Node2D

var target: Node2D
var velocity := Vector2.RIGHT * RASENGAN_SPEED
var targetless_time := 0.0
var explosion_remaining := 0.0

# 是否已经进入爆炸收尾阶段。
# 用布尔量而不是比较 explosion_remaining > 0 来判断，
# 避免「倒计时恰好落到 0」时状态歧义导致弹体永远不被回收。
var exploding := false

var trail: Array[Vector2] = []

func _ready() -> void:
	z_index = 5
	add_to_group("ability_projectile")
	if kind == Kind.FIREBALL and initial_target != null:
		target = initial_target
		flying = true
		velocity = global_position.direction_to(Target.center(target)) * FIREBALL_SPEED

func advance(delta: float) -> void:
	age += delta
	if exploding:
		explosion_remaining = maxf(0.0, explosion_remaining - delta)
		if explosion_remaining <= 0.0:
			queue_free()
		queue_redraw()
		return
	if age >= LIFETIME or absf(global_position.x - player.global_position.x) > MAX_PLAYER_DISTANCE:
		queue_free()
		return
	var previous := global_position
	if kind == Kind.FIREBALL:
		if not update_fireball(delta):
			queue_redraw()
			return
	global_position += velocity * delta
	trail.push_front(previous)
	if trail.size() > TRAIL_COUNT:
		trail.pop_back()
	resolve_hits(previous)
	queue_redraw()

func update_fireball(delta: float) -> bool:
	if not Target.available(target):
		target = find_target()
	if not flying:
		var angle := age * 3.0 + TAU * orbit_index / FIREBALL_COUNT
		global_position = player.body_collision.global_position + Vector2.from_angle(angle) * ORBIT_RADIUS
		if age < ORBIT_TIME + orbit_index * LAUNCH_INTERVAL or not Target.available(target):
			return false
		flying = true
		velocity = global_position.direction_to(Target.center(target)) * FIREBALL_SPEED
	if not Target.available(target):
		# 目标丢失 / 目标在射程外：直线飞完自己的生命周期。
		# 这不再代表「发射失败」，而是「这一发打空了」。
		targetless_time += delta
		if targetless_time >= LOST_TARGET_TIME:
			queue_free()
		return true
	targetless_time = 0.0
	var angle := rotate_toward(
		velocity.angle(),
		global_position.direction_to(Target.center(target)).angle(),
		TURN_SPEED * delta
	)
	velocity = Vector2.from_angle(angle) * FIREBALL_SPEED
	return true

func find_target() -> Node2D:
	var nearest: Node2D
	var unclaimed: Node2D
	var nearest_distance := SEEK_RANGE
	var unclaimed_distance := SEEK_RANGE
	for candidate in get_tree().get_nodes_in_group("destructible"):
		if not Target.available(candidate) or Target.center(candidate).x < player.global_position.x:
			continue
		var distance := global_position.distance_to(Target.center(candidate))
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
		if distance < unclaimed_distance and not is_claimed(candidate):
			unclaimed = candidate
			unclaimed_distance = distance
	return unclaimed if unclaimed != null else nearest

func is_claimed(candidate: Node2D) -> bool:
	for projectile in get_tree().get_nodes_in_group("ability_projectile"):
		if projectile != self and not projectile.is_queued_for_deletion() and projectile.target == candidate:
			return true
	return false

func resolve_hits(previous: Vector2) -> void:
	var radius := RASENGAN_RADIUS if kind == Kind.RASENGAN else FIREBALL_RADIUS
	for candidate in get_tree().get_nodes_in_group("destructible"):
		if not Target.available(candidate) or not Target.swept_hit(candidate, previous, global_position, radius):
			continue
		if kind == Kind.FIREBALL:
			global_position = Geometry2D.get_closest_point_to_segment(Target.center(candidate), previous, global_position)
			remove_target(candidate)
			explode()
			return
		remove_target(candidate)

func remove_target(candidate: Node2D) -> void:
	var location := Target.center(candidate)
	if Target.destroy(candidate):
		destroyed_target.emit(location)

func explode() -> void:
	exploding = true
	explosion_remaining = EXPLOSION_TIME
	target = null
	for candidate in get_tree().get_nodes_in_group("destructible"):
		if Target.available(candidate) and Target.swept_hit(candidate, global_position, global_position, EXPLOSION_RADIUS):
			remove_target(candidate)

func _draw() -> void:
	var fire := kind == Kind.FIREBALL
	var color := Color("f28c38") if fire else Color("30badb")
	var radius := FIREBALL_RADIUS if fire else RASENGAN_RADIUS
	if exploding:
		color.a = maxf(0.0, explosion_remaining / EXPLOSION_TIME)
		draw_arc(Vector2.ZERO, EXPLOSION_RADIUS * (1.0 - color.a * 0.5), 0, TAU, 32, color, 5.0, true)
		return
	for index in trail.size():
		draw_circle(to_local(trail[index]), radius * (1.0 - float(index) / TRAIL_COUNT), Color(color, 0.06))
	if fire:
		draw_flame()
		return
	draw_circle(Vector2.ZERO, radius, Color(color, 0.3))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 48, color, 2.5, true)
	for index in 3:
		var angle := age * 9.0 + index * TAU / 3.0
		draw_arc(Vector2.from_angle(angle) * radius * 0.2, radius * 0.65, angle, angle + PI, 24, Color("e6fbff"), 3.0, true)
	draw_circle(Vector2.ZERO, radius * 0.22, Color("efffff"))

func draw_flame() -> void:
	var angle := velocity.angle() if flying else age * 3.0 + TAU * orbit_index / FIREBALL_COUNT + PI / 2.0
	var flicker := 3.0 * sin(age * 28.0)
	var flame := PackedVector2Array([
		Vector2(-32 - flicker, 0), Vector2(-17, -5), Vector2(-23, -16),
		Vector2(0, -FIREBALL_RADIUS), Vector2(FIREBALL_RADIUS, 0),
		Vector2(0, FIREBALL_RADIUS), Vector2(-22, 14), Vector2(-15, 5),
	])
	for index in flame.size():
		flame[index] = flame[index].rotated(angle)
	draw_colored_polygon(flame, Color("ef6b28"))
	draw_circle(Vector2.ZERO, FIREBALL_RADIUS * 0.75, Color("ffbf48"))
	draw_circle(Vector2.ZERO, FIREBALL_RADIUS * 0.4, Color("fff6c5"))
