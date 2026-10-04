extends Node2D

const BODY_SCRIPT := preload("res://visuals/ninja_body.gd")
const RUN_SCENE := preload("res://visuals/run_skeleton.tscn")
const INTERVAL := 0.04
const LIFETIME := 0.25
const RUN_DEBUG_OPACITY := 0.08
const SPEED_THRESHOLD := 1.1
const CYAN := Color(0.12, 0.7, 0.75)
const GOLD := Color(0.85, 0.65, 0.25)
var ghost_count := 0
var suppress_run_effects := false
@onready var player: Variant = get_node("../..")
var emitting: bool:
	get:
		return player.active and absf(player.velocity.x) > player.RUN_SPEED * SPEED_THRESHOLD and not (suppress_run_effects and source.pose_mode == "run")
var elapsed := 0.0
@onready var source: Node2D = $"../Orientation/ActionPivot/Body"
@onready var source_animation: AnimationPlayer = $"../Orientation/ActionPivot/Body/VisualRoot_V1/RunSkeleton/AnimationPlayer"

func _process(delta: float) -> void:
	if not emitting:
		elapsed = 0.0
		return
	elapsed += delta
	if elapsed >= INTERVAL:
		elapsed = fmod(elapsed, INTERVAL)
		spawn_ghost()

func spawn_ghost() -> void:
	var running: bool = source.pose_mode == "run"
	if running and suppress_run_effects:
		return
	var ghost: Node2D = RUN_SCENE.instantiate() if running else Node2D.new()
	if not running:
		ghost.set_script(BODY_SCRIPT)
		ghost.ink_color = CYAN if ghost_count % 2 == 0 else GOLD
	ghost_count += 1
	if not running:
		ghost.phase = source.phase
		ghost.pose_mode = source.pose_mode
		ghost.falling = source.falling
	else:
		ghost.visible = true
	ghost.top_level = true
	ghost.z_index = -1
	add_child(ghost)
	ghost.global_transform = source.global_transform
	if running:
		var animation := ghost.get_node("AnimationPlayer") as AnimationPlayer
		animation.play("run")
		animation.seek(source_animation.current_animation_position, true)
		animation.pause()
	ghost.modulate = Color(CYAN if ghost_count % 2 == 1 else GOLD, RUN_DEBUG_OPACITY) if running else Color(1, 1, 1, 0.6)
	var fade := ghost.create_tween()
	fade.tween_property(ghost, "modulate:a", 0.0, LIFETIME)
	fade.tween_callback(ghost.queue_free)

func clear_ghosts() -> void:
	elapsed = 0.0
	for ghost in get_children():
		ghost.queue_free()
