extends SceneTree

const World := preload("res://test_world.tscn")
const SpikeScene := preload("res://scenes/Spike.tscn")
const OUTPUT := "res://tests/artifacts/"
var world: Node2D

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUTPUT + filename)
	if result != OK:
		printerr("Screenshot failed: ", filename)
		quit(1)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = World.instantiate()
	root.add_child(world)
	world.player.set_run_speed(0.0)
	await frames(3)
	await capture("full-health.png")
	world.player.take_damage(12)
	for index in 8:
		var target: Area2D = SpikeScene.instantiate()
		world.add_child(target)
		target.global_position = world.player.global_position + Vector2(420 + index * 100, 0)
	world.cast_weapon_skill()
	world.cast_ninjutsu()
	await frames(75)
	await capture("combat-damaged.png")
	world.player.heal(50)
	await frames(2)
	await capture("healed.png")
	world.combat.reset()
	world.player.global_position.x = 1600.0
	world.get_node("DynamicCamera").reset_camera()
	await frames(58)
	await capture("dart-wave.png")
	print("Rendered preview captured: full health, damage with abilities, healed, dart wave.")
	quit(0)
