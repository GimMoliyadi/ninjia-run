extends Skeleton2D

const IDLE_DURATION := 1.2
const JUMP_START_DURATION := 0.09
const AIR_POSE_DURATION := 0.3
const DOUBLE_JUMP_DURATION := 0.32
const LAND_DURATION := 0.12
const SLIDE_DURATION := 0.58
const BREATHING_HEIGHT := -36.7
const COAT_TRACKS := {
	"Hip/CoatTail_Base:rotation": 2.827433,
	"Hip/CoatTail_Base/CoatTail_Mid:rotation": 0.0,
	"Hip/CoatTail_Base/CoatTail_Mid/CoatTail_Tip:rotation": 0.0,
}

# 沿用 RUN 已成立的双手握持关系，让 Torso 带动手臂、握点和剑鞘，避免各动作脱手。
const HOLD_POSE := [rad_to_deg(3.639034), rad_to_deg(-1.915892), rad_to_deg(2.036702), rad_to_deg(1.901556), rad_to_deg(1.160644)]
# 顺序对应现有 RUN 的轨道；位置以像素计，其余关节以角度计。
const IDLE_POSE := [Vector2(0, -36), 0.0, -90.0, 90.0, -18.0, 8.0, 105.0, -25.0, -80.0, 75.0, 25.0, -100.0] + HOLD_POSE
const CROUCH_POSE := [Vector2(2, -25), 6.0, -78.0, 78.0, -8.0, 5.0, 40.0, 110.0, -156.0, 125.0, -100.0, -31.0] + HOLD_POSE
const JUMP_POSE := [Vector2(1, -34), 5.0, -88.0, 88.0, 8.0, 10.0, -15.0, 110.0, -100.0, 125.0, -65.0, -65.0] + HOLD_POSE
const TUCK_POSE := [Vector2(-3, -21), 12.0, -78.0, 78.0, 5.0, 8.0, -35.0, 140.0, -117.0, 15.0, 125.0, -152.0] + HOLD_POSE
const FALL_POSE := [Vector2(1, -34), 2.0, -92.0, 92.0, -8.0, 5.0, 65.0, 25.0, -92.0, 112.0, -35.0, -79.0] + HOLD_POSE
const SLIDE_POSE := [Vector2(-10, -12), 5.0, 5.0, -5.0, 2.0, 5.0, 10.0, -8.0, -7.0, 145.0, -35.0, -115.0] + HOLD_POSE

func _ready() -> void:
	var animation_player := $AnimationPlayer as AnimationPlayer
	# 每个实例保留自己的动画库，避免改动共享 RUN 资源或已有残影实例。
	var library := animation_player.get_animation_library("").duplicate() as AnimationLibrary
	animation_player.remove_animation_library("")
	animation_player.add_animation_library("", library)
	var run := library.get_animation("run")
	add_pose_animation(library, run, "idle", IDLE_DURATION, true, [IDLE_POSE, breathing_pose(), IDLE_POSE])
	add_pose_animation(library, run, "jump_start", JUMP_START_DURATION, false, [CROUCH_POSE, JUMP_POSE])
	add_pose_animation(library, run, "jump_up", AIR_POSE_DURATION, true, [JUMP_POSE])
	add_pose_animation(library, run, "double_jump", DOUBLE_JUMP_DURATION, false, [JUMP_POSE, TUCK_POSE, TUCK_POSE, JUMP_POSE])
	add_pose_animation(library, run, "fall", AIR_POSE_DURATION, true, [FALL_POSE])
	add_pose_animation(library, run, "land", LAND_DURATION, false, [FALL_POSE, CROUCH_POSE, IDLE_POSE])
	add_pose_animation(library, run, "slide", SLIDE_DURATION, true, [SLIDE_POSE])

func breathing_pose() -> Array:
	var pose := IDLE_POSE.duplicate()
	pose[0] = Vector2(0, BREATHING_HEIGHT)
	return pose

func add_pose_animation(library: AnimationLibrary, run: Animation, animation_name: String, duration: float, looping: bool, poses: Array) -> void:
	var animation := Animation.new()
	animation.resource_name = animation_name
	animation.length = duration
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	for track in run.get_track_count():
		var pose_track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(pose_track, run.track_get_path(track))
		for frame in poses.size():
			var key_time := duration * frame / maxf(1.0, poses.size() - 1.0)
			var value: Variant = poses[frame][track]
			if track != 0:
				value = deg_to_rad(float(value))
			animation.track_insert_key(pose_track, key_time, value)
	for path: String in COAT_TRACKS:
		var coat_track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(coat_track, NodePath(path))
		animation.track_insert_key(coat_track, 0.0, COAT_TRACKS[path])
	library.add_animation(animation_name, animation)
