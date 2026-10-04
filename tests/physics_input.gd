extends Node

var step: Callable

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 1

func _physics_process(_delta: float) -> void:
	step.call()
