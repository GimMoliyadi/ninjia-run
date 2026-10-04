extends RefCounted

const SoleProbe = preload("res://tests/godot/rig_action_sole_probe.gd")
const CYCLE_SECONDS := 0.33
const SUPPORT_FRACTION := 0.3
const KEY_INTERVALS := 120
const SUBDIVISIONS := 4
const SUPPORT_SAMPLES := 37
const DEFAULT_SPEED := 400.0
const SPEED_TOLERANCE := DEFAULT_SPEED * 0.02
const PIXEL_SCALE := 0.055
const GROUND_TOLERANCE := 1.0
const KEY_TOLERANCE := 0.01
const PHASE_EPSILON := 0.000001
const SWING_MINIMUM := 130.0
const RECOVERY_END_FRACTION := 0.62
const LEAN_LIMITS_DEGREES := Vector2(30.0, 40.0)
const SUPPORT_EXTENSION_MIN := 0.82
const SUPPORT_COMPRESSION_MAX := 0.9
const SUPPORT_EXTENSION_PEAK_MIN := 0.95
const EXTENSION_LIMIT := 0.997
const RECOVERY_BEND_MIN_DEGREES := 65.0
const BLEND_SECONDS := 0.05
const LOAD_FRACTION := 0.4
const LOAD_BEND_CHANGE_MIN := 20.0
const FOREARM_TRAIL_RATIO_MIN := 0.6


static func run(rig: Node2D, skeleton: Skeleton2D, animator: AnimationPlayer, check: Callable) -> void:
	var soles: Array = []
	for side in ["L", "R"]:
		soles.append(SoleProbe.new(rig.get_node("Skin/Leg_%s" % side), skeleton.find_child("Shin_%s" % side, true, false)))
	var animation := animator.get_animation(&"run")
	check.call(animation.track_get_key_count(0) == KEY_INTERVALS + 1, "run 必须使用已验证的 120 个采样区间")
	rig.play_action(&"run")
	animator.advance(BLEND_SECONDS)
	_check_phases(skeleton, animator, soles, check)
	_check_limb_motion(rig, skeleton, animator, check)
	_check_geometry(skeleton, animator, check)
	_check_loading(skeleton, animator, check)
	_check_fixed_arms(skeleton, animation, check)
	_check_support(skeleton, animator, soles, int(KEY_INTERVALS * SUPPORT_FRACTION), "keys", check)
	_check_support(skeleton, animator, soles, SUPPORT_SAMPLES, "interpolated", check)


static func _is_support(phase: float, side: int) -> bool:
	return fposmod(phase - side * 0.5, 1.0) <= SUPPORT_FRACTION + PHASE_EPSILON


static func _phase_errors(phase: float, heights: Array, offset: float, is_key: bool, head_angle: float) -> PackedStringArray:
	var errors := PackedStringArray()
	if absf(head_angle) >= 0.00001:
		errors.append("跑步头部在关键帧及插值帧都应保持稳定")
	var tolerance := KEY_TOLERANCE if is_key else GROUND_TOLERANCE
	for side in range(2):
		var actual: float = heights[side] + offset
		if heights[side] > GROUND_TOLERANCE or actual > GROUND_TOLERANCE:
			errors.append("run 实际 alpha 鞋底不得穿地（资源及 runtime）")
		if _is_support(phase, side):
			if absf(heights[side]) > tolerance or absf(actual) > tolerance:
				errors.append("run 两侧必须在各自非零支撑阶段真实贴地，不能悬空或错相位")
		elif is_key and (heights[side] >= -KEY_TOLERANCE or actual >= -KEY_TOLERANCE):
			errors.append("run 摆脚关键帧必须抬起，不能被 runtime 压回地面")
	if maxf(heights[0], heights[1]) < -KEY_TOLERANCE and not is_zero_approx(offset):
		errors.append("run mixer 校正必须保留实际双脚腾空，不能强制接地")
	return errors


static func _check_phases(skeleton: Skeleton2D, animator: AnimationPlayer, soles: Array, check: Callable) -> void:
	var errors := PackedStringArray()
	var support_keys := [0, 0]
	var flight_keys := [0, 0, 0]
	var maximum_lift := [0.0, 0.0]
	var raw_penetration := 0.0
	var runtime_penetration := 0.0
	var flight_gap := Vector2.ZERO
	var head: Bone2D = skeleton.find_child("Head", true, false)
	for sample in range(KEY_INTERVALS * SUBDIVISIONS + 1):
		var phase := float(sample) / (KEY_INTERVALS * SUBDIVISIONS)
		animator.seek(CYCLE_SECONDS * phase, true)
		var heights := [soles[0].height(), soles[1].height()]
		var offset := skeleton.position.y
		var is_key := sample % SUBDIVISIONS == 0
		for error in _phase_errors(phase, heights, offset, is_key, head.global_rotation - skeleton.global_rotation):
			if not errors.has(error):
				errors.append(error)
		var raw_bottom: float = maxf(heights[0], heights[1])
		raw_penetration = maxf(raw_penetration, raw_bottom)
		runtime_penetration = maxf(runtime_penetration, raw_bottom + offset)
		flight_gap.x = maxf(flight_gap.x, -raw_bottom)
		flight_gap.y = maxf(flight_gap.y, -(raw_bottom + offset))
		for side in range(2):
			maximum_lift[side] = maxf(maximum_lift[side], -heights[side])
			if is_key and sample < KEY_INTERVALS * SUBDIVISIONS and _is_support(phase, side):
				support_keys[side] += 1
		if is_key and sample < KEY_INTERVALS * SUBDIVISIONS:
			flight_keys[0] += int(not _is_support(phase, 0) and not _is_support(phase, 1))
			flight_keys[1] += int(raw_bottom < -KEY_TOLERANCE)
			flight_keys[2] += int(raw_bottom + offset < -KEY_TOLERANCE)
	check.call(errors.is_empty(), "；".join(errors))
	check.call(support_keys[0] >= 2 and support_keys[0] == support_keys[1] and flight_keys[0] > 0, "run 完整周期必须包含左右等长非零交替支撑及腾空")
	check.call(support_keys == [37, 37] and flight_keys[0] == 46, "run 必须每腿支撑 30% 周期，短腾空后换脚，不能长时间悬浮")
	check.call(flight_keys[0] == flight_keys[1] and flight_keys[1] == flight_keys[2], "run 正式资源和 runtime 必须保留全部阶段腾空关键帧")
	check.call(minf(maximum_lift[0], maximum_lift[1]) > SWING_MINIMUM, "run 左右脚都必须有完整摆动抬脚段")
	print("RUN phases support keys=%s, flight expected/resource/runtime=%s, flight peak gap resource/runtime=%s gamepx, penetration resource/runtime=%.5f/%.5f gamepx" % [support_keys, flight_keys, flight_gap * PIXEL_SCALE, raw_penetration * PIXEL_SCALE, runtime_penetration * PIXEL_SCALE])


static func _check_limb_motion(rig: Node2D, skeleton: Skeleton2D, animator: AnimationPlayer, check: Callable) -> void:
	var minimums := [INF, INF]
	var maximums := [-INF, -INF]
	for sample in range(KEY_INTERVALS + 1):
		animator.seek(CYCLE_SECONDS * sample / KEY_INTERVALS, true)
		for side in range(2):
			var shin: Bone2D = skeleton.find_child("Shin_%s" % ["L", "R"][side], true, false)
			minimums[side] = minf(minimums[side], shin.rotation)
			maximums[side] = maxf(maximums[side], shin.rotation)
	for side in range(2):
		check.call(maximums[side] - minimums[side] > 0.3, "run 左右膝都必须有显著屈伸")
	var animation := animator.get_animation(&"run")
	for name in ["Hair_04", "Ribbon_L_03", "CoatBack_L_03"]:
		var bone: Bone2D = skeleton.find_child(name, true, false)
		var path := NodePath("Skeleton2D/%s:rotation" % skeleton.get_path_to(bone))
		var track := animation.find_track(path, Animation.TYPE_VALUE)
		check.call(absf(animation.value_track_interpolate(track, 0.0) - animation.value_track_interpolate(track, CYCLE_SECONDS / 4.0)) > 0.01, "run 缺少附属链变化：%s" % name)


static func _leg_geometry(skeleton: Skeleton2D, side: String) -> Vector2:
	var hip: Vector2 = skeleton.find_child("Thigh_%s" % side, true, false).global_position
	var knee: Vector2 = skeleton.find_child("Shin_%s" % side, true, false).global_position
	var ankle: Vector2 = skeleton.find_child("Foot_%s" % side, true, false).global_position
	var upper := hip.distance_to(knee)
	var lower := knee.distance_to(ankle)
	var span := hip.distance_to(ankle)
	var cosine := clampf((upper * upper + lower * lower - span * span) / (2.0 * upper * lower), -1.0, 1.0)
	return Vector2(span / (upper + lower), 180.0 - rad_to_deg(acos(cosine)))


static func _geometry_errors(lean: Vector2, support_min: Vector2, support_max: Vector2, recovery_bend: Vector2, maximum_extension: float) -> PackedStringArray:
	var errors := PackedStringArray()
	if lean.x < LEAN_LIMITS_DEGREES.x or lean.y > LEAN_LIMITS_DEGREES.y:
		errors.append("run 实际髋颈轴线须明显前倾，不能仍是旧直立姿态")
	if maximum_extension >= EXTENSION_LIMIT:
		errors.append("run 不能数学锁膝或翻膝")
	for side in range(2):
		if support_min[side] < SUPPORT_EXTENSION_MIN or support_max[side] < SUPPORT_EXTENSION_PEAK_MIN:
			errors.append("run 两侧支撑腿必须真正伸展，不能始终蜷腿：%d" % side)
		if support_min[side] > SUPPORT_COMPRESSION_MAX:
			errors.append("run 触地后必须屈膝承重，不能直腿弹跳：%d" % side)
		if recovery_bend[side] < RECOVERY_BEND_MIN_DEGREES:
			errors.append("run 两侧离地后必须有折膝回收：%d" % side)
	return errors


static func _check_geometry(skeleton: Skeleton2D, animator: AnimationPlayer, check: Callable) -> void:
	var lean := Vector2(INF, -INF)
	var support_min := Vector2(INF, INF)
	var support_max := Vector2.ZERO
	var recovery_bend := Vector2.ZERO
	var maximum_extension := 0.0
	var pelvis: Bone2D = skeleton.find_child("Pelvis", true, false)
	var neck: Bone2D = skeleton.find_child("Neck", true, false)
	for sample in range(KEY_INTERVALS):
		var phase := float(sample) / KEY_INTERVALS
		animator.seek(CYCLE_SECONDS * phase, true)
		var axis := neck.global_position - pelvis.global_position
		var angle := rad_to_deg(atan2(axis.x, -axis.y))
		lean = Vector2(minf(lean.x, angle), maxf(lean.y, angle))
		for side in range(2):
			var geometry := _leg_geometry(skeleton, ["L", "R"][side])
			maximum_extension = maxf(maximum_extension, geometry.x)
			if _is_support(phase, side):
				support_min[side] = minf(support_min[side], geometry.x)
				support_max[side] = maxf(support_max[side], geometry.x)
			elif fposmod(phase - side * 0.5, 1.0) <= RECOVERY_END_FRACTION:
				recovery_bend[side] = maxf(recovery_bend[side], geometry.y)
	check.call(_geometry_errors(lean, support_min, support_max, recovery_bend, maximum_extension).is_empty(), "；".join(_geometry_errors(lean, support_min, support_max, recovery_bend, maximum_extension)))
	check.call(not _geometry_errors(Vector2(7.9, 10.54), support_min, support_max, recovery_bend, maximum_extension).is_empty(), "旧直立轴线反例必须失败")
	check.call(not _geometry_errors(lean, Vector2(0.7, 0.8), Vector2(0.8452, 0.9627), recovery_bend, maximum_extension).is_empty(), "旧左腿始终蜷曲反例必须失败")
	check.call(not _geometry_errors(lean, support_min, support_max, Vector2(30.0, 30.0), maximum_extension).is_empty(), "只有直腿而没有回收阶段的反例必须失败")
	print("RUN geometry lean=%.3f..%.3f degrees, support extension min/max=%s/%s, recovery bend peak=%s degrees" % [lean.x, lean.y, support_min, support_max, recovery_bend])


static func _check_loading(skeleton: Skeleton2D, animator: AnimationPlayer, check: Callable) -> void:
	for side in range(2):
		var side_name: String = ["L", "R"][side]
		var bends := PackedFloat32Array()
		for phase in [0.0, SUPPORT_FRACTION * LOAD_FRACTION, SUPPORT_FRACTION]:
			animator.seek(CYCLE_SECONDS * (side * 0.5 + phase), true)
			bends.append(_leg_geometry(skeleton, side_name).y)
		check.call(bends[1] > bends[0] + LOAD_BEND_CHANGE_MIN and bends[1] > bends[2] + LOAD_BEND_CHANGE_MIN, "run 必须先屈膝缓冲再蹬伸，不能直腿弹跳：%s" % side_name)
		var hip: Bone2D = skeleton.find_child("Thigh_%s" % side_name, true, false)
		var knee: Bone2D = skeleton.find_child("Shin_%s" % side_name, true, false)
		var ankle: Bone2D = skeleton.find_child("Foot_%s" % side_name, true, false)
		check.call(knee.global_position.x < hip.global_position.x, "run 蹬地末段必须向后伸展：%s" % side_name)
		animator.seek(CYCLE_SECONDS * (side * 0.5 + 0.4), true)
		check.call(ankle.global_position.x < hip.global_position.x, "run 脚跟应先在髋后回收，不得在身前踢腿：%s" % side_name)
		animator.seek(CYCLE_SECONDS * fposmod(side * 0.5 + 0.7, 1.0), true)
		check.call(knee.global_position.x > hip.global_position.x, "run 回收后膝应前送准备落脚：%s" % side_name)


static func _check_fixed_arms(skeleton: Skeleton2D, animation: Animation, check: Callable) -> void:
	for side in ["L", "R"]:
		var pelvis: Bone2D = skeleton.find_child("Pelvis", true, false)
		var elbow: Bone2D = skeleton.find_child("Forearm_%s" % side, true, false)
		var wrist: Bone2D = skeleton.find_child("Hand_%s" % side, true, false)
		var forearm := wrist.global_position - elbow.global_position
		check.call(wrist.global_position.x < pelvis.global_position.x and forearm.x < -FOREARM_TRAIL_RATIO_MIN * forearm.length(), "run 前臂和手腕须后掠，不能固定在身体前下方：%s" % side)
		for joint in ["Clavicle", "UpperArm", "Forearm", "Hand"]:
			var bone: Bone2D = skeleton.find_child("%s_%s" % [joint, side], true, false)
			var path := NodePath("Skeleton2D/%s:rotation" % skeleton.get_path_to(bone))
			var track := animation.find_track(path, Animation.TYPE_VALUE)
			var first: float = animation.track_get_key_value(track, 0)
			var maximum_delta := 0.0
			for key in range(animation.track_get_key_count(track)):
				maximum_delta = maxf(maximum_delta, absf(float(animation.track_get_key_value(track, key)) - first))
			check.call(maximum_delta < 0.00001, "run 手臂须随胸腔固定，不能有独立摆臂/屈肘/甩腕：%s" % bone.name)


static func _check_support(skeleton: Skeleton2D, animator: AnimationPlayer, soles: Array, samples: int, label: String, check: Callable) -> void:
	var minimums := Vector2(INF, INF)
	var maximums := Vector2(-INF, -INF)
	var height_errors := Vector2.ZERO
	var step_seconds := CYCLE_SECONDS * SUPPORT_FRACTION / samples
	for side in range(2):
		var previous := Vector2.ZERO
		for sample in range(samples + 1):
			animator.seek(side * CYCLE_SECONDS / 2.0 + sample * step_seconds, true)
			var raw: Vector2 = soles[side].contact()
			var actual := raw + skeleton.position
			var contacts := Vector2(raw.x, actual.x)
			height_errors.x = maxf(height_errors.x, absf(soles[side].height()) * PIXEL_SCALE)
			height_errors.y = maxf(height_errors.y, absf(soles[side].height() + skeleton.position.y) * PIXEL_SCALE)
			if sample > 0:
				var speeds := (previous - contacts) * PIXEL_SCALE / step_seconds
				minimums = minimums.min(speeds)
				maximums = maximums.max(speeds)
			previous = contacts
	for mode in range(2):
		check.call(absf(minimums[mode] - DEFAULT_SPEED) <= SPEED_TOLERANCE and absf(maximums[mode] - DEFAULT_SPEED) <= SPEED_TOLERANCE, "run %s 支撑段 alpha 鞋底后扫必须匹配默认400（误差≤2%%），资源/runtime %d" % [label, mode])
		check.call(height_errors[mode] <= GROUND_TOLERANCE * PIXEL_SCALE, "run %s 支撑段实际鞋底必须贴地，资源/runtime %d" % [label, mode])
	print("RUN %s support sweep resource=%.5f..%.5f runtime=%.5f..%.5f gamepx/s, sole y error resource/runtime=%s gamepx, tolerance=%.1f; NOT absolute no-slip" % [label, minimums.x, maximums.x, minimums.y, maximums.y, height_errors, SPEED_TOLERANCE])
