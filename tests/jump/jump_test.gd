extends Node2D

const GROUND_Y := 460.0
const START := Vector2(140, GROUND_Y)
const END_X := 1500.0
const CASE_NAMES := ["1 · 点按完整跳", "2 · 高障碍与落点", "3 · 二段跳修正", "4 · 团身穿缝", "5 · 连续高低控制"]
const INSTRUCTIONS := [
	"点一下 Space 即可完整起跳；松手不影响高度，按 S 可随时快速下落。",
	"点按 Space 越过 96px 高块，利用较慢的自然下落或按 S 选择落点。",
	"越过 250px 缺口：先跳，在空中再次按 Space 修正轨迹。",
	"二段翻滚进入 58px 通道；40px 团身可通过，66px 站姿无法直接进入。",
	"先跳高台，二段跳修正，再按 S 急降避开横梁；双按 S 可接滑铲。"
]
@export var enable_runtime_bridge := true
@onready var player: Variant = $Player
@onready var selector: OptionButton = $HUD/Panel/Rows/Controls/Case
@onready var status: Label = $HUD/Panel/Rows/Status
var case_index := 0
var course: Node2D
var elapsed := 0.0
var peak_height := 0.0
var debug_visible := true
var finished := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	$Camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	for label in CASE_NAMES:
		selector.add_item(label)
	selector.item_selected.connect(select_case)
	$HUD/Panel/Rows/Controls/Start.pressed.connect(toggle_pause)
	$HUD/Panel/Rows/Controls/Restart.pressed.connect(restart)
	$HUD/Panel/Rows/Controls/Next.pressed.connect(next_case)
	player.died.connect(func() -> void: stop("角色死亡；R 重开"))
	restart()
	if enable_runtime_bridge and OS.has_feature("editor"):
		var bridge: Node = load("res://addons/godot-mcp/runtime_bridge.gd").new()
		bridge.name = "JumpTestBridge"
		add_child(bridge)

func select_case(index: int) -> void:
	case_index = posmod(index, CASE_NAMES.size())
	restart()

func next_case() -> void:
	select_case(case_index + 1)

func restart() -> void:
	Input.action_release("jump")
	Input.action_release("slide")
	if is_instance_valid(course):
		remove_child(course)
		course.queue_free()
	course = Node2D.new()
	course.name = "Course"
	add_child(course)
	build_course()
	player.reset_run(START)
	elapsed = 0
	peak_height = 0
	finished = false
	selector.select(case_index)
	$HUD/Panel/Rows/Instruction.text = INSTRUCTIONS[case_index]
	get_tree().paused = true
	update_status()
	queue_redraw()

func toggle_pause() -> void:
	if finished:
		restart()
	get_tree().paused = not get_tree().paused
	update_status()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_P: toggle_pause()
		KEY_R: restart()
		KEY_BRACKETRIGHT, KEY_PAGEDOWN: next_case()
		KEY_BRACKETLEFT, KEY_PAGEUP: select_case(case_index - 1)
		KEY_F1: debug_visible = not debug_visible; queue_redraw()

func _physics_process(delta: float) -> void:
	if get_tree().paused or finished:
		return
	elapsed += delta
	peak_height = maxf(peak_height, GROUND_Y - player.position.y)
	if player.position.y > 800:
		stop("落入缺口；R 重开，可尝试更晚触发二段跳")
	elif player.position.x > END_X:
		stop("到达终点；R 重试当前项目，] 下一个")
	else:
		update_status()
	queue_redraw()

func stop(message: String) -> void:
	finished = true
	get_tree().paused = true
	status.text = message + " | 本轮最高 %.0fpx" % peak_height

func update_status() -> void:
	var air_names := ["地面", "一段上升", "二段翻滚", "二段上升", "下落"]
	var waiting: bool = player.roll_hitbox_active and player.roll_remaining <= 0
	status.text = "%s | %s | 最高 %.0fpx | 竖直速度 %.0f | 碰撞 %.0f×%.0f\n%s" % [
		"按 Enter 开始/继续" if get_tree().paused else "运行", air_names[player.air_state], peak_height,
		player.velocity.y, player.body_collision.shape.size.x, player.body_collision.shape.size.y,
		"空间不足：保持团身，离开后自动恢复" if waiting else "Space 跳/二段跳 · S 急降/滑铲 · R 重开 · [ / ] 切换 · P 暂停 · F1 碰撞框"]

func build_course() -> void:
	if case_index == 2:
		block(Rect2(-500, GROUND_Y, 1100, 120), true)
		block(Rect2(850, GROUND_Y - 20, 1200, 140), true)
		marker(Vector2(600, GROUND_Y + 10), "250px 缺口")
	else:
		block(Rect2(-500, GROUND_Y, 2600, 120), true)
	match case_index:
		0: block(Rect2(540, GROUND_Y - 24, 28, 24))
		1: block(Rect2(540, GROUND_Y - 96, 36, 96))
		3:
			block(Rect2(600, 150, 140, 162))
			block(Rect2(600, 370, 140, 90))
			marker(Vector2(610, 270), "58px 团身通道")
		4:
			block(Rect2(540, 390, 36, 70))
			block(Rect2(720, 140, 60, 200))
	marker(Vector2(390, GROUND_Y + 6), "起跳参考区")
	marker(Vector2(END_X, GROUND_Y - 30), "终点")

func block(rect: Rect2, ground := false) -> void:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	collision.position = rect.get_center()
	body.add_child(collision)
	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	fill.color = Color("334d43") if ground else Color("967757")
	body.add_child(fill)
	course.add_child(body)

func marker(at: Vector2, text: String) -> void:
	var label := Label.new()
	label.position = at
	label.text = text
	label.add_theme_color_override("font_color", Color("f1e4bd"))
	label.add_theme_color_override("font_outline_color", Color("263c32"))
	label.add_theme_constant_override("outline_size", 4)
	course.add_child(label)

func _draw() -> void:
	if not debug_visible or not is_instance_valid(player):
		return
	var size: Vector2 = player.body_collision.shape.size
	draw_rect(Rect2(player.position + player.body_collision.position - size / 2.0, size), Color("d77c26") if player.roll_hitbox_active else Color("218daa"), false, 1.5)

func get_test_status() -> Dictionary:
	return {"case": CASE_NAMES[case_index], "paused": get_tree().paused, "elapsed": elapsed, "peak_height": peak_height,
		"air_state": player.AirState.keys()[player.air_state], "jumps_used": player.jumps_used,
		"roll_remaining": player.roll_remaining, "hitbox": player.body_collision.shape.size,
		"roll_hitbox_active": player.roll_hitbox_active, "position": player.position, "velocity": player.velocity,
		"roll_angle": player.get_node("PlayerVisual/Orientation/ActionPivot").rotation}
