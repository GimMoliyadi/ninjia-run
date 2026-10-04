class_name PatternRunner
extends Node2D

signal event_spawned(event: PatternEvent, obstacle: Node2D)
signal finished
const Motion := preload("res://patterns/player_motion_profile.gd")
const MAX_OBSTACLES := 96
var plan: Dictionary
var player: Node2D
var elapsed := 0.0
var event_index := 0
var completed := false
var spawned_count := 0
var moving: Array[Node2D] = []
var linear_velocities: Dictionary = {}
var distance_started := false
var previous_player_position := Vector2.ZERO

func configure(compiled: Dictionary, target: Node2D) -> void:
	plan = compiled
	player = target
	if is_instance_valid(player):
		previous_player_position = player.global_position

func advance(delta: float) -> void:
	_advance_to(elapsed + delta)

func advance_distance(local_distance: float) -> void:
	var route_time := local_distance / Motion.RUN_SPEED
	if not distance_started:
		elapsed = minf(route_time, plan.events[0].spawn_time) if not plan.events.is_empty() else route_time
		previous_player_position = player.global_position
		distance_started = true
	_advance_to(route_time)

func _advance_to(next_elapsed: float) -> void:
	if completed or not plan.issues.is_empty():
		return
	var delta := maxf(0.0, next_elapsed - elapsed)
	elapsed = maxf(elapsed, next_elapsed)
	for index in range(moving.size() - 1, -1, -1):
		var obstacle = moving[index]
		if not is_instance_valid(obstacle) or obstacle.is_queued_for_deletion():
			moving.remove_at(index)
		else:
			_advance_obstacle(obstacle, delta)
	while event_index < plan.events.size() and plan.events[event_index].spawn_time <= elapsed:
		var event: PatternEvent = plan.events[event_index]
		var obstacle := spawn_event(event)
		if obstacle != null:
			var remaining := elapsed - event.spawn_time
			if "previous_player_position" in obstacle and delta > 0.0:
				var fraction := clampf(1.0 - remaining / delta, 0.0, 1.0)
				obstacle.set("previous_player_position", previous_player_position.lerp(player.global_position, fraction))
			_advance_obstacle(obstacle, remaining)
		event_index += 1
	if is_instance_valid(player):
		previous_player_position = player.global_position
	if elapsed >= plan.duration and event_index >= plan.events.size():
		var player_passed: bool = is_instance_valid(player) and player.global_position.x >= global_position.x + plan.length
		if not plan.get("distance_driven", false) or (moving.is_empty() and player_passed):
			finish()
	queue_redraw()

func _advance_obstacle(obstacle: Node2D, delta: float) -> void:
	if obstacle.has_method("advance"):
		obstacle.advance(delta, player)
	elif linear_velocities.has(obstacle.get_instance_id()):
		obstacle.position += linear_velocities[obstacle.get_instance_id()] * delta

func finish() -> void:
	if completed:
		return
	completed = true
	for obstacle in get_children():
		obstacle.queue_free()
	moving.clear()
	linear_velocities.clear()
	finished.emit()

func spawn_event(event: PatternEvent) -> Node2D:
	if get_child_count() >= MAX_OBSTACLES:
		push_error("Pattern obstacle limit exceeded")
		return null
	if player == null or not is_instance_valid(player):
		# Section 允许先于玩家存在，运行推进前必须补上玩家引用。
		push_error("PatternRunner: player 未绑定，无法生成障碍")
		return null
	var obstacle: Node2D = event.obstacle_scene.instantiate()
	for key in event.optional_parameters:
		if key not in obstacle:
			push_error("Unknown obstacle parameter: " + str(key))
			obstacle.free()
			return null
		obstacle.set(key, event.optional_parameters[key])
	if obstacle.has_signal("player_contact"):
		obstacle.connect("player_contact", on_player_contact)
	add_child(obstacle)
	obstacle.position = event.position_offset
	if "velocity" in obstacle:
		obstacle.set("velocity", event.direction.normalized() * event.speed)
	if obstacle.has_method("advance"):
		if "previous_player_position" in obstacle:
			obstacle.set("previous_player_position", player.global_position)
		moving.append(obstacle)
	elif event.speed > 0:
		linear_velocities[obstacle.get_instance_id()] = event.direction.normalized() * event.speed
		moving.append(obstacle)
	if obstacle.has_method("initialize"):
		obstacle.initialize(player)
	spawned_count += 1
	event_spawned.emit(event, obstacle)
	return obstacle

func on_player_contact(body: Node2D, damage: float) -> void:
	if body == player and player.active:
		player.take_damage(damage)

func _draw() -> void:
	if plan.is_empty() or completed or plan.get("distance_driven", false):
		return
	for index in range(event_index, plan.events.size()):
		var event: PatternEvent = plan.events[index]
		if event.spawn_time - elapsed <= 0.8:
			draw_arc(event.position_offset, 15.0, 0, TAU, 16, Color("d86634"), 2.0, true)
