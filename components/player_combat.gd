extends Node2D

const Projectile := preload("res://components/ability_projectile.gd")
const Orbit := preload("res://components/orbit_fireball.gd")
const Target := preload("res://components/combat_target.gd")
const NINJUTSU_COOLDOWN := 6.0
const FIREBALL_COOLDOWN := 8.0
const SWORD_COOLDOWN := 0.4
const SWORD_DURATION := 0.18
const SWORD_REACH := 94.0
const SWORD_HEIGHT := 55.0
const HIT_FLASH_TIME := 0.16
const MAX_HIT_FLASHES := 16
const RASENGAN_SPAWN_OFFSET := Vector2(70, 0)

# 武器主动技能（持续型火球）的持续时间。
#
# 技能激活后，角色周围常驻 FIREBALL_COUNT 个环绕火球槽位，
# 每个槽位按自己的相位持续发射独立的攻击火球并自行补充。
# 时长结束后停止新的发射与环绕补充；已经飞出去的攻击弹
# 按自己的生命周期 / 最大距离 / 世界清理正常结束。
const FIREBALL_DURATION := 6.0

signal target_destroyed
var player: Node2D
var ninjutsu_cooldown := 0.0
var fireball_cooldown := 0.0
var sword_cooldown := 0.0
var slash_remaining := 0.0
var hit_flashes: Array[Dictionary] = []

# 环绕火球槽位（Orbiting Fireball）。技能持续期间长度恒为 FIREBALL_COUNT。
var orbit_slots: Array[Node2D] = []

# 技能剩余时间。> 0 表示技能激活中。
var fireball_remaining := 0.0

# 距离下一轮开火还剩多久。
#
# 这是**全队共享**的一个节奏：到点时由「轮转到的那个槽位」射出**一颗**火球，
# 而不是三个槽位同时倾泻。实际射速 = 1 / FIREBALL_LAUNCH_INTERVAL。
var fireball_launch_cooldown := 0.0

# 下一轮由哪个槽位开火，逐轮轮转，让三颗环绕火球轮流发射。
var fireball_launch_cursor := 0

#' 本技能期间累计发射出去的攻击火球数量（含已命中和已回收的）。
var fireballs_launched := 0

# 发射出去后仍在世界里的攻击火球（Projectile Fireball）。
# 它们独立存在，数量可以明显超过 FIREBALL_COUNT。
var projectiles: Array[Node2D] = []


func advance(delta: float) -> void:
	ninjutsu_cooldown = maxf(0.0, ninjutsu_cooldown - delta)
	fireball_cooldown = maxf(0.0, fireball_cooldown - delta)
	sword_cooldown = maxf(0.0, sword_cooldown - delta)
	slash_remaining = maxf(0.0, slash_remaining - delta)
	if slash_remaining > 0.0:
		resolve_slash()
	advance_fireball_skill(delta)
	# 推进本节点下的全部投射物：螺旋丸与所有已发射的攻击火球。
	for child in get_children():
		if child is Node and child.has_method("advance") and not child.is_queued_for_deletion():
			child.advance(delta)
	_prune_projectiles()
	for flash in hit_flashes:
		flash.time -= delta
	hit_flashes = hit_flashes.filter(func(flash: Dictionary) -> bool: return flash.time > 0.0)
	queue_redraw()


# 武器技能：维持环绕槽位，并按**全队统一的节奏**轮流射出一颗火球。
func advance_fireball_skill(delta: float) -> void:
	if fireball_remaining <= 0.0:
		# 技能已结束：停止发射与环绕补充，并结束环绕视觉。
		if not orbit_slots.is_empty():
			_clear_orbit_slots()
		return
	fireball_remaining = maxf(0.0, fireball_remaining - delta)
	for slot in orbit_slots:
		if is_instance_valid(slot) and not slot.is_queued_for_deletion():
			slot.advance(delta)
	if fireball_remaining <= 0.0:
		_clear_orbit_slots()
		return
	# 统一的开火节奏：到点只射一颗，然后重新计时。
	fireball_launch_cooldown = maxf(0.0, fireball_launch_cooldown - delta)
	if fireball_launch_cooldown <= 0.0:
		if fire_round():
			fireball_launch_cooldown = Projectile.FIREBALL_LAUNCH_INTERVAL


# 射出一颗火球：由当前轮转到的槽位执行，成功后游标前进。
#
# 与旧的「每槽位各自冷却」相比，这里保证同一时刻只产生一颗攻击火球，
# 射速恒定且与环绕数量无关。
func fire_round() -> bool:
	var count := orbit_slots.size()
	if count == 0:
		return false
	for attempt in count:
		var index := (fireball_launch_cursor + attempt) % count
		var slot: Node2D = orbit_slots[index]
		if not is_instance_valid(slot) or slot.is_queued_for_deletion():
			continue
		if slot.try_launch():
			fireball_launch_cursor = (index + 1) % count
			return true
	return false


func _prune_projectiles() -> void:
	var alive: Array[Node2D] = []
	for projectile in projectiles:
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
			alive.append(projectile)
	projectiles = alive


# 环绕火球数量。技能激活期间应恒等于 Projectile.FIREBALL_COUNT。
func orbiting_fireball_count() -> int:
	var count := 0
	for slot in orbit_slots:
		if is_instance_valid(slot) and not slot.is_queued_for_deletion():
			count += 1
	return count


# 仍在世界里的攻击火球数量。允许 > FIREBALL_COUNT。
func live_projectile_count() -> int:
	var count := 0
	for projectile in projectiles:
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
			count += 1
	return count


func is_fireball_skill_active() -> bool:
	return fireball_remaining > 0.0


func cast_ninjutsu() -> bool:
	if ninjutsu_cooldown > 0.0 or not player.active:
		return false
	ninjutsu_cooldown = NINJUTSU_COOLDOWN
	var projectile := spawn_projectile(Projectile.Kind.RASENGAN)
	projectile.global_position = player.body_collision.global_position + RASENGAN_SPAWN_OFFSET
	return true


# 激活武器主动技能。
#
# 重复输入不会叠加槽位（冷却已经挡掉绝大多数情况，
# 但技能持续时间长于冷却时可能被再次触发），
# 此时只重置持续时间，环绕数量始终保持 FIREBALL_COUNT。
func cast_fireballs() -> bool:
	if fireball_cooldown > 0.0 or not player.active:
		return false
	fireball_cooldown = FIREBALL_COOLDOWN
	fireball_remaining = FIREBALL_DURATION
	# 技能刚激活时立刻可以射出第一颗，之后按统一节奏轮转。
	fireball_launch_cooldown = 0.0
	fireball_launch_cursor = 0
	_ensure_orbit_slots()
	return true


# 建立 / 复位环绕槽位，数量严格等于 Projectile.FIREBALL_COUNT。
func _ensure_orbit_slots() -> void:
	_clear_orbit_slots()
	orbit_slots.clear()
	for index in Projectile.FIREBALL_COUNT:
		var slot := Orbit.new()
		slot.name = "OrbitFireball%d" % index
		slot.player = player
		slot.orbit_index = index
		# 让三颗火球从一开始就分布在不同相位，而不是重叠在一起。
		# 这里只错开**视觉相位**；开火节奏由 PlayerCombat 统一控制，
		# 所以错开相位不会造成「三颗同时射出」。
		slot.age = index * Projectile.FIREBALL_LAUNCH_INTERVAL / Projectile.FIREBALL_COUNT
		add_child(slot)
		if slot.has_signal("launched"):
			slot.connect("launched", on_fireball_launched)
		orbit_slots.append(slot)


func _clear_orbit_slots() -> void:
	for slot in orbit_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	orbit_slots.clear()


func on_fireball_launched(projectile: Node2D) -> void:
	# 发射出去的攻击火球在 OrbitSlot 里已经挂到本节点下，
	# 这里只登记它，让 combat.advance 负责推进和回收。
	if not projectile.destroyed_target.is_connected(on_target_destroyed):
		projectile.destroyed_target.connect(on_target_destroyed)
	fireballs_launched += 1
	projectiles.append(projectile)


func cast_sword() -> bool:
	if sword_cooldown > 0.0 or not player.active:
		return false
	sword_cooldown = SWORD_COOLDOWN
	slash_remaining = SWORD_DURATION
	resolve_slash()
	return true


func spawn_projectile(kind: int) -> Node2D:
	var projectile := Projectile.new()
	projectile.kind = kind
	projectile.player = player
	projectile.destroyed_target.connect(on_target_destroyed)
	add_child(projectile)
	return projectile

func resolve_slash() -> void:
	var origin: Vector2 = player.body_collision.global_position
	for candidate in get_tree().get_nodes_in_group("destructible"):
		if not Target.available(candidate):
			continue
		var offset := Target.center(candidate) - origin
		if offset.x >= 0.0 and offset.x <= SWORD_REACH and absf(offset.y) <= SWORD_HEIGHT:
			var location := Target.center(candidate)
			if Target.destroy(candidate):
				on_target_destroyed(location)

func on_target_destroyed(location: Vector2) -> void:
	if hit_flashes.size() < MAX_HIT_FLASHES:
		hit_flashes.append({"position": location, "time": HIT_FLASH_TIME})
	target_destroyed.emit()

func reset() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	orbit_slots.clear()
	projectiles.clear()
	fireballs_launched = 0
	fireball_remaining = 0.0
	fireball_launch_cooldown = 0.0
	fireball_launch_cursor = 0
	ninjutsu_cooldown = 0.0
	fireball_cooldown = 0.0
	sword_cooldown = 0.0
	slash_remaining = 0.0
	hit_flashes.clear()
	queue_redraw()

func _draw() -> void:
	for flash in hit_flashes:
		var strength: float = flash.time / HIT_FLASH_TIME
		draw_arc(to_local(flash.position), 24.0 * (1.0 - strength) + 4.0, 0, TAU, 16, Color(1, 0.7, 0.3, strength), 3.0, true)
