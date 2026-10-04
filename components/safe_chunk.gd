class_name SafeChunk
extends "res://components/chunk.gd"

const COIN_SHIFT_LIMIT := 100.0
const COIN_ARC_STEP := 18.0

var layout_seed := 0

func _ready() -> void:
	if layout_seed != 0:
		var random := RandomNumberGenerator.new()
		random.seed = layout_seed
		var shift := random.randf_range(-COIN_SHIFT_LIMIT, COIN_SHIFT_LIMIT)
		var arc_height := random.randi_range(0, 2) * COIN_ARC_STEP
		var coins: Array[Coin] = []
		for child in get_children():
			if child is Coin:
				coins.append(child)
		for index in coins.size():
			var progress := float(index) / float(coins.size() - 1)
			coins[index].position += Vector2(shift, -arc_height * sin(PI * progress))
	super._ready()
