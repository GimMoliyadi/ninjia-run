import json
import math
from pathlib import Path

from action_kinematics import COM_REST_Y, load_boot_profiles
from action_poses import Action, build_actions, validate_action_samples
from action_silhouettes import load_outlines, validate_silhouettes
from mesh_binding import mesh_weights, rectangular_mesh
from rig_definition import BONES, BONE_BY_NAME, PLAYER_SCALE, SOURCE_ORIGIN, TEST_POSES, TEST_POSE_SECONDS, bone_path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
REGIONS_PATH = PROJECT_ROOT / "assets/player/cultivator/rig_v2/regions.json"
SCENE_PATH = PROJECT_ROOT / "visuals/rig_v2/visual_root_v2.tscn"
TEXTURE_FILTER_LINEAR_WITH_MIPMAPS = 4
ANCHORS = {
    "SwordGrip": ("Hand_R", (886, 735)),
    "ScabbardGripTarget": ("Hand_L", (350, 718)),
    "ScabbardAnchor": ("Pelvis", (534, 584)),
    "SheathedSwordSocket": ("ScabbardAnchor", (553, 563)),
}


def number(value: float) -> str:
    return f"{value:.6f}".rstrip("0").rstrip(".") or "0"


def vector(point: tuple[float, float]) -> str:
    return f"Vector2({number(point[0])}, {number(point[1])})"


def packed(kind: str, values) -> str:
    return f"{kind}({', '.join(number(value) for value in values)})"


def source_position(name: str) -> tuple[float, float]:
    return BONE_BY_NAME[name].position if name in BONE_BY_NAME else ANCHORS[name][1]


def attachment_path(name: str) -> str:
    if name in BONE_BY_NAME:
        return f"Skeleton2D/{bone_path(name)}"
    parent, _ = ANCHORS[name]
    return f"{attachment_path(parent)}/{name}"


def bone_nodes() -> list[str]:
    sections = ['[node name="Skeleton2D" type="Skeleton2D" parent="."]']
    for bone in BONES:
        parent = f"Skeleton2D/{bone_path(bone.parent)}" if bone.parent else "Skeleton2D"
        parent_position = BONE_BY_NAME[bone.parent].position if bone.parent else SOURCE_ORIGIN
        position = tuple(value - origin for value, origin in zip(bone.position, parent_position))
        delta = tuple(tip - start for tip, start in zip(bone.tip, bone.position))
        sections.append("\n".join((
            f'[node name="{bone.name}" type="Bone2D" parent="{parent}"]',
            f"position = {vector(position)}",
            f"rest = Transform2D(1, 0, 0, 1, {number(position[0])}, {number(position[1])})",
            "auto_calculate_length_and_angle = false",
            f"length = {number(math.hypot(*delta))}",
            f"bone_angle = {number(math.degrees(math.atan2(delta[1], delta[0])))}",
        )))
    for name, (parent, position) in ANCHORS.items():
        origin = source_position(parent)
        local = tuple(value - base for value, base in zip(position, origin))
        sections.append(f'[node name="{name}" type="Marker2D" parent="{attachment_path(parent)}"]\nposition = {vector(local)}')
    return sections


def mesh_node(region: dict, texture_id: str) -> str:
    bounds = region["bounds"]
    points, triangles, internal_count = rectangular_mesh(bounds)
    influences = region["influences"]
    if region["name"].startswith("Arm_") and influences[0] != "Chest":
        influences = ["Chest"] + influences
    weights = mesh_weights(points, influences)
    coordinates = [coordinate - SOURCE_ORIGIN[axis] for point in points for axis, coordinate in enumerate(point)]
    uvs = [coordinate - bounds[axis] for point in points for axis, coordinate in enumerate(point)]
    faces = ", ".join(packed("PackedInt32Array", face) for face in triangles)
    bindings = ", ".join(f'"{bone_path(name)}", {packed("PackedFloat32Array", values)}' for name, values in zip(influences, weights))
    return "\n".join((
        f'[node name="{region["name"]}" type="Polygon2D" parent="Skin"]',
        f'z_index = {region["z_index"]}',
        "z_as_relative = true",
        f'texture = ExtResource("{texture_id}")',
        f'polygon = {packed("PackedVector2Array", coordinates)}',
        f'uv = {packed("PackedVector2Array", uvs)}',
        f"internal_vertex_count = {internal_count}",
        f"polygons = [{faces}]",
        'skeleton = NodePath("../../Skeleton2D")',
        f"bones = [{bindings}]",
        "antialiased = true",
        f'metadata/region = "{region["name"]}"',
    ))


def sprite_node(region: dict, texture_id: str) -> str:
    name = region["rigid_bone"]
    if region["name"] == "Scabbard":
        name = "ScabbardAnchor"
    elif region["name"] == "Sword":
        name = "SheathedSwordSocket"
    origin = source_position(name)
    position = tuple(region["bounds"][axis] - origin[axis] for axis in range(2))
    return "\n".join((
        f'[node name="{region["name"]}" type="Sprite2D" parent="{attachment_path(name)}"]',
        f"position = {vector(position)}",
        f'visible = {str(region["visible"]).lower()}',
        f'z_index = {region["z_index"]}',
        "z_as_relative = true",
        f'texture = ExtResource("{texture_id}")',
        "centered = false",
        f'metadata/source_unavailable = {str(region["unavailable"]).lower()}',
    ))


def value_track(index: int, path: str, times: list[float], values: list[float]) -> str:
    # Godot 按首个 Variant 推断插值类型，零值也必须序列化成浮点。
    key_values = ", ".join(f"{value:.6f}" for value in values)
    return "\n".join((
        f'tracks/{index}/type = "value"',
        f'tracks/{index}/path = NodePath("{path}")',
        f"tracks/{index}/interp = 1",
        f"tracks/{index}/loop_wrap = false",
        f'tracks/{index}/keys = {{"times": {packed("PackedFloat32Array", times)}, "transitions": {packed("PackedFloat32Array", [1.0] * len(times))}, "update": 0, "values": [{key_values}]}}',
    ))


def action_animation(action: Action) -> str:
    spec = action.spec
    sections = [f'[sub_resource type="Animation" id="Animation_{spec.name}"]', f'resource_name = "{spec.name}"', f"length = {number(spec.seconds)}"]
    if spec.loop:
        sections.append("loop_mode = 1")
    for index, bone in enumerate(BONES):
        sections.append(value_track(index, f"Skeleton2D/{bone_path(bone.name)}:rotation", action.times, [pose.rotations[bone.name] for pose in action.poses]))
    for axis, suffix in enumerate(("x", "y")):
        sections.append(value_track(len(BONES) + axis, f'Skeleton2D/{bone_path("COM")}:position:{suffix}', action.times, [pose.com_position[axis] for pose in action.poses]))
    return "\n".join(sections)


def animations(actions: tuple[Action, ...]) -> list[str]:
    seconds = [index * TEST_POSE_SECONDS for index in range(len(TEST_POSES))]
    test = ['[sub_resource type="Animation" id="Animation_rig_test"]', 'resource_name = "rig_test"', f"length = {number(seconds[-1])}"]
    reset = ['[sub_resource type="Animation" id="Animation_RESET"]', "length = 0.001"]
    for index, bone in enumerate(BONES):
        path = f"Skeleton2D/{bone_path(bone.name)}:rotation"
        values = [math.radians(rotations.get(bone.name, 0.0)) for _, rotations in TEST_POSES]
        test.append(value_track(index, path, seconds, values))
        reset.append(value_track(index, path, [0.0], [0.0]))
    com_path = f'Skeleton2D/{bone_path("COM")}:position'
    test.append(value_track(len(BONES), f"{com_path}:x", seconds, [16.0 if index == 1 else 0.0 for index in range(len(TEST_POSES))]))
    reset.append(value_track(len(BONES), f"{com_path}:x", [0.0], [0.0]))
    test.append(value_track(len(BONES) + 1, f"{com_path}:y", seconds, [COM_REST_Y] * len(seconds)))
    reset.append(value_track(len(BONES) + 1, f"{com_path}:y", [0.0], [COM_REST_Y]))
    names = ["RESET", "rig_test", *(action.spec.name for action in actions)]
    entries = ", ".join(f'&"{name}": SubResource("Animation_{name}")' for name in names)
    library = f'[sub_resource type="AnimationLibrary" id="AnimationLibrary_rig"]\n_data = {{{entries}}}'
    return ["\n".join(reset), "\n".join(test), *(action_animation(action) for action in actions), library]


def build_scene(regions: list[dict], actions: tuple[Action, ...]) -> str:
    resources = ['[ext_resource type="Script" path="res://visuals/rig_v2/visual_rig_v2.gd" id="1_script"]']
    for index, region in enumerate(regions):
        texture_path = region["texture"].removeprefix("res://")
        if not (PROJECT_ROOT / texture_path).is_file():
            raise FileNotFoundError(texture_path)
        resources.append(f'[ext_resource type="Texture2D" path="res://{texture_path}" id="texture_{index}"]')
    sections = [f"[gd_scene load_steps={len(resources) + len(actions) + 4} format=3]", *resources, *animations(actions)]
    sections.append(f'[node name="VisualRoot_V2" type="Node2D"]\nz_index = 1\ntexture_filter = {TEXTURE_FILTER_LINEAR_WITH_MIPMAPS}\nscale = Vector2({PLAYER_SCALE}, {PLAYER_SCALE})\nscript = ExtResource("1_script")\nmetadata/source_origin = {vector(SOURCE_ORIGIN)}')
    sections.extend(bone_nodes())
    sections.append('[node name="Skin" type="Node2D" parent="."]')
    minimum_z = min(region["z_index"] for region in regions)
    for index, region in enumerate(regions):
        region = {**region, "z_index": region["z_index"] - minimum_z}
        sections.append(sprite_node(region, f"texture_{index}") if region.get("rigid_bone") else mesh_node(region, f"texture_{index}"))
    sections.append('[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\nlibraries = {&"": SubResource("AnimationLibrary_rig")}')
    return "\n\n".join(sections) + "\n"


def main() -> None:
    manifest = json.loads(REGIONS_PATH.read_text(encoding="utf-8"))
    if manifest["source_size"] != [1086, 1448]:
        raise ValueError("分层素材尺寸与最新立绘不一致")
    regions = manifest["regions"]
    if len({region["name"] for region in regions}) != len(regions):
        raise ValueError("分层素材节点名重复")
    profiles = load_boot_profiles(PROJECT_ROOT, regions)
    actions = build_actions(profiles)
    metrics = validate_action_samples(actions, profiles)
    metrics.update(validate_silhouettes(actions, load_outlines(PROJECT_ROOT, regions)))
    SCENE_PATH.parent.mkdir(parents=True, exist_ok=True)
    SCENE_PATH.write_text(build_scene(regions, actions), encoding="utf-8")
    print(f"Rig V2：{len(BONES)} 根 Bone2D，{len(regions)} 个独立视觉区域，8 个测试姿态，{len(actions)} 个正式移动动作，统一 53 条浮点轨。")
    print(json.dumps(metrics, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
