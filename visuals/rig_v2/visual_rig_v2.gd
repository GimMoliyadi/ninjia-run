@tool
extends Node2D

const POSE_NAMES: PackedStringArray = [
	"中性", "躯干前倾", "胸腔微调", "单腿抬起", "明显屈膝", "脚踝与脚尖", "抬臂屈肘", "头部独立微调",
]
const POSE_INTERVAL_SECONDS := 1.0
const ACTION_BLEND_SECONDS := 0.05
const AlphaContour = preload("res://visuals/rig_v2/skinned_alpha_contour.gd")
const GROUNDED_ACTIONS: Array[StringName] = [&"idle", &"run", &"land", &"slide"]

var _soles: Array = []
var _replay_rotations: PackedFloat32Array = []
var _replay_com := Vector2.ZERO
var _bones: Array[Bone2D] = []
var _replay_blending := false
var _com: Bone2D

@onready var _near_arm: Polygon2D = $Skin/Arm_L
@onready var _near_hand: Sprite2D = $Skeleton2D.find_child("Hand_L", true, false).get_node("Hand_L")
@onready var _far_hand: Sprite2D = $Skeleton2D.find_child("Hand_R", true, false).get_node("Hand_R")
@onready var _near_arm_rest_z: int = _near_arm.z_index
@onready var _far_hand_rest_z: int = _far_hand.z_index

@export_enum("中性", "躯干前倾", "胸腔微调", "单腿抬起", "明显屈膝", "脚踝与脚尖", "抬臂屈肘", "头部独立微调") var preview_pose: int = 0:
	set(value):
		preview_pose = clampi(value, 0, POSE_NAMES.size() - 1)
		if is_node_ready() and not _action_mode:
			_apply_preview_pose()

var _action_mode := false
var _current_action: StringName = &""


func _ready() -> void:
	$AnimationPlayer.mixer_applied.connect(_after_animation)
	_apply_preview_pose()


func set_action_mode(enabled: bool) -> void:
	if _action_mode == enabled:
		return
	_action_mode = enabled
	_set_arm_depth(enabled)
	_current_action = &""
	_replay_blending = false
	$Skeleton2D.position.y = 0.0
	$AnimationPlayer.pause()
	if enabled and _soles.is_empty():
		var skeleton: Skeleton2D = $Skeleton2D
		_com = skeleton.find_child("COM", true, false)
		for index in range(skeleton.get_bone_count()):
			_bones.append(skeleton.get_bone(index))
		for side in ["L", "R"]:
			_soles.append(AlphaContour.new(get_node("Skin/Leg_%s" % side), skeleton.find_child("Shin_%s" % side, true, false)))


func _set_arm_depth(enabled: bool) -> void:
	# 原画左侧白肩 Arm_L 是近景臂；只在正式动作中让整条臂/手处于一致的前后层。
	_near_arm.z_index = _near_hand.z_index - 1 if enabled else _near_arm_rest_z
	_far_hand.z_index = $Skin/Arm_R.z_index + 1 if enabled else _far_hand_rest_z


func play_action(name: StringName, speed: float = 1.0, replay: bool = false) -> void:
	if not _action_mode or Engine.is_editor_hint():
		return
	var animation_player: AnimationPlayer = $AnimationPlayer
	if not animation_player.has_animation(name):
		push_error("V2 缺少正式动作：%s" % name)
		return
	if not is_finite(speed) or speed <= 0.0:
		push_error("V2 动作播放速度必须为正有限数。")
		return
	animation_player.speed_scale = speed
	if _current_action == name:
		if replay:
			_restart_from_current_pose(animation_player, name)
		return
	_replay_blending = false
	_current_action = name
	animation_player.play(name, ACTION_BLEND_SECONDS)


func reset_actions() -> void:
	var animation_player: AnimationPlayer = $AnimationPlayer
	_current_action = &""
	_replay_blending = false
	$Skeleton2D.position.y = 0.0
	animation_player.stop()
	animation_player.speed_scale = 1.0
	animation_player.play(&"RESET")
	animation_player.advance(0.0)
	animation_player.pause()
	if not _action_mode:
		_apply_preview_pose()


func _restart_from_current_pose(animator: AnimationPlayer, name: StringName) -> void:
	_replay_rotations.clear()
	for bone in _bones:
		_replay_rotations.append(bone.rotation)
	_replay_com = _com.position
	_replay_blending = true
	animator.stop(true)
	animator.play(name, ACTION_BLEND_SECONDS)


func _after_animation() -> void:
	if not _action_mode:
		return
	if _replay_blending:
		var animator: AnimationPlayer = $AnimationPlayer
		var amount := clampf(animator.current_animation_position / (ACTION_BLEND_SECONDS * animator.speed_scale), 0.0, 1.0)
		for index in range(_bones.size()):
			_bones[index].rotation = lerp_angle(_replay_rotations[index], _bones[index].rotation, amount)
		_com.position = _replay_com.lerp(_com.position, amount)
		_replay_blending = amount < 1.0
	var skeleton: Skeleton2D = $Skeleton2D
	skeleton.position.y = 0.0
	if GROUNDED_ACTIONS.has(_current_action):
		# 只消除插值穿地，保留跑步腾空；Actor 和外层支点不参与视觉校正。
		var height: float = maxf(_soles[0].height(), _soles[1].height())
		skeleton.position.y = -maxf(0.0, height)


func _apply_preview_pose() -> void:
	if _action_mode:
		return
	var animation_player: AnimationPlayer = $AnimationPlayer
	animation_player.speed_scale = 1.0
	animation_player.play(&"rig_test")
	animation_player.seek(preview_pose * POSE_INTERVAL_SECONDS, true)
	animation_player.pause()
