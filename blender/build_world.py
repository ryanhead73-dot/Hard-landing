"""Builds Hard Landing's world dressing (basalt columns, boulders, crags, moss and reeds) as GLB.

Run headless with Blender 4.2+ (or the `bpy` 4.2 module):
    python blender/build_world.py            # with `pip install bpy==4.2.0`

Everything is built with bmesh from a fixed seed, so the output is identical every run.
Positions are written in Godot space (x right, y up, -z forward). Each model's origin is at its
base, with a little extra buried below y = 0 so it sits on uneven ground. Godot shades rocks with
its own triplanar basalt shader, so the materials here are only names and base colours.
Output: godot/assets/world/<name>.glb.
"""

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector, noise

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "godot", "assets", "world")


def g(x, y, z):
    return Vector((x, -z, y))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb, rough=0.8):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1.0)
    p.inputs["Roughness"].default_value = rough
    return m


def to_object(bm, name, mat, smooth=False):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def export(name):
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB",
                              export_apply=True, export_yup=True, export_materials="EXPORT")
    print("exported", name)


# --- Basalt columns ------------------------------------------------------------------------

def hex_column(bm, cx, cz, radius, height, rng, bury=1.2):
    """One hexagonal column from y = -bury to `height`, its top cut at a slight tilt and its
    rim chipped, so a cluster reads as cooled lava, not a row of pencils."""
    turn = rng.uniform(0.0, math.pi / 3.0)
    tilt_x = rng.uniform(-0.12, 0.12)
    tilt_z = rng.uniform(-0.12, 0.12)
    bottom, top = [], []
    for k in range(6):
        a = turn + k * math.pi / 3.0
        r = radius * rng.uniform(0.92, 1.04)
        x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
        y_top = height + (x - cx) * tilt_x + (z - cz) * tilt_z + rng.uniform(-0.04, 0.04)
        bottom.append(bm.verts.new(g(x, -bury, z)))
        # A slight inward lean near the top: weathering rounds the edges.
        top.append(bm.verts.new(g(cx + (x - cx) * 0.96, y_top, cz + (z - cz) * 0.96)))
    for k in range(6):
        n = (k + 1) % 6
        bm.faces.new((bottom[k], bottom[n], top[n], top[k]))
    cap = bm.faces.new(list(reversed(top)) if False else top)
    # Chamfer the cap: an inset that drops a little reads as a worn rim.
    res = bmesh.ops.inset_region(bm, faces=[cap], thickness=radius * 0.12, depth=-0.03)
    return cap


def basalt_cluster(name, seed, count, spread, h_range, radius=(0.45, 0.8), mound=True):
    reset()
    rng = random.Random(seed)
    bm = bmesh.new()
    placed = []
    r_avg = sum(radius) * 0.5
    step = r_avg * 1.85
    ring = 0
    # Columns packed on a hex lattice from the centre out; heights fall away from the core.
    cells = []
    for q in range(-6, 7):
        for r in range(-6, 7):
            x = step * (q + r * 0.5)
            z = step * r * 0.866
            d = math.hypot(x, z)
            cells.append((d + rng.uniform(0.0, spread * 0.25), x, z))
    cells.sort()
    for d, x, z in cells[:count]:
        rad = rng.uniform(*radius)
        fall = 1.0 - min(d / (spread + 0.01), 1.0)
        h = h_range[0] + (h_range[1] - h_range[0]) * (fall ** 0.8 if mound else rng.random())
        h *= rng.uniform(0.7, 1.15)
        # Now and then a broken stub.
        if rng.random() < 0.18:
            h *= 0.35
        hex_column(bm, x + rng.uniform(-0.05, 0.05), z + rng.uniform(-0.05, 0.05), rad * 0.97, max(h, 0.3), rng)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    to_object(bm, name, material("basalt", (0.012, 0.013, 0.014), 0.75))
    export(name)


# --- Boulders and crags ----------------------------------------------------------------------

def rock(name, seed, size, crag=0.35, facet=7.0, subdiv=3, flat_base=True):
    reset()
    rng = random.Random(seed)
    off = Vector((rng.uniform(0, 100), rng.uniform(0, 100), rng.uniform(0, 100)))
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in bm.verts:
        p = v.co.copy()
        n = noise.fractal(p * 1.4 + off, 0.6, 2.1, 4)
        cells = noise.voronoi(p * 2.2 + off)[0][0]
        v.co = p * (1.0 + n * crag - cells * crag * 0.6)
        v.co.x *= size[0]
        v.co.y *= size[2]
        v.co.z *= size[1]
        if flat_base and v.co.z < -size[1] * 0.25:
            v.co.z = -size[1] * 0.25 - (v.co.z + size[1] * 0.25) * 0.15
    # Lift so the base sits a little under y = 0.
    for v in bm.verts:
        v.co.z += size[1] * 0.25 - 0.15
    # Faceted, the way basalt fractures: merge nearly-flat faces.
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(facet), verts=bm.verts, edges=bm.edges)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    to_object(bm, name, material("basalt", (0.015, 0.016, 0.017), 0.8))
    export(name)


# --- Ground cover ----------------------------------------------------------------------------

def moss_clump(name, seed):
    reset()
    rng = random.Random(seed)
    bm = bmesh.new()
    for i in range(5):
        sub = bmesh.new()
        bmesh.ops.create_icosphere(sub, subdivisions=2, radius=1.0)
        r = rng.uniform(0.18, 0.34)
        cx, cz = rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35)
        off = Vector((rng.uniform(0, 50), rng.uniform(0, 50), 0))
        for v in sub.verts:
            p = v.co.copy()
            bump = 1.0 + noise.fractal(p * 3.0 + off, 0.5, 2.0, 3) * 0.35
            v.co = Vector((cx + p.x * r * bump, -cz + p.y * r * bump, max(p.z, -0.2) * r * 0.45 * bump))
        mesh = bpy.data.meshes.new("tmp")
        sub.to_mesh(mesh)
        sub.free()
        bm.from_mesh(mesh)
    to_object(bm, name, material("moss", (0.02, 0.2, 0.15), 1.0), smooth=True)
    export(name)


def reeds(name, seed, blades=9, height=(0.7, 1.4)):
    reset()
    rng = random.Random(seed)
    bm = bmesh.new()
    for b in range(blades):
        a = rng.uniform(0.0, math.tau)
        h = rng.uniform(*height)
        lean = rng.uniform(0.15, 0.45)
        base = Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15)))
        width = rng.uniform(0.035, 0.06)
        side = Vector((-math.sin(a), math.cos(a)))
        out = Vector((math.cos(a), math.sin(a)))
        rows = []
        for s in range(5):
            t = s / 4.0
            c = base + out * (lean * t * t * h)
            w = width * (1.0 - t * 0.9)
            y = h * t * (1.0 - lean * 0.3 * t)
            l = bm.verts.new(g(c.x - side.x * w, y, c.y - side.y * w))
            r = bm.verts.new(g(c.x + side.x * w, y, c.y + side.y * w))
            rows.append((l, r))
        for s in range(4):
            bm.faces.new((rows[s][0], rows[s][1], rows[s + 1][1], rows[s + 1][0]))
    to_object(bm, name, material("reed", (0.02, 0.06, 0.05), 0.9))
    export(name)


def main():
    basalt_cluster("basalt_cluster_0", 11, 19, 3.5, (2.5, 9.0))
    basalt_cluster("basalt_cluster_1", 23, 9, 2.2, (1.5, 5.5))
    basalt_cluster("basalt_cluster_2", 37, 34, 5.0, (3.0, 14.0))
    basalt_cluster("basalt_step_0", 41, 26, 4.5, (0.4, 1.6), radius=(0.55, 0.9), mound=False)
    rock("boulder_0", 3, (1.3, 0.9, 1.1))
    rock("boulder_1", 5, (2.2, 1.4, 1.6), crag=0.4)
    rock("boulder_2", 8, (0.7, 0.5, 0.6), crag=0.3, subdiv=2)
    rock("crag_0", 13, (9.0, 7.0, 6.0), crag=0.5, facet=4.0, subdiv=4)
    rock("crag_1", 17, (14.0, 10.0, 8.0), crag=0.55, facet=4.0, subdiv=4)
    moss_clump("moss_clump", 2)
    reeds("reeds", 4)


if __name__ == "__main__":
    main()
