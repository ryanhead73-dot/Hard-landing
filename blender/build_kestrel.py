"""Builds Kestrel's exterior as GLB, to the orthographic model sheet (33 m long nose to nozzle,
20 m span): a faceted salvage hull with a glazed cockpit canopy, dorsal fin and twin engine pods.

Run headless with Blender 4.2+ (or the `bpy` 4.2 module):
    python blender/build_kestrel.py

The hull is lofted through hand-placed stations so it wraps the walkable deck plan in
godot/data/kestrel_layout.json with clearance: the rooms stay the CSG interior and collision, and
this shell is the silhouette. Each station is a ten-sided section (flat belly and roof, chamfered
corners, and a break line on each side where the canopy glazing starts). The side door and the
stern ramp are cut through it. Coordinates are Kestrel's local space in Godot
(plan x - 16.5, y, plan z - 13).

Object names pick the material in Godot: oxide_*, dark_*, frame_*, glass_*, decal_*; the rest
is hull.
Outputs (godot/assets/kestrel/):
    kestrel_hull.glb     hull shell, fin, vents, oxide plates, panel seams, canopy frame ribs
    kestrel_scorch.glb   crash soot overlays (hidden on the pre-crash ship)
    kestrel_canopy.glb   the canopy glazing on its own (swapped cracked/clear by the canopy repair)
    kestrel_nacelle.glb  one engine pod on the centreline (Godot places it at plan z 7.6 / 18.4)
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

# x (aft of the nose), half width W, roof T, belly B, roof chamfer c, belly chamfer cb.
STATIONS = [
    (0.0, 0.3, 1.55, 1.0, 0.1, 0.1),
    (1.0, 1.25, 2.3, 0.45, 0.4, 0.35),
    (2.2, 2.05, 3.15, 0.05, 0.55, 0.45),
    (3.4, 2.75, 4.0, -0.4, 0.4, 0.35),
    (6.0, 3.4, 4.2, -0.48, 0.6, 0.45),
    (8.2, 4.15, 4.15, -0.5, 0.65, 0.45),
    (11.3, 4.4, 4.1, -0.55, 0.6, 0.55),
    (16.0, 4.4, 4.0, -0.6, 0.6, 0.6),
    (23.5, 4.4, 3.85, -0.6, 0.6, 0.6),
    (27.0, 4.2, 3.65, -0.5, 0.55, 0.5),
    (29.6, 4.2, 3.55, -0.45, 0.5, 0.5),
    (30.45, 3.5, 3.35, -0.25, 0.4, 0.35),
]
# Extra loft rings so face boundaries land on the canopy, vent and seam lines.
EXTRA_X = [4.6, 7.0, 9.6, 13.4, 14.0, 14.6, 15.2, 15.8, 16.4, 19.6, 25.5]
WINDOW_Y = 2.0          # side break line: glazing above it, from GLASS_X[0] to GLASS_X[1]
GLASS_X = (1.0, 8.2)
GLASS_ROOF_TO = 3.4     # the roof is glazed only ahead of the cockpit's front wall
SKIN = 0.07

HULL = (0.82, 0.76, 0.62)
OXIDE = (0.55, 0.12, 0.03)
DARK = (0.02, 0.025, 0.03)
GLASS = (0.1, 0.2, 0.22)


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


def make(name, bm, rgb=HULL, smooth=False):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = smooth
    mesh.materials.append(material(name.split("_")[0], rgb))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def apply_mods(obj):
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


# --- Sections ------------------------------------------------------------------------------

def station(x):
    """Interpolated (W, T, B, c, cb) at plan x."""
    for a, b in zip(STATIONS, STATIONS[1:]):
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            return tuple(a[i] + (b[i] - a[i]) * t for i in range(1, 6))
    s = STATIONS[0] if x < STATIONS[0][0] else STATIONS[-1]
    return s[1:]


def window_y(x):
    W, T, B, c, cb = station(x)
    return min(max(WINDOW_Y, B + cb + 0.05), T - c - 0.05)


def section(x, grow=0.0):
    """Ten (z, y) points round the section, anticlockwise seen from the nose, starting at the
    belly's starboard corner. Face k runs from point k to k+1:
    0 stbd belly chamfer, 1 stbd lower side, 2 stbd upper side, 3 stbd roof chamfer, 4 roof,
    5 port roof chamfer, 6 port upper side, 7 port lower side, 8 port belly chamfer, 9 belly."""
    W, T, B, c, cb = station(x)
    W, T, B = W + grow, T + grow, B - grow
    wy = window_y(x)
    half = [((W - cb), B), (W, B + cb), (W, wy), (W, T - c), ((W - c), T)]
    pts = [(CZ + z, y) for z, y in half]
    pts += [(CZ - z, y) for z, y in reversed(half)]
    return pts


GLASS_FACES = {2, 3, 5, 6}
ROOF_FACE = 4


def ring_xs():
    xs = sorted(set([s[0] for s in STATIONS] + EXTRA_X + list(GLASS_X) + [GLASS_ROOF_TO]))
    return xs


def hull():
    """The shell and, separately, its canopy glazing."""
    xs = ring_xs()
    bm = bmesh.new()
    glass_bm = bmesh.new()
    rings = [[bm.verts.new(g(x, y, z)) for z, y in section(x)] for x in xs]
    grings = [[glass_bm.verts.new(g(x, y, z)) for z, y in section(x)] for x in xs]
    n = len(rings[0])
    for i in range(len(xs) - 1):
        xm = (xs[i] + xs[i + 1]) * 0.5
        for k in range(n):
            k2 = (k + 1) % n
            glazed = GLASS_X[0] <= xm <= GLASS_X[1] and (k in GLASS_FACES or (k == ROOF_FACE and xm < GLASS_ROOF_TO))
            r = grings if glazed else rings
            target = glass_bm if glazed else bm
            target.faces.new((r[i][k], r[i][k2], r[i + 1][k2], r[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    for b in (bm, glass_bm):
        bmesh.ops.remove_doubles(b, verts=b.verts, dist=0.0005)
        loose = [v for v in b.verts if not v.link_faces]
        bmesh.ops.delete(b, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
    # Normals of the open shell can come out inward; force them to face away from the axis.
    for b, is_glass in ((bm, False), (glass_bm, True)):
        flip = []
        for f in b.faces:
            c = f.calc_center_median()
            axis = Vector((c.x, 0.0, 1.6))
            if f.normal.dot(c - axis) < 0.0 and abs(f.normal.x) < 0.95:
                flip.append(f)
        if flip:
            bmesh.ops.reverse_faces(b, faces=flip)
    shell = make("hull", bm)
    mod = shell.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = SKIN
    mod.offset = -1.0
    mod.use_rim = True
    apply_mods(shell)
    # Openings: the side door (starboard, over the door steps) and the stern cargo ramp.
    door = LAYOUT["door_steps"]["x"]
    cut(shell, (door[0] - 0.05, door[1] + 0.05), (-0.9, 2.45), (16.9, 18.8))
    ramp = next(o for o in LAYOUT["openings"] if o["id"] == "cargo_ramp")
    cut(shell, (29.9, 31.0), (-0.1, 2.95), (ramp["z"][0] - 0.3, ramp["z"][1] + 0.3))
    make("glass_canopy", glass_bm, GLASS)


def cut(obj, xr, yr, zr):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    lo, hi = g(xr[0], yr[0], zr[1]), g(xr[1], yr[1], zr[0])
    for v in bm.verts:
        v.co = Vector((lo.x if v.co.x < 0 else hi.x, lo.y if v.co.y < 0 else hi.y, lo.z if v.co.z < 0 else hi.z))
    mesh = bpy.data.meshes.new("cutter")
    bm.to_mesh(mesh)
    bm.free()
    cutter = bpy.data.objects.new("cutter", mesh)
    bpy.context.collection.objects.link(cutter)
    mod = obj.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter
    apply_mods(obj)
    bpy.data.objects.remove(cutter)


# --- Surface details -------------------------------------------------------------------------

def on_face(x, k, u, lift=0.012):
    """A point on section face k at plan x, a fraction u along it, lifted off the skin."""
    pts = section(x, lift)
    a, b = pts[k], pts[(k + 1) % len(pts)]
    return (x, a[1] + (b[1] - a[1]) * u, a[0] + (b[0] - a[0]) * u)


def quad_strip(bm, rows):
    """Rows of points (same length) -> faces."""
    vs = [[bm.verts.new(g(*p)) for p in row] for row in rows]
    for a, b in zip(vs, vs[1:]):
        for k in range(len(a) - 1):
            bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
    return vs


def band(name, x0, x1, faces, rgb, lift=0.012, skip_door=False):
    """A strip round the listed section faces between x0 and x1 (panel seams, frame ribs)."""
    bm = bmesh.new()
    for k in faces:
        quad_strip(bm, [[on_face(x0, k, 0.0, lift), on_face(x0, k, 1.0, lift)],
                        [on_face(x1, k, 0.0, lift), on_face(x1, k, 1.0, lift)]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return make(name, bm, rgb)


def vents():
    """Six slanted cooling louvres on each roof chamfer, ahead of the radiators."""
    bm = bmesh.new()
    for i in range(6):
        x = 13.5 + i * 0.5
        for k in (3, 5):
            lo_u, hi_u = (0.15, 0.85)
            rows = []
            for u in (lo_u, hi_u):
                skew = (u - 0.5) * 0.3 * (1 if k == 3 else -1) * -1
                p0 = on_face(x + skew, k, u, 0.02)
                p1 = on_face(x + 0.14 + skew, k, u, 0.02)
                rows.append([p0, p1])
            quad_strip(bm, rows)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    make("dark_vents", bm, DARK)


def oxide_plates():
    """The sheet's raked oxide panel low on each side under the canopy, and a stern patch."""
    bm = bmesh.new()
    for k in (1, 7):
        rows = []
        for t in (0.0, 0.25, 0.5, 0.75, 1.0):
            row = []
            for s in range(25):
                f = s / 24
                # Parallelogram: lower edge x 4.6..9.2, upper edge shifted aft and shorter.
                x = (4.6 + 4.6 * f) * (1.0 - t) + (6.3 + 3.6 * f) * t
                W, T, B, c, cb = station(x)
                y0, y1 = B + cb + 0.25, window_y(x) - 0.45
                y = y0 + (y1 - y0) * t
                u = (y - (B + cb)) / max(window_y(x) - (B + cb), 0.01)
                row.append(on_face(x, k, u if k == 1 else 1.0 - u, 0.02))
            rows.append(row)
        quad_strip(bm, rows)
    # Roof patch over the cargo bay, as on the crash paintover.
    for k in (4,):
        quad_strip(bm, [[on_face(x, k, u, 0.015) for u in (0.12, 0.5, 0.88)] for x in (24.2, 26.0, 27.8, 29.4)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    make("oxide_plates", bm, OXIDE)


def fin():
    """Single swept dorsal fin over the cargo bay."""
    bm = bmesh.new()
    rings = []
    root_y = station(28.0)[1] - 0.1
    for t in (0.0, 0.3, 0.65, 1.0):
        lx = 25.6 + (29.6 - 25.6) * t
        tx = 30.3 + (31.4 - 30.3) * t
        y = root_y + (5.9 - root_y) * t
        th = 0.34 + (0.12 - 0.34) * t
        ring = []
        for k in range(10):
            a = math.tau * k / 10
            u = 0.5 - 0.5 * math.cos(a)
            x = lx + (tx - lx) * u
            half = th * 0.5 * (math.sin(math.pi * u ** 0.6) if 0 < u < 1 else 0.0) + 0.01
            ring.append(bm.verts.new(g(x, y, CZ + math.copysign(half, math.sin(a)))))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(10):
            k2 = (k + 1) % 10
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    make("hull_fin", bm)
    # Oxide cap on the fin tip.
    bm = bmesh.new()
    rows = []
    for y, lx, tx in ((5.3, 29.25, 31.18), (5.92, 29.62, 31.42)):
        rows.append([(lx, y, CZ - 0.09), (tx, y, CZ - 0.09), (tx, y, CZ + 0.09), (lx, y, CZ + 0.09), (lx, y, CZ - 0.09)])
    quad_strip(bm, rows)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    make("oxide_fin", bm, OXIDE)


# --- Engine pod ------------------------------------------------------------------------------

POD_Y = 1.9
POD_SIDES = 12
POD_PROFILE = [(18.0, 0.72), (18.08, 0.92), (18.45, 1.05), (28.0, 1.05), (30.8, 0.98), (32.6, 0.86), (33.0, 0.8)]


def pod_ring(x, r, phase=0.5):
    return [(x, POD_Y + r * math.sin(math.tau * (k + phase) / POD_SIDES), CZ + r * math.cos(math.tau * (k + phase) / POD_SIDES))
            for k in range(POD_SIDES)]


def nacelle():
    bm = bmesh.new()
    rings = [[bm.verts.new(g(*p)) for p in pod_ring(x, r)] for x, r in POD_PROFILE]
    for a, b in zip(rings, rings[1:]):
        for k in range(POD_SIDES):
            k2 = (k + 1) % POD_SIDES
            bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    make("nacelle", bm)
    for name, x0, x1, r0, r1, rgb, cap in (("dark_intake", 18.0, 18.9, 0.72, 0.6, DARK, True),
                                           ("dark_nozzle", 33.0, 32.2, 0.8, 0.66, DARK, True),
                                           ("oxide_band", 20.2, 20.9, 1.065, 1.065, OXIDE, False),
                                           ("dark_seam_pod", 27.4, 27.5, 1.06, 1.06, DARK, False)):
        b2 = bmesh.new()
        rs = [[b2.verts.new(g(*p)) for p in pod_ring(x, r)] for x, r in ((x0, r0), (x1, r1))]
        for k in range(POD_SIDES):
            k2 = (k + 1) % POD_SIDES
            b2.faces.new((rs[0][k], rs[0][k2], rs[1][k2], rs[1][k]))
        if cap:
            b2.faces.new(rs[1])
        bmesh.ops.recalc_face_normals(b2, faces=b2.faces)
        make(name, b2, rgb)


# --- Decal overlays ----------------------------------------------------------------------------
# Thin mesh overlays UV-mapped into the 2048 decal atlas (assets/textures/kestrel/decal_atlas.png),
# image coordinates 0..1 with y down. They work in every renderer, unlike Decal nodes.
ATLAS = {
    "soot_a": (0.585, 0.03, 0.73, 0.14), "soot_b": (0.80, 0.0, 0.935, 0.18),
    "soot_c": (0.6, 0.18, 0.735, 0.28), "soot_d": (0.79, 0.19, 0.945, 0.32),
    "soot_wide": (0.54, 0.0, 0.99, 0.38),
    "hazard": (0.035, 0.405, 0.455, 0.455), "power": (0.565, 0.445, 0.66, 0.535),
    "warning": (0.69, 0.44, 0.8, 0.535), "streaks": (0.53, 0.57, 0.99, 0.68),
    "rivets": (0.03, 0.825, 0.965, 0.855),
}
UPWARD = {0, 1, 2, 3}   # faces whose u runs up the hull; 5..8 run down, 4 and 9 run across


def side_u(k, f):
    """u on face k for a fraction f measured up the face (or across, for the roof and belly)."""
    return f if k in UPWARD or k in (4, 9) else 1.0 - f


def decal(bm, uv, region, x0, x1, k, f_bottom, f_top, lift=0.022, nx=4):
    """Overlay on face k between plan x0..x1 and fractions f_bottom..f_top up the face. The
    image reads left to right when seen from outside, with its top edge up the hull."""
    ix0, iy0, ix1, iy1 = ATLAS[region]
    flip = k in (5, 6, 7, 8)  # port side: seen from outside, the nose is on the right
    rows = []
    for j, f in enumerate((f_top, f_bottom)):
        row = []
        for i in range(nx + 1):
            t = i / nx
            p = on_face(x0 + (x1 - x0) * t, k, side_u(k, f), lift)
            iu = ix0 + (ix1 - ix0) * (1.0 - t if flip else t)
            iv = iy0 + (iy1 - iy0) * j
            row.append((bm.verts.new(g(*p)), (iu, 1.0 - iv)))
        rows.append(row)
    for a, b in zip(rows, rows[1:]):
        for i in range(nx):
            f = bm.faces.new((a[i][0], a[i + 1][0], b[i + 1][0], b[i][0]))
            for loop, (_, co) in zip(f.loops, (a[i], a[i + 1], b[i + 1], b[i])):
                loop[uv].uv = co


def decals(name, entries):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    for e in entries:
        decal(bm, uv, *e)
    make(name, bm, DARK)


WEAR = [
    # Rivet lines just under the window line, both sides, cockpit to stern.
    ("rivets", 8.4, 19.0, 1, 0.9, 0.97, 0.022, 8), ("rivets", 19.0, 29.5, 1, 0.9, 0.97, 0.022, 8),
    ("rivets", 8.4, 19.0, 7, 0.9, 0.97, 0.022, 8), ("rivets", 19.0, 29.5, 7, 0.9, 0.97, 0.022, 8),
    # Hazard stripe over the side door, and warning marks by the engine intakes.
    ("hazard", 11.8, 14.0, 2, 0.28, 0.42), ("warning", 16.4, 17.2, 1, 0.45, 0.85, 0.022, 1),
    ("warning", 16.4, 17.2, 7, 0.45, 0.85, 0.022, 1), ("power", 9.0, 9.8, 1, 0.35, 0.8, 0.022, 1),
    # Rain streaks under the cooling louvres and along the cargo bay.
    ("streaks", 13.2, 16.8, 2, 0.05, 1.0), ("streaks", 13.2, 16.8, 6, 0.05, 1.0),
    ("streaks", 24.0, 28.6, 1, 0.1, 0.95), ("streaks", 24.0, 28.6, 7, 0.1, 0.95),
]
SCORCH = [
    # Nose-down impact: soot over the chin and lower nose.
    ("soot_wide", 0.3, 3.6, 9, 0.05, 0.95), ("soot_a", 0.4, 3.4, 1, 0.0, 1.0), ("soot_c", 0.4, 3.4, 7, 0.0, 1.0),
    ("soot_b", 0.6, 3.0, 0, 0.0, 1.0), ("soot_d", 0.6, 3.0, 8, 0.0, 1.0),
    # Engine surge: trails along the port flank where the pod tore away, and over the stern roof.
    ("soot_wide", 17.5, 26.0, 7, 0.0, 1.0, 0.024), ("soot_b", 18.0, 22.0, 6, 0.0, 1.0, 0.024),
    ("soot_d", 26.5, 30.3, 4, 0.0, 0.45, 0.026), ("soot_a", 22.0, 25.0, 3, 0.0, 1.0, 0.024),
    ("soot_c", 8.6, 11.0, 8, 0.0, 1.0),
]


def export(name):
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    print("exported", name)


def main():
    reset()
    hull()
    glass = bpy.data.objects["glass_canopy"]
    bpy.data.objects.remove(glass)
    fin()
    vents()
    oxide_plates()
    for i, x in enumerate((9.6, 19.6, 25.5)):
        band("dark_seam_%d" % i, x - 0.03, x + 0.03, [0, 1, 2, 3, 4, 5, 6, 7, 8], DARK)
    # Canopy frame: ribs over the glazing and a sill along the break line.
    for i, x in enumerate((1.0, 2.2, 3.4, 4.6, 5.8, 7.0, 8.2)):
        faces = [2, 3, 4, 5, 6] if x <= GLASS_ROOF_TO else [2, 3, 5, 6]
        band("frame_rib_%d" % i, x - 0.07, x + 0.07, faces, DARK, lift=0.03)
    for k, u in ((2, 0.0), (6, 1.0), (3, 0.0), (5, 1.0)):
        bm = bmesh.new()
        xs = [x for x in ring_xs() if GLASS_X[0] <= x <= GLASS_X[1]]
        rows = []
        for x in xs:
            p = on_face(x, k, u, 0.03)
            rows.append([(p[0], p[1] - 0.06, p[2]), (p[0], p[1] + 0.06, p[2])])
        quad_strip(bm, rows)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        make("frame_sill_%d_%d" % (k, int(u)), bm, DARK)
    decals("decal_wear", WEAR)
    export("kestrel_hull")
    reset()
    decals("decal_scorch", SCORCH)
    export("kestrel_scorch")
    reset()
    hull()
    for obj in list(bpy.data.objects):
        if obj.name != "glass_canopy":
            bpy.data.objects.remove(obj)
    export("kestrel_canopy")
    reset()
    nacelle()
    export("kestrel_nacelle")


if __name__ == "__main__":
    main()
