extends RefCounted

const Motion := preload("res://patterns/player_motion_profile.gd")
var player: Node2D
var actions: Array[Dictionary] = []
var index := 0
var held := ""
var rope_frames := 0
var total_frames := 0
var flips := 0
var last_side := 0
var triggered_jumps := 0

func configure(module: Node2D, target: Node2D) -> void:
	player = target
	for section in module.sections:
		for runner in section.runners:
			for action in runner.plan.rope_actions:
				var located: Dictionary = action.duplicate()
				for key in ["x", "danger_start", "danger_end"]:
					located[key] += runner.global_position.x
				actions.append(located)

func advance() -> void:
	release()
	total_frames += 1
	if player.movement_state == player.MovementState.ROPE:
		rope_frames += 1
		if player.rope_side != last_side:
			flips += 1
		last_side = player.rope_side
	while index < actions.size() and player.global_position.x > actions[index].danger_end:
		index += 1
	if index >= actions.size() or player.movement_state != player.MovementState.ROPE or player.flip_remaining > 0.0:
		return
	var action := actions[index]
	var speed: float = player.run_speed + player.boost_speed
	var time: float = (action.x - player.global_position.x) / speed
	if action.kind == "jump":
		if player.rope_side == player.RopeSide.BOTTOM and time <= Motion.ROPE_JUMP_LEAD + Motion.rope_flip_window():
			press("jump")
		elif player.rope_side == player.RopeSide.TOP and not action.get("jumped", false) and time <= Motion.ROPE_JUMP_LEAD:
			press("jump")
			action["jumped"] = true
			triggered_jumps += 1
	elif player.rope_side != action.safe_side and time <= Motion.rope_flip_window() + Motion.BODY_SIZE.x / speed:
		press("slide" if action.safe_side == player.RopeSide.BOTTOM else "jump")

func press(action: String) -> void:
	Input.action_press(action)
	held = action

func release() -> void:
	if not held.is_empty():
		Input.action_release(held)
		held = ""
