extends SceneTree

const TestScene := preload("res://patterns/test/PatternTest.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var test: Node2D = TestScene.instantiate()
	test.enable_runtime_bridge = false
	root.add_child(test)
	current_scene = test
	check_custom_event(test)
	for index in 12:
		test.select_pattern(index)
		await process_frame
		check(test.get_test_status().issues.is_empty(), "test selection rejected")
		check(test.section.runners.size() == 1, "old runners leaked")
		for frame in 45:
			await physics_frame
			await process_frame
		check(test.section.runners[0].spawned_count > 0, "no first event")
		var old_section: Node2D = test.section
		test.finish_test("pause before restart")
		test.restart_pattern()
		await process_frame
		check(not paused and not test.stopped, "restart did not resume")
		check(not is_instance_valid(old_section), "restart kept previous section")
		check(test.player.health == test.player.MAX_HP, "restart did not reset health")
		test.modifier = PatternModifier.Kind.DOUBLE
		test.restart_pattern()
		check(test.section.runners[0].plan.recoveries.size() > 0, "DOUBLE missing recovery")
		test.modifier = PatternModifier.Kind.NORMAL
	test.queue_free()
	await process_frame
	check(get_nodes_in_group("hazard").is_empty(), "obstacles survived teardown")
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Pattern test regression passed: 12 selections, pause/restart, DOUBLE, teardown")
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func check_custom_event(test: Node2D) -> void:
	var prototype := Node2D.new()
	var scene := PackedScene.new()
	scene.pack(prototype)
	prototype.free()
	var event := PatternEvent.new()
	event.obstacle_scene = scene
	event.position_offset = Vector2(600, -100)
	event.speed = 100
	event.direction = Vector2.LEFT
	var data := ObstaclePatternData.new()
	data.start_delay = 0
	data.events.append(event)
	var runner := PatternRunner.new()
	test.add_child(runner)
	runner.configure(PatternCompiler.compile(data, 3, 0, RecoverySection.new()), test.player)
	runner.advance(0.1)
	check(runner.get_child_count() == 1, "CUSTOM did not spawn new scene")
	check(is_equal_approx(runner.get_child(0).position.x, 590), "generic scene did not move")
	check(data.events[0].position_offset.x == 600, "CUSTOM source event mutated")
	runner.free()
