class_name MapModuleChunk
extends "res://components/chunk.gd"

const Section := preload("res://patterns/pattern_section.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")
const JumpWave := preload("res://patterns/jump_wave_layout.gd")
# ⚠ 这两个常量名不能叫 Motion / Library：本类是很多 Chunk 的父类
#（dart_encounter.gd、rope_map_chunk.gd 都 extends 它），
# 子类里已经有自己的 `const Motion`，同名会在解析期直接报
# "The member already exists in parent class" 并把整个子类脚本废掉。
const DartLibrary := preload("res://patterns/dart_pattern_library.gd")
const DartMotion := preload("res://patterns/player_motion_profile.gd")

@export_file("*.tres") var module_data_path := ""

@onready var entry: Marker2D = $Entry
@onready var exit: Marker2D = $Exit

var module_data: MapModuleData
var sections: Array[PatternSection] = []
var total_length := 0.0
var build_ready := false
var layout_seed := 0

# 全图飞镖衔接体检结果（见 _check_act_continuity）。
var act_report: Dictionary = {}

func _ready() -> void:
	module_data = load(module_data_path)
	if module_data == null:
		push_error("%s: 找不到 Map Module 数据 %s" % [name, module_data_path])
		return
	_build_sections()
	_build_ground()
	super._ready()
	build_ready = true

func _build_sections() -> void:
	sections.clear()
	total_length = 0.0
	for section_index in module_data.sections.size():
		var section_data: PatternSectionData = module_data.sections[section_index]
		var entries: Array[Resource] = section_data.entries.duplicate()
		var stages: PackedStringArray = section_data.stages.duplicate()
		var random := RandomNumberGenerator.new()
		random.seed = layout_seed + section_index
		if layout_seed != 0 and section_data.shuffle_prefix > 1:
			var prefix: int = mini(section_data.shuffle_prefix, entries.size())
			for index in range(prefix - 1, 0, -1):
				var choice := random.randi_range(0, index)
				var selected: Resource = entries[index]
				entries[index] = entries[choice]
				entries[choice] = selected
				var stage: String = stages[index]
				stages[index] = stages[choice]
				stages[choice] = stage
			section_data = section_data.duplicate()
			section_data.entries = entries
			section_data.stages = stages
		var section := Section.new()
		section.name = "Section%d" % (section_index + 1)
		section.data = section_data
		section.coin_arc_height = 0.0 if layout_seed == 0 else random.randi_range(0, 2) * Section.COIN_ARC_STEP
		if layout_seed != 0:
			section.coin_alignment = random.randf()
			section.coin_spacing_scale = random.randf_range(0.75, 1.0)
		section.position = Vector2(entry.position.x + total_length, entry.position.y)
		add_child(section)
		section.build(
			entries,
			_find_player(),
			module_data.difficulty,
			Modifier.Kind.NORMAL,
			null,
			false
		)
		sections.append(section)
		total_length += section.section_length
		for issue in section.all_issues():
			push_error("%s/%s: Pattern 参数问题 — %s" % [name, section.name, issue])
	exit.position = Vector2(entry.position.x + total_length, entry.position.y)
	_check_act_continuity()

# =========================================================
# 全图飞镖衔接体检（2026-09-18 第 7 轮新增）
# =========================================================
#
# 为什么必须在 Module 层再做一遍：
#
#   dart_wave_layout 只能看到**单段 Wave 内部**的飞镖。
#   但玩家是从上一段 Wave 直接跑进下一段的 —— 上一段的末枚与下一段的首枚
#   之间隔多远，决定了「上一个动作的轨迹能不能自然接上」。
#   这一段距离由「上一段的 duration（= 地面长度）」和「下一段的 start_px」共同决定，
#   单段编译时根本看不到。
#
#   所以这里按**真实相遇点 X**（beat × RUN_SPEED，加上各 Wave 的世界原点）
#   把整张图的飞镖排成一条时间线，再用与 Wave 内部完全相同的规则复核：
#
#     * 一簇用 CONTINUOUS 间距连起来的 ACT 飞镖，首尾跨度必须 <= 一个滑铲的覆盖
#       —— 否则玩家滑到一半滑铲结束，正好在最后一枚上撞个正着。
#     * 簇与簇之间的间距不能落进死区（268 ~ 384px，见 dart_pattern_library
#       的 seam_continuous_max_px / seam_clean_min_px）
#       —— 既接不上上一个动作，又来不及重新起跳，只会逼出帧级操作。
#
#   落在死区只报 warning（还能靠「滑铲结束立刻再按一次」硬过，只是不自然）；
#   跨度超限报 error（物理上盖不住，是真·不可解）。
#
# ⚠ 只在平地图上跑（见 _act_check_applies）。
func _check_act_continuity() -> void:
	if not _act_check_applies():
		return
	act_report = DartLibrary.map_act_report(_collect_dart_encounters())
	for issue in act_report.issues:
		push_error("%s: 飞镖衔接问题 — ACT 飞镖簇跨度过长：%d 枚从 x=%.0f 起跨 %.0fpx，一个滑铲只能盖 %.0fpx" % [
			name, issue.count, issue.first_x, issue.span_px, issue.limit_px])
	for note in act_report.notes:
		push_warning("%s: 飞镖衔接提示 — %s" % [name, note])

# 按编译计划的坐标语义选择检查，而不是按主题；混合段也可能含平地飞镖。
func _act_check_applies() -> bool:
	for section in sections:
		for runner in section.runners:
			if runner.plan.get("flat_dart_layout", false) or runner.plan.get("patterns_arranged", null) != null:
				return true
	return false

# 收集整张图所有飞镖的相遇点。
#
# 相遇点世界 X = Wave 世界原点 + beat × RUN_SPEED。
# 其中 beat = spawn_time + approach（approach = 单跳滞空 × 2，见 dart_wave_layout）。
# 这里刻意不读飞镖节点的实时坐标：节点只在玩家靠近时才生成，
# 而衔接体检要在建图时就能跑。
func _collect_dart_encounters() -> Array:
	var darts: Array = []
	for section in sections:
		for runner in section.runners:
			var plan: Dictionary = runner.plan
			if not plan.get("flat_dart_layout", false) and not plan.has("patterns_arranged"):
				continue
			var wave_x: float = section.position.x + runner.position.x
			for event in plan.events:
				if event.preview_kind != PatternEvent.PreviewKind.DART:
					continue
				var approach: float = (event.position_offset.x - event.spawn_time * DartMotion.RUN_SPEED) / (DartMotion.RUN_SPEED - event.speed * event.direction.normalized().x)
				var beat: float = event.spawn_time + approach
				darts.append({
					"x": wave_x + beat * DartMotion.RUN_SPEED,
					"h": -event.position_offset.y,
				})
	darts.sort_custom(func(a, b): return float(a.x) < float(b.x))
	return darts

func _find_player() -> Node2D:
	var owner_node := get_parent()
	if owner_node != null:
		var sibling := owner_node.get_node_or_null("Player")
		if sibling is Node2D:
			return sibling
	return null

func _build_ground() -> void:
	var plans: Array[Dictionary] = []
	var offsets := PackedFloat64Array()
	for section in sections:
		for runner in section.runners:
			if runner.plan.get("jump_layout", false):
				plans.append(runner.plan)
				offsets.append(section.position.x + runner.position.x)
	JumpWave.carve_platform_pits(plans, offsets)
	for section in sections:
		for runner in section.runners:
			section.build_ground(runner.plan, runner.position.x)
		section.add_route_coin_trails()

func advance(delta: float, player: Node2D, progress_x: float = NAN) -> void:
	for section in sections:
		for runner in section.runners:
			if runner.player == null:
				runner.player = player
		section.advance(delta, player, progress_x)

func debug_info() -> Dictionary:
	if module_data == null:
		return {}
	var sequences := PackedStringArray()
	var issues := PackedStringArray()
	for section in sections:
		sequences.append(section.template_sequence())
		issues.append_array(section.all_issues())
	return {
		"map": module_data.display_name if not module_data.display_name.is_empty() else module_data.module_id,
		"map_id": module_data.module_id,
		"theme": module_data.theme,
		"variant": module_data.variant,
		"difficulty": module_data.difficulty,
		"sequence": " | ".join(sequences),
		"total_length": total_length,
		"issues": issues,
		"act_issues": act_report.get("issues", []),
		"act_notes": act_report.get("notes", []),
		"act_darts": act_report.get("acts", 0),
	}

func debug_info_at(global_x: float) -> Dictionary:
	for section_index in sections.size():
		var section := sections[section_index]
		var section_data: PatternSectionData = module_data.sections[section_index]
		var info := section.info_at(global_x)
		if info.is_empty():
			continue
		info["map"] = module_data.display_name if not module_data.display_name.is_empty() else module_data.module_id
		info["map_id"] = module_data.module_id
		info["section"] = section_data.display_name if not section_data.display_name.is_empty() else section_data.section_name
		info["section_id"] = section_data.section_name
		info["wave"] = info.get("stage", "")
		info["difficulty"] = module_data.difficulty
		return info
	return {}
