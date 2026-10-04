@tool
extends Node2D

const MOVING_SPEED_THRESHOLD := 1.0
const POSE_PROCESS_PRIORITY := -20
const ANIMATION_PROCESS_PRIORITY := -10

@export_storage var visual_enabled := true

@onready var player: Variant = get_parent()
@onready var orientation: Node2D = $Orientation
@onready var action_pivot: Node2D = $Orientation/ActionPivot
@onready var rig: Node2D = $Orientation/ActionPivot/VisualRoot_V2
@onready var animation_player: AnimationPlayer = $Orientation/ActionPivot/VisualRoot_V2/AnimationPlayer
@onready var ghosts: Node2D = $GhostSpawner_V2

var visual_animation: StringName = &""
var jump_start_pending := false
var land_pending := false
var jump_replay_requested := false
var land_replay_requested := false


func _ready() -> void:
	if Engine.is_editor_hint():
		visible = visual_enabled
		set_process(false)
		return
	# 先选动作，再应用动画混合/鞋底修正，最后由残影节点冻结最终绘制姿势。
	process_priority = POSE_PROCESS_PRIORITY
	animation_player.process_priority = ANIMATION_PROCESS_PRIORITY
	set_visual_enabled(visual_enabled)


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and is_instance_valid(player):
		_disconnect_signals()


func _process(_delta: float) -> void:
	update_pose()


func set_visual_enabled(enabled: bool) -> void:
	visual_enabled = enabled
	visible = enabled
	process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if Engine.is_editor_hint():
		return
	rig.set_action_mode(enabled)
	if enabled:
		_connect_signals()
		update_pose()
	else:
		ghosts.clear_ghosts()
		_disconnect_signals()
		visual_animation = &""
		_clear_jump()
		_clear_land()


func _connect_signals() -> void:
	for signal_name in [&"jumped", &"landed", &"run_reset", &"died"]:
		var callback := _player_signal_callback(signal_name)
		if player.has_signal(signal_name) and not player.is_connected(signal_name, callback):
			player.connect(signal_name, callback)
	if not animation_player.animation_finished.is_connected(on_animation_finished):
		animation_player.animation_finished.connect(on_animation_finished)


func _disconnect_signals() -> void:
	for signal_name in [&"jumped", &"landed", &"run_reset", &"died"]:
		var callback := _player_signal_callback(signal_name)
		if player.has_signal(signal_name) and player.is_connected(signal_name, callback):
			player.disconnect(signal_name, callback)
	if animation_player.animation_finished.is_connected(on_animation_finished):
		animation_player.animation_finished.disconnect(on_animation_finished)


func _player_signal_callback(signal_name: StringName) -> Callable:
	match signal_name:
		&"jumped":
			return on_jump
		&"landed":
			return on_land
		&"died":
			return ghosts.clear_ghosts
		_:
			return reset_visual


func update_pose() -> void:
	if not visual_enabled or Engine.is_editor_hint():
		return
	if not player.has_method("is_rope_flipping") or not player.has_method("is_sliding"):
		return
	var flipping: bool = player.is_rope_flipping()
	var hanging: bool = player.movement_state == player.MovementState.ROPE and player.rope_side == player.RopeSide.BOTTOM
	orientation.position.y = -player.PLAYER_HEIGHT * player.rope_flip_progress if flipping else (-player.PLAYER_HEIGHT if hanging else 0.0)
	orientation.rotation = 0.0
	orientation.scale.y = 1.0 if flipping or not hanging else -1.0
	_update_action_pivot(flipping)
	var action := select_visual_animation(flipping)
	var speed: float = absf(player.velocity.x) / player.RUN_SPEED if action == &"run" else 1.0
	var replay := (action == &"jump_start" and jump_replay_requested) or (action == &"land" and land_replay_requested)
	if action == &"jump_start":
		jump_replay_requested = false
	elif action == &"land":
		land_replay_requested = false
	rig.play_action(action, speed, replay)
	visual_animation = action


func _update_action_pivot(flipping: bool) -> void:
	var rolling: bool = player.air_state == player.AirState.DOUBLE_JUMP_ROLL
	# 支点与反向平移都在游戏像素空间，素材根节点的 0.055 缩放不参与计算。
	action_pivot.position.y = -player.ROLL_HEIGHT / 2.0 if player.roll_hitbox_active else 0.0
	rig.position.y = -action_pivot.position.y
	action_pivot.rotation = player.rope_flip_angle if flipping else (TAU * (1.0 - player.roll_remaining / player.DOUBLE_JUMP_ROLL_DURATION) if rolling else 0.0)


func select_visual_animation(flipping: bool) -> StringName:
	if not player.active:
		_clear_jump()
		_clear_land()
		return &"idle"
	if player.is_sliding():
		_clear_jump()
		_clear_land()
		return &"slide"
	if flipping or player.air_state == player.AirState.DOUBLE_JUMP_ROLL:
		_clear_jump()
		_clear_land()
		return &"double_jump"
	if player.movement_state == player.MovementState.AIRBORNE:
		_clear_land()
		if player.velocity.y >= 0.0:
			_clear_jump()
			return &"fall"
		return &"jump_start" if jump_start_pending else &"jump_up"
	_clear_jump()
	if player.movement_state != player.MovementState.GROUNDED:
		_clear_land()
	if land_pending:
		return &"land"
	return &"run" if absf(player.velocity.x) > MOVING_SPEED_THRESHOLD else &"idle"


func on_jump(jump_index: int) -> void:
	if not visual_enabled or Engine.is_editor_hint():
		return
	jump_start_pending = jump_index == 1
	jump_replay_requested = jump_start_pending
	_clear_land()


func on_land(_speed: float) -> void:
	if not visual_enabled or Engine.is_editor_hint():
		return
	# landed 早于本物理帧最终结算，绘制帧再判断缓冲跳跃、滑铲或真正落地。
	land_pending = true
	land_replay_requested = true
	_clear_jump()


func on_animation_finished(animation_name: StringName) -> void:
	if not visual_enabled or Engine.is_editor_hint() or animation_name != visual_animation:
		return
	if animation_name == &"jump_start" and not jump_replay_requested:
		_clear_jump()
	elif animation_name == &"land" and not land_replay_requested:
		_clear_land()


func _clear_jump() -> void:
	jump_start_pending = false
	jump_replay_requested = false


func _clear_land() -> void:
	land_pending = false
	land_replay_requested = false


func reset_visual() -> void:
	if not visual_enabled or Engine.is_editor_hint():
		return
	ghosts.clear_ghosts()
	_clear_jump()
	_clear_land()
	visual_animation = &""
	orientation.position = Vector2.ZERO
	orientation.rotation = 0.0
	orientation.scale = Vector2.ONE
	action_pivot.position = Vector2.ZERO
	action_pivot.rotation = 0.0
	rig.position = Vector2.ZERO
	rig.reset_actions()
	update_pose()
