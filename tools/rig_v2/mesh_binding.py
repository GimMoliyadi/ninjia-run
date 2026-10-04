import math

from rig_definition import BONE_BY_NAME, JOINT_BLEND_RADIUS, MESH_SPACING


JOINT_BLEND_FRACTION = 0.42
# 原 38px 窗口小于这些关节内侧衣料的折叠宽度；局部加宽且不与相邻窗口重叠。
JOINT_BLEND_OVERRIDES_SOURCEPX = {"Forearm_L": 120.0, "Shin_L": 145.0, "Shin_R": 115.0, "Foot_R": 85.0}
HIP_BLEND_HEIGHT = 108.0
HIP_BLEND_ROOT_OVERLAP = 12.0
HIP_LATERAL_HALF_WIDTH = 70.0


def smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def rectangular_mesh(bounds: list[int]) -> tuple[list[tuple[float, float]], list[tuple[int, int, int]], int]:
    x, y, width, height = bounds
    columns = max(2, math.ceil(width / MESH_SPACING))
    rows = max(2, math.ceil(height / MESH_SPACING))
    perimeter = [(column, 0) for column in range(columns + 1)]
    perimeter += [(columns, row) for row in range(1, rows + 1)]
    perimeter += [(column, rows) for column in range(columns - 1, -1, -1)]
    perimeter += [(0, row) for row in range(rows - 1, 0, -1)]
    interior = [(column, row) for row in range(1, rows) for column in range(1, columns)]
    grid = perimeter + interior
    indices = {coordinate: index for index, coordinate in enumerate(grid)}
    points = [(x + column * width / columns, y + row * height / rows) for column, row in grid]
    triangles = []
    for row in range(rows):
        for column in range(columns):
            top_left = indices[column, row]
            top_right = indices[column + 1, row]
            bottom_left = indices[column, row + 1]
            bottom_right = indices[column + 1, row + 1]
            triangles.extend(((top_left, top_right, bottom_left), (top_right, bottom_right, bottom_left)))
    return points, triangles, len(interior)


def project_to_chain(point: tuple[float, float], joints: list[tuple[float, float]]) -> tuple[float, list[float]]:
    distances = [0.0]
    nearest_distance = math.inf
    nearest_arc = 0.0
    for start, end in zip(joints, joints[1:]):
        dx, dy = end[0] - start[0], end[1] - start[1]
        length = math.hypot(dx, dy)
        if length == 0:
            raise ValueError("骨骼链包含零长度段")
        amount = max(0.0, min(1.0, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / length**2))
        squared_distance = (point[0] - start[0] - amount * dx)**2 + (point[1] - start[1] - amount * dy)**2
        if squared_distance < nearest_distance:
            nearest_distance = squared_distance
            nearest_arc = distances[-1] + amount * length
        distances.append(distances[-1] + length)
    return nearest_arc, distances


def chain_vertex_weights(point: tuple[float, float], influences: list[str]) -> list[float]:
    if len(influences) == 1:
        return [1.0]
    joints = [BONE_BY_NAME[name].position for name in influences]
    terminal_bone = BONE_BY_NAME[influences[-1]]
    terminal_tip = terminal_bone.tip
    if BONE_BY_NAME[influences[-2]].parent == terminal_bone.name:
        # 逆层级链的父骨 tip 指回前一关节，需反射端点以延续当前链方向。
        terminal_tip = tuple(2.0 * position - tip for position, tip in zip(terminal_bone.position, terminal_tip))
    joints.append(terminal_tip)
    arc, distances = project_to_chain(point, joints)
    weights = [0.0] * len(influences)
    for index in range(1, len(influences)):
        previous_length = distances[index] - distances[index - 1]
        next_length = distances[index + 1] - distances[index] if index + 1 < len(distances) else previous_length
        radius = JOINT_BLEND_OVERRIDES_SOURCEPX.get(influences[index], min(JOINT_BLEND_RADIUS, previous_length * JOINT_BLEND_FRACTION, next_length * JOINT_BLEND_FRACTION))
        if abs(arc - distances[index]) <= radius:
            amount = smoothstep((arc - distances[index] + radius) / (2.0 * radius))
            weights[index - 1], weights[index] = 1.0 - amount, amount
            return weights
    index = sum(arc > boundary for boundary in distances[1:len(influences)])
    weights[index] = 1.0
    return weights


def pelvis_vertex_weights(point: tuple[float, float], influences: list[str]) -> list[float]:
    pelvis = BONE_BY_NAME["Pelvis"].position
    thigh_blend = smoothstep((point[1] - pelvis[1] + HIP_BLEND_ROOT_OVERLAP) / HIP_BLEND_HEIGHT)
    right_blend = smoothstep((point[0] - pelvis[0] + HIP_LATERAL_HALF_WIDTH) / (2.0 * HIP_LATERAL_HALF_WIDTH))
    values = {"Pelvis": 1.0 - thigh_blend, "Thigh_L": thigh_blend * (1.0 - right_blend), "Thigh_R": thigh_blend * right_blend}
    return [values[name] for name in influences]


def mesh_weights(points: list[tuple[float, float]], influences: list[str]) -> list[list[float]]:
    if not influences or any(name not in BONE_BY_NAME for name in influences):
        raise ValueError(f"未知骨骼权重引用：{influences}")
    weight_function = pelvis_vertex_weights if set(influences) == {"Pelvis", "Thigh_L", "Thigh_R"} else chain_vertex_weights
    vertex_weights = [weight_function(point, influences) for point in points]
    if any(abs(sum(weights) - 1.0) > 1e-6 for weights in vertex_weights):
        raise ValueError("网格顶点权重未归一化")
    return [[weights[index] for weights in vertex_weights] for index in range(len(influences))]
