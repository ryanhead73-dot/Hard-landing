"""Builds Kestrel's exterior skin as GLB: the curved roof fairings, belly keel, nose cone,
twin tail fins and the engine nacelle.

Run headless with Blender 4.2+ (or the `bpy` 4.2 module):
    python blender/build_kestrel.py

The skin is fitted around the deck plan in godot/data/kestrel_layout.json: the rooms stay the
walkable CSG interior, and these fairings wrap over and under them with a little clearance, so
from outside Kestrel reads as a curved salvage hauler rather than a stack of boxes. Openings
(side door, canopy windows, cargo ramp) are left clear. Coordinates are Kestrel's local space
in Godot (plan x - 16.5, y, plan z - 13). Mesh objects named "oxide_*" or "dark_*" take those
materials in Godot; everything else is cream hull.
Output: godot/assets/kestrel/<part>.glb.
"""

import json
import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "godot", "assets", "kestrel")
LAYOUT = json.load(open(os.path.join(ROOT, "godot", "data", "kestrel_layout.json")))
HALF_LEN = LAYOUT["length"] * 0.5
CZ = LAYOUT["centreline_z"]
T = LAYOUT["wall"] * 0.5


def g(x, y, z):
    """Plan coordinates (x aft of the nose, y up from the deck, z from the port line) -> Blender."""
    return Vector((x - HALF_LEN, -(z - CZ), y))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1.0)
    return m


HULL = (0.82, 0.76, 0.62)
OXIDE = (0.55, 0.12, 0.03)
DARK = (0.02, 0.025, 0.03)


def make(name, bm, rgb=HULL, smooth=True, solidify=0.0, offset=-1.0):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = smooth
    mesh.materials.append(material(name.split("_")[0] if name.split("_")[0] in ("oxide", "dark") else "hull", rgb))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if solidify:
        mod = obj.modifiers.new("Solidify", "SOLIDIFY")
        mod.thickness = solidify
        mod.offset = offset
    return obj


def loft(bm, rings, closed, cap_start=False, cap_end=False):
    """Skins a list of rings (lists of plan-space points, same length) into faces."""
    verts = [[bm.verts.new(g(*p)) for p in ring] for ring in rings]
    n = len(rings[0])
    for a, b in zip(verts, verts[1:]):
        for k in range(n if closed else n - 1):
            k2 = (k + 1) % n
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    if cap_start:
        bm.faces.new(list(reversed(verts[0])))
    if cap_end:
        bm.faces.new(verts[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return verts


def superellipse(cy, cz, half_w, half_h, n, steps, start=0.0, end=math.tau):
    """Points round (cy, cz): angle 0 is +z (starboard), pi/2 is up."""
    pts = []
    for i in range(steps + 1 if end - start < math.tau - 1e-6 else steps):
        a = start + (end - start) * i / steps
        c, s = math.cos(a), math.sin(a)
        z = cz + half_w * math.copysign(abs(c) ** (2.0 / n), c)
        y = cy + half_h * math.copysign(abs(s) ** (2.0 / n), s)
        pts.append((z, y))
    return pts


# --- Fitting the skin to the deck plan --------------------------------------------------------

def rooms_at(x, min_top=0.0):
    return [r for r in LAYOUT["rooms"] if r["x"][0] - T <= x <= r["x"][1] + T and r["ceiling"] + 0.2 > min_top]


def raw_half_width(x, min_top):
    rs = rooms_at(x, min_top)
    return max((max(abs(r["z"][0] - CZ), abs(r["z"][1] - CZ)) + T for r in rs), default=0.0)


def raw_top(x):
    return max((r["ceiling"] + 0.2 for r in rooms_at(x)), default=0.0)


def dilate(f, x, reach=0.7, samples=8):
    return max(f(x + reach * (i / samples * 2.0 - 1.0)) for i in range(samples + 1))


# --- Parts -----------------------------------------------------------------------------------

def roof(name, x0, x1, base_y, step=0.2, n=4.0):
    """An arched fairing from base_y up over the rooms between x0 and x1, ends capped."""
    bm = bmesh.new()
    rings = []
    x = x0
    xs = []
    while x <= x1 + 1e-6:
        xs.append(x)
        x += step
    for x in xs:
        w = dilate(lambda q: raw_half_width(q, base_y), x)
        top = dilate(raw_top, x)
        W = w + 0.22
        # Rise so the top corners of the rooms sit inside the arch (superellipse n).
        k = max(0.92 - (w / W) ** n, 0.05)
        R = max(top - base_y, 0.3) / k ** (1.0 / n) + 0.08
        # Round the ends down into the caps.
        end = min(x - x0, x1 - x) / 1.2
        shrink = 1.0 if end >= 1.0 else 0.75 + 0.25 * math.sin(end * math.pi * 0.5)
        pts = superellipse(base_y, CZ, W, R * shrink, n, 28, 0.0, math.pi)
        rings.append([(x, y, z) for z, y in pts])
    loft(bm, rings, closed=False)
    # End caps: fans from the base centre.
    for ring, flip in ((rings[0], True), (rings[-1], False)):
        centre = bm.verts.new(g(ring[0][0], base_y, CZ))
        vs = [bm.verts.new(g(*p)) for p in ring]
        for a, b in zip(vs, vs[1:]):
            bm.faces.new((centre, b, a) if flip else (centre, a, b))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return make(name, bm, solidify=0.08)


def keel(name, x0, x1, half_w=1.9, depth=0.55, top_y=-0.21):
    bm = bmesh.new()
    rings = []
    steps = 40
    for i in range(steps + 1):
        x = x0 + (x1 - x0) * i / steps
        t = i / steps
        taper = math.sin(math.pi * min(t / 0.18, 1.0, (1.0 - t) / 0.12) * 0.5) if t < 0.18 or t > 0.88 else 1.0
        pts = superellipse(top_y, CZ, half_w * (0.4 + 0.6 * taper), depth * (0.2 + 0.8 * taper), 3.0, 20, math.pi, math.tau)
        rings.append([(x, y, z) for z, y in pts])
    loft(bm, rings, closed=False, cap_start=False, cap_end=False)
    return make(name, bm, solidify=0.06)


def nose(name):
    """Chin and nose cone ahead of the cockpit, under the windscreen."""
    bm = bmesh.new()
    rings = []
    tip_x, root_x = 0.15, 3.75
    steps = 24
    for i in range(steps + 1):
        t = i / steps
        x = tip_x + (root_x - tip_x) * t
        # Ogive: blunt, then full.
        k = math.sin(t * math.pi * 0.5) ** 0.6
        half_w = 0.12 + 2.45 * k
        bottom, top = 0.85 - 1.3 * k, 0.95 + 1.04 * k
        cy, hh = (top + bottom) * 0.5, (top - bottom) * 0.5
        pts = superellipse(cy, CZ, half_w, max(hh, 0.1), 2.6, 32)
        rings.append([(x, y, z) for z, y in pts])
    loft(bm, rings, closed=True, cap_start=True, cap_end=True)
    obj = make(name, bm)
    # A dark sensor window under the chin, and an oxide stripe round the cone.
    bm2 = bmesh.new()
    band = []
    for x in (1.6, 1.85):
        t = (x - tip_x) / (root_x - tip_x)
        k = math.sin(t * math.pi * 0.5) ** 0.6
        half_w = 0.12 + 2.45 * k + 0.012
        bottom, top = 0.85 - 1.3 * k - 0.012, 0.95 + 1.04 * k + 0.012
        pts = superellipse((top + bottom) * 0.5, CZ, half_w, (top - bottom) * 0.5, 2.6, 32)
        band.append([(x, y, z) for z, y in pts])
    loft(bm2, band, closed=True)
    make(name + "_oxide_band".replace(name + "_", "oxide_nose_"), bm2, OXIDE)
    return obj


def rounded_rect(z0, z1, y0, y1, r, steps=4):
    """Corner points of a rounded rectangle in (z, y), anticlockwise from the bottom right."""
    pts = []
    for cz, cy, a0 in ((z1 - r, y0 + r, -math.pi / 2), (z1 - r, y1 - r, 0.0),
                       (z0 + r, y1 - r, math.pi / 2), (z0 + r, y0 + r, math.pi)):
        for i in range(steps + 1):
            a = a0 + (math.pi / 2) * i / steps
            pts.append((cz + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def plate_with_hole(bm, x, outer, inner):
    """A flat face at plan x bounded by `outer` with `inner` cut out (both (z, y) loops)."""
    edges = []
    for loop in (outer, inner):
        vs = [bm.verts.new(g(x, y, z)) for z, y in loop]
        for a, b in zip(vs, vs[1:] + vs[:1]):
            edges.append(bm.edges.new((a, b)))
    bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=edges)
    # Face forward (towards the nose, -x in Blender) so the solidified plate shades outward.
    flip = [f for f in bm.faces if f.normal.x > 0.0]
    if flip:
        bmesh.ops.reverse_faces(bm, faces=flip)


WINDSCREEN = (11.25, 14.75, 1.95, 3.35)


def cowl(name):
    """The cockpit's front bulkhead skin: a hull-coloured bezel round the windscreen that hides
    the boxy wall ends between the nose cone and the roof, with an oxide frame round the glass."""
    z0, z1, y0, y1 = WINDSCREEN
    outer = rounded_rect(CZ - 2.62, CZ + 2.62, 0.9, 3.55, 0.7, 6)
    inner = rounded_rect(z0, z1, y0, y1, 0.22)
    bm = bmesh.new()
    plate_with_hole(bm, 3.44, outer, inner)
    make(name, bm, solidify=0.12, offset=0.0)
    bm = bmesh.new()
    frame = rounded_rect(z0 - 0.14, z1 + 0.14, y0 - 0.14, y1 + 0.14, 0.32)
    plate_with_hole(bm, 3.37, frame, inner)
    make("oxide_" + name, bm, OXIDE, solidify=0.03, offset=0.0)


def fin(name, zc):
    """Swept tail fin with a thin airfoil, oxide tip."""
    bm = bmesh.new()
    root = [(29.2, 2.7), (33.3, 2.7)]
    tip = [(32.0, 6.1), (33.7, 6.1)]
    thick_root, thick_tip = 0.22, 0.1
    rings = []
    for t in (0.0, 0.25, 0.5, 0.75, 1.0):
        lx = root[0][0] + (tip[0][0] - root[0][0]) * t
        tx = root[1][0] + (tip[1][0] - root[1][0]) * t
        y = root[0][1] + (tip[0][1] - root[0][1]) * t
        th = thick_root + (thick_tip - thick_root) * t
        ring = []
        for k in range(12):
            a = math.tau * k / 12
            u = 0.5 - 0.5 * math.cos(a)  # 0 leading edge .. 1 trailing edge
            x = lx + (tx - lx) * u
            half = th * 0.5 * (math.sin(math.pi * u ** 0.6) if 0 < u < 1 else 0.0) + 0.005
            ring.append((x, y, zc + math.copysign(half, math.sin(a))))
        rings.append(ring)
    loft(bm, rings, closed=True, cap_start=True, cap_end=True)
    make(name, bm)
    bm2 = bmesh.new()
    cap = []
    for t in (0.86, 1.0):
        lx = root[0][0] + (tip[0][0] - root[0][0]) * t
        tx = root[1][0] + (tip[1][0] - root[1][0]) * t
        y = root[0][1] + (tip[0][1] - root[0][1]) * t + 0.01
        cap.append([(lx - 0.01, y, zc - 0.07), (tx + 0.01, y, zc - 0.07), (tx + 0.01, y, zc + 0.07), (lx - 0.01, y, zc + 0.07)])
    loft(bm2, cap, closed=True, cap_end=True)
    make("oxide_" + name, bm2, OXIDE, smooth=False)


def nacelle(name):
    """Engine nacelle along +x, centred on its axis at the origin of plan (29.0, 1.9, 13)."""
    bm = bmesh.new()
    # (x offset from the nacelle centre, radius) from the intake lip to the nozzle.
    profile = [(-4.55, 0.78), (-4.6, 0.92), (-4.45, 1.06), (-4.0, 1.1), (-1.0, 1.12), (2.0, 1.06),
               (3.6, 0.96), (4.3, 0.86), (4.45, 0.8), (4.4, 0.7)]
    rings = []
    for dx, r in profile:
        ring = []
        for k in range(32):
            a = math.tau * k / 32
            ring.append((29.0 + dx, 1.9 + r * math.sin(a), CZ + r * math.cos(a)))
        rings.append(ring)
    loft(bm, rings, closed=True)
    make(name, bm)
    # Dark intake and nozzle throats, and an oxide band round the cowling.
    for part, x0, x1, r0, r1, rgb in (("dark_intake", -4.55, -3.6, 0.78, 0.7, DARK), ("dark_nozzle", 4.4, 3.6, 0.7, 0.62, DARK),
                                       ("oxide_band", -2.2, -1.6, 1.125, 1.125, OXIDE)):
        bm2 = bmesh.new()
        rings = []
        for dx, r in ((x0, r0), (x1, r1)):
            rings.append([(29.0 + dx, 1.9 + r * math.sin(math.tau * k / 32), CZ + r * math.cos(math.tau * k / 32)) for k in range(32)])
        loft(bm2, rings, closed=True, cap_end=part.startswith("dark"))
        make(part, bm2, rgb)


def export(name):
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    print("exported", name)


def main():
    reset()
    roof("roof_main", 8.0, 30.2, 2.5)
    roof("roof_cockpit", 3.5, 8.3, 3.35, step=0.15)
    export("kestrel_roof")
    reset()
    keel("keel", 4.2, 29.4)
    export("kestrel_keel")
    reset()
    nose("nose")
    cowl("cowl")
    export("kestrel_nose")
    reset()
    fin("fin_port", 7.6)
    fin("fin_stbd", 18.4)
    export("kestrel_fins")
    reset()
    nacelle("nacelle")
    export("kestrel_nacelle")


if __name__ == "__main__":
    main()
