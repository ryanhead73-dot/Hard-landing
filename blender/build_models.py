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

def pod(name, size, at, parent, material, n=2.6, taper=1.0, segs=20, rings=12, rot=None, taper_axis="y"):
    """A smooth rounded volume (superellipsoid) sized in Godot axes: n=2 is an ellipsoid, higher
    is boxier. taper scales one end: the bottom (-y) in x and z by default, or with
    taper_axis="z" the front (-z) in x and y, like box()'s taper."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    e = 2.0 / n
    for v in bm.verts:
        x, y, z = v.co  # blender axes: z is Godot up, +y is Godot's front (-z)
        f = lambda a: math.copysign(abs(a) ** e, a)
        x, y, z = f(x), f(y), f(z)
        if taper_axis == "z":
            k = taper + (1.0 - taper) * (1.0 - (y + 1.0) * 0.5)
            v.co = Vector((x * size[0] * 0.5 * k, y * size[2] * 0.5, z * size[1] * 0.5 * k))
        else:
            k = taper + (1.0 - taper) * (z + 1.0) * 0.5
            v.co = Vector((x * size[0] * 0.5 * k, y * size[2] * 0.5 * k, z * size[1] * 0.5))
    bm.to_mesh(me)
    bm.free()
    obj = _finish(bpy.data.objects.new(name, me), name, at, parent, material, 0.0, rot)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def obox(name, size, at, parent, material, bevel=0.0, rot=None, taper=None, n=2.8):
    """box() for creatures: the same size, placement and front taper, as a rounded pod."""
    t = taper[0] if taper else 1.0
    return pod(name, size, at, parent, material, n=n, taper=t, segs=16, rings=10, rot=rot, taper_axis="z")


def juno():
    suit = mat("suit", "3f4d58", 0.85)
    weave = mat("suit_dark", "2a333b", 0.9)
    plate = mat("plate", CREAM, 0.45)
    orange = mat("oxide", OXIDE, 0.55)
    dark = mat("dark_metal", DARK_METAL, 0.4, 0.6)
    visor = mat("visor", "e08a2c", 0.08, 0.3, 0.9)
    lamp = mat("lamp", "5fe0c8", 0.3, 0.0, 2.0)

    root = pivot("Juno")
    hips = pivot("Hips", (0, 0.95, 0), root)
    pod("pelvis", (0.38, 0.22, 0.26), (0, -0.01, 0), hips, suit, n=3.0, taper=0.85)
    pod("belt", (0.41, 0.075, 0.29), (0, 0.08, 0), hips, dark, n=4.0)
    pod("buckle", (0.1, 0.06, 0.04), (0, 0.08, -0.135), hips, orange, n=3.0)
    for s in (-1, 1):
        pod("pouch%d" % s, (0.08, 0.1, 0.07), (0.18 * s, 0.02, -0.05), hips, weave, n=3.0)
    spine = pivot("Spine", (0, 0.12, 0), hips)
    pod("abdomen", (0.33, 0.26, 0.23), (0, 0.12, 0), spine, weave, n=2.6)
    chest = pivot("Chest", (0, 0.25, 0), spine)
    pod("torso", (0.5, 0.38, 0.3), (0, 0.16, 0), chest, suit, n=3.0, taper=0.78)
    pod("chest_plate", (0.42, 0.27, 0.1), (0, 0.2, -0.11), chest, plate, n=3.2, taper=0.85)
    pod("chest_stripe", (0.3, 0.035, 0.1), (0, 0.29, -0.125), chest, orange, n=4.0)
    pod("chest_lamp", (0.04, 0.025, 0.02), (0.11, 0.2, -0.165), chest, lamp, n=3.0)
    pod("collar", (0.3, 0.08, 0.26), (0, 0.35, 0), chest, dark, n=3.5)
    pod("back_plate", (0.36, 0.3, 0.06), (0, 0.18, 0.13), chest, plate, n=3.2)
    pack = pivot("PackMount", (0, 0.12, 0.2), chest)
    # Life-support pack: a squared-off dark unit in a cream frame, twin steel bottles set into
    # its sides, a vent grille and the status lamp. Hard edges, so it reads as kit, not body.
    pod("life_support", (0.3, 0.38, 0.15), (0, 0.06, 0.03), pack, dark, n=5.0, taper=0.92)
    pod("pack_frame", (0.34, 0.06, 0.17), (0, 0.25, 0.03), pack, plate, n=5.0)
    pod("pack_base", (0.32, 0.05, 0.16), (0, -0.13, 0.03), pack, plate, n=5.0)
    pod("pack_cap", (0.2, 0.025, 0.12), (0, 0.29, 0.03), pack, orange, n=4.0)
    steel = mat("steel", STEEL, 0.25, 0.85)
    for side, s in (("l", -1), ("r", 1)):
        cyl("tank_" + side, 0.042, 0.3, (0.135 * s, 0.05, 0.08), pack, steel, verts=14, bevel=0.004)
        cyl("tank_band_" + side, 0.045, 0.03, (0.135 * s, 0.12, 0.08), pack, orange, verts=14, bevel=0.0)
        cyl("tank_valve_" + side, 0.018, 0.04, (0.135 * s, 0.22, 0.08), pack, dark, verts=8, bevel=0.0)
    for k in range(4):
        box("vent%d" % k, (0.16, 0.012, 0.01), (0, 0.16 - k * 0.028, 0.108), pack, weave, bevel=0.0)
    cyl("hose", 0.014, 0.2, (-0.08, 0.27, -0.02), pack, weave, verts=8, bevel=0.0, rot=(60, 0, 20))
    pod("pack_lamp", (0.05, 0.03, 0.02), (0, -0.04, 0.11), pack, lamp, n=3.0)
    neck = pivot("Neck", (0, 0.36, 0), chest)
    pod("neck_ring", (0.2, 0.06, 0.19), (0, 0.02, 0), neck, weave, n=2.4)
    head = pivot("Head", (0, 0.06, 0), neck)
    pod("helmet", (0.33, 0.35, 0.36), (0, 0.14, 0.01), head, plate, n=2.3)
    # The visor bulges out of the helmet's face: a flattened ellipsoid set forward.
    pod("visor", (0.27, 0.15, 0.2), (0, 0.13, -0.08), head, visor, n=2.4)
    pod("visor_brow", (0.29, 0.04, 0.18), (0, 0.21, -0.085), head, dark, n=3.0)
    pod("helmet_ridge", (0.05, 0.05, 0.3), (0, 0.3, 0.02), head, orange, n=3.0)
    # The back of the helmet: a dark seal plate and a rim, so it isn't just a ball from behind.
    pod("helmet_rear", (0.24, 0.13, 0.08), (0, 0.04, 0.15), head, dark, n=3.2)
    pod("helmet_rim", (0.31, 0.03, 0.32), (0, -0.015, 0.02), head, dark, n=3.0)
    for s in (-1, 1):
        pod("ear%d" % s, (0.05, 0.1, 0.1), (0.165 * s, 0.12, 0.02), head, dark, n=2.6)
    cyl("antenna", 0.006, 0.16, (0.15, 0.27, 0.07), head, dark, verts=6, bevel=0.0)
    for side, s in (("L", -1), ("R", 1)):
        shoulder = pivot("Arm" + side, (0.29 * s, 0.3, 0), chest)
        pod("pauldron" + side, (0.16, 0.11, 0.19), (0.01 * s, 0.0, 0), shoulder, plate, n=3.4, taper=0.85)
        pod("pauldron_trim" + side, (0.18, 0.03, 0.18), (0.015 * s, -0.055, 0), shoulder, orange, n=3.0)
        pod("upper_arm" + side, (0.135, 0.31, 0.14), (0, -0.15, 0), shoulder, suit, n=2.4, taper=0.85)
        elbow = pivot("Forearm" + side, (0, -0.3, 0), shoulder)
        pod("elbow" + side, (0.125, 0.1, 0.125), (0, 0.0, 0), elbow, weave, n=2.2)
        pod("forearm" + side, (0.12, 0.27, 0.13), (0, -0.13, 0), elbow, suit, n=2.4, taper=0.85)
        pod("bracer" + side, (0.145, 0.16, 0.15), (0, -0.13, 0), elbow, plate, n=3.0, taper=0.9)
        pod("glove" + side, (0.11, 0.12, 0.12), (0, -0.3, 0), elbow, dark, n=2.6)
        hip = pivot("Leg" + side, (0.1 * s, -0.06, 0), hips)
        pod("thigh" + side, (0.19, 0.46, 0.2), (0, -0.21, 0), hip, suit, n=2.4, taper=0.8)
        pod("thigh_plate" + side, (0.15, 0.24, 0.06), (0, -0.18, -0.09), hip, plate, n=3.0, taper=0.85)
        pod("hip_joint" + side, (0.17, 0.12, 0.17), (0, -0.01, 0), hip, weave, n=2.2)
        knee = pivot("Shin" + side, (0, -0.43, 0), hip)
        pod("knee_joint" + side, (0.15, 0.14, 0.15), (0, 0.01, 0), knee, weave, n=2.2)
        pod("knee" + side, (0.15, 0.13, 0.1), (0, 0.0, -0.085), knee, orange, n=2.6)
        pod("shin" + side, (0.16, 0.42, 0.17), (0, -0.19, 0), knee, suit, n=2.4, taper=0.82)
        pod("shin_plate" + side, (0.13, 0.26, 0.06), (0, -0.17, -0.08), knee, plate, n=3.0, taper=0.85)
        pod("boot" + side, (0.18, 0.15, 0.3), (0, -0.39, -0.045), knee, dark, n=3.2)
        pod("sole" + side, (0.185, 0.04, 0.31), (0, -0.445, -0.045), knee, weave, n=4.0)
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
        obox("spine%d" % i, (0.07, 0.24, 0.07), (0, 0.38 - abs(i - 1.5) * 0.04, -0.32 + i * 0.24), body, glow, rot=(-20, 0, 0))
    head = pivot("Head", (0, 0.02, -0.66), body)
    ball("head_shell", 0.24, (0, 0, -0.06), head, shell, scale=(1.2, 0.7, 1.0), segs=8, rings=5)
    for side, s in (("L", -1), ("R", 1)):
        ball("eye" + side, 0.055, (0.13 * s, 0.07, -0.22), head, glow, segs=8, rings=5)
        jaw = pivot("Jaw" + side, (0.1 * s, -0.06, -0.2), head)
        obox("mandible" + side, (0.05, 0.05, 0.22), (0.02 * s, 0, -0.1), jaw, belly, rot=(0, -15 * s, 0))
        for j in range(3):
            z = -0.32 + j * 0.34
            hip = pivot("Leg%s%d" % (side, j + 1), (0.42 * s, -0.02, z), body)
            hip.rotation_euler[1] = math.radians(-25 * s)  # splay upward
            obox("upper%s%d" % (side, j), (0.48, 0.07, 0.07), (0.24 * s, 0, 0), hip, shell)
            knee = pivot("Foot%s%d" % (side, j + 1), (0.48 * s, 0, 0), hip)
            knee.rotation_euler[1] = math.radians(75 * s)  # knee bends down
            obox("lower%s%d" % (side, j), (0.5, 0.06, 0.06), (0.25 * s, 0, 0), knee, belly, taper=None)
    export("scuttler")


def spitter():
    hide = mat("spitter_hide", "2a2f2c", 0.75)
    plate = mat("spitter_plate", SLATE, 0.5, 0.2)
    sac = mat("acid_sac", "b4e05a", 0.3, 0.0, 2.0)
    glow = mat("moss_glow", MOSS, 0.4, 0.0, 3.0)
    root = pivot("Spitter")
    body = pivot("Body", (0, 0.85, 0), root)
    ball("torso", 0.4, (0, 0, 0.1), body, hide, scale=(1.0, 0.9, 1.3), segs=12, rings=8)
    obox("back_plate", (0.5, 0.08, 0.7), (0, 0.32, 0.1), body, plate, rot=(-8, 0, 0))
    sac_p = pivot("Sac", (0, 0.42, 0.28), body)
    ball("sac", 0.28, (0, 0.05, 0), sac_p, sac, scale=(1.0, 0.85, 1.0))
    neck = pivot("Neck", (0, 0.18, -0.35), body)
    obox("neck", (0.2, 0.2, 0.42), (0, 0.1, -0.15), neck, hide, rot=(30, 0, 0))
    head = pivot("Head", (0, 0.28, -0.32), neck)
    ball("head", 0.17, (0, 0, -0.05), head, hide, scale=(1.0, 0.8, 1.3), segs=10, rings=6)
    cyl("mouth", 0.08, 0.14, (0, -0.02, -0.25), head, sac, axis="z", verts=10, radius2=0.05)
    for s in (-1, 1):
        ball("eye%d" % s, 0.035, (0.09 * s, 0.07, -0.17), head, glow, segs=6, rings=4)
    for side, s in (("L", -1), ("R", 1)):
        for j, z in enumerate((-0.15, 0.3)):
            hip = pivot("Leg%s%d" % (side, j + 1), (0.3 * s, -0.05, z), body)
            obox("thigh%s%d" % (side, j), (0.09, 0.5, 0.09), (0.12 * s, -0.2, 0), hip, hide, rot=(0, 0, 25 * s))
            knee = pivot("Foot%s%d" % (side, j + 1), (0.24 * s, -0.42, 0), hip)
            obox("shin%s%d" % (side, j), (0.07, 0.48, 0.07), (0.04 * s, -0.22, 0), knee, plate, rot=(0, 0, -10 * s))
    export("spitter")


def ram():
    hide = mat("ram_hide", "202326", 0.8)
    plate = mat("ram_plate", "4a5257", 0.45, 0.35)
    crest = mat("moss_glow", MOSS, 0.4, 0.0, 2.0)
    horn = mat("ram_horn", "8a8170", 0.6)
    root = pivot("Ram")
    body = pivot("Body", (0, 0.95, 0), root)
    obox("barrel", (1.3, 1.0, 2.0), (0, 0, 0.1), body, hide, bevel=0.12)
    obox("hump", (1.0, 0.4, 1.1), (0, 0.55, -0.15), body, hide, bevel=0.12)
    for x in (-0.25, 0.25):
        obox("vent%d" % int(x * 10), (0.14, 0.1, 1.3), (x, 0.78, 0.15), body, crest, bevel=0.02)
    for i, z in enumerate((-0.4, 0.2, 0.75)):
        obox("back_plate%d" % i, (1.2, 0.12, 0.5), (0, 0.55 - i * 0.05, z), body, plate, bevel=0.03)
    tail = pivot("Tail", (0, 0.1, 1.1), body)
    obox("tail", (0.25, 0.25, 0.6), (0, -0.1, 0.25), tail, hide, rot=(-25, 0, 0))
    head = pivot("Head", (0, -0.05, -1.0), body)
    obox("skull", (0.8, 0.7, 0.6), (0, -0.05, -0.15), head, hide, bevel=0.1)
    obox("head_plate", (1.6, 1.15, 0.35), (0, 0.0, -0.45), head, plate, bevel=0.06, taper=(0.85, 0.85))
    obox("plate_rim", (1.62, 0.1, 0.37), (0, 0.5, -0.45), head, crest, bevel=0.02)
    for s in (-1, 1):
        obox("horn%d" % s, (0.18, 0.18, 0.7), (0.72 * s, 0.25, -0.65), head, horn, rot=(15, 20 * s, 0), taper=(0.3, 0.3))
    for side, s in (("L", -1), ("R", 1)):
        for j, (name, z) in enumerate((("F", -0.65), ("B", 0.7))):
            hip = pivot("Leg%s%s" % (name, side), (0.55 * s, -0.35, z), body)
            obox("thigh%s%s" % (name, side), (0.34, 0.45, 0.4), (0, -0.15, 0), hip, hide, bevel=0.06)
            knee = pivot("Foot%s%s" % (name, side), (0, -0.38, 0), hip)
            obox("shin%s%s" % (name, side), (0.26, 0.3, 0.28), (0, -0.12, 0), knee, plate, bevel=0.04)
            obox("hoof%s%s" % (name, side), (0.32, 0.08, 0.36), (0, -0.27, -0.02), knee, horn, bevel=0.02)
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
            obox("ridge%s%d" % (side, i), (0.12, 0.5, 0.12), (0.65 * s, 0.62, -1.0 + i * 0.6), plate, glow, rot=(0, 0, 20 * s))
        arm = pivot("Arm" + side, (0.95 * s, 0.1, -1.4), body)
        obox("arm_upper" + side, (0.35, 1.1, 0.35), (0.1 * s, -0.4, -0.2), arm, shell, bevel=0.05, rot=(-30, 0, 0))
        fore = pivot("Fist" + side, (0.15 * s, -0.95, -0.55), arm)
        obox("arm_lower" + side, (0.45, 0.9, 0.45), (0, -0.4, 0), fore, shell, bevel=0.06, taper=(0.7, 0.7))
        obox("knuckle" + side, (0.55, 0.2, 0.55), (0, -0.85, 0), fore, glow, bevel=0.04)
        for j in range(3):
            hip = pivot("Leg%s%d" % (side, j + 1), (1.0 * s, -0.4, -0.6 + j * 1.0), body)
            hip.rotation_euler[1] = math.radians(-20 * s)
            obox("leg_upper%s%d" % (side, j), (1.3, 0.24, 0.24), (0.65 * s, 0, 0), hip, shell, bevel=0.04)
            knee = pivot("Foot%s%d" % (side, j + 1), (1.3 * s, 0, 0), hip)
            knee.rotation_euler[1] = math.radians(70 * s)
            obox("leg_lower%s%d" % (side, j), (1.2, 0.2, 0.2), (0.6 * s, 0, 0), knee, hide, bevel=0.03, taper=None)
    head = pivot("Head", (0, -0.1, -1.75), body)
    obox("brow", (1.2, 0.5, 0.6), (0, 0.15, -0.1), head, shell, bevel=0.1, taper=(0.7, 0.8))
    for s in (-1, 1):
        ball("eye%d" % s, 0.15, (0.35 * s, 0.05, -0.38), head, core, segs=8, rings=5)
    export("warden")


# --- Weapons -------------------------------------------------------------------------------

def lurker():
    """Mire lurker: a long, low pool ambusher. Flat wet hide, a pale belly, a broad hinged jaw
    with a row of bone teeth, glowing eye stalks (all that shows above the water while it waits)
    and a ridge of fin spines that flares teal when it surfaces."""
    hide = mat("lurker_hide", "1b2420", 0.35, 0.05)
    belly = mat("lurker_belly", "57574a", 0.6)
    bone = mat("ram_horn", "8a8170", 0.6)
    gum = mat("lurker_gum", "5a1f22", 0.5)
    glow = mat("lurker_glow", MOSS, 0.4, 0.0, 2.0)
    root = pivot("Lurker")
    body = pivot("Body", (0, 0.36, 0), root)
    pod("torso", (0.95, 0.42, 2.1), (0, 0.02, 0.05), body, hide, n=2.4, taper=0.85, taper_axis="z")
    pod("belly", (0.8, 0.22, 1.9), (0, -0.12, 0.05), body, belly, n=2.2)
    pod("shoulders", (1.05, 0.36, 0.6), (0, 0.04, -0.6), body, hide, n=2.3)
    for i in range(7):
        z = -0.75 + i * 0.26
        hgt = 0.2 - abs(i - 2.5) * 0.03
        obox("spine%d" % i, (0.03, hgt, 0.12), (0, 0.24 + hgt * 0.35, z), body, glow, rot=(-35, 0, 0), n=2.2)
        for side in (-1, 1):
            obox("scute%d%d" % (i, side), (0.14, 0.06, 0.16), (0.24 * side, 0.2, z + 0.1), body, hide, rot=(0, 0, 18 * side))
    head = pivot("Head", (0, 0.02, -1.05), body)
    pod("skull", (0.74, 0.26, 0.78), (0, 0.05, -0.3), head, hide, n=2.6, taper=0.6, taper_axis="z")
    pod("brow", (0.6, 0.14, 0.3), (0, 0.16, -0.12), head, hide, n=2.4)
    for side, sx in (("L", -1), ("R", 1)):
        stalk = pivot("Stalk" + side, (0.22 * sx, 0.18, -0.16), head)
        obox("stalk" + side, (0.06, 0.22, 0.06), (0, 0.09, 0), stalk, hide, rot=(-15, 0, 12 * sx))
        ball("eye" + side, 0.055, (0.02 * sx, 0.22, -0.03), stalk, glow, segs=8, rings=5)
    for i in range(7):
        x = -0.27 + i * 0.09
        obox("tooth_u%d" % i, (0.03, 0.08, 0.03), (x, -0.07, -0.58 + abs(x) * 0.55), head, bone, taper=None)
    jaw = pivot("Jaw", (0, -0.03, -0.02), head)
    pod("jaw", (0.7, 0.14, 0.78), (0, -0.07, -0.33), jaw, belly, n=2.6, taper=0.6, taper_axis="z")
    pod("tongue", (0.36, 0.05, 0.5), (0, 0.01, -0.3), jaw, gum, n=2.2)
    for i in range(6):
        x = -0.23 + i * 0.09
        obox("tooth_l%d" % i, (0.03, 0.07, 0.03), (x, 0.02, -0.56 + abs(x) * 0.55), jaw, bone, taper=None)
    tail = pivot("Tail", (0, 0.0, 1.05), body)
    pod("tail", (0.5, 0.3, 1.1), (0, 0, 0.5), tail, hide, n=2.3, taper=0.6, taper_axis="z")
    tip = pivot("TailTip", (0, 0, 1.0), tail)
    pod("tail_tip", (0.26, 0.18, 1.1), (0, 0, 0.5), tip, hide, n=2.2)
    obox("tail_fin", (0.03, 0.18, 0.8), (0, 0.1, 0.5), tip, glow, rot=(4, 0, 0), n=2.2)
    for side, sx in (("L", -1), ("R", 1)):
        for j, z in enumerate((-0.6, 0.65)):
            hip = pivot("Leg%s%d" % (side, j + 1), (0.42 * sx, -0.04, z), body)
            hip.rotation_euler[1] = math.radians(-12 * sx)
            obox("upper%s%d" % (side, j), (0.4, 0.15, 0.15), (0.19 * sx, 0, 0), hip, hide)
            knee = pivot("Foot%s%d" % (side, j + 1), (0.38 * sx, 0, 0), hip)
            knee.rotation_euler[1] = math.radians(65 * sx)
            obox("lower%s%d" % (side, j), (0.32, 0.12, 0.12), (0.15 * sx, 0, 0), knee, hide)
            pod("paw%s%d" % (side, j), (0.22, 0.06, 0.24), (0.32 * sx, -0.02, 0), knee, belly, n=2.2)
    export("lurker")


def skimmer():
    """Basin skimmer: a lean glider on two pairs of veined membrane wings, all neck and tail,
    with a glowing belly sac (its soft spot) that lights up before it dives, and hooked
    talons it rakes with on the way past."""
    hide = mat("skimmer_hide", "23292a", 0.55, 0.05)
    web = mat("skimmer_web", "3a3530", 0.8)
    bone = mat("ram_horn", "8a8170", 0.6)
    glow = mat("skimmer_glow", MOSS, 0.4, 0.0, 2.5)
    root = pivot("Skimmer")
    body = pivot("Body", (0, 0.0, 0), root)
    pod("torso", (0.34, 0.26, 0.95), (0, 0, 0.0), body, hide, n=2.3, taper=0.7, taper_axis="z")
    pod("keel", (0.12, 0.12, 0.6), (0, 0.13, 0.0), body, hide, n=2.2)
    core = pivot("Core", (0, -0.13, 0.05), body)
    ball("core", 0.13, (0, 0, 0), core, glow, scale=(1.0, 0.8, 1.4), segs=10, rings=6)
    head = pivot("Head", (0, 0.03, -0.5), body)
    pod("neck", (0.14, 0.13, 0.32), (0, 0, -0.08), head, hide, n=2.2)
    pod("skull", (0.2, 0.15, 0.34), (0, 0.02, -0.3), head, hide, n=2.4, taper=0.45, taper_axis="z")
    obox("beak", (0.05, 0.05, 0.22), (0, -0.02, -0.52), head, bone, taper=(0.3, 0.3))
    for s in (-1, 1):
        ball("eye%d" % s, 0.03, (0.08 * s, 0.06, -0.33), head, glow, segs=6, rings=4)
    for side, sx in (("L", -1), ("R", 1)):
        wing = pivot("Wing" + side, (0.15 * sx, 0.06, -0.12), body)
        obox("arm" + side, (0.5, 0.06, 0.06), (0.25 * sx, 0, -0.02), wing, hide)
        pod("web" + side, (0.62, 0.02, 0.66), (0.27 * sx, 0, 0.26), wing, web, n=2.8, taper=0.85, taper_axis="z")
        for k, z in enumerate((0.05, 0.25, 0.45)):
            obox("vein%s%d" % (side, k), (0.5, 0.025, 0.025), (0.26 * sx, 0.012, z), wing, glow, rot=(0, -12 * sx * k, 0))
        tip = pivot("WingTip" + side, (0.52 * sx, 0, -0.02), wing)
        obox("finger" + side, (0.6, 0.045, 0.045), (0.3 * sx, 0, 0.02), tip, hide, rot=(0, 10 * sx, 0))
        pod("tipweb" + side, (0.66, 0.018, 0.6), (0.3 * sx, 0, 0.26), tip, web, n=2.4, taper=0.55, taper_axis="z")
        obox("tipvein" + side, (0.5, 0.022, 0.022), (0.28 * sx, 0.01, 0.2), tip, glow, rot=(0, -20 * sx, 0))
        claw = pivot("Claw" + side, (0.1 * sx, -0.12, -0.05), body)
        obox("shank" + side, (0.04, 0.2, 0.04), (0, -0.09, 0), claw, hide)
        obox("talon" + side, (0.03, 0.03, 0.14), (0, -0.19, -0.05), claw, bone, taper=(0.3, 0.3))
    tail = pivot("Tail", (0, 0.0, 0.46), body)
    pod("tail", (0.12, 0.1, 0.7), (0, 0, 0.33), tail, hide, n=2.2, taper=0.5, taper_axis="z")
    tip = pivot("TailTip", (0, 0, 0.68), tail)
    pod("tail_tip", (0.06, 0.05, 0.5), (0, 0, 0.24), tip, hide, n=2.2)
    obox("tail_fin", (0.24, 0.015, 0.22), (0, 0, 0.42), tip, glow, n=2.2)
    export("skimmer")


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
    "juno": juno, "scuttler": scuttler, "spitter": spitter, "ram": ram, "warden": warden, "lurker": lurker, "skimmer": skimmer,
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
