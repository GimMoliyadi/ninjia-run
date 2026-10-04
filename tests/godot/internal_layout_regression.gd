extends SceneTree

const MAPS := [
	{"scene": preload("res://scenes/segment_jump_map.tscn"), "section": 0},
	{"scene": preload("res://scenes/segment_rope_map.tscn"), "section": 1},
	{"scene": preload("res://scenes/segment_platform_dart_map.tscn"), "section": 1},
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for map in MAPS:
		var orders := {}
		for seed in range(1, 13):
			var chunk: MapModuleChunk = map.scene.instantiate()
			chunk.layout_seed = seed
			root.add_child(chunk)
			var section: PatternSection = chunk.sections[map.section]
			if not chunk.debug_info().issues.is_empty():
				printerr("随机障碍编译失败：", chunk.name, " seed=", seed)
				quit(1)
				return
			var first: String = section.runners[0].name
			var second: String = section.runners[1].name
			orders[first + "," + second] = true
			var authored: PatternSectionData = chunk.module_data.sections[map.section]
			var authored_index: int = authored.entries.find(section.data.entries[0])
			if authored_index < 0 or section.pattern_info[0].stage != authored.stages[authored_index]:
				printerr("重排后的阶段名称与障碍不一致：", chunk.name)
				quit(1)
				return
			chunk.free()
		if orders.size() < 2:
			printerr("障碍顺序没有随种子变化：", map.scene.resource_path)
			quit(1)
			return
	var heights := {}
	for seed in range(1, 13):
		var chunk: MapModuleChunk = MAPS[0].scene.instantiate()
		chunk.layout_seed = seed
		root.add_child(chunk)
		for child in chunk.sections[0].get_children():
			if child is Coin:
				heights[child.position.y] = true
		chunk.free()
	if heights.size() < 2:
		printerr("金币轨迹没有随种子变化")
		quit(1)
		return
	print("Internal layout regression passed: three maps change obstacle order and coin heights vary")
	quit(0)
