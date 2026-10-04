extends "res://tests/godot/dart_map_playtest.gd"

func _initialize() -> void:
	capture_enabled = true
	call_deferred("run")
