extends SceneTree


func _initialize() -> void:
	var scene := load("res://tests/player_skeleton_test/player_skeleton_test.tscn") as PackedScene
	assert(scene != null)
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame
	var player := root.get_node("AnimationPlayer") as AnimationPlayer
	assert(player.current_animation == "run")
	var run := player.get_animation("run")
	assert(run.loop_mode == Animation.LOOP_LINEAR)
	for index in run.get_track_count():
		assert(run.track_get_key_time(index, 0) == 0.0)
		assert(is_equal_approx(run.track_get_key_time(index, run.track_get_key_count(index) - 1), run.length))
		assert(run.track_get_key_value(index, 0) == run.track_get_key_value(index, run.track_get_key_count(index) - 1))
	player.seek(0.15, true)
	assert(root.get_node("Skeleton/Hip/FrontThigh").rotation != root.get_node("Skeleton/Hip/RearThigh").rotation)
	assert(root.get_node("Skeleton/Hip/FrontThigh/FrontShin").rotation != root.get_node("Skeleton/Hip/RearThigh/RearShin").rotation)
	print("Skeleton run scene verified")
	quit()
