from dataclasses import dataclass

SOURCE_ORIGIN = (613.0, 1418.0)
PLAYER_SCALE = 0.055
MESH_SPACING = 24.0
JOINT_BLEND_RADIUS = 38.0
TEST_POSE_SECONDS = 1.0


@dataclass(frozen=True)
class Bone:
    name: str
    parent: str | None
    position: tuple[float, float]
    tip: tuple[float, float]


BONES = (
    Bone("Root", None, SOURCE_ORIGIN, (613, 1368)),
    Bone("COM", "Root", (613, 615), (613, 580)),
    Bone("Pelvis", "COM", (613, 607), (611, 542)),
    Bone("Spine_01", "Pelvis", (611, 542), (606, 471)),
    Bone("Spine_02", "Spine_01", (606, 471), (596, 361)),
    Bone("Chest", "Spine_02", (596, 361), (597, 256)),
    Bone("Neck", "Chest", (597, 256), (602, 210)),
    Bone("Head", "Neck", (602, 210), (625, 130)),
    Bone("Clavicle_L", "Chest", (560, 308), (469, 318)),
    Bone("UpperArm_L", "Clavicle_L", (469, 318), (420, 476)),
    Bone("Forearm_L", "UpperArm_L", (420, 476), (352, 672)),
    Bone("Hand_L", "Forearm_L", (352, 672), (350, 746)),
    Bone("Clavicle_R", "Chest", (650, 313), (710, 337)),
    Bone("UpperArm_R", "Clavicle_R", (710, 337), (774, 493)),
    Bone("Forearm_R", "UpperArm_R", (774, 493), (870, 688)),
    Bone("Hand_R", "Forearm_R", (870, 688), (886, 752)),
    Bone("Thigh_L", "Pelvis", (574, 655), (484, 1035)),
    Bone("Shin_L", "Thigh_L", (484, 1035), (448, 1270)),
    Bone("Foot_L", "Shin_L", (448, 1270), (438, 1355)),
    Bone("Toe_L", "Foot_L", (438, 1355), (435, 1406)),
    Bone("Thigh_R", "Pelvis", (657, 655), (721, 1050)),
    Bone("Shin_R", "Thigh_R", (721, 1050), (767, 1276)),
    Bone("Foot_R", "Shin_R", (767, 1276), (845, 1355)),
    Bone("Toe_R", "Foot_R", (845, 1355), (902, 1374)),
    Bone("HairRoot", "Head", (553, 91), (516, 190)),
    Bone("Hair_01", "HairRoot", (516, 190), (439, 312)),
    Bone("Hair_02", "Hair_01", (439, 312), (347, 437)),
    Bone("Hair_03", "Hair_02", (347, 437), (317, 516)),
    Bone("Hair_04", "Hair_03", (317, 516), (308, 575)),
    Bone("RibbonRoot", "Head", (553, 91), (519, 110)),
    Bone("Ribbon_L_01", "RibbonRoot", (519, 100), (398, 182)),
    Bone("Ribbon_L_02", "Ribbon_L_01", (398, 182), (281, 237)),
    Bone("Ribbon_L_03", "Ribbon_L_02", (281, 237), (250, 274)),
    Bone("Ribbon_R_01", "RibbonRoot", (528, 109), (442, 232)),
    Bone("Ribbon_R_02", "Ribbon_R_01", (442, 232), (305, 281)),
    Bone("Ribbon_R_03", "Ribbon_R_02", (305, 281), (265, 332)),
    Bone("ClothFront_L", "Pelvis", (592, 604), (516, 753)),
    Bone("ClothFront_L_02", "ClothFront_L", (516, 753), (454, 906)),
    Bone("ClothFront_L_03", "ClothFront_L_02", (454, 906), (383, 1038)),
    Bone("ClothFront_R", "Pelvis", (671, 609), (690, 764)),
    Bone("ClothFront_R_02", "ClothFront_R", (690, 764), (745, 901)),
    Bone("ClothFront_R_03", "ClothFront_R_02", (745, 901), (772, 940)),
    Bone("CoatBack_L_01", "Pelvis", (567, 630), (371, 826)),
    Bone("CoatBack_L_02", "CoatBack_L_01", (371, 826), (174, 950)),
    Bone("CoatBack_L_03", "CoatBack_L_02", (174, 950), (159, 1072)),
    Bone("CoatBack_R_01", "Pelvis", (695, 611), (808, 876)),
    Bone("CoatBack_R_02", "CoatBack_R_01", (808, 876), (867, 1063)),
    Bone("CoatBack_R_03", "CoatBack_R_02", (867, 1063), (888, 1130)),
    Bone("WaistTasselRoot", "Pelvis", (606, 559), (602, 654)),
    Bone("WaistTassel_01", "WaistTasselRoot", (602, 654), (591, 714)),
    Bone("WaistTassel_02", "WaistTassel_01", (591, 714), (587, 770)),
)

BONE_BY_NAME = {bone.name: bone for bone in BONES}

TEST_POSES = (
    ("Neutral", {}),
    ("TorsoForward", {"COM": -3, "Pelvis": -4, "Spine_01": 8, "Spine_02": 10, "Chest": 4}),
    ("ChestAdjust", {"Spine_02": -5, "Chest": 9, "Neck": -3, "Head": -3}),
    ("LegLift", {"Pelvis": -3, "Thigh_R": -32, "Shin_R": 12}),
    ("KneeBend", {"Thigh_R": -24, "Shin_R": 65, "Foot_R": -18}),
    ("FootToe", {"Foot_R": -22, "Toe_R": 35, "Foot_L": 8, "Toe_L": -16}),
    ("ArmBend", {"Clavicle_L": 6, "UpperArm_L": -38, "Forearm_L": -68, "Hand_L": 12}),
    ("HeadAdjust", {"Neck": -4, "Head": 10}),
    ("Neutral", {}),
)


def bone_path(name: str) -> str:
    bone = BONE_BY_NAME[name]
    return f"{bone_path(bone.parent)}/{name}" if bone.parent else name
