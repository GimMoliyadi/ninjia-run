extends SceneTree
const PLAYER := preload("res://player.tscn")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var player: Variant = PLAYER.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var visual: Variant = player.get_node("PlayerVisual")
	visual.set_process(false)
	var scarf: Variant = visual.scarf
	scarf.set_process(false)
	check(scarf.points.size() == 20, "Scarf must have twenty points")
	check(is_equal_approx(scarf.width_curve.sample(1.0) * scarf.width, 1.0), "Tip must taper to one pixel")
	for fps in [30, 60, 120]:
		for direction in [1.0, -1.0]:
			player.velocity.x = 620.0 * direction
			for tick in fps:
				player.position.x += player.velocity.x / fps
				visual.body.rotation = TAU * tick / fps
				scarf._process(1.0 / fps)
				check(scarf.points[0].distance_to(scarf.get_parent().global_position) < 0.01, "Anchor lost during rotation")
				for index in range(1, scarf.points.size()):
					var gap: float = (scarf.points[index - 1].x - scarf.points[index].x) * direction
					check(gap > 0.0 and is_equal_approx(scarf.points[index - 1].distance_to(scarf.points[index]), scarf.WIND_SPACING), "Scarf curls forward or stretches during rotation")
			check(scarf.history.size() <= fps * 0.3 + 2, "Position history grows without bound")
	visual.body.rotation = 0.0
	player.velocity.x = 620.0
	for vertical_speed in [0.0, -500.0, 500.0]:
		scarf.reset_chain()
		for tick in 60:
			player.position += Vector2(620.0, vertical_speed) / 60.0
			scarf._process(1.0 / 60.0)
		var tail_offset: float = scarf.points[-1].y - scarf.points[0].y
		if vertical_speed == 0.0:
			check(absf(tail_offset) < 0.01, "Horizontal run introduced vertical waves")
		else:
			check(tail_offset * vertical_speed < 0.0, "Trail does not lag vertical trajectory")
	scarf.reset_chain()
	visual.body.position.y += 30.0
	scarf._process(1.0 / 60.0)
	check(scarf.points[-1].y < scarf.points[0].y, "Slide neck drop lost historical trajectory")
	player.reset_run(Vector2(5000, 460))
	check(scarf.history.size() == 1, "Teleport history did not clear")
	player.free()
	if failures == 0:
		print("Scarf passed: full rotation, both directions, bounded history at 30/60/120fps")
	quit(1 if failures else 0)
