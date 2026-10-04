class_name Coin
extends Area2D

signal collected(player: Node2D, score: int, energy: float)

@export var score := 10
@export var energy := 2.0

func _ready() -> void:
	body_entered.connect(on_body_entered)

func on_body_entered(body: Node2D) -> void:
	if not body.has_method("take_damage"):
		return
	collected.emit(body, score, energy)
	queue_free()
