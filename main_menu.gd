extends Control


func _ready() -> void:
	$Center/Panel/Margin/Content/StartButton.grab_focus()


func _on_start_button_pressed() -> void:
	var error: Error = get_tree().change_scene_to_file("res://test_world.tscn")
	if error != OK:
		push_error("无法开始游戏：%s" % error_string(error))
