@tool
extends Node

const LEGACY_SKELETON_PATH := "Orientation/ActionPivot/Body/VisualRoot_V1/RunSkeleton"

@export_enum("V1：旧视觉备份", "V2：新 Rig 完整动作链") var visual_version: int = 1:
	set(value):
		visual_version = clampi(value, 0, 1)
		if is_node_ready():
			_apply_version()


func _ready() -> void:
	_apply_version()


func _apply_version() -> void:
	var legacy: Node2D = get_parent().get_node("PlayerVisual")
	var visual_v2: Node2D = get_parent().get_node("PlayerVisual_V2")
	var show_v2 := visual_version == 1
	if Engine.is_editor_hint():
		legacy.visible = not show_v2
		legacy.process_mode = Node.PROCESS_MODE_DISABLED if show_v2 else Node.PROCESS_MODE_INHERIT
		legacy.set("visual_enabled", not show_v2)
		legacy.get_node(LEGACY_SKELETON_PATH).visible = not show_v2
	else:
		legacy.call("set_visual_enabled", not show_v2)
	visual_v2.call("set_visual_enabled", show_v2)
