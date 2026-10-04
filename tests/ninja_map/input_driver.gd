extends RefCounted

const Layout := preload("res://patterns/ninja_wave_layout.gd")
var player: Node2D
var actions: Array[Dictionary] = []
var index := 0
var held := ""
var jumps := 0
var slides := 0

func configure(module: Node2D, target: Node2D) -> void:
	player = target
	for section in module.sections:
		for runner in section.runners:
			for action in runner.plan.get("ninja_actions", []):
				var entry: Dictionary = action.duplicate()
				entry.x += runner.global_position.x
				actions.append(entry)

func advance() -> void:
	release()
	if index >= actions.size():
		return
	var action := actions[index]
	var lead := Layout.JUMP_LEAD
	if player.global_position.x < action.x - lead:
		return
	if not player.is_on_floor() and player.jumps_used != 1:
		return
	held = "jump"
	Input.action_press(held)
	jumps += int(held == "jump")
	slides += int(held == "slide")
	index += 1

func release() -> void:
	if not held.is_empty():
		Input.action_release(held)
		held = ""
