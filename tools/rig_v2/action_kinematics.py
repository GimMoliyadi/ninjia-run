import math
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from mesh_binding import mesh_weights, rectangular_mesh
from rig_definition import BONES, BONE_BY_NAME, MESH_SPACING, SOURCE_ORIGIN

GROUND_Y = SOURCE_ORIGIN[1]
COM_REST_Y = BONE_BY_NAME["COM"].position[1] - BONE_BY_NAME["Root"].position[1]
CONTACT_ALPHA_THRESHOLD = 16
SOLE_BAND_DEPTH = 2.0
IK_REACH_EPSILON = 1e-7
SOLE_SOLVE_TOLERANCE = 1e-6
SOLE_SOLVE_ITERATIONS = 12
SOLE_DERIVATIVE_STEP = 0.01
SOLE_DERIVATIVE_EPSILON = 1e-8

Point = tuple[float, float]


@dataclass(frozen=True)
class FootGoal:
    x: float
    y: float
    angle: float = 0.0
    toe: float = 0.0


@dataclass(frozen=True)
class Pose:
    rotations: dict[str, float]
    com_position: Point
    feet: tuple[FootGoal, FootGoal]


@dataclass(frozen=True)
class BootProfile:
    side: str
    contact: Point
    influences: tuple[str, ...]
    vertices: tuple[Point, ...]
    weights: tuple[tuple[float, ...], ...]
    samples: tuple[tuple[tuple[int, int, int], tuple[float, float, float]], ...]


def rotate(point: Point, angle: float) -> Point:
    cosine, sine = math.cos(angle), math.sin(angle)
    return point[0] * cosine - point[1] * sine, point[0] * sine + point[1] * cosine


def subtract(first: Point, second: Point) -> Point:
    return first[0] - second[0], first[1] - second[1]


def forward_transforms(rotations: dict[str, float], com_position: Point) -> dict[str, tuple[Point, float]]:
    transforms = {}
    for bone in BONES:
        parent_position, parent_angle = transforms[bone.parent] if bone.parent else (SOURCE_ORIGIN, 0.0)
        rest_parent = BONE_BY_NAME[bone.parent].position if bone.parent else SOURCE_ORIGIN
        local_position = com_position if bone.name == "COM" else subtract(bone.position, rest_parent)
        offset = rotate(local_position, parent_angle)
        position = parent_position[0] + offset[0], parent_position[1] + offset[1]
        transforms[bone.name] = position, parent_angle + rotations[bone.name]
    return transforms


def set_segment_direction(rotations: dict[str, float], com_position: Point, start: str, end: str, direction: float) -> None:
    parent = BONE_BY_NAME[start].parent
    parent_angle = forward_transforms(rotations, com_position)[parent][1]
    segment = subtract(BONE_BY_NAME[end].position, BONE_BY_NAME[start].position)
    rotations[start] = direction - math.atan2(segment[1], segment[0]) - parent_angle


def boot_contour(image: Image.Image, source_offset: Point, knee_y: float) -> list[Point]:
    alpha = image.getchannel("A")
    pixels = alpha.load()
    contour = set()
    for y in range(image.height):
        if y + source_offset[1] < knee_y:
            continue
        row = [x for x in range(image.width) if pixels[x, y] >= CONTACT_ALPHA_THRESHOLD]
        if row:
            contour.update(((row[0], y), (row[-1], y)))
    for x in range(image.width):
        column = [y for y in range(image.height) if y + source_offset[1] >= knee_y and pixels[x, y] >= CONTACT_ALPHA_THRESHOLD]
        if column:
            contour.update(((x, column[0]), (x, column[-1])))
    if not contour:
        raise ValueError("靴纹理没有可用的 alpha 轮廓")
    return [(x + source_offset[0] + 0.5, y + source_offset[1] + 0.5) for x, y in sorted(contour)]


def mesh_sample(point: Point, bounds: list[int], indices: dict[Point, int]) -> tuple[tuple[int, int, int], tuple[float, float, float]]:
    x, y, width, height = bounds
    columns, rows = max(2, math.ceil(width / MESH_SPACING)), max(2, math.ceil(height / MESH_SPACING))
    grid_x, grid_y = (point[0] - x) * columns / width, (point[1] - y) * rows / height
    column, row = min(columns - 1, int(grid_x)), min(rows - 1, int(grid_y))
    u, v = grid_x - column, grid_y - row
    corners = ((column, row), (column + 1, row), (column, row + 1), (column + 1, row + 1))
    if u + v <= 1.0:
        return tuple(indices[corner] for corner in corners[:3]), (1.0 - u - v, u, v)
    return tuple(indices[corners[index]] for index in (1, 3, 2)), (1.0 - v, u + v - 1.0, 1.0 - u)


def load_boot_profiles(project_root: Path, regions: list[dict]) -> tuple[BootProfile, BootProfile]:
    profiles = []
    for side in ("L", "R"):
        region = next(region for region in regions if region["name"] == f"Leg_{side}")
        with Image.open(project_root / region["texture"].removeprefix("res://")) as image:
            points = boot_contour(image, tuple(region["bounds"][:2]), BONE_BY_NAME[f"Shin_{side}"].position[1])
        bottom = max(point[1] for point in points)
        sole = [point for point in points if point[1] >= bottom - SOLE_BAND_DEPTH]
        contact = sum(point[0] for point in sole) / len(sole), bottom
        vertices, _, _ = rectangular_mesh(region["bounds"])
        x, y, width, height = region["bounds"]
        columns, rows = max(2, math.ceil(width / MESH_SPACING)), max(2, math.ceil(height / MESH_SPACING))
        indices = {(round((point[0] - x) * columns / width), round((point[1] - y) * rows / height)): index for index, point in enumerate(vertices)}
        influences = tuple(region["influences"])
        weights = mesh_weights(vertices, list(influences))
        profiles.append(BootProfile(side, contact, influences, tuple(vertices), tuple(tuple(values) for values in zip(*weights)), tuple(mesh_sample(point, region["bounds"], indices) for point in points)))
    return tuple(profiles)


def boot_height(profile: BootProfile, transforms: dict[str, tuple[Point, float]]) -> float:
    vertex_heights = []
    for point, weights in zip(profile.vertices, profile.weights):
        height = 0.0
        for name, weight in zip(profile.influences, weights):
            if weight == 0.0:
                continue
            position, angle = transforms[name]
            offset = rotate(subtract(point, BONE_BY_NAME[name].position), angle)
            height += weight * (position[1] + offset[1])
        vertex_heights.append(height)
    # 与 Polygon2D 一样先蒙皮顶点，再在三角形内部插值，不能用像素处权重近似。
    return max(sum(vertex_heights[index] * weight for index, weight in zip(indices, barycentric)) for indices, barycentric in profile.samples)


def solve_two_bone_leg(rotations: dict[str, float], com_position: Point, side: str, ankle: Point, goal: FootGoal, slack: float = 0.0) -> None:
    transforms = forward_transforms(rotations, com_position)
    hip, _ = transforms[f"Thigh_{side}"]
    parent_angle = transforms["Pelvis"][1]
    thigh = BONE_BY_NAME[f"Thigh_{side}"].position
    knee = BONE_BY_NAME[f"Shin_{side}"].position
    foot = BONE_BY_NAME[f"Foot_{side}"].position
    upper_vector, lower_vector = subtract(knee, thigh), subtract(foot, knee)
    upper_length, lower_length = math.hypot(*upper_vector), math.hypot(*lower_vector)
    delta = subtract(ankle, hip)
    distance = math.hypot(*delta)
    lower_bound = abs(upper_length - lower_length) + IK_REACH_EPSILON
    upper_bound = upper_length + lower_length - IK_REACH_EPSILON
    if not lower_bound < distance < upper_bound:
        if not lower_bound - slack < distance < upper_bound + slack:
            raise ValueError(f"{side} 足部目标不可达：距离 {distance:.3f}，合法区间 ({lower_bound:.3f}, {upper_bound:.3f})，目标 {ankle}")
        # 跑姿步态解在蹬伸顶点轻微过伸；按腿长投影回去，残余误差交给鞋底求解消掉。
        clamped = min(max(distance, lower_bound), upper_bound)
        delta = (delta[0] * clamped / distance, delta[1] * clamped / distance)
        distance = clamped
    cosine = (upper_length**2 + distance**2 - lower_length**2) / (2.0 * upper_length * distance)
    upper_direction = math.atan2(delta[1], delta[0]) - math.acos(max(-1.0, min(1.0, cosine)))
    knee_position = hip[0] + upper_length * math.cos(upper_direction), hip[1] + upper_length * math.sin(upper_direction)
    lower_direction = math.atan2(ankle[1] - knee_position[1], ankle[0] - knee_position[0])
    lower_direction = upper_direction + math.remainder(lower_direction - upper_direction, math.tau)
    # Rest 的局部变换为平移；骨段原图方向不是节点 rotation，必须单独扣除。
    upper_rotation = upper_direction - math.atan2(upper_vector[1], upper_vector[0])
    lower_rotation = lower_direction - math.atan2(lower_vector[1], lower_vector[0])
    rotations[f"Thigh_{side}"] = upper_rotation - parent_angle
    rotations[f"Shin_{side}"] = lower_rotation - upper_rotation
    rotations[f"Foot_{side}"] = math.radians(goal.angle) - lower_rotation
    rotations[f"Toe_{side}"] = math.radians(goal.toe)


def place_feet(rotations: dict[str, float], com_position: Point, goals: tuple[FootGoal, FootGoal], profiles: tuple[BootProfile, BootProfile], slack: float = 0.0) -> None:
    for profile, goal in zip(profiles, goals):
        offset = rotate(subtract(profile.contact, BONE_BY_NAME[f"Foot_{profile.side}"].position), math.radians(goal.angle))
        ankle = goal.x - offset[0], goal.y - offset[1]
        lower_y, upper_y = None, None
        for _ in range(SOLE_SOLVE_ITERATIONS):
            solve_two_bone_leg(rotations, com_position, profile.side, ankle, goal, slack)
            error = boot_height(profile, forward_transforms(rotations, com_position)) - goal.y
            if abs(error) <= SOLE_SOLVE_TOLERANCE:
                break
            # 接触点可能从鞋尖换到鞋跟；用实际蒙皮轮廓的局部导数校正，而非假定高度斜率恒为 1。
            if error < 0.0:
                lower_y = ankle[1]
            else:
                upper_y = ankle[1]
            probe = ankle[0], ankle[1] + SOLE_DERIVATIVE_STEP
            solve_two_bone_leg(rotations, com_position, profile.side, probe, goal, slack)
            probe_error = boot_height(profile, forward_transforms(rotations, com_position)) - goal.y
            derivative = (probe_error - error) / SOLE_DERIVATIVE_STEP
            if abs(derivative) < SOLE_DERIVATIVE_EPSILON:
                raise ValueError(f"{profile.side} 鞋底高度不可解：局部导数为零")
            next_y = ankle[1] - error / derivative
            # 轮廓主导三角形切换时，牛顿步可能反复越过同一异号区间。
            if lower_y is not None and upper_y is not None and not lower_y < next_y < upper_y:
                next_y = (lower_y + upper_y) / 2.0
            ankle = ankle[0], next_y
        else:
            raise ValueError(f"{profile.side} 蒙皮鞋底接触未收敛：{error:.6f} 像素")


def blend_poses(first: Pose, second: Pose, amount: float) -> Pose:
    blend = lambda start, end: start + (end - start) * amount
    feet = tuple(FootGoal(*(blend(getattr(start, name), getattr(end, name)) for name in ("x", "y", "angle", "toe"))) for start, end in zip(first.feet, second.feet))
    return Pose({name: blend(value, second.rotations[name]) for name, value in first.rotations.items()}, tuple(blend(start, end) for start, end in zip(first.com_position, second.com_position)), feet)
