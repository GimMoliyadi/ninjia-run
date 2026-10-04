extends Line2D

# --- 飘带基础配置 ---
@export var points_count: int = 20           # 飘带节点数
@export var segment_length: float = 7.5        # 每一节的长度（总长约 150 像素）

var points_world: Array[Vector2] = []
var player_node: CharacterBody2D

func _ready() -> void:
	process_priority = 1
	# 1. 核心关键：脱离父节点旋转缩放影响，绝对世界坐标运算
	top_level = true
	z_index = 2
	
	# 2. 智能向上寻亲：无论当前节点嵌套在多少层子目录下，都能一直往上找到真正的 Player！
	player_node = find_player_node()

	# 3. 程序化自动配置丝绸流光外观
	default_color = Color(0.15, 0.95, 0.85, 0.95) # 青莲仙剑灵气色
	width = 6.5
	
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.15))
	width_curve = curve
	
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	antialiased = true
	
	# 4. 初始化点位置
	var start_anchor = get_current_anchor_pos()
	points_world.clear()
	for i in range(points_count):
		points_world.append(start_anchor - Vector2(i * segment_length, 0.0))

func _process(_delta: float) -> void:
	# 如果还没有找到玩家，再次尝试寻找
	if not is_instance_valid(player_node):
		player_node = find_player_node()
		if not is_instance_valid(player_node):
			return

	# 1. 实时更新头部根部锚点
	var anchor_pos = get_current_anchor_pos()
	points_world[0] = anchor_pos

	# 2. 核心算法：基于真实位移惯性的无角度约束链条
	for i in range(1, points_count):
		var prev = points_world[i - 1]
		var current = points_world[i]

		var diff = current - prev
		if diff.length_squared() < 0.001:
			diff = Vector2(-1.0, 0.0)

		# 迎风偏置（身后 -X）
		var dir = diff.normalized()
		dir.x = minf(dir.x, -0.3)
		dir = dir.normalized()

		points_world[i] = prev + dir * segment_length

	# 3. 将世界坐标转换到 Line2D 本地坐标系输出渲染
	clear_points()
	for pt in points_world:
		add_point(to_local(pt))

func reset_chain() -> void:
	if not is_instance_valid(player_node):
		player_node = find_player_node()
	var start_anchor := get_current_anchor_pos()
	points_world.clear()
	clear_points()
	for i in range(points_count):
		var point := start_anchor - Vector2(i * segment_length, 0.0)
		points_world.append(point)
		add_point(to_local(point))

# 向上逐级遍历寻找真正的 CharacterBody2D 节点
func find_player_node() -> CharacterBody2D:
	var curr: Node = get_parent()
	while curr != null:
		if curr is CharacterBody2D:
			return curr
		curr = curr.get_parent()
	return null

func get_current_anchor_pos() -> Vector2:
	return get_parent().global_position
