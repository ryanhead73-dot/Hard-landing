"""Builds the expedition sites' prop kit as GLB: a shipping container, a concrete barrier, a
generator, pipe runs and torn hull shards for debris fields.

Run headless with Blender 4.2+ (or the `bpy` 4.2 module):
    python blender/build_props.py            # with `pip install bpy==4.2.0`
Optional arguments after `--` pick props by name.

Props use the same helpers and Godot-space coordinates as build_models.py. Each is modelled at
its natural size with its origin at the centre of its base; the game fits a prop to the box its
site already uses for collision (scripts/site_props.gd). Output: godot/assets/models/prop_<name>.glb.
"""

import math
import os
import random
import sys

import bpy
import bmesh  # noqa: E402 (needs bpy first)
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_models as m  # noqa: E402

RUST = "8a4a2a"
RUST_DARK = "5a2f1c"
CONCRETE = "8a8d86"
CONCRETE_DARK = "5f625d"
HAZARD = "e0a83a"


def extrude_profile(name, profile, length, parent, material, at=(0, 0, 0)):
    """A prism: `profile` is a closed list of (z, y) points, extruded along x by `length`."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    ends = []
    for x in (-length * 0.5, length * 0.5):
        ends.append([bm.verts.new(m.g(x, y, z)) for z, y in profile])
    n = len(profile)
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((ends[0][k], ends[0][k2], ends[1][k2], ends[1][k]))
    bm.faces.new(ends[0])
    bm.faces.new(list(reversed(ends[1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    return m._finish(obj, name, at, parent, material, 0.01, None)


def container():
    paint = m.mat("container_paint", RUST, 0.75, 0.2)
    dark = m.mat("container_frame", RUST_DARK, 0.6, 0.4)
    band = m.mat("oxide", m.OXIDE, 0.55)
    root = m.pivot("Container")
    L, H, W = 6.0, 2.6, 2.4
    # Body, a touch inside the frame so the ribs and rails stand proud.
    m.box("body", (L - 0.16, H - 0.16, W - 0.12), (0, H * 0.5, 0), root, paint, bevel=0.02)
    # Corrugation: vertical ribs down both long sides.
    count = 22
    for side in (-1, 1):
        for i in range(count):
            x = -L * 0.5 + 0.25 + i * (L - 0.5) / (count - 1)
            m.box("rib%d_%d" % (side, i), (0.11, H - 0.3, 0.05), (x, H * 0.5, side * (W * 0.5 - 0.04)), root, paint, bevel=0.01)
    # Frame: corner posts, top and bottom rails, corner castings.
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box("post%d%d" % (sx, sz), (0.16, H, 0.16), (sx * (L * 0.5 - 0.08), H * 0.5, sz * (W * 0.5 - 0.08)), root, dark)
            for y in (0.09, H - 0.09):
                m.box("casting%d%d%d" % (sx, sz, int(y)), (0.2, 0.18, 0.2), (sx * (L * 0.5 - 0.09), y, sz * (W * 0.5 - 0.09)), root, dark, bevel=0.02)
        for y in (0.06, H - 0.06):
            m.box("rail_end%d%d" % (sx, int(y)), (0.12, 0.12, W), (sx * (L * 0.5 - 0.06), y, 0), root, dark)
    for sz in (-1, 1):
        for y in (0.06, H - 0.06):
            m.box("rail%d%d" % (sz, int(y)), (L, 0.12, 0.12), (0, y, sz * (W * 0.5 - 0.06)), root, dark)
    # Doors at +x: two leaves, four locking bars, hinges.
    for i, z in enumerate((-0.6, 0.6)):
        m.box("door%d" % i, (0.04, H - 0.3, W * 0.5 - 0.1), (L * 0.5 - 0.02, H * 0.5, z), root, paint, bevel=0.01)
    for i, z in enumerate((-0.95, -0.3, 0.3, 0.95)):
        m.cyl("lockbar%d" % i, 0.025, H - 0.4, (L * 0.5 + 0.03, H * 0.5, z), root, dark, verts=8)
        m.box("handle%d" % i, (0.06, 0.04, 0.22), (L * 0.5 + 0.06, 1.1, z + 0.08), root, dark)
    # A faded oxide band and stencil block, for scale.
    m.box("band", (L - 0.6, 0.18, W - 0.06), (0, H - 0.5, 0), root, band, bevel=0.0)
    m.export("prop_container")


def barrier():
    concrete = m.mat("concrete", CONCRETE, 0.95)
    stripe = m.mat("hazard", HAZARD, 0.7)
    root = m.pivot("Barrier")
    # Jersey profile: wide foot, sloped face, narrow top.
    profile = [(-0.3, 0.0), (0.3, 0.0), (0.3, 0.08), (0.2, 0.3), (0.1, 1.1), (-0.1, 1.1), (-0.2, 0.3), (-0.3, 0.08)]
    extrude_profile("barrier", profile, 4.0, root, concrete)
    for x in (-1.4, 1.4):
        m.box("lift_slot%d" % int(x), (0.3, 0.1, 0.62), (x, 0.12, 0), root, m.mat("concrete_dark", CONCRETE_DARK, 0.95), bevel=0.0)
    for i, x in enumerate((-1.8, -0.6, 0.6, 1.8)):
        m.box("stripe%d" % i, (0.35, 0.12, 0.215), (x, 0.92, 0), root, stripe, bevel=0.0, rot=(0, 0, 0))
    m.export("prop_barrier")


def generator():
    body_m = m.mat("plate", m.CREAM_WORN, 0.55)
    dark = m.mat("dark_metal", m.DARK_METAL, 0.45, 0.6)
    band = m.mat("oxide", m.OXIDE, 0.55)
    root = m.pivot("Generator")
    m.box("skid", (2.4, 0.15, 1.3), (0, 0.075, 0), root, dark)
    m.pod("housing", (2.1, 1.1, 1.1), (0, 0.72, 0), root, body_m, n=3.4)
    m.pod("housing_band", (2.12, 0.14, 1.12), (0, 0.95, 0), root, band, n=4.0)
    for i in range(6):
        m.box("vent%d" % i, (0.06, 0.5, 0.02), (-0.6 + i * 0.12, 0.72, -0.56), root, dark, bevel=0.0)
    m.cyl("exhaust", 0.07, 0.6, (0.75, 1.45, 0.25), root, dark, verts=10)
    m.box("panel", (0.5, 0.4, 0.05), (0.55, 0.75, -0.56), root, dark)
    m.export("prop_generator")


def pipes():
    steel = m.mat("steel", m.STEEL, 0.4, 0.7)
    dark = m.mat("dark_metal", m.DARK_METAL, 0.45, 0.6)
    root = m.pivot("Pipes")
    for i, (z, r) in enumerate(((-0.35, 0.18), (0.1, 0.12), (0.45, 0.14))):
        m.cyl("pipe%d" % i, r, 4.0, (0, 0.5 + r, z), root, steel, axis="x", verts=16)
        for x in (-1.6, 0.0, 1.6):
            m.cyl("flange%d_%d" % (i, int(x * 10)), r + 0.04, 0.08, (x, 0.5 + r, z), root, dark, axis="x", verts=16)
    for x in (-1.4, 1.4):
        m.box("stand%d" % int(x), (0.12, 0.6, 1.2), (x, 0.3, 0.05), root, dark)
    m.export("prop_pipes")


def shard(name, seed, length, arc_deg, radius, band_at=None, ribbed=False):
    """A torn piece of curved hull skin: a strip of a cylinder with ragged ends, solidified."""
    rng = random.Random(seed)
    # Weathered and dirtied: lying in the wet basin, they shouldn't outshine the ship.
    hull = m.mat("debris_plate", "9e968a", 0.85)
    band = m.mat("debris_oxide", "8e4a28", 0.75)
    dark = m.mat("dark_metal", m.DARK_METAL, 0.45, 0.6)
    root = m.pivot(name.title())
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    cols = 10
    rows = 6
    arc = math.radians(arc_deg)
    grid = []
    for r in range(rows + 1):
        row = []
        for c in range(cols + 1):
            a = -arc * 0.5 + arc * c / cols
            # Ragged ends: each column's length is torn short by a random amount.
            tear = rng.uniform(0.0, 0.35) * length if r in (0, rows) else 0.0
            x = -length * 0.5 + length * r / rows
            if r == 0:
                x += tear
            elif r == rows:
                x -= tear
            y = math.cos(a) * radius - radius * math.cos(arc * 0.5) + 0.02
            z = math.sin(a) * radius
            row.append(bm.verts.new(m.g(x, y, z)))
        grid.append(row)
    for r in range(rows):
        for c in range(cols):
            bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name + "_skin", me)
    m._finish(obj, name + "_skin", (0, 0, 0), root, hull, 0.0, None)
    for p in obj.data.polygons:
        p.use_smooth = True
    mod = obj.modifiers.new("solid", "SOLIDIFY")
    mod.thickness = 0.06
    if band_at is not None:
        span = 2.0 * radius * math.sin(arc * 0.5)
        m.box(name + "_band", (0.35, 0.03, span * 0.9), (band_at, radius * (1 - math.cos(arc * 0.5)) + 0.06, 0), root, band, bevel=0.0)
    if ribbed:
        for x in (-length * 0.25, length * 0.25):
            m.box(name + "_rib%d" % int(x * 10), (0.12, 0.14, 2.0 * radius * math.sin(arc * 0.5)), (x, 0.08, 0), root, dark)
    m.export("prop_" + name)


def _wheel(name, at, parent, rot=None):
    rubber = m.mat("tyre", "1b1d1f", 0.9)
    hub = m.mat("plate", m.CREAM_WORN, 0.5)
    dark = m.mat("dark_metal", m.DARK_METAL, 0.45, 0.6)
    w = m.pivot(name, at, parent)
    if rot:
        w.rotation_euler = tuple(math.radians(a) for a in (rot[0], -rot[2], rot[1]))
    m.cyl(name + "_tyre", 0.45, 0.32, (0, 0, 0), w, rubber, axis="z", verts=28, bevel=0.04)
    m.cyl(name + "_hub", 0.24, 0.34, (0, 0, 0), w, hub, axis="z", verts=20)
    m.cyl(name + "_axle", 0.07, 0.5, (0, 0, 0), w, dark, axis="z", verts=10)
    for i in range(5):
        a = i * math.tau / 5
        m.cyl(name + "_bolt%d" % i, 0.025, 0.36, (math.cos(a) * 0.15, math.sin(a) * 0.15, 0), w, dark, axis="z", verts=6, bevel=0.0)
    return w


def gear():
    """A landing-gear leg as it hangs under Kestrel: origin at the mount, wheel centre 0.95 m down."""
    dark = m.mat("dark_metal", m.DARK_METAL, 0.45, 0.6)
    steel = m.mat("steel", m.STEEL, 0.25, 0.85)
    band = m.mat("oxide", m.OXIDE, 0.55)
    root = m.pivot("Gear")
    m.pod("mount", (0.8, 0.08, 0.8), (0, -0.22, 0), root, band, n=4.0)
    m.cyl("cylinder", 0.11, 0.42, (0, -0.45, 0), root, dark, verts=16)
    m.cyl("oleo", 0.07, 0.36, (0, -0.8, 0), root, steel, verts=16)
    m.cyl("collar", 0.13, 0.06, (0, -0.64, 0), root, dark, verts=16)
    # Torque links on the front of the oleo.
    m.box("link_upper", (0.05, 0.2, 0.05), (0, -0.6, -0.12), root, dark, rot=(25, 0, 0))
    m.box("link_lower", (0.05, 0.2, 0.05), (0, -0.78, -0.12), root, dark, rot=(-25, 0, 0))
    for z in (-0.2, 0.2):
        m.box("fork%d" % int(z * 10), (0.14, 0.32, 0.04), (0, -0.88, z), root, dark)
    _wheel("Wheel", (0, -0.95, 0), root)
    m.export("prop_gear")


def gear_broken():
    """The same leg after the crash: strut snapped and folded, wheel torn off beside it."""
    dark = m.mat("dark_metal", m.DARK_METAL, 0.45, 0.6)
    steel = m.mat("steel", m.STEEL, 0.25, 0.85)
    band = m.mat("oxide", m.OXIDE, 0.55)
    root = m.pivot("GearBroken")
    m.pod("mount", (0.8, 0.08, 0.8), (0, -0.22, 0), root, band, n=4.0)
    m.cyl("cylinder", 0.11, 0.3, (0, -0.38, 0), root, dark, verts=16)
    # Snapped oleo folded back under the hull.
    m.cyl("oleo", 0.07, 0.5, (0.22, -0.48, 0), root, steel, verts=16, rot=(0, 0, 70))
    m.box("link", (0.05, 0.2, 0.05), (0.1, -0.55, -0.12), root, dark, rot=(0, 0, 50))
    _wheel("Wheel", (0.7, -0.62, 0.25), root, rot=(80, 0, 10))
    m.export("prop_gear_broken")


BUILDERS = {
    "container": container,
    "barrier": barrier,
    "generator": generator,
    "pipes": pipes,
    "gear": gear,
    "gear_broken": gear_broken,
    "shard_0": lambda: shard("shard_0", 3, 2.6, 50, 2.2, band_at=0.4),
    "shard_1": lambda: shard("shard_1", 7, 1.6, 70, 1.4, ribbed=True),
    "shard_2": lambda: shard("shard_2", 11, 3.4, 35, 3.0, band_at=-0.8, ribbed=True),
}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in args or list(BUILDERS):
        m.reset()
        BUILDERS[name]()


if __name__ == "__main__":
    main()
