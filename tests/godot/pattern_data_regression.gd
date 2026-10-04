extends SceneTree

const Library := preload("res://patterns/pattern_library.gd")
const Compiler := preload("res://patterns/pattern_compiler.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")
var failures: Array[String] = []
var checked := 0

func _initialize() -> void:
	for index in Library.NAMES.size():
		var data := Library.load_pattern(index)
		var before := var_to_str(data.parameters)
		for level in range(1, 6):
			for mode in Modifier.LABELS.size():
				var plan := Compiler.compile(data, level, mode, RecoverySection.new())
				if not Modifier.supported(data, mode):
					check(not plan.issues.is_empty(), "unsupported modifier accepted")
					continue
				checked += 1
				check(plan.issues.is_empty(), "%s/%d/%s: %s" % [data.pattern_name, level, Modifier.LABELS[mode], plan.issues])
				check(plan.needs_manual_playtest, "must not claim route proof")
				check(plan.events.size() <= 96, "event budget exceeded")
		check(before == var_to_str(data.parameters), "resource mutated by compilation")
	check_transformations()
	check_invalid_parameters()
	for failure in failures:
		printerr(failure)
	if failures.is_empty():
		print("Pattern data regression passed: %d supported combinations" % checked)
	quit(0 if failures.is_empty() else 1)

func check_transformations() -> void:
	var data := Library.load_pattern(6)
	var recovery := RecoverySection.new()
	recovery.duration = 1.7
	var normal := Compiler.compile(data, 3, Modifier.Kind.NORMAL, recovery)
	var doubled := Compiler.compile(data, 3, Modifier.Kind.DOUBLE, recovery)
	check(doubled.events.size() == normal.events.size() * 2, "DOUBLE lost events")
	check(is_equal_approx(doubled.recoveries[-1].y - doubled.recoveries[-1].x, 1.7), "DOUBLE ignored recovery duration")
	var reverse := Compiler.compile(data, 3, Modifier.Kind.REVERSE, recovery)
	reverse.gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	check(reverse.gaps[0].rect.position.y == normal.gaps[-1].rect.position.y, "REVERSE did not reverse wall order")
	var mirrored := Compiler.compile(data, 3, Modifier.Kind.MIRRORED, recovery)
	check(is_equal_approx(mirrored.gaps[0].rect.get_center().y + normal.gaps[0].rect.get_center().y, -320), "mirror axis incorrect")
	var rhythm := Compiler.compile(Library.load_pattern(11), 3, Modifier.Kind.SLOW, recovery)
	check(rhythm.recoveries[0].x > rhythm.events[1].spawn_time + 1.0, "Recovery starts before darts pass")
	check(Compiler.compile(data, 1, 0, recovery).gaps.size() == 2, "easy wall count")
	check(Compiler.compile(data, 5, 0, recovery).gaps.size() == 4, "hard wall count")

func check_invalid_parameters() -> void:
	var spike: ObstaclePatternData = Library.load_pattern(0).duplicate(true)
	spike.parameters.warning_distance = 20.0
	check(not Compiler.compile(spike, 3, 0, RecoverySection.new()).issues.is_empty(), "short warning accepted")
	var wall: ObstaclePatternData = Library.load_pattern(3).duplicate(true)
	wall.parameters.safe_gap_size = 40.0
	check(not Compiler.compile(wall, 3, 0, RecoverySection.new()).issues.is_empty(), "impossible narrow gap accepted")
	var pit: ObstaclePatternData = Library.load_pattern(9).duplicate(true)
	pit.parameters.pit_width = 500.0
	check(not Compiler.compile(pit, 3, 0, RecoverySection.new()).issues.is_empty(), "impossible pit accepted")
	var cycle: ObstaclePatternData = Library.load_pattern(11).duplicate(true)
	cycle.final_pattern = Library.load_pattern(11)
	check(not Compiler.compile(cycle, 3, 0, RecoverySection.new()).issues.is_empty(), "nested rhythm accepted")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
