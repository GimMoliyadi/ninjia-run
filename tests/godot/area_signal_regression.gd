extends SceneTree

const WORLD_SCENE := preload("res://test_world.tscn")
const SINGLE_JUMP_SEGMENT := preload("res://scenes/segment_single_jump.tscn")

var damage_signal_received := false
var coin_signal_received := false

func _initialize() -> void:
	var world: Variant = WORLD_SCENE.instantiate()
	world.route_seed = 20260909
	root.add_child(world)
	await physics_frame
	await physics_frame
	var segment: Node2D = SINGLE_JUMP_SEGMENT.instantiate()
	segment.global_position = Vector2(10000.0, 0.0)
	root.add_child(segment)
	var spike: Area2D = segment.get_node("SpikeA")
	var coin: Area2D = segment.get_node("CoinA")
	spike.player_contact.connect(on_spike_contact)
	coin.collected.connect(on_coin_collected)

	world.player.global_position = coin.global_position
	await physics_frame
	await physics_frame
	if not coin_signal_received:
		printerr("Area signal regression: Coin did not emit collected after player overlap.")
		quit(1)
		return

	world.player.global_position = Vector2(spike.global_position.x + 12.0, 460.0)
	await physics_frame
	await physics_frame
	if not damage_signal_received:
		printerr("Area signal regression: Spike did not emit player_contact after player overlap.")
		quit(1)
		return
	print("Area signal regression passed: pickups and hazards notify through Area2D signals.")
	quit(0)

func on_spike_contact(_player: Node2D, _damage: float) -> void:
	damage_signal_received = true

func on_coin_collected(_player: Node2D, _score: int, _energy: float) -> void:
	coin_signal_received = true
