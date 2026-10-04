extends Node2D

const VisualRigV2 = preload("res://visuals/rig_v2/visual_rig_v2.gd")

@onready var _v1: Skeleton2D = $Stage/VisualRoot_V1
@onready var _v2: VisualRigV2 = $Stage/VisualRoot_V2
@onready var _animation_player: AnimationPlayer = $Stage/VisualRoot_V2/AnimationPlayer
@onready var _status: Label = $Status

var _show_v2 := true


func _ready() -> void:
	var legacy_animation: AnimationPlayer = _v1.get_node("AnimationPlayer")
	legacy_animation.play(&"idle")
	legacy_animation.seek(0.0, true)
	legacy_animation.pause()
	_refresh_visibility()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_8:
		_select_pose(event.keycode - KEY_1)
	elif event.keycode == KEY_LEFT:
		_select_pose(_v2.preview_pose - 1)
	elif event.keycode == KEY_RIGHT:
		_select_pose(_v2.preview_pose + 1)
	elif event.keycode == KEY_TAB:
		_show_v2 = not _show_v2
		_refresh_visibility()
	elif event.keycode == KEY_SPACE and _show_v2:
		_toggle_test_playback()
	else:
		return
	get_viewport().set_input_as_handled()


func _select_pose(index: int) -> void:
	_v2.preview_pose = index
	_refresh_status()


func _refresh_visibility() -> void:
	_v1.visible = not _show_v2
	_v2.visible = _show_v2
	if not _show_v2:
		_animation_player.pause()
	_refresh_status()


func _toggle_test_playback() -> void:
	if _animation_player.is_playing():
		_animation_player.pause()
	else:
		_animation_player.play(&"rig_test")
		if _animation_player.current_animation_position >= _animation_player.current_animation_length:
			_animation_player.seek(0.0, true)


func _refresh_status() -> void:
	var version := "V2：独立网格骨架" if _show_v2 else "V1：旧视觉备份"
	_status.text = "%s　｜　测试姿态：%s" % [version, VisualRigV2.POSE_NAMES[_v2.preview_pose]]
