extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var menu: Control = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu

	if menu.get_node_or_null("Player") != null or get_nodes_in_group("dart").size() > 0:
		printerr("首页加载时不应启动关卡。")
		quit(1)
		return

	var start_button: Button = menu.get_node("Center/Panel/Margin/Content/StartButton")
	start_button.pressed.emit()
	await process_frame
	await process_frame

	if current_scene == null or current_scene.scene_file_path != "res://test_world.tscn":
		printerr("点击开始后未进入关卡。")
		quit(1)
		return

	print("Main menu regression passed: waiting on menu, then starting the game.")
	quit()
