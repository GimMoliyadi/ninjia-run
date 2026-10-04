extends "res://tests/jump_map/input_driver.gd"

const Layout := preload("res://patterns/platform_dart_wave_layout.gd")
var landing_darts: Array[float] = []
var slides := 0

func configure(module: Node2D, target: Node2D) -> void:
	player = target
	for section in module.sections:
		for runner in section.runners:
			for event in runner.plan.events:
				if event.obstacle_scene != Layout.JumpWave.PILLAR:
					continue
				var x: float = runner.global_position.x + event.position_offset.x
				obstacles.append({"x": x, "end": x + event.preview_size.x,
					"height": event.preview_size.y, "pillar": true})
				landing_darts.append(x + event.preview_size.x * Layout.LANDING_DART_RATIO)
	obstacles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.x < b.x)
	landing_darts.sort()

func advance() -> void:
	var speed: float = player.run_speed + player.boost_speed
	for encounter in landing_darts:
		var distance: float = encounter - player.global_position.x
		if distance < -Motion.BODY_SIZE.x:
			continue
		if distance <= speed * 0.18 and player.is_on_floor() and not player.is_sliding():
			release()
			press("slide")
			slides += 1
			return
		break
	super.advance()
