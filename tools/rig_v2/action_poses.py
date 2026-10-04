import math
from dataclasses import dataclass, replace
from functools import lru_cache

from action_kinematics import (
    BootProfile, COM_REST_Y, FootGoal, Pose, blend_poses, boot_height,
    forward_transforms, place_feet, set_segment_direction,
)
from action_silhouettes import outline_points, sole_contact_indices, sole_contact_x
from rig_definition import BONES, BONE_BY_NAME, PLAYER_SCALE, SOURCE_ORIGIN

GROUND_Y = SOURCE_ORIGIN[1]
CONTACT_TOLERANCE = 1e-6
INTERPOLATED_CONTACT_TOLERANCE = 1.0
CONTACT_SUBDIVISIONS = 4
RUN_CYCLE_SECONDS = 0.33
RUN_SAMPLE_INTERVALS = 120
RUN_SUPPORT_FRACTION = 0.3
RUN_LOAD_FRACTION = 0.4
RUN_CONTACT_FRACTION_LIMITS = (0.55, 0.8)
RUN_LOAD_BEND_CHANGE_MIN_DEGREES = 20.0
RUN_FOREARM_TRAIL_RATIO_MIN = 0.6
RUN_DEFAULT_SPEED_GAMEPX = 400.0
RUN_SPEED_TOLERANCE_GAMEPX = RUN_DEFAULT_SPEED_GAMEPX * 0.02
RUN_SUPPORT_SAMPLES = 37
RUN_PHASE_EPSILON = 1e-6
RUN_HALF_STRIDE = RUN_DEFAULT_SPEED_GAMEPX * RUN_CYCLE_SECONDS * RUN_SUPPORT_FRACTION / (2.0 * PLAYER_SCALE)
RUN_SWING_CLEARANCE = 180.0
RUN_COM_X = 18.0
RUN_PELVIS_ANGLE = 20.0
RUN_TORSO = (RUN_PELVIS_ANGLE, 12.0, 11.0, 5.0)
RUN_TRANSITION_COMPRESSION_OFFSET = 285.0
RUN_TRANSITION_FOOT_GATHER_RATIO = 0.2
RUN_RECOVERY_END_FRACTION = 0.62
RUN_COM_DERIVATIVE_PHASE = 1e-5
RUN_COM_EXCURSION_LIMIT_SOURCEPX = 100.0
# 骨盆只保留低频分量：k=2 是双脚交替支撑的真实起伏，k≥4 是步态解带来的整身高频颤抖。
RUN_PELVIS_HARMONICS = 3
RUN_PELVIS_SAMPLE_INTERVALS = 192
# 各节相对平均倾角的前倾振幅（度），随重心下沉压前倾、蹬伸到顶点回正。
RUN_TORSO_LEAN_WAVE = (3.0, 2.5, 2.0, 1.5)
RUN_TORSO_LEAN_HEAD_WAVE = 2.0
# 蹬伸顶点步态解让腿轻微过伸（约 0.5 源像素）；骨盆平滑把脚目标补正后需要这点容差才能闭合。
RUN_LEG_REACH_SLACK_SOURCEPX = 2.0
RUN_FLIGHT_CLEARANCE_SOURCEPX = 24.0
RUN_JOINT_STEP_LIMIT_DEGREES = 12.0
JUMP_START_SAMPLE_INTERVALS = 28
JUMP_START_SECONDS = 0.16
JUMP_AIR_SECONDS = 0.30
DOUBLE_JUMP_SECONDS = 0.32
LAND_SECONDS = 0.20
LAND_SAMPLE_INTERVALS = 24
SLIDE_SECONDS = 0.58
SLIDE_SAMPLE_INTERVALS = 40
SLIDE_ENTRY_FRACTION = 0.06
RUN_JOINT_STAGES = (
    (0.0, 50.0, 25.0),
    (0.12, 66.0, 65.0),
    (0.3, 118.0, 22.0),
    (0.4, 130.0, 85.0),
    (0.55, 92.0, 104.0),
    (0.7, 40.0, 88.0),
    (0.84, 32.0, 52.0),
    (1.0, 50.0, 25.0),
)
RUN_FOOT_ANGLE_STAGES = (
    (0.0, 0.0), (0.3, 0.0), (0.4, 90.0), (0.55, 85.0),
    (0.7, 20.0), (0.84, -8.0), (1.0, 0.0),
)
RUN_HIP_NECK_LEAN_LIMITS_DEGREES = (30.0, 40.0)
RUN_SUPPORT_EXTENSION_MIN = 0.82
RUN_SUPPORT_COMPRESSION_MAX = 0.9
RUN_SUPPORT_EXTENSION_PEAK_MIN = 0.95
RUN_LEG_EXTENSION_LIMIT = 0.997
RUN_RECOVERY_BEND_MIN_DEGREES = 65.0
RUN_SWEEP_SOURCEPX_PER_CYCLE = RUN_DEFAULT_SPEED_GAMEPX * RUN_CYCLE_SECONDS / PLAYER_SCALE
RUN_TRAILING_DIRECTIONS = (
    ("HairRoot", "Hair_01", 140.0),
    ("RibbonRoot", "Ribbon_L_01", 175.0),
    ("Ribbon_R_01", "Ribbon_R_02", 165.0),
    ("CoatBack_L_01", "CoatBack_L_02", 165.0),
    ("CoatBack_R_01", "CoatBack_R_02", 158.0),
    ("ClothFront_L", "ClothFront_L_02", 145.0),
    ("ClothFront_R", "ClothFront_R_02", 140.0),
    ("WaistTasselRoot", "WaistTassel_01", 140.0),
)
TUCK_ENTRY_FRACTION = 0.2
TUCK_FOOT_ARC = 200.0
CLOTH_TUCK_LEAD = 1.3
TORSO_BONES = ("Pelvis", "Spine_01", "Spine_02", "Chest")
TRAILING_CHAINS = (
    (("HairRoot", "Hair_01", "Hair_02", "Hair_03", "Hair_04"), 1.8, 0.055, 1.0),
    (("RibbonRoot", "Ribbon_L_01", "Ribbon_L_02", "Ribbon_L_03"), 2.4, 0.07, 1.2),
    (("Ribbon_R_01", "Ribbon_R_02", "Ribbon_R_03"), 2.2, 0.085, 1.1),
    (("ClothFront_L", "ClothFront_L_02", "ClothFront_L_03"), 2.2, 0.075, 0.65),
    (("ClothFront_R", "ClothFront_R_02", "ClothFront_R_03"), 2.4, 0.09, -0.65),
    (("CoatBack_L_01", "CoatBack_L_02", "CoatBack_L_03"), 2.4, 0.10, 1.2),
    (("CoatBack_R_01", "CoatBack_R_02", "CoatBack_R_03"), 2.2, 0.095, -0.7),
    (("WaistTasselRoot", "WaistTassel_01", "WaistTassel_02"), 1.5, 0.065, -0.3),
)


@dataclass(frozen=True)
class ArmPlan:
    upper: float
    lower: float
    wrist: float = 0.0
    clavicle: float | None = None

    @property
    def clavicle_angle(self) -> float:
        return -0.04 * (self.upper - 90.0) if self.clavicle is None else self.clavicle


RUN_ARMS_CHEST_RELATIVE = {
    "L": ArmPlan(105.0, 127.0, -4.0, -0.4),
    "R": ArmPlan(98.0, 113.0, 4.0, 0.0),
}


@dataclass(frozen=True)
class PoseDesign:
    com_offset: tuple[float, float]
    torso: tuple[float, float, float, float]
    feet: dict[str, FootGoal]
    arms: dict[str, ArmPlan]
    trailing: dict[str, float]
    head_angle: float = 0.0


@dataclass(frozen=True)
class ActionSpec:
    name: str
    seconds: float
    loop: bool
    intervals: int


@dataclass(frozen=True)
class Action:
    spec: ActionSpec
    poses: tuple[Pose, ...]

    @property
    def times(self) -> list[float]:
        return [index * self.spec.seconds / self.spec.intervals for index in range(self.spec.intervals + 1)]


ACTION_SPECS = (
    ActionSpec("idle", 1.2, True, 48),
    ActionSpec("run", RUN_CYCLE_SECONDS, True, RUN_SAMPLE_INTERVALS),
    ActionSpec("jump_start", JUMP_START_SECONDS, False, JUMP_START_SAMPLE_INTERVALS),
    ActionSpec("jump_up", JUMP_AIR_SECONDS, True, 24),
    ActionSpec("double_jump", DOUBLE_JUMP_SECONDS, False, 32),
    ActionSpec("fall", JUMP_AIR_SECONDS, True, 24),
    ActionSpec("land", LAND_SECONDS, False, LAND_SAMPLE_INTERVALS),
    # 滑铲是一次性动作：开头切入、中段贴地、结尾抬身，不能循环否则第二次切入会弹。
    ActionSpec("slide", SLIDE_SECONDS, False, SLIDE_SAMPLE_INTERVALS),
)


def trailing_angles(phase: float, strength: float, bias: float) -> dict[str, float]:
    rotations = {}
    for names, amplitude, delay, direction in TRAILING_CHAINS:
        for index, name in enumerate(names):
            # 链节逐级延迟，不能把发带和衣摆复制成躯干同相摆动。
            wave = math.sin(math.tau * (phase - delay * (index + 1)))
            rotations[name] = bias * direction / (index + 1) + amplitude * strength * (1.0 + 0.25 * index) * wave
    return rotations


def foot(contact_x: float, clearance: float, angle: float = 0.0) -> FootGoal:
    return FootGoal(contact_x, GROUND_Y - clearance, angle)


def hermite_value(start: float, end: float, start_velocity: float, end_velocity: float, seconds: float, amount: float) -> float:
    squared, cubed = amount * amount, amount * amount * amount
    return (2.0 * cubed - 3.0 * squared + 1.0) * start + (cubed - 2.0 * squared + amount) * seconds * start_velocity + (-2.0 * cubed + 3.0 * squared) * end + (cubed - squared) * seconds * end_velocity


def periodic_slope(stages: tuple[tuple[float, float], ...], index: int) -> float:
    index %= len(stages) - 1
    time, value = stages[index]
    previous_time, previous = stages[index - 1] if index else (stages[-2][0] - 1.0, stages[-2][1])
    next_time, following = stages[index + 1]
    before, after = (value - previous) / (time - previous_time), (following - value) / (next_time - time)
    if before * after <= 0.0:
        return 0.0
    before_span, after_span = time - previous_time, next_time - time
    first_weight, second_weight = 2.0 * after_span + before_span, after_span + 2.0 * before_span
    return (first_weight + second_weight) / (first_weight / before + second_weight / after)


def periodic_value(phase: float, stages: tuple[tuple[float, float], ...]) -> float:
    phase %= 1.0
    for index, ((start_time, start), (end_time, end)) in enumerate(zip(stages, stages[1:])):
        if phase <= end_time:
            span = end_time - start_time
            return hermite_value(start, end, periodic_slope(stages, index), periodic_slope(stages, index + 1), span, (phase - start_time) / span)
    raise ValueError("run 关节曲线未覆盖循环")


def run_body_design(phase: float) -> PoseDesign:
    # 躯干随重心下沉压前倾、蹬伸到顶点回正；持械版手臂锁在躯干上，动感全部由躯干承接。
    wave = math.cos(2.0 * math.tau * phase)
    torso = tuple(base + amplitude * wave for base, amplitude in zip(RUN_TORSO, RUN_TORSO_LEAN_WAVE))
    chest_angle = sum(torso)
    arms = {side: replace(arm, upper=arm.upper + chest_angle, lower=arm.lower + chest_angle) for side, arm in RUN_ARMS_CHEST_RELATIVE.items()}
    return PoseDesign((0.0, 0.0), torso, {}, arms, run_trailing_angles(phase), head_angle=-RUN_TORSO_LEAN_HEAD_WAVE * wave)


def run_fk_rotations(phase: float) -> dict[str, float]:
    rotations, com_position = realize_body(run_body_design(phase))
    thigh_stages = tuple((time, direction) for time, direction, _ in RUN_JOINT_STAGES)
    knee_stages = tuple((time, bend) for time, _, bend in RUN_JOINT_STAGES)
    for side, offset in (("L", 0.0), ("R", 0.5)):
        local_phase = (phase - offset) % 1.0
        thigh = periodic_value(local_phase, thigh_stages)
        shin = thigh + periodic_value(local_phase, knee_stages)
        set_segment_direction(rotations, com_position, f"Thigh_{side}", f"Shin_{side}", math.radians(thigh))
        set_segment_direction(rotations, com_position, f"Shin_{side}", f"Foot_{side}", math.radians(shin))
        lower_angle = forward_transforms(rotations, com_position)[f"Shin_{side}"][1]
        rotations[f"Foot_{side}"] = math.radians(periodic_value(local_phase, RUN_FOOT_ANGLE_STAGES)) - lower_angle
    return rotations


def run_support_com(local_phase: float, profile: BootProfile) -> tuple[float, float]:
    offset = 0.0 if profile.side == "L" else 0.5
    transforms = forward_transforms(run_fk_rotations(local_phase + offset), (0.0, COM_REST_Y))
    initial = forward_transforms(run_fk_rotations(offset), (0.0, COM_REST_Y))
    indices = sole_contact_indices(profile)
    contact_x = sole_contact_x(outline_points(profile, transforms), indices)
    initial_x = sole_contact_x(outline_points(profile, initial), indices)
    return RUN_COM_X + initial_x - RUN_SWEEP_SOURCEPX_PER_CYCLE * local_phase - contact_x, GROUND_Y - boot_height(profile, transforms)


def run_support_velocity(local_phase: float, profile: BootProfile) -> tuple[float, float]:
    step = RUN_COM_DERIVATIVE_PHASE
    before, after = run_support_com(local_phase - step, profile), run_support_com(local_phase + step, profile)
    return tuple((end - start) / (2.0 * step) for start, end in zip(before, after))


def run_com_offset(phase: float, profiles: tuple[BootProfile, BootProfile]) -> tuple[float, float]:
    phase %= 1.0
    side = int(phase >= 0.5)
    half_phase = phase % 0.5
    if half_phase <= RUN_SUPPORT_FRACTION:
        return run_support_com(half_phase, profiles[side])
    start, end = run_support_com(RUN_SUPPORT_FRACTION, profiles[side]), run_support_com(0.0, profiles[1 - side])
    start_velocity = run_support_velocity(RUN_SUPPORT_FRACTION, profiles[side])
    end_velocity = run_support_velocity(0.0, profiles[1 - side])
    span = 0.5 - RUN_SUPPORT_FRACTION
    amount = (half_phase - RUN_SUPPORT_FRACTION) / span
    offset = tuple(hermite_value(start[axis], end[axis], start_velocity[axis], end_velocity[axis], span, amount) for axis in (0, 1))
    # 腾空余量在端点的位置与导数均为零，接地时不抖动，也不重写腿角。
    envelope = 16.0 * amount**2 * (1.0 - amount)**2
    return offset[0], offset[1] - RUN_FLIGHT_CLEARANCE_SOURCEPX * envelope


def _pelvis_series(values: list[float]) -> tuple[float, tuple[tuple[float, float, float], ...]]:
    points = len(values)
    mean = sum(values) / points
    terms = []
    for harmonic in range(1, RUN_PELVIS_HARMONICS + 1):
        turn = math.tau * harmonic
        real = sum(value * math.cos(turn * index / points) for index, value in enumerate(values)) * 2.0 / points
        imag = sum(value * math.sin(turn * index / points) for index, value in enumerate(values)) * 2.0 / points
        terms.append((turn, real, imag))
    return mean, tuple(terms)


def _series_value(series: tuple[float, tuple[tuple[float, float, float], ...]], phase: float) -> float:
    mean, terms = series
    return mean + sum(real * math.cos(turn * phase) + imag * math.sin(turn * phase) for turn, real, imag in terms)


@lru_cache(maxsize=2)
def pelvis_series(profiles: tuple[BootProfile, BootProfile]) -> tuple[tuple[float, tuple], tuple[float, tuple]]:
    """骨盆只保留低频分量：滤掉的高频部分由腿的 IK 吃掉，脚仍然精确踩在地面。"""
    exact_x, exact_y = [], []
    for index in range(RUN_PELVIS_SAMPLE_INTERVALS):
        offset = run_com_offset(index / RUN_PELVIS_SAMPLE_INTERVALS, profiles)
        exact_x.append(offset[0])
        exact_y.append(offset[1])
    return _pelvis_series(exact_x), _pelvis_series(exact_y)


def run_pose(phase: float, profiles: tuple[BootProfile, BootProfile]) -> Pose:
    """骨盆走平滑曲线，把被滤掉的高频位移补回到脚的目标上，由腿的 IK 吃掉。

    脚因此仍然精确踩在地面，而整身不再每帧反向抖动。
    """
    rotations = run_fk_rotations(phase)
    exact = run_com_offset(phase, profiles)
    x_series, y_series = pelvis_series(profiles)
    pelvis = _series_value(x_series, phase), _series_value(y_series, phase)
    com_position = pelvis[0], COM_REST_Y + pelvis[1]
    anchored = run_contact_pose(rotations, com_position, profiles)
    goals = tuple(replace(goal, x=goal.x + exact[0] - pelvis[0], y=goal.y + exact[1] - pelvis[1]) for goal in anchored.feet)
    solved = dict(rotations)
    place_feet(solved, com_position, goals, profiles, RUN_LEG_REACH_SLACK_SOURCEPX)
    return Pose(solved, com_position, goals)


def run_contact_pose(rotations: dict[str, float], com_position: tuple[float, float], profiles: tuple[BootProfile, BootProfile]) -> Pose:
    transforms = forward_transforms(rotations, com_position)
    feet = []
    for profile in profiles:
        position, angle = transforms[f"Foot_{profile.side}"]
        delta = profile.contact[0] - BONE_BY_NAME[f"Foot_{profile.side}"].position[0], profile.contact[1] - BONE_BY_NAME[f"Foot_{profile.side}"].position[1]
        contact_x = position[0] + delta[0] * math.cos(angle) - delta[1] * math.sin(angle)
        feet.append(FootGoal(contact_x, boot_height(profile, transforms), math.degrees(angle)))
    return Pose(rotations, com_position, tuple(feet))


def run_trailing_angles(phase: float) -> dict[str, float]:
    trailing = trailing_angles(phase, 0.75, 0.0)
    parents = {"Head": 0.0, "Pelvis": RUN_PELVIS_ANGLE}
    for start, end, direction in RUN_TRAILING_DIRECTIONS:
        bone, tip = BONE_BY_NAME[start], BONE_BY_NAME[end]
        rest_direction = math.degrees(math.atan2(tip.position[1] - bone.position[1], tip.position[0] - bone.position[0]))
        parent_angle = parents[bone.parent]
        trailing[start] += direction - rest_direction - parent_angle
        parents[start] = parent_angle + trailing[start]
    return trailing


def run_design(phase: float, profiles: tuple[BootProfile, BootProfile]) -> PoseDesign:
    pose = run_pose(phase, profiles)
    return replace(run_body_design(phase), com_offset=(pose.com_position[0], pose.com_position[1] - COM_REST_Y), feet=dict(zip(("L", "R"), pose.feet)))


def idle_design(phase: float) -> PoseDesign:
    breath = math.sin(math.tau * phase)
    return PoseDesign(
        (3.0 * breath, 65.0 + 5.0 * breath),
        (0.0, 0.6 * breath, 0.5 * breath, -0.2 * breath),
        {"L": foot(500.0, 0.0), "R": foot(760.0, 0.0)},
        {"L": ArmPlan(108.0 + breath, 101.0 + breath, 1.0), "R": ArmPlan(73.0 - breath, 65.0 - breath, -1.0)},
        trailing_angles(phase, 0.35, 0.0),
        0.25 * breath,
    )


def airborne_design() -> PoseDesign:
    return PoseDesign(
        (18.0, 105.0), (4.0, 4.0, 6.0, 2.0),
        {"L": foot(530.0, 130.0, -8.0), "R": foot(710.0, 75.0, 5.0)},
        {"L": ArmPlan(70.0, -5.0, -4.0), "R": ArmPlan(125.0, 40.0, 5.0)},
        trailing_angles(0.0, 0.8, 6.0),
    )


def flight_design(phase: float, falling: bool) -> PoseDesign:
    base = airborne_design()
    wave = math.sin(math.tau * phase)
    magnitude = 1.0 - math.cos(math.tau * phase)
    direction = 1.0 if falling else -1.0
    trailing = trailing_angles(phase, 0.8, 6.0)
    return replace(
        base,
        com_offset=(18.0 + 3.0 * wave, 105.0 + direction * 5.0 * magnitude),
        torso=(4.0, 4.0 + direction * 0.7 * magnitude, 6.0 + direction * 0.5 * magnitude, 2.0),
        feet={"L": foot(530.0 + 8.0 * wave, 130.0 - direction * 10.0 * magnitude, -8.0 + 2.0 * wave), "R": foot(710.0 - 8.0 * wave, 75.0 + direction * 8.0 * magnitude, 5.0 - 2.0 * wave)},
        arms={"L": ArmPlan(70.0 + 3.0 * wave, -5.0 + direction * 4.0 * magnitude, -4.0), "R": ArmPlan(125.0 - 3.0 * wave, 40.0 - direction * 4.0 * magnitude, 5.0)},
        trailing=trailing,
    )


def blend_value(first: float, second: float, amount: float) -> float:
    return first + (second - first) * amount


def blend_design(first: PoseDesign, second: PoseDesign, amount: float) -> PoseDesign:
    feet, arms = {}, {}
    for side in ("L", "R"):
        start, end = first.feet[side], second.feet[side]
        feet[side] = FootGoal(*(blend_value(getattr(start, field), getattr(end, field), amount) for field in ("x", "y", "angle", "toe")))
        start_arm, end_arm = first.arms[side], second.arms[side]
        arms[side] = ArmPlan(
            *(blend_value(getattr(start_arm, field), getattr(end_arm, field), amount) for field in ("upper", "lower", "wrist")),
            clavicle=blend_value(start_arm.clavicle_angle, end_arm.clavicle_angle, amount),
        )
    return PoseDesign(
        tuple(blend_value(value, second.com_offset[axis], amount) for axis, value in enumerate(first.com_offset)),
        tuple(blend_value(value, second.torso[index], amount) for index, value in enumerate(first.torso)),
        feet, arms,
        {name: blend_value(value, second.trailing[name], amount) for name, value in first.trailing.items()},
        blend_value(first.head_angle, second.head_angle, amount),
    )


def staged_design(phase: float, stages: tuple[tuple[float, PoseDesign], ...]) -> PoseDesign:
    for (start_time, start), (end_time, end) in zip(stages, stages[1:]):
        if phase <= end_time:
            amount = (phase - start_time) / (end_time - start_time)
            return blend_design(start, end, amount * amount * (3.0 - 2.0 * amount))
    return stages[-1][1]


def gathered_transition_feet(feet: dict[str, FootGoal]) -> dict[str, FootGoal]:
    # 后收脚拉平并落地时须向髋下收拢，原水平落点可能超出两段腿长。
    return {side: foot(blend_value(goal.x, SOURCE_ORIGIN[0], RUN_TRANSITION_FOOT_GATHER_RATIO), 0.0) for side, goal in feet.items()}


def jump_start_design(phase: float, profiles: tuple[BootProfile, BootProfile]) -> PoseDesign:
    start = run_design(0.0, profiles)
    compressed = replace(start, com_offset=(18.0, RUN_TRANSITION_COMPRESSION_OFFSET), feet=gathered_transition_feet(start.feet), torso=(6.0, 7.0, 10.0, 3.0), arms={"L": ArmPlan(140.0, 65.0, -4.0), "R": ArmPlan(120.0, 35.0, 4.0)}, trailing=trailing_angles(0.12, 1.0, 3.0))
    launched = replace(start, com_offset=(18.0, 85.0), feet={"L": foot(610.0, 45.0), "R": foot(760.0, 45.0)}, arms={"L": ArmPlan(65.0, -10.0, -4.0), "R": ArmPlan(80.0, 0.0, 4.0)}, trailing=trailing_angles(0.24, 1.0, 6.0))
    return staged_design(phase, ((0.0, start), (0.38, compressed), (0.72, launched), (1.0, airborne_design())))


def double_jump_design(phase: float) -> PoseDesign:
    trailing = trailing_angles(0.32, 0.5, 0.0)
    trailing.update(
        CoatBack_L_01=0.0, CoatBack_L_02=150.0, CoatBack_L_03=0.0,
        CoatBack_R_01=-175.0, CoatBack_R_02=160.0, CoatBack_R_03=0.0,
        ClothFront_L=35.0, ClothFront_L_02=140.0, ClothFront_L_03=0.0,
        ClothFront_R=-140.0, ClothFront_R_02=150.0, ClothFront_R_03=0.0,
    )
    tuck = PoseDesign(
        (-10.0, 500.0), (24.0, 65.0, 65.0, 40.0),
        {"L": foot(750.0, 450.0, -18.0), "R": foot(700.0, 450.0, 12.0)},
        {"L": ArmPlan(160.0, -90.0, -8.0), "R": ArmPlan(160.0, -90.0, 8.0)},
        trailing, -5.0,
    )
    amount = min(1.0, (math.sin(math.pi * phase) / math.sin(math.pi * TUCK_ENTRY_FRACTION))**2)
    start = airborne_design()
    design = blend_design(start, tuck, amount)
    cloth_amount = min(1.0, amount * CLOTH_TUCK_LEAD)
    trailing = {name: blend_value(start.trailing[name], degrees, cloth_amount) for name, degrees in tuck.trailing.items()}
    # 足目标从髋下移至髋上时绕开两骨腿的内侧不可达区，不能沿直线穿过髋部。
    arc = TUCK_FOOT_ARC * math.sin(math.pi * amount)
    return replace(design, trailing=trailing, feet={side: replace(goal, x=goal.x + arc) for side, goal in design.feet.items()})


def land_design(phase: float, profiles: tuple[BootProfile, BootProfile]) -> PoseDesign:
    recovery = run_design(0.0, profiles)
    impact = replace(recovery, com_offset=(25.0, RUN_TRANSITION_COMPRESSION_OFFSET), feet=gathered_transition_feet(recovery.feet), torso=(6.0, 8.0, 9.0, 4.0), arms={"L": ArmPlan(100.0, 22.0, -5.0), "R": ArmPlan(115.0, 32.0, 5.0)}, trailing=trailing_angles(0.22, 1.2, 3.0))
    return staged_design(phase, ((0.0, airborne_design()), (0.25, impact), (1.0, recovery)))


def slide_design(phase: float) -> PoseDesign:
    wave = math.sin(math.tau * phase)
    trailing = trailing_angles(phase, 0.65, 0.0)
    trailing.update(
        CoatBack_L_01=35.0 + wave, CoatBack_L_02=0.0, CoatBack_L_03=0.0,
        CoatBack_R_01=-120.0 + wave, CoatBack_R_02=0.0, CoatBack_R_03=0.0,
        ClothFront_L=45.0 + wave, ClothFront_L_02=0.0, ClothFront_L_03=0.0,
        ClothFront_R=-115.0 + wave, ClothFront_R_02=0.0, ClothFront_R_03=0.0,
    )
    return PoseDesign(
        (20.0, 465.0),
        (24.0, 40.0 + wave, 55.0 + wave, 40.0),
        {"L": foot(390.0, 0.0), "R": foot(1100.0, 0.0)},
        {"L": ArmPlan(140.0 + 3.0 * wave, 70.0 + 2.0 * wave, -6.0), "R": ArmPlan(78.0 - 3.0 * wave, 8.0 - 2.0 * wave, 6.0)},
        trailing, 15.0,
    )


DESIGNERS = {
    "idle": idle_design,
    "jump_up": lambda phase: flight_design(phase, False),
    "double_jump": double_jump_design,
    "fall": lambda phase: flight_design(phase, True),
    "slide": slide_design,
}


def realize_body(design: PoseDesign) -> tuple[dict[str, float], tuple[float, float]]:
    rotations = {bone.name: 0.0 for bone in BONES}
    com_position = design.com_offset[0], COM_REST_Y + design.com_offset[1]
    for name, degrees in zip(TORSO_BONES, design.torso):
        rotations[name] = math.radians(degrees)
    torso_angle = sum(rotations[name] for name in TORSO_BONES)
    rotations["Neck"] = -0.7 * torso_angle
    rotations["Head"] = math.radians(design.head_angle) - 0.3 * torso_angle
    for side in ("L", "R"):
        arm = design.arms[side]
        rotations[f"Clavicle_{side}"] = math.radians(arm.clavicle_angle)
        set_segment_direction(rotations, com_position, f"UpperArm_{side}", f"Forearm_{side}", math.radians(arm.upper))
        set_segment_direction(rotations, com_position, f"Forearm_{side}", f"Hand_{side}", math.radians(arm.lower))
        rotations[f"Hand_{side}"] = math.radians(arm.wrist)
    for name, degrees in design.trailing.items():
        rotations[name] = math.radians(degrees)
    return rotations, com_position


def realize_pose(design: PoseDesign, profiles: tuple[BootProfile, BootProfile]) -> Pose:
    rotations, com_position = realize_body(design)
    feet = tuple(design.feet[side] for side in ("L", "R"))
    place_feet(rotations, com_position, feet, profiles)
    return Pose(rotations, com_position, feet)


def action_pose(spec: ActionSpec, index: int, profiles: tuple[BootProfile, BootProfile]) -> Pose:
    phase = index / spec.intervals
    try:
        if spec.name == "run":
            return run_pose(phase, profiles)
        if spec.name == "jump_start":
            design = jump_start_design(phase, profiles)
        elif spec.name == "land":
            design = land_design(phase, profiles)
        else:
            design = DESIGNERS[spec.name](phase)
        return realize_pose(design, profiles)
    except ValueError as error:
        raise ValueError(f"{spec.name} 第 {index}/{spec.intervals} 帧：{error}") from error


def build_actions(profiles: tuple[BootProfile, BootProfile]) -> tuple[Action, ...]:
    actions = []
    for spec in ACTION_SPECS:
        poses = [action_pose(spec, index, profiles) for index in range(spec.intervals + 1)]
        if spec.loop:
            poses[-1] = poses[0]
        actions.append(Action(spec, tuple(poses)))
    return tuple(actions)


def pose_distance(first: Pose, second: Pose) -> float:
    return max(*(abs(first.rotations[name] - second.rotations[name]) for name in first.rotations), *(abs(first.com_position[axis] - second.com_position[axis]) for axis in range(2)))


def validate_contact(pose: Pose, profiles: tuple[BootProfile, BootProfile]) -> float:
    transforms = forward_transforms(pose.rotations, pose.com_position)
    maximum_error = max(abs(boot_height(profile, transforms) - goal.y) for profile, goal in zip(profiles, pose.feet))
    if maximum_error > CONTACT_TOLERANCE:
        raise ValueError(f"alpha 蒙皮鞋底未对准目标：{maximum_error:.6f}px")
    return maximum_error


def validate_action_samples(actions: tuple[Action, ...], profiles: tuple[BootProfile, BootProfile]) -> dict[str, float]:
    maximum_contact_error, maximum_penetration = 0.0, 0.0
    for action in actions:
        for pose in action.poses:
            if set(pose.rotations) != {bone.name for bone in BONES} or not all(math.isfinite(value) for value in (*pose.rotations.values(), *pose.com_position)):
                raise ValueError(f"动作骨骼契约不完整：{action.spec.name}")
            if pose.rotations["Root"] != 0.0:
                raise ValueError(f"整身翻滚不能写入 Root：{action.spec.name}")
            maximum_contact_error = max(maximum_contact_error, validate_contact(pose, profiles))
        if action.spec.loop and pose_distance(action.poses[0], action.poses[-1]) != 0.0:
            raise ValueError(f"循环动作首尾不一致：{action.spec.name}")
        for first, second in zip(action.poses, action.poses[1:]):
            for subdivision in range(1, CONTACT_SUBDIVISIONS):
                interpolated = blend_poses(first, second, subdivision / CONTACT_SUBDIVISIONS)
                transforms = forward_transforms(interpolated.rotations, interpolated.com_position)
                penetration = max(boot_height(profile, transforms) - GROUND_Y for profile in profiles)
                maximum_penetration = max(maximum_penetration, penetration)
        if maximum_penetration > INTERPOLATED_CONTACT_TOLERANCE:
            raise ValueError(f"插值使鞋底穿过视觉接触面：{action.spec.name}, {maximum_penetration:.6f}px")
    validate_connections(actions)
    run_metrics = validate_run_phases(next(action for action in actions if action.spec.name == "run"), profiles)
    return {"key_contact_error_px": maximum_contact_error, "interpolated_penetration_px": maximum_penetration, **run_metrics}


def validate_connections(actions: tuple[Action, ...]) -> None:
    by_name = {action.spec.name: action for action in actions}
    connections = (("run", 0, "jump_start", 0), ("jump_start", -1, "jump_up", 0), ("jump_up", 0, "fall", 0), ("fall", 0, "land", 0), ("land", -1, "run", 0), ("double_jump", 0, "jump_up", 0), ("double_jump", -1, "jump_up", 0))
    for start, start_index, end, end_index in connections:
        if pose_distance(by_name[start].poses[start_index], by_name[end].poses[end_index]) > CONTACT_TOLERANCE:
            raise ValueError(f"跨动作连接端点不连续：{start}→{end}")


def sampled_run_pose(action: Action, phase: float, profiles: tuple[BootProfile, BootProfile]) -> Pose:
    position = (phase % 1.0) * action.spec.intervals
    index = int(position)
    pose = blend_poses(action.poses[index], action.poses[index + 1], position - index)
    # 足目标不是资源轨；FK 插值帧的轮廓接触点必须从同一帧的实际蒙皮读取。
    contact = run_contact_pose(pose.rotations, pose.com_position, profiles)
    feet = tuple(replace(goal, y=GROUND_Y) if (phase - side * 0.5) % 1.0 <= RUN_SUPPORT_FRACTION + RUN_PHASE_EPSILON else goal for side, goal in enumerate(contact.feet))
    return replace(contact, feet=feet)


def validate_run_frame(pose: Pose, phase: float, profiles: tuple[BootProfile, BootProfile]) -> tuple[bool, bool]:
    transforms = forward_transforms(pose.rotations, pose.com_position)
    supports = []
    for side, (goal, profile) in enumerate(zip(pose.feet, profiles)):
        support = (phase - side * 0.5) % 1.0 <= RUN_SUPPORT_FRACTION + RUN_PHASE_EPSILON
        height = boot_height(profile, transforms)
        if height > GROUND_Y + INTERPOLATED_CONTACT_TOLERANCE:
            raise ValueError(f"run 摆脚/支撑脚穿地：{profile.side}")
        if support:
            if abs(goal.y - GROUND_Y) > CONTACT_TOLERANCE or abs(height - GROUND_Y) > INTERPOLATED_CONTACT_TOLERANCE:
                raise ValueError(f"run 支撑脚悬空或错相位：{profile.side}")
        elif goal.y >= GROUND_Y - CONTACT_TOLERANCE:
            raise ValueError(f"run 摆脚未抬起或错相位：{profile.side}")
        if abs(height - goal.y) > INTERPOLATED_CONTACT_TOLERANCE:
            raise ValueError(f"run 实际 alpha 鞋底偏离阶段目标：{profile.side}")
        supports.append(support)
    if all(supports):
        raise ValueError("run 左右支撑必须交替，不能同相")
    if abs(transforms["Head"][1]) > CONTACT_TOLERANCE:
        raise ValueError("run 没有稳定头部")
    return tuple(supports)


def inspect_run_support(action: Action, profiles: tuple[BootProfile, BootProfile]) -> dict[str, float]:
    speeds, height_errors = [], []
    step_seconds = action.spec.seconds * RUN_SUPPORT_FRACTION / RUN_SUPPORT_SAMPLES
    for side, profile in enumerate(profiles):
        previous = None
        indices = sole_contact_indices(profile)
        for sample in range(RUN_SUPPORT_SAMPLES + 1):
            phase = side * 0.5 + RUN_SUPPORT_FRACTION * sample / RUN_SUPPORT_SAMPLES
            pose = sampled_run_pose(action, phase, profiles)
            points = outline_points(profile, forward_transforms(pose.rotations, pose.com_position))
            height_errors.append(abs(max(point[1] for point in points) - GROUND_Y) * PLAYER_SCALE)
            x = sole_contact_x(points, indices)
            if previous is not None:
                speeds.append((previous - x) * PLAYER_SCALE / step_seconds)
            previous = x
    return {"run_support_speed_min_gamepx_s": min(speeds), "run_support_speed_max_gamepx_s": max(speeds), "run_support_ground_error_gamepx": max(height_errors)}


def validate_run_arms(action: Action) -> None:
    first = action.poses[0]
    transforms = forward_transforms(first.rotations, first.com_position)
    for side in ("L", "R"):
        for joint in ("Clavicle", "UpperArm", "Forearm", "Hand"):
            name = f"{joint}_{side}"
            values = [pose.rotations[name] for pose in action.poses]
            if max(values) - min(values) > CONTACT_TOLERANCE:
                raise ValueError(f"run 手臂必须相对胸腔固定，不能独立摆动：{name}")
        elbow, wrist = (transforms[f"{joint}_{side}"][0] for joint in ("Forearm", "Hand"))
        if wrist[0] >= transforms["Pelvis"][0][0] or elbow[0] - wrist[0] < RUN_FOREARM_TRAIL_RATIO_MIN * math.dist(elbow, wrist):
            raise ValueError(f"run 手腕和前臂必须后掠，不能垂在身体前方：{side}")


def inspect_run_geometry(action: Action) -> dict[str, float]:
    leans = []
    support_extensions = {side: [] for side in ("L", "R")}
    recovery_bends = {side: [] for side in ("L", "R")}
    extensions = []
    for index, pose in enumerate(action.poses[:-1]):
        phase = index / action.spec.intervals
        transforms = forward_transforms(pose.rotations, pose.com_position)
        pelvis, neck = transforms["Pelvis"][0], transforms["Neck"][0]
        leans.append(math.degrees(math.atan2(neck[0] - pelvis[0], pelvis[1] - neck[1])))
        for side, offset in (("L", 0.0), ("R", 0.5)):
            hip, knee, ankle = (transforms[f"{joint}_{side}"][0] for joint in ("Thigh", "Shin", "Foot"))
            upper, lower = math.dist(hip, knee), math.dist(knee, ankle)
            extension = math.dist(hip, ankle) / (upper + lower)
            extensions.append(extension)
            cosine = ((knee[0] - hip[0]) * (knee[0] - ankle[0]) + (knee[1] - hip[1]) * (knee[1] - ankle[1])) / (upper * lower)
            bend = 180.0 - math.degrees(math.acos(max(-1.0, min(1.0, cosine))))
            local_phase = (phase - offset) % 1.0
            if local_phase <= RUN_SUPPORT_FRACTION + RUN_PHASE_EPSILON:
                support_extensions[side].append(extension)
            elif local_phase <= RUN_RECOVERY_END_FRACTION:
                recovery_bends[side].append(bend)
    metrics = {"run_hip_neck_lean_min_degrees": min(leans), "run_hip_neck_lean_max_degrees": max(leans), "run_leg_extension_max": max(extensions)}
    for side in ("L", "R"):
        metrics[f"run_{side}_support_extension_min"] = min(support_extensions[side])
        metrics[f"run_{side}_support_extension_max"] = max(support_extensions[side])
        metrics[f"run_{side}_recovery_bend_max_degrees"] = max(recovery_bends[side])
    return metrics


def validate_run_geometry(action: Action) -> dict[str, float]:
    metrics = inspect_run_geometry(action)
    if metrics["run_hip_neck_lean_min_degrees"] < RUN_HIP_NECK_LEAN_LIMITS_DEGREES[0] or metrics["run_hip_neck_lean_max_degrees"] > RUN_HIP_NECK_LEAN_LIMITS_DEGREES[1]:
        raise ValueError("run 实际髋颈轴线必须明确前倾，不能只改局部骨旋转")
    if metrics["run_leg_extension_max"] >= RUN_LEG_EXTENSION_LIMIT:
        raise ValueError("run 腿部不能锁成数学直线或翻膝")
    for side in ("L", "R"):
        if metrics[f"run_{side}_support_extension_max"] < RUN_SUPPORT_EXTENSION_PEAK_MIN or metrics[f"run_{side}_support_extension_min"] < RUN_SUPPORT_EXTENSION_MIN:
            raise ValueError(f"run 支撑腿必须承重伸展，不能始终蜷腿：{side}")
        if metrics[f"run_{side}_support_extension_min"] > RUN_SUPPORT_COMPRESSION_MAX:
            raise ValueError(f"run 触地后必须有屈膝承重，不能直腿弹跳：{side}")
        if metrics[f"run_{side}_recovery_bend_max_degrees"] < RUN_RECOVERY_BEND_MIN_DEGREES:
            raise ValueError(f"run 离地后必须有独立折膝回收阶段：{side}")
    validate_run_loading(action)
    return metrics


def validate_run_loading(action: Action) -> None:
    phases = (0.0, RUN_SUPPORT_FRACTION * RUN_LOAD_FRACTION, RUN_SUPPORT_FRACTION)
    for side, offset in (("L", 0.0), ("R", 0.5)):
        contact, compression, push = [run_world_leg_angles(action.poses[round((phase + offset) * action.spec.intervals)], side) for phase in phases]
        if compression[1] - contact[1] < RUN_LOAD_BEND_CHANGE_MIN_DEGREES or compression[1] - push[1] < RUN_LOAD_BEND_CHANGE_MIN_DEGREES or push[0] <= 90.0:
            raise ValueError(f"run 必须依次触地、屈膝缓冲、向后蹬伸：{side}")


def run_world_leg_angles(pose: Pose, side: str) -> tuple[float, float, float]:
    transforms = forward_transforms(pose.rotations, pose.com_position)
    hip, knee, ankle = (transforms[f"{joint}_{side}"][0] for joint in ("Thigh", "Shin", "Foot"))
    thigh = math.atan2(knee[1] - hip[1], knee[0] - hip[0])
    shin = math.atan2(ankle[1] - knee[1], ankle[0] - knee[0])
    return math.degrees(thigh), math.degrees(math.remainder(shin - thigh, math.tau)), math.degrees(transforms[f"Foot_{side}"][1])


def cycle_peak_count(values: list[float], minimum: float = -math.inf) -> int:
    steps = [(index, following - value) for index, (value, following) in enumerate(zip(values, values[1:] + values[:1])) if abs(following - value) > CONTACT_TOLERANCE]
    return sum(previous > 0.0 and step < 0.0 and values[index] >= minimum for (_, previous), (index, step) in zip(steps[-1:] + steps[:-1], steps))


def validate_run_recovery(bends: list[float], side: str) -> None:
    if cycle_peak_count(bends, RUN_RECOVERY_BEND_MIN_DEGREES) != 1:
        raise ValueError(f"run 每周期只能有一次主要折膝回收，不能二次回收：{side}")


def validate_run_gait(action: Action) -> dict[str, float]:
    if action.spec.intervals != RUN_SAMPLE_INTERVALS:
        raise ValueError("run 必须保持 120 个采样区间")
    count = len(action.poses) - 1
    angles = {side: [run_world_leg_angles(pose, side) for pose in action.poses[:-1]] for side in ("L", "R")}
    for index in range(count):
        left, right = angles["L"][index], angles["R"][(index + count // 2) % count]
        if max(abs(first - second) for first, second in zip(left, right)) > CONTACT_TOLERANCE:
            raise ValueError("run 左右世界腿角必须严格偏半周期")
    maximum_step = 0.0
    for side, samples in angles.items():
        thighs, bends, feet = (list(values) for values in zip(*samples))
        if min(bends) <= 0.0 or max(bends) >= 180.0:
            raise ValueError(f"run 有符号膝角必须保持正确弯曲分支：{side}")
        if cycle_peak_count(thighs) != 1 or cycle_peak_count([-value for value in thighs]) != 1:
            raise ValueError(f"run 每周期只能有一次后摆峰和一次前摆峰：{side}")
        validate_run_recovery(bends, side)
        for values in (thighs, bends, feet):
            maximum_step = max(maximum_step, max(abs(following - value) for value, following in zip(values, values[1:] + values[:1])))
    if maximum_step > RUN_JOINT_STEP_LIMIT_DEGREES:
        raise ValueError("run 相邻帧或循环接缝的世界关节角突跳")
    excursions = [max(pose.com_position[axis] for pose in action.poses) - min(pose.com_position[axis] for pose in action.poses) for axis in (0, 1)]
    if max(excursions) > RUN_COM_EXCURSION_LIMIT_SOURCEPX:
        raise ValueError(f"run COM 左右/上下位移过大：{excursions}")
    return {"run_world_joint_step_max_degrees": maximum_step, "run_com_x_excursion_sourcepx": excursions[0], "run_com_y_excursion_sourcepx": excursions[1]}


def validate_run_motion(action: Action) -> None:
    validate_run_arms(action)
    validate_run_geometry(action)
    for index, side in enumerate(("L", "R")):
        contacts = [pose.feet[index] for pose in action.poses]
        clearances = [GROUND_Y - point.y for point in contacts]
        if max(clearances) < RUN_SWING_CLEARANCE * 0.95 or max(point.x for point in contacts) - min(point.x for point in contacts) < 2.0 * RUN_HALF_STRIDE * 0.95:
            raise ValueError(f"run 缺少推进和抬脚阶段：{side}")
        if min(pose.rotations[f"Shin_{side}"] for pose in action.poses) == max(pose.rotations[f"Shin_{side}"] for pose in action.poses):
            raise ValueError(f"run 没有屈膝变化：{side}")


def validate_run_phases(action: Action, profiles: tuple[BootProfile, BootProfile]) -> dict[str, float]:
    if action.spec.seconds != RUN_CYCLE_SECONDS or pose_distance(action.poses[0], action.poses[-1]) > CONTACT_TOLERANCE or action.poses[0].feet != action.poses[-1].feet:
        raise ValueError("run 周期或阶段首尾未闭合")
    support_keys, flight_keys = [0, 0], 0
    for index, pose in enumerate(action.poses[:-1]):
        supports = validate_run_frame(pose, index / action.spec.intervals, profiles)
        support_keys = [count + int(support) for count, support in zip(support_keys, supports)]
        flight_keys += int(not any(supports))
    for index in range(action.spec.intervals):
        for subdivision in range(1, CONTACT_SUBDIVISIONS):
            phase = (index + subdivision / CONTACT_SUBDIVISIONS) / action.spec.intervals
            validate_run_frame(sampled_run_pose(action, phase, profiles), phase, profiles)
    if min(support_keys) < 2 or support_keys[0] != support_keys[1] or flight_keys == 0:
        raise ValueError("run 一个周期必须含等长非零左右支撑及腾空段")
    contact_fraction = sum(support_keys) / action.spec.intervals
    if not RUN_CONTACT_FRACTION_LIMITS[0] < contact_fraction < RUN_CONTACT_FRACTION_LIMITS[1]:
        raise ValueError("run 支撑时间必须长于腾空，不能以长时间悬空代替交替蹬地")
    metrics = inspect_run_support(action, profiles)
    for name in ("run_support_speed_min_gamepx_s", "run_support_speed_max_gamepx_s"):
        if abs(metrics[name] - RUN_DEFAULT_SPEED_GAMEPX) > RUN_SPEED_TOLERANCE_GAMEPX:
            raise ValueError(f"run alpha 鞋底后扫不匹配默认速度：{metrics[name]:.5f}gamepx/s")
    if metrics["run_support_ground_error_gamepx"] > INTERPOLATED_CONTACT_TOLERANCE * PLAYER_SCALE:
        raise ValueError("run 支撑段真实 alpha 鞋底未贴地")
    validate_run_motion(action)
    gait_metrics = validate_run_gait(action)
    return {**metrics, **inspect_run_geometry(action), **gait_metrics, "run_left_support_keys": support_keys[0], "run_right_support_keys": support_keys[1], "run_flight_keys": flight_keys}
