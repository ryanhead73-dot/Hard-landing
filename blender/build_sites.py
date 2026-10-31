"""Builds the large set pieces of the expedition sites as GLB: the quarry's mining crawler, the
freighter graveyard's hull ribs, fallen hull plates and engine section.

Run headless with Blender 4.2+ (or the `bpy` 4.2 module):
    python blender/build_sites.py            # with `pip install bpy==4.2.0`
Optional arguments after `--` pick models by name.

Unlike the prop kit (build_props.py), the crawler and the engine are modelled in their site's own
coordinates, so the game places them at the site origin and their walls line up with the
collision boxes the site scripts build. Ribs and hull plates have their origin at the centre of
their base. Each model is joined into one mesh per material to keep draw calls down.
Output: godot/assets/models/site_<name>.glb (hull plates: prop_hull_plate.glb).
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

PAINT = "b8913a"        # mining ochre, sun-faded
PAINT_DARK = "7d6127"
HAZARD = "e0b420"
BLACK = "1c1c1c"
GLASS = "1c2a30"
HULL = "5f645f"         # the Long Patience's grey-green
HULL_PLATE = "6b6f68"
RUST = "6a4a3a"
RUST_DARK = "4a2f22"


# --- Helpers -------------------------------------------------------------------------------

def prot(name, at, rot, parent=None):
    """A pivot with a rotation in Godot axes (degrees about x, y, z)."""
    p = m.pivot(name, at, parent)
    p.rotation_euler = tuple(math.radians(a) for a in (rot[0], -rot[2], rot[1]))
    return p


def strut(name, p0, p1, radius, parent, material, verts=10):
    """A cylinder from Godot point p0 to p1."""
    a, b = m.g(*p0), m.g(*p1)
    d = b - a
    obj = m.cyl(name, radius, d.length, (0, 0, 0), parent, material, verts=verts, bevel=0.0)
    obj.location = (a + b) * 0.5
    obj.rotation_euler = Vector((0, 0, 1)).rotation_difference(d).to_euler()
    return obj


def mesh_obj(name, bm, parent, material, smooth=False):
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = m._finish(bpy.data.objects.new(name, me), name, (0, 0, 0), parent, material, 0.0, None)
    for p in obj.data.polygons:
        p.use_smooth = smooth
    return obj


def sweep(name, path, profile, parent, material, tear=None, z=0.0):
    """Sweeps a closed cross-section along a path in the Godot XY plane (at depth z).
    profile: (n, dz) points, n along the path's left-hand normal. tear=(rng, amount) jitters the
    last ring along the path, a torn-off end."""
    bm = bmesh.new()
    rings = []
    count = len(path)
    for i, (px, py) in enumerate(path):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, count - 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(tx, ty) or 1.0
        tx, ty = tx / ln, ty / ln
        nx, ny = -ty, tx
        ring = []
        for n, dz in profile:
            off = tear[0].uniform(-tear[1], tear[1]) if tear and i == count - 1 else 0.0
            ring.append(bm.verts.new(m.g(px + nx * n + tx * off, py + ny * n + ty * off, z + dz)))
        rings.append(ring)
    k = len(profile)
    for i in range(count - 1):
        for j in range(k):
            j2 = (j + 1) % k
            bm.faces.new((rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    return mesh_obj(name, bm, parent, material)


def tube(name, r_out, r_in, z0, z1, centre, parent, material, segs=32, jag=None, arc=None):
    """A thick-walled tube along Godot z from z0 to z1 around centre (x, y). jag(k) shortens the
    z1 end at segment k (a torn lip). arc=(a0, a1) builds only part of the ring, in radians."""
    bm = bmesh.new()
    cx, cy = centre
    full = arc is None
    a0, a1 = arc if arc else (0.0, math.tau)
    n = segs if full else segs + 1
    verts = []
    for s in range(n):
        a = a0 + (a1 - a0) * s / segs
        ze = z1 - (jag(s) if jag else 0.0)
        ring = []
        for r, zz in ((r_out, z0), (r_out, ze), (r_in, ze), (r_in, z0)):
            ring.append(bm.verts.new(m.g(cx + math.cos(a) * r, cy + math.sin(a) * r, zz)))
        verts.append(ring)
    for s in range(segs):
        s2 = (s + 1) % n if full else s + 1
        for j in range(4):
            j2 = (j + 1) % 4
            bm.faces.new((verts[s][j], verts[s][j2], verts[s2][j2], verts[s2][j]))
    if not full:
        bm.faces.new(verts[0])
        bm.faces.new(list(reversed(verts[-1])))
    return mesh_obj(name, bm, parent, material)


def join_by_material():
    """Applies modifiers and joins every mesh into one object per material."""
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        return
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.convert(target="MESH")
    groups = {}
    for o in meshes:
        groups.setdefault(o.data.materials[0].name, []).append(o)
    for objs in groups.values():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()


def export(name):
    join_by_material()
    m.export(name)


# --- Quarry: the mining crawler -------------------------------------------------------------

def crawler():
    """In quarry site coordinates (scripts/quarry_crawler.gd): the hollow body spans x +-3.6,
    y 0.6..4.6, z -15..-1, with the bay floor at y 1.1 and the rear door 3 m wide."""
    rng = random.Random(5)
    paint = m.mat("crawler_paint", PAINT, 0.72, 0.05)
    worn = m.mat("crawler_worn", PAINT_DARK, 0.85)
    dark = m.mat("dark_metal", m.DARK_METAL, 0.5, 0.6)
    steel = m.mat("steel", m.STEEL, 0.35, 0.8)
    hazard = m.mat("hazard", HAZARD, 0.7)
    black = m.mat("hazard_black", BLACK, 0.8)
    glass = m.mat("cab_glass", GLASS, 0.15, 0.3, 0.25)
    rust = m.mat("rust_streak", RUST, 0.9)
    lamp = m.mat("lamp_lens", "ffe2b0", 0.2, 0.0, 0.6)
    root = m.pivot("Crawler")

    # Body walls as panels over a dark frame, so the seams read.
    z0, z1 = -15.0, -1.0
    seg = (z1 - z0) / 4
    for s in (-1, 1):
        m.box("wall_back%d" % s, (0.24, 3.9, 14.0), (s * 3.44, 2.6, -8.0), root, dark, bevel=0.0)
        for i in range(4):
            zc = z0 + seg * (i + 0.5)
            m.box("wall%d_%d" % (s, i), (0.3, 3.92, seg - 0.07), (s * 3.45, 2.6, zc), root, paint, bevel=0.03)
            # Stiffening swage on each panel.
            m.box("swage%d_%d" % (s, i), (0.05, 2.2, seg - 0.7), (s * 3.62, 2.75, zc), root, paint, bevel=0.02)
        for y in (1.25, 4.05):
            m.box("rub%d_%d" % (s, int(y * 10)), (0.1, 0.16, 14.2), (s * 3.66, y, -8.0), root, dark, bevel=0.02)
        for k in range(5):
            zr = rng.uniform(-14.0, -2.0)
            h = rng.uniform(0.6, 1.6)
            m.box("streak%d_%d" % (s, k), (0.02, h, rng.uniform(0.1, 0.25)), (s * 3.605, 4.0 - h * 0.5 - 0.1, zr), root, rust, bevel=0.0)
        # Grime band low on the walls.
        m.box("grime%d" % s, (0.02, 0.5, 13.9), (s * 3.602, 0.9, -8.0), root, worn, bevel=0.0)
    m.box("roof_back", (7.1, 0.24, 14.0), (0, 4.44, -8.0), root, dark, bevel=0.0)
    for i in range(4):
        m.box("roof%d" % i, (7.2, 0.3, seg - 0.07), (0, 4.45, z0 + seg * (i + 0.5)), root, paint, bevel=0.03)
    m.box("front", (7.2, 4.0, 0.4), (0, 2.6, -14.8), root, paint, bevel=0.03)
    # Rear wall either side of the door, lintel, frame and hazard posts.
    for s in (-1, 1):
        m.box("rear%d" % s, (2.1, 4.0, 0.4), (s * 2.55, 2.6, -1.2), root, paint, bevel=0.03)
        m.box("jamb%d" % s, (0.16, 3.25, 0.52), (s * 1.55, 2.2, -1.2), root, dark, bevel=0.02)
        for k in range(8):
            m.box("stripe%d_%d" % (s, k), (0.2, 0.38, 0.03), (s * 1.8, 0.82 + k * 0.4, -0.985), root,
                  hazard if (k + (s > 0)) % 2 == 0 else black, bevel=0.0)
    m.box("lintel", (3.0, 0.8, 0.4), (0, 4.2, -1.2), root, paint, bevel=0.03)
    m.box("header", (3.4, 0.16, 0.52), (0, 3.86, -1.2), root, dark, bevel=0.02)
    for k in range(7):
        m.box("lstripe%d" % k, (0.4, 0.28, 0.03), (-1.2 + k * 0.4, 4.25, -0.985), root, hazard if k % 2 == 0 else black, bevel=0.0)
    # Undercarriage between the tracks, so the body never floats.
    m.box("belly", (5.6, 0.62, 13.4), (0, 0.3, -8.1), root, dark, bevel=0.03)

    # The bay: dark lining, frames, and the crane rail the strut pack hangs from.
    for s in (-1, 1):
        m.box("lining%d" % s, (0.04, 3.12, 13.1), (s * 3.28, 2.7, -8.0), root, dark, bevel=0.0)
    m.box("ceiling", (6.5, 0.04, 13.1), (0, 4.28, -8.0), root, dark, bevel=0.0)
    m.box("lining_front", (6.5, 3.12, 0.04), (0, 2.7, -14.58), root, dark, bevel=0.0)
    for s in (-1, 1):
        m.box("lining_rear%d" % s, (1.75, 3.12, 0.04), (s * 2.4, 2.7, -1.42), root, dark, bevel=0.0)
    for k in range(6):
        z = -13.8 + k * 2.3
        for s in (-1, 1):
            m.box("frame%d_%d" % (s, k), (0.14, 3.1, 0.22), (s * 3.19, 2.7, z), root, steel, bevel=0.01)
        m.box("beam%d" % k, (6.4, 0.2, 0.22), (0, 4.15, z), root, steel, bevel=0.01)
    m.box("rail", (0.3, 0.24, 11.6), (0, 3.93, -8.4), root, dark, bevel=0.02)
    m.box("trolley", (0.8, 0.34, 0.7), (0, 3.68, -13.4), root, hazard, bevel=0.03)
    for x in (-0.2, 0.2):
        m.cyl("cable%d" % int(x * 10), 0.018, 0.5, (x, 3.27, -13.4), root, steel, verts=6, bevel=0.0)

    # Tracks: frame, road wheels, idler and sprocket, top rollers, a loop of shoes, fender.
    for s in (-1, 1):
        x = s * 4.4
        m.box("tframe%d" % s, (0.8, 0.85, 12.8), (x, 0.8, -8.0), root, dark, bevel=0.03)
        for k in range(6):
            m.cyl("road%d_%d" % (s, k), 0.42, 1.0, (x, 0.5, -13.3 + k * 2.12), root, steel, axis="x", verts=18)
            m.cyl("roadhub%d_%d" % (s, k), 0.2, 1.06, (x, 0.5, -13.3 + k * 2.12), root, dark, axis="x", verts=10)
        for zc, r, name in ((-14.75, 0.66, "idler"), (-1.25, 0.66, "sprocket")):
            m.cyl("%s%d" % (name, s), r, 1.08, (x, 0.8, zc), root, steel, axis="x", verts=20)
            m.cyl("%shub%d" % (name, s), 0.3, 1.14, (x, 0.8, zc), root, dark, axis="x", verts=12)
        for k in range(3):
            m.cyl("roller%d_%d" % (s, k), 0.14, 0.7, (x, 1.32, -11.0 + k * 5.0), root, dark, axis="x", verts=10)
        # Shoes round the loop: two straight runs and two half turns of radius 0.74.
        r, yc = 0.74, 0.79
        za, zb = -14.75, -1.25
        pitch = 0.42
        shoes = []
        n_run = int((zb - za) / pitch)
        for k in range(n_run + 1):
            z = za + k * (zb - za) / n_run
            shoes.append((z, yc + r, 0.0))
            shoes.append((z, yc - r, 180.0))
        for zc, sign in ((za, -1), (zb, 1)):
            for k in range(1, 6):
                a = math.pi * k / 6
                shoes.append((zc + sign * math.sin(a) * r, yc + math.cos(a) * r, sign * math.degrees(a)))
        for k, (z, y, ang) in enumerate(shoes):
            shoe = prot("shoe%d_%d" % (s, k), (x, y, z), (ang, 0, 0), root)
            m.box("plate%d_%d" % (s, k), (1.5, 0.1, 0.36), (0, 0, 0), shoe, dark, bevel=0.015)
            m.box("grouser%d_%d" % (s, k), (1.5, 0.05, 0.07), (0, 0.07, 0), shoe, steel, bevel=0.0)
        m.box("fender%d" % s, (1.8, 0.1, 14.6), (x, 1.68, -8.0), root, paint, bevel=0.02)
        m.box("skirt%d" % s, (0.06, 0.42, 14.6), (s * 5.27, 1.46, -8.0), root, paint, bevel=0.01)
    # Side ladder up to the roof.
    for z in (-10.25, -9.75):
        m.box("ladrail%d" % int(z * 10), (0.06, 3.0, 0.06), (3.78, 3.15, z), root, steel, bevel=0.0)
    for k in range(8):
        m.box("rung%d" % k, (0.04, 0.04, 0.5), (3.78, 1.9 + k * 0.36, -10.0), root, steel, bevel=0.0)

    # Roof: walkway, handrails, intake, exhaust stacks.
    m.box("walkway", (1.2, 0.05, 11.0), (-2.3, 4.63, -6.0), root, dark, bevel=0.0)
    for k in range(6):
        z = -11.0 + k * 2.0
        m.box("hrpost%d" % k, (0.05, 0.9, 0.05), (-3.35, 5.05, z), root, hazard, bevel=0.0)
    m.box("hrail", (0.05, 0.05, 10.2), (-3.35, 5.5, -6.0), root, hazard, bevel=0.0)
    m.box("intake", (1.8, 0.8, 2.4), (1.6, 5.0, -6.5), root, paint, bevel=0.04)
    for k in range(6):
        m.box("slat%d" % k, (1.6, 0.05, 0.08), (1.6, 5.42, -7.4 + k * 0.36), root, dark, bevel=0.0)
    for k, z in enumerate((-3.0, -4.0)):
        m.cyl("stack%d" % k, 0.2, 2.4, (2.6, 5.8, z), root, dark, verts=14)
        m.cyl("stackcap%d" % k, 0.26, 0.12, (2.6, 7.02, z), root, dark, verts=14)
        m.cyl("soot%d" % k, 0.205, 0.5, (2.6, 6.7, z), root, m.mat("soot", "121212", 0.95), verts=14, bevel=0.0)

    # Cab over the front of the body: lower shell, glass band with pillars, roof and lamp bar.
    m.box("cab_lower", (6.0, 1.6, 4.0), (0, 5.4, -13.0), root, paint, bevel=0.04)
    m.box("cab_glass", (5.8, 1.0, 3.7), (0, 6.7, -13.05), root, glass, bevel=0.0, taper=(1.0, 0.94))
    for x in (-2.92, -1.0, 1.0, 2.92):
        m.box("pillar_f%d" % int(x * 10), (0.14, 1.02, 0.14), (x, 6.7, -14.88), root, dark, bevel=0.0)
    for z in (-14.8, -13.0, -11.3):
        for s in (-1, 1):
            m.box("pillar_s%d_%d" % (s, int(z)), (0.14, 1.02, 0.14), (s * 2.92, 6.7, z), root, dark, bevel=0.0)
    m.box("cab_roof", (6.2, 0.3, 4.2), (0, 7.35, -13.0), root, paint, bevel=0.04)
    m.box("visor", (6.3, 0.08, 0.5), (0, 7.22, -15.25), root, dark, bevel=0.0)
    m.box("lampbar", (4.0, 0.2, 0.25), (0, 7.62, -14.6), root, dark, bevel=0.02)
    for k in range(4):
        m.cyl("lamp%d" % k, 0.15, 0.12, (-1.5 + k, 7.62, -14.8), root, lamp, axis="z", verts=14, bevel=0.0)
    m.box("cab_stripe", (6.02, 0.2, 4.02), (0, 4.75, -13.0), root, black, bevel=0.0)

    # Drill boom: a lattice arm angled down from the front, a ram, the cutter head on the ground.
    boom = prot("Boom", (0, 3.0, -19.0), (math.degrees(-0.25), 0, 0), root)
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.box("chord%d%d" % (sx, sy), (0.16, 0.16, 9.0), (sx * 0.4, sy * 0.4, 0), boom, paint, bevel=0.02)
    for k in range(9):
        z = -4.0 + k
        for sx in (-1, 1):
            m.box("brace_v%d_%d" % (k, sx), (0.08, 0.95, 0.08), (sx * 0.4, 0, z), boom, paint, bevel=0.0, rot=(35 if k % 2 else -35, 0, 0))
        for sy in (-1, 1):
            m.box("brace_h%d_%d" % (k, sy), (0.95, 0.08, 0.08), (0, sy * 0.4, z), boom, paint, bevel=0.0, rot=(0, 35 if k % 2 else -35, 0))
    m.box("boom_root", (1.2, 1.2, 0.6), (0, 0, 4.4), boom, dark, bevel=0.03)
    head = m.pivot("Head", (0, 0, -5.0), boom)
    m.cyl("drum", 0.85, 1.4, (0, 0, 0), head, steel, axis="z", verts=20)
    m.cyl("nose", 0.85, 0.8, (0, 0, -1.1), head, steel, axis="z", verts=20, radius2=0.25)
    m.cyl("gearbox", 0.6, 0.6, (0, 0, 0.95), head, dark, axis="z", verts=14)
    for ring in range(5):
        zt = 0.5 - ring * 0.42
        rad = 0.85 if ring < 3 else 0.85 - (ring - 2) * 0.22
        for k in range(8):
            a = math.tau * (k + ring * 0.5) / 8
            m.box("pick%d_%d" % (ring, k), (0.1, 0.32, 0.1), (math.cos(a) * (rad + 0.1), math.sin(a) * (rad + 0.1), zt),
                  head, dark, bevel=0.0, taper=None, rot=(0, 0, math.degrees(a) - 90))
    # Hydraulic ram from the body's nose to the boom's underside.
    strut("ram_cyl", (0, 1.4, -15.05), (0, 2.6, -17.8), 0.16, root, dark, verts=12)
    strut("ram_rod", (0, 2.4, -17.4), (0, 3.25, -19.6), 0.08, root, steel, verts=10)
    for s in (-1, 1):
        m.box("lug%d" % s, (0.1, 0.5, 0.5), (s * 0.24, 1.4, -15.1), root, dark, bevel=0.0)
    export("site_crawler")


# --- Freighter graveyard --------------------------------------------------------------------

R_RIB, H_RIB = 10.5, 9.4
I_BEAM = [(-0.45, -0.35), (-0.45, 0.35), (-0.33, 0.35), (-0.33, 0.1), (0.33, 0.1), (0.33, 0.35),
          (0.45, 0.35), (0.45, -0.35), (0.33, -0.35), (0.33, -0.1), (-0.33, -0.1), (-0.33, -0.35)]


def _arch(a0, a1, steps=28):
    """Points on the rib's centre line, a superellipse arch from the +x foot (a = 0) over the
    top (a = pi/2) to the -x foot (a = pi)."""
    out = []
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        c, s = math.cos(a), math.sin(a)
        x = R_RIB * math.copysign(abs(c) ** (2.0 / 3.0), c)
        y = H_RIB * abs(s) ** (2.0 / 3.0)
        out.append((x, y))
    return out


def _skin(name, a0, a1, rng, parent, material, half_width=1.5):
    plate = [(-0.47, -half_width), (-0.47, half_width), (-0.56, half_width), (-0.56, -half_width)]
    return sweep(name, _arch(a0, a1, 8), plate, parent, material, tear=(rng, 0.35))


def rib(broken=False):
    """One hull rib of the Long Patience standing out of the ground: an I-beam arch with its
    feet at x = +-10.5 and its crown at 9.4 m. The broken one has lost its crown."""
    rng = random.Random(21 if broken else 13)
    hull = m.mat("hull", HULL, 0.75, 0.35)
    plate = m.mat("hull_plate", HULL_PLATE, 0.8, 0.2)
    rust = m.mat("rust", RUST, 0.9, 0.1)
    rust_dark = m.mat("rust_dark", RUST_DARK, 0.95)
    band = m.mat("oxide", m.OXIDE, 0.6)
    root = m.pivot("RibBroken" if broken else "Rib")
    if broken:
        sweep("rib_r", _arch(0.0, math.pi * 0.56, 18), I_BEAM, root, hull, tear=(rng, 0.4))
        sweep("rib_l", _arch(math.pi * 0.8, math.pi, 8)[::-1], [(-n, z) for n, z in I_BEAM], root, rust, tear=(rng, 0.4))
        _skin("skin0", 0.12, 0.36, rng, root, plate)
        _skin("skin1", 0.38, 0.5, rng, root, rust)
    else:
        sweep("rib", _arch(0.0, math.pi), I_BEAM, root, hull)
        _skin("skin0", 0.1, 0.32, rng, root, plate)
        _skin("skin1", 0.62, 0.78, rng, root, rust)
        _skin("skin2", 1.1, 1.35, rng, root, plate, half_width=1.2)
        _skin("skin3", 2.3, 2.62, rng, root, plate)
        sweep("band", _arch(1.45, 1.69, 4), [(-0.46, -0.37), (-0.46, 0.37), (-0.52, 0.37), (-0.52, -0.37)], root, band)
    # Gussets and lightening holes read as dark plates on the web every couple of metres.
    path = _arch(0.0, math.pi * (0.56 if broken else 1.0), 14)
    for i in range(1, len(path) - 1, 2):
        x, y = path[i]
        m.box("gusset%d" % i, (0.5, 0.5, 0.24), (x, y, 0), root, m.mat("dark_metal", m.DARK_METAL, 0.6, 0.5), bevel=0.0,
              rot=(0, 0, math.degrees(math.atan2(path[i + 1][1] - path[i - 1][1], path[i + 1][0] - path[i - 1][0]))))
    # Feet: the rib sunk in a pad of rubble.
    for s in (-1, 1):
        m.box("foot%d" % s, (1.6, 0.4, 1.3), (s * 10.5, 0.1, 0), root, rust_dark, bevel=0.05, rot=(0, rng.uniform(-15, 15), 0))
        for k in range(3):
            m.box("rubble%d_%d" % (s, k), (rng.uniform(0.3, 0.6), 0.3, rng.uniform(0.3, 0.6)),
                  (s * 10.5 + rng.uniform(-1.1, 1.1), 0.08, rng.uniform(-1.0, 1.0)), root, m.mat("basalt", m.BASALT, 0.9),
                  bevel=0.04, rot=(rng.uniform(-20, 20), rng.uniform(0, 90), rng.uniform(-20, 20)))
    export("site_rib_broken" if broken else "site_rib")


def hull_plate():
    """A fallen section of hull skin standing on edge: 8 m long, 4 m tall, 0.5 m deep, bowed,
    torn along the top, with frames and stringers behind. Fitted to its collision box in game."""
    rng = random.Random(9)
    skin = m.mat("hull_plate", HULL_PLATE, 0.8, 0.2)
    rust = m.mat("rust", RUST, 0.9, 0.1)
    rust_dark = m.mat("rust_dark", RUST_DARK, 0.95)
    band = m.mat("oxide", m.OXIDE, 0.6)
    root = m.pivot("HullPlate")
    L, H = 8.0, 4.0
    cols, rows = 16, 6
    tops = [H - rng.uniform(0.0, 0.7) for _ in range(cols + 1)]
    tops[0] = H - 0.9
    bm = bmesh.new()
    grid = []
    for r in range(rows + 1):
        row = []
        for c in range(cols + 1):
            u = c / cols
            x = -L * 0.5 + L * u
            y = tops[c] * r / rows
            z = 0.12 * math.sin(math.pi * u)  # bowed outward (+z)
            row.append(bm.verts.new(m.g(x, y, z)))
        grid.append(row)
    for r in range(rows):
        for c in range(cols):
            bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
    obj = mesh_obj("skin", bm, root, skin, smooth=True)
    mod = obj.modifiers.new("solid", "SOLIDIFY")
    mod.thickness = 0.08
    # Rust tide-mark low down and a faded oxide band.
    m.box("tide", (L * 0.98, 0.6, 0.02), (0, 0.3, 0.16), root, rust, bevel=0.0)
    m.box("band", (1.0, 2.6, 0.02), (1.4, 1.5, 0.17), root, band, bevel=0.0)
    for k in range(4):
        x = rng.uniform(-3.5, 3.5)
        m.box("streak%d" % k, (rng.uniform(0.12, 0.3), rng.uniform(0.8, 2.0), 0.02), (x, 2.2, 0.155), root, rust_dark, bevel=0.0)
    # Frames and stringers behind (-z).
    for k in range(6):
        x = -L * 0.5 + 0.6 + k * (L - 1.2) / 5
        c = int(round((x + L * 0.5) / L * cols))
        h = tops[c] - 0.1
        m.box("frame%d" % k, (0.12, h, 0.3), (x, h * 0.5, -0.15), root, rust_dark, bevel=0.01)
    for y in (1.2, 2.5):
        m.box("stringer%d" % int(y * 10), (L - 0.4, 0.12, 0.2), (0, y, -0.12), root, rust, bevel=0.01)
    export("prop_hull_plate")


def engine():
    """In graveyard site coordinates (scripts/freighter_graveyard.gd): the engine section lies
    along z from -30 (closed bulkhead) to -18 (open, torn lip), radius 4.2 round (0, 4.2)."""
    rng = random.Random(4)
    hull = m.mat("hull", HULL, 0.75, 0.35)
    plate = m.mat("hull_plate", HULL_PLATE, 0.8, 0.2)
    dark = m.mat("dark_metal", m.DARK_METAL, 0.6, 0.5)
    rust = m.mat("rust", RUST, 0.9, 0.1)
    rust_dark = m.mat("rust_dark", RUST_DARK, 0.95)
    band = m.mat("oxide", m.OXIDE, 0.6)
    root = m.pivot("Engine")
    c = (0.0, 4.2)
    segs = 40
    lip = [0.0 if (k % 5) else rng.uniform(0.2, 0.9) for k in range(segs + 1)]
    lip = [max(lip[k], rng.uniform(0.0, 0.35)) for k in range(segs + 1)]
    lip[-1] = lip[0]
    tube("shell", 4.2, 3.8, -30.0, -18.0, c, root, hull, segs=segs, jag=lambda k: lip[k % segs])
    m.cyl("bulkhead", 3.85, 0.4, (0, 4.2, -29.8), root, dark, axis="z", verts=40)
    # Outer stiffening rings, one with a section rusted through, and longitudinal stringers.
    for k, z in enumerate((-29.0, -26.6, -24.2, -21.8, -19.4)):
        mat = rust if k == 3 else hull
        tube("ring%d" % k, 4.42, 4.18, z - 0.18, z + 0.18, c, root, mat, segs=40)
    for k in range(14):
        a = math.tau * (k + 0.5) / 14
        if math.sin(a) < -0.75:
            continue
        L = rng.uniform(7.5, 11.8)
        m.box("stringer%d" % k, (0.16, 0.16, L), (math.cos(a) * 4.26, 4.2 + math.sin(a) * 4.26, -30.0 + L * 0.5), root,
              plate, bevel=0.0, rot=(0, 0, math.degrees(a)))
    tube("band", 4.23, 4.19, -25.0, -23.2, c, root, band, segs=40, arc=(0.25, 2.9))
    for k in range(5):
        a = rng.uniform(0.3, 2.8)
        tube("streak%d" % k, 4.215, 4.19, -29.0 + k * 2.2, -28.7 + k * 2.2 + rng.uniform(0.0, 0.3), c, root, rust_dark,
             segs=4, arc=(a, a + 0.2))
    # Nozzle petals round the open end, flaring out; the low ones are gone into the ground.
    for k in range(12):
        a = math.tau * k / 12 + 0.13
        if math.sin(a) < -0.35 or k in (2, 7):
            continue
        flare = 22 + rng.uniform(-6, 10)
        p = prot("petal%d" % k, (math.cos(a) * 4.0, 4.2 + math.sin(a) * 4.0, -18.0), (0, 0, math.degrees(a) - 90), root)
        tilt = prot("petal_tilt%d" % k, (0, 0, 0), (-flare, 0, 0), p)
        m.box("petal_plate%d" % k, (2.0, 0.12, 1.8), (0, 0, 0.85), tilt, dark if k % 3 else rust, bevel=0.02)
    # Inside: frames under the floor line, conduits along the walls, a coil cradle at the back.
    for k, z in enumerate((-28.6, -26.0, -23.4, -20.8)):
        tube("iframe%d" % k, 3.8, 3.6, z - 0.12, z + 0.12, c, root, rust_dark, segs=40)
    for s in (-1, 1):
        a = math.pi * 0.5 + s * 1.0
        for k in range(2):
            rr = 3.45 - k * 0.32
            m.cyl("conduit%d_%d" % (s, k), 0.13, 11.4, (math.cos(a + s * k * 0.09) * rr, 4.2 + math.sin(a + s * k * 0.09) * rr, -24.0),
                  root, dark if k else plate, axis="z", verts=10, bevel=0.0)
    for s in (-1, 1):
        m.box("cradle%d" % s, (0.3, 1.4, 1.6), (s * 1.1, 1.3, -26.5), root, dark, bevel=0.03)
    m.box("cradle_top", (2.5, 0.25, 1.0), (0, 2.75, -26.5), root, dark, bevel=0.03)
    m.cyl("housing", 1.15, 0.2, (0, 1.95, -27.4), root, rust, axis="z", verts=24)
    export("site_engine")


# --- Hot springs: the coolant hauler --------------------------------------------------------

def se_prism(name, hx, hy, cy, z0, z1, parent, material, n=4.0, segs=40, front_scale=1.0):
    """A closed prism along Godot z whose section is a superellipse of half-sizes hx, hy round
    (0, cy). front_scale shrinks the z0 end, for a tapered nose."""
    bm = bmesh.new()
    rings = []
    for z, k in ((z0, front_scale), (z1, 1.0)):
        ring = []
        for i in range(segs):
            a = math.tau * i / segs
            c, s_ = math.cos(a), math.sin(a)
            x = hx * k * math.copysign(abs(c) ** (2.0 / n), c)
            y = cy + hy * k * math.copysign(abs(s_) ** (2.0 / n), s_)
            ring.append(bm.verts.new(m.g(x, y, z)))
        rings.append(ring)
    for i in range(segs):
        i2 = (i + 1) % segs
        bm.faces.new((rings[0][i], rings[0][i2], rings[1][i2], rings[1][i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[1])))
    return mesh_obj(name, bm, parent, material)


def carve(obj, cutters):
    """Boolean-subtracts each cutter from obj and deletes the cutters."""
    for k, cut in enumerate(cutters):
        if cut.name.startswith("cutter"):
            # Faces cut by a plain cutter take the carved object's own material.
            cut.data.materials.clear()
            cut.data.materials.append(obj.data.materials[0])
        mod = obj.modifiers.new("cut%d" % k, "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.material_mode = "TRANSFER"
        mod.object = cut
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for cut in cutters:
        bpy.data.objects.remove(cut, do_unlink=True)
    for p in obj.data.polygons:
        p.use_smooth = False


def _cutter(size, at):
    return m.box("cutter", size, at, None, m.mat("cutter", "ff00ff"), bevel=0.0)


def hauler():
    """In hot-springs site coordinates (scripts/hauler_wreck.gd): the hold is a 6 x 4.5 x 20 m
    shell round (0, 2, -6), walls 0.3 thick, with the cargo door open at +z, a breach in the
    starboard side and the nose torn off the front. Tail fin and engine pods on top."""
    rng = random.Random(8)
    paint = m.mat("hauler_paint", "5d6b73", 0.7, 0.15)
    paint_dark = m.mat("hauler_dark", "3f4a50", 0.8, 0.1)
    inner = m.mat("hauler_inner", "3a4247", 0.85)
    dark = m.mat("dark_metal", m.DARK_METAL, 0.55, 0.55)
    steel = m.mat("steel", m.STEEL, 0.35, 0.8)
    hazard = m.mat("hazard", HAZARD, 0.7)
    black = m.mat("hazard_black", BLACK, 0.8)
    rust = m.mat("rust", RUST, 0.9, 0.1)
    frost = m.mat("frost", "cfe6ea", 0.6)
    root = m.pivot("Hauler")
    shell = se_prism("shell", 3.0, 2.25, 2.0, -16.0, 4.0, root, paint)
    hole = se_prism("hole", 2.7, 1.95, 1.95, -15.7, 3.7, None, inner)
    carve(shell, [hole, _cutter((4.6, 3.6, 1.0), (0, 1.6, 4.0)), _cutter((1.0, 2.4, 3.0), (3.0, 1.4, -10.5)),
                  _cutter((5.0, 2.0, 1.0), (0, 3.3, -16.0))])
    # Torn edges round the breach and the nose: bent-out skin flaps.
    for k in range(4):
        m.box("flap%d" % k, (0.06, rng.uniform(0.4, 0.8), rng.uniform(0.5, 0.9)), (3.12, 0.6 + k * 0.55, -12.15 + (k % 2) * 3.3),
              root, paint, bevel=0.0, rot=(rng.uniform(-20, 20), rng.uniform(25, 50) * (1 if k % 2 else -1), 0))
    for k in range(5):
        m.box("nflap%d" % k, (rng.uniform(0.6, 1.0), 0.06, rng.uniform(0.4, 0.7)), (-2.0 + k, 4.3, -16.1),
              root, paint, bevel=0.0, rot=(rng.uniform(15, 40), rng.uniform(-15, 15), 0))
    # Outer frames every 2 m and a spine strake along the roof.
    for k in range(10):
        z = -15.0 + k * 2.0
        ring = se_prism("frame%d" % k, 3.06, 2.31, 2.0, z - 0.1, z + 0.1, root, paint_dark)
        hole = se_prism("fhole", 2.98, 2.23, 2.0, z - 0.2, z + 0.2, None, paint_dark)
        cuts = [hole]
        if -12.2 < z < -8.8:
            cuts.append(_cutter((1.2, 2.5, 3.2), (3.0, 1.4, -10.5)))
        carve(ring, cuts)
    m.box("strake", (0.5, 0.12, 19.6), (0, 4.28, -6.0), root, paint_dark, bevel=0.02)
    # Hazard band high along both sides, rust tide low down where the spring water sits.
    for side in (-1, 1):
        for i in range(12):
            z = 3.4 - i * 0.9
            if side > 0 and -12.3 < z < -8.6:
                continue
            m.box("hz%d_%d" % (side, i), (0.04, 0.4, 0.88), (side * 3.0, 3.55, z), root, hazard if i % 2 == 0 else black, bevel=0.0)
        m.box("tide%d" % side, (0.03, 0.5, 19.2), (side * 2.99, 0.25, -6.0), root, rust, bevel=0.0)
        m.box("frost%d" % side, (0.03, 0.18, 6.0), (side * 3.0, 2.4, -1.0), root, frost, bevel=0.0)
    # Inside: frames and a cable tray along the ceiling.
    for k in range(9):
        z = -14.0 + k * 2.0
        ring = se_prism("iframe%d" % k, 2.72, 1.97, 1.95, z - 0.08, z + 0.08, root, dark)
        hole = se_prism("ihole", 2.55, 1.8, 1.95, z - 0.2, z + 0.2, None, dark)
        cuts = [hole, _cutter((6.0, 0.6, 1.0), (0, -0.1, z))]
        if -12.2 < z < -8.8:
            cuts.append(_cutter((1.2, 2.5, 3.2), (3.0, 1.4, -10.5)))
        carve(ring, cuts)
    m.box("tray", (0.6, 0.08, 18.0), (0, 3.7, -6.0), root, dark, bevel=0.0)
    # Cargo door ramp lying open on the ground behind the hold.
    m.box("door", (4.4, 0.16, 3.2), (0, 0.12, 5.7), root, paint_dark, bevel=0.03, rot=(-4, 0, 0))
    for k in range(6):
        m.box("dstripe%d" % k, (4.2, 0.02, 0.24), (0, 0.22, 4.6 + k * 0.45), root, hazard if k % 2 == 0 else black, bevel=0.0, rot=(-4, 0, 0))
    for s in (-1, 1):
        m.cyl("hinge%d" % s, 0.12, 0.6, (s * 1.8, 0.1, 4.1), root, dark, axis="x", verts=10)
    # Tail fin (leaning, as in hauler_wreck.gd) with a strobe housing on top.
    fin = prot("Fin", (0, 6.9, 1.6), (0, 0, math.degrees(0.12)), root)
    m.box("fin", (0.4, 5.5, 3.5), (0, 0, 0), fin, paint, bevel=0.04, taper=(1.0, 0.55))
    m.box("fin_edge", (0.44, 5.4, 0.3), (0, 0, 1.6), fin, paint_dark, bevel=0.02)
    m.box("fin_band", (0.42, 0.5, 3.0), (0, 1.2, 0.1), fin, m.mat("oxide", m.OXIDE, 0.6), bevel=0.0)
    m.cyl("strobe_mount", 0.18, 0.3, (0, 2.85, 0.6), fin, dark, verts=10)
    # Engine pods either side of the fin.
    for s in (-1, 1):
        x = s * 2.4
        m.box("pylon%d" % s, (0.3, 0.6, 2.4), (x, 4.45, 1.0), root, paint_dark, bevel=0.03)
        m.cyl("pod%d" % s, 0.65, 4.2, (x, 5.2, 1.0), root, paint, axis="z", verts=20)
        m.cyl("intake%d" % s, 0.7, 0.3, (x, 5.2, -1.1), root, dark, axis="z", verts=20)
        m.cyl("fan%d" % s, 0.5, 0.32, (x, 5.2, -1.1), root, m.mat("soot", "121212", 0.95), axis="z", verts=20)
        m.cyl("nozzle%d" % s, 0.55, 0.6, (x, 5.2, 3.3), root, dark, axis="z", verts=20, radius2=0.42)
        m.box("pod_band%d" % s, (1.34, 0.2, 0.3), (x, 5.2, 0.2), root, hazard, bevel=0.0)
    # Landing skids, half sunk.
    for s in (-1, 1):
        m.box("skid%d" % s, (0.3, 0.25, 16.0), (s * 2.6, -0.05, -6.0), root, dark, bevel=0.03)
    export("site_hauler")


def hauler_nose():
    """The hauler's torn-off cockpit, modelled at its natural size (5.2 x 3.6 x 5 m) with its
    origin at its centre; the game fits it to the tilted box it uses for collision."""
    rng = random.Random(12)
    paint = m.mat("hauler_paint", "5d6b73", 0.7, 0.15)
    paint_dark = m.mat("hauler_dark", "3f4a50", 0.8, 0.1)
    glass = m.mat("cab_glass", GLASS, 0.15, 0.3, 0.2)
    dark = m.mat("dark_metal", m.DARK_METAL, 0.55, 0.55)
    root = m.pivot("HaulerNose")
    shell = se_prism("nose", 2.6, 1.8, 0.0, -2.5, 2.5, root, paint, front_scale=0.55)
    hole = se_prism("nhole", 2.3, 1.5, 0.0, -1.9, 2.8, None, dark, front_scale=0.6)
    carve(shell, [hole])
    m.box("glass", (3.2, 0.7, 1.3), (0, 0.85, -1.5), root, glass, bevel=0.0, rot=(-28, 0, 0), taper=(0.8, 1.0))
    for x in (-1.6, 0.0, 1.6):
        m.box("mullion%d" % int(x * 10), (0.1, 0.75, 1.35), (x * 0.95, 0.88, -1.5), root, dark, bevel=0.0, rot=(-28, 0, 0))
    for k in range(6):
        a = math.tau * k / 6 + 0.3
        m.box("tear%d" % k, (rng.uniform(0.5, 0.9), 0.05, rng.uniform(0.3, 0.6)),
              (math.cos(a) * 2.4, math.sin(a) * 1.6, 2.55), root, paint_dark, bevel=0.0, rot=(rng.uniform(20, 50), math.degrees(a), 0))
    m.box("chin", (3.0, 0.3, 1.0), (0, -1.45, -1.8), root, dark, bevel=0.03)
    export("site_hauler_nose")


BUILDERS = {
    "crawler": crawler,
    "rib": lambda: rib(False),
    "rib_broken": lambda: rib(True),
    "hull_plate": hull_plate,
    "engine": engine,
    "hauler": hauler,
    "hauler_nose": hauler_nose,
}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in args or list(BUILDERS):
        m.reset()
        BUILDERS[name]()


if __name__ == "__main__":
    main()
