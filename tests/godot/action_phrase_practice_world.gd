extends "res://game.gd"

class PracticeRoute extends RefCounted:
	const Kinds := preload("res://components/rhythm_route_generator.gd")
	const ChunkKind = Kinds.ChunkKind
	const GROUP_COUNT := 3
	const ENCOUNTERS_PER_GROUP := 3
	const ACTION_COMBINATIONS: Array[int] = [
		ChunkKind.JUMP_SLIDE_PHRASE,
		ChunkKind.SLIDE_PLATFORM_PHRASE,
		ChunkKind.DART_JUMP_SLIDE_PHRASE,
	]

	var base_seed: int

	func _init(seed: int) -> void:
		base_seed = seed

	func build_cycle(cycle_index: int) -> Array[int]:
		var random := RandomNumberGenerator.new()
		random.seed = base_seed + cycle_index
		var route: Array[int] = [ChunkKind.SAFE]
		var previous := -1
		for _group in GROUP_COUNT:
			var choices: Array[int] = ACTION_COMBINATIONS.duplicate()
			for _encounter in ENCOUNTERS_PER_GROUP:
				var candidates := choices.filter(func(kind: int) -> bool: return kind != previous)
				var selected: int = candidates[random.randi_range(0, candidates.size() - 1)]
				choices.erase(selected)
				route.append(selected)
				route.append(ChunkKind.SHORT_RECOVERY)
				previous = selected
		route.append(ChunkKind.FINISH)
		return route

func reset_route_generator() -> void:
	super.reset_route_generator()
	# 仅替换练习路线，继续使用真实世界的跨圈、生成、回收和重开逻辑。
	route_generator = PracticeRoute.new(route_generator.base_seed)
