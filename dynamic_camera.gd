extends Camera2D

# 为高速迎面机关留出前方读招空间，不靠缩小人物扩大视野。
const LOOK_AHEAD := 240.0
# 垂直方向仍然把角色压在画面中线下方 80px（相机抬高一档，多看头顶一侧的空间）。
const VERTICAL_OFFSET := -80.0
const FOLLOW_RESPONSE := 12.0
const BASE_ZOOM := Vector2.ONE
const TRAUMA_DECAY := 1.8
const SHAKE_PIXELS := Vector2(9, 6)
@export var target: CharacterBody2D
var forward_x := 0.0
var trauma := 0.0
var noise := FastNoiseLite.new()
var noise_time := 0.0

func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	position_smoothing_enabled = false
	noise.seed = 73
	noise.frequency = 1.0
	target.landed.connect(on_landed)
	target.damaged.connect(on_damaged)
	target.run_reset.connect(reset_camera)
	reset_camera()

func _process(delta: float) -> void:
	var destination := target.global_position + Vector2(LOOK_AHEAD, VERTICAL_OFFSET)
	destination.x = maxf(forward_x, target.global_position.x) + LOOK_AHEAD
	global_position = global_position.lerp(destination, 1.0 - exp(-FOLLOW_RESPONSE * delta))
	zoom = BASE_ZOOM
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	noise_time += delta * 24.0
	offset = SHAKE_PIXELS * trauma * trauma * Vector2(noise.get_noise_1d(noise_time), noise.get_noise_1d(noise_time + 100.0))

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func on_landed(speed: float) -> void:
	add_trauma(clampf(speed / 2000.0, 0.0, 0.3))

func on_damaged(_amount: float) -> void:
	add_trauma(0.65)

func reset_camera() -> void:
	forward_x = target.global_position.x
	global_position = target.global_position + Vector2(LOOK_AHEAD, VERTICAL_OFFSET)
	zoom = BASE_ZOOM
	offset = Vector2.ZERO
	trauma = 0.0
