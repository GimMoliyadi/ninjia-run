extends SceneTree

const RopeWave := preload("res://patterns/rope_wave_layout.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")

const WAVE_PATHS := [
	"res://patterns/library/RopeMap_Wave01_RiseFlip.tres",
	"res://patterns/library/RopeMap_Wave02_FallFlip.tres",
	"res://patterns/library/RopeMap_Wave03_ChainFlip.tres",
	"res://patterns/library/RopeMap_Wave04_ShortSpike.tres",
	"res://patterns/library/RopeMap_Wave05_LongSpike.tres",
	"res://patterns/library/RopeMap_Wave06_Breath.tres",
	"res://patterns/library/RopeMap_Wave07_TopRow.tres",
	"res://patterns/library/RopeMap_Wave08_RowSpike.tres",
	"res://patterns/library/RopeMap_Wave09_ReverseRow.tres",
	"res://patterns/library/RopeMap_Wave10_Finale.tres",
	"res://patterns/library/RopeMap_Wave11_Exit.tres",
]
const DIAGONAL_WAVES := [
	"RopeMap_Wave01_RiseFlip", "RopeMap_Wave02_FallFlip", "RopeMap_Wave03_ChainFlip",
	"RopeMap_Wave04_ShortSpike", "RopeMap_Wave05_LongSpike",
]
const CROSS_ROPE_MARGIN := 0.3

var failures: Array[String] = []

func _initialize() -> void:
	var all_actions: Array = []
	var offset := 0.0
	for path in WAVE_PATHS:
		var data: Resource = load(path)
		if data == null:
			failures.append("%s 资源解析失败" % path)
			continue
		if data is RecoverySection:
			offset += data.distance(Motion.RUN_SPEED)
			continue
		var plan := RopeWave.compile(data, Modifier.Kind.NORMAL, RecoverySection.new())
		for issue in plan.issues:
			failures.append("%s: %s" % [data.pattern_name, issue])
		if data.pattern_name in DIAGONAL_WAVES:
			check_crosses_rope(data, plan)
		for action in plan.rope_actions:
			var located: Dictionary = action.duplicate()
			for key in ["x", "danger_start", "danger_end"]:
				located[key] += offset
			all_actions.append(located)
		offset += plan.length
	for issue in RopeWave.validate_route(all_actions):
		failures.append("跨 Wave 汇总：" + issue)
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Rope wave data check passed: %d waves, %.0fpx" % [WAVE_PATHS.size(), offset])
	quit(0 if failures.is_empty() else 1)

func check_crosses_rope(data: Resource, plan: Dictionary) -> void:
	# 斜列的飞镖必须真的跨过绳线上下两侧（y>0 绳下 / y<0 绳上）。
	var threshold := Motion.BODY_SIZE.y * CROSS_ROPE_MARGIN
	var dart_events: Array = plan.events.filter(
		func(e: PatternEvent) -> bool: return e.preview_kind == PatternEvent.PreviewKind.DART
	)
	var below := dart_events.any(func(e: PatternEvent) -> bool: return e.position_offset.y > threshold)
	var above := dart_events.any(func(e: PatternEvent) -> bool: return e.position_offset.y < -threshold)
	check(below and above, "%s 斜列没有同时覆盖绳上与绳下" % data.pattern_name)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
