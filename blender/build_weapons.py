"""Build Juno's three rigid game props with Blender 4.2 or bpy.

    python blender/build_weapons.py [-- rifle scattergun arc_lance]

Side elevations below are drawn in metres, (forward, height). Across the hull is
Blender X, forward is Blender Y (Godot -Z), and height is Blender Z (Godot Y).
"""

import atexit
import math
import os
import sys
from collections import defaultdict
from functools import lru_cache

import bpy  # Standalone bpy initializes bmesh and mathutils on import.

# isort: split
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_models as bm
import creature_kit as kit

GRIP_R = (0, -0.12, 0.17)
GRIP_L = (0, -0.06, -0.12)
MUZZLE = (0, 0.01, -0.48)

IRON = "45525a"
DARK = "28343a"
STEEL = "94a0a1"
IVORY = "e0d3b7"
ORANGE = "c86632"
YELLOW = "edb64b"
RUBBER = "393737"
WRAP = "70554a"
COPPER = "a4694e"
TEAL = "51dcda"
linear = lru_cache(None)(kit.C)


class Casting:
    """Gather bevelled pieces in one mesh per rigid pivot. Bake against the whole prop."""

    def __init__(self, root_name, lamp="52dfdf"):
        bm.reset()
        self.root = bm.pivot(root_name)
        self.parent = self.root
        self.parts = defaultdict(list)
        self.materials = {
            "metal": bm.mat("Brushed alloy", "ffffff", 0.46, 0.57),
            "paint": bm.mat("Salvaged enamel", "ffffff", 0.59, 0.18),
            "soft": bm.mat("Insulation", "ffffff", 0.86),
        }
        if lamp:
            mat = bm.mat("Instrument phosphor", "ffffff", 0.32, 0.12)
            shader = mat.node_tree.nodes.get("Principled BSDF")
            shader.inputs["Emission Color"].default_value = (*linear(lamp), 1)
            shader.inputs["Emission Strength"].default_value = 1.45
            self.materials["lamp"] = mat
        for material in self.materials.values():
            nodes = material.node_tree.nodes
            color = nodes.new("ShaderNodeVertexColor")
            color.layer_name = "Finish"
            material.node_tree.links.new(color.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
        for name, point in (("GripR", GRIP_R), ("GripL", GRIP_L), ("Muzzle", MUZZLE)):
            bm.pivot(name, point, self.root)

    def piece(self, verts, faces, color, surface, bevel=0, edge_faces=()):
        mesh = bmesh.new()
        points = [mesh.verts.new(v) for v in verts]
        for i, face in enumerate(faces):
            poly = mesh.faces.new([points[j] for j in face])
            poly.material_index = int(i in edge_faces)
        bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
        if bevel:
            bmesh.ops.bevel(
                mesh, geom=list(mesh.edges), offset=bevel, segments=1, affect="EDGES", clamp_overlap=True, material=1
            )
        mesh.normal_update()
        mesh.verts.index_update()
        positions = [v.co.copy() for v in mesh.verts]
        polygons = [tuple(v.index for v in f.verts) for f in mesh.faces]
        edges = [bool(f.material_index) for f in mesh.faces]
        self.parts[self.parent].append((positions, polygons, edges, color, surface))
        mesh.free()

    def plate(self, outline, width, color, surface="paint", *, x=0, bevel=0.004):
        """A profiled casting or a thin inlaid marking, seen from the side."""
        n = len(outline)
        verts = [(side, f, h) for side in (x - width / 2, x + width / 2) for f, h in outline]
        faces = [tuple(range(n)), tuple(range(n, 2 * n))]
        faces.extend((i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n))
        self.piece(verts, faces, color, surface, bevel)

    def block(self, start, end, bottom, top, width, color, surface="metal", **kwargs):
        self.plate([(start, bottom), (end, bottom), (end, top), (start, top)], width, color, surface, **kwargs)

    def turned(self, origin, profile, color, surface="metal", *, axis=(0, 1, 0), sides=12, hollow=False, rims=()):
        """Turn a chamfered section around its axis. A returning profile leaves a real opening."""
        axis = Vector(axis).normalized()
        across = axis.cross(Vector((0, 0, 1)))
        if across.length < 0.01:
            across = axis.cross(Vector((0, 1, 0)))
        across.normalize()
        up = axis.cross(across)
        verts, faces, edges = [], [], set()
        for dist, radius in profile:
            center = Vector(origin) + dist * axis
            for i in range(sides):
                angle = math.tau * (i + 0.5) / sides
                verts.append(center + radius * (math.cos(angle) * across + math.sin(angle) * up))
        for k in range(len(profile) if hollow else len(profile) - 1):
            following = (k + 1) % len(profile)
            for i in range(sides):
                j = (i + 1) % sides
                if k in rims:
                    edges.add(len(faces))
                faces.append((k * sides + i, k * sides + j, following * sides + j, following * sides + i))
        if not hollow:
            faces += [tuple(range(sides)), tuple(range(len(verts) - sides, len(verts)))]
        self.piece(verts, faces, color, surface, edge_faces=edges)

    def collar(self, origin, radius, length, color, surface="metal", *, axis=(0, 1, 0), sides=12):
        lip = min(radius * 0.14, length * 0.19)
        self.turned(
            origin,
            [(0, radius - lip), (lip, radius), (length - lip, radius), (length, radius - lip)],
            color,
            surface,
            axis=axis,
            sides=sides,
            rims=(0, 2),
        )

    def hose(self, path, radius, color, surface="soft", *, sides=8, samples=2):
        geo = kit.tube(path, [radius] * len(path), sides=sides, samples=samples, caps=("flat", "flat"))
        self.piece(geo.verts, geo.faces, color, surface)

    def screws(self, positions, x, radius=0.009):
        for side in (-1, 1):
            for f, h in positions:
                self.collar((side * x, f, h), radius, 0.003, STEEL, axis=(side, 0, 0), sides=6)

    def export(self, asset):
        verts, faces = [], []
        for parts in self.parts.values():
            for points, polys, _, _, _ in parts:
                offset = len(verts)
                faces.extend(tuple(i + offset for i in poly) for poly in polys)
                verts.extend(points)
        tree = BVHTree.FromPolygons(verts, faces)
        rays = kit._hemisphere(20)
        for parent, parts in self.parts.items():
            points, polys, finishes = [], [], []
            for verts, faces, edges, color, surface in parts:
                offset = len(points)
                points.extend(verts)
                polys.extend(tuple(i + offset for i in face) for face in faces)
                finishes.extend((color, surface, edge) for edge in edges)

            mesh = bpy.data.meshes.new(parent.name + " casting")
            mesh.from_pydata(points, [], polys)
            mesh.update()
            colors = mesh.color_attributes.new("Finish", "FLOAT_COLOR", "CORNER")
            slots = list(self.materials)
            for mat in self.materials.values():
                mesh.materials.append(mat)
            shades = []
            for v in mesh.vertices:
                n = v.normal
                tangent = n.cross(Vector((0.33, 0.84, 0.43))).normalized()
                bitangent = n.cross(tangent)
                shade = 1.0
                for ray in rays:
                    direction = tangent * ray.x + bitangent * ray.y + n * ray.z
                    hit = tree.ray_cast(v.co + n * 0.0015, direction, 0.085)
                    if hit[0] is not None:
                        shade -= 0.53 * (1 - hit[3] / 0.085) / len(rays)
                grain = kit.fbm(v.co, 64, 2)
                shades.append((shade * (0.96 + 0.12 * grain), grain))
            for poly, (color, surface, edge) in zip(mesh.polygons, finishes):
                poly.material_index = slots.index(surface)
                for li in poly.loop_indices:
                    vi = mesh.loops[li].vertex_index
                    shade, grain = shades[vi]
                    rgb = linear(color)
                    if edge and surface in ("metal", "paint"):
                        # Interrupted bright metal on exposed arrises. Broad faces retain their paint.
                        wear = kit.smooth(-0.26, 0.39, grain)
                        rgb = kit.mix(rgb, linear("b7b7a9"), wear * 0.68)
                    # Rig.spawn applies CreatureLook's sRGB convention to COLOR_0.
                    colors.data[li].color = (*[kit._srgb(c * shade) for c in rgb], 1)
            mesh.color_attributes.active_color = colors
            obj = bpy.data.objects.new(mesh.name, mesh)
            bpy.context.collection.objects.link(obj)
            obj.parent = parent
            # Pieces were drawn together in model space, including the moving pump.
            obj.location = -parent.location
        bm.export(asset)


def pistol_grip(g, tape=WRAP):
    g.plate(
        [(-0.241, -0.195), (-0.170, -0.207), (-0.107, -0.069), (-0.103, -0.024), (-0.177, -0.018), (-0.203, -0.095)],
        0.048,
        DARK,
        "soft",
        bevel=0.008,
    )
    for i in range(5):
        h = -0.168 + 0.021 * i
        f = -0.17 + (h + 0.12) * 0.46
        g.plate(
            [(f - 0.036, h - 0.012), (f + 0.026, h - 0.022), (f + 0.036, h - 0.004), (f - 0.028, h + 0.007)],
            0.052,
            tape if i % 2 == 0 else RUBBER,
            "soft",
            bevel=0.003,
        )
    g.hose(
        [(0, -0.174, -0.139), (0, -0.085, -0.126), (0, -0.061, -0.098), (0, -0.053, -0.034)], 0.008, IRON, "metal", samples=2
    )
    g.hose([(0, -0.123, -0.039), (0, -0.121, -0.070), (0, -0.133, -0.083)], 0.0065, ORANGE, "paint")


def stencil_07(g):
    # Broken strokes survive as inlaid geometry after import (on both faces).
    glyphs = [
        [(0, 0.24), (0, 0.83), (0.12, 1), (0.44, 1), (0.44, 0.84), (0.21, 0.84), (0.18, 0.75), (0.18, 0.24)],
        [(0, 0.20), (0.18, 0.20), (0.21, 0.16), (0.40, 0.16), (0.44, 0.20), (0.44, 0), (0.11, 0), (0, 0.10)],
        [
            (0.51, 0),
            (0.51, 0.17),
            (0.57, 0.22),
            (0.57, 0.78),
            (0.51, 0.84),
            (0.51, 1),
            (0.63, 1),
            (0.75, 0.85),
            (0.75, 0.14),
            (0.61, 0),
        ],
        [(0.90, 0.80), (0.90, 1), (1.59, 1), (1.59, 0.84), (1.29, 0.38), (1.14, 0.38), (1.37, 0.80)],
        [(1.12, 0.32), (1.26, 0.32), (1.11, 0), (0.92, 0)],
    ]
    for side in (-1, 1):
        for stroke in glyphs:
            g.plate(
                [(-0.094 + side * (u - 0.8) * 0.045, 0.005 + v * 0.045) for u, v in stroke],
                0.0012,
                IVORY,
                x=side * 0.0573,
                bevel=0.00025,
            )


def rifle():
    g = Casting("Rifle")
    g.plate(
        [
            (-0.294, 0.055),
            (-0.27, 0.078),
            (0.094, 0.076),
            (0.142, 0.047),
            (0.162, -0.026),
            (0.101, -0.053),
            (-0.210, -0.052),
            (-0.282, -0.023),
        ],
        0.092,
        IRON,
        "metal",
        bevel=0.011,
    )
    # Bent two-sided wire stock, cheek sleeve and folding hinge.
    for side in (-1, 1):
        x = side * 0.027
        g.hose(
            [
                (x, -0.253, 0.024),
                (x, -0.335, 0.044),
                (x, -0.443, 0.049),
                (x, -0.458, 0.030),
                (x, -0.459, -0.087),
                (x, -0.443, -0.105),
                (x, -0.325, -0.059),
                (x, -0.252, -0.014),
            ],
            0.010,
            STEEL,
            "metal",
        )
    g.plate(
        [(-0.47, 0.044), (-0.452, 0.052), (-0.443, 0.038), (-0.444, -0.089), (-0.451, -0.114), (-0.47, -0.101)],
        0.068,
        RUBBER,
        "soft",
    )
    g.plate([(-0.432, 0.062), (-0.334, 0.063), (-0.302, 0.047), (-0.325, 0.031), (-0.43, 0.038)], 0.070, IVORY)
    g.screws([(-0.264, 0.010)], 0.047, 0.020)
    pistol_grip(g)
    # Battery cassette behind the grip. Gauge sits in a raised black rubber bezel.
    g.plate(
        [(-0.306, -0.023), (-0.222, -0.028), (-0.240, -0.151), (-0.263, -0.161), (-0.315, -0.144)], 0.074, IVORY, bevel=0.006
    )
    g.plate([(-0.316, -0.129), (-0.235, -0.141), (-0.239, -0.163), (-0.318, -0.153)], 0.083, IRON, "metal")
    for side in (-1, 1):
        g.block(-0.298, -0.248, -0.105, -0.067, 0.003, DARK, x=side * 0.038, bevel=0.001)
        for j in range(3):
            g.block(-0.292 + 0.014 * j, -0.282 + 0.014 * j, -0.098, -0.073, 0.002, TEAL, "lamp", x=side * 0.040, bevel=0.0007)
    g.plate(
        [
            (-0.214, 0.047),
            (-0.191, 0.065),
            (-0.023, 0.065),
            (-0.013, 0.043),
            (-0.028, -0.011),
            (-0.156, -0.018),
            (-0.207, 0.002),
        ],
        0.113,
        ORANGE,
        bevel=0.006,
    )
    stencil_07(g)
    for j in range(4):
        f = 0.004 + 0.023 * j
        g.plate(
            [(f - 0.007, -0.030), (f + 0.007, -0.030), (f + 0.018, 0.056), (f + 0.005, 0.058)],
            0.102,
            STEEL if j == 0 else IRON,
            "metal",
            bevel=0.003,
        )
    # Sight bridge, reclaimed optical tube with a hood and two mounting feet.
    g.block(-0.205, 0.083, 0.074, 0.089, 0.048, DARK, bevel=0.003)
    for f in (-0.155, -0.076):
        g.plate([(f - 0.017, 0.084), (f + 0.02, 0.084), (f + 0.009, 0.115), (f - 0.01, 0.115)], 0.042, STEEL, "metal")
    g.collar((0, -0.185, 0.13), 0.028, 0.132, IRON)
    g.collar((0, -0.198, 0.13), 0.035, 0.032, RUBBER, "soft")
    g.turned(
        (0, -0.081, 0.13),
        [(0, 0.03), (0.012, 0.040), (0.050, 0.041), (0.054, 0.038), (0.054, 0.030), (0.042, 0.029), (0, 0.024)],
        IVORY,
        "paint",
        hollow=True,
        rims=(0, 2),
    )
    g.collar((0, -0.042, 0.13), 0.029, 0.002, TEAL, "lamp")
    g.collar((0, -0.116, 0.157), 0.016, 0.015, ORANGE, "paint", axis=(0, 0, 1))
    # Five heat-sink vanes straddle an exposed dark liner; gaps are open from side to side.
    g.collar((0, 0.118, 0.010), 0.030, 0.329, DARK)
    g.plate(
        [(0.010, -0.032), (0.077, -0.104), (0.167, -0.104), (0.228, -0.037), (0.218, -0.014)],
        0.067,
        RUBBER,
        "soft",
        bevel=0.008,
    )
    for j in range(4):
        f = 0.064 + 0.025 * j
        g.plate([(f, -0.090), (f + 0.012, -0.099), (f + 0.040, -0.043), (f + 0.027, -0.039)], 0.071, WRAP, "soft", bevel=0.003)
    for j in range(5):
        f = 0.143 + 0.043 * j
        g.turned(
            (0, f, 0.010),
            [(0, 0.045), (0.008, 0.059), (0.026, 0.059), (0.032, 0.053), (0.032, 0.034), (0, 0.034)],
            IVORY,
            "paint",
            sides=8,
            hollow=True,
            rims=(0, 2),
        )
    g.block(0.136, 0.351, 0.052, 0.066, 0.028, IRON, bevel=0.003)
    g.turned(
        (0, 0.348, 0.010),
        [
            (0, 0.037),
            (0.006, 0.041),
            (0.026, 0.041),
            (0.034, 0.027),
            (0.085, 0.027),
            (0.091, 0.034),
            (0.127, 0.034),
            (0.132, 0.030),
            (0.132, 0.021),
            (0.095, 0.017),
            (0, 0.017),
        ],
        IRON,
        hollow=True,
        rims=(0, 2, 4, 6, 7),
    )
    g.screws([(-0.181, 0.041), (-0.040, 0.003)], 0.057, 0.006)
    g.export("rifle")


def scattergun():
    g = Casting("Scattergun", lamp=None)
    # Open-webbed stock with a thick, stepped recoil pad.
    g.plate(
        [
            (-0.406, 0.042),
            (-0.351, 0.061),
            (-0.184, 0.055),
            (-0.128, -0.007),
            (-0.190, -0.031),
            (-0.254, 0.012),
            (-0.356, 0.004),
            (-0.399, -0.054),
        ],
        0.088,
        IVORY,
        bevel=0.008,
    )
    g.plate(
        [
            (-0.399, -0.119),
            (-0.365, -0.125),
            (-0.227, -0.062),
            (-0.193, 0.005),
            (-0.241, 0.015),
            (-0.266, -0.036),
            (-0.375, -0.086),
        ],
        0.065,
        IRON,
        "metal",
        bevel=0.007,
    )
    g.plate(
        [
            (-0.420, 0.051),
            (-0.398, 0.060),
            (-0.379, 0.047),
            (-0.384, -0.098),
            (-0.368, -0.124),
            (-0.391, -0.141),
            (-0.420, -0.128),
        ],
        0.114,
        DARK,
        "soft",
        bevel=0.008,
    )
    for h in (-0.100, -0.064, -0.028, 0.008):
        g.block(-0.427, -0.414, h, h + 0.017, 0.101, RUBBER, "soft", bevel=0.004)
    pistol_grip(g, tape="685747")
    g.plate(
        [
            (-0.228, 0.014),
            (-0.190, 0.074),
            (-0.126, 0.090),
            (0.177, 0.081),
            (0.235, 0.045),
            (0.221, -0.015),
            (0.154, -0.043),
            (-0.165, -0.040),
        ],
        0.120,
        IRON,
        "metal",
        bevel=0.012,
    )
    g.plate(
        [(-0.189, 0.049), (-0.146, 0.080), (0.045, 0.077), (0.082, 0.061), (0.056, 0.012), (-0.166, 0.005)],
        0.129,
        IVORY,
        bevel=0.005,
    )
    # Side saddle with five copper-capped orange capsules. Opposite side carries the latch.
    g.block(-0.170, 0.049, 0.001, 0.048, 0.023, DARK, x=-0.071, bevel=0.004)
    for j in range(5):
        f = -0.154 + j * 0.042
        axis = (0, 0.24, 0.971)
        foot = Vector((-0.081, f, -0.015))
        g.collar(foot, 0.018, 0.079, ORANGE, "paint", axis=axis, sides=10)
        g.collar(foot - 0.005 * Vector(axis), 0.020, 0.020, "d0a16b", axis=axis, sides=10)
        g.collar(foot + 0.031 * Vector(axis), 0.0195, 0.012, DARK, "soft", axis=axis, sides=10)
    g.plate([(-0.159, 0.023), (-0.129, 0.060), (0.012, 0.060), (-0.003, 0.024)], 0.008, DARK, "metal", x=0.066)
    g.block(-0.121, -0.037, 0.035, 0.046, 0.017, STEEL, x=0.074, bevel=0.002)
    # Stripes lie inside a clipped enamel panel on both sides of the barrel jacket.
    g.plate(
        [(0.068, 0.059), (0.093, 0.082), (0.244, 0.080), (0.266, 0.054), (0.237, -0.011), (0.056, -0.010)],
        0.123,
        YELLOW,
        bevel=0.006,
    )
    stripe = [(0.075, -0.007), (0.105, -0.007), (0.165, 0.077), (0.135, 0.077)]
    for side in (-1, 1):
        for shift in (0, 0.063):
            g.plate([(f + shift, h) for f, h in stripe], 0.0014, DARK, "paint", x=side * 0.062, bevel=0.0004)
    # Continue the flank markings across the jacket's sloping crown.
    for f in (0.135, 0.198):
        h = 0.082 - 0.002 * (f - 0.093) / 0.151
        g.plate([(f, h - 0.0015), (f + 0.030, h - 0.0019), (f + 0.030, h + 0.0004), (f, h + 0.0008)], 0.115, DARK, bevel=0.0004)
    g.plate(
        [
            (-0.115, 0.084),
            (-0.092, 0.109),
            (-0.010, 0.109),
            (0.018, 0.080),
            (-0.007, 0.080),
            (-0.022, 0.096),
            (-0.082, 0.096),
            (-0.095, 0.084),
        ],
        0.044,
        STEEL,
        "metal",
        bevel=0.003,
    )
    g.collar((0, 0.168, 0.010), 0.046, 0.190, IRON)
    g.collar((0, 0.053, -0.052), 0.022, 0.255, STEEL)
    g.collar((0, 0.287, -0.052), 0.029, 0.035, DARK)
    pump = bm.pivot("Pump", (0, -0.04, -0.25), g.root)
    g.parent = pump
    g.plate(
        [
            (-0.012, -0.067),
            (0.015, -0.031),
            (0.211, -0.029),
            (0.235, -0.049),
            (0.207, -0.105),
            (0.025, -0.113),
            (-0.005, -0.095),
        ],
        0.100,
        "594b45",
        "soft",
        bevel=0.009,
    )
    for j in range(6):
        f = 0.003 + 0.034 * j
        g.plate(
            [(f, -0.091), (f + 0.010, -0.106), (f + 0.034, -0.050), (f + 0.023, -0.042)], 0.107, RUBBER, "soft", bevel=0.004
        )
    g.parent = g.root
    # Recessed bore behind a broad faceted bell. Pale armour covers the sloping cheeks.
    g.turned(
        (0, 0.282, 0.010),
        [
            (0, 0.053),
            (0.010, 0.065),
            (0.034, 0.065),
            (0.040, 0.059),
            (0.090, 0.070),
            (0.172, 0.110),
            (0.191, 0.111),
            (0.198, 0.105),
            (0.198, 0.083),
            (0.184, 0.080),
            (0.081, 0.041),
            (0.014, 0.036),
            (0, 0.038),
        ],
        IRON,
        sides=12,
        hollow=True,
        rims=(0, 2, 5, 6, 7),
    )
    g.turned(
        (0, 0.321, 0.010),
        [
            (0, 0.061),
            (0.008, 0.066),
            (0.050, 0.074),
            (0.128, 0.110),
            (0.135, 0.107),
            (0.135, 0.100),
            (0.047, 0.066),
            (0, 0.055),
        ],
        IVORY,
        "paint",
        sides=12,
        hollow=True,
        rims=(0, 3),
    )
    g.turned(
        (0, 0.423, 0.010),
        [(0, 0.096), (0.004, 0.101), (0.014, 0.106), (0.017, 0.102), (0.017, 0.098), (0, 0.092)],
        ORANGE,
        "paint",
        sides=12,
        hollow=True,
        rims=(0,),
    )
    g.screws([(-0.365, 0.025), (-0.275, 0.034)], 0.044, 0.009)
    g.export("scattergun")


def arc_lance():
    g = Casting("ArcLance", "22ddd6")
    # A lantern-like aft cell, visible through the gap between cast end plates.
    g.collar((0, -0.489, 0.014), 0.055, 0.213, TEAL, "lamp", sides=10)
    for f in (-0.478, -0.425, -0.350):
        g.collar((0, f, 0.014), 0.058, 0.013, COPPER, sides=10)
    g.plate(
        [
            (-0.515, 0.054),
            (-0.490, 0.092),
            (-0.453, 0.090),
            (-0.453, 0.061),
            (-0.478, 0.041),
            (-0.478, -0.024),
            (-0.449, -0.044),
            (-0.449, -0.072),
            (-0.484, -0.073),
            (-0.516, -0.045),
        ],
        0.099,
        IVORY,
        bevel=0.007,
    )
    for h in (-0.068, 0.069):
        g.plate([(-0.473, h), (-0.293, h + 0.002), (-0.256, h + 0.021), (-0.463, h + 0.018)], 0.066, IRON, "metal", bevel=0.004)
    g.plate(
        [
            (-0.463, 0.078),
            (-0.430, 0.116),
            (-0.330, 0.117),
            (-0.300, 0.082),
            (-0.320, 0.080),
            (-0.339, 0.103),
            (-0.419, 0.103),
            (-0.440, 0.078),
        ],
        0.035,
        IVORY,
        bevel=0.003,
    )
    g.plate(
        [
            (-0.321, 0.042),
            (-0.285, 0.091),
            (-0.084, 0.086),
            (-0.035, 0.052),
            (0.008, 0.024),
            (-0.029, -0.034),
            (-0.160, -0.047),
            (-0.217, -0.074),
            (-0.303, -0.047),
        ],
        0.100,
        IRON,
        "metal",
        bevel=0.010,
    )
    pistol_grip(g, tape="545251")
    g.plate(
        [
            (-0.336, -0.023),
            (-0.283, 0.094),
            (-0.255, 0.105),
            (-0.116, 0.100),
            (-0.081, 0.081),
            (-0.102, 0.031),
            (-0.162, 0.017),
            (-0.223, -0.053),
            (-0.291, -0.056),
        ],
        0.117,
        IVORY,
        bevel=0.009,
    )
    g.plate(
        [
            (-0.257, -0.056),
            (-0.223, -0.055),
            (-0.164, 0.011),
            (-0.138, 0.017),
            (-0.154, -0.013),
            (-0.205, -0.069),
            (-0.254, -0.070),
        ],
        0.116,
        ORANGE,
        bevel=0.003,
    )
    # A tilted broken orbital insignia cast into the ivory cheek.
    for side in (-1, 1):
        x = side * 0.059
        pts = [
            (x, -0.236 + 0.033 * math.cos(t) + 0.017 * math.sin(t), 0.040 + 0.018 * math.sin(t))
            for t in [i * math.tau / 12 for i in range(12)]
        ]
        g.hose(pts, 0.0026, IRON, "paint", sides=4, samples=1)
        g.hose([(x, -0.271, 0.010), (x, -0.203, 0.069)], 0.0025, IRON, "paint", sides=5, samples=1)
    # Open triangular truss. Narrow sections leave sky between the coil collars.
    for h in (-0.001, 0.036):
        g.block(-0.102, 0.352, h, h + 0.014, 0.039, IRON, bevel=0.004)
    for j in range(5):
        f = -0.067 + 0.079 * j
        g.plate([(f, -0.001), (f + 0.010, -0.001), (f + 0.049, 0.041), (f + 0.037, 0.041)], 0.034, STEEL, "metal", bevel=0.002)
    g.plate(
        [
            (0.030, -0.049),
            (0.043, -0.016),
            (0.066, 0.001),
            (0.085, -0.006),
            (0.078, -0.039),
            (0.154, -0.055),
            (0.180, -0.013),
            (0.199, -0.002),
            (0.211, -0.018),
            (0.180, -0.077),
            (0.152, -0.087),
            (0.065, -0.078),
        ],
        0.052,
        IVORY,
        bevel=0.006,
    )
    g.plate(
        [(0.064, -0.046), (0.161, -0.054), (0.175, -0.065), (0.155, -0.083), (0.062, -0.073)],
        0.058,
        RUBBER,
        "soft",
        bevel=0.004,
    )
    # Three independent open rings with chamfered ceramic shoulders and luminous windings.
    for f, r in ((0.016, 0.080), (0.136, 0.073), (0.256, 0.066)):
        section = [(-0.012, r - 0.008), (-0.006, r), (0.007, r), (0.012, r - 0.008), (0.006, r - 0.021), (-0.006, r - 0.021)]
        g.turned((0, f, 0.028), section, TEAL, "lamp", hollow=True, sides=16)
        g.turned(
            (0, f - 0.012, 0.028),
            [(-0.009, r - 0.009), (-0.004, r - 0.003), (0.004, r - 0.006), (0.002, r - 0.017), (-0.007, r - 0.017)],
            COPPER,
            hollow=True,
            sides=12,
            rims=(0, 2),
        )
        for side in (-1, 1):
            x = side * (r - 0.009)
            g.block(f - 0.017, f + 0.017, 0.017, 0.041, 0.019, DARK, x=x, bevel=0.004)
            g.hose([(side * 0.017, f, 0.031), (x, f, 0.031)], 0.006, STEEL, "metal", sides=6, samples=1)
    # Return and feed cables leave the battery below the rear yoke and climb to the first coil.
    for side in (-1, 1):
        x = side * 0.052
        cable = [
            (x * 0.70, -0.405, -0.018),
            (x * 1.10, -0.365, -0.077),
            (x * 1.30, -0.297, -0.100),
            (x * 1.33, -0.190, -0.086),
            (x * 1.24, -0.090, -0.045),
            (x * 1.36, 0.015, 0.027),
        ]
        g.hose(cable, 0.009, COPPER if side < 0 else DARK, samples=2, sides=6)
        g.hose([(a * 1.08, b, c - 0.016) for a, b, c in cable], 0.0055, DARK, samples=2, sides=6)
        for idx in (1, 3):
            along = (Vector(cable[idx + 1]) - Vector(cable[idx - 1])).normalized()
            g.collar(Vector(cable[idx]) - 0.007 * along, 0.012, 0.015, STEEL, axis=along, sides=8)

    # Fork opens vertically so its split reads in side view, centred on the shared muzzle.
    def jaw(sign, outline):
        return [(f, MUZZLE[1] + sign * h) for f, h in outline]

    for sign in (-1, 1):
        g.plate(
            jaw(
                sign,
                [
                    (0.316, 0.002),
                    (0.350, 0.002),
                    (0.386, 0.022),
                    (0.474, 0.036),
                    (0.480, 0.038),
                    (0.480, 0.046),
                    (0.409, 0.049),
                    (0.363, 0.049),
                    (0.340, 0.033),
                    (0.311, 0.030),
                ],
            ),
            0.064,
            IVORY,
            bevel=0.004,
        )
        g.plate(
            jaw(sign, [(0.343, 0.027), (0.362, 0.037), (0.389, 0.036), (0.397, 0.042), (0.360, 0.046)]),
            0.065,
            ORANGE,
            bevel=0.001,
        )
        g.plate(jaw(sign, [(0.391, 0.022), (0.461, 0.033), (0.441, 0.035), (0.405, 0.033)]), 0.058, TEAL, "lamp", bevel=0.001)
    g.collar((0, 0.288, 0.023), 0.037, 0.056, IRON, sides=8)
    g.screws([(-0.277, 0.076), (-0.262, -0.035), (-0.130, 0.073)], 0.0585, 0.0065)
    g.export("arc_lance")


BUILDERS = {"rifle": rifle, "scattergun": scattergun, "arc_lance": arc_lance}

# The standalone bpy 4.2 wheel can leave editor panels alive after glTF export.
# Release their Python classes before the wheel's native space types are destroyed.
if bpy.app.version[:2] == (4, 2) and not bpy.app.binary_path:

    @atexit.register
    def _release_background_ui():
        import addon_utils
        import bl_operators
        import bl_ui

        addon_utils.disable_all()
        bl_ui.unregister()
        bl_operators.unregister()


if __name__ == "__main__":
    assets = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    for asset in assets or BUILDERS:
        BUILDERS[asset]()
