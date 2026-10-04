extends SceneTree

const Generator := preload("res://components/rhythm_route_generator.gd")
const PlatformDriver := preload("res://tests/platform_dart_map/input_driver.gd")
const NinjaDriver := preload("res://tests/ninja_map/input_driver.gd")
const TerrainDriver := preload("res://tests/jump_map/input_driver.gd")
const MAX_FRAMES := 60 * 180
const EXIT_RUNOUT := 160.0
var world: Node2D
var driver: RefCounted
var enemy_driver := NinjaDriver.new()
var current_module: Node2D
var last_exit := INF
var modules_entered := 0
var damage := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var reverse := OS.get_cmdline_user_args().has("--reverse")
	var scene_path := "res://tests/ninja_map/NinjaMapPractice.tscn" if reverse else "res://tests/platform_dart_map/PlatformDartMapPractice.tscn"
	world = load(scene_path).instantiate()
	root.add_child(world)
	current_scene = world
	var maps := [Generator.ChunkKind.PLATFORM_DART_MAP, Generator.ChunkKind.NINJA_MAP]
	if reverse:
		maps.reverse()
	world.route_steps.assign([Generator.ChunkKind.SAFE, maps[0], maps[1], Generator.ChunkKind.FINISH])
	world.player.damaged.connect(func(_amount: float) -> void: damage += 1)
	var input := preload("res://tests/physics_input.gd").new()
	input.step = drive
	world.add_child(input)
	for frame in MAX_FRAMES:
		await physics_frame
		await process_frame
		if not world.player.active or world.player.global_position.x >= last_exit + EXIT_RUNOUT:
			break
	var completed: bool = modules_entered == 2 and world.player.active and world.player.global_position.x >= last_exit + EXIT_RUNOUT
	print("MAP_CHAIN reverse=%s modules=%d damage=%d complete=%s" % [reverse, modules_entered, damage, completed])
	if driver != null:
		driver.release()
	enemy_driver.release()
	world.free()
	quit(0 if completed and damage == 0 else 1)

func drive() -> void:
	for chunk in world.active_chunks:
		if not chunk is MapModuleChunk or chunk == current_module:
			continue
		if world.player.global_position.x >= chunk.get_node("Entry").global_position.x and world.player.global_position.x < chunk.get_node("Exit").global_position.x:
			if driver != null:
				driver.release()
			enemy_driver.release()
			current_module = chunk
			driver = PlatformDriver.new() if chunk.module_data.module_id == "Platform_Dart_Map_A" else TerrainDriver.new()
			driver.configure(chunk, world.player)
			enemy_driver = NinjaDriver.new()
			enemy_driver.configure(chunk, world.player)
			modules_entered += 1
			if modules_entered == 2:
				last_exit = chunk.get_node("Exit").global_position.x
	if driver != null:
		driver.advance()
		enemy_driver.advance()
