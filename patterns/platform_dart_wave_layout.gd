extends RefCounted

const Motion := preload("res://patterns/player_motion_profile.gd")
const JumpWave := preload("res://patterns/jump_wave_layout.gd")
const Layouts := preload("res://patterns/pattern_layouts.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")
const Dart := preload("res://components/dart.gd")
const LANDING_DART_HEIGHT := 58.0
const GAP_DART_HEIGHT := 28.0
const LANDING_DART_RATIO := 0.74
const MIN_LANDING_WIDTH := 360.0
const EXIT_MARGIN := 0.4

static func compile(data: ObstaclePatternData, modifier: int, recovery: RecoverySection) -> Dictionary:
	var plan := {
		"events": [], "pits": [], "gaps": [], "recoveries": [], "notes": [],
		"issues": PackedStringArray(), "distance_driven": true, "jump_layout": true,
		"duration": data.duration, "length": data.duration * Motion.RUN_SPEED,
		"recovery_length": recovery.distance(Motion.RUN_SPEED), "needs_manual_playtest": true,
	}
	if modifier != Modifier.Kind.NORMAL or data.mirror or not is_zero_approx(data.start_delay):
		plan.issues.append("跳台飞镖 Wave 使用固定落点，不支持时间或镜像变体")
	var phrases: Array = data.parameters.get("phrases", [])
	var speed: float = data.parameters.get("speed", 180.0)
	if phrases.is_empty() or data.duration <= 0.0 or speed <= 0.0:
		plan.issues.append("跳台飞镖 Wave 必须有正时长、正镖速和连续 Pattern")
		return plan
	var previous := Rect2()
	for phrase in phrases:
		previous = append_phrase(plan, phrase, previous, speed)
	plan.events.sort_custom(func(a: PatternEvent, b: PatternEvent) -> bool: return a.spawn_time < b.spawn_time)
	plan["threat_end"] = previous.end.x / Motion.RUN_SPEED
	plan["needed_length"] = previous.end.x
	if previous.end.x > plan.length - Motion.RUN_SPEED * EXIT_MARGIN:
		plan.issues.append("最后跳台没有保留出场落地距离")
	JumpWave.carve_platform_pits([plan], PackedFloat64Array([0.0]))
	plan.notes.append("坑中低镖配合跨台起跳；台尾高镖要求落稳压低，再起跳跨下一坑")
	return plan

static func append_phrase(plan: Dictionary, phrase: Dictionary, previous: Rect2, speed: float) -> Rect2:
	var platform := Rect2(float(phrase.get("beat", 0.0)) * Motion.RUN_SPEED, 0.0,
		float(phrase.get("width", 400.0)), float(phrase.get("height", 70.0)))
	var pattern: String = phrase.get("pattern", "vault_slide")
	if pattern not in ["vault", "landing_slide", "vault_slide"]:
		plan.issues.append("未知跳台飞镖 Pattern: " + pattern)
	if platform.size.x < MIN_LANDING_WIDTH or platform.position.x < previous.end.x:
		plan.issues.append("跳台须有完整落地滑铲宽度，且不能与前台重叠")
	JumpWave.append_obstacle(plan, platform.position.x, platform.size, true)
	if previous.size.x > 0.0:
		var gap := platform.position.x - previous.end.x
		if gap <= 0.0 or gap > Motion.safe_double_jump_gap(platform.size.y - previous.size.y):
			plan.issues.append("连续跳台间隙超过保守二段跳范围")
		elif pattern in ["vault", "vault_slide"]:
			var encounter := previous.end.x + gap * 0.5
			append_dart(plan, encounter, maxf(previous.size.y, platform.size.y) + GAP_DART_HEIGHT, speed)
	if pattern in ["landing_slide", "vault_slide"]:
		append_dart(plan, platform.position.x + platform.size.x * LANDING_DART_RATIO,
			platform.size.y + LANDING_DART_HEIGHT, speed)
	return platform

static func append_dart(plan: Dictionary, encounter: float, height: float, speed: float) -> void:
	var distance := Motion.RUN_SPEED * Motion.jump_time() * JumpWave.LOOKAHEAD_JUMPS
	var approach := distance / (Motion.RUN_SPEED + speed)
	if approach >= Dart.LIFETIME:
		plan.issues.append("飞镖寿命不足以到达跳台落点")
	plan.events.append(Layouts.dart(encounter / Motion.RUN_SPEED - approach, distance, height, speed))
