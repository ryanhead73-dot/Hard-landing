"""Builds Hard Landing's character, weapon and prop models and exports them as GLB.

Run headless with Blender 4.2+ (or the `bpy` 4.2 module):
    blender --background --python blender/build_models.py
    python blender/build_models.py            # with `pip install bpy==4.2.0`
Optional arguments after `--` pick models by name: `... -- scuttler rifle`.

Every model is a rigid-part rig: each moving part is an empty (a pivot at the joint) with its
meshes as children, so Godot can animate the pivots directly (see godot/scripts/rig.gd).
Positions are written in Godot space (x right, y up, -z forward) and converted on the way in,
so the numbers line up with the game scripts. Output: godot/assets/models/<name>.glb.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "godot", "assets", "models")

# Palette from the art brief.
CREAM = "e9e1cc"
CREAM_WORN = "d8cfb6"
OXIDE = "c4622d"
DARK_METAL = "2b2f33"
STEEL = "8d9397"
BASALT = "1b1d1f"
SLATE = "3c4448"
MOSS = "3fd1b5"
AMBER = "f2a93b"


# --- Scene helpers -------------------------------------------------------------------------

def g(x, y, z):
    """Godot position -> Blender position (Blender is Z-up, the glTF exporter flips it back)."""
    return Vector((x, -z, y))


_mats = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()


def mat(name, color, rough=0.7, metal=0.0, emit=0.0):
    key = (name, color, rough, metal, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    c = tuple(int(color[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    lin = tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)
    p.inputs["Base Color"].default_value = (*lin, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit > 0.0:
        p.inputs["Emission Color"].default_value = (*lin, 1.0)
        p.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


def pivot(name, at=(0, 0, 0), parent=None):
    """An empty at a joint. Children are placed in its local space (Godot axes)."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.1
    bpy.context.collection.objects.link(e)
    e.parent = parent
    e.location = g(*at)
    return e


def _finish(obj, name, at, parent, material, bevel, rot):
    obj.name = name
    obj.data.name = name
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = g(*at)
    if rot:
        # Rotation in Godot axes (degrees about x, y, z) -> Blender axes.
        rx, ry, rz = (math.radians(a) for a in rot)
        obj.rotation_euler = (rx, -rz, ry)
    obj.data.materials.append(material)
    if bevel > 0.0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def box(name, size, at, parent, material, bevel=0.015, rot=None, taper=None):
    """Box sized in Godot axes. taper=(sx, sy) scales the -z (front) face for wedge shapes."""
    sx, sy, sz = size
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        x, y, z = v.co  # blender axes; blender y = -godot z
        if taper and y > 0:  # front face (godot -z)
            x *= taper[0]
            z *= taper[1]
        v.co = Vector((x * sx, y * sz, z * sy))
    bm.to_mesh(me)
    bm.free()
    return _finish(bpy.data.objects.new(name, me), name, at, parent, material, bevel, rot)


def cyl(name, radius, depth, at, parent, material, axis="y", verts=12, bevel=0.01, rot=None, radius2=None):
    """Cylinder along a Godot axis ("x", "y" or "z")."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    _finish(obj, name, at, parent, material, bevel, rot)
    if not rot:
        if axis == "x":
            obj.rotation_euler = (0.0, math.radians(90), 0.0)
        elif axis == "z":
            obj.rotation_euler = (math.radians(90), 0.0, 0.0)
    return obj


def ball(name, radius, at, parent, material, scale=(1, 1, 1), segs=16, rings=10):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    for v in bm.verts:
        x, y, z = v.co
        v.co = Vector((x * scale[0], y * scale[2], z * scale[1]))
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    _finish(obj, name, at, parent, material, 0.0, None)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def limb(name, length, thick, at, parent, material, down=True, bevel=0.02):
    """A pivot at `at` with a box hanging below it (or forward when down=False)."""
    p = pivot(name, at, parent)
    if down:
        box(name + "_mesh", (thick, length, thick), (0, -length * 0.5, 0), p, material, bevel)
    else:
        box(name + "_mesh", (thick, thick, length), (0, 0, -length * 0.5), p, material, bevel)
    return p


def export(name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
                              export_yup=True, use_selection=True, export_animations=False)
    print("exported", os.path.relpath(path, ROOT))


# --- Juno ----------------------------------------------------------------------------------

def juno():
    suit = mat("suit", "4a5a66", 0.8)
    plate = mat("plate", CREAM, 0.55)
    orange = mat("oxide", OXIDE, 0.6)
    dark = mat("dark_metal", DARK_METAL, 0.45, 0.6)
    visor = mat("visor", AMBER, 0.2, 0.0, 2.5)

    root = pivot("Juno")
    hips = pivot("Hips", (0, 0.95, 0), root)
    box("pelvis", (0.36, 0.2, 0.24), (0, 0, 0), hips, suit)
    box("belt", (0.38, 0.06, 0.26), (0, 0.08, 0), hips, dark)
    spine = pivot("Spine", (0, 0.12, 0), hips)
    box("abdomen", (0.32, 0.22, 0.22), (0, 0.12, 0), spine, suit)
    chest = pivot("Chest", (0, 0.25, 0), spine)
    box("torso", (0.44, 0.34, 0.28), (0, 0.17, 0), chest, suit)
    box("chest_plate", (0.4, 0.26, 0.06), (0, 0.19, -0.15), chest, plate, taper=(0.9, 0.9))
    box("chest_stripe", (0.41, 0.04, 0.065), (0, 0.27, -0.155), chest, orange)
    box("back_plate", (0.38, 0.3, 0.05), (0, 0.18, 0.15), chest, plate)
    pack = pivot("PackMount", (0, 0.12, 0.2), chest)
    box("life_support", (0.3, 0.36, 0.14), (0, 0.06, 0.03), pack, dark)
    cyl("tank_l", 0.05, 0.3, (-0.1, 0.06, 0.12), pack, plate)
    cyl("tank_r", 0.05, 0.3, (0.1, 0.06, 0.12), pack, plate)
    neck = pivot("Neck", (0, 0.36, 0), chest)
    head = pivot("Head", (0, 0.06, 0), neck)
    ball("helmet", 0.16, (0, 0.13, 0.01), head, plate, scale=(1.0, 1.05, 1.1))
    box("visor", (0.24, 0.09, 0.06), (0, 0.14, -0.14), head, visor, bevel=0.01, taper=(0.9, 0.8))
    box("helmet_ridge", (0.05, 0.05, 0.28), (0, 0.29, 0.01), head, orange)
    for side, s in (("L", -1), ("R", 1)):
        shoulder = pivot("Arm" + side, (0.27 * s, 0.3, 0), chest)
        box("pauldron" + side, (0.16, 0.1, 0.18), (0.02 * s, 0.02, 0), shoulder, plate)
        box("upper_arm" + side, (0.1, 0.28, 0.11), (0, -0.15, 0), shoulder, suit)
        elbow = pivot("Forearm" + side, (0, -0.3, 0), shoulder)
        box("forearm" + side, (0.1, 0.26, 0.11), (0, -0.13, 0), elbow, suit)
        box("bracer" + side, (0.115, 0.12, 0.125), (0, -0.12, 0), elbow, plate)
        box("glove" + side, (0.09, 0.09, 0.1), (0, -0.3, 0), elbow, dark)
        hip = pivot("Leg" + side, (0.1 * s, -0.06, 0), hips)
        box("thigh" + side, (0.14, 0.42, 0.15), (0, -0.21, 0), hip, suit)
        box("thigh_plate" + side, (0.12, 0.2, 0.04), (0, -0.18, -0.08), hip, plate)
        knee = pivot("Shin" + side, (0, -0.43, 0), hip)
        box("knee" + side, (0.12, 0.08, 0.06), (0, 0.0, -0.08), knee, orange)
        box("shin" + side, (0.13, 0.4, 0.14), (0, -0.2, 0), knee, suit)
        box("shin_plate" + side, (0.11, 0.24, 0.04), (0, -0.18, -0.08), knee, plate)
        box("boot" + side, (0.14, 0.1, 0.26), (0, -0.4, -0.05), knee, dark)
    export("juno")


# --- Wildlife ------------------------------------------------------------------------------

def scuttler():
    shell = mat("scuttler_shell", "1e2124", 0.5, 0.2)
    belly = mat("scuttler_belly", "2c3134", 0.8)
    glow = mat("moss_glow", MOSS, 0.4, 0.0, 3.0)
    root = pivot("Scuttler")
    body = pivot("Body", (0, 0.5, 0), root)
    ball("carapace", 0.6, (0, 0.08, 0.05), body, shell, scale=(1.0, 0.55, 1.25), segs=10, rings=6)
    ball("underside", 0.48, (0, -0.04, 0.05), body, belly, scale=(1.0, 0.5, 1.2), segs=10, rings=6)
    for i in range(4):
        box("spine%d" % i, (0.07, 0.24, 0.07), (0, 0.38 - abs(i - 1.5) * 0.04, -0.32 + i * 0.24), body, glow, rot=(-20, 0, 0))
    head = pivot("Head", (0, 0.02, -0.66), body)
    ball("head_shell", 0.24, (0, 0, -0.06), head, shell, scale=(1.2, 0.7, 1.0), segs=8, rings=5)
    for side, s in (("L", -1), ("R", 1)):
        ball("eye" + side, 0.055, (0.13 * s, 0.07, -0.22), head, glow, segs=8, rings=5)
        jaw = pivot("Jaw" + side, (0.1 * s, -0.06, -0.2), head)
        box("mandible" + side, (0.05, 0.05, 0.22), (0.02 * s, 0, -0.1), jaw, belly, rot=(0, -15 * s, 0))
        for j in range(3):
            z = -0.32 + j * 0.34
            hip = pivot("Leg%s%d" % (side, j + 1), (0.42 * s, -0.02, z), body)
            hip.rotation_euler[1] = math.radians(-25 * s)  # splay upward
            box("upper%s%d" % (side, j), (0.48, 0.07, 0.07), (0.24 * s, 0, 0), hip, shell)
            knee = pivot("Foot%s%d" % (side, j + 1), (0.48 * s, 0, 0), hip)
            knee.rotation_euler[1] = math.radians(75 * s)  # knee bends down
            box("lower%s%d" % (side, j), (0.5, 0.06, 0.06), (0.25 * s, 0, 0), knee, belly, taper=None)
    export("scuttler")


def spitter():
    hide = mat("spitter_hide", "2a2f2c", 0.75)
    plate = mat("spitter_plate", SLATE, 0.5, 0.2)
    sac = mat("acid_sac", "b4e05a", 0.3, 0.0, 2.0)
    glow = mat("moss_glow", MOSS, 0.4, 0.0, 3.0)
    root = pivot("Spitter")
    body = pivot("Body", (0, 0.85, 0), root)
    ball("torso", 0.4, (0, 0, 0.1), body, hide, scale=(1.0, 0.9, 1.3), segs=12, rings=8)
    box("back_plate", (0.5, 0.08, 0.7), (0, 0.32, 0.1), body, plate, rot=(-8, 0, 0))
    sac_p = pivot("Sac", (0, 0.42, 0.28), body)
    ball("sac", 0.28, (0, 0.05, 0), sac_p, sac, scale=(1.0, 0.85, 1.0))
    neck = pivot("Neck", (0, 0.18, -0.35), body)
    box("neck", (0.2, 0.2, 0.42), (0, 0.1, -0.15), neck, hide, rot=(30, 0, 0))
    head = pivot("Head", (0, 0.28, -0.32), neck)
    ball("head", 0.17, (0, 0, -0.05), head, hide, scale=(1.0, 0.8, 1.3), segs=10, rings=6)
    cyl("mouth", 0.08, 0.14, (0, -0.02, -0.25), head, sac, axis="z", verts=10, radius2=0.05)
    for s in (-1, 1):
        ball("eye%d" % s, 0.035, (0.09 * s, 0.07, -0.17), head, glow, segs=6, rings=4)
    for side, s in (("L", -1), ("R", 1)):
        for j, z in enumerate((-0.15, 0.3)):
            hip = pivot("Leg%s%d" % (side, j + 1), (0.3 * s, -0.05, z), body)
            box("thigh%s%d" % (side, j), (0.09, 0.5, 0.09), (0.12 * s, -0.2, 0), hip, hide, rot=(0, 0, 25 * s))
            knee = pivot("Foot%s%d" % (side, j + 1), (0.24 * s, -0.42, 0), hip)
            box("shin%s%d" % (side, j), (0.07, 0.48, 0.07), (0.04 * s, -0.22, 0), knee, plate, rot=(0, 0, -10 * s))
    export("spitter")


def ram():
    hide = mat("ram_hide", "202326", 0.8)
    plate = mat("ram_plate", "4a5257", 0.45, 0.35)
    crest = mat("moss_glow", MOSS, 0.4, 0.0, 2.0)
    horn = mat("ram_horn", "8a8170", 0.6)
    root = pivot("Ram")
    body = pivot("Body", (0, 0.95, 0), root)
    box("barrel", (1.3, 1.0, 2.0), (0, 0, 0.1), body, hide, bevel=0.12)
    box("hump", (1.0, 0.4, 1.1), (0, 0.55, -0.15), body, hide, bevel=0.12)
    for x in (-0.25, 0.25):
        box("vent%d" % int(x * 10), (0.14, 0.1, 1.3), (x, 0.78, 0.15), body, crest, bevel=0.02)
    for i, z in enumerate((-0.4, 0.2, 0.75)):
        box("back_plate%d" % i, (1.2, 0.12, 0.5), (0, 0.55 - i * 0.05, z), body, plate, bevel=0.03)
    tail = pivot("Tail", (0, 0.1, 1.1), body)
    box("tail", (0.25, 0.25, 0.6), (0, -0.1, 0.25), tail, hide, rot=(-25, 0, 0))
    head = pivot("Head", (0, -0.05, -1.0), body)
    box("skull", (0.8, 0.7, 0.6), (0, -0.05, -0.15), head, hide, bevel=0.1)
    box("head_plate", (1.6, 1.15, 0.35), (0, 0.0, -0.45), head, plate, bevel=0.06, taper=(0.85, 0.85))
    box("plate_rim", (1.62, 0.1, 0.37), (0, 0.5, -0.45), head, crest, bevel=0.02)
    for s in (-1, 1):
        box("horn%d" % s, (0.18, 0.18, 0.7), (0.72 * s, 0.25, -0.65), head, horn, rot=(15, 20 * s, 0), taper=(0.3, 0.3))
    for side, s in (("L", -1), ("R", 1)):
        for j, (name, z) in enumerate((("F", -0.65), ("B", 0.7))):
            hip = pivot("Leg%s%s" % (name, side), (0.55 * s, -0.35, z), body)
            box("thigh%s%s" % (name, side), (0.34, 0.45, 0.4), (0, -0.15, 0), hip, hide, bevel=0.06)
            knee = pivot("Foot%s%s" % (name, side), (0, -0.38, 0), hip)
            box("shin%s%s" % (name, side), (0.26, 0.3, 0.28), (0, -0.12, 0), knee, plate, bevel=0.04)
            box("hoof%s%s" % (name, side), (0.32, 0.08, 0.36), (0, -0.27, -0.02), knee, horn, bevel=0.02)
    export("ram")


def warden():
    shell = mat("warden_shell", "16181a", 0.4, 0.3)
    hide = mat("warden_hide", "24282b", 0.8)
    core = mat("warden_core", MOSS, 0.2, 0.0, 5.0)
    glow = mat("moss_glow", MOSS, 0.4, 0.0, 3.0)
    root = pivot("Warden")
    body = pivot("Body", (0, 1.5, 0), root)
    ball("trunk", 1.3, (0, 0, 0.2), body, hide, scale=(1.0, 0.75, 1.4), segs=14, rings=8)
    core_p = pivot("Core", (0, 0.55, -0.2), body)
    ball("core", 0.55, (0, 0, 0), core_p, core, segs=14, rings=8)
    for side, s in (("L", -1), ("R", 1)):
        plate = pivot("Plate" + side, (0.15 * s, 0.75, 0.2), body)
        ball("carapace" + side, 1.25, (0.42 * s, -0.05, 0), plate, shell, scale=(0.6, 0.4, 1.5), segs=12, rings=7)
        for i in range(4):
            box("ridge%s%d" % (side, i), (0.12, 0.5, 0.12), (0.65 * s, 0.62, -1.0 + i * 0.6), plate, glow, rot=(0, 0, 20 * s))
        arm = pivot("Arm" + side, (0.95 * s, 0.1, -1.4), body)
        box("arm_upper" + side, (0.35, 1.1, 0.35), (0.1 * s, -0.4, -0.2), arm, shell, bevel=0.05, rot=(-30, 0, 0))
        fore = pivot("Fist" + side, (0.15 * s, -0.95, -0.55), arm)
        box("arm_lower" + side, (0.45, 0.9, 0.45), (0, -0.4, 0), fore, shell, bevel=0.06, taper=(0.7, 0.7))
        box("knuckle" + side, (0.55, 0.2, 0.55), (0, -0.85, 0), fore, glow, bevel=0.04)
        for j in range(3):
            hip = pivot("Leg%s%d" % (side, j + 1), (1.0 * s, -0.4, -0.6 + j * 1.0), body)
            hip.rotation_euler[1] = math.radians(-20 * s)
            box("leg_upper%s%d" % (side, j), (1.3, 0.24, 0.24), (0.65 * s, 0, 0), hip, shell, bevel=0.04)
            knee = pivot("Foot%s%d" % (side, j + 1), (1.3 * s, 0, 0), hip)
            knee.rotation_euler[1] = math.radians(70 * s)
            box("leg_lower%s%d" % (side, j), (1.2, 0.2, 0.2), (0.6 * s, 0, 0), knee, hide, bevel=0.03, taper=None)
    head = pivot("Head", (0, -0.1, -1.75), body)
    box("brow", (1.2, 0.5, 0.6), (0, 0.15, -0.1), head, shell, bevel=0.1, taper=(0.7, 0.8))
    for s in (-1, 1):
        ball("eye%d" % s, 0.15, (0.35 * s, 0.05, -0.38), head, core, segs=8, rings=5)
    export("warden")


# --- Weapons -------------------------------------------------------------------------------

def rifle():
    metal = mat("gun_metal", "24282b", 0.45, 0.6)
    stripe = mat("oxide", OXIDE, 0.6)
    steel = mat("steel", STEEL, 0.35, 0.8)
    root = pivot("Rifle")
    box("receiver", (0.08, 0.11, 0.42), (0, 0, 0.02), root, metal)
    cyl("barrel", 0.018, 0.4, (0, 0.02, -0.38), root, steel, axis="z", verts=8)
    box("handguard", (0.075, 0.08, 0.26), (0, 0.0, -0.28), root, metal, taper=(0.9, 0.85))
    box("stripe", (0.082, 0.025, 0.24), (0, 0.06, -0.06), root, stripe)
    box("grip", (0.05, 0.14, 0.07), (0, -0.11, 0.08), root, metal, rot=(-15, 0, 0))
    box("mag", (0.045, 0.16, 0.08), (0, -0.12, -0.06), root, steel, rot=(10, 0, 0))
    box("stock", (0.06, 0.1, 0.22), (0, -0.02, 0.32), root, metal, taper=(1.0, 0.8))
    box("sight", (0.03, 0.04, 0.08), (0, 0.08, 0.04), root, steel)
    pivot("Muzzle", (0, 0.02, -0.58), root)
    export("rifle")


def scattergun():
    metal = mat("gun_metal", "24282b", 0.45, 0.6)
    stripe = mat("oxide", OXIDE, 0.6)
    steel = mat("steel", STEEL, 0.35, 0.8)
    wood = mat("grip_polymer", "5a4636", 0.7)
    root = pivot("Scattergun")
    box("receiver", (0.11, 0.13, 0.3), (0, 0, 0.05), root, metal)
    cyl("barrel", 0.035, 0.46, (0, 0.03, -0.32), root, steel, axis="z", verts=10)
    cyl("tube", 0.025, 0.4, (0, -0.04, -0.28), root, steel, axis="z", verts=8)
    pump = pivot("Pump", (0, -0.04, -0.25), root)
    box("pump", (0.09, 0.07, 0.16), (0, 0, 0), pump, wood)
    box("stripe", (0.112, 0.03, 0.18), (0, 0.075, 0.04), root, stripe)
    box("grip", (0.06, 0.15, 0.07), (0, -0.12, 0.15), root, wood, rot=(-15, 0, 0))
    box("stock", (0.07, 0.11, 0.2), (0, -0.03, 0.3), root, metal, taper=(1.0, 0.85))
    pivot("Muzzle", (0, 0.03, -0.56), root)
    export("scattergun")


def arc_lance():
    steel = mat("steel", STEEL, 0.35, 0.8)
    metal = mat("gun_metal", "24282b", 0.45, 0.6)
    arc = mat("arc_glow", "7fd6ff", 0.2, 0.0, 4.0)
    cream = mat("plate", CREAM, 0.55)
    root = pivot("ArcLance")
    box("body", (0.1, 0.13, 0.5), (0, 0, 0.0), root, cream)
    box("spine", (0.06, 0.05, 0.6), (0, 0.08, -0.1), root, metal)
    for i, z in enumerate((-0.38, -0.26, -0.14)):
        cyl("coil%d" % i, 0.07, 0.04, (0, 0.0, z), root, arc, axis="z", verts=12)
    cyl("emitter", 0.03, 0.42, (0, 0.0, -0.3), root, steel, axis="z", verts=8)
    box("prong_l", (0.02, 0.02, 0.16), (-0.04, 0.0, -0.56), root, steel)
    box("prong_r", (0.02, 0.02, 0.16), (0.04, 0.0, -0.56), root, steel)
    box("grip", (0.06, 0.15, 0.07), (0, -0.12, 0.1), root, metal, rot=(-15, 0, 0))
    box("cell", (0.08, 0.1, 0.12), (0, -0.04, 0.24), root, arc)
    pivot("Muzzle", (0, 0.0, -0.64), root)
    export("arc_lance")


# --- Components and props ------------------------------------------------------------------

def components():
    def fresh():
        # Each model starts from an empty file, which drops the materials too.
        reset()
        return (mat("dark_metal", DARK_METAL, 0.45, 0.6), mat("steel", STEEL, 0.35, 0.8),
                mat("oxide", OXIDE, 0.6))

    dark, steel, oxide = fresh()
    root = pivot("AuxCell")
    box("casing", (0.44, 0.62, 0.26), (0, 0, 0), root, dark, bevel=0.03)
    box("window", (0.3, 0.42, 0.02), (0, 0.02, -0.135), root, mat("cell_glow", AMBER, 0.2, 0.0, 4.0))
    for y in (-0.33, 0.33):
        box("cap%d" % int(y * 10), (0.48, 0.06, 0.3), (0, y, 0), root, steel)
    box("handle", (0.2, 0.05, 0.05), (0, 0.38, 0), root, oxide)
    export("aux_cell")

    dark, steel, oxide = fresh()
    root = pivot("Manifold")
    for i, x in enumerate((-0.35, 0.0, 0.35)):
        cyl("pipe%d" % i, 0.08, 0.45, (x, 0, 0), root, steel, verts=10)
    cyl("header", 0.1, 1.05, (0, 0.18, 0), root, steel, axis="x", verts=12)
    cyl("header_lo", 0.1, 1.05, (0, -0.18, 0), root, steel, axis="x", verts=12)
    box("frost", (0.9, 0.06, 0.2), (0, 0, -0.02), root, mat("coolant_glow", "7fd6ff", 0.2, 0.0, 2.5))
    export("manifold")

    dark, steel, oxide = fresh()
    root = pivot("Glazing")
    box("frame", (1.0, 0.8, 0.05), (0, 0, 0), root, dark, bevel=0.01)
    glass = mat("glass", "bfe3ea", 0.05, 0.0, 0.4)
    box("pane", (0.9, 0.7, 0.03), (0, 0, -0.01), root, glass, bevel=0.0)
    export("glazing")

    dark, steel, oxide = fresh()
    root = pivot("Struts")
    for i, x in enumerate((-0.09, 0.09)):
        cyl("cyl%d" % i, 0.07, 0.8, (x, 0.15, 0), root, steel, verts=10)
        cyl("rod%d" % i, 0.035, 0.5, (x, -0.4, 0), root, mat("chrome", "d0d4d6", 0.15, 1.0), verts=8)
    box("clamp", (0.34, 0.08, 0.16), (0, 0.5, 0), root, oxide)
    box("foot", (0.34, 0.06, 0.2), (0, -0.62, 0), root, dark)
    export("struts")

    dark, steel, oxide = fresh()
    root = pivot("WingPanel")
    box("skin", (1.4, 0.88, 0.06), (0, 0, 0), root, mat("hull_cream", CREAM, 0.55), bevel=0.01, taper=(0.7, 1.0))
    box("band", (1.42, 0.12, 0.065), (0, 0.25, 0), root, oxide)
    box("spar", (1.3, 0.06, 0.08), (0, -0.2, 0.02), root, dark)
    export("wing_panel")

    dark, steel, oxide = fresh()
    root = pivot("DriveCoil")
    cyl("core", 0.16, 0.42, (0, 0, 0), root, dark, axis="z", verts=12)
    for i in range(4):
        cyl("winding%d" % i, 0.32, 0.06, (0, 0, -0.15 + i * 0.1), root, mat("coil_glow", "ff7a3a", 0.3, 0.0, 3.0), axis="z", verts=16, radius2=0.3)
    box("bracket", (0.7, 0.08, 0.4), (0, -0.33, 0), root, steel)
    export("drive_coil")

    dark, steel, oxide = fresh()
    root = pivot("NavCore")
    ball("core", 0.16, (0, 0, 0), root, mat("nav_glow", MOSS, 0.2, 0.0, 5.0), segs=12, rings=8)
    for i, rot in enumerate(((0, 0, 0), (90, 0, 0), (0, 0, 90))):
        cyl("ring%d" % i, 0.2, 0.03, (0, 0, 0), root, steel, verts=20, radius2=0.2, rot=rot)
    for s in (-1, 1):
        box("cap%d" % s, (0.16, 0.06, 0.16), (0, 0.2 * s, 0), root, dark)
    export("nav_core")

    dark, steel, oxide = fresh()
    root = pivot("Crate")
    box("body", (1.4, 0.8, 0.9), (0, 0.4, 0), root, mat("crate", OXIDE, 0.75), bevel=0.04)
    for x in (-0.55, 0.55):
        box("rib%d" % int(x * 10), (0.08, 0.82, 0.92), (x, 0.4, 0), root, dark, bevel=0.01)
    box("lid", (1.45, 0.08, 0.95), (0, 0.84, 0), root, mat("lid_glow", AMBER, 0.4, 0.0, 1.0), bevel=0.01)
    box("stencil", (0.5, 0.18, 0.01), (0, 0.45, -0.455), root, mat("stencil", CREAM, 0.8))
    export("crate")


BUILDERS = {
    "juno": juno, "scuttler": scuttler, "spitter": spitter, "ram": ram, "warden": warden,
    "rifle": rifle, "scattergun": scattergun, "arc_lance": arc_lance,
}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = args or list(BUILDERS) + ["components"]
    for name in names:
        reset()
        if name == "components":
            components()
        else:
            BUILDERS[name]()


if __name__ == "__main__":
    main()
