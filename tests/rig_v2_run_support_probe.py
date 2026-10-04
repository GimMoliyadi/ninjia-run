import json
import math
import sys
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "tools/rig_v2"))

import action_poses
from action_kinematics import GROUND_Y, forward_transforms, load_boot_profiles
from action_poses import (
    ACTION_SPECS, RUN_DEFAULT_SPEED_GAMEPX, RUN_HALF_STRIDE, RUN_SUPPORT_FRACTION,
    Action, action_pose, inspect_run_support, realize_pose, run_design,
    validate_run_geometry, validate_run_phases,
)
from action_silhouettes import outline_points, sole_contact_indices, sole_contact_x
from rig_definition import BONES, PLAYER_SCALE, SOURCE_ORIGIN

LEGACY_WORLD_SWEEP_GAMEPX = 70.71428571428571
COM_VELOCITY_SEAM_TOLERANCE_SOURCEPX_S = 5.0
COM_DERIVATIVE_STEP_PHASE = 1e-6
INVALID_SOLE_OFFSET_SOURCEPX = 20.0


def build_run(spec, profiles) -> Action:
    poses = [action_pose(spec, index, profiles) for index in range(spec.intervals + 1)]
    poses[-1] = poses[0]
    return Action(spec, tuple(poses))


def inspect_key_support(action: Action, profiles) -> dict:
    speeds, heights = [], []
    for side, profile in enumerate(profiles):
        previous = None
        indices = sole_contact_indices(profile)
        for pose in action.poses[:-1]:
            if abs(pose.feet[side].y - GROUND_Y) > action_poses.CONTACT_TOLERANCE:
                previous = None
                continue
            points = outline_points(profile, forward_transforms(pose.rotations, pose.com_position))
            heights.append(abs(max(point[1] for point in points) - GROUND_Y) * PLAYER_SCALE)
            contact = sole_contact_x(points, indices)
            if previous is not None:
                speeds.append((previous - contact) * PLAYER_SCALE / (action.spec.seconds / action.spec.intervals))
            previous = contact
    return {"alpha_key_speed_min_gamepx_s": min(speeds), "alpha_key_speed_max_gamepx_s": max(speeds), "alpha_key_ground_error_gamepx": max(heights)}


class RunPhaseContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        regions = json.loads((PROJECT_ROOT / "assets/player/cultivator/rig_v2/regions.json").read_text(encoding="utf-8"))["regions"]
        cls.profiles = load_boot_profiles(PROJECT_ROOT, regions)
        cls.spec = next(spec for spec in ACTION_SPECS if spec.name == "run")
        cls.animation = build_run(cls.spec, cls.profiles)

    def with_pose(self, index: int, pose) -> Action:
        poses = list(self.animation.poses)
        poses[index] = pose
        return replace(self.animation, poses=tuple(poses))

    def test_default400_staged_run_is_the_source(self) -> None:
        self.assertEqual(self.spec.intervals, 120)
        self.assertEqual(self.spec.seconds, 0.33)
        self.assertEqual(RUN_SUPPORT_FRACTION, 0.3)
        self.assertAlmostEqual(RUN_HALF_STRIDE, RUN_DEFAULT_SPEED_GAMEPX * self.spec.seconds * RUN_SUPPORT_FRACTION / (2.0 * PLAYER_SCALE))
        metrics = validate_run_phases(self.animation, self.profiles)
        self.assertEqual(metrics["run_left_support_keys"], 37)
        self.assertEqual(metrics["run_right_support_keys"], 37)
        self.assertEqual(metrics["run_flight_keys"], 46)
        keys = inspect_key_support(self.animation, self.profiles)
        self.assertAlmostEqual(keys["alpha_key_speed_min_gamepx_s"], RUN_DEFAULT_SPEED_GAMEPX)
        self.assertAlmostEqual(keys["alpha_key_speed_max_gamepx_s"], RUN_DEFAULT_SPEED_GAMEPX)
        print(json.dumps({"source_animation_not_runtime": {**keys, **metrics}}, ensure_ascii=False))

    def test_world_geometry_has_forward_lean_and_stance_recovery_contrast(self) -> None:
        support_extensions = {side: [] for side in ("L", "R")}
        recovery_bends = {side: [] for side in ("L", "R")}
        for index, pose in enumerate(self.animation.poses[:-1]):
            transforms = forward_transforms(pose.rotations, pose.com_position)
            hip_axis, neck = transforms["Pelvis"][0], transforms["Neck"][0]
            lean = math.degrees(math.atan2(neck[0] - hip_axis[0], hip_axis[1] - neck[1]))
            self.assertGreater(lean, 30.0)
            self.assertLess(lean, 40.0)
            for side, offset in (("L", 0.0), ("R", 0.5)):
                hip, knee, ankle = (transforms[f"{joint}_{side}"][0] for joint in ("Thigh", "Shin", "Foot"))
                upper, lower = math.dist(hip, knee), math.dist(knee, ankle)
                extension = math.dist(hip, ankle) / (upper + lower)
                cosine = (upper * upper + lower * lower - math.dist(hip, ankle)**2) / (2.0 * upper * lower)
                bend = 180.0 - math.degrees(math.acos(max(-1.0, min(1.0, cosine))))
                phase = (index / self.spec.intervals - offset) % 1.0
                if phase <= RUN_SUPPORT_FRACTION + action_poses.RUN_PHASE_EPSILON:
                    support_extensions[side].append(extension)
                elif phase <= action_poses.RUN_RECOVERY_END_FRACTION:
                    recovery_bends[side].append(bend)
        for side in ("L", "R"):
            self.assertGreater(min(support_extensions[side]), 0.82, f"{side} 承重段不能抱腿")
            self.assertLess(min(support_extensions[side]), 0.9, f"{side} 触地后应屈膝缓冲")
            self.assertGreater(max(support_extensions[side]), 0.96, f"{side} 后蹬应接近伸展")
            self.assertLess(max(support_extensions[side]), 0.99, f"{side} 不能锁膝")
            self.assertGreater(max(recovery_bends[side]), 80.0, f"{side} 离地后应折膝回收")

    def test_legacy_upright_torso_is_rejected_by_world_axis(self) -> None:
        poses = []
        for pose in self.animation.poses:
            rotations = {**pose.rotations, **dict(zip(action_poses.TORSO_BONES, map(math.radians, (4.0, 4.0, 6.0, 3.0))))}
            poses.append(replace(pose, rotations=rotations))
        with self.assertRaisesRegex(ValueError, "实际髋颈轴线"):
            validate_run_geometry(replace(self.animation, poses=tuple(poses)))

    def test_permanently_compressed_support_legs_are_rejected(self) -> None:
        poses = []
        for pose in self.animation.poses:
            rotations = {**pose.rotations}
            for side in ("L", "R"):
                rotations[f"Shin_{side}"] += math.radians(35.0)
            poses.append(replace(pose, rotations=rotations))
        with self.assertRaisesRegex(ValueError, "支撑腿.*始终蜷腿"):
            validate_run_geometry(replace(self.animation, poses=tuple(poses)))

    def test_load_absorption_precedes_push_off(self) -> None:
        phases = (0.0, RUN_SUPPORT_FRACTION * 0.4, RUN_SUPPORT_FRACTION)
        for side, offset in (("L", 0.0), ("R", 0.5)):
            angles = [action_poses.run_world_leg_angles(self.animation.poses[round((phase + offset) * self.spec.intervals)], side) for phase in phases]
            contact, compression, push = angles
            self.assertGreater(compression[1], contact[1] + 20.0, f"{side} 触地后须屈膝承重，不可直腿弹跳")
            self.assertLess(push[1], compression[1] - 20.0, f"{side} 缓冲后须伸腿后蹬")
            self.assertGreater(push[0], 90.0, f"{side} 后蹬时膝应位于髋后")

    def test_run_hands_trail_elbows_and_hips(self) -> None:
        for pose in self.animation.poses[:-1]:
            transforms = forward_transforms(pose.rotations, pose.com_position)
            pelvis = transforms["Pelvis"][0]
            for side in ("L", "R"):
                elbow = transforms[f"Forearm_{side}"][0]
                wrist = transforms[f"Hand_{side}"][0]
                self.assertLess(wrist[0], pelvis[0], f"{side} 手腕必须后掠，不能垂在腿前")
                self.assertLess(wrist[0] - elbow[0], -0.6 * math.dist(elbow, wrist), f"{side} 前臂须随上臂向后延伸")

    def test_ground_contact_outlasts_flight_without_double_support(self) -> None:
        grounded = 0
        for pose in self.animation.poses[:-1]:
            touching = [abs(goal.y - GROUND_Y) <= action_poses.CONTACT_TOLERANCE for goal in pose.feet]
            self.assertLessEqual(sum(touching), 1, "跑步不能双脚同时支撑")
            grounded += any(touching)
        contact_fraction = grounded / self.spec.intervals
        self.assertGreater(contact_fraction, 0.55, "不能用长时间悬空代替双腿交替跑动")
        self.assertLess(contact_fraction, 0.8, "跑步仍须保留短腾空段")

    def test_body_does_not_lurch_fore_and_aft(self) -> None:
        transforms = forward_transforms(self.animation.poses[0].rotations, self.animation.poses[0].com_position)
        hip, knee, ankle = (transforms[f"{joint}_L"][0] for joint in ("Thigh", "Shin", "Foot"))
        leg_length = math.dist(hip, knee) + math.dist(knee, ankle)
        for axis in range(2):
            values = [pose.com_position[axis] for pose in self.animation.poses]
            self.assertLess(max(values) - min(values), 0.16 * leg_length, "重心不应靠前后大幅抽动补偿脚步")

    def test_run_arms_remain_fixed_relative_to_chest(self) -> None:
        for side in ("L", "R"):
            for joint in ("Clavicle", "UpperArm", "Forearm", "Hand"):
                values = [pose.rotations[f"{joint}_{side}"] for pose in self.animation.poses]
                self.assertLess(max(values) - min(values), action_poses.CONTACT_TOLERANCE, f"{joint}_{side} 不应独立摆动")
            positions = []
            for pose in self.animation.poses:
                transforms = forward_transforms(pose.rotations, pose.com_position)
                chest, angle = transforms["Chest"]
                wrist, _ = transforms[f"Hand_{side}"]
                delta = wrist[0] - chest[0], wrist[1] - chest[1]
                positions.append((delta[0] * math.cos(angle) + delta[1] * math.sin(angle), -delta[0] * math.sin(angle) + delta[1] * math.cos(angle)))
            self.assertLess(max(math.dist(positions[0], position) for position in positions), action_poses.CONTACT_TOLERANCE)

    def test_independent_arm_and_wrist_swing_are_rejected(self) -> None:
        index = self.spec.intervals // 4
        pose = self.animation.poses[index]
        for name in ("UpperArm_L", "Forearm_R", "Hand_L"):
            moving_arm = replace(pose, rotations={**pose.rotations, name: pose.rotations[name] + math.radians(10.0)})
            with self.assertRaisesRegex(ValueError, "手臂.*固定"):
                validate_run_phases(self.with_pose(index, moving_arm), self.profiles)

    def test_suspended_actual_support_sole_is_rejected(self) -> None:
        index = round(self.spec.intervals * RUN_SUPPORT_FRACTION / 2.0)
        pose = self.animation.poses[index]
        suspended = replace(pose, com_position=(pose.com_position[0], pose.com_position[1] - INVALID_SOLE_OFFSET_SOURCEPX))
        with self.assertRaisesRegex(ValueError, "支撑脚悬空"):
            validate_run_phases(self.with_pose(index, suspended), self.profiles)

    def test_swing_sole_pressed_below_ground_is_rejected(self) -> None:
        index = round(self.spec.intervals * 0.4)
        pose = self.animation.poses[index]
        shift = GROUND_Y + INVALID_SOLE_OFFSET_SOURCEPX - pose.feet[0].y
        underground = replace(pose, com_position=(pose.com_position[0], pose.com_position[1] + shift))
        with self.assertRaisesRegex(ValueError, "穿地"):
            validate_run_phases(self.with_pose(index, underground), self.profiles)

    def test_same_phase_feet_are_rejected(self) -> None:
        index = round(self.spec.intervals * RUN_SUPPORT_FRACTION / 2.0)
        phase = index / self.spec.intervals
        design = run_design(phase, self.profiles)
        same_phase = realize_pose(replace(design, feet={**design.feet, "R": action_poses.foot(SOURCE_ORIGIN[0], 0.0)}), self.profiles)
        with self.assertRaisesRegex(ValueError, "错相位"):
            validate_run_phases(self.with_pose(index, same_phase), self.profiles)

    def test_fk_world_angles_half_cycle_and_contact_translation_preserve_joints(self) -> None:
        metrics = action_poses.validate_run_gait(self.animation)
        self.assertLessEqual(metrics["run_com_x_excursion_sourcepx"], action_poses.RUN_COM_EXCURSION_LIMIT_SOURCEPX)
        self.assertLessEqual(metrics["run_com_y_excursion_sourcepx"], action_poses.RUN_COM_EXCURSION_LIMIT_SOURCEPX)
        for index, pose in enumerate(self.animation.poses[:-1]):
            phase = index / self.spec.intervals
            self.assertEqual(pose.rotations, action_poses.run_fk_rotations(phase))
            shifted = self.animation.poses[(index + self.spec.intervals // 2) % self.spec.intervals]
            left = action_poses.run_world_leg_angles(pose, "L")
            right = action_poses.run_world_leg_angles(shifted, "R")
            for first, second in zip(left, right):
                self.assertAlmostEqual(first, second, places=6)
            self.assertGreater(left[1], 0.0)
        for name in action_poses.TORSO_BONES + ("Neck", "Head"):
            self.assertEqual(len({pose.rotations[name] for pose in self.animation.poses}), 1)

    def test_com_support_flight_and_loop_match_endpoint_velocities(self) -> None:
        step = COM_DERIVATIVE_STEP_PHASE
        for phase in (0.0, RUN_SUPPORT_FRACTION, 0.5, 0.5 + RUN_SUPPORT_FRACTION):
            before, at, after = (action_poses.run_com_offset(phase + offset, self.profiles) for offset in (-step, 0.0, step))
            for axis in (0, 1):
                incoming = (at[axis] - before[axis]) / (step * self.spec.seconds)
                outgoing = (after[axis] - at[axis]) / (step * self.spec.seconds)
                self.assertLess(abs(incoming - outgoing), COM_VELOCITY_SEAM_TOLERANCE_SOURCEPX_S, (phase, axis))

    def test_fk_run_zero_is_recovered_by_ik_along_connection_neighbors(self) -> None:
        start = self.animation.poses[0]
        reconstructed = realize_pose(run_design(0.0, self.profiles), self.profiles)
        self.assertLess(action_poses.pose_distance(start, reconstructed), action_poses.CONTACT_TOLERANCE)
        for name, designer in (("jump_start", action_poses.jump_start_design), ("land", action_poses.land_design)):
            spec = next(spec for spec in ACTION_SPECS if spec.name == name)
            indices = range(3) if name == "jump_start" else range(spec.intervals - 2, spec.intervals + 1)
            for index in indices:
                expected = realize_pose(designer(index / spec.intervals, self.profiles), self.profiles)
                self.assertLess(action_poses.pose_distance(action_pose(spec, index, self.profiles), expected), action_poses.CONTACT_TOLERANCE)
            endpoint = action_pose(spec, 0 if name == "jump_start" else spec.intervals, self.profiles)
            self.assertLess(action_poses.pose_distance(start, endpoint), action_poses.CONTACT_TOLERANCE)

    def test_compressed_transitions_keep_reachable_alpha_foot_targets(self) -> None:
        for name in ("jump_start", "land"):
            spec = next(spec for spec in ACTION_SPECS if spec.name == name)
            for index in range(spec.intervals + 1):
                with self.subTest(action=name, sample=index):
                    pose = action_pose(spec, index, self.profiles)
                    self.assertLessEqual(action_poses.validate_contact(pose, self.profiles), action_poses.CONTACT_TOLERANCE)

    def test_actual_pre_fix_second_recovery_sequence_is_rejected(self) -> None:
        fixture = json.loads((PROJECT_ROOT / "tests/fixtures/rig_v2_run_pre_fix_poses.json").read_text(encoding="utf-8"))
        self.assertEqual(fixture["tracks"], [bone.name for bone in BONES] + ["COM.position.x", "COM.position.y"])
        bends = []
        for sample in fixture["gait_recovery"]["samples"]:
            values = sample["tracks"]
            self.assertEqual(len(values), len(BONES) + 2)
            pose = action_poses.Pose({bone.name: value for bone, value in zip(BONES, values)}, tuple(values[-2:]), ())
            bends.append(action_poses.run_world_leg_angles(pose, "L")[1])
        self.assertEqual(action_poses.cycle_peak_count(bends, action_poses.RUN_RECOVERY_BEND_MIN_DEGREES), 2)
        with self.assertRaisesRegex(ValueError, "一次主要折膝回收.*二次回收"):
            action_poses.validate_run_recovery(bends, "L")

    def test_wrong_signed_knee_branch_is_rejected(self) -> None:
        poses = []
        for pose in self.animation.poses:
            rotations = {**pose.rotations}
            for side in ("L", "R"):
                bend = action_poses.run_world_leg_angles(pose, side)[1]
                rotations[f"Shin_{side}"] -= math.radians(2.0 * bend)
            poses.append(replace(pose, rotations=rotations))
        with self.assertRaisesRegex(ValueError, "有符号膝角"):
            action_poses.validate_run_gait(replace(self.animation, poses=tuple(poses)))

    def test_old70_alpha_sweep_is_rejected(self) -> None:
        old_sweep = LEGACY_WORLD_SWEEP_GAMEPX * self.spec.seconds / PLAYER_SCALE
        with patch.object(action_poses, "RUN_SWEEP_SOURCEPX_PER_CYCLE", old_sweep):
            old_run = build_run(self.spec, self.profiles)
        old_metrics = inspect_run_support(old_run, self.profiles)
        self.assertLess(old_metrics["run_support_speed_max_gamepx_s"], RUN_DEFAULT_SPEED_GAMEPX - action_poses.RUN_SPEED_TOLERANCE_GAMEPX)
        with self.assertRaisesRegex(ValueError, "后扫不匹配默认速度"):
            validate_run_phases(old_run, self.profiles)


if __name__ == "__main__":
    unittest.main(verbosity=2)
