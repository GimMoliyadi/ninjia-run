extends SceneTree

const Generator := preload("res://components/rhythm_route_generator.gd")
const MAP_POSITIONS := [1, 2, 3, 5, 6]
const REST_POSITIONS := [4, 8]
const CHALLENGE_POSITIONS := [7, 9, 10, 11]
const CYCLE_LENGTH := 13
const COMPLETE_MAPS: Array[int] = [
	Generator.ChunkKind.DARTS, Generator.ChunkKind.JUMP_MAP,
	Generator.ChunkKind.ROPE_MAP, Generator.ChunkKind.PLATFORM_DART_MAP,
	Generator.ChunkKind.NINJA_MAP,
]
const AUTHORED_CHALLENGES: Array[int] = [
	Generator.ChunkKind.SINGLE_JUMP, Generator.ChunkKind.DOUBLE_JUMP,
	Generator.ChunkKind.SLIDE_INTRO, Generator.ChunkKind.MIXED,
	Generator.ChunkKind.TRIPLE_JUMP, Generator.ChunkKind.SLALOM,
	Generator.ChunkKind.ROPE, Generator.ChunkKind.ROPE_SWITCH,
	Generator.ChunkKind.COMBO,
]


func _initialize() -> void:
	var orders := {}
	var openings := {}
	for seed in range(20260900, 20261000):
		var generator := Generator.new(seed)
		for cycle in 3:
			var route := generator.build_cycle(cycle)
			if route != generator.build_cycle(cycle):
				fail("同种子同圈的路线必须可复现")
				return
			var error := route_error(route)
			if not error.is_empty():
				fail("seed=%d cycle=%d：%s" % [seed, cycle, error])
				return
			orders[str(route)] = true
			openings[route[1]] = true
	if orders.size() < COMPLETE_MAPS.size() or openings.size() != COMPLETE_MAPS.size():
		fail("不同种子必须能够以全部五张完整地图开局")
		return
	print("完整路线回归通过：100 seeds × 3 cycles；每圈五图各一次、两段REST、四个旧挑战；%d种顺序" % orders.size())
	quit(0)


func route_error(route: Array[int]) -> String:
	if route.size() != CYCLE_LENGTH:
		return "正式路线必须恢复13段，不能仍循环短组合"
	if route.front() != Generator.ChunkKind.SAFE or route.back() != Generator.ChunkKind.FINISH:
		return "热身与收尾不正确"
	for position in REST_POSITIONS:
		if route[position] != Generator.ChunkKind.REST:
			return "完整地图组之间必须保留原REST恢复段"
	var seen := {}
	for position in MAP_POSITIONS:
		var kind := route[position]
		if kind not in COMPLETE_MAPS or seen.has(kind):
			return "五种完整地图必须各一次进入前两组"
		seen[kind] = true
	for position in CHALLENGE_POSITIONS:
		if route[position] not in AUTHORED_CHALLENGES:
			return "地图之后必须接原有跳跃、滑铲、绳索或综合挑战"
	if route.count(Generator.ChunkKind.REST) != REST_POSITIONS.size():
		return "不能用频繁短喘息稀释正式关卡"
	return ""


func fail(message: String) -> void:
	printerr(message)
	quit(1)
