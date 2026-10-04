extends Node2D

const IDLE_SECONDS := 1.2
const RUN_SECONDS := 0.33
const JUMP_START_SECONDS := 0.09
const JUMP_UP_SECONDS := 0.3
const DOUBLE_JUMP_SECONDS := 0.32
const FALL_SECONDS := 0.3
const LAND_SECONDS := 0.12
const SLIDE_SECONDS := 0.58
const ROPE_FLIP_SECONDS := 0.18
const PLAYER_HEIGHT_PIXELS := 66.0
const ROLL_PIVOT_PIXELS := 20.0
const LIFTOFF_HEIGHT_PIXELS := -8.0
const FIRST_APEX_PIXELS := -32.0
const DOUBLE_JUMP_HEIGHT_PIXELS := -46.0
const SECOND_APEX_PIXELS := -58.0
const ROPE_DISPLAY_Y := -75.0

const STAGES: Array[Dictionary] = [
	{"label": "待机", "action": &"idle", "seconds": IDLE_SECONDS},
	{"label": "跑步", "action": &"run", "seconds": RUN_SECONDS * 2.0},
	{"label": "一段起跳", "action": &"jump_start", "seconds": JUMP_START_SECONDS, "to_y": LIFTOFF_HEIGHT_PIXELS},
	{"label": "一段上升", "action": &"jump_up", "seconds": JUMP_UP_SECONDS, "from_y": LIFTOFF_HEIGHT_PIXELS, "to_y": FIRST_APEX_PIXELS},
	{"label": "下落", "action": &"fall", "seconds": FALL_SECONDS, "from_y": FIRST_APEX_PIXELS},
	{"label": "落地", "action": &"land", "seconds": LAND_SECONDS},
	{"label": "恢复跑步", "action": &"run", "seconds": RUN_SECONDS},
	{"label": "再次起跳", "action": &"jump_start", "seconds": JUMP_START_SECONDS, "to_y": LIFTOFF_HEIGHT_PIXELS},
	{"label": "上升，可被二段跳打断", "action": &"jump_up", "seconds": JUMP_UP_SECONDS, "from_y": LIFTOFF_HEIGHT_PIXELS, "to_y": FIRST_APEX_PIXELS},
	{"label": "二段跳整身翻滚（外层支点）", "action": &"double_jump", "seconds": DOUBLE_JUMP_SECONDS, "from_y": FIRST_APEX_PIXELS, "to_y": DOUBLE_JUMP_HEIGHT_PIXELS, "roll": true},
	{"label": "二段跳继续上升", "action": &"jump_up", "seconds": JUMP_UP_SECONDS, "from_y": DOUBLE_JUMP_HEIGHT_PIXELS, "to_y": SECOND_APEX_PIXELS},
	{"label": "二段跳下落", "action": &"fall", "seconds": FALL_SECONDS * 2.0, "from_y": SECOND_APEX_PIXELS},
	{"label": "再次落地", "action": &"land", "seconds": LAND_SECONDS},
	{"label": "跑步", "action": &"run", "seconds": RUN_SECONDS},
	{"label": "滑铲", "action": &"slide", "seconds": SLIDE_SECONDS},
	{"label": "滑铲后返回跑步", "action": &"run", "seconds": RUN_SECONDS * 2.0},
	{"label": "绳索上方", "action": &"run", "seconds": RUN_SECONDS, "rope": true},
	{"label": "绳索翻至下方", "action": &"double_jump", "seconds": ROPE_FLIP_SECONDS, "rope": true, "flip": true, "from_side": 0.0, "to_side": 1.0},
	{"label": "绳索下方镜像", "action": &"run", "seconds": RUN_SECONDS, "rope": true, "bottom": true},
	{"label": "绳索翻回上方", "action": &"double_jump", "seconds": ROPE_FLIP_SECONDS, "rope": true, "flip": true, "from_side": 1.0, "to_side": 0.0},
	{"label": "绳索上方恢复跑步", "action": &"run", "seconds": RUN_SECONDS, "rope": true},
	{"label": "返回待机，继续完整链", "action": &"idle", "seconds": IDLE_SECONDS},
]

@onready var visual_anchor: Node2D = $Stage/PreviewVisual
@onready var orientation: Node2D = $Stage/PreviewVisual/Orientation
@onready var action_pivot: Node2D = $Stage/PreviewVisual/Orientation/ActionPivot
@onready var rig: Node2D = $Stage/PreviewVisual/Orientation/ActionPivot/VisualRoot_V2
@onready var animation_player: AnimationPlayer = $Stage/PreviewVisual/Orientation/ActionPivot/VisualRoot_V2/AnimationPlayer
@onready var rope_line: Line2D = $Stage/RopeLine
@onready var status: Label = $Status

var stage_index := 0
var stage_elapsed := 0.0
var paused := false


func _ready() -> void:
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.set_action_mode(true)
	replay()


func _process(delta: float) -> void:
	advance_preview(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_SPACE:
		toggle_pause()
	elif event.keycode == KEY_R:
		replay()
	else:
		return
	get_viewport().set_input_as_handled()


func advance_preview(delta: float) -> void:
	if paused or not is_finite(delta) or delta <= 0.0:
		return
	var remaining := delta
	# 按边界拆分时间，低帧率也必须依次经过每个动作和混合起点。
	while remaining > 0.0:
		var duration: float = STAGES[stage_index]["seconds"]
		var step := minf(remaining, duration - stage_elapsed)
		animation_player.advance(step)
		stage_elapsed += step
		remaining -= step
		if stage_elapsed >= duration:
			stage_index = (stage_index + 1) % STAGES.size()
			stage_elapsed = 0.0
			_start_stage()
	_apply_stage_pose()
	_refresh_status()


func toggle_pause() -> void:
	paused = not paused
	_refresh_status()


func replay() -> void:
	paused = false
	stage_index = 0
	stage_elapsed = 0.0
	visual_anchor.position = Vector2.ZERO
	orientation.position = Vector2.ZERO
	orientation.rotation = 0.0
	orientation.scale = Vector2.ONE
	action_pivot.position = Vector2.ZERO
	action_pivot.rotation = 0.0
	rig.position = Vector2.ZERO
	rig.reset_actions()
	_start_stage()
	_refresh_status()


func _start_stage() -> void:
	rig.play_action(STAGES[stage_index]["action"])
	animation_player.advance(0.0)
	_apply_stage_pose()


func _apply_stage_pose() -> void:
	var stage := STAGES[stage_index]
	var progress := stage_elapsed / float(stage["seconds"])
	visual_anchor.position.y = lerpf(stage.get("from_y", 0.0), stage.get("to_y", 0.0), progress)
	var flipping: bool = stage.get("flip", false)
	var hanging: bool = stage.get("bottom", false)
	var tucked: bool = flipping or stage.get("roll", false)
	orientation.position.y = -PLAYER_HEIGHT_PIXELS * lerpf(stage.get("from_side", 0.0), stage.get("to_side", 0.0), progress) if flipping else (-PLAYER_HEIGHT_PIXELS if hanging else 0.0)
	orientation.scale.y = -1.0 if hanging else 1.0
	action_pivot.position.y = -ROLL_PIVOT_PIXELS if tucked else 0.0
	rig.position.y = -action_pivot.position.y
	var side_progress := lerpf(stage.get("from_side", 0.0), stage.get("to_side", 0.0), progress)
	var rope_offset := ROPE_DISPLAY_Y if stage.get("rope", false) else 0.0
	# 正式 Player 会随绳侧下移；这里仅模拟位移并抬高展示线，不能把补偿只写在 Orientation。
	visual_anchor.position.y += rope_offset + PLAYER_HEIGHT_PIXELS * (side_progress if flipping else (1.0 if hanging else 0.0))
	rope_line.position.y = rope_offset
	action_pivot.rotation = PI * sin(PI * side_progress) if flipping else (TAU * progress if tucked else 0.0)
	rope_line.visible = stage.get("rope", false)


func _refresh_status() -> void:
	var stage := STAGES[stage_index]
	status.text = "%s　｜　%d/%d　%s　(%s)" % ["已暂停" if paused else "自动连续播放", stage_index + 1, STAGES.size(), stage["label"], stage["action"]]
