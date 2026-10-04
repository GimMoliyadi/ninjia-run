extends Bone2D

const BASE := 0
const MID := 1
const TIP := 2
const BONE_COUNT := 3
const ANGLE_PER_DEGREE := PI / 180.0
const MIN_DELTA := 0.0001
const TAIL_PROCESS_PRIORITY := 1
const MAX_DELTA_STEP := 1.0 / 120.0
const MAX_CATCH_UP_TIME := 0.2
const MAX_HIP_ANGLE_SPEED := 4.0
const MAX_HIP_Y_OFFSET := 4.0
const MAX_HIP_Y_SPEED := 240.0
const MAX_DRIVE_ANGLE := 6.0 * ANGLE_PER_DEGREE
const SPRING_STIFFNESS := [360.0, 240.0, 160.0]
const SPRING_DAMPING := [24.0, 18.0, 14.0]
const DRIVE_GAIN := [0.75, 0.55, 0.35]
const ANGLE_LIMITS := [
	4.0 * ANGLE_PER_DEGREE,
	7.0 * ANGLE_PER_DEGREE,
	10.0 * ANGLE_PER_DEGREE,
]
const PARENT_FOLLOW := [0.0, 0.8, 0.85]
const HIP_ANGLE_GAIN := 0.05
const HIP_Y_SPEED_GAIN := 0.00024
const HIP_Y_OFFSET_GAIN := 0.009

@onready var mid_bone: Bone2D = $CoatTail_Mid
@onready var tip_bone: Bone2D = $CoatTail_Mid/CoatTail_Tip
@onready var hip_bone: Bone2D = get_parent() as Bone2D
@onready var run_skeleton: Skeleton2D = hip_bone.get_parent() as Skeleton2D

var rest_rotations := PackedFloat32Array([0.0, 0.0, 0.0])
var spring_offsets := PackedFloat32Array([0.0, 0.0, 0.0])
var spring_velocities := PackedFloat32Array([0.0, 0.0, 0.0])
var hip_rest_rotation := 0.0
var hip_rest_y := 0.0
var last_hip_rotation := 0.0
var last_hip_y := 0.0
var was_running := false

func _ready() -> void:
	# Apply secondary motion after AnimationPlayer updates the hip.
	process_priority = TAIL_PROCESS_PRIORITY
	hip_rest_rotation = hip_bone.rotation
	hip_rest_y = hip_bone.position.y
	rest_rotations = PackedFloat32Array([rotation, mid_bone.rotation, tip_bone.rotation])
	_reset_state()

func _process(delta: float) -> void:
	if not run_skeleton.visible:
		was_running = false
		return
	if not was_running:
		_reset_state()
		was_running = true
		return
	# 非 RUN 只跟随父骨骼，保留原 RUN 次级动态且不与其他动作争写。
	var animation_player := run_skeleton.get_node("AnimationPlayer") as AnimationPlayer
	if animation_player.current_animation != "run":
		_reset_state()
		rotation = rest_rotations[BASE]
		return
	_update_tail(delta)

func _reset_state() -> void:
	spring_offsets.fill(0.0)
	spring_velocities.fill(0.0)
	last_hip_rotation = hip_bone.rotation
	last_hip_y = hip_bone.position.y
	rotation = rest_rotations[BASE] - wrapf(hip_bone.rotation - hip_rest_rotation, -PI, PI)
	mid_bone.rotation = rest_rotations[MID]
	tip_bone.rotation = rest_rotations[TIP]

func _update_tail(delta: float) -> void:
	var safe_delta := maxf(delta, MIN_DELTA)
	var hip_angle_speed := clampf(
		wrapf(hip_bone.rotation - last_hip_rotation, -PI, PI) / safe_delta,
		-MAX_HIP_ANGLE_SPEED,
		MAX_HIP_ANGLE_SPEED
	)
	var hip_y_offset := clampf(hip_bone.position.y - hip_rest_y, -MAX_HIP_Y_OFFSET, MAX_HIP_Y_OFFSET)
	var hip_y_speed := clampf(
		(hip_bone.position.y - last_hip_y) / safe_delta,
		-MAX_HIP_Y_SPEED,
		MAX_HIP_Y_SPEED
	)
	var motion_drive := clampf(
		-hip_angle_speed * HIP_ANGLE_GAIN
		- hip_y_speed * HIP_Y_SPEED_GAIN
		- hip_y_offset * HIP_Y_OFFSET_GAIN,
		-MAX_DRIVE_ANGLE,
		MAX_DRIVE_ANGLE
	)
	last_hip_rotation = hip_bone.rotation
	last_hip_y = hip_bone.position.y

	var remaining := minf(maxf(delta, 0.0), MAX_CATCH_UP_TIME)
	while remaining > 0.0:
		var step := minf(remaining, MAX_DELTA_STEP)
		_step_springs(motion_drive, step)
		remaining -= step

	var hip_rotation_delta := wrapf(hip_bone.rotation - hip_rest_rotation, -PI, PI)
	rotation = rest_rotations[BASE] - hip_rotation_delta + spring_offsets[BASE]
	mid_bone.rotation = rest_rotations[MID] + spring_offsets[MID]
	tip_bone.rotation = rest_rotations[TIP] + spring_offsets[TIP]

func _step_springs(motion_drive: float, delta: float) -> void:
	var targets := PackedFloat32Array([
		motion_drive * DRIVE_GAIN[BASE],
		spring_offsets[BASE] * PARENT_FOLLOW[MID] + motion_drive * DRIVE_GAIN[MID],
		spring_offsets[MID] * PARENT_FOLLOW[TIP] + motion_drive * DRIVE_GAIN[TIP],
	])
	for index in BONE_COUNT:
		var limit: float = ANGLE_LIMITS[index]
		var target := clampf(targets[index], -limit, limit)
		var acceleration: float = (target - spring_offsets[index]) * SPRING_STIFFNESS[index]
		acceleration -= spring_velocities[index] * SPRING_DAMPING[index]
		spring_velocities[index] += acceleration * delta
		spring_offsets[index] = clampf(
			spring_offsets[index] + spring_velocities[index] * delta,
			-limit,
			limit
		)
