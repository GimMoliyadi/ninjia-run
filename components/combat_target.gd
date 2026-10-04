extends RefCounted

static func available(target: Variant) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.is_in_group("destructible")

static func center(target: Node2D) -> Vector2:
	return target.get_node("CollisionShape2D").global_position

static func swept_hit(target: Node2D, start: Vector2, finish: Vector2, radius: float) -> bool:
	var collider: CollisionShape2D = target.get_node("CollisionShape2D")
	return swept_shape(collider, start, finish, radius)

static func swept_shape(collider: CollisionShape2D, start: Vector2, finish: Vector2, radius: float) -> bool:
	if collider.shape is CircleShape2D:
		var closest := Geometry2D.get_closest_point_to_segment(collider.global_position, start, finish)
		return closest.distance_to(collider.global_position) <= radius + collider.shape.radius
	var half_size: Vector2 = collider.shape.size * collider.global_scale.abs() / 2.0
	var bounds := Rect2(collider.global_position - half_size, half_size * 2.0).grow(radius)
	if bounds.has_point(start) or bounds.has_point(finish):
		return true
	var corners := [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	for index in 4:
		if Geometry2D.segment_intersects_segment(start, finish, corners[index], corners[(index + 1) % 4]) != null:
			return true
	return false

static func destroy(target: Node2D) -> bool:
	if not available(target):
		return false
	target.remove_from_group("destructible")
	target.hide()
	target.queue_free()
	return true
