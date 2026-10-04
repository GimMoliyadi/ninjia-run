from pathlib import Path


ROOT = Path(__file__).parent
SCENE = ROOT / "player_skeleton_test.tscn"
PARTS = [
    ("Hip", "Skeleton", (480, 396), 10, ""),
    ("Torso", "Hip", (0, -4), 27, "torso"),
    ("Head", "Torso", (0, -27), 13, "head"),
    ("RearUpperArm", "Torso", (-3, -21), 16, "upper_arm"),
    ("RearForearm", "RearUpperArm", (0, 16), 15, "forearm"),
    ("RearHand", "RearForearm", (0, 15), 6, "hand"),
    ("FrontUpperArm", "Torso", (4, -21), 16, "upper_arm"),
    ("FrontForearm", "FrontUpperArm", (0, 16), 15, "forearm"),
    ("FrontHand", "FrontForearm", (0, 15), 6, "hand"),
    ("RearThigh", "Hip", (-3, 1), 20, "thigh"),
    ("RearShin", "RearThigh", (0, 20), 20, "shin"),
    ("RearFoot", "RearShin", (0, 20), 9, "foot"),
    ("FrontThigh", "Hip", (3, 1), 20, "thigh"),
    ("FrontShin", "FrontThigh", (0, 20), 20, "shin"),
    ("FrontFoot", "FrontShin", (0, 20), 9, "foot"),
]
SHAPES = {
    "torso": ("-9, 2, 8, 2, 9, -26, -7, -27", "0.09, 0.12, 0.19, 1"),
    "head": ("-10, -12, 8, -12, 11, -4, 8, 9, -9, 9, -12, 0", "0.11, 0.14, 0.2, 1"),
    "upper_arm": ("-5, -3, 5, -3, 5, 18, -5, 18", "0.12, 0.16, 0.24, 1"),
    "forearm": ("-4, -2, 4, -2, 4, 17, -4, 17", "0.17, 0.22, 0.31, 1"),
    "hand": ("-4, -2, 4, -2, 4, 7, -4, 7", "0.73, 0.69, 0.55, 1"),
    "thigh": ("-6, -3, 6, -3, 5, 22, -5, 22", "0.1, 0.14, 0.22, 1"),
    "shin": ("-5, -3, 5, -3, 4, 22, -4, 22", "0.16, 0.21, 0.3, 1"),
    "foot": ("-4, -3, 10, -3, 12, 5, -4, 5", "0.08, 0.1, 0.15, 1"),
}
POSES = {
    "Hip:position": [(0, (480, 396)), (.075, (482, 398)), (.15, (484, 392)), (.225, (482, 389)), (.3, (480, 396)), (.375, (482, 398)), (.45, (484, 392)), (.525, (482, 389)), (.6, (480, 396))],
    "Torso:rotation": [(0, -0.16), (.15, -0.11), (.3, -0.16), (.45, -0.11), (.6, -0.16)],
    "Head:rotation": [(0, .12), (.15, .08), (.3, .12), (.45, .08), (.6, .12)],
    "FrontThigh:rotation": [(0, -.72), (.075, -.2), (.15, .48), (.225, .72), (.3, .48), (.375, -.3), (.45, -.86), (.525, -.9), (.6, -.72)],
    "FrontShin:rotation": [(0, .16), (.075, .18), (.15, .5), (.225, 1.16), (.3, 1.2), (.375, .82), (.45, .2), (.525, .12), (.6, .16)],
    "RearThigh:rotation": [(0, .48), (.075, -.3), (.15, -.86), (.225, -.9), (.3, -.72), (.375, -.2), (.45, .48), (.525, .72), (.6, .48)],
    "RearShin:rotation": [(0, 1.2), (.075, .82), (.15, .2), (.225, .12), (.3, .16), (.375, .18), (.45, .5), (.525, 1.16), (.6, 1.2)],
    "FrontFoot:rotation": [(0, .28), (.15, -.24), (.3, .28), (.45, -.24), (.6, .28)],
    "RearFoot:rotation": [(0, -.24), (.15, .28), (.3, -.24), (.45, .28), (.6, -.24)],
    "FrontUpperArm:rotation": [(0, .57), (.15, -.47), (.3, -.63), (.45, .4), (.6, .57)],
    "RearUpperArm:rotation": [(0, -.63), (.15, .4), (.3, .57), (.45, -.47), (.6, -.63)],
    "FrontForearm:rotation": [(0, -.85), (.15, -.95), (.3, -.82), (.45, -.95), (.6, -.85)],
    "RearForearm:rotation": [(0, -.82), (.15, -.95), (.3, -.85), (.45, -.95), (.6, -.82)],
}


def vector(value):
    return f"Vector2({value[0]}, {value[1]})"


def main():
    lines = ["[gd_scene load_steps=3 format=3]", "", '[sub_resource type="Animation" id="Animation_run"]', 'resource_name = "run"', 'length = 0.6', 'loop_mode = 1']
    for index, (target, poses) in enumerate(POSES.items()):
        bone, prop = target.split(":")
        path = next_path(bone)
        values = [vector(v) if isinstance(v, tuple) else str(v) for _, v in poses]
        lines += [f'tracks/{index}/type = "value"', f'tracks/{index}/path = NodePath("{path}:{prop}")', f'tracks/{index}/interp = 1', f'tracks/{index}/loop_wrap = true', f'tracks/{index}/keys = {{"times": PackedFloat32Array({", ".join(str(t) for t, _ in poses)}), "transitions": PackedFloat32Array({", ".join("1" for _ in poses)}), "update": 0, "values": [{", ".join(values)}]}}']
    lines += ["", '[sub_resource type="AnimationLibrary" id="AnimationLibrary_main"]', '_data = {"run": SubResource("Animation_run")}', "", '[node name="PlayerSkeletonTest" type="Node2D"]', "", '[node name="Background" type="Polygon2D" parent="."]', 'color = Color(0.86, 0.9, 0.91, 1)', 'polygon = PackedVector2Array(0, 0, 960, 0, 960, 540, 0, 540)', "", '[node name="Ground" type="Polygon2D" parent="."]', 'color = Color(0.25, 0.32, 0.36, 1)', 'polygon = PackedVector2Array(0, 441, 960, 441, 960, 540, 0, 540)', "", '[node name="Skeleton" type="Skeleton2D" parent="."]', 'position = Vector2(0, 0)']
    for name, parent, pos, length, shape in PARTS:
        parent_path = "Skeleton" if parent == "Skeleton" else "Skeleton/" + lineage(parent)
        lines += ["", f'[node name="{name}" type="Bone2D" parent="{parent_path}"]', f'position = {vector(pos)}', f'length = {length}.0', 'rest = Transform2D(1, 0, 0, 1, 0, 0)']
        if name in ("Head", "RearHand", "FrontHand", "RearFoot", "FrontFoot"):
            lines += ['auto_calculate_length_and_angle = false']
        if shape:
            coords, color = SHAPES[shape]
            lines += ["", f'[node name="Art" type="Polygon2D" parent="{parent_path}/{name}"]', f'color = Color({color})', f'polygon = PackedVector2Array({coords})']
    lines += ["", '[node name="AnimationPlayer" type="AnimationPlayer" parent="."]', 'root_node = NodePath("..")', 'libraries = {"": SubResource("AnimationLibrary_main")}', 'autoplay = "run"', ""]
    SCENE.write_text("\n".join(lines), encoding="utf-8")


def lineage(name):
    parents = {part[0]: part[1] for part in PARTS}
    chain = [name]
    while parents[chain[0]] != "Skeleton":
        chain.insert(0, parents[chain[0]])
    return "/".join(chain)


def next_path(name):
    return "Skeleton/" + lineage(name)


if __name__ == "__main__":
    main()
