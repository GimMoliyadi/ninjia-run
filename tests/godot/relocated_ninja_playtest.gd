extends SceneTree

const World := preload("res://tests/jump_map/JumpMapPractice.tscn")
const Driver := preload("res://tests/ninja_map/input_driver.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var passed := true
	for wave_name in ["NinjaMap_Wave02_Alternation", "NinjaMap_Wave03_Pressure"]:
		passed = await play_wave(wave_name) and passed
	quit(0 if passed else 1)

func play_wave(wave_name: String) -> bool:
	var world := World.instantiate()
	root.add_child(world)
	current_scene = world
	var module: Node2D = world.active_chunks[1]
	var runner: Node2D
	for section in module.sections:
		for candidate in section.runners:
			if candidate.name == wave_name:
				runner = candidate
	if runner == null:
		printerr("未找到敌人 Wave: ", wave_name)
		world.free()
		return false
	var player: Node2D = world.player
	player.global_position = Vector2(runner.global_position.x + 8.0, Motion.GROUND_Y)
	world.arena_x = player.global_position.x
	var driver := Driver.new()
	driver.configure(module, player)
	while driver.index < driver.actions.size() and driver.actions[driver.index].x < player.global_position.x:
		driver.index += 1
	var first_action := driver.index
	var damage := 0
	player.damaged.connect(func(_amount: float) -> void: damage += 1)
	var input := preload("res://tests/physics_input.gd").new()
	input.step = driver.advance
	world.add_child(input)
	var wave_end: float = runner.global_position.x + float(runner.plan.length)
	for frame in Engine.physics_ticks_per_second * 16:
		await physics_frame
		if not player.active or player.global_position.x >= wave_end:
			break
	var passed: bool = player.active and player.global_position.x >= wave_end and damage == 0
	passed = passed and driver.index > first_action and runner.spawned_count == runner.plan.events.size()
	print("RELOCATED_NINJA %s passed=%s damage=%d spawned=%d/%d" % [wave_name, passed, damage, runner.spawned_count, runner.plan.events.size()])
	driver.release()
	world.free()
	return passed
