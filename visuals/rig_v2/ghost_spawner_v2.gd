extends Node2D

const Snapshot = preload("res://visuals/rig_v2/ghost_snapshot_v2.gd")
const INTERVAL_SECONDS := 0.06
const MAX_LIVE_GHOSTS := 5
const SPEED_THRESHOLD := 1.1
const CAPTURE_PROCESS_PRIORITY := 20

var elapsed := 0.0
var ghost_count := 0

@onready var visual: Node2D = get_parent()
@onready var player: Variant = visual.get_parent()
@onready var source: Node2D = visual.get_node("Orientation/ActionPivot/VisualRoot_V2")

var emitting: bool:
	get:
		return not Engine.is_editor_hint() and visual.visual_enabled and player.has_method("is_sliding") and player.active and absf(player.velocity.x) > player.RUN_SPEED * SPEED_THRESHOLD


func _ready() -> void:
	process_priority = CAPTURE_PROCESS_PRIORITY
	if Engine.is_editor_hint():
		set_process(false)


func _exit_tree() -> void:
	clear_ghosts()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	for snapshot in get_children():
		if snapshot.advance_snapshot(delta):
			snapshot.free()
	if not emitting:
		elapsed = 0.0
		return
	elapsed += delta
	if elapsed >= INTERVAL_SECONDS:
		# 卡顿帧只捕获一次当前姿势，不补发重叠残影。
		elapsed = 0.0
		spawn_ghost()


func spawn_ghost() -> CanvasGroup:
	if not emitting or get_tree().paused:
		return null
	if get_child_count() >= MAX_LIVE_GHOSTS:
		get_child(0).free()
	var snapshot := Snapshot.new()
	snapshot.capture(source, player.velocity.x)
	add_child(snapshot)
	snapshot.global_transform = source.global_transform
	ghost_count += 1
	return snapshot


func clear_ghosts() -> void:
	elapsed = 0.0
	for snapshot in get_children():
		# died 的其他监听者可能立即暂停；这里同步销毁，不等下一帧或 Tween。
		snapshot.free()
