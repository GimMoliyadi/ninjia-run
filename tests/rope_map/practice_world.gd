extends "res://game.gd"

func reset_route_generator() -> void:
	super.reset_route_generator()
	route_steps.assign([
		ROUTE_GENERATOR_SCRIPT.ChunkKind.SAFE,
		ROUTE_GENERATOR_SCRIPT.ChunkKind.ROPE_MAP,
		ROUTE_GENERATOR_SCRIPT.ChunkKind.FINISH,
	])
