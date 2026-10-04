extends SceneTree

const WORLD_SCENE := preload("res://test_world.tscn")
const EXTRA_CHUNK_DISTANCE := 8000.0

func _initialize() -> void:
	var world: Variant = WORLD_SCENE.instantiate()
	world.route_seed = 20260909
	root.add_child(world)
	await physics_frame
	var initial_frontier: float = world.next_chunk_entry.x
	world.spawn_chunks_ahead(initial_frontier + EXTRA_CHUNK_DISTANCE)
	if world.next_chunk_entry.x < initial_frontier + EXTRA_CHUNK_DISTANCE:
		printerr("Chunk regression: chunks did not extend to the requested frontier.")
		quit(1)
		return
	if world.active_chunks.size() < 5:
		printerr("Chunk regression: infinite generation did not create enough scene instances.")
		quit(1)
		return
	for index in range(1, world.active_chunks.size()):
		var previous: Node2D = world.active_chunks[index - 1]
		var current: Node2D = world.active_chunks[index]
		if not previous.get_node("Exit").global_position.is_equal_approx(current.get_node("Entry").global_position):
			printerr("Chunk regression: entry and exit do not align.")
			quit(1)
			return
	var removed_chunk: Node2D = world.active_chunks.front()
	world.player.global_position.x = removed_chunk.get_node("Exit").global_position.x + 800.0
	world.cleanup_chunks()
	if world.active_chunks.has(removed_chunk) or not removed_chunk.is_queued_for_deletion():
		printerr("Chunk regression: passed chunks were not recycled.")
		quit(1)
		return
	print("Chunk regression passed: generated scene chunks extend and recycle across the infinite route.")
	quit(0)
