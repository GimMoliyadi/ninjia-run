extends SceneTree

func _initialize() -> void:
	call_deferred("probe")

func probe() -> void:
	var rig := preload("res://visuals/run_skeleton.tscn").instantiate()
	root.add_child(rig)
	var hip := rig.get_node("Hip") as Bone2D
	for property in hip.get_property_list():
		if "auto" in property.name or "length" in property.name:
			print(property.name, " = ", hip.get(property.name))
	var animation := rig.get_node("AnimationPlayer") as AnimationPlayer
	animation.play("run")
	for index in 32:
		animation.seek(index * 0.02, true)
		var soles: Array[float] = []
		for side in ["L", "R"]:
			var foot := rig.get_node("Hip/Thigh_%s/Shin_%s/Foot_%s/BootFoot" % [side,side,side]) as Polygon2D
			var bottom := -INF
			for vertex in foot.polygon:
				bottom = maxf(bottom, rig.to_local(foot.to_global(vertex)).y)
			soles.append(bottom)
		print(index, " hip=", hip.position, " soles=", soles)
	quit()
