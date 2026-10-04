extends Node2D

const RUN_SCENE := preload("res://visuals/run_skeleton.tscn")
const POSES := ["Contact R", "Down R", "Passing R", "Up R", "Contact L", "Down L", "Passing L", "Up L"]
var rigs: Array[Skeleton2D] = []
var paused := false

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("e7e1d2"))
	for index in 8:
		var rig := RUN_SCENE.instantiate() as Skeleton2D
		rig.position = Vector2(190 + (index % 4) * 300, 325 + (index / 4) * 350)
		rig.scale = Vector2.ONE * 3.3
		rig.visible = true
		add_child(rig)
		rigs.append(rig)
		var animation := rig.get_node("AnimationPlayer") as AnimationPlayer
		animation.play("run")
		animation.seek(index * 0.08, true)
		animation.pause()
		var label := Label.new()
		label.text = "%d  %s" % [index + 1, POSES[index]]
		label.position = Vector2(35 + (index % 4) * 300, 55 + (index / 4) * 350)
		label.add_theme_color_override("font_color", Color("294653"))
		label.add_theme_font_size_override("font_size", 22)
		add_child(label)
	paused = true
	var instructions := Label.new()
	instructions.text = "SPACE: play / hold eight reference poses     F7: bones     1-8: solo pose"
	instructions.position = Vector2(35, 15)
	instructions.add_theme_color_override("font_color", Color("294653"))
	add_child(instructions)
	queue_redraw()

func _draw() -> void:
	for row in 2:
		draw_line(Vector2(25,325 + row*350), Vector2(1220,325 + row*350), Color("b3a98f"), 1.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_SPACE:
		paused = not paused
		for index in rigs.size():
			var animation := rigs[index].get_node("AnimationPlayer") as AnimationPlayer
			if paused:
				animation.seek(index * 0.08, true)
				animation.pause()
			else:
				animation.play("run")
	elif event.keycode == KEY_F7:
		for rig in rigs:
			var bones := rig.get_node("BoneDebug") as Node2D
			bones.visible = not bones.visible
	elif event.keycode >= KEY_1 and event.keycode <= KEY_8:
		for rig in rigs:
			var animation := rig.get_node("AnimationPlayer") as AnimationPlayer
			animation.seek((event.keycode - KEY_1) * 0.08, true)
			animation.pause()
		paused = true
