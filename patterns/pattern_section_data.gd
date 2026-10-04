@tool
class_name PatternSectionData
extends Resource

# 关卡设计语义单位（Phrase）的直接表达：
# entries 中每一段是 ObstaclePatternData 或 RecoverySection，
# 顺序即编排顺序。例如 Dart_Introduction 的 entries 就是
#   P04 → P04 Variation → P14 → Recovery → P14 Variation → P17 → P17 Variation → Recovery

@export var section_name := ""

# 人类可读的 Section 名称，用于 F1 调试覆盖层与人工试玩反馈。
# 例如 "飞镖关"。留空时回退到 section_name。
@export var display_name := ""

# 可选：为 F1 调试覆盖层提供阶段名（Phrase A / Recovery / Phrase B / Exit Recovery）。
#
# stages 描述的是「阶段」，一个阶段可以覆盖多个 entries。
# stage_entries 给出每个阶段包含多少个 entry，因此必须满足
#   sum(stage_entries) == entries.size()
# 例如 Dart_Introduction：
#   stages        = ["Phrase A", "Recovery", "Phrase B", "Exit Recovery"]
#   stage_entries = [3, 1, 3, 1]      # P04/P04/P14 | R | P14/P17/P17 | R
#
# 两者都为空时不展示阶段名，不影响 build()。
@export var stages: PackedStringArray = []
@export var stage_entries: PackedInt32Array = []

@export var entries: Array[Resource] = []
@export_range(0, 3, 1) var shuffle_prefix := 0

# 返回 entry_index 对应的阶段名；无法对应时返回空字符串。
func stage_for(entry_index: int) -> String:
	if entry_index < 0 or entry_index >= entries.size():
		return ""
	if stages.is_empty() or stage_entries.is_empty():
		return ""
	if stages.size() != stage_entries.size():
		return ""
	var cursor := 0
	for index in stages.size():
		var count: int = stage_entries[index]
		if count <= 0:
			continue
		if entry_index < cursor + count:
			return stages[index]
		cursor += count
	if cursor != entries.size():
		return ""
	return ""
