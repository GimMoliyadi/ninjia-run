extends SceneTree

const PlayerScene := preload("res://player.tscn")
const NinjaScene := preload("res://scenes/LeapingNinja.tscn")
const NinjaMap := preload("res://scenes/segment_ninja_map.tscn")
const GROUND_Y := 460.0
const ENEMY_X := 1000.0
const PLAYER_START_X := 500.0
const EXPECTED_WAVES := {
	"NinjaMap_Wave01_Shadow": [2, 0],
	"NinjaMap_Wave04_Spike": [0, 2],
	"NinjaMap_Wave06_Crossfire": [3, 1],
	"NinjaMap_Wave08_Finale": [2, 1],
}

var world := Node2D.new()
var player: Node2D
var contacts := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.add_child(world)
	player = PlayerScene.instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	for kind in ["low", "high"]:
		if not check_stationary_enemy(kind):
			quit(1)
			return
	if not check_spike_lineup():
		quit(1)
		return
	world.free()
	print("Ninja obstacles passed: right-side entry, stationary landing, one proximity slash, spike lineup, no aimed arrows")
	quit(0)

func check_stationary_enemy(kind: String) -> bool:
	contacts = 0
	player.global_position = Vector2(PLAYER_START_X, GROUND_Y)
	root.canvas_transform = Transform2D(0.0, Vector2(330.0 - PLAYER_START_X, 0.0))
	var ninja := NinjaScene.instantiate()
	ninja.jump_kind = kind
	ninja.crossing_time = 1.8
	world.add_child(ninja)
	ninja.global_position = Vector2(ENEMY_X, GROUND_Y)
	ninja.initialize(player)
	ninja.player_contact.connect(func(_body: Node2D, _damage: float) -> void: contacts += 1)
	var entered_from_right: bool = ninja.global_position.x > ENEMY_X
	ninja.advance(1.4, player)
	var landed: bool = ninja.state == ninja.State.IDLE and ninja.velocity.x == 0.0 and ninja.global_position.is_equal_approx(Vector2(ENEMY_X, GROUND_Y))
	ninja.advance(0.6, player)
	var waits_for_player: bool = ninja.state == ninja.State.IDLE and ninja.global_position.x == ENEMY_X and ninja.slash_started < 0.0 and not ninja.is_queued_for_deletion()
	player.global_position.x = ENEMY_X - ninja.SLASH_TRIGGER_DISTANCE
	ninja.advance(0.01, player)
	var swung_on_approach: bool = ninja.state == ninja.State.ATTACK and ninja.slash_started >= 0.0
	player.global_position.x = ENEMY_X - 50.0
	ninja.advance(0.05, player)
	var hit_once: bool = contacts == 1
	ninja.advance(0.5, player)
	var first_slash: float = ninja.slash_started
	ninja.advance(0.5, player)
	var no_repeat: bool = ninja.state == ninja.State.IDLE and ninja.velocity.x == 0.0 and ninja.slash_started == first_slash and contacts == 1
	player.global_position.x = ENEMY_X + ninja.EXIT_MARGIN + 1.0
	ninja.advance(0.01, player)
	var exits_after_player: bool = ninja.is_queued_for_deletion()
	ninja.free()
	root.canvas_transform = Transform2D.IDENTITY
	if not (entered_from_right and landed and waits_for_player and swung_on_approach and hit_once and no_repeat and exits_after_player):
		printerr("忍者站定或挥刀行为失败：", kind, " ", [entered_from_right, landed, waits_for_player, swung_on_approach, hit_once, no_repeat, exits_after_player])
		return false
	return true

func check_spike_lineup() -> bool:
	var map: MapModuleChunk = NinjaMap.instantiate()
	world.add_child(map)
	var matched := 0
	var supported_platform := false
	for section in map.sections:
		for runner in section.runners:
			if not EXPECTED_WAVES.has(runner.name):
				continue
			matched += 1
			var spikes := 0
			var ninjas := 0
			var formation_spawns: Array[float] = []
			var platform: PatternEvent
			var elevated_enemy: PatternEvent
			for event in runner.plan.events:
				if event.obstacle_scene.resource_path == "res://scenes/AimedArrow.tscn":
					printerr("忍者关卡仍包含瞄准飞箭")
					return false
				match event.obstacle_scene.resource_path:
					"res://scenes/SpikeStrip.tscn":
						spikes += 1
					"res://scenes/LeapingNinja.tscn":
						ninjas += 1
						formation_spawns.append(event.spawn_time)
						if event.position_offset.y < 0.0:
							elevated_enemy = event
					"res://scenes/JumpPillar.tscn":
						platform = event
			var expected: Array = EXPECTED_WAVES[runner.name]
			if ninjas != expected[0] or spikes != expected[1]:
				printerr("阵型人数或地刺数量错误：", runner.name, " ", ninjas, " / ", spikes)
				return false
			formation_spawns.sort()
			for index in range(1, formation_spawns.size()):
				if absf(formation_spawns[index] - formation_spawns[index - 1] - 0.22) > 0.001:
					printerr("敌人未快速错峰跃入：", runner.name)
					return false
			if runner.name == "NinjaMap_Wave08_Finale":
				supported_platform = platform != null and elevated_enemy != null
				if supported_platform:
					supported_platform = platform.position_offset.x <= elevated_enemy.position_offset.x
					supported_platform = supported_platform and elevated_enemy.position_offset.x <= platform.position_offset.x + platform.preview_size.x
					supported_platform = supported_platform and -elevated_enemy.position_offset.y == platform.preview_size.y
	map.free()
	if matched != EXPECTED_WAVES.size() or not supported_platform:
		printerr("敌人阵型或高处平台缺失：", matched, " / ", supported_platform)
		return false
	return true
