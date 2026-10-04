extends Node2D

const Library := preload("res://patterns/pattern_library.gd")
const Section := preload("res://patterns/pattern_section.gd")
const Preview := preload("res://patterns/pattern_preview.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")
const Combat := preload("res://components/player_combat.gd")
const START := Vector2(140, 460)

@export var custom_pattern: ObstaclePatternData
@export var enable_runtime_bridge := true
@export var recovery: RecoverySection = preload("res://patterns/library/Recovery.tres")
@export_range(0, 11) var pattern_index := 0
@export_range(1, 5) var difficulty := 3
@export_enum("NORMAL", "FAST", "SLOW", "MIRRORED", "DOUBLE", "REVERSE") var modifier := 0
@onready var player: Variant = $Player
@onready var selector: OptionButton = $HUD/Panel/Rows/Selectors/Pattern
@onready var difficulty_selector: OptionButton = $HUD/Panel/Rows/Selectors/Difficulty
@onready var modifier_selector: OptionButton = $HUD/Panel/Rows/Selectors/Modifier
@onready var status: Label = $HUD/Panel/Rows/Status
var section: PatternSection
var combat: Node2D
var preview: PatternPreview
var stopped := false
var debug_visible := true
var current_data: ObstaclePatternData

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	$DynamicCamera.process_mode = Node.PROCESS_MODE_PAUSABLE
	configure_ui()
	combat = Combat.new()
	combat.player = player
	add_child(combat)
	player.get_node("PlayerVisual/Orientation/ActionPivot/Body/Sword").combat = combat
	player.ninjutsu_requested.connect(func() -> void: combat.cast_ninjutsu())
	player.fireball_requested.connect(func() -> void: combat.cast_fireballs())
	# 注意：
	# 不连接 sword_requested。
	#
	# 正式游戏（game.gd）同样不连接它。工作台用于验证正式关卡的 Pattern，
	# 因此能力基线必须与正式游戏保持一致：
	#
	# Sword = 装备
	# Fireballs = Sword 的主动武器技能
	#
	# 剑斩相关代码仍保留在 components/player_combat.gd 中，
	# 但"代码里仍存在"不代表它属于玩家正式能力集。
	player.died.connect(func() -> void: finish_test("角色死亡；R 重开"))
	restart_pattern()
	if enable_runtime_bridge and OS.has_feature("editor"):
		var bridge: Node = load("res://addons/godot-mcp/runtime_bridge.gd").new()
		bridge.name = "PatternTestBridge"
		add_child(bridge)

func configure_ui() -> void:
	for name in Library.NAMES:
		selector.add_item(name)
	for level in range(1, 6):
		difficulty_selector.add_item("难度 %d" % level)
	for label in Modifier.LABELS:
		modifier_selector.add_item(label)
	selector.item_selected.connect(select_pattern)
	difficulty_selector.item_selected.connect(func(index: int) -> void: difficulty = index + 1; restart_pattern())
	modifier_selector.item_selected.connect(func(index: int) -> void: modifier = index; restart_pattern())
	$HUD/Panel/Rows/Buttons/Restart.pressed.connect(restart_pattern)
	$HUD/Panel/Rows/Buttons/Previous.pressed.connect(func() -> void: select_pattern(pattern_index - 1))
	$HUD/Panel/Rows/Buttons/Next.pressed.connect(func() -> void: select_pattern(pattern_index + 1))
	$HUD/Panel/Rows/Buttons/Debug.toggled.connect(func(value: bool) -> void: debug_visible = value; preview.visible = value)

func select_pattern(index: int) -> void:
	pattern_index = posmod(index, Library.NAMES.size())
	custom_pattern = null
	restart_pattern()

func restart_pattern() -> void:
	get_tree().paused = false
	stopped = false
	combat.reset()
	if is_instance_valid(section):
		remove_child(section)
		section.queue_free()
	current_data = custom_pattern if custom_pattern != null else Library.load_pattern(pattern_index)
	if not Modifier.supported(current_data, modifier):
		modifier = Modifier.Kind.NORMAL
	selector.select(pattern_index)
	difficulty_selector.select(difficulty - 1)
	modifier_selector.select(modifier)
	for index in Modifier.LABELS.size():
		modifier_selector.set_item_disabled(index, not Modifier.supported(current_data, index))
	player.reset_run(START)
	section = Section.new()
	section.name = "Section"
	section.position = START
	add_child(section)
	var entries: Array[Resource] = [current_data, recovery]
	section.build(entries, player, difficulty, modifier, recovery)
	section.add_ground(-600, 600)
	preview = Preview.new()
	preview.name = "DebugPreview"
	preview.plan = section.runners[0].plan
	preview.runner = section.runners[0]
	preview.visible = debug_visible
	section.add_child(preview)
	$HUD/Panel/Rows/Instruction.text = current_data.instruction
	if not preview.plan.issues.is_empty():
		finish_test("参数检查阻止运行：" + "；".join(preview.plan.issues))
	else:
		update_status()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_R: restart_pattern()
		KEY_BRACKETRIGHT, KEY_PAGEDOWN: select_pattern(pattern_index + 1)
		KEY_BRACKETLEFT, KEY_PAGEUP: select_pattern(pattern_index - 1)
		KEY_F1: $HUD/Panel/Rows/Buttons/Debug.button_pressed = not debug_visible
		KEY_P, KEY_ESCAPE:
			if not stopped:
				get_tree().paused = not get_tree().paused
				update_status()

func _physics_process(delta: float) -> void:
	if stopped or get_tree().paused:
		return
	combat.advance(delta)
	section.advance(delta, player)
	if player.global_position.y > 900:
		finish_test("落入坑中；R 重开")
	elif player.global_position.x >= START.x + section.section_length - 60:
		finish_test("本次抵达终点；仍需人工判断难度与路线，R 重开")
	else:
		update_status()

func finish_test(message: String) -> void:
	stopped = true
	get_tree().paused = true
	status.text = message

func update_status() -> void:
	var runner := section.runners[0]
	status.text = "%s | %.1fs | 速度 %.0f | 事件 %d/%d | 需人工试玩\n蓝色=站立范围/参考单跳弧线（非通关解），绿色=安全口，红色=坑/障碍" % ["暂停" if get_tree().paused else ("Recovery" if runner.completed else "运行"), runner.elapsed, player.velocity.x, runner.spawned_count, runner.plan.events.size()]

func get_test_status() -> Dictionary:
	return {"pattern": current_data.pattern_name, "difficulty": difficulty, "modifier": Modifier.LABELS[modifier], "elapsed": section.runners[0].elapsed, "spawned": section.runners[0].spawned_count, "events": section.runners[0].plan.events.size(), "issues": section.runners[0].plan.issues, "health": player.health, "needs_manual_playtest": true}
