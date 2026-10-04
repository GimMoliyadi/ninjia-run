@tool
class_name PatternEvent
extends Resource

enum PreviewKind { SPIKE, DART, CEILING, OTHER, PLATFORM, BLADE_WHEEL, FALLING_BLADE }
@export var obstacle_scene: PackedScene
@export var position_offset := Vector2.ZERO
@export_range(0.0, 60.0, 0.05) var spawn_time := 0.0
@export_range(0.0, 1200.0, 1.0) var speed := 0.0
@export var direction := Vector2.LEFT
@export var optional_parameters: Dictionary = {}
@export var preview_kind := PreviewKind.OTHER
@export var preview_size := Vector2(22, 22)

