class_name Chunk
extends Node2D

signal player_contact(player: Node2D, damage: float)
signal coin_collected(score: int, energy: float)

func _ready() -> void:
	for node in find_children("*", "", true, false):
		if node.has_signal("player_contact"):
			node.connect("player_contact", relay_player_contact)
		if node.has_signal("collected"):
			node.connect("collected", relay_coin_collected)

func relay_player_contact(player: Node2D, damage: float) -> void:
	player_contact.emit(player, damage)

func relay_coin_collected(_player: Node2D, score: int, energy: float) -> void:
	coin_collected.emit(score, energy)
