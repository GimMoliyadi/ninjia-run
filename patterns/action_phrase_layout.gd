extends RefCounted

const Motion := preload("res://patterns/player_motion_profile.gd")
const JumpWave := preload("res://patterns/jump_wave_layout.gd")
const Layouts := preload("res://patterns/pattern_layouts.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")
const DartLibrary := preload("res://patterns/dart_pattern_library.gd")
const Wheel := preload("res://components/blade_wheel.gd")
const FallingBlade := preload("res://components/falling_blade.gd")
const WHEEL_SCENE := preload("res://scenes/BladeWheel.tscn")
const FALLING_BLADE_SCENE := preload("res://scenes/FallingBlade.tscn")
const MIN_SECONDS := 3.0
const MAX_SECONDS := 7.0
const BEAM_CLEARANCE_MARGIN := 8.0
const DART_APPROACH_JUMPS := 2.0
const DART_SPEED_RATIO := 0.45
const MIN_NEW_OBSTACLE_REACTION := 0.75
const DEFAULT_CRUMBLE_DELAY_RATIO := 1.0

static func compile(data: ObstaclePatternData, modifier: int, recovery: RecoverySection) -> Dictionary:
	var plan := {
		"events": [], "pits": [], "gaps": [], "recoveries": [], "notes": [],
		"issues": PackedStringArray(), "distance_driven": true,
		"flat_dart_layout": true, "duration": data.duration,
		"length": data.duration * Motion.RUN_SPEED,
		"recovery_length": recovery.distance(Motion.RUN_SPEED), "needs_manual_playtest": true,
	}
	if modifier != Modifier.Kind.NORMAL or data.mirror or not is_zero_approx(data.start_delay):
		plan.issues.append("动作组合使用固定空间编排，不支持时间或镜像变体")
	# duration 是路线距离标尺，不是假装所有输入都维持基础跑速。
	if plan.length / Motion.Player.SLIDE_BURST_SPEED < MIN_SECONDS or data.duration > MAX_SECONDS:
		plan.issues.append("动作组合在基础及峰值跑速下都必须占用 3～7 秒")
	append_actions(plan, data.parameters.get("actions", []))
	plan.events.sort_custom(func(a: PatternEvent, b: PatternEvent) -> bool: return a.spawn_time < b.spawn_time)
	return plan

static func append_actions(plan: Dictionary, actions: Array) -> void:
	var kinds := {}
	var previous_end := 0.0
	for action in actions:
		var x: float = float(action.get("beat", 0.0)) * Motion.RUN_SPEED
		var kind: String = action.get("kind", "")
		var event := action_event(plan, action, kind, x)
		if event == null:
			continue
		kinds[kind] = true
		var span := action_span(event, kind, x)
		if span.x < 0.0 or span.x < previous_end or span.y > plan.length - Motion.BODY_SIZE.x:
			plan.issues.append("组合障碍重叠或越过出口缓冲")
		previous_end = maxf(previous_end, span.y)
		if event.speed <= 0.0:
			event.spawn_time = x / Motion.RUN_SPEED - Motion.jump_time() * JumpWave.LOOKAHEAD_JUMPS
		if kind in ["roller", "falling_blade"]:
			var first_contact := span.x - Motion.BODY_SIZE.x * 0.5
			if first_contact / Motion.Player.SLIDE_BURST_SPEED < MIN_NEW_OBSTACLE_REACTION:
				plan.issues.append("新障碍入口必须留出至少 0.75 秒首次反应空间")
	var has_low_action: bool = kinds.has("slide") or kinds.has("falling_blade")
	var has_jump_action: bool = kinds.has("spike") or kinds.has("platform") or kinds.has("crumble_platform") or kinds.has("roller")
	if not has_low_action or not has_jump_action:
		plan.issues.append("动作组合必须同时含真实低身通道与起跳障碍")
	if plan.get("jump_layout", false):
		JumpWave.carve_platform_pits([plan], PackedFloat64Array([0.0]))
	plan["threat_end"] = previous_end / Motion.RUN_SPEED
	plan["needed_length"] = previous_end

static func action_span(event: PatternEvent, kind: String, x: float) -> Vector2:
	if kind in ["roller", "falling_blade"]:
		var radius := event.preview_size.x * 0.5
		return Vector2(x - radius, x + radius)
	return Vector2(x, x + event.preview_size.x)

static func action_event(plan: Dictionary, action: Dictionary, kind: String, x: float) -> PatternEvent:
	match kind:
		"spike", "platform", "crumble_platform":
			var pillar := kind != "spike"
			var width: float = Motion.BODY_SIZE.x * float(action.get("width_ratio", 1.0))
			var height: float = Motion.jump_height() * float(action.get("height_ratio", 0.4)) if pillar else JumpWave.SPIKE_HEIGHT
			var phrase := action.duplicate()
			if kind == "crumble_platform":
				phrase["crumble_delay_ratio"] = float(action.get("crumble_delay_ratio", DEFAULT_CRUMBLE_DELAY_RATIO))
				if float(phrase.crumble_delay_ratio) <= 0.0:
					plan.issues.append("crumble_platform 必须设置正的碎裂延迟")
				plan["jump_layout"] = true
			return JumpWave.append_obstacle(plan, x, Vector2(width, height), pillar, phrase)
		"slide":
			var event := Layouts.ceiling(x, Motion.SLIDE_HEIGHT + BEAM_CLEARANCE_MARGIN)
			plan.events.append(event)
			return event
		"dart", "roller":
			return append_moving_event(plan, kind, x)
		"falling_blade":
			return append_falling_blade(plan, x)
		_:
			plan.issues.append("未知动作组合障碍：" + kind)
			return null

static func append_moving_event(plan: Dictionary, kind: String, encounter_x: float) -> PatternEvent:
	var roller := kind == "roller"
	var approach := Motion.jump_time() * DART_APPROACH_JUMPS
	var speed := Motion.RUN_SPEED * (Wheel.WHEEL_SPEED_RATIO if roller else DART_SPEED_RATIO)
	var height := Wheel.WHEEL_RADIUS if roller else DartLibrary.slide_height()
	if roller:
		var contact_pad := Wheel.WHEEL_RADIUS + Motion.BODY_SIZE.x * 0.5
		var reaction_in_route_time := MIN_NEW_OBSTACLE_REACTION * Motion.Player.SLIDE_BURST_SPEED / Motion.RUN_SPEED
		approach = maxf(approach, reaction_in_route_time + contact_pad / (Motion.RUN_SPEED + speed))
	var event := Layouts.dart(encounter_x / Motion.RUN_SPEED - approach, approach * (Motion.RUN_SPEED + speed), height, speed)
	if roller:
		event.obstacle_scene = WHEEL_SCENE
		event.optional_parameters = {"collision_radius": Wheel.WHEEL_RADIUS}
		event.preview_kind = PatternEvent.PreviewKind.BLADE_WHEEL
		event.preview_size = Vector2.ONE * Wheel.WHEEL_RADIUS * 2.0
	plan.events.append(event)
	return event

static func append_falling_blade(plan: Dictionary, x: float) -> PatternEvent:
	var event := PatternEvent.new()
	event.obstacle_scene = FALLING_BLADE_SCENE
	event.position_offset = Vector2(x, -FallingBlade.START_HEIGHT)
	event.preview_kind = PatternEvent.PreviewKind.FALLING_BLADE
	event.preview_size = Vector2(FallingBlade.BLADE_RADIUS * 2.0, FallingBlade.DROP_DISTANCE + FallingBlade.BLADE_RADIUS * 2.0)
	plan.events.append(event)
	return event
