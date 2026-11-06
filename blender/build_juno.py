"""Builds Juno as a skinned character with keyframed animations and exports it as GLB.

    python blender/build_juno.py            # with `pip install bpy==4.2.0`
    blender --background --python blender/build_juno.py

Juno is one armature (bones named like the old rigid-part pivots: Hips, Spine, Chest, Neck,
Head, ArmL/R, ForearmL/R, LegL/R, ShinL/R, plus PackMount) and one mesh: a continuous
under-suit made with a Skin modifier and weighted to the bones automatically, with the hard
armour (helmet, plates, bracers, gloves, boots, life-support pack) bound rigidly to its bone.

Every animation is an action keyed here and exported as its own clip. Poses are written the way
the game's old procedural animator wrote them: per joint, degrees about Godot's x, y and z in
the joint's rest frame (+x swings a limb forward or tips the torso back; -x on a shin or forearm
bends the knee back or the elbow up). pose_key() turns that into Blender bone rotations.

Output: godot/assets/models/juno_rigged.glb, and blender/juno_rigged.blend so the clips can be
opened and edited by hand in Blender.
"""

import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_models as bm  # noqa: E402  (shared helpers: g(), mat(), pod(), cyl(), box())

ROOT = bm.ROOT
OUT = bm.OUT
FPS = 30

# Soft suit parts of the rigid model that the skinned under-suit replaces.
SOFT = {"pelvis", "abdomen", "upper_armL", "upper_armR", "forearmL", "forearmR", "elbowL", "elbowR",
        "thighL", "thighR", "shinL", "shinR", "hip_jointL", "hip_jointR", "knee_jointL", "knee_jointR",
        "neck_ring"}
JOINTS = ["Hips", "Spine", "Chest", "Neck", "Head", "PackMount", "ArmL", "ForearmL", "ArmR", "ForearmR",
          "LegL", "ShinL", "LegR", "ShinR"]
# Bones that carry things rather than skin: the pack, and the rifle (the game hangs the weapon
# on WeaponMount, so every clip carries the rifle with her hands on it).
NON_DEFORM = {"PackMount", "WeaponMount"}
BONES = JOINTS + ["WeaponMount"]
PARENT = {"Spine": "Hips", "Chest": "Spine", "Neck": "Chest", "Head": "Neck", "PackMount": "Chest",
          "WeaponMount": "Chest",
          "ArmL": "Chest", "ForearmL": "ArmL", "ArmR": "Chest", "ForearmR": "ArmR",
          "LegL": "Hips", "ShinL": "LegL", "LegR": "Hips", "ShinR": "LegR"}
# Where each bone's tail goes (Godot space): toward the next joint, or out along the limb.
TAILS = {
    "Hips": (0, 1.07, 0), "Spine": (0, 1.32, 0), "Chest": (0, 1.68, 0), "Neck": (0, 1.74, 0),
    "Head": (0, 2.0, 0), "PackMount": (0, 1.56, 0.2),
    "ArmL": (-0.26, 1.27, 0), "ForearmL": (-0.26, 0.92, 0), "ArmR": (0.26, 1.27, 0), "ForearmR": (0.26, 0.92, 0),
    "WeaponMount": (0.13, 1.27, -0.6),
    "LegL": (-0.1, 0.46, 0), "ShinL": (-0.1, 0.03, 0), "LegR": (0.1, 0.46, 0), "ShinR": (0.1, 0.03, 0),
}


# --- Model -------------------------------------------------------------------------------

def _world_heads():
    """Builds the rigid model (without exporting) and returns its joint positions and parts."""
    real_export = bm.export
    bm.export = lambda name: None
    try:
        bm.juno()
    finally:
        bm.export = real_export
    # World matrices of the new objects are stale until the scene is evaluated.
    bpy.context.view_layer.update()
    heads = {}
    for name in JOINTS:
        o = bpy.data.objects[name]
        heads[name] = o.matrix_world.translation.copy()
    heads["WeaponMount"] = bm.g(*HOLD_W[0])
    return heads


def _bone_of(obj):
    p = obj.parent
    while p is not None:
        if p.name in JOINTS:
            return p.name
        p = p.parent
    return "Hips"


def build_armature(heads):
    arm_data = bpy.data.armatures.new("JunoSkeleton")
    arm = bpy.data.objects.new("JunoRig", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name in BONES:
        b = arm_data.edit_bones.new(name)
        b.head = heads[name]
        b.tail = bm.g(*TAILS[name])
        b.roll = 0.0
        if name in NON_DEFORM:
            b.use_deform = False
    for name, parent in PARENT.items():
        arm_data.edit_bones[name].parent = arm_data.edit_bones[parent]
        arm_data.edit_bones[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def build_undersuit():
    """A continuous suit body: a vertex skeleton with radii through the Skin modifier, smoothed."""
    # (Godot position, radius x, radius depth)
    pts = {
        "pelvis": ((0, 0.92, 0), 0.17, 0.12), "waist": ((0, 1.08, 0), 0.15, 0.11),
        "ribs": ((0, 1.3, 0), 0.19, 0.13), "chest": ((0, 1.52, 0), 0.2, 0.13), "neck": ((0, 1.72, 0), 0.075, 0.075),
    }
    edges = [("pelvis", "waist"), ("waist", "ribs"), ("ribs", "chest"), ("chest", "neck")]
    for side, s in (("L", -1), ("R", 1)):
        pts["sho" + side] = ((0.22 * s, 1.6, 0), 0.075, 0.075)
        pts["elb" + side] = ((0.26 * s, 1.27, 0), 0.06, 0.062)
        pts["wri" + side] = ((0.26 * s, 0.98, 0), 0.045, 0.048)
        pts["hip" + side] = ((0.1 * s, 0.86, 0), 0.1, 0.1)
        pts["kne" + side] = ((0.1 * s, 0.46, 0), 0.07, 0.075)
        pts["ank" + side] = ((0.1 * s, 0.1, 0), 0.055, 0.058)
        edges += [("chest", "sho" + side), ("sho" + side, "elb" + side), ("elb" + side, "wri" + side),
                  ("pelvis", "hip" + side), ("hip" + side, "kne" + side), ("kne" + side, "ank" + side)]
    names = list(pts)
    me = bpy.data.meshes.new("undersuit")
    me.from_pydata([bm.g(*pts[n][0]) for n in names], [(names.index(a), names.index(b)) for a, b in edges], [])
    obj = bpy.data.objects.new("undersuit", me)
    bpy.context.collection.objects.link(obj)
    skin = obj.modifiers.new("skin", "SKIN")
    skin.use_smooth_shade = True
    for i, n in enumerate(names):
        sv = me.skin_vertices[0].data[i]
        sv.radius = (pts[n][1], pts[n][2])
    me.skin_vertices[0].data[0].use_root = True
    sub = obj.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier="skin")
    bpy.ops.object.modifier_apply(modifier="sub")
    obj.data.materials.append(bm.mat("suit", "3f4d58", 0.85))
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def bind(arm, suit):
    """Weights the under-suit to the bones automatically, and the armour rigidly to its joint."""
    bpy.ops.object.select_all(action="DESELECT")
    suit.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    parts = []
    bpy.context.view_layer.update()
    for o in list(bpy.data.objects):
        if o.type != "MESH" or o is suit:
            continue
        if o.name in SOFT:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        bone = _bone_of(o)
        world = o.matrix_world.copy()
        for m in list(o.modifiers):
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.ops.object.modifier_apply(modifier=m.name)
        o.parent = None
        o.matrix_world = world
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        vg = o.vertex_groups.new(name=bone)
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        parts.append(o)
    # One mesh for the whole character: one draw call per material.
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    suit.select_set(True)
    bpy.context.view_layer.objects.active = suit
    bpy.ops.object.join()
    suit.name = "JunoMesh"
    suit.parent = arm
    mod = suit.modifiers.get("Armature") or suit.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    for o in list(bpy.data.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o, do_unlink=True)
    return suit


# --- Animation ---------------------------------------------------------------------------

# The rifle: where it sits in the hold and when aiming, as (position, Godot degrees) in the
# spine's frame (so it rides the hips, lean and crouch, but not the chest's twist).
HOLD_W = ((0.13, 1.27, -0.40), (-10, 0, 0))
AIM_W = ((0.14, 1.44, -0.46), (0, 0, 0))
# Where the hands go on the rifle, in the weapon's own frame (-z is the muzzle).
GRIP_R = (0.0, -0.12, 0.17)
GRIP_L = (0.0, -0.06, -0.12)
HAND = 0.35  # elbow to the middle of the glove
# Elbows point down and out, the right one a little back (Godot axes, chest frame).
POLE = {"L": (-0.45, -1.0, 0.05), "R": (0.55, -1.0, 0.35)}


def _godot_rot(deg):
    """Godot Euler degrees (applied y, then x, then z, as Node3D does) -> Blender-space matrix."""
    x, y, z = (math.radians(a) for a in deg)
    # Godot axes in Blender: x -> x, y -> z, z -> -y.
    rx = Matrix.Rotation(x, 3, Vector((1, 0, 0)))
    ry = Matrix.Rotation(y, 3, Vector((0, 0, 1)))
    rz = Matrix.Rotation(z, 3, Vector((0, -1, 0)))
    return ry @ rx @ rz


def _fk(arm, rots, locs):
    """Posed armature-space matrices for world-aligned rotations `rots` and offsets `locs`."""
    out = {}
    for b in arm.data.bones:  # parents come first (creation order)
        rest3 = b.matrix_local.to_3x3()
        lq = (rest3.inverted() @ rots[b.name] @ rest3).to_4x4()
        basis = Matrix.Translation(rest3.inverted() @ locs[b.name]) @ lq
        if b.parent:
            out[b.name] = out[b.parent.name] @ b.parent.matrix_local.inverted() @ b.matrix_local @ basis
        else:
            out[b.name] = b.matrix_local @ basis
    return out


def _carried(arm, posed, name):
    """How the bone's rest-aligned frame has been moved by its parent: posed_parent @ rest_parent^-1."""
    p = arm.data.bones[name].parent
    return posed[p.name] @ p.matrix_local.inverted()


def _solve_arm(arm, posed, rots, side, target):
    """Two-bone IK: turns Arm<side> and Forearm<side> so the hand lands on `target` (Blender)."""
    up = arm.data.bones["Arm" + side]
    lo = arm.data.bones["Forearm" + side]
    a = (lo.head_local - up.head_local).length
    b = HAND
    c3 = _carried(arm, posed, "Arm" + side).to_3x3()
    s = posed["Arm" + side].translation
    d_vec = target - s
    d = min(max(d_vec.length, abs(a - b) + 1e-3), (a + b) * 0.995)
    dirv = d_vec.normalized()
    pole = c3 @ bm.g(*POLE[side])
    n = (pole - dirv * pole.dot(dirv)).normalized()
    cos_a = (a * a + d * d - b * b) / (2 * a * d)
    sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
    elbow = s + a * (dirv * cos_a + n * sin_a)
    hand = s + dirv * d
    u0 = lo.head_local - up.head_local
    w_up = u0.rotation_difference(c3.inverted() @ (elbow - s)).to_matrix()
    v0 = bm.g(0, -HAND, 0)
    cf = c3 @ w_up
    w_lo = v0.rotation_difference(cf.inverted() @ (hand - elbow)).to_matrix()
    rots["Arm" + side] = w_up
    rots["Forearm" + side] = w_lo


def solve(arm, pose, offsets):
    """World-aligned rotations and offsets for every bone, with the rifle placed and the hands
    put on it. pose: {joint: (x, y, z) Godot degrees} plus optional "_w" (rifle (pos, rot) in the
    spine's frame, or None to leave it at rest on the chest), "_ikL"/"_ikR" (a point in the
    rifle's frame for that hand, or None to pose the arm by its angles)."""
    rots = {}
    locs = {}
    for b in arm.data.bones:
        rots[b.name] = _godot_rot(pose.get(b.name, (0, 0, 0)))
        locs[b.name] = bm.g(*(offsets or {}).get(b.name, (0, 0, 0)))
    w = pose.get("_w", HOLD_W)
    if w is None:
        return rots, locs
    posed = _fk(arm, rots, locs)
    spine = posed["Spine"] @ arm.data.bones["Spine"].matrix_local.inverted()
    frame = spine @ Matrix.Translation(bm.g(*w[0])) @ _godot_rot(w[1]).to_4x4()
    # The WeaponMount bone (parented to the chest) is turned and moved to put the rifle there.
    wb = arm.data.bones["WeaponMount"]
    want = frame @ wb.matrix_local.to_3x3().to_4x4()
    carried = _carried(arm, posed, "WeaponMount")
    # want = carried @ rest @ T(rest3^-1 off) @ R(rest3^-1 W rest3)  =>  solve W and off.
    rest = wb.matrix_local
    base = (carried @ rest).inverted() @ want
    loc, rot, _ = base.decompose()
    rest3 = rest.to_3x3()
    rots["WeaponMount"] = rest3 @ rot.to_matrix() @ rest3.inverted()
    locs["WeaponMount"] = rest3 @ loc
    for side in ("L", "R"):
        p = pose.get("_ik" + side, GRIP_L if side == "L" else GRIP_R)
        if p is not None:
            _solve_arm(arm, posed, rots, side, frame @ bm.g(*p))
    return rots, locs


def pose_key(arm, frame, pose, offsets=None, prev=None):
    """Keys a pose: {joint: (x, y, z) Godot degrees}; joints left out go back to rest.
    offsets: {joint: (x, y, z) Godot metres} moves a bone (the hips, for bob and crouch)."""
    rots, locs = solve(arm, pose, offsets)
    for pb in arm.pose.bones:
        rest = pb.bone.matrix_local.to_3x3()
        q = (rest.inverted() @ rots[pb.name] @ rest).to_quaternion()
        if prev is not None:
            if pb.name in prev:
                q.make_compatible(prev[pb.name])
            prev[pb.name] = q.copy()
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.location = rest.inverted() @ locs[pb.name]
        pb.keyframe_insert("location", frame=frame)


def action(arm, name, keys, loop=True):
    """keys: [(frame, pose, offsets)]. Makes an action, pushes it to its own NLA track (so the
    glTF exporter writes it as a separate clip) and leaves the armature at rest."""
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    prev = {}
    for frame, pose, offsets in keys:
        pose_key(arm, frame, pose, offsets, prev)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(keys[0][0]), act)
    strip.name = name
    track.mute = True
    arm.animation_data.action = None
    act.use_fake_user = True
    return act


def _merge(*dicts):
    """Adds joint angles together; for the "_" settings (rifle, hand targets) the last one wins."""
    out = {}
    for d in dicts:
        for k, v in d.items():
            if k.startswith("_"):
                out[k] = v
                continue
            a = out.get(k, (0, 0, 0))
            out[k] = (a[0] + v[0], a[1] + v[1], a[2] + v[2])
    return out


# The two-handed rifle hold: the chest turns a little right so the left hand reaches the
# handguard, the head turns back to look ahead. The arms are solved onto the rifle.
HOLD = {"Chest": (0, -18, 0), "Neck": (0, 8, 0), "Head": (0, 10, 0)}
# Shouldered and raised for aiming, bladed further, cheek down to the sight.
AIM = {"Chest": (0, -24, 0), "Neck": (0, 10, 0), "Head": (-4, 13, 0), "_w": AIM_W}
# Hands off the rifle: it stays on the chest at rest and the arms take their angles.
FREE = {"_w": None, "_ikL": None, "_ikR": None}


def _gait(phase, stride, bend, lean, bob):
    """One frame of a walk/run cycle at `phase` (radians)."""
    s = math.sin(phase)
    p = dict(HOLD)
    off = {"Hips": (0, -abs(math.sin(phase)) * bob * -1.0 - bob, 0)}
    for side, ph in (("L", 0.0), ("R", math.pi)):
        ls = math.sin(phase + ph)
        lift = max(0.0, math.sin(phase + ph + 1.6))
        p["Leg" + side] = (ls * stride, 0, 0)
        p["Shin" + side] = (-lift * bend - 6.0, 0, 0)
    p = _merge(p, {
        "Hips": (lean * 0.3, s * 6.0, -s * 3.0),
        "Spine": (lean * 0.4, -s * 6.0, s * 1.5),
        "Chest": (lean * 0.3, -s * 2.0, 0),
        "Head": (-lean * 0.8, s * 4.0, 0),
    })
    return p, off


def build_actions(arm):
    # Idle: breathing, weight shift, a slow look around. 4 s loop.
    keys = []
    for i in range(5):
        t = i / 4.0 * math.tau
        b = math.sin(t)
        keys.append((1 + i * 30, _merge(HOLD, {
            "Spine": (-2.0 + b * 1.5, 0, 0), "Chest": (b * 1.2, math.sin(t * 0.5) * 3.0, 0),
            "Head": (-b * 1.0, math.sin(t * 0.5) * 9.0, 0),
            "LegL": (2, 0, -2), "LegR": (-2, 0, 2), "ShinL": (-6, 0, 0), "ShinR": (-4, 0, 0),
            "Hips": (0, 0, math.sin(t * 0.5) * 1.5),
        }), {"Hips": (math.sin(t * 0.5) * 0.012, b * 0.006 - 0.01, 0)}))
    action(arm, "idle", keys)

    # Walk and run share a 24-frame cycle (0.8 s) so the game can blend them in step; it plays
    # them faster or slower to match her ground speed (walk covers 3.2 m, run 4.4 m per cycle).
    for name, stride, bend, lean, bob in (("walk", 28.0, 30.0, 4.0, 0.03), ("run", 44.0, 66.0, 16.0, 0.06)):
        keys = []
        n = 8
        for i in range(n + 1):
            ph = i / n * math.tau
            pose, off = _gait(ph, stride, bend, -lean, bob)
            keys.append((1 + i * 24 / n, pose, off))
        action(arm, name, keys)

    # Crouch idle and crouch walk.
    crouch = {"LegL": (70, 0, -4), "LegR": (78, 0, 4), "ShinL": (-112, 0, 0), "ShinR": (-120, 0, 0),
              "Spine": (-20, 0, 0), "Chest": (-4, 0, 0), "Head": (18, 0, 0), "_w": ((0.13, 1.27, -0.40), (14, 0, 0))}
    action(arm, "crouch", [(1, _merge(HOLD, crouch), {"Hips": (0, -0.42, 0)}),
                           (31, _merge(HOLD, crouch, {"Spine": (-2, 0, 0)}), {"Hips": (0, -0.43, 0)}),
                           (61, _merge(HOLD, crouch), {"Hips": (0, -0.42, 0)})])
    keys = []
    for i in range(9):
        ph = i / 8 * math.tau
        pose, _ = _gait(ph, 22.0, 26.0, 0.0, 0.0)
        pose = _merge(pose, crouch)
        keys.append((1 + i * 3, pose, {"Hips": (0, -0.42 - abs(math.sin(ph)) * 0.02, 0)}))
    action(arm, "crouch_walk", keys)

    # Air: rising tuck and falling reach.
    action(arm, "jump", [(1, _merge(HOLD, {"LegL": (40, 0, 0), "ShinL": (-70, 0, 0), "LegR": (-10, 0, 0),
                                           "ShinR": (-30, 0, 0), "Spine": (6, 0, 0)}), {})], loop=False)
    fall_a = {"LegL": (22, 0, -6), "ShinL": (-40, 0, 0), "LegR": (8, 0, 6), "ShinR": (-26, 0, 0),
              "Spine": (-4, 0, 0), "Head": (6, 0, 0)}
    fall_b = {"LegL": (18, 0, -8), "ShinL": (-34, 0, 0), "LegR": (12, 0, 8), "ShinR": (-30, 0, 0),
              "Spine": (-6, 0, 0), "Head": (8, 0, 0)}
    action(arm, "fall", [(1, _merge(HOLD, fall_a), {}), (13, _merge(HOLD, fall_b), {}), (25, _merge(HOLD, fall_a), {})])

    # Aim: an upper-body hold, layered over the legs in the game.
    action(arm, "aim", [(1, AIM, {}), (31, _merge(AIM, {"Chest": (0.8, 0, 0)}), {}), (61, AIM, {})])

    # Reload (1.6 s): tilt the rifle, the left hand drops to the belt, pulls a cell, slaps it into
    # the magazine well, racks the bolt, back to the hold.
    tilt = {"_w": ((0.1, 1.22, -0.36), (-16, 18, 30)), "Chest": (0, 4, 0), "Head": (14, 10, 0)}
    belt = {"_ikL": None, "ArmL": (-6, 0, -16), "ForearmL": (-60, 30, 0)}
    insert = {"_ikL": (0.0, -0.24, 0.06)}
    slap = {"_ikL": (0.0, -0.17, 0.05)}
    rack = {"_ikL": (0.07, 0.03, 0.12)}
    action(arm, "reload", [
        (1, HOLD, {}), (8, _merge(HOLD, tilt), {}), (16, _merge(HOLD, tilt, belt), {}),
        (24, _merge(HOLD, tilt, belt, {"Spine": (3, 0, 0), "ForearmL": (-8, 0, 0)}), {}),
        (31, _merge(HOLD, tilt, insert), {}), (35, _merge(HOLD, tilt, slap, {"Chest": (2, 0, 0)}), {}),
        (41, _merge(HOLD, tilt, rack, {"Chest": (0, 6, 0)}), {}), (49, HOLD, {}),
    ], loop=False)

    # Hurt flinch (0.4 s).
    action(arm, "hurt", [(1, HOLD, {}), (4, _merge(HOLD, {"Spine": (10, 8, 5), "Chest": (6, 0, 0), "Head": (-10, -10, 0)}), {}),
                         (12, HOLD, {})], loop=False)

    # Dodge roll (0.5 s): tuck the rifle in, roll forward over the shoulder, come up.
    tuck = {"LegL": (100, 0, 0), "LegR": (100, 0, 0), "ShinL": (-130, 0, 0), "ShinR": (-130, 0, 0),
            "Spine": (40, 0, 0), "Chest": (30, 0, 0), "Head": (-20, 0, 0),
            "_w": ((0.08, 1.3, -0.3), (40, 0, 0))}
    action(arm, "roll", [
        (1, HOLD, {}),
        (4, _merge(tuck, {"Hips": (-60, 0, 0)}), {"Hips": (0, -0.4, 0)}),
        (8, _merge(tuck, {"Hips": (-180, 0, 0)}), {"Hips": (0, -0.45, 0)}),
        (12, _merge(tuck, {"Hips": (-300, 0, 0)}), {"Hips": (0, -0.4, 0)}),
        (16, _merge(HOLD, {"Hips": (-360, 0, 0), "LegL": (40, 0, 0), "ShinL": (-60, 0, 0), "Spine": (10, 0, 0)}), {"Hips": (0, -0.12, 0)}),
    ], loop=False)

    # Interact (0.8 s): the rifle drops to the right hand, the left reaches out and works a panel.
    lowered = {"_w": ((0.18, 1.12, -0.3), (-40, 10, 10)), "_ikL": None}
    reach = _merge(lowered, {"ArmL": (80, 0, 6), "ForearmL": (10, 0, 0), "Spine": (-10, 0, 0), "Chest": (-4, 10, 0), "Head": (-8, 0, 0)})
    action(arm, "interact", [(1, HOLD, {}), (8, reach, {}),
                             (14, _merge(reach, {"ForearmL": (-18, 0, 0)}), {}), (24, HOLD, {})], loop=False)

    # Install (1.4 s): rifle away, kneel, both hands push the part home.
    kneel = _merge(FREE, {"LegL": (85, 0, 0), "ShinL": (-90, 0, 0), "LegR": (-10, 0, 0), "ShinR": (-100, 0, 0),
                          "Spine": (-16, 0, 0), "Head": (-10, 0, 0), "ArmL": (75, 0, 10), "ArmR": (75, 0, -10), "ForearmL": (20, 0, 0), "ForearmR": (20, 0, 0)})
    action(arm, "install", [(1, HOLD, {}), (10, kneel, {"Hips": (0, -0.38, 0)}),
                            (20, _merge(kneel, {"Spine": (-8, 0, 0), "ForearmL": (-20, 0, 0), "ForearmR": (-20, 0, 0)}), {"Hips": (0, -0.38, 0)}),
                            (30, kneel, {"Hips": (0, -0.38, 0)}), (42, HOLD, {})], loop=False)

    # Stim (0.9 s): the left hand slaps the injector into the thigh.
    stab = _merge(lowered, {"ArmL": (16, 0, -4), "ForearmL": (8, 0, 0), "Spine": (-10, 0, 0), "Head": (-16, 0, 0)})
    action(arm, "stim", [(1, HOLD, {}), (9, stab, {}), (13, _merge(stab, {"Spine": (-4, 0, 0), "ArmL": (-6, 0, 0)}), {}),
                         (27, HOLD, {})], loop=False)

    # Throw (0.75 s): the left arm winds back over the shoulder and whips forward.
    action(arm, "throw", [(1, HOLD, {}), (7, _merge(lowered, {"ArmL": (-40, 0, -60), "ForearmL": (-90, 0, 0), "Chest": (-6, 24, 0)}), {}),
                          (12, _merge(lowered, {"ArmL": (110, 0, -10), "ForearmL": (0, 0, 0), "Chest": (6, -20, 0)}), {}),
                          (23, HOLD, {})], loop=False)

    # Down (1.4 s): knees buckle, she folds and topples onto her side. The game hides the rifle.
    action(arm, "die", [
        (1, HOLD, {}),
        (9, _merge(FREE, {"LegL": (60, 0, 0), "LegR": (50, 0, 0), "ShinL": (-100, 0, 0), "ShinR": (-90, 0, 0),
                          "Spine": (20, 0, 0), "Head": (20, 0, 0), "ArmL": (20, 0, -20), "ArmR": (20, 0, 20)}), {"Hips": (0, -0.45, 0)}),
        (20, _merge(FREE, {"Hips": (0, 0, 80), "LegL": (40, 0, 0), "LegR": (60, 0, 0), "ShinL": (-60, 0, 0), "ShinR": (-80, 0, 0),
                           "Spine": (14, 0, 0), "Head": (10, 0, -20), "ArmL": (60, 0, -60), "ArmR": (30, 0, 40)}), {"Hips": (0, -0.75, 0)}),
        (42, _merge(FREE, {"Hips": (0, 0, 88), "LegL": (36, 0, 0), "LegR": (62, 0, 0), "ShinL": (-56, 0, 0), "ShinR": (-84, 0, 0),
                           "Spine": (12, 0, 0), "Head": (6, 0, -26), "ArmL": (70, 0, -70), "ArmR": (24, 0, 40)}), {"Hips": (0, -0.78, 0)}),
    ], loop=False)


def export(arm):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "juno_rigged.glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, use_selection=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_frame_range=False,
                              export_def_bones=False, export_optimize_animation_size=False)
    print("exported", os.path.relpath(path, ROOT))
    blend = os.path.join(ROOT, "blender", "juno_rigged.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    print("saved", os.path.relpath(blend, ROOT))


def main():
    bm.reset()
    bpy.context.scene.render.fps = FPS
    heads = _world_heads()
    arm = build_armature(heads)
    suit = build_undersuit()
    bind(arm, suit)
    build_actions(arm)
    export(arm)


if __name__ == "__main__":
    main()
