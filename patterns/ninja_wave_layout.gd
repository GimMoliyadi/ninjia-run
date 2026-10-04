extends RefCounted

const Motion := preload("res://patterns/player_motion_profile.gd")
const NINJA := preload("res://scenes/LeapingNinja.tscn")
const SPIKES := preload("res://scenes/SpikeStrip.tscn")
const PILLAR := preload("res://scenes/JumpPillar.tscn")
const NINJA_APPROACH := 1.8
const SPIKE_SIZE := Vector2(76.0, 72.0)
const PLATFORM_WIDTH := 200.0
const JUMP_LEAD := 140.0
const EXIT_CLEARANCE := 0.8
const MIN_GATE_DISTANCE := 280.0
const FORMATION_LAUNCH_DELAY := 0.12

static func compile(data: ObstaclePatternData, modifier: int, recovery: RecoverySection) -> Dictionary:
	var plan := {
		"events": [], "pits": [], "gaps": [], "recoveries": [], "notes": [],
		"issues": PackedStringArray(), "distance_driven": true, "ninja_actions": [],
		"duration": data.duration, "length": data.duration * Motion.RUN_SPEED,
		"recovery_length": recovery.distance(Motion.RUN_SPEED), "needs_manual_playtest": true,
	}
	if modifier != PatternModifier.Kind.NORMAL or data.mirror or not is_zero_approx(data.start_delay):
		plan.issues.append("忍者 Wave 使用固定空间节奏，不支持镜像或时间偏移")
	var gates: Array = data.parameters.get("gates", [])
	if gates.is_empty() or data.duration <= 0.0:
		plan.issues.append("忍者 Wave 必须有正时长和有序动作")
	for gate in gates:
		append_gate(plan, gate)
	plan.events.sort_custom(func(a: PatternEvent, b: PatternEvent) -> bool: return a.spawn_time < b.spawn_time)
	plan.issues.append_array(validate_route(plan.ninja_actions))
	return plan

static func append_gate(plan: Dictionary, gate: Dictionary) -> void:
	var kind := str(gate.get("kind", ""))
	var beat := float(gate.get("beat", -1.0))
	if kind not in ["low", "high", "spike"]:
		plan.issues.append("未知忍者动作: %s" % kind)
		return
	if beat < 0.0 or beat > plan.duration - EXIT_CLEARANCE:
		plan.issues.append("忍者动作越出 Wave 或没有留出落地出口")
	var event := PatternEvent.new()
	event.position_offset = Vector2(beat * Motion.RUN_SPEED, 0)
	if kind == "spike":
		event.obstacle_scene = SPIKES
		event.spawn_time = beat - NINJA_APPROACH
		event.optional_parameters = {"size": SPIKE_SIZE}
		event.preview_kind = PatternEvent.PreviewKind.SPIKE
		event.preview_size = SPIKE_SIZE
	else:
		var spawn_beat: float = float(gate.get("spawn_beat", -1.0))
		var platform_height: float = float(gate.get("platform_height", 0.0))
		event.obstacle_scene = NINJA
		event.spawn_time = spawn_beat if spawn_beat >= 0.0 else beat - NINJA_APPROACH
		event.optional_parameters = {"jump_kind": kind, "crossing_time": NINJA_APPROACH}
		if spawn_beat >= 0.0:
			event.optional_parameters["launch_delay"] = FORMATION_LAUNCH_DELAY
		if platform_height > 0.0:
			event.position_offset.y = -platform_height
			append_platform(plan, event.position_offset.x, platform_height, event.spawn_time)
		event.preview_kind = PatternEvent.PreviewKind.OTHER
	plan.events.append(event)
	plan.ninja_actions.append({"kind": kind, "x": event.position_offset.x, "height": -event.position_offset.y})

static func append_platform(plan: Dictionary, enemy_x: float, height: float, spawn_time: float) -> void:
	var left := enemy_x - PLATFORM_WIDTH * 0.5
	if left < 0.0:
		plan.issues.append("平台敌人的站位超出 Wave 起点")
	var platform := PatternEvent.new()
	platform.obstacle_scene = PILLAR
	platform.position_offset = Vector2(left, 0.0)
	platform.spawn_time = maxf(0.0, spawn_time - 0.1)
	platform.optional_parameters = {"size": Vector2(PLATFORM_WIDTH, height)}
	platform.preview_kind = PatternEvent.PreviewKind.PLATFORM
	platform.preview_size = Vector2(PLATFORM_WIDTH, height)
	plan.events.append(platform)

static func validate_route(actions: Array) -> PackedStringArray:
	var issues := PackedStringArray()
	for index in range(1, actions.size()):
		var previous: Dictionary = actions[index - 1]
		var current: Dictionary = actions[index]
		if current.x - previous.x < MIN_GATE_DISTANCE:
			issues.append("%s → %s 的站位间隔过短" % [previous.kind, current.kind])
		if previous.kind == "spike" and current.kind == "spike":
			var available: float = (current.x - previous.x) / Motion.Player.SLIDE_BURST_SPEED
			if available < Motion.jump_time() + Motion.Player.JUMP_BUFFER_TIME:
				issues.append("连续地刺缺少完整跳跃恢复时间")
	return issues
