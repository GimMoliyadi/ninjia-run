extends SceneTree

const Generator := preload("res://components/rhythm_route_generator.gd")
const World := preload("res://test_world.tscn")
const COIN_RADIUS := 14.0
const CoinLayout := preload("res://patterns/coin_trajectory_layout.gd")
const JumpWave := preload("res://patterns/jump_wave_layout.gd")
const Motion := preload("res://patterns/player_motion_profile.gd")
const Dart := preload("res://components/dart.gd")

const MAP_KINDS: Array[int] = [
	Generator.ChunkKind.DARTS,
	Generator.ChunkKind.JUMP_MAP,
	Generator.ChunkKind.ROPE_MAP,
	Generator.ChunkKind.PLATFORM_DART_MAP,
	Generator.ChunkKind.NINJA_MAP,
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var first_seed := -1
	var second_seed := -1
	var first_index := -1
	var orders := {}
	var openings := {}
	var dart_opening_seed := -1
	for seed in range(20260900, 20260930):
		var route: Array[int] = Generator.new(seed).build_cycle(0)
		var map_order: Array[int] = []
		for kind in route:
			if Generator.ACTION_COMBINATIONS.has(kind):
				map_order.append(kind)
		if map_order.size() != Generator.ACTION_COMBINATIONS.size() * Generator.GROUP_COUNT:
			printerr("完整地图没有按预期进入循环")
			quit(1)
			return
		for kind in Generator.ACTION_COMBINATIONS:
			if route.count(kind) != Generator.GROUP_COUNT:
				printerr("完整地图出现次数不正确：", kind)
				quit(1)
				return
		orders[str(map_order)] = true
		openings[route[1]] = true
		if route[1] == Generator.ChunkKind.DART_JUMP_SLIDE_PHRASE and dart_opening_seed < 0:
			dart_opening_seed = seed
		var practice_order := practice_route(seed)
		var jump_index := practice_order.find(Generator.ChunkKind.JUMP_MAP)
		if first_seed < 0:
			first_seed = seed
			first_index = jump_index
		elif jump_index != first_index and second_seed < 0:
			second_seed = seed
	if orders.size() < 3 or openings.size() != Generator.ACTION_COMBINATIONS.size() or second_seed < 0:
		printerr("不同种子没有生成足够的地图排列")
		quit(1)
		return
	var first := inspect_world(first_seed)
	var second := inspect_world(second_seed)
	var repeated := inspect_world(first_seed)
	var passed: bool = first.valid and second.valid and repeated.valid
	passed = passed and first.coin_count == second.coin_count
	passed = passed and first.jump_coin_x != second.jump_coin_x
	passed = passed and first.jump_coin_layout != second.jump_coin_layout
	passed = passed and absf(first.safe_coin_x - second.safe_coin_x) > 1.0
	passed = passed and first.safe_coin_x == repeated.safe_coin_x
	passed = passed and first.jump_coin_relative_x == repeated.jump_coin_relative_x
	passed = passed and first.jump_coin_layout == repeated.jump_coin_layout
	for seed in range(20260900, 20260910):
		var sample := inspect_world(seed)
		if not sample.valid:
			printerr("种子 %d 的金币轨迹不安全或不连续" % seed)
			passed = false
	if not passed:
		printerr("金币轨迹回归失败：", first.valid, " / ", second.valid, "，金币数 ", first.coin_count, " / ", second.coin_count)
	else:
		print("Random route and coin regression passed: %d orders, %d openings, dart opening seed %d, %d coins, Jump coin %.0f → %.0f" % [orders.size(), openings.size(), dart_opening_seed, first.coin_count, first.jump_coin_x, second.jump_coin_x])
	quit(0 if passed else 1)

func practice_route(seed: int) -> Array[int]:
	var route: Array[int] = [Generator.ChunkKind.SAFE]
	var choices: Array[int] = MAP_KINDS.duplicate()
	var random := RandomNumberGenerator.new()
	random.seed = seed
	for index in range(choices.size() - 1, 0, -1):
		var choice := random.randi_range(0, index)
		var selected := choices[index]
		choices[index] = choices[choice]
		choices[choice] = selected
	route.append_array(choices.slice(0, 3))
	route.append(Generator.ChunkKind.REST)
	route.append_array(choices.slice(3))
	return route

func inspect_world(seed: int) -> Dictionary:
	var world := World.instantiate()
	world.route_seed = seed
	root.add_child(world)
	# 完整地图不再进入正式路线；仍逐张走真实生成器检查练习资源的金币安全。
	var route: Array[int] = practice_route(seed)
	world.restart_run()
	for chunk in world.active_chunks:
		chunk.free()
	world.active_chunks.clear()
	world.next_chunk_entry = Vector2(0, Motion.GROUND_Y)
	world.route_steps = route
	world.route_step_index = 0
	world.route_cycle = 1
	while world.active_chunks.size() < route.size():
		if not world.spawn_chunk():
			world.free()
			return {"valid": false}
	var coin_count := 0
	var jump_coin_x := INF
	var jump_coin_relative_x := INF
	var safe_coin_x := INF
	var valid := true
	var map_coin_counts := {}
	var jump_coin_layout := PackedVector2Array()
	for index in route.size():
		var chunk: Node2D = world.active_chunks[index]
		if index > 0:
			valid = valid and chunk.get_node("Entry").global_position.is_equal_approx(world.active_chunks[index - 1].get_node("Exit").global_position)
		if route[index] == Generator.ChunkKind.SAFE:
			safe_coin_x = chunk.get_node("CoinA").global_position.x
		if not chunk is MapModuleChunk:
			continue
		valid = valid and chunk.debug_info().issues.is_empty()
		if route[index] == Generator.ChunkKind.JUMP_MAP:
			valid = valid and jump_coin_trails_are_safe(chunk)
		elif route[index] == Generator.ChunkKind.ROPE_MAP:
			valid = valid and rope_coins_guide_safe_sides(chunk)
		elif route[index] == Generator.ChunkKind.PLATFORM_DART_MAP:
			valid = valid and jump_coin_trails_are_safe(chunk)
			valid = valid and coins_follow_enemy(chunk.sections[0], "NinjaMap_Wave07_Pursuit")
		elif route[index] == Generator.ChunkKind.NINJA_MAP:
			valid = valid and coins_follow_enemy(chunk.sections[2], "NinjaMap_Wave08_Finale")
		for section in chunk.sections:
			for child in section.get_children():
				if not child is Coin:
					continue
				coin_count += 1
				map_coin_counts[route[index]] = map_coin_counts.get(route[index], 0) + 1
				if route[index] == Generator.ChunkKind.JUMP_MAP and jump_coin_x == INF:
					jump_coin_x = child.global_position.x
					jump_coin_relative_x = child.global_position.x - chunk.get_node("Entry").global_position.x
				if route[index] == Generator.ChunkKind.JUMP_MAP:
					jump_coin_layout.append(child.global_position - chunk.get_node("Entry").global_position)
	for kind in MAP_KINDS:
		valid = valid and map_coin_counts.get(kind, 0) > 0
	var result := {"valid": valid and jump_coin_x != INF and safe_coin_x != INF, "coin_count": coin_count,
		"jump_coin_x": jump_coin_x, "jump_coin_relative_x": jump_coin_relative_x,
		"jump_coin_layout": jump_coin_layout}
	result["safe_coin_x"] = safe_coin_x
	world.free()
	return result

func coins_follow_enemy(section: Node2D, wave_name: String) -> bool:
	var enemy_end := INF
	var last_coin := -INF
	for runner in section.runners:
		if runner.name == wave_name:
			enemy_end = runner.global_position.x + float(runner.plan.length)
	for child in section.get_children():
		if child is Coin:
			last_coin = maxf(last_coin, child.global_position.x)
	return enemy_end != INF and last_coin > enemy_end

func jump_coin_trails_are_safe(chunk: MapModuleChunk) -> bool:
	for child in chunk.get_children():
		if child is Coin:
			return false
	for section in chunk.sections:
		var coins: Array[Coin] = []
		for child in section.get_children():
			if child is Coin:
				coins.append(child)
		for runner in section.runners:
			if not runner.plan.get("jump_layout", false):
				continue
			for event in runner.plan.events:
				if event.preview_kind == PatternEvent.PreviewKind.DART:
					continue
				var obstacle := Rect2(
					Vector2(runner.position.x + event.position_offset.x, -event.preview_size.y),
					event.preview_size
				)
				var nearby_x: Array[float] = []
				var platform_x: Array[float] = []
				for coin in coins:
					if CoinLayout.distance_to_obstacle(coin.position, obstacle) < CoinLayout.MINIMUM_COIN_CLEARANCE:
						printerr("金币过近：", chunk.name, " ", runner.name, " ", coin.position)
						return false
					if coin.position.x >= obstacle.position.x - CoinLayout.SPIKE_APPROACH and coin.position.x <= obstacle.end.x + CoinLayout.SPIKE_APPROACH:
						nearby_x.append(coin.position.x)
					if coin.position.x >= obstacle.position.x and coin.position.x <= obstacle.end.x and coin.position.y + COIN_RADIUS < obstacle.position.y:
						platform_x.append(coin.position.x)
				if event.obstacle_scene == JumpWave.PILLAR and not has_continuous_group(platform_x):
					printerr("平台金币不足：", chunk.name, " ", runner.name, " ", platform_x)
					return false
				if event.obstacle_scene == JumpWave.SPIKES and not has_continuous_group(nearby_x):
					printerr("地刺轨迹不足：", chunk.name, " ", runner.name, " ", nearby_x)
					return false
	return true

func rope_coins_guide_safe_sides(chunk: MapModuleChunk) -> bool:
	var top_x: Array[float] = []
	var bottom_x: Array[float] = []
	for section in chunk.sections:
		var darts: Array[Vector2] = []
		var spikes: Array[Rect2] = []
		for runner in section.runners:
			if not runner.plan.has("rope_actions"):
				continue
			for event in runner.plan.events:
				if event.preview_kind == PatternEvent.PreviewKind.DART:
					var approach: float = (event.position_offset.x - Motion.RUN_SPEED * event.spawn_time) / (Motion.RUN_SPEED + event.speed)
					darts.append(Vector2(runner.position.x + Motion.RUN_SPEED * (event.spawn_time + approach), event.position_offset.y))
				elif event.preview_kind == PatternEvent.PreviewKind.SPIKE:
					var y_scale: float = event.optional_parameters.get("scale", Vector2.ONE).y
					spikes.append(Rect2(
						Vector2(runner.position.x + event.position_offset.x, -event.preview_size.y if y_scale > 0.0 else 0.0),
						event.preview_size
					))
		for child in section.get_children():
			if not child is Coin:
				continue
			if child.position.y <= -CoinLayout.PLATFORM_COIN_HEIGHT:
				top_x.append(child.global_position.x)
			elif child.position.y >= CoinLayout.PLATFORM_COIN_HEIGHT:
				bottom_x.append(child.global_position.x)
			for spike in spikes:
				if CoinLayout.distance_to_obstacle(child.position, spike) < CoinLayout.MINIMUM_COIN_CLEARANCE:
					return false
			for dart in darts:
				if child.position.distance_to(dart) < CoinLayout.MINIMUM_COIN_CLEARANCE + Dart.RADIUS:
					return false
	return has_continuous_group(top_x) and has_continuous_group(bottom_x)

func has_continuous_group(positions: Array[float]) -> bool:
	if positions.size() < 3:
		return false
	positions.sort()
	var run_length := 1
	for index in range(1, positions.size()):
		if positions[index] - positions[index - 1] <= CoinLayout.TRAIL_SPACING * 1.8:
			run_length += 1
			if run_length >= 3:
				return true
		else:
			run_length = 1
	return false
