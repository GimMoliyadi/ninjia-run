extends Node2D

const STRIDE_LENGTH := 160.0
const MAX_RUN_ANIMATION_SPEED := 1.4
const ANIMATION_BLEND_TIME := 0.05
const MOVING_SPEED_THRESHOLD := 1.0
@export var show_run_bones := false
@export var hide_run_effects := false
@export_storage var visual_enabled := true
@onready var player: Variant = get_parent()
@onready var orientation: Node2D = $Orientation
@onready var action_pivot: Node2D = $Orientation/ActionPivot
@onready var body: Node2D = $Orientation/ActionPivot/Body
@onready var run_skeleton: Skeleton2D = $Orientation/ActionPivot/Body/VisualRoot_V1/RunSkeleton
@onready var run_animation: AnimationPlayer = $Orientation/ActionPivot/Body/VisualRoot_V1/RunSkeleton/AnimationPlayer
@onready var scarf: Line2D = $Orientation/ActionPivot/Body/Neck/Scarf
@onready var ghosts: Node2D = $GhostSpawner
@onready var dust: CPUParticles2D = $RunDust
var phase := 0.0
var visual_animation: StringName = &""
var jump_start_pending := false
var land_pending := false

func _ready() -> void:
	player.jumped.connect(on_jump)
	player.landed.connect(on_land)
	player.run_reset.connect(reset_visual)
	run_animation.animation_finished.connect(on_animation_finished)
	body.skeleton_pose = true
	update_pose(0.0)

func _process(delta: float) -> void:
	update_pose(delta)

func set_visual_enabled(enabled: bool) -> void:
	visual_enabled = enabled
	visible = enabled
	process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if enabled:
		reset_visual()
	else:
		run_animation.stop(true)
		visual_animation = &""
		jump_start_pending = false
		land_pending = false
		dust.emitting = false
		ghosts.clear_ghosts()

func update_pose(delta: float) -> void:
	if not visual_enabled:
		return
	var flipping: bool = player.is_rope_flipping()
	var hanging: bool = player.movement_state == player.MovementState.ROPE and player.rope_side == player.RopeSide.BOTTOM
	orientation.position.y = -player.PLAYER_HEIGHT * player.rope_flip_progress if flipping else (-player.PLAYER_HEIGHT if hanging else 0.0)
	orientation.rotation = 0.0
	var side_sign := -1.0 if hanging else 1.0
	orientation.scale.y = 1.0 if flipping else (side_sign if player.movement_state == player.MovementState.ROPE else 1.0)
	if player.active and player.movement_state == player.MovementState.GROUNDED:
		phase += absf(player.velocity.x) * delta * TAU / STRIDE_LENGTH
	update_action_pose(flipping)
	dust.emitting = player.active and player.movement_state == player.MovementState.GROUNDED and absf(player.velocity.x) > MOVING_SPEED_THRESHOLD and not hide_run_effects
	body.modulate = Color(1, 1, 1, 0.5 if player.invulnerability_remaining > 0.0 and sin(phase * 3.0) > 0.0 else 1.0)

func update_action_pose(flipping: bool) -> void:
	var tucked: bool = player.roll_hitbox_active
	var rolling: bool = player.air_state == player.AirState.DOUBLE_JUMP_ROLL
	action_pivot.position.y = -player.ROLL_HEIGHT / 2.0 if tucked else 0.0
	body.position.y = -action_pivot.position.y
	# 二段跳与绳索翻转沿用原支点和转角，动画只控制骨骼姿态。
	action_pivot.rotation = player.rope_flip_angle if flipping else (TAU * (1.0 - player.roll_remaining / player.DOUBLE_JUMP_ROLL_DURATION) if rolling else 0.0)
	play_visual_animation(select_visual_animation(flipping))
	var mode := "double_jump_roll" if tucked else ("slide" if player.is_sliding() else ("air" if player.movement_state == player.MovementState.AIRBORNE else ("run" if visual_animation == &"run" else "idle")))
	body.set_pose(phase, mode, player.velocity.y > 0.0)
	run_skeleton.visible = true
	run_skeleton.get_node("BoneDebug").visible = show_run_bones
	scarf.visible = false
	ghosts.suppress_run_effects = hide_run_effects
	body.get_node("Sword").visible = not tucked and body.is_attacking()

func select_visual_animation(flipping: bool) -> StringName:
	if not player.active:
		jump_start_pending = false
		land_pending = false
		return &"idle"
	if player.is_sliding():
		jump_start_pending = false
		land_pending = false
		return &"slide"
	if flipping or player.air_state == player.AirState.DOUBLE_JUMP_ROLL:
		jump_start_pending = false
		land_pending = false
		return &"double_jump"
	if player.movement_state == player.MovementState.AIRBORNE:
		land_pending = false
		if player.velocity.y >= 0.0:
			jump_start_pending = false
			return &"fall"
		return &"jump_start" if jump_start_pending else &"jump_up"
	jump_start_pending = false
	if player.movement_state == player.MovementState.ROPE:
		land_pending = false
	if land_pending:
		return &"land"
	return &"run" if absf(player.velocity.x) > MOVING_SPEED_THRESHOLD else &"idle"

func play_visual_animation(animation_name: StringName) -> void:
	run_animation.speed_scale = clampf(absf(player.velocity.x) / player.RUN_SPEED, 1.0, MAX_RUN_ANIMATION_SPEED) if animation_name == &"run" else 1.0
	if visual_animation == animation_name:
		return
	visual_animation = animation_name
	run_animation.play(animation_name, ANIMATION_BLEND_TIME)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_F7:
		show_run_bones = not show_run_bones
	elif event.keycode == KEY_F8:
		hide_run_effects = not hide_run_effects
		ghosts.clear_ghosts()

func on_jump(jump_index: int) -> void:
	if not visual_enabled:
		return
	jump_start_pending = jump_index == 1
	land_pending = false
	# 重播时保留当前骨骼姿态作为混合起点，避免先重置到动画首帧。
	visual_animation = &""
	run_animation.stop(true)
	update_pose(0.0)

func on_land(_speed: float) -> void:
	if not visual_enabled:
		return
	# landed 信号早于本物理帧状态结算；到绘制帧再决定落地、滑铲或缓冲起跳。
	land_pending = true
	jump_start_pending = false

func on_animation_finished(animation_name: StringName) -> void:
	if not visual_enabled or animation_name != visual_animation:
		return
	if animation_name == &"jump_start":
		jump_start_pending = false
	elif animation_name == &"land":
		land_pending = false

func reset_visual() -> void:
	if not visual_enabled:
		return
	body.scale = Vector2.ONE
	phase = 0.0
	visual_animation = &""
	run_animation.stop()
	jump_start_pending = false
	land_pending = false
	ghosts.clear_ghosts()
	dust.emitting = false
	dust.restart()
	update_pose(0.0)
	scarf.reset_chain()
