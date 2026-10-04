@tool
class_name MapModuleData
extends Resource

@export var module_id := ""
@export var display_name := ""
@export var theme := ""
@export var variant := "A"
@export_range(1, 5, 1) var difficulty := 1
@export var sections: Array[PatternSectionData] = []

