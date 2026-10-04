extends Node2D

const IMPACT_TIME := 0.08
const RECOVERY_TIME := 0.16
const STRIDE_LENGTH := 160.0
const MAX_RUN_ANIMATION_SPEED := 1.4
@onready var player: Variant = get_parent()
@onready var orientation: Node2D = $Orientation
@onready var action_pivot: Node2D = $Orientation/ActionPivot
@onready var body: Node2D = $Orientation/ActionPivot/Body
@onready var run_skeleton: Skeleton2D = $Orientation/ActionPivot/Body/RunSkeleton
@onready var run_animation: AnimationPlayer = $Orientation/ActionPivot/Body/RunSkeleton/AnimationPlayer
@onready var scarf: Line2D = $Orientation/ActionPivot/Body/Neck/Scarf
@onready var ghosts: Node2D = $GhostSpawner
@onready var dust: CPUParticles2D = $RunDust
var phase := 0.0
var impact: Tween

func _ready() -> void:
	player.state_changed.connect(on_state_changed)
	player.jumped.connect(on_jump)
	player.landed.connect(on_land)
	player.run_reset.connect(reset_visual)
	update_pose(0.0)

func _process(delta: float) -> void:
	update_pose(delta)

func update_pose(delta: float) -> void:
	var flipping: bool = player.is_rope_flipping()
	var hanging: bool = player.movement_state == player.MovementState.ROPE and player.rope_side == player.RopeSide.BOTTOM
	orientation.position.y = -player.PLAYER_HEIGHT * player.rope_flip_progress if flipping else (-player.PLAYER_HEIGHT if hanging else 0.0)
	orientation.rotation = 0.0
	var side_sign := -1.0 if hanging else 1.0
	orientation.scale.y = 1.0 if flipping else (side_sign if player.movement_state == player.MovementState.ROPE else 1.0)
	var sliding: bool = player.movement_state == player.MovementState.SLIDE
	var airborne: bool = player.movement_state == player.MovementState.AIRBORNE
	if player.active and player.movement_state == player.MovementState.GROUNDED:
		phase += absf(player.velocity.x) * delta * TAU / STRIDE_LENGTH
	update_action_pose(sliding, airborne, flipping)
	dust.emitting = player.active and player.movement_state == player.MovementState.GROUNDED and absf(player.velocity.x) > 1.0
	body.modulate = Color(1, 1, 1, 0.5 if player.invulnerability_remaining > 0.0 and sin(phase * 3.0) > 0.0 else 1.0)

func on_state_changed(_previous: int, current: int) -> void:
	if current == player.MovementState.SLIDE or current == player.MovementState.ROPE:
		if impact:
			impact.kill()
		body.scale = Vector2.ONE

func update_action_pose(sliding: bool, airborne: bool, flipping: bool) -> void:
	var tucked: bool = player.roll_hitbox_active
	var rolling: bool = player.air_state == player.AirState.DOUBLE_JUMP_ROLL
	action_pivot.position.y = -player.ROLL_HEIGHT / 2.0 if tucked else 0.0
	body.position.y = -action_pivot.position.y
	action_pivot.rotation = player.rope_flip_angle if flipping else (TAU * (1.0 - player.roll_remaining / player.DOUBLE_JUMP_ROLL_DURATION) if rolling else 0.0)
	var mode := "double_jump_roll" if tucked else ("slide" if sliding else ("air" if airborne else ("run" if player.active and absf(player.velocity.x) > 1.0 else "idle")))
	body.set_pose(phase, mode, player.velocity.y > 0.0)
	var running: bool = mode == "run" and player.active
	var attacking: bool = body.is_attacking()
	run_skeleton.visible = running
	if running:
		run_animation.speed_scale = clampf(absf(player.velocity.x) / player.RUN_SPEED, 1.0, MAX_RUN_ANIMATION_SPEED)
		if run_animation.current_animation != "run":
			run_animation.play("run")
	else:
		run_animation.stop()
	body.get_node("Sword").visible = not tucked and attacking

func on_jump(jump_index: int) -> void:
	if jump_index == 1:
		pulse(Vector2(0.7, 1.35))
	else:
		if impact:
			impact.kill()
		body.scale = Vector2.ONE
	update_pose(0.0)

func on_land(_speed: float) -> void:
	if not player.roll_hitbox_active:
		pulse(Vector2(1.3, 0.7))

func pulse(peak: Vector2) -> void:
	if impact:
		impact.kill()
	impact = create_tween()
	impact.tween_property(body, "scale", peak, IMPACT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	impact.tween_property(body, "scale", Vector2.ONE, RECOVERY_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func reset_visual() -> void:
	if impact:
		impact.kill()
	body.scale = Vector2.ONE
	phase = 0.0
	ghosts.clear_ghosts()
	dust.emitting = false
	dust.restart()
	update_pose(0.0)
	scarf.reset_chain()
