extends SceneTree

const WORLD := preload("res://test_world.tscn")
const Generator := preload("res://components/rhythm_route_generator.gd")
const ROUTE_SEED := 20260909

func _initialize() -> void:
	var world: Variant = WORLD.instantiate()
	world.route_seed = ROUTE_SEED
	root.add_child(world)
	await physics_frame
	var expected_route: Array[int] = Generator.new(ROUTE_SEED).build_cycle(0)
	for kind in Generator.ACTION_COMBINATIONS:
		if expected_route.count(kind) != Generator.GROUP_COUNT:
			printerr("动作组合库没有完整进入每组循环")
			quit(1)
			return
	while world.active_chunks.size() < expected_route.size():
		world.spawn_chunk()
	if not route_matches(world, expected_route):
		printerr("Generated route regression: the game did not instantiate the seeded first rhythm cycle.")
		quit(1)
		return

	world.restart_run()
	while world.active_chunks.size() < expected_route.size():
		world.spawn_chunk()
	if not route_matches(world, expected_route):
		printerr("Generated route regression: restarting with an explicit seed must reproduce the first cycle.")
		quit(1)
		return

	print("Generated route regression passed: the visible first cycle is procedural and seed-reproducible.")
	quit(0)

func route_matches(world: Node2D, expected_route: Array[int]) -> bool:
	if world.active_chunks.size() < expected_route.size():
		return false
	for index in expected_route.size():
		var expected_scene: PackedScene = world.CHUNK_SCENES[expected_route[index]]
		if world.active_chunks[index].scene_file_path != expected_scene.resource_path:
			printerr("Generated route regression: expected %s but found %s at chunk %d." % [expected_scene.resource_path, world.active_chunks[index].scene_file_path, index])
			return false
		var chunk: Node2D = world.active_chunks[index]
		if chunk is MapModuleChunk:
			if expected_route[index] == Generator.ChunkKind.SHORT_RECOVERY:
				if chunk.module_data.module_id != "Short_Recovery" or not chunk.debug_info().issues.is_empty():
					return false
				continue
			var descriptor := Generator.new(ROUTE_SEED).content_descriptor(expected_route[index])
			if chunk.module_data.module_id != descriptor.variant or not chunk.debug_info().issues.is_empty():
				printerr("Map library regression: module descriptor or compilation failed for ", descriptor.variant)
				return false
	return true
