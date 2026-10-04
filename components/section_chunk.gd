class_name SectionChunk
extends "res://components/chunk.gd"

const Section := preload("res://patterns/pattern_section.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const Modifier := preload("res://patterns/pattern_modifier.gd")

@export_file("*.tres") var section_data_path := ""
@export var route_theme := ""
@export var section_variant := "A"
@export_range(1, 5, 1) var section_difficulty := 1
@export var section_start_input_clearance := 0.9

@onready var entry: Marker2D = $Entry
@onready var exit: Marker2D = $Exit

var section: PatternSection
var section_data: PatternSectionData
var build_ready := false

func _ready() -> void:
	super._ready()
	section_data = load(section_data_path)
	if section_data == null:
		push_error("%s: 找不到 Section 数据 %s" % [name, section_data_path])
		return
	section = Section.new()
	section.name = "Section"
	section.data = section_data
	section.position = Vector2(entry.position.x + section_start_input_clearance * Motion.RUN_SPEED, entry.position.y)
	add_child(section)
	var clearance_width := section_start_input_clearance * Motion.RUN_SPEED
	section.add_ground(-clearance_width, clearance_width)
	section.build(section_data.entries, _find_player(), section_difficulty, Modifier.Kind.NORMAL)
	exit.position = Vector2(section.position.x + section.section_length, entry.position.y)
	for issue in section.all_issues():
		push_error("%s: Pattern 参数问题 — %s" % [name, issue])
	build_ready = true

func _find_player() -> Node2D:
	var owner_node := get_parent()
	if owner_node != null:
		var sibling := owner_node.get_node_or_null("Player")
		if sibling is Node2D:
			return sibling
	return null

func advance(delta: float, player: Node2D) -> void:
	if section == null:
		return
	for runner in section.runners:
		if runner.player == null:
			runner.player = player
	section.advance(delta, player)

func debug_info() -> Dictionary:
	if section == null:
		return {}
	return {
		"segment": route_theme,
		"route_theme": route_theme,
		"section": section_data.display_name if not section_data.display_name.is_empty() else section_data.section_name,
		"variant": section_variant,
		"difficulty": section_difficulty,
		"template_sequence": section.template_sequence(),
		"issues": section.all_issues(),
	}

func debug_info_at(global_x: float) -> Dictionary:
	if section == null:
		return {}
	var info := section.info_at(global_x)
	if not info.is_empty():
		info["route_theme"] = route_theme
		info["variant"] = section_variant
	return info
