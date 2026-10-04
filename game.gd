extends Node2D


const ROUTE_GENERATOR_SCRIPT = preload("res://components/rhythm_route_generator.gd")
const Combat = preload("res://components/player_combat.gd")


enum RunState {
	RUNNING,
	PAUSED,
	GAME_OVER
}


const START_POSITION := Vector2(140.0, 460.0)

const CHUNK_AHEAD := 2200.0
const CHUNK_CLEAN_BEHIND := 700.0

# 忍术能量
const ENERGY_MAX := 100.0

# 如果某些旧金币传入的 coin_energy 为 0，
# 默认一枚金币提供这么多忍术能量。
const DEFAULT_COIN_ENERGY := 10.0

const FALL_DEATH_Y := 900.0
const DESTRUCTION_SCORE := 15


const CHUNK_SCENES: Array[PackedScene] = [
	preload("res://scenes/segment_safe.tscn"),
	preload("res://scenes/segment_single_jump.tscn"),
	preload("res://scenes/segment_double_jump.tscn"),
	preload("res://scenes/segment_slide_intro.tscn"),
	preload("res://scenes/segment_rest.tscn"),
	preload("res://scenes/segment_rope.tscn"),
	preload("res://scenes/segment_mixed.tscn"),
	preload("res://scenes/segment_triple_jump.tscn"),
	preload("res://scenes/segment_slalom.tscn"),
	preload("res://scenes/segment_rope_switch.tscn"),
	preload("res://scenes/segment_combo.tscn"),
	preload("res://scenes/segment_finish.tscn"),
	preload("res://scenes/segment_darts.tscn"),
	preload("res://scenes/segment_jump_map.tscn"),
	preload("res://scenes/segment_rope_map.tscn"),
	preload("res://scenes/segment_platform_dart_map.tscn"),
	preload("res://scenes/segment_ninja_map.tscn"),
	preload("res://scenes/segment_jump_slide_phrase.tscn"),
	preload("res://scenes/segment_slide_platform_phrase.tscn"),
	preload("res://scenes/segment_dart_jump_slide_phrase.tscn"),
	preload("res://scenes/segment_short_recovery.tscn")
]


# =========================================================
# 核心节点
# =========================================================

var player: Variant = null
var combat: Variant = null

var hud_root: Node = null
var message: Label = null

var dynamic_camera: Node = null


# =========================================================
# 路线
# =========================================================

var active_chunks: Array[Node2D] = []

var next_chunk_entry := Vector2(0.0, 460.0)

@export var route_seed := 0

var route_generator: Variant = null

var route_cycle := 0
var route_steps: Array[int] = []
var route_step_index := 0


# =========================================================
# 游戏状态
# =========================================================

var run_state := RunState.RUNNING
var arena_x := START_POSITION.x

var score := 0
var distance_m := 0

# 开局为空。
# 只通过收集金币增加。
var energy := 0.0


# =========================================================
# 正式 HUD
# =========================================================

var formal_hud: Control = null

var score_label: Label = null
var distance_label: Label = null

var chakra_bar: ProgressBar = null
var chakra_percent_label: Label = null

var pause_button: Button = null

var weapon_skill_button: Button = null
var ninjutsu_skill_button: Button = null

var weapon_cooldown_label: Label = null
var ninjutsu_cooldown_label: Label = null

var debug_overlay: Control = null
var encounter_hint: Label = null

var f1_was_down := false


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	player = get_node_or_null("Player")

	if player == null:
		push_error("game.gd: 找不到 Player 节点。")
		set_physics_process(false)
		return

	player.process_mode = Node.PROCESS_MODE_PAUSABLE

	dynamic_camera = get_node_or_null("DynamicCamera")

	if dynamic_camera != null:
		dynamic_camera.process_mode = Node.PROCESS_MODE_PAUSABLE

	ensure_hud_root()
	ensure_message()

	setup_combat()
	setup_hud()

	reset_route_generator()
	spawn_chunks_ahead(CHUNK_AHEAD)

	update_hud()


# =========================================================
# HUD 基础节点
# =========================================================

func ensure_hud_root() -> void:
	hud_root = get_node_or_null("HUD")

	if hud_root != null:
		return

	var new_hud: CanvasLayer = CanvasLayer.new()
	new_hud.name = "HUD"
	add_child(new_hud)

	hud_root = new_hud


func ensure_message() -> void:
	var existing_message: Node = hud_root.get_node_or_null("Message")

	if existing_message is Label:
		message = existing_message as Label
		return

	message = Label.new()
	message.name = "Message"

	hud_root.add_child(message)


# =========================================================
# COMBAT
# =========================================================

func setup_combat() -> void:
	combat = Combat.new()

	if combat == null:
		push_error("game.gd: 无法创建 player_combat.gd。")
		return

	combat.name = "Combat"
	combat.player = player

	add_child(combat)

	var combat_node: Node = combat as Node

	if combat_node != null:
		if combat_node.has_signal("target_destroyed"):
			combat_node.connect(
				"target_destroyed",
				Callable(self, "_on_target_destroyed")
			)

	setup_sword_visual()

	var player_node: Node = player as Node

	if player_node == null:
		return

	if player_node.has_signal("ninjutsu_requested"):
		player_node.connect(
			"ninjutsu_requested",
			Callable(self, "cast_ninjutsu")
		)

	if player_node.has_signal("fireball_requested"):
		player_node.connect(
			"fireball_requested",
			Callable(self, "cast_weapon_skill")
		)

	if player_node.has_signal("died"):
		player_node.connect(
			"died",
			Callable(self, "end_run")
		)

	# 注意：
	# 不再连接 sword_requested。
	# 当前设计为：
	#
	# Sword = 装备
	# Fireballs = Sword 的主动武器技能


func setup_sword_visual() -> void:
	var sword_visual: Node = null

	# 新版结构
	sword_visual = player.get_node_or_null(
		"PlayerVisual/Orientation/ActionPivot/Body/Sword"
	)

	# 如果 ActionPivot 还没建立，则兼容旧结构
	if sword_visual == null:
		sword_visual = player.get_node_or_null(
			"PlayerVisual/Orientation/Body/Sword"
		)

	if sword_visual != null:
		sword_visual.set("combat", combat)


func _on_target_destroyed() -> void:
	score += DESTRUCTION_SCORE


# =========================================================
# HUD 创建
# =========================================================

func setup_hud() -> void:
	hide_old_test_hud()

	formal_hud = Control.new()
	formal_hud.name = "FormalHUD"
	formal_hud.process_mode = Node.PROCESS_MODE_ALWAYS

	formal_hud.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	formal_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	formal_hud.z_index = 100

	hud_root.add_child(formal_hud)

	create_run_info()
	create_chakra_display()
	create_pause_button()
	create_skill_bar()

	setup_message()
	setup_debug_overlay()


# =========================================================
# 隐藏旧 UI
# =========================================================

func hide_old_test_hud() -> void:
	# 把旧 HUD 下所有内容隐藏。
	#
	# 这样会隐藏：
	# - 黑色标题框
	# - “水墨忍者 Godot 重制版”
	# - 旧 Sword / Fireball / Ninjutsu 按钮
	# - 底部操作说明
	# - EncounterHint
	#
	# 唯独保留 Message。

	for child in hud_root.get_children():
		if child == message:
			continue

		if child is CanvasItem:
			var canvas_item: CanvasItem = child as CanvasItem
			canvas_item.hide()


# =========================================================
# 左上：分数和距离
# =========================================================

func create_run_info() -> void:
	var container: VBoxContainer = VBoxContainer.new()

	container.name = "RunInfo"

	container.set_anchors_preset(
		Control.PRESET_TOP_LEFT
	)

	container.offset_left = 20.0
	container.offset_top = 16.0
	container.offset_right = 220.0
	container.offset_bottom = 90.0

	formal_hud.add_child(container)


	score_label = Label.new()
	score_label.text = "分数 000000"

	score_label.add_theme_font_size_override(
		"font_size",
		22
	)

	container.add_child(score_label)


	distance_label = Label.new()
	distance_label.text = "距离 0m"

	distance_label.add_theme_font_size_override(
		"font_size",
		15
	)

	container.add_child(distance_label)


# =========================================================
# 顶部中间：忍术进度
# =========================================================

func create_chakra_display() -> void:
	var container: VBoxContainer = VBoxContainer.new()

	container.name = "ChakraDisplay"

	container.anchor_left = 0.5
	container.anchor_right = 0.5
	container.anchor_top = 0.0
	container.anchor_bottom = 0.0

	container.offset_left = -160.0
	container.offset_right = 160.0
	container.offset_top = 14.0
	container.offset_bottom = 70.0

	formal_hud.add_child(container)


	var title: Label = Label.new()
	title.text = "忍术"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	title.add_theme_font_size_override(
		"font_size",
		14
	)

	container.add_child(title)


	chakra_bar = ProgressBar.new()

	chakra_bar.min_value = 0.0
	chakra_bar.max_value = ENERGY_MAX
	chakra_bar.value = energy

	chakra_bar.show_percentage = false

	chakra_bar.custom_minimum_size = Vector2(
		320.0,
		14.0
	)

	container.add_child(chakra_bar)


	chakra_percent_label = Label.new()
	chakra_percent_label.text = "0%"

	chakra_percent_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	chakra_percent_label.add_theme_font_size_override(
		"font_size",
		12
	)

	container.add_child(chakra_percent_label)


# =========================================================
# 右上：暂停
# =========================================================

func create_pause_button() -> void:
	pause_button = Button.new()

	pause_button.name = "PauseButton"
	pause_button.text = "Ⅱ"

	pause_button.process_mode = Node.PROCESS_MODE_ALWAYS

	pause_button.anchor_left = 1.0
	pause_button.anchor_right = 1.0
	pause_button.anchor_top = 0.0
	pause_button.anchor_bottom = 0.0

	pause_button.offset_left = -72.0
	pause_button.offset_right = -20.0
	pause_button.offset_top = 16.0
	pause_button.offset_bottom = 62.0

	pause_button.add_theme_font_size_override(
		"font_size",
		22
	)

	pause_button.pressed.connect(toggle_pause)

	formal_hud.add_child(pause_button)


# =========================================================
# 右下：技能
# =========================================================

func create_skill_bar() -> void:
	var skill_bar: HBoxContainer = HBoxContainer.new()

	skill_bar.name = "SkillBar"

	skill_bar.anchor_left = 1.0
	skill_bar.anchor_right = 1.0
	skill_bar.anchor_top = 1.0
	skill_bar.anchor_bottom = 1.0

	skill_bar.offset_left = -230.0
	skill_bar.offset_right = -18.0
	skill_bar.offset_top = -82.0
	skill_bar.offset_bottom = -16.0

	skill_bar.add_theme_constant_override(
		"separation",
		12
	)

	formal_hud.add_child(skill_bar)


	var weapon_slot: Dictionary = create_skill_slot(
		"武器技",
		"Q"
	)

	weapon_skill_button = (
		weapon_slot["button"] as Button
	)

	weapon_cooldown_label = (
		weapon_slot["cooldown"] as Label
	)

	var weapon_root: Control = (
		weapon_slot["root"] as Control
	)

	if weapon_skill_button != null:
		weapon_skill_button.pressed.connect(
			cast_weapon_skill
		)

	if weapon_root != null:
		skill_bar.add_child(weapon_root)


	var ninjutsu_slot: Dictionary = create_skill_slot(
		"忍术",
		"K"
	)

	ninjutsu_skill_button = (
		ninjutsu_slot["button"] as Button
	)

	ninjutsu_cooldown_label = (
		ninjutsu_slot["cooldown"] as Label
	)

	var ninjutsu_root: Control = (
		ninjutsu_slot["root"] as Control
	)

	if ninjutsu_skill_button != null:
		ninjutsu_skill_button.pressed.connect(
			cast_ninjutsu
		)

	if ninjutsu_root != null:
		skill_bar.add_child(ninjutsu_root)


func create_skill_slot(
	title: String,
	key_text: String
) -> Dictionary:

	var root: VBoxContainer = VBoxContainer.new()

	root.custom_minimum_size = Vector2(
		96.0,
		64.0
	)


	var button: Button = Button.new()

	button.text = title

	button.custom_minimum_size = Vector2(
		92.0,
		42.0
	)

	button.add_theme_font_size_override(
		"font_size",
		14
	)

	root.add_child(button)


	var state_row: HBoxContainer = HBoxContainer.new()
	root.add_child(state_row)


	var key_label: Label = Label.new()

	key_label.text = "[" + key_text + "]"

	key_label.add_theme_font_size_override(
		"font_size",
		11
	)

	state_row.add_child(key_label)


	var cooldown: Label = Label.new()

	cooldown.text = ""

	cooldown.add_theme_font_size_override(
		"font_size",
		11
	)

	state_row.add_child(cooldown)


	return {
		"root": root,
		"button": button,
		"cooldown": cooldown
	}


# =========================================================
# Message
# =========================================================

func setup_message() -> void:
	if message == null:
		return

	message.process_mode = Node.PROCESS_MODE_ALWAYS

	message.anchor_left = 0.5
	message.anchor_right = 0.5
	message.anchor_top = 0.5
	message.anchor_bottom = 0.5

	message.offset_left = -170.0
	message.offset_right = 170.0
	message.offset_top = -80.0
	message.offset_bottom = 80.0

	message.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	message.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	message.add_theme_font_size_override(
		"font_size",
		27
	)

	set_message("")


func set_message(text: String) -> void:
	if message == null:
		return

	message.text = text
	message.visible = not text.is_empty()


# =========================================================
# Debug
# =========================================================

func setup_debug_overlay() -> void:
	debug_overlay = Control.new()

	debug_overlay.name = "DebugOverlay"

	debug_overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	debug_overlay.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	formal_hud.add_child(debug_overlay)


	encounter_hint = Label.new()

	encounter_hint.offset_left = 20.0
	encounter_hint.offset_top = 88.0
	encounter_hint.offset_right = 900.0
	encounter_hint.offset_bottom = 240.0

	# Pattern 调试要展示多行（阶段 / 当前 Pattern / Modifier / 难度），
	 # 因此允许自动换行并按行高排版。
	encounter_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	encounter_hint.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	encounter_hint.add_theme_font_size_override(
		"font_size",
		14
	)

	debug_overlay.add_child(encounter_hint)

	# 默认不显示任何测试说明。
	debug_overlay.hide()


# =========================================================
# 主循环
# =========================================================

func _physics_process(delta: float) -> void:
	handle_global_input()

	if run_state != RunState.RUNNING:
		return

	arena_x = maxf(arena_x + player.run_speed * delta, player.global_position.x)
	dynamic_camera.forward_x = arena_x
	update_distance_and_score()

	spawn_chunks_ahead(
		arena_x + CHUNK_AHEAD
	)

	cleanup_chunks()

	if combat != null:
		combat.advance(delta)

	for chunk: Node2D in active_chunks:
		if chunk is MapModuleChunk:
			chunk.advance(delta, player, arena_x)
		elif chunk.has_method("advance"):
			chunk.call(
				"advance",
				delta,
				player
			)

	var screen_left: float = dynamic_camera.get_screen_center_position().x - get_viewport_rect().size.x / (2.0 * dynamic_camera.zoom.x)
	if float(player.global_position.y) > FALL_DEATH_Y or player.global_position.x + player.PLAYER_WIDTH * 0.5 < screen_left:
		var max_hp: float = float(player.MAX_HP)
		player.take_damage(max_hp)

	update_hud()


# =========================================================
# INPUT
# =========================================================

func handle_global_input() -> void:
	if Input.is_action_just_pressed("restart"):
		restart_run()

	if (
		Input.is_action_just_pressed("pause")
		and run_state != RunState.GAME_OVER
	):
		toggle_pause()

	var f1_down: bool = Input.is_key_pressed(KEY_F1)

	if f1_down and not f1_was_down:
		if debug_overlay != null:
			debug_overlay.visible = (
				not debug_overlay.visible
			)

	f1_was_down = f1_down


# =========================================================
# 分数 / 距离
# =========================================================

func update_distance_and_score() -> void:
	var player_x: float = float(
		player.global_position.x
	)

	var travelled: float = maxf(
		0.0,
		player_x - START_POSITION.x
	)

	distance_m = int(
		travelled / 100.0
	)

	score = maxi(
		score,
		distance_m * 10
	)


# =========================================================
# ROUTE
# =========================================================

func spawn_chunks_ahead(limit_x: float) -> void:
	while next_chunk_entry.x < limit_x:
		var spawned: bool = spawn_chunk()

		if not spawned:
			push_error(
				"game.gd: Chunk 创建失败，停止继续生成，防止死循环。"
			)
			break


func spawn_chunk() -> bool:
	var chunk_index: int = next_chunk_kind()

	if (
		chunk_index < 0
		or chunk_index >= CHUNK_SCENES.size()
	):
		push_error(
			"game.gd: route_generator 返回了非法 chunk index: %d"
			% chunk_index
		)

		return false


	var instance: Node = (
		CHUNK_SCENES[chunk_index].instantiate()
	)

	var chunk: Node2D = instance as Node2D

	if chunk == null:
		push_error(
			"game.gd: Chunk 根节点不是 Node2D。"
		)

		if instance != null:
			instance.queue_free()

		return false


	chunk.process_mode = Node.PROCESS_MODE_PAUSABLE
	var layout_seed: int = hash("%d:%d:%d" % [route_generator.base_seed, route_cycle, route_step_index])
	if chunk is MapModuleChunk or chunk_index == ROUTE_GENERATOR_SCRIPT.ChunkKind.SAFE:
		chunk.set("layout_seed", layout_seed)

	add_child(chunk)


	var entry: Node2D = (
		chunk.get_node_or_null("Entry") as Node2D
	)

	var exit: Node2D = (
		chunk.get_node_or_null("Exit") as Node2D
	)

	if entry == null or exit == null:
		push_error(
			"game.gd: Chunk 缺少 Entry 或 Exit 节点: %s"
			% chunk.name
		)

		chunk.queue_free()
		return false


	if chunk.has_signal("player_contact"):
		chunk.connect(
			"player_contact",
			Callable(
				self,
				"on_chunk_player_contact"
			)
		)


	if chunk.has_signal("coin_collected"):
		chunk.connect(
			"coin_collected",
			Callable(
				self,
				"on_chunk_coin_collected"
			)
		)


	chunk.global_position += (
		next_chunk_entry
		- entry.global_position
	)


	var hint: Node = chunk.get_node_or_null("Hint")

	if hint is CanvasItem:
		var hint_canvas: CanvasItem = hint as CanvasItem
		hint_canvas.hide()


	active_chunks.append(chunk)

	next_chunk_entry = exit.global_position

	return true


func next_chunk_kind() -> int:
	if route_generator == null:
		return 0


	if route_step_index >= route_steps.size():
		var generated_steps: Variant = (
			route_generator.build_cycle(
				route_cycle
			)
		)

		route_steps.clear()

		if generated_steps is Array:
			var raw_steps: Array = generated_steps

			for raw_step in raw_steps:
				route_steps.append(
					int(raw_step)
				)

		route_cycle += 1
		route_step_index = 0


	if route_steps.is_empty():
		return 0


	var chunk_kind: int = (
		route_steps[route_step_index]
	)

	route_step_index += 1

	return chunk_kind


func reset_route_generator() -> void:
	var seed: int = route_seed

	if seed == 0:
		seed = int(
			Time.get_ticks_usec()
		)

	route_generator = (
		ROUTE_GENERATOR_SCRIPT.new(seed)
	)

	route_cycle = 0
	route_steps.clear()
	route_step_index = 0


func cleanup_chunks() -> void:
	var player_x: float = float(
		player.global_position.x
	)

	var cleanup_x: float = (
		player_x
		- CHUNK_CLEAN_BEHIND
	)


	var chunks_copy: Array[Node2D] = (
		active_chunks.duplicate()
	)

	for chunk: Node2D in chunks_copy:
		var exit: Node2D = (
			chunk.get_node_or_null("Exit") as Node2D
		)

		if exit == null:
			active_chunks.erase(chunk)
			chunk.queue_free()
			continue


		if exit.global_position.x >= cleanup_x:
			continue


		active_chunks.erase(chunk)
		chunk.queue_free()


# =========================================================
# 碰撞 / 金币
# =========================================================

func on_chunk_player_contact(
	contacted_player: Node2D,
	damage: float
) -> void:

	if run_state != RunState.RUNNING:
		return

	if contacted_player != player:
		return

	player.take_damage(damage)


func on_chunk_coin_collected(
	coin_score: int,
	coin_energy: float
) -> void:

	if run_state != RunState.RUNNING:
		return


	score += coin_score


	# 忍术只能通过金币/收集物积攒。
	#
	# 如果旧金币已经定义了 coin_energy，
	# 就使用它。
	#
	# 如果传入 0，则默认使用 DEFAULT_COIN_ENERGY。

	var gained_energy: float = coin_energy

	if gained_energy <= 0.0:
		gained_energy = DEFAULT_COIN_ENERGY


	energy = minf(
		ENERGY_MAX,
		energy + gained_energy
	)

	update_hud()


# =========================================================
# 技能
# =========================================================

func cast_weapon_skill() -> void:
	if run_state != RunState.RUNNING:
		return

	if combat == null:
		return

	combat.cast_fireballs()

	update_hud()


func cast_ninjutsu() -> void:
	if run_state != RunState.RUNNING:
		return

	if combat == null:
		return

	# 必须金币收集到满槽才能释放。
	if energy < ENERGY_MAX:
		return


	var cast_success: bool = bool(
		combat.cast_ninjutsu()
	)

	if cast_success:
		energy = 0.0

	update_hud()


# =========================================================
# 暂停 / 死亡 / 重开
# =========================================================

func toggle_pause() -> void:
	if run_state == RunState.GAME_OVER:
		return


	if run_state == RunState.PAUSED:
		run_state = RunState.RUNNING

		set_message("")

		get_tree().paused = false

	else:
		run_state = RunState.PAUSED

		set_message(
			"暂停\n\nP / Esc 继续"
		)

		get_tree().paused = true


	update_hud()


func end_run() -> void:
	run_state = RunState.GAME_OVER

	set_message(
		"任务失败\n\nR 重新开始"
	)

	if combat != null:
		combat.reset()

	get_tree().paused = true

	update_hud()


func restart_run() -> void:
	get_tree().paused = false

	if combat != null:
		combat.reset()


	for chunk: Node2D in active_chunks:
		if is_instance_valid(chunk):
			chunk.queue_free()


	active_chunks.clear()

	next_chunk_entry = Vector2(
		0.0,
		460.0
	)


	reset_route_generator()


	run_state = RunState.RUNNING
	arena_x = START_POSITION.x

	score = 0
	distance_m = 0

	# 重开后忍术为空
	energy = 0.0

	set_message("")


	player.reset_run(
		START_POSITION
	)


	spawn_chunks_ahead(
		CHUNK_AHEAD
	)

	update_hud()


# =========================================================
# HUD UPDATE
# =========================================================

func update_hud() -> void:
	if formal_hud == null:
		return


	if score_label != null:
		score_label.text = (
			"分数 %06d"
			% score
		)


	if distance_label != null:
		distance_label.text = (
			"距离 %dm"
			% distance_m
		)


	if chakra_bar != null:
		chakra_bar.value = energy


	if chakra_percent_label != null:
		chakra_percent_label.text = (
			"%d%%"
			% int(energy)
		)


	update_debug_hint()
	update_weapon_skill_hud()
	update_ninjutsu_hud()


	if pause_button != null:
		pause_button.disabled = (
			run_state == RunState.GAME_OVER
		)


# =========================================================
# Debug Hint
# =========================================================

func update_debug_hint() -> void:
	if encounter_hint == null:
		return


	encounter_hint.text = ""


	if (
		debug_overlay == null
		or not debug_overlay.visible
	):
		return


	var player_x: float = float(
		player.global_position.x
	)


	for chunk: Node2D in active_chunks:
		var entry: Node2D = (
			chunk.get_node_or_null("Entry") as Node2D
		)

		var exit: Node2D = (
			chunk.get_node_or_null("Exit") as Node2D
		)


		if entry == null or exit == null:
			continue


		if (
			player_x >= entry.global_position.x
			and player_x < exit.global_position.x
		):
			encounter_hint.text = _debug_text_for(chunk, player_x)

			break


# 由 Segment 提供自身调试文本；未接入的旧 Segment 回退到 Hint。
func _debug_text_for(chunk: Node2D, player_x: float) -> String:
	if chunk.has_method("debug_info"):
		var info: Variant = chunk.call("debug_info")

		if info is Dictionary and not (info as Dictionary).is_empty():
			return _format_pattern_debug(
				info as Dictionary,
				chunk,
				player_x
			)


	var hint: Node = (
		chunk.get_node_or_null("Hint")
	)

	if hint is Label:
		return (hint as Label).text


	return ""


# 正式关卡的 Pattern 调试展示。
# 目的是让人工试玩反馈能直接引用阶段与 Pattern 名，
# 例如「飞镖地图 A / 飞镖墙阶段 / 飞镖墙加强太紧」。
func _format_pattern_debug(
	info: Dictionary,
	chunk: Node2D,
	player_x: float
) -> String:
	var lines: PackedStringArray = PackedStringArray()

	var map_name: String = str(info.get("map", info.get("segment", "?")))
	var map_id: String = str(info.get("map_id", ""))
	if not map_id.is_empty():
		map_name = "%s (%s)" % [map_name, map_id]
	lines.append("Map: %s" % map_name)


	var current: Dictionary = {}

	if chunk.has_method("debug_info_at"):
		var raw: Variant = chunk.call("debug_info_at", player_x)

		if raw is Dictionary:
			current = raw as Dictionary


	if not current.is_empty():
		var section_name: String = str(current.get("section", info.get("section", "?")))
		var section_id: String = str(current.get("section_id", ""))
		if not section_id.is_empty():
			section_name = "%s (%s)" % [section_name, section_id]
		lines.append("Section: %s" % section_name)

		var stage: String = str(current.get("wave", current.get("stage", "")))

		if not stage.is_empty():
			lines.append("Wave: %s" % stage)


		if current.get("kind", "") == "pattern":
			# 优先显示人类可读名称，内部编号放括号里。
			# 例如「低位单飞镖 (P04)」，方便直接口述反馈。
			var display: String = str(current.get("display_name", ""))
			var template: String = str(current.get("template", "?"))
			if display.is_empty():
				display = str(current.get("pattern_name", "?"))
			lines.append("Pattern: %s (%s)" % [display, template])
		else:
			var recovery_display: String = str(current.get("display_name", "喘息"))
			if recovery_display.is_empty():
				recovery_display = "喘息"
			lines.append("Pattern: %s" % recovery_display)


		lines.append(
			"Modifier: %s    Difficulty: %d"
			% [
				_modifier_label(int(current.get("modifier", 0))),
				int(current.get("difficulty", 0)),
			]
		)


	lines.append("Sequence: %s" % info.get("sequence", ""))

	lines.append("Length: %.0f px" % float(info.get("total_length", 0.0)))


	var issues: Variant = info.get("issues")

	if issues is PackedStringArray and (issues as PackedStringArray).size() > 0:
		lines.append("ISSUES: %s" % "; ".join(issues as PackedStringArray))


	return "\n".join(lines)


func _modifier_label(kind: int) -> String:
	var labels: PackedStringArray = PackedStringArray([
		"NORMAL",
		"FAST",
		"SLOW",
		"MIRRORED",
		"DOUBLE",
		"REVERSE",
	])

	if kind < 0 or kind >= labels.size():
		return "NORMAL"


	return labels[kind]


# =========================================================
# 武器技能 HUD
# =========================================================

func update_weapon_skill_hud() -> void:
	if (
		weapon_skill_button == null
		or weapon_cooldown_label == null
		or combat == null
	):
		return


	var cooldown: float = float(
		combat.fireball_cooldown
	)


	weapon_skill_button.disabled = (
		run_state != RunState.RUNNING
		or cooldown > 0.0
	)


	if cooldown > 0.0:
		weapon_cooldown_label.text = (
			" %.1fs"
			% cooldown
		)
	else:
		weapon_cooldown_label.text = " 就绪"


# =========================================================
# 忍术 HUD
# =========================================================

func update_ninjutsu_hud() -> void:
	if (
		ninjutsu_skill_button == null
		or ninjutsu_cooldown_label == null
		or combat == null
	):
		return


	var cooldown: float = float(
		combat.ninjutsu_cooldown
	)


	var energy_ready: bool = (
		energy >= ENERGY_MAX
	)

	var cooldown_ready: bool = (
		cooldown <= 0.0
	)


	ninjutsu_skill_button.disabled = (
		run_state != RunState.RUNNING
		or not energy_ready
		or not cooldown_ready
	)


	if cooldown > 0.0:
		ninjutsu_cooldown_label.text = (
			" %.1fs"
			% cooldown
		)

	elif not energy_ready:
		ninjutsu_cooldown_label.text = (
			" %d%%"
			% int(energy)
		)

	else:
		ninjutsu_cooldown_label.text = " 就绪"
