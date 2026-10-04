extends Node2D

# 环绕火球槽位（Orbiting Fireball）。
#
# 与「已经发射出去的火球」（Projectile Fireball，见 ability_projectile.gd）
# 是两类完全不同的对象：
#
#   OrbitSlot            = 环绕角色的视觉槽位，技能持续期间常驻
#   AbilityProjectile    = 发射后独立飞行、追踪、命中、按生命周期回收的攻击弹
#
# 武器主动技能激活后，角色周围维持 FIREBALL_COUNT 个 OrbitSlot。
# 每个槽位按自己的相位绕角色旋转，但**不自己决定何时开火**——
# 开火节奏由 PlayerCombat 统一控制（全队共享一个 FIREBALL_LAUNCH_INTERVAL），
# 每一轮只有一个槽位向目标射出**一颗** AbilityProjectile。
#
# 因此：
#   · 屏幕上同一时刻的攻击火球 = 最多 1 颗（刚射出的那颗）
#   · orbiting_fireball_count 恒等于 FIREBALL_COUNT
#   · 射速是「角色射速」，不是 FIREBALL_COUNT 倍

const Projectile := preload("res://components/ability_projectile.gd")
const Target := preload("res://components/combat_target.gd")

# 与 ability_projectile.gd 保持一致的视觉与运动参数。
const ORBIT_RADIUS := Projectile.ORBIT_RADIUS
const FIREBALL_RADIUS := Projectile.FIREBALL_RADIUS
const ORBIT_SPIN := 3.0

signal launched(projectile: Node2D)

var player: Node2D
var orbit_index := 0

# 当前环绕角度（弧度），由 age 与相位推导。
var age := 0.0

# 本槽位实际发射出去过多少颗攻击火球。
var launched_count := 0


# 本槽位只负责旋转与绘制。
# 是否开火由 PlayerCombat.fire_round() 决定。
func advance(delta: float) -> void:
	age += delta
	if not is_instance_valid(player):
		return
	global_position = _orbit_position()
	queue_redraw()


# 向目标射出一颗独立的攻击火球。
# 返回是否真的发射成功（没有可攻击目标时返回 false，冷却不会被消耗）。
func try_launch() -> bool:
	var target := _find_target()
	if target == null:
		return false
	var projectile := Projectile.new()
	projectile.kind = Projectile.Kind.FIREBALL
	projectile.player = player
	projectile.initial_target = target
	projectile.global_position = global_position
	# 脱离槽位所在节点，成为世界里的独立攻击弹。
	# 让弹体挂在槽位的父节点（也就是 PlayerCombat）下，
	# 这样既脱离槽位、又仍在战斗系统的推进与回收范围内。
	var host: Node = get_parent()
	if host == null:
		host = player
	host.add_child(projectile)
	launched_count += 1
	launched.emit(projectile)
	return true


func _orbit_position() -> Vector2:
	var angle := age * ORBIT_SPIN + TAU * orbit_index / Projectile.FIREBALL_COUNT
	return player.body_collision.global_position + Vector2.from_angle(angle) * ORBIT_RADIUS


# 槽位的目标选择：优先「未被其它在途火球锁定」的最近目标。
#
# 注意：认领只是**短期预约**，不是永久占用。
# 已经飞出去的火球会一直持有 target 直到命中或消散，
# 如果把它当成永久锁，几轮之后可用目标就被占满，
# 开火会失败（表现为「技能期间只射出极少数几颗」）。
func _find_target() -> Node2D:
	var origin := global_position
	var nearest: Node2D
	var unclaimed: Node2D
	var nearest_distance := Projectile.SEEK_RANGE
	var unclaimed_distance := Projectile.SEEK_RANGE
	for candidate in get_tree().get_nodes_in_group("destructible"):
		if not Target.available(candidate):
			continue
		if Target.center(candidate).x < player.global_position.x:
			continue
		var distance := origin.distance_to(Target.center(candidate))
		if distance > Projectile.SEEK_RANGE:
			continue
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
		if distance < unclaimed_distance and not _is_claimed(candidate):
			unclaimed = candidate
			unclaimed_distance = distance
	# 没有空闲目标时仍然开火，打最近的——开火节奏优先于目标独占。
	return unclaimed if unclaimed != null else nearest


# 目标是否已被**其它在途火球**认领。
#
# 只看「仍在飞行、尚未进入爆炸收尾」的火球，
# 并且每个目标最多被一颗火球认领，避免连续多轮打同一个目标。
func _is_claimed(candidate: Node2D) -> bool:
	for projectile in get_tree().get_nodes_in_group("ability_projectile"):
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			continue
		if projectile == self:
			continue
		if projectile.get("exploding") == true:
			continue
		if projectile.get("target") == candidate:
			return true
	return false


func _draw() -> void:
	var angle := age * ORBIT_SPIN + TAU * orbit_index / Projectile.FIREBALL_COUNT + PI / 2.0
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
