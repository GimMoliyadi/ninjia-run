extends Node

const TRAJECTORY_LAYOUT: GDScript = preload("res://patterns/coin_trajectory_layout.gd")

@export var obstacle_paths: Array[NodePath] = []
@export var coin_paths: Array[NodePath] = []

func _ready() -> void:
	if obstacle_paths.is_empty() or coin_paths.is_empty():
		return
	var chunk: Node2D = get_parent() as Node2D
	var entry: Marker2D = chunk.get_node("Entry") as Marker2D
	var exit: Marker2D = chunk.get_node("Exit") as Marker2D
	var ground_offset: Vector2 = Vector2(0.0, entry.position.y)
	var bounds: Vector2 = Vector2(entry.position.x, exit.position.x)
	var trail: Array[Vector2] = TRAJECTORY_LAYOUT.obstacle_jump_trail(_merged_obstacles(ground_offset), bounds)
	var positions: Array[Vector2] = []
	if not trail.is_empty():
		var peak: Vector2 = trail[0]
		for point: Vector2 in trail:
			if point.y < peak.y:
				peak = point
		positions.assign([trail[0], peak, trail[-1]])
	for index: int in coin_paths.size():
		var coin: Node2D = get_node(coin_paths[index]) as Node2D
		if positions.is_empty():
			coin.hide()
			coin.queue_free()
		else:
			coin.position = positions[index] + ground_offset

func _merged_obstacles(ground_offset: Vector2) -> Rect2:
	var first: Spike = get_node(obstacle_paths[0]) as Spike
	var merged: Rect2 = Rect2(first.position - ground_offset - Vector2(0.0, first.size.y), first.size)
	for path: NodePath in obstacle_paths:
		var spike: Spike = get_node(path) as Spike
		var obstacle: Rect2 = Rect2(spike.position - ground_offset - Vector2(0.0, spike.size.y), spike.size)
		merged = merged.merge(obstacle)
	return merged
