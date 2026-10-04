extends SceneTree

const Library := preload("res://patterns/pattern_library.gd")
const Section := preload("res://patterns/pattern_section.gd")
const Player := preload("res://player.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var requested := OS.get_cmdline_user_args()
	for index in Library.NAMES.size():
		if not requested.is_empty() and not Library.NAMES[index].begins_with(requested[0]):
			continue
		var world := Node2D.new()
		root.add_child(world)
		var player: Variant = Player.instantiate()
		world.add_child(player)
		player.reset_run(Vector2(140, 460))
		var section := Section.new()
		section.position = Vector2(140, 460)
		world.add_child(section)
		var data := Library.load_pattern(index)
		var entries: Array[Resource] = [data, RecoverySection.new()]
		section.build(entries, player, data.difficulty, 0)
		section.add_ground(-500, 500)
		var runner := section.runners[0]
		if not runner.plan.issues.is_empty():
			failures.append(data.pattern_name + ": " + str(runner.plan.issues))
		for frame in int(runner.plan.duration * 60) + 3:
			await physics_frame
			section.advance(1.0 / 60.0, player)
			await process_frame
		if runner.spawned_count != runner.plan.events.size():
			failures.append(data.pattern_name + ": missing spawned events")
		print("RAN %s: events=%d health=%.0f (smoke only; manual playtest required)" % [data.pattern_name, runner.spawned_count, player.health])
		world.free()
		await process_frame
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Pattern smoke passed")
	quit(0 if failures.is_empty() else 1)
