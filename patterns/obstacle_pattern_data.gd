@tool
class_name ObstaclePatternData
extends Resource

@export var pattern_name := "NewPattern"

# 人类可读名称。用于 F1 调试覆盖层与人工试玩反馈。
#
# 设计要求：描述这个 Pattern 的**真实行为**，而不是编号或抽象代号。
# 玩家与设计者应当能用这个名称直接对话，例如
#   「低位单飞镖太简单」
#   「上下换位飞镖墙后面留白太长」
#
# 编号（template，如 P04 / P14 / P17）继续作为内部技术 ID，
# 在调试信息里以括号形式附在显示名之后：`低位单飞镖 (P04)`。
@export var display_name := ""

@export_enum("CUSTOM", "P01", "P04", "P08", "P14", "P15", "P16", "P17", "P18", "P21", "P22", "P24", "P28", "P30", "DART_WAVE", "JUMP_WAVE", "ROPE_WAVE", "PLATFORM_DART_WAVE", "NINJA_WAVE", "ACTION_PHRASE") var template := "CUSTOM"
@export_range(1, 5, 1) var difficulty := 3
@export_range(0.1, 60.0, 0.1) var duration := 4.0
@export_range(200.0, 30000.0, 10.0) var length := 1800.0
@export_range(0.0, 10.0, 0.05) var start_delay := 0.5
@export var tags: PackedStringArray = []
@export var mirror := false
@export_range(0.5, 1.5, 0.05) var speed_multiplier := 1.0
@export var supports_mirror := false
@export var supports_speed := true
@export var supports_reverse := false
@export var needs_manual_playtest := true
@export_multiline var instruction := ""
@export var parameters: Dictionary = {}
@export var events: Array[PatternEvent] = []
@export var pit_ranges: Array[Vector2] = []
@export var final_pattern: ObstaclePatternData
