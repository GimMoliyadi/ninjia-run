import json
import math
import re
import sys
import unittest
from dataclasses import dataclass
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "tools/rig_v2"))

import action_poses
import build_rig
import mesh_binding
from action_kinematics import forward_transforms, load_boot_profiles
from rig_definition import BONES, BONE_BY_NAME, SOURCE_ORIGIN, TEST_POSES
from rig_v2_run_support_probe import build_run

SCENE_PATH = PROJECT_ROOT / "visuals/rig_v2/visual_root_v2.tscn"
ALPHA_THRESHOLD = 16
AREA_EPSILON = 1e-8
RUN_SUBDIVISIONS = 4
MAX_WEIGHT_STEP_PER_SOURCEPX = 0.05
MIN_VISIBLE_TORSO_AREA_RATIO = 0.5
JOINTS = {"Arm_L": ("Forearm_L",), "Leg_L": ("Shin_L", "Foot_L"), "Leg_R": ("Shin_R", "Foot_R")}


@dataclass(frozen=True)
class SkinMesh:
    name: str
    vertices: np.ndarray
    faces: np.ndarray
    influences: tuple[str, ...]
    weights: np.ndarray
    centroid_alpha: np.ndarray


def numbers(text: str) -> np.ndarray:
    return np.array([float(value) for value in text.split(",")])


def load_mesh(node: str, region: dict) -> SkinMesh:
    vertices = numbers(re.search(r"polygon = PackedVector2Array\(([^)]*)\)", node)[1]).reshape(-1, 2) + SOURCE_ORIGIN
    faces = np.array([tuple(map(int, values.split(","))) for values in re.findall(r"PackedInt32Array\(([^)]*)\)", re.search(r"polygons = ([^\n]*)", node)[1])])
    bindings = re.findall(r'"([^"\n]+)", PackedFloat32Array\(([^)]*)\)', re.search(r"bones = ([^\n]*)", node)[1])
    influences = tuple(path.rsplit("/", 1)[-1] for path, _ in bindings)
    weights = np.array([numbers(values) for _, values in bindings]).T
    uv = np.floor(vertices[faces].mean(axis=1) - region["bounds"][:2]).astype(int)
    with Image.open(PROJECT_ROOT / region["texture"]) as image:
        alpha = np.array(image.getchannel("A"))[uv[:, 1], uv[:, 0]]
    return SkinMesh(region["name"], vertices, faces, influences, weights, alpha)


def load_scene_meshes(text: str) -> dict[str, SkinMesh]:
    regions = json.loads((PROJECT_ROOT / "assets/player/cultivator/rig_v2/regions.json").read_text(encoding="utf-8"))["regions"]
    return {region["name"]: load_mesh(re.search(r'\[node name="' + region["name"] + r'" type="Polygon2D"[^\n]*\]\n.*?(?=\n\n\[)', text, re.S)[0], region) for region in regions if not region["rigid_bone"]}


def load_run_keys(text: str) -> np.ndarray:
    animation = re.search(r'\[sub_resource type="Animation" id="Animation_run"\].*?(?=\n\n\[)', text, re.S)[0]
    keys = {int(index): numbers(values) for index, values in re.findall(r'tracks/(\d+)/keys = .*?"values": \[([^\]]*)\]', animation)}
    return np.array([keys[index] for index in range(len(BONES) + 2)]).T


def skin_vertices(mesh: SkinMesh, transforms: dict) -> np.ndarray:
    result = np.zeros_like(mesh.vertices)
    for index, name in enumerate(mesh.influences):
        position, angle = transforms[name]
        cosine, sine = math.cos(angle), math.sin(angle)
        matrix = np.array(((cosine, sine), (-sine, cosine)))
        result += mesh.weights[:, index, None] * ((mesh.vertices - BONE_BY_NAME[name].position) @ matrix + position)
    return result


def signed_areas(vertices: np.ndarray, faces: np.ndarray) -> np.ndarray:
    triangles = vertices[faces]
    first, second = triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0]
    return (first[:, 0] * second[:, 1] - first[:, 1] * second[:, 0]) / 2.0


def joint_faces(mesh: SkinMesh, joint: str) -> np.ndarray:
    bone = BONE_BY_NAME[joint]
    upstream = BONE_BY_NAME[bone.parent]
    half_segment = min(math.dist(upstream.position, bone.position), math.dist(bone.position, bone.tip)) / 2.0
    centroids = mesh.vertices[mesh.faces].mean(axis=1)
    # 整段纹理宽度均检查；纵向覆盖相邻骨段中点，避免把用例绑定到三个顶点编号。
    return (mesh.centroid_alpha >= ALPHA_THRESHOLD) & (np.abs(centroids[:, 1] - bone.position[1]) <= half_segment)


def run_transforms(keys: np.ndarray, subdivisions: int = RUN_SUBDIVISIONS):
    for index in range(len(keys) - 1):
        for subdivision in range(subdivisions):
            amount = subdivision / subdivisions
            values = keys[index] * (1.0 - amount) + keys[index + 1] * amount
            rotations = {bone.name: values[bone_index] for bone_index, bone in enumerate(BONES)}
            yield (index + amount) / (len(keys) - 1), forward_transforms(rotations, tuple(values[-2:]))


def joint_minimum_areas(meshes: dict[str, SkinMesh], keys: np.ndarray, subdivisions: int = RUN_SUBDIVISIONS) -> dict[str, float]:
    minima = {joint: math.inf for joints in JOINTS.values() for joint in joints}
    masks = {(name, joint): joint_faces(meshes[name], joint) for name, joints in JOINTS.items() for joint in joints}
    for _, transforms in run_transforms(keys, subdivisions):
        for name, joints in JOINTS.items():
            mesh = meshes[name]
            areas = signed_areas(skin_vertices(mesh, transforms), mesh.faces)
            rest = signed_areas(mesh.vertices, mesh.faces)
            oriented_areas = areas * np.sign(rest)
            for joint in joints:
                mask = masks[name, joint]
                if not mask.any():
                    raise AssertionError(f"没有可见关节三角形：{name}/{joint}")
                minima[joint] = min(minima[joint], float(oriented_areas[mask].min()))
    return minima


def assert_no_joint_folds(meshes: dict[str, SkinMesh], keys: np.ndarray, subdivisions: int = RUN_SUBDIVISIONS) -> dict[str, float]:
    minima = joint_minimum_areas(meshes, keys, subdivisions)
    failures = {name: area for name, area in minima.items() if area <= AREA_EPSILON}
    if failures:
        raise AssertionError(f"RUN 可见关节蒙皮反折：{failures}")
    return minima


class ChainBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.regions = json.loads(build_rig.REGIONS_PATH.read_text(encoding="utf-8"))["regions"]
        cls.torso_region = next(region for region in cls.regions if region["name"] == "Torso")

    def test_reverse_chain_terminal_blend_reaches_full_pelvis_weight(self) -> None:
        influences = self.torso_region["influences"]
        pelvis = BONE_BY_NAME["Pelvis"].position
        np.testing.assert_allclose(mesh_binding.chain_vertex_weights(pelvis, influences), [0.0, 0.0, 0.5, 0.5], atol=1e-12, rtol=0.0)
        np.testing.assert_array_equal(mesh_binding.chain_vertex_weights((613.0, 700.0), influences), [0.0, 0.0, 0.0, 1.0])

    def test_reverse_chain_off_axis_waist_weights_stay_continuous(self) -> None:
        points = [(700.0, float(y)) for y in range(520, 608)]
        weights = np.array(mesh_binding.mesh_weights(points, self.torso_region["influences"])).T
        np.testing.assert_allclose(weights.sum(axis=1), 1.0, atol=1e-12, rtol=0.0)
        self.assertTrue((weights >= 0.0).all())
        self.assertLessEqual(float(np.abs(np.diff(weights, axis=0)).max()), MAX_WEIGHT_STEP_PER_SOURCEPX)
        progression = weights @ np.arange(weights.shape[1])
        self.assertTrue((np.diff(progression) >= -1e-12).all())

    def test_torso_forward_pose_keeps_at_least_half_visible_waist_area(self) -> None:
        mesh = load_mesh(build_rig.mesh_node(self.torso_region, "probe"), self.torso_region)
        degrees = next(degrees for name, degrees in TEST_POSES if name == "TorsoForward")
        rotations = {bone.name: math.radians(degrees.get(bone.name, 0.0)) for bone in BONES}
        transforms = forward_transforms(rotations, (0.0, 0.0))
        ratios = signed_areas(skin_vertices(mesh, transforms), mesh.faces) / signed_areas(mesh.vertices, mesh.faces)
        mask = joint_faces(mesh, "Spine_01")
        self.assertTrue(mask.any(), "没有可见腰部三角形")
        self.assertGreaterEqual(float(ratios[mask].min()), MIN_VISIBLE_TORSO_AREA_RATIO)

    def test_forward_and_hip_bindings_still_match_generated_resource(self) -> None:
        meshes = load_scene_meshes(SCENE_PATH.read_text(encoding="utf-8"))
        for region in self.regions:
            if region["rigid_bone"] or region["name"] == "Torso":
                continue
            with self.subTest(region=region["name"]):
                source = load_mesh(build_rig.mesh_node(region, "probe"), region)
                actual = meshes[region["name"]]
                self.assertEqual(actual.influences, source.influences)
                np.testing.assert_array_equal(actual.vertices, source.vertices)
                np.testing.assert_array_equal(actual.weights, source.weights)

    def test_single_bone_binding_and_neutral_torso_remain_identity(self) -> None:
        points = [(596.0, 361.0), (700.0, 550.0), (613.0, 700.0)]
        np.testing.assert_array_equal(mesh_binding.mesh_weights(points, ["Chest"]), [[1.0] * len(points)])
        mesh = load_mesh(build_rig.mesh_node(self.torso_region, "probe"), self.torso_region)
        neutral = {bone.name: (bone.position, 0.0) for bone in BONES}
        np.testing.assert_allclose(mesh.weights.sum(axis=1), 1.0, atol=0.000001, rtol=0.0)
        self.assertTrue((mesh.weights >= 0.0).all())
        np.testing.assert_allclose(skin_vertices(mesh, neutral), mesh.vertices, atol=0.000001, rtol=0.0)


class JointSkinTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SCENE_PATH.read_text(encoding="utf-8")
        cls.meshes = load_scene_meshes(cls.text)
        cls.keys = load_run_keys(cls.text)
        cls.regions = json.loads(build_rig.REGIONS_PATH.read_text(encoding="utf-8"))["regions"]
        fixture = json.loads((PROJECT_ROOT / "tests/fixtures/rig_v2_run_pre_fix_poses.json").read_text(encoding="utf-8"))
        expected = [bone.name for bone in BONES] + ["COM.position.x", "COM.position.y"]
        if fixture["tracks"] != expected:
            raise AssertionError("修前 fixture 的 53 条轨顺序不符")
        samples = fixture["joint_skin"]["samples"]
        cls.pre_fix_keys = np.array([sample["tracks"] for sample in samples] + [samples[-1]["tracks"]])

    def source_meshes(self) -> dict[str, SkinMesh]:
        return {region["name"]: load_mesh(build_rig.mesh_node(region, "probe"), region) for region in self.regions if not region["rigid_bone"]}

    def source_keys(self) -> np.ndarray:
        profiles = load_boot_profiles(PROJECT_ROOT, self.regions)
        spec = next(spec for spec in action_poses.ACTION_SPECS if spec.name == "run")
        run = build_run(spec, profiles)
        return np.array([[*(pose.rotations[bone.name] for bone in BONES), *pose.com_position] for pose in run.poses])

    def test_actual_resource_joint_triangles_keep_orientation(self) -> None:
        minima = assert_no_joint_folds(self.meshes, self.keys)
        print(json.dumps({"resource_joint_min_area_sourcepx2": minima}, ensure_ascii=False))

    def test_resource_matches_source_and_neutral_skin_stays_in_place(self) -> None:
        source = self.source_meshes()
        np.testing.assert_allclose(self.keys, self.source_keys(), atol=0.0000005, rtol=0.0)
        neutral = {bone.name: (bone.position, 0.0) for bone in BONES}
        for name in (*JOINTS, "Torso"):
            actual = self.meshes[name]
            np.testing.assert_array_equal(actual.weights, source[name].weights)
            np.testing.assert_allclose(actual.weights.sum(axis=1), 1.0, atol=0.000001, rtol=0.0)
            self.assertTrue((actual.weights >= 0.0).all())
            np.testing.assert_allclose(skin_vertices(actual, neutral), actual.vertices, atol=0.000001, rtol=0.0)

    def test_rebound_slide_boot_still_solves_real_alpha_contact(self) -> None:
        profiles = load_boot_profiles(PROJECT_ROOT, self.regions)
        spec = next(spec for spec in action_poses.ACTION_SPECS if spec.name == "slide")
        pose = action_poses.action_pose(spec, 0, profiles)
        self.assertLessEqual(action_poses.validate_contact(pose, profiles), action_poses.CONTACT_TOLERANCE)

    def test_legacy_narrow_bindings_are_rejected_with_real_pre_fix_poses(self) -> None:
        with patch.object(mesh_binding, "JOINT_BLEND_OVERRIDES_SOURCEPX", {}):
            legacy = self.source_meshes()
        with self.assertRaisesRegex(AssertionError, "Forearm_L.*Shin_L.*Foot_R"):
            assert_no_joint_folds(legacy, self.pre_fix_keys, subdivisions=1)

    def test_real_pre_fix_elbow_and_foot_poses_fail_on_current_mesh(self) -> None:
        minima = joint_minimum_areas(self.meshes, self.pre_fix_keys, subdivisions=1)
        self.assertLess(minima["Forearm_L"], 0.0)
        self.assertLess(minima["Foot_R"], 0.0)
        with self.assertRaisesRegex(AssertionError, "Forearm_L.*Foot_R"):
            assert_no_joint_folds(self.meshes, self.pre_fix_keys, subdivisions=1)



if __name__ == "__main__":
    unittest.main(verbosity=2)
