extends RefCounted

const Motion := preload("res://patterns/player_motion_profile.gd")
const HALF_BODY := Motion.BODY_SIZE.x * 0.5
const FOOT_MARGIN := 4.0
var player: Node2D
var obstacles: Array[Dictionary] = []
var held := ""
var boost_enabled := false
var boost_presses := 0
var crossing_pit := false

func configure(module: Node2D, target: Node2D) -> void:
	player = target
	for section in module.sections:
		for runner in section.runners:
			for event in runner.plan.events:
				if runner.plan.has("ninja_actions") and event.obstacle_scene.resource_path != "res://scenes/JumpPillar.tscn":
					continue
				obstacles.append({
					"x": runner.global_position.x + event.position_offset.x,
					"end": runner.global_position.x + event.position_offset.x + event.preview_size.x,
					"height": event.preview_size.y,
					"pillar": event.preview_kind == PatternEvent.PreviewKind.OTHER,
				})
	obstacles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.x < b.x)

func advance() -> void:
	release()
	var px: float = player.global_position.x
	var height: float = Motion.GROUND_Y - player.global_position.y
	if player.is_on_floor():
		crossing_pit = false
	var speed: float = maxf(Motion.RUN_SPEED, player.run_speed + player.boost_speed)
	var support: Dictionary = {}
	var next: Dictionary = {}
	for obstacle in obstacles:
		if obstacle.end + HALF_BODY < px:
			continue
		if obstacle.pillar and px >= obstacle.x - HALF_BODY and absf(height - obstacle.height) < 2.0 and player.is_on_floor():
			support = obstacle
			continue
		if obstacle.pillar and px >= obstacle.x + HALF_BODY and px < obstacle.end - HALF_BODY and height > obstacle.height + FOOT_MARGIN:
			if not player.is_on_floor() and player.velocity.y >= -120.0:
				press("slide")
				return
		if obstacle.pillar and height >= obstacle.height - 1.0 and px >= obstacle.x - HALF_BODY:
			return
		next = obstacle
		break
	if next.is_empty():
		return
	var time: float = (next.x - HALF_BODY - px) / speed
	if not support.is_empty() and next.pillar and next.x - support.end <= Motion.safe_double_jump_gap(next.height - support.height):
		if support.end - px <= Motion.BODY_SIZE.x and player.is_on_floor():
			press("jump")
			crossing_pit = true
		return
	var required: float = next.height + FOOT_MARGIN
	if player.is_on_floor():
		if boost_enabled and absf(height) < 2.0 and time > 0.85 and player.boost_speed < 1.0:
			press("slide")
			boost_presses += 1
			return
		var lead := 0.6 if required - height > Motion.jump_height() - 12.0 else 0.24
		if time <= lead:
			press("jump")
	elif player.jumps_used == 1 and (time < 0.35 or crossing_pit):
		var exit_time: float = (next.end + HALF_BODY - px) / speed
		var check_time := maxf(0.0, time) if next.pillar else maxf(0.0, exit_time)
		if predicted_height(check_time) < required and player.velocity.y >= -260.0:
			press("jump")

func predicted_height(time: float) -> float:
	var height: float = Motion.GROUND_Y - player.global_position.y
	var velocity: float = player.velocity.y
	var steps := maxi(1, int(ceil(time * 60.0)))
	var delta := time / steps
	for index in steps:
		velocity += (player.ASCENT_GRAVITY if velocity < 0.0 else player.FALL_GRAVITY) * delta
		height -= velocity * delta
	return maxf(0.0, height)

func press(action: String) -> void:
	if action == "slide" and player.fast_falling:
		return
	Input.action_press(action)
	held = action

func release() -> void:
	if not held.is_empty():
		Input.action_release(held)
		held = ""
