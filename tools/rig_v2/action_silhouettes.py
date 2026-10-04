import math
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from action_kinematics import SOLE_BAND_DEPTH, boot_contour, forward_transforms, mesh_sample, rotate, subtract
from mesh_binding import mesh_weights, rectangular_mesh
from rig_definition import BONES, BONE_BY_NAME, MESH_SPACING, PLAYER_SCALE, SOURCE_ORIGIN

ROLL_PIVOT = (0.0, -20.0)
SLIDE_CEILING = -32.0
GROUND_TOLERANCE = 0.055


@dataclass(frozen=True)
class Outline:
    name: str
    influences: tuple[str, ...]
    vertices: tuple[tuple[float, float], ...]
    weights: tuple[tuple[float, ...], ...]
    samples: tuple


def load_outlines(root: Path, regions: list[dict]) -> tuple[Outline, ...]:
    outlines = []
    for region in regions:
        if not region["visible"]:
            continue
        with Image.open(root / region["texture"].removeprefix("res://")) as image:
            points = boot_contour(image, tuple(region["bounds"][:2]), 0.0)
        if region["rigid_bone"]:
            bone = region["rigid_bone"]
            if bone == "ScabbardAnchor":
                bone = "Pelvis"
            outlines.append(Outline(region["name"], (bone,), tuple(points), ((1.0,),) * len(points), ()))
            continue
        vertices, _, _ = rectangular_mesh(region["bounds"])
        x, y, width, height = region["bounds"]
        columns, rows = max(2, math.ceil(width / MESH_SPACING)), max(2, math.ceil(height / MESH_SPACING))
        indices = {(round((point[0] - x) * columns / width), round((point[1] - y) * rows / height)): index for index, point in enumerate(vertices)}
        influences = tuple(region["influences"])
        weights = tuple(tuple(values) for values in zip(*mesh_weights(vertices, list(influences))))
        samples = tuple(mesh_sample(point, region["bounds"], indices) for point in points)
        outlines.append(Outline(region["name"], influences, tuple(vertices), weights, samples))
    return tuple(outlines)


def outline_points(outline: Outline, transforms: dict) -> list[tuple[float, float]]:
    vertices = []
    for point, weights in zip(outline.vertices, outline.weights):
        x, y = 0.0, 0.0
        for name, weight in zip(outline.influences, weights):
            if weight == 0.0:
                continue
            position, angle = transforms[name]
            offset = rotate(subtract(point, BONE_BY_NAME[name].position), angle)
            x += weight * (position[0] + offset[0])
            y += weight * (position[1] + offset[1])
        vertices.append((x, y))
    if not outline.samples:
        return vertices
    return [tuple(sum(vertices[index][axis] * weight for index, weight in zip(indices, weights)) for axis in (0, 1)) for indices, weights in outline.samples]


def sole_contact_indices(profile) -> tuple[int, ...]:
    rest = {bone.name: (bone.position, 0.0) for bone in BONES}
    points = outline_points(profile, rest)
    bottom = max(point[1] for point in points)
    return tuple(index for index, point in enumerate(points) if point[1] >= bottom - SOLE_BAND_DEPTH)


def sole_contact_x(points: list, indices: tuple[int, ...]) -> float:
    return sum(points[index][0] for index in indices) / len(indices)


def bounds(outline: Outline, transforms: dict, angle: float = 0.0, roll: bool = False) -> tuple[float, float, float, float]:
    points = []
    for point in outline_points(outline, transforms):
        local = tuple((point[axis] - SOURCE_ORIGIN[axis]) * PLAYER_SCALE for axis in (0, 1))
        if roll:
            rotated = rotate(subtract(local, ROLL_PIVOT), angle)
            local = rotated[0] + ROLL_PIVOT[0], rotated[1] + ROLL_PIVOT[1]
        points.append(local)
    return min(point[0] for point in points), min(point[1] for point in points), max(point[0] for point in points), max(point[1] for point in points)


def validate_silhouettes(actions: tuple, outlines: tuple[Outline, ...]) -> dict[str, float]:
    by_name = {action.spec.name: action for action in actions}
    slide = by_name["slide"]
    head_top, coat_bottom = math.inf, -math.inf
    visible_top, visible_bottom = math.inf, -math.inf
    for phase in (0.0, 0.25, 0.5, 0.75, 1.0):
        pose = slide.poses[round(phase * slide.spec.intervals)]
        transforms = forward_transforms(pose.rotations, pose.com_position)
        for outline in outlines:
            box = bounds(outline, transforms)
            visible_top = min(visible_top, box[1])
            visible_bottom = max(visible_bottom, box[3])
            if outline.name == "HeadFace":
                head_top = min(head_top, box[1])
            elif outline.name.startswith(("CoatBack", "ClothFront")):
                coat_bottom = max(coat_bottom, box[3])
    if not math.isfinite(head_top) or not math.isfinite(coat_bottom) or head_top < SLIDE_CEILING or coat_bottom > GROUND_TOLERANCE:
        raise ValueError(f"滑铲轮廓不适配低通道：头顶 {head_top:.5f}，衣片底 {coat_bottom:.5f} 游戏像素")
    if visible_top < SLIDE_CEILING or visible_bottom > GROUND_TOLERANCE:
        raise ValueError(f"滑铲完整可见轮廓越界：{visible_top:.5f}～{visible_bottom:.5f} 游戏像素")
    roll_bottom = validate_roll_silhouette(by_name["double_jump"], outlines)
    return {"slide_head_top_gamepx": head_top, "slide_coat_bottom_gamepx": coat_bottom, "slide_visible_top_gamepx": visible_top, "slide_visible_bottom_gamepx": visible_bottom, "roll_bottom_gamepx": roll_bottom}


def validate_roll_silhouette(action, outlines: tuple[Outline, ...]) -> float:
    bottom = -math.inf
    for index, pose in enumerate(action.poses):
        phase = index / action.spec.intervals
        transforms = forward_transforms(pose.rotations, pose.com_position)
        bottom = max(bottom, *(bounds(outline, transforms, math.tau * phase, True)[3] for outline in outlines))
    if bottom > GROUND_TOLERANCE:
        raise ValueError(f"翻滚可见轮廓穿地：{bottom:.5f} 游戏像素")
    return bottom
