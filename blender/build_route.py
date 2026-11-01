"""Builds the opening expedition's kit as GLB: the relay's power line (lattice pylons, standing
and toppled), the geothermal wellhead the line ran from, cable junction boxes, the relay's
charging cradle with its clamp arms, and a floodlight mast.

Run headless with Blender 4.2+ (or the `bpy` 4.2 module):
    python blender/build_route.py            # with `pip install bpy==4.2.0`
Optional arguments after `--` pick props by name.

Same helpers and Godot-space coordinates as build_models.py; origins at the centre of the base.
Static props are joined into one mesh per pivot before export, so a 300-strut pylon is a
single draw per material, not 300 nodes. Pivots that animate keep their own meshes:
the cradle's ClampL / ClampR swing open about their hinge (local z).
Output: godot/assets/models/prop_<name>.glb.
"""

import math
import os
import sys

import bpy
import bmesh  # noqa: E402 (needs bpy first)
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_models as m  # noqa: E402

GALV = "7f878b"        # weathered galvanised steel
GALV_DARK = "4a5054"
CONCRETE = "6f726c"
RUST = "7a4026"
HAZARD = "e0a83a"
CERAMIC = "c9c2b0"


def strut(name, a, b, thick, parent, material):
    """A square-section bar from Godot point a to point b (no rotation maths at the call site)."""
    a = Vector(a)
    b = Vector(b)
    d = (b - a).normalized()
    up = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))
    u = d.cross(up).normalized() * thick * 0.5
    v = d.cross(u).normalized() * thick * 0.5
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for p in (a, b):
        rings.append([bm.verts.new(m.g(*(p + u + v))), bm.verts.new(m.g(*(p - u + v))),
                      bm.verts.new(m.g(*(p - u - v))), bm.verts.new(m.g(*(p + u - v)))])
    for k in range(4):
        k2 = (k + 1) % 4
        bm.faces.new((rings[0][k], rings[0][k2], rings[1][k2], rings[1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.data.materials.append(material)
    return obj


def join_by_parent():
    """Joins every group of meshes that share a parent into one object (modifiers applied)."""
    groups = {}
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            groups.setdefault(o.parent.name if o.parent else "", []).append(o)
    for key, objs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.convert(target="MESH")
        if len(objs) > 1:
            bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
        joined.name = (key or "mesh") + "_mesh"
        for poly in joined.data.polygons:
            poly.use_smooth = False


def _tower(prefix, parent, steel, dark, h=8.4, base=0.95, top=0.3, arm_y=7.3):
    """A four-legged tapered lattice tower with a crossarm and two insulator strings."""
    def corner(sx, sz, y):
        r = base + (top - base) * (y / h)
        return (sx * r, y, sz * r)
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for i, (sx, sz) in enumerate(corners):
        strut("%sleg%d" % (prefix, i), corner(sx, sz, 0.0), corner(sx, sz, h), 0.09, parent, steel)
    levels = [0.0, 1.9, 3.6, 5.0, 6.2, arm_y]
    for li in range(len(levels) - 1):
        y0, y1 = levels[li], levels[li + 1]
        for i in range(4):
            c0, c1 = corners[i], corners[(i + 1) % 4]
            # Horizontal girt and an X brace on each face of the bay.
            strut("%sgirt%d_%d" % (prefix, li, i), corner(*c0, y1), corner(*c1, y1), 0.05, parent, steel)
            strut("%sxa%d_%d" % (prefix, li, i), corner(*c0, y0), corner(*c1, y1), 0.035, parent, dark)
            strut("%sxb%d_%d" % (prefix, li, i), corner(*c1, y0), corner(*c0, y1), 0.035, parent, dark)
    # Peak above the arm.
    for i, (sx, sz) in enumerate(corners):
        strut("%speak%d" % (prefix, i), corner(sx, sz, arm_y), (0, h + 0.5, 0), 0.05, parent, steel)
    # Crossarm: two booms out to +-1.9 m with diagonal ties back to the peak.
    for sx in (-1, 1):
        for sz in (-1, 1):
            strut("%sarm%d%d" % (prefix, sx, sz), corner(sx, sz, arm_y), (sx * 1.9, arm_y, sz * 0.12), 0.07, parent, steel)
        strut("%stie%d" % (prefix, sx), (0, h + 0.4, 0), (sx * 1.85, arm_y + 0.05, 0), 0.04, parent, steel)
    # Insulator strings hanging from the arm tips (cables hang from y = arm_y - 0.75).
    ceramic = m.mat("insulator", CERAMIC, 0.3, 0.0)
    for sx in (-1, 1):
        for k in range(6):
            m.cyl("%sins%d_%d" % (prefix, sx, k), 0.085, 0.05, (sx * 1.8, arm_y - 0.12 - k * 0.11, 0), parent, ceramic, verts=10, bevel=0.0)
        m.cyl("%sclamp%d" % (prefix, sx), 0.03, 0.12, (sx * 1.8, arm_y - 0.78, 0), parent, dark, verts=6, bevel=0.0)


def _footings(prefix, parent, concrete, base=0.95):
    for i, (sx, sz) in enumerate([(-1, -1), (1, -1), (1, 1), (-1, 1)]):
        m.box("%sfoot%d" % (prefix, i), (0.55, 0.45, 0.55), (sx * base, 0.12, sz * base), parent, concrete, bevel=0.03)


def pylon():
    steel = m.mat("galvanised", GALV, 0.55, 0.7)
    dark = m.mat("galvanised_dark", GALV_DARK, 0.6, 0.6)
    concrete = m.mat("concrete", CONCRETE, 0.95)
    hazard = m.mat("hazard", HAZARD, 0.7)
    root = m.pivot("Pylon")
    _footings("", root, concrete)
    _tower("", root, steel, dark)
    # Anti-climb band and a danger plate at head height.
    for i, (sx, sz) in enumerate([(-1, -1), (1, -1), (1, 1), (-1, 1)]):
        r = 0.95 + (0.3 - 0.95) * (2.4 / 8.4)
        m.box("band%d" % i, (0.16, 0.5, 0.16), (sx * r, 2.4, sz * r), root, hazard, bevel=0.0)
    m.box("plate", (0.5, 0.35, 0.02), (0, 2.6, 0.78), root, hazard, bevel=0.0)
    join_by_parent()
    m.export("prop_pylon")


def pylon_down():
    """The same tower torn off its footings and lying on its side, crossarm buckled into the mud."""
    steel = m.mat("galvanised", GALV, 0.55, 0.7)
    dark = m.mat("galvanised_dark", GALV_DARK, 0.6, 0.6)
    concrete = m.mat("concrete", CONCRETE, 0.95)
    rust = m.mat("rust", RUST, 0.85, 0.3)
    root = m.pivot("PylonDown")
    _footings("", root, concrete)
    for i, (sx, sz) in enumerate([(-1, -1), (1, -1), (1, 1), (-1, 1)]):
        # Snapped leg stubs.
        strut("stub%d" % i, (sx * 0.95, 0.2, sz * 0.95), (sx * 0.9, 0.75 + 0.2 * i, sz * 0.9 + 0.1), 0.09, root, rust)
    fallen = m.pivot("Fallen", (0.0, 0.35, 1.0), root)
    # Tipped over towards +z, twisted a little; Blender axes: x, -z, y.
    fallen.rotation_euler = (math.radians(82), math.radians(-6), math.radians(9))
    _tower("f_", fallen, steel, dark)
    join_by_parent()
    m.export("prop_pylon_down")


def wellhead():
    """The geothermal tap the relay's line ran from: a cased bore with a valve tree, a step-up
    cabinet with cooling fins, and a short pole where the overhead line started."""
    concrete = m.mat("concrete", CONCRETE, 0.95)
    steel = m.mat("galvanised", GALV, 0.45, 0.75)
    dark = m.mat("dark_metal", m.DARK_METAL, 0.5, 0.55)
    oxide = m.mat("oxide", m.OXIDE, 0.6)
    rust = m.mat("rust", RUST, 0.85, 0.3)
    hazard = m.mat("hazard", HAZARD, 0.7)
    lamp = m.mat("lamp_dead", "3a2a18", 0.3, 0.0)
    root = m.pivot("Wellhead")
    m.box("pad", (3.6, 0.3, 3.0), (0, 0.15, 0), root, concrete, bevel=0.04)
    # Bore casing with flanges and the valve tree.
    m.cyl("casing", 0.32, 1.5, (-0.8, 1.0, 0), root, steel, verts=16)
    for y in (0.45, 1.05, 1.7):
        m.cyl("flange%d" % int(y * 10), 0.42, 0.08, (-0.8, y, 0), root, dark, verts=16, bevel=0.0)
    m.box("cross", (0.5, 0.45, 0.5), (-0.8, 1.95, 0), root, dark, bevel=0.03)
    m.cyl("bonnet", 0.16, 0.5, (-0.8, 2.4, 0), root, steel, verts=12)
    wheel = m.pivot("Wheel", (-0.8, 2.72, 0), root)
    m.cyl("rim", 0.3, 0.04, (0, 0, 0), wheel, oxide, verts=20, bevel=0.0)
    m.cyl("hub", 0.06, 0.1, (0, 0, 0), wheel, dark, verts=8, bevel=0.0)
    for k in range(3):
        m.box("spoke%d" % k, (0.56, 0.03, 0.04), (0, 0, 0), wheel, oxide, bevel=0.0, rot=(0, k * 60, 0))
    # Side outlet across to the cabinet.
    m.cyl("outlet", 0.12, 1.4, (-0.05, 1.95, 0), root, steel, axis="x", verts=12)
    m.cyl("outlet_flange", 0.18, 0.06, (0.55, 1.95, 0), root, dark, axis="x", verts=12, bevel=0.0)
    for k in range(5):
        m.box("rust%d" % k, (0.05, 0.35 + k * 0.08, 0.02), (-0.7 + k * 0.05, 1.2, 0.31), root, rust, bevel=0.0)
    # Step-up cabinet: body, cooling fins down both sides, hazard stripe, dead status lamp.
    m.box("cabinet", (1.2, 1.7, 1.0), (0.95, 1.15, 0), root, dark, bevel=0.03)
    m.box("cab_roof", (1.35, 0.08, 1.15), (0.95, 2.04, 0), root, steel, bevel=0.02)
    for side in (-1, 1):
        for k in range(7):
            m.box("fin%d_%d" % (side, k), (0.04, 1.3, 0.16), (0.5 + k * 0.15, 1.05, side * 0.58), root, steel, bevel=0.0)
    m.box("stripe", (1.22, 0.14, 1.02), (0.95, 0.42, 0), root, hazard, bevel=0.0)
    m.cyl("lamp", 0.07, 0.1, (1.35, 2.13, 0.3), root, lamp, verts=10, bevel=0.0)
    # Line pole: the first span left from here.
    m.cyl("pole", 0.09, 4.6, (1.35, 2.3 + 0.0, -0.75), root, steel, verts=8)
    m.box("pole_arm", (1.5, 0.08, 0.08), (1.35, 4.4, -0.75), root, steel, bevel=0.0)
    ceramic = m.mat("insulator", CERAMIC, 0.3, 0.0)
    for sx in (-1, 1):
        for k in range(3):
            m.cyl("pins%d_%d" % (sx, k), 0.06, 0.04, (1.35 + sx * 0.65, 4.5 + k * 0.07, -0.75), root, ceramic, verts=8, bevel=0.0)
    m.cyl("conduit", 0.06, 1.6, (1.35, 1.5, -0.55), root, dark, verts=8)
    join_by_parent()
    m.export("prop_wellhead")


def junction():
    """A cable junction box on a short post: where a breaker's feed meets the ground run."""
    dark = m.mat("dark_metal", m.DARK_METAL, 0.5, 0.55)
    steel = m.mat("galvanised", GALV, 0.45, 0.75)
    oxide = m.mat("oxide", m.OXIDE, 0.6)
    root = m.pivot("Junction")
    m.box("post", (0.12, 1.0, 0.12), (0, 0.5, 0), root, steel, bevel=0.0)
    m.box("box", (0.5, 0.55, 0.28), (0, 1.05, 0), root, dark, bevel=0.025)
    m.box("lid", (0.54, 0.06, 0.32), (0, 1.35, 0), root, oxide, bevel=0.01)
    for k in range(3):
        m.cyl("gland%d" % k, 0.035, 0.08, (-0.15 + k * 0.15, 0.75, 0), root, steel, verts=8, bevel=0.0)
    m.box("foot", (0.35, 0.08, 0.35), (0, 0.04, 0), root, steel, bevel=0.01)
    join_by_parent()
    m.export("prop_junction")


def cradle():
    """The relay's charging cradle. The cell sits at y 1.35 between two clamp arms hinged at
    their feet (pivots ClampL and ClampR, which swing outward about local z as it releases).
    Charging rings (material cradle_glow) circle the cell; a cable trunk runs out of the back."""
    dark = m.mat("dark_metal", m.DARK_METAL, 0.45, 0.6)
    steel = m.mat("galvanised", GALV, 0.4, 0.8)
    oxide = m.mat("oxide", m.OXIDE, 0.6)
    hazard = m.mat("hazard", HAZARD, 0.7)
    glow = m.mat("cradle_glow", m.AMBER, 0.2, 0.0, 3.0)
    root = m.pivot("Cradle")
    m.box("plinth", (1.5, 0.5, 1.1), (0, 0.25, 0), root, dark, bevel=0.04)
    for k in range(6):
        m.box("chevron%d" % k, (0.18, 0.1, 1.12), (-0.62 + k * 0.25, 0.42, 0), root, hazard if k % 2 == 0 else dark, bevel=0.0)
    m.box("seat", (0.62, 0.35, 0.5), (0, 0.67, 0), root, steel, bevel=0.03)
    # Charging rings round the cell, carried on two posts at the back.
    for i, y in enumerate((1.05, 1.35, 1.65)):
        ring = m.pivot("Ring%d" % i, (0, y, 0), root)
        me = bpy.data.meshes.new("ring%d" % i)
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=False, segments=24, radius=0.36)
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new("ring%d" % i, me)
        bpy.context.collection.objects.link(obj)
        obj.parent = ring
        obj.data.materials.append(glow)
        mod = obj.modifiers.new("skin", "SKIN")
        for v in obj.data.skin_vertices[0].data:
            v.radius = (0.025, 0.025)
    for sx in (-1, 1):
        m.box("ring_post%d" % sx, (0.08, 1.4, 0.08), (sx * 0.3, 1.3, 0.34), root, steel, bevel=0.0)
    m.box("back", (0.8, 1.6, 0.14), (0, 1.25, 0.48), root, dark, bevel=0.02)
    m.box("back_band", (0.82, 0.12, 0.16), (0, 1.9, 0.48), root, oxide, bevel=0.0)
    m.cyl("trunk", 0.09, 1.0, (0, 0.9, 1.0), root, dark, axis="z", verts=10)
    # Clamp arms: hinged at their feet beside the seat, jaws closing on the cell.
    for name, sx in (("ClampL", -1), ("ClampR", 1)):
        arm = m.pivot(name, (sx * 0.45, 0.55, 0), root)
        m.box(name + "_beam", (0.12, 1.15, 0.22), (0, 0.6, 0), arm, oxide, bevel=0.02)
        m.box(name + "_jaw", (0.2, 0.3, 0.3), (-sx * 0.08, 1.05, 0), arm, steel, bevel=0.02)
        m.cyl(name + "_hinge", 0.08, 0.3, (0, 0.0, 0), arm, steel, axis="z", verts=10)
        m.cyl(name + "_ram", 0.035, 0.6, (sx * 0.08, 0.3, -0.12), arm, steel, verts=8, bevel=0.0, rot=(0, 0, sx * 20))
    join_by_parent()
    m.export("prop_cradle")


def floodlight():
    """A site floodlight mast: pole, cage head with two lamps (material flood_lens), ballast box."""
    steel = m.mat("galvanised", GALV, 0.45, 0.75)
    dark = m.mat("dark_metal", m.DARK_METAL, 0.5, 0.55)
    lens = m.mat("flood_lens", "fff1d6", 0.2, 0.0, 0.0)
    root = m.pivot("Floodlight")
    m.box("base", (0.6, 0.15, 0.6), (0, 0.08, 0), root, steel, bevel=0.02)
    m.cyl("pole", 0.07, 4.2, (0, 2.2, 0), root, steel, verts=8)
    m.box("ballast", (0.3, 0.45, 0.2), (0, 1.2, 0.12), root, dark, bevel=0.02)
    m.box("bar", (1.1, 0.08, 0.08), (0, 4.25, 0), root, steel, bevel=0.0)
    for sx in (-1, 1):
        m.box("head%d" % sx, (0.42, 0.32, 0.22), (sx * 0.42, 4.15, -0.08), root, dark, bevel=0.02, rot=(-25, 0, 0))
        m.box("lens%d" % sx, (0.34, 0.24, 0.02), (sx * 0.42, 4.11, -0.2), root, lens, bevel=0.0, rot=(-25, 0, 0))
    join_by_parent()
    m.export("prop_floodlight")


BUILDERS = {
    "pylon": pylon,
    "pylon_down": pylon_down,
    "wellhead": wellhead,
    "junction": junction,
    "cradle": cradle,
    "floodlight": floodlight,
}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in args or list(BUILDERS):
        m.reset()
        BUILDERS[name]()


if __name__ == "__main__":
    main()
