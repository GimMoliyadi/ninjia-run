extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var preview: Node2D = load("res://tests/cultivator_run_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://tests/artifacts/cultivator-run/eight-poses.png")
	print("Pose capture saved: ", result)
	for rig in preview.rigs:
		rig.get_node("BoneDebug").visible = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/cultivator-run/eight-poses-bones.png")
	quit(result)
