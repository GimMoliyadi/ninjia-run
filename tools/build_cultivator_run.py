"""Bake reference-image cutouts and eight authored poses into an editable Godot scene."""
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCALE = 0.18
DURATION = 0.50
HIP_LEAN = [6, 7, 6, 5, 6, 7, 6, 5]
HIP_POSITIONS = [(3.0, -30.5), (3.6, -29.4), (3.4, -30.2), (3.0, -31.0),
                 (3.0, -30.5), (3.6, -29.4), (3.4, -30.2), (3.0, -31.0)]
TORSO_REST_ANGLE = -66.5
COAT_ROOT_SOURCE = (304, 246)
COAT_SOURCE_ANGLE = math.degrees(math.atan2(32, -99))
COAT_TRAIL_ANGLE = 168
COAT_SEGMENT_LENGTHS = (16, 15, 14)
COAT_LENGTH_SCALE = 0.85
COAT_WIDTH_SCALE = 0.5
POSE_NAMES = ['Contact R', 'Down R', 'Passing R', 'Up R',
              'Contact L', 'Down L', 'Passing L', 'Up L']


def rotate(point, angle):
    x, y = point
    return (x * math.cos(angle) - y * math.sin(angle),
            x * math.sin(angle) + y * math.cos(angle))


def numbers(values):
    return ', '.join(f'{value:.6f}' for value in values)


def vector(point):
    return f'Vector2({numbers(point)})'


def polygon(points):
    return f'PackedVector2Array({numbers([v for p in points for v in p])})'


class Scene:
    def __init__(self):
        self.nodes = []
        self.tracks = []

    def bone(self, path, position, rotation, length, z=0, script=None):
        parent, _, name = path.rpartition('/')
        angle = math.radians(rotation)
        x, y = position
        rest = [math.cos(angle), math.sin(angle), -math.sin(angle), math.cos(angle), x, y]
        self.nodes.append(f'''[node name="{name}" type="Bone2D" parent="{parent or '.'}"]
position = {vector(position)}
rotation = {angle:.6f}
z_index = {z}
z_as_relative = false
rest = Transform2D({numbers(rest)})
length = {length:.6f}
auto_calculate_length_and_angle = false
''')
        if script:
            self.nodes[-1] += f'script = ExtResource("{script}")\n'

    def art(self, path, name, points, pivot, source_angle=0, resize=1):
        local = [rotate(((x-pivot[0])*SCALE*resize, (y-pivot[1])*SCALE*resize),
                        -math.radians(source_angle)) for x, y in points]
        self.nodes.append(f'''[node name="{name}" type="Polygon2D" parent="{path}"]
texture = ExtResource("1_texture")
polygon = {polygon(local)}
uv = {polygon(points)}
antialiased = true
''')

    def track(self, path, values, positions=False):
        values = values + values[:1]
        rendered = ', '.join(vector(v) for v in values) if positions else numbers(map(math.radians, values))
        index = len(self.tracks)
        self.tracks.append(f'''tracks/{index}/type = "value"
tracks/{index}/path = NodePath("{path}")
tracks/{index}/interp = 1
tracks/{index}/loop_wrap = true
tracks/{index}/keys = {{
"times": PackedFloat32Array({numbers(i * DURATION / 8 for i in range(9))}),
"transitions": PackedFloat32Array(1, 1, 1, 1, 1, 1, 1, 1, 1),
"update": 0,
"values": [{rendered}]
}}
''')

    def save(self):
        header = f'''[gd_scene load_steps=6 format=3]

[ext_resource type="Texture2D" path="res://assets/player/cultivator/run-sword-reference.png" id="1_texture"]
[ext_resource type="Script" path="res://visuals/run_debug.gd" id="2_debug"]
[ext_resource type="Script" path="res://visuals/coat_tail.gd" id="3_coat_tail"]

[sub_resource type="Animation" id="Animation_run"]
resource_name = "run"
length = {DURATION}
loop_mode = 1
step = {DURATION / 8}
'''
        library = '''
[sub_resource type="AnimationLibrary" id="AnimationLibrary_run"]
_data = {"run": SubResource("Animation_run")}

[node name="RunSkeleton" type="Skeleton2D"]
visible = false
texture_filter = 2
'''
        tail = '''
[node name="AnimationPlayer" type="AnimationPlayer" parent="."]
root_node = NodePath("..")
libraries = {"": SubResource("AnimationLibrary_run")}

[node name="BoneDebug" type="Node2D" parent="."]
visible = false
z_index = 100
script = ExtResource("2_debug")
'''
        (ROOT / 'visuals/run_skeleton.tscn').write_text(
            header + '\n'.join(self.tracks) + library + '\n'.join(self.nodes) + tail,
            encoding='utf-8')


def source_offset(point, pivot, angle=0):
    return rotate(((point[0]-pivot[0])*SCALE, (point[1]-pivot[1])*SCALE),
                  -math.radians(angle))


def body(scene):
    hip = (310, 254)
    scene.bone('Hip', HIP_POSITIONS[0], HIP_LEAN[0], 5)
    scene.track('Hip:position', HIP_POSITIONS, True)
    scene.track('Hip:rotation', HIP_LEAN)
    torso = 'Hip/Torso'
    scene.bone(torso, (0,0), TORSO_REST_ANGLE, 24.09, 2)
    scene.track(torso + ':rotation', [TORSO_REST_ANGLE]*8)
    scene.art(torso, 'Torso', [(290,129),(319,116),(338,116),(354,125),
              (370,144),(370,174),(350,195),(323,222),(307,251),(278,237),
              (260,211),(261,172)], hip, TORSO_REST_ANGLE)
    scene.art(torso, 'WaistRobe', [(311,235),(329,236),(350,258),(357,272),
              (344,274),(319,258),(307,271),(292,275),(278,263),(279,247)],
              hip, TORSO_REST_ANGLE)
    head = torso + '/Head'
    scene.bone(head, source_offset((356,128), hip, TORSO_REST_ANGLE),
               -TORSO_REST_ANGLE, 9, 5)
    scene.track(head + ':rotation', [-TORSO_REST_ANGLE]*8)
    scene.art(head, 'Face', [(345,88),(370,76),(391,77),(402,88),(399,110),
              (392,119),(384,133),(370,130),(357,119),(345,109)], (356,128))
    scene.art(head, 'MainHair', [(315,43),(318,33),(332,28),(345,33),(352,49),
              (374,50),(398,62),(413,78),(416,101),(410,121),(398,129),
              (398,108),(391,90),(377,102),(361,111),(346,108),(328,88),
              (322,65)], (356,128))
    hair = head + '/Hair_1'
    scene.bone(hair, source_offset((334,66),(356,128)), 2, 17, 0)
    scene.track(hair + ':rotation', [2,1,0,2,3,1,0,1])
    scene.art(hair, 'LongHair', [(334,48),(321,61),(299,69),(276,70),
              (244,69),(219,66),(216,89),(229,100),(228,128),(231,161),
              (263,148),(291,130),(315,105),(334,84)], (334,66))
    tip = hair + '/Hair_2'
    scene.bone(tip, source_offset((234,116),(334,66)), 3, 13, 0)
    scene.track(tip + ':rotation', [3,4,2,-1,2,4,3,0])
    scene.art(tip, 'HairTip', [(239,93),(215,96),(187,108),(161,129),
              (148,151),(156,173),(174,190),(195,175),(218,159),(249,138)],
              (234,116))
    coat_tail(scene)


def coat_tail(scene):
    coat = 'Hip/CoatTail_Base'
    scene.bone(coat, source_offset(COAT_ROOT_SOURCE, (310,254)),
               COAT_TRAIL_ANGLE-HIP_LEAN[0], COAT_SEGMENT_LENGTHS[0], -3,
               script='3_coat_tail')
    middle = coat + '/CoatTail_Mid'
    tip = middle + '/CoatTail_Tip'
    scene.bone(middle, (COAT_SEGMENT_LENGTHS[0],0), 0, COAT_SEGMENT_LENGTHS[1], -3)
    scene.bone(tip, (COAT_SEGMENT_LENGTHS[1],0), 0, COAT_SEGMENT_LENGTHS[2], -3)
    scene.nodes.append('''[node name="CoatTailVisual" type="Node2D" parent="."]
z_index = -3
z_as_relative = false
''')
    bones = (coat, middle, tip)
    coat_art(scene, 'CoatTail', [(304,228),(279,235),(250,243),(227,255),
              (200,280),(176,309),(179,331),(199,335),(223,326),(249,310),
              (278,281),(307,258)], bones)
    coat_art(scene, 'TrailingCloth', [(215,230),(186,228),(150,225),(118,228),
              (89,239),(71,255),(64,268),(88,276),(109,266),(94,286),
              (71,300),(43,314),(20,331),(7,345),(26,350),(39,367),
              (64,380),(88,369),(112,349),(151,333),(181,310),(216,285)],
              bones)
    coat_art(scene, 'CoatLining', [(197,293),(172,320),(145,338),(120,350),
              (96,369),(70,380),(49,375),(38,355),(51,342),(81,329),
              (112,316),(150,302),(178,285)], bones)


def coat_art(scene, name, points, bones):
    root_offset = rotate(source_offset(COAT_ROOT_SOURCE, (310,254)),
                         math.radians(HIP_LEAN[0]))
    root_position = tuple(hip+offset for hip, offset in zip(HIP_POSITIONS[0], root_offset))
    vertices = []
    weights = [[], [], []]
    for point in points:
        along, across = source_offset(point, COAT_ROOT_SOURCE, COAT_SOURCE_ANGLE)
        along *= COAT_LENGTH_SCALE
        offset = rotate((along, across*COAT_WIDTH_SCALE), math.radians(COAT_TRAIL_ANGLE))
        vertices.append(tuple(root+value for root, value in zip(root_position, offset)))
        base_blend = max(0, min(1, along/COAT_SEGMENT_LENGTHS[0]))
        tip_blend = max(0, min(1, (along-COAT_SEGMENT_LENGTHS[0])/COAT_SEGMENT_LENGTHS[1]))
        for bone_weights, weight in zip(weights, (1-base_blend, base_blend-tip_blend, tip_blend)):
            bone_weights.append(weight)
    bindings = ', '.join(f'"{path}", PackedFloat32Array({numbers(values)})'
                         for path, values in zip(bones, weights))
    scene.nodes.append(f'''[node name="{name}" type="Polygon2D" parent="CoatTailVisual"]
texture = ExtResource("1_texture")
polygon = {polygon(vertices)}
uv = {polygon(points)}
skeleton = NodePath("../..")
bones = [{bindings}]
antialiased = true
''')


def legs(scene):
    thigh_length = 20.0
    shin_length = 12.0
    foot_length = 8.0
    thigh_art_scale = thigh_length / (math.dist((310,254), (373,363))*SCALE)
    thigh_angles = [50, 80, 112, 108, 70, 56, 35, 42]
    knee_angles = [85, 85, 140, 140, 135, 130, 107, 75]
    foot_angles = [16, 4, -48, -52, -44, -42, -20, 16]
    thigh_art = [(306,247),(321,257),(344,276),(369,301),(391,321),
                 (396,346),(381,366),(361,365),(348,347),(333,328),
                 (313,312),(296,289),(289,270)]
    shin_art = [(355,359),(376,360),(393,357),(398,378),(403,399),
                (416,418),(400,433),(373,426),(368,406),(363,382)]
    foot_art = [(373,419),(396,408),(412,417),(429,417),(447,416),
                (457,423),(451,441),(431,452),(407,460),(375,465),
                (369,451),(369,434)]
    for side, offset, z in [('L',4,-2),('R',0,-1)]:
        thigh = f'Hip/Thigh_{side}'
        shin = thigh + f'/Shin_{side}'
        foot = shin + f'/Foot_{side}'
        shift = lambda values: values[offset:] + values[:offset]
        local_thigh = [angle-lean for angle, lean in zip(shift(thigh_angles), HIP_LEAN)]
        local_foot = shift([f-t-k for f,t,k in zip(foot_angles,thigh_angles,knee_angles)])
        scene.bone(thigh, (0,0), local_thigh[0], thigh_length, z)
        scene.bone(shin, (thigh_length,0), shift(knee_angles)[0], shin_length, z)
        scene.bone(foot, (shin_length,0), local_foot[0], foot_length, z)
        scene.art(thigh, 'Trouser', thigh_art, (310,254), 60, resize=thigh_art_scale)
        scene.art(shin, 'BootShin', shin_art, (373,363), 74)
        scene.art(foot, 'BootFoot', foot_art, (388,427))
        scene.track(thigh + ':rotation', local_thigh)
        scene.track(shin + ':rotation', shift(knee_angles))
        scene.track(foot + ':rotation', local_foot)


def arms(scene):
    torso = 'Hip/Torso'
    hip = (310,254)
    arm_parts = [
        ('L', (307,141), (243,191), (289,220), 4,
         [(303,124),(277,128),(247,142),(211,161),(189,174),(183,184),
          (198,204),(220,215),(244,213),(260,195),(281,174),(314,155)],
         [(230,186),(249,188),(264,198),(279,205),(288,210),(300,217),
          (303,227),(296,234),(281,236),(273,227),(259,222),(239,210)]),
        ('R', (352,143), (392,191), (350,207), 5,
         [(352,126),(369,145),(387,164),(400,184),(405,207),(396,216),
          (385,199),(372,188),(349,173),(337,152)],
         [(392,187),(401,202),(397,222),(391,235),(381,240),(373,225),
          (365,218),(354,218),(341,221),(336,214),(339,199),(348,193),
          (359,196),(377,193)])]
    for side, shoulder, elbow, hand, z, sleeve, forearm in arm_parts:
        upper = torso + f'/UpperArm_{side}'
        lower = upper + f'/Forearm_{side}'
        upper_angle = math.degrees(math.atan2(elbow[1]-shoulder[1], elbow[0]-shoulder[0]))
        lower_angle = math.degrees(math.atan2(hand[1]-elbow[1], hand[0]-elbow[0]))
        upper_length = math.dist(shoulder, elbow)*SCALE
        lower_length = math.dist(elbow, hand)*SCALE
        scene.bone(upper, source_offset(shoulder, hip, TORSO_REST_ANGLE),
                   upper_angle-TORSO_REST_ANGLE, upper_length, z)
        scene.bone(lower, (upper_length,0), lower_angle-upper_angle, lower_length, z)
        scene.art(upper, 'Sleeve', sleeve, shoulder, upper_angle)
        scene.art(lower, 'ForearmAndGrip', forearm, elbow, lower_angle)
        scene.track(upper + ':rotation', [upper_angle-TORSO_REST_ANGLE]*8)
        scene.track(lower + ':rotation', [lower_angle-upper_angle]*8)
        grip = lower + ('/SwordGrip' if side == 'R' else '/ScabbardGrip')
        scene.bone(grip, (lower_length,0), -lower_angle, 4, z)
    weapon = torso + '/SheathedSword'
    scene.bone(weapon, source_offset((326,211),hip,TORSO_REST_ANGLE),
               -TORSO_REST_ANGLE, 48, 3)
    scene.track(weapon + ':rotation', [-TORSO_REST_ANGLE]*8)
    scene.art(weapon, 'SwordAndScabbard', [(384,191),(393,196),(392,211),
              (370,216),(347,218),(327,224),(310,232),(290,242),(267,250),
              (243,259),(216,270),(184,283),(151,298),(117,312),(85,326),
              (64,332),(60,321),(83,308),(115,296),(150,280),(181,267),
              (216,250),(244,235),(272,225),(300,216),(318,201),(333,199),
              (356,197)], (326,211))


if __name__ == '__main__':
    scene = Scene()
    body(scene)
    legs(scene)
    arms(scene)
    scene.save()
    print(f'Baked {len(scene.tracks)} tracks, {DURATION}s, eight poses: {", ".join(POSE_NAMES)}')
