"""Shared kit for the skinned creatures and people (build_creatures.py, build_people.py).

A creature is described in Godot space (x right, y up, -z forward, metres):

  * bones, named after what the game drives (Body, Head, LegL1, Tendril3b ...);
  * parts: closed pieces of geometry made here (swept tubes, shaped ellipsoids, sheets, shells),
    each bound to one bone rigidly or blended across a few by distance, each with a paint
    function giving its colour at a point;
  * clips: keyframed poses, written per bone as Godot degrees about the model's axes on top of
    rest, the way the older rigs' clips are written.

build() joins the parts into ONE mesh (one MeshInstance3D in the game, however many parts it
has), bakes ambient occlusion and the paint into vertex colours, and skins it to the armature.
export() writes godot/assets/models/<name>.glb and blender/<name>.blend for editing by hand.

Nothing here needs a GPU or a display: it runs under `pip install bpy==4.2.0`.
"""

import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_models as bm  # noqa: E402

FPS = 30
V = Vector


# --- Colour ------------------------------------------------------------------------------

def C(hexcol):
    """sRGB hex -> linear rgb (what vertex colours and glTF want)."""
    c = tuple(int(hexcol[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def _srgb(v):
    v = min(1.0, max(0.0, v))
    return v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


def mix(a, b, t):
    t = min(1.0, max(0.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a))) if b != a else float(x >= b)
    return t * t * (3.0 - 2.0 * t)


def fbm(p, freq=1.0, octaves=3, seed=0.0):
    """Smooth noise in -1..1."""
    q = V((p[0] * freq + seed * 17.3, p[1] * freq - seed * 9.1, p[2] * freq + seed * 3.7))
    out, amp, tot = 0.0, 1.0, 0.0
    for _ in range(octaves):
        out += noise.noise(q) * amp
        tot += amp
        amp *= 0.5
        q = q * 2.03
    return out / tot


def cells(p, freq=1.0, seed=0.0):
    """Cell noise: (distance to nearest cell centre, distance to the cell's edge), roughly 0..1."""
    q = V((p[0] * freq + seed * 11.1, p[1] * freq + seed * 5.3, p[2] * freq - seed * 7.9))
    d, _ = noise.voronoi(q)
    return d[0], d[1] - d[0]


def flat(col):
    c = C(col) if isinstance(col, str) else col
    return lambda p, n: c


def mottled(base, alt, freq=4.0, sharp=1.0, seed=0.0, belly=None, belly_at=-0.2):
    """Two colours broken up by noise; `belly` takes over where the surface faces down."""
    a = C(base) if isinstance(base, str) else base
    b = C(alt) if isinstance(alt, str) else alt
    u = (C(belly) if isinstance(belly, str) else belly) if belly else None

    def paint(p, n):
        t = 0.5 + 0.5 * fbm(p, freq, 3, seed) * sharp
        c = mix(a, b, smooth(0.25, 0.75, t))
        if u:
            c = mix(c, u, smooth(belly_at, belly_at - 0.6, n[1]))
        return c
    return paint


# --- Geometry ----------------------------------------------------------------------------

class Geo:
    """Vertices (Godot space) and faces. Closed, wound counter-clockwise seen from outside."""

    def __init__(self, verts=None, faces=None):
        self.verts = verts or []
        self.faces = faces or []

    def copy(self):
        return Geo([v.copy() for v in self.verts], list(self.faces))

    def add(self, other):
        n = len(self.verts)
        self.verts += [v.copy() for v in other.verts]
        self.faces += [tuple(i + n for i in f) for f in other.faces]
        return self

    def deform(self, fn):
        self.verts = [V(fn(v)) for v in self.verts]
        return self

    def move(self, by):
        by = V(by)
        return self.deform(lambda v: v + by)

    def scale(self, s, about=(0, 0, 0)):
        s = V((s, s, s)) if isinstance(s, (int, float)) else V(s)
        c = V(about)
        return self.deform(lambda v: c + V(((v.x - c.x) * s.x, (v.y - c.y) * s.y, (v.z - c.z) * s.z)))

    def rotate(self, deg, about=(0, 0, 0)):
        """Godot Euler degrees (y, then x, then z), about a point."""
        m = godot_basis(deg)
        c = V(about)
        return self.deform(lambda v: c + m @ (v - c))

    def mirror(self):
        """This geometry reflected across x = 0 (a new Geo)."""
        return Geo([V((-v.x, v.y, v.z)) for v in self.verts], [tuple(reversed(f)) for f in self.faces])

    def normals(self):
        out = [V((0, 0, 0)) for _ in self.verts]
        for f in self.faces:
            a, b, c = self.verts[f[0]], self.verts[f[1]], self.verts[f[2]]
            n = (b - a).cross(c - a)
            if len(f) == 4:
                n += (c - a).cross(self.verts[f[3]] - a)
            for i in f:
                out[i] += n
        return [n.normalized() if n.length > 1e-12 else V((0, 1, 0)) for n in out]

    def bumps(self, amp, freq, seed=0.0, octaves=3, mask=None):
        """Pushes the surface in and out along its normals by noise. mask(p) scales it."""
        ns = self.normals()
        self.verts = [v + n * (amp * fbm(v, freq, octaves, seed) * (mask(v) if mask else 1.0))
                      for v, n in zip(self.verts, ns)]
        return self

    def plates(self, amp, freq, seed=0.0, groove=0.12, mask=None):
        """Cell pattern: raised plates with grooves between them (hide, scales, bark)."""
        ns = self.normals()
        out = []
        for v, n in zip(self.verts, ns):
            _, edge = cells(v, freq, seed)
            k = smooth(0.0, groove, edge) - 0.6
            out.append(v + n * (amp * k * (mask(v) if mask else 1.0)))
        self.verts = out
        return self

    def inflate(self, by):
        ns = self.normals()
        self.verts = [v + n * by for v, n in zip(self.verts, ns)]
        return self

    def subdivide(self, levels=1):
        """Catmull-Clark through Blender (smooths the form as it adds faces)."""
        me = bpy.data.meshes.new("tmp")
        me.from_pydata([bm.g(*v) for v in self.verts], [], self.faces)
        b = bmesh.new()
        b.from_mesh(me)
        for _ in range(levels):
            bmesh.ops.subdivide_edges(b, edges=b.edges[:], cuts=1, use_grid_fill=True, smooth=1.0)
        b.verts.ensure_lookup_table()
        self.verts = [V((v.co.x, v.co.z, -v.co.y)) for v in b.verts]
        self.faces = [tuple(v.index for v in f.verts) for f in b.faces]
        b.free()
        bpy.data.meshes.remove(me)
        return self


def godot_basis(deg):
    """Godot Euler degrees (applied y, then x, then z) as a matrix in Godot space."""
    x, y, z = (math.radians(a) for a in deg)
    return (Matrix.Rotation(y, 3, "Y") @ Matrix.Rotation(x, 3, "X") @ Matrix.Rotation(z, 3, "Z"))


def ellipsoid(at, radii, segs=20, rings=12, fn=None, rot=None):
    """An ellipsoid, optionally shaped: fn(u) -> radius multiplier for the unit direction u
    (Godot axes, before `rot`), so lobes, ridges, flats and snouts are a line of maths each."""
    at = V(at)
    rx, ry, rz = radii if not isinstance(radii, (int, float)) else (radii, radii, radii)
    verts, faces = [], []
    verts.append(V((0, 1, 0)))
    for r in range(1, rings):
        phi = math.pi * r / rings
        for s in range(segs):
            th = 2 * math.pi * s / segs
            verts.append(V((math.sin(phi) * math.cos(th), math.cos(phi), math.sin(phi) * math.sin(th))))
    verts.append(V((0, -1, 0)))
    last = len(verts) - 1
    for s in range(segs):
        s2 = (s + 1) % segs
        faces.append((0, 1 + s2, 1 + s))
        faces.append((last, last - segs + s, last - segs + s2))
    for r in range(rings - 2):
        a = 1 + r * segs
        b = a + segs
        for s in range(segs):
            s2 = (s + 1) % segs
            faces.append((a + s, a + s2, b + s2, b + s))
    m = godot_basis(rot) if rot else None
    out = []
    for u in verts:
        k = fn(u) if fn else 1.0
        p = V((u.x * rx * k, u.y * ry * k, u.z * rz * k))
        out.append(at + (m @ p if m else p))
    return Geo(out, faces)


def _catmull(pts, samples):
    """Smooth path through pts: [(pos, radius-pair)], `samples` steps per span."""
    if samples <= 1 or len(pts) < 3:
        return pts
    out = []
    n = len(pts)
    for i in range(n - 1):
        p0 = pts[max(i - 1, 0)]
        p1, p2 = pts[i], pts[i + 1]
        p3 = pts[min(i + 2, n - 1)]
        for k in range(samples):
            t = k / samples
            t2, t3 = t * t, t * t * t
            w = (-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2)
            pos = p0[0] * w[0] + p1[0] * w[1] + p2[0] * w[2] + p3[0] * w[3]
            rad = tuple(max(1e-4, p0[1][j] * w[0] + p1[1][j] * w[1] + p2[1][j] * w[2] + p3[1][j] * w[3]) for j in (0, 1))
            out.append((pos, rad))
    out.append(pts[-1])
    return out


def tube(pts, radii, sides=8, samples=3, up=(0, 1, 0), caps=("round", "round"), profile=None):
    """A limb, tail, neck or tendril swept along a path. radii: one per point, a number or
    (across, along-`up`). caps: "round", "point" or "flat" for each end. profile(angle, t) ->
    radius multiplier shapes the cross-section (ridges, keels) along the limb (t in 0..1)."""
    path = [(V(p), (r, r) if isinstance(r, (int, float)) else tuple(r)) for p, r in zip(pts, radii)]
    path = _catmull(path, samples)
    n = len(path)
    up = V(up).normalized()
    verts, faces = [], []
    # Parallel-transported frame, so the tube never twists on itself.
    tangents = []
    for i in range(n):
        a = path[max(i - 1, 0)][0]
        b = path[min(i + 1, n - 1)][0]
        t = (b - a)
        tangents.append(t.normalized() if t.length > 1e-9 else V((0, 0, -1)))
    side = tangents[0].cross(up)
    if side.length < 1e-4:
        side = tangents[0].cross(V((1, 0, 0)))
    side.normalize()
    rings = []
    for i in range(n):
        t = tangents[i]
        side = (side - t * side.dot(t))
        if side.length < 1e-6:
            side = t.cross(up)
        side.normalize()
        upv = side.cross(t).normalized()
        pos, (ra, rb) = path[i]
        ring = []
        for s in range(sides):
            ang = 2 * math.pi * s / sides
            k = profile(ang, i / (n - 1)) if profile else 1.0
            ring.append(pos + (side * (math.cos(ang) * ra) + upv * (math.sin(ang) * rb)) * k)
        rings.append(len(verts))
        verts += ring
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for s in range(sides):
            s2 = (s + 1) % sides
            faces.append((a + s, b + s, b + s2, a + s2))
    for end, cap in ((0, caps[0]), (n - 1, caps[1])):
        pos, (ra, rb) = path[end]
        t = tangents[end] * (-1.0 if end == 0 else 1.0)
        r = min(ra, rb)
        base = rings[end]
        if cap == "round":
            # One extra shrunken ring, then a tip.
            ring2 = len(verts)
            for s in range(sides):
                p = verts[base + s]
                verts.append(pos + (p - pos) * 0.62 + t * r * 0.6)
            tip = len(verts)
            verts.append(pos + t * r * 0.85)
            for s in range(sides):
                s2 = (s + 1) % sides
                if end == 0:
                    faces.append((base + s, base + s2, ring2 + s2, ring2 + s))
                    faces.append((ring2 + s, ring2 + s2, tip))
                else:
                    faces.append((base + s, ring2 + s, ring2 + s2, base + s2))
                    faces.append((ring2 + s, tip, ring2 + s2))
        else:
            tip = len(verts)
            verts.append(pos + (t * r * 1.6 if cap == "point" else V((0, 0, 0))))
            for s in range(sides):
                s2 = (s + 1) % sides
                faces.append((base + s, base + s2, tip) if end == 0 else (base + s, tip, base + s2))
    return Geo(verts, faces)


def spike(base, tip, radius, sides=6, bend=None):
    """A horn, claw, tooth or spine. bend: a point the spike curves toward on the way."""
    base, tip = V(base), V(tip)
    mid = (base + tip) * 0.5 if bend is None else (base + tip) * 0.25 + V(bend) * 0.5
    return tube([base, mid, tip], [radius, radius * 0.6, radius * 0.08], sides=sides, samples=3,
                caps=("flat", "point"))


def sheet(edge_a, edge_b, nv=4, thick=0.02, camber=None, taper=1.0):
    """A wing membrane, fin, frill or plate stretched between two edges (lists of points, same
    length). camber(u, v) lifts it along its normal; the far edge thins by `taper`."""
    a = [V(p) for p in edge_a]
    b = [V(p) for p in edge_b]
    nu = len(a)
    grid = []
    for i in range(nu):
        row = []
        for j in range(nv + 1):
            row.append(a[i].lerp(b[i], j / nv))
        grid.append(row)
    # A rough normal for the whole sheet.
    nrm = V((0, 0, 0))
    for i in range(nu - 1):
        nrm += (grid[i + 1][0] - grid[i][0]).cross(grid[i][nv] - grid[i][0])
    nrm = nrm.normalized() if nrm.length > 1e-9 else V((0, 1, 0))
    top, bot = [], []
    for i in range(nu):
        for j in range(nv + 1):
            u, v = i / max(nu - 1, 1), j / nv
            p = grid[i][j] + (nrm * camber(u, v) if camber else V((0, 0, 0)))
            edge = min(u, 1 - u, v, 1 - v)
            t = thick * (1.0 + (taper - 1.0) * v) * (0.35 + 0.65 * smooth(0.0, 0.18, edge))
            top.append(p + nrm * t * 0.5)
            bot.append(p - nrm * t * 0.5)
    w = nv + 1
    verts = top + bot
    off = len(top)
    faces = []
    for i in range(nu - 1):
        for j in range(nv):
            q = (i * w + j, i * w + j + 1, (i + 1) * w + j + 1, (i + 1) * w + j)
            faces.append(q)
            faces.append(tuple(off + k for k in reversed(q)))
    # Stitch the rim.
    rim = [i * w for i in range(nu)] + [(nu - 1) * w + j for j in range(1, w)] + \
          [i * w + nv for i in range(nu - 2, -1, -1)] + [j for j in range(nv - 1, 0, -1)]
    for k in range(len(rim)):
        p, q = rim[k], rim[(k + 1) % len(rim)]
        faces.append((q, p, off + p, off + q))
    return Geo(verts, faces)


def shell(at, radii, cover=0.5, thick=0.04, segs=16, rings=8, fn=None, rot=None, lip=0.0):
    """An armour plate: the top `cover` (0..1) of an ellipsoid, as a thick curved slab. `lip`
    flares the rim outward. Lies over a body the way a carapace segment does."""
    at = V(at)
    rx, ry, rz = radii
    m = godot_basis(rot) if rot else None
    phi_max = math.pi * cover
    outer, inner = [], []
    for r in range(rings + 1):
        phi = phi_max * r / rings
        for s in range(segs):
            if r == 0 and s > 0:
                continue
            th = 2 * math.pi * s / segs
            u = V((math.sin(phi) * math.cos(th), math.cos(phi), math.sin(phi) * math.sin(th)))
            k = (fn(u) if fn else 1.0) * (1.0 + lip * smooth(0.6, 1.0, r / rings))
            p = V((u.x * rx * k, u.y * ry * k, u.z * rz * k))
            q = p - V((u.x, u.y, u.z)) * thick
            outer.append(at + (m @ p if m else p))
            inner.append(at + (m @ q if m else q))
    verts = outer + inner
    off = len(outer)

    def idx(r, s):
        return 0 if r == 0 else 1 + (r - 1) * segs + (s % segs)
    faces = []
    for s in range(segs):
        faces.append((0, idx(1, s + 1), idx(1, s)))
        faces.append((off, off + idx(1, s), off + idx(1, s + 1)))
    for r in range(1, rings):
        for s in range(segs):
            q = (idx(r, s), idx(r, s + 1), idx(r + 1, s + 1), idx(r + 1, s))
            faces.append(q)
            faces.append(tuple(off + k for k in reversed(q)))
    for s in range(segs):
        a, b = idx(rings, s), idx(rings, s + 1)
        faces.append((a, b, off + b, off + a))
    return Geo(verts, faces)


def lathe(profile, at=(0, 0, 0), segs=12, rot=None, squash=1.0):
    """A shape turned about the y axis from a profile [(radius, height)], bottom to top."""
    at = V(at)
    m = godot_basis(rot) if rot else None
    verts, faces = [], []
    for r, h in profile:
        for s in range(segs):
            th = 2 * math.pi * s / segs
            p = V((math.cos(th) * r, h, math.sin(th) * r * squash))
            verts.append(at + (m @ p if m else p))
    n = len(profile)
    for i in range(n - 1):
        for s in range(segs):
            s2 = (s + 1) % segs
            faces.append((i * segs + s, (i + 1) * segs + s, (i + 1) * segs + s2, i * segs + s2))
    for i, flip in ((0, False), (n - 1, True)):
        c = len(verts)
        p = V((0, profile[i][1], 0))
        verts.append(at + (m @ p if m else p))
        for s in range(segs):
            s2 = (s + 1) % segs
            faces.append((i * segs + s2, c, i * segs + s) if flip else (i * segs + s, c, i * segs + s2))
    return Geo(verts, faces)


def hollow(profile, at=(0, 0, 0), segs=16, rot=None, fn=None):
    """A walled, open-ended shape turned about the y axis: `profile` is a closed loop of
    (radius, height) going up the outside and back down the inside (a pipe, a bell, a collar).
    fn(angle, radius, height) -> radius reshapes it round the turn (flutes, lobes)."""
    at = V(at)
    m = godot_basis(rot) if rot else None
    verts, faces = [], []
    n = len(profile)
    for r, h in profile:
        for s in range(segs):
            th = 2 * math.pi * s / segs
            rr = fn(th, r, h) if fn else r
            p = V((math.cos(th) * rr, h, math.sin(th) * rr))
            verts.append(at + (m @ p if m else p))
    for i in range(n):
        j = (i + 1) % n
        for s in range(segs):
            s2 = (s + 1) % segs
            faces.append((i * segs + s, j * segs + s, j * segs + s2, i * segs + s2))
    return Geo(verts, faces)


def slab(size, at=(0, 0, 0), rot=None, bevel=0.0, taper=None):
    """A box (Godot axes), optionally bevelled, with the -z (front) face scaled by taper=(sx, sy)."""
    sx, sy, sz = (s * 0.5 for s in size)
    me = bpy.data.meshes.new("tmp")
    b = bmesh.new()
    bmesh.ops.create_cube(b, size=1.0)
    for v in b.verts:
        x, y, z = v.co.x * 2, v.co.z * 2, -v.co.y * 2
        if taper and z < 0:
            x *= taper[0]
            y *= taper[1]
        v.co = bm.g(x * sx, y * sy, z * sz)
    if bevel > 0.0:
        bmesh.ops.bevel(b, geom=b.edges[:], offset=bevel, segments=2, affect="EDGES", profile=0.6)
    b.verts.ensure_lookup_table()
    geo = Geo([V((v.co.x, v.co.z, -v.co.y)) for v in b.verts], [tuple(v.index for v in f.verts) for f in b.faces])
    b.free()
    bpy.data.meshes.remove(me)
    if rot:
        geo.rotate(rot)
    return geo.move(at)


# --- The creature ------------------------------------------------------------------------

# Hemisphere directions for the ambient occlusion bake (z is the surface normal).
def _hemisphere(n, seed=3):
    rng = random.Random(seed)
    out = []
    for i in range(n):
        u, v = (i + rng.random()) / n, rng.random()
        r = math.sqrt(u)
        th = 2 * math.pi * v
        out.append(V((r * math.cos(th), r * math.sin(th), math.sqrt(max(0.0, 1 - u)))))
    return out


class Creature:
    def __init__(self, name, root="Root"):
        bm.reset()
        bpy.context.scene.render.fps = FPS
        self.name = name
        self.root = root
        self.bones = {}
        self.order = []
        self.parts = []
        self.mats = {}
        self.arm = None
        self.mesh = None
        self.bone(root, (0, 0, 0), (0, 0.2, 0), None, deform=False)

    # --- Skeleton ---

    def bone(self, name, head, tail, parent=None, deform=True):
        """A bone from head to tail (Godot space). parent defaults to the root."""
        if parent is None and name != self.root:
            parent = self.root
        self.bones[name] = (V(head), V(tail), parent, deform)
        self.order.append(name)
        return name

    def chain(self, prefix, pts, parent=None, suffixes="abcdefgh"):
        """Bones through a run of points: prefix+a, prefix+b ... each parented to the last."""
        names = []
        for i in range(len(pts) - 1):
            n = prefix + suffixes[i]
            self.bone(n, pts[i], pts[i + 1], parent if i == 0 else names[-1])
            names.append(n)
        return names

    # --- Materials and parts ---

    def material(self, key, rough=0.6, metal=0.0, emit=None, energy=0.0, alpha=1.0):
        """A surface of the finished mesh. Base colour comes from the paint (vertex colours)."""
        m = bpy.data.materials.new(key)
        m.use_nodes = True
        nodes = m.node_tree.nodes
        p = nodes["Principled BSDF"]
        # The paint is stored sRGB-encoded (the game keeps vertex colours in 8 bits, and linear
        # values would band in the darks); the gamma node shows it right in Blender, and the game
        # reads it as sRGB (creature_look.gd).
        attr = nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        gamma = nodes.new("ShaderNodeGamma")
        gamma.inputs["Gamma"].default_value = 2.2
        m.node_tree.links.new(attr.outputs["Color"], gamma.inputs["Color"])
        m.node_tree.links.new(gamma.outputs["Color"], p.inputs["Base Color"])
        p.inputs["Roughness"].default_value = rough
        p.inputs["Metallic"].default_value = metal
        if emit:
            p.inputs["Emission Color"].default_value = (*C(emit), 1.0)
            p.inputs["Emission Strength"].default_value = energy
        if alpha < 1.0:
            p.inputs["Alpha"].default_value = alpha
            m.blend_method = "BLEND"
        self.mats[key] = m
        return key

    def part(self, geo, bones, mat, paint, ao=True, hard=0.0, falloff=4.0):
        """Adds a piece. bones: one name (moves rigidly with it) or a list (blended by distance
        to each bone, sharper with a higher `falloff`). hard: split edges sharper than this
        many degrees, for plates and machined parts."""
        if isinstance(paint, str):
            paint = flat(paint)
        self.parts.append({"geo": geo, "bones": [bones] if isinstance(bones, str) else list(bones),
                           "mat": mat, "paint": paint, "ao": ao, "hard": hard, "falloff": falloff})
        return geo

    def both(self, fn):
        """Calls fn(side_name, sign) for the left (-x) and right (+x) sides."""
        for side, s in (("L", -1.0), ("R", 1.0)):
            fn(side, s)

    # --- Build ---

    def _weights(self, part, verts):
        bones = part["bones"]
        if len(bones) == 1:
            return [[(bones[0], 1.0)] for _ in verts]
        segs = [(b, self.bones[b][0], self.bones[b][1]) for b in bones]
        out = []
        for v in verts:
            ws = []
            for name, h, t in segs:
                ab = t - h
                k = max(0.0, min(1.0, (v - h).dot(ab) / max(ab.length_squared, 1e-9)))
                d = (v - (h + ab * k)).length
                ws.append((name, 1.0 / (d + 0.01) ** part["falloff"]))
            ws.sort(key=lambda w: -w[1])
            ws = ws[:3]
            tot = sum(w for _, w in ws)
            out.append([(n, w / tot) for n, w in ws if w / tot > 0.02])
        return out

    def build(self, ao_reach=None, ao_floor=0.28, ao_samples=14):
        objs = []
        slots = []
        for i, part in enumerate(self.parts):
            geo = part["geo"]
            me = bpy.data.meshes.new("part%d" % i)
            me.from_pydata([bm.g(*v) for v in geo.verts], [], geo.faces)
            me.update()
            b = bmesh.new()
            b.from_mesh(me)
            bmesh.ops.recalc_face_normals(b, faces=b.faces[:])
            b.to_mesh(me)
            b.free()
            obj = bpy.data.objects.new("part%d" % i, me)
            bpy.context.collection.objects.link(obj)
            for p in me.polygons:
                p.use_smooth = True
            me.materials.append(self.mats[part["mat"]])
            # Paint (per vertex, from the unsplit surface so normals are smooth).
            col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
            ns = geo.normals()
            # recalc may have flipped the winding relative to ours; use Blender's normals' sign.
            for vi, v in enumerate(geo.verts):
                bn = me.vertices[vi].normal
                n = V((bn.x, bn.z, -bn.y))
                c = part["paint"](v, n if n.length > 0.1 else ns[vi])
                col.data[vi].color = (c[0], c[1], c[2], 1.0)
            flag = me.attributes.new("ao", "FLOAT", "POINT")
            for vi in range(len(geo.verts)):
                flag.data[vi].value = 1.0 if part["ao"] else 0.0
            for vi, ws in enumerate(self._weights(part, geo.verts)):
                for name, w in ws:
                    vg = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                    vg.add([vi], w, "REPLACE")
            if part["hard"] > 0.0:
                b = bmesh.new()
                b.from_mesh(me)
                lim = math.radians(part["hard"])
                sharp = [e for e in b.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim]
                bmesh.ops.split_edges(b, edges=sharp)
                b.to_mesh(me)
                b.free()
            objs.append(obj)
            slots.append(part["mat"])
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        mesh = objs[0]
        mesh.name = self.name.title().replace("_", "") + "Mesh"
        mesh.data.name = mesh.name
        self.mesh = mesh
        mesh.data.color_attributes.active_color = mesh.data.color_attributes["Col"]
        mesh.data.color_attributes.render_color_index = mesh.data.color_attributes.find("Col")
        self._bake_ao(mesh, ao_reach, ao_floor, ao_samples)
        mesh.data.attributes.remove(mesh.data.attributes["ao"])
        self._armature()
        mesh.parent = self.arm
        mod = mesh.modifiers.new("Armature", "ARMATURE")
        mod.object = self.arm
        tris = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
        print("%s: %d parts, %d verts, %d tris, %d bones, %d surfaces" % (
            self.name, len(self.parts), len(mesh.data.vertices), tris, len(self.order), len(mesh.data.materials)))
        return mesh

    def _bake_ao(self, mesh, reach, floor, samples):
        """Darkens creases and undersides: rays from every vertex, counted against the whole
        creature, multiplied into the paint. Costs nothing at run time."""
        me = mesh.data
        me.update()
        tree = BVHTree.FromPolygons([v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
        if reach is None:
            size = max((max(v.co[i] for v in me.vertices) - min(v.co[i] for v in me.vertices)) for i in range(3))
            reach = size * 0.22
        dirs = _hemisphere(samples)
        col = me.color_attributes["Col"]
        flag = me.attributes["ao"]
        for vi, v in enumerate(me.vertices):
            if flag.data[vi].value < 0.5:
                continue
            n = v.normal
            t = n.cross(V((0.3, 0.9, 0.2)))
            if t.length < 1e-4:
                t = n.cross(V((1, 0, 0)))
            t.normalize()
            bt = n.cross(t)
            start = v.co + n * (reach * 0.02 + 0.004)
            occ = 0.0
            for d in dirs:
                w = t * d.x + bt * d.y + n * d.z
                hit = tree.ray_cast(start, w, reach)
                if hit[0] is not None:
                    occ += 1.0 - 0.6 * (hit[3] / reach)
            k = 1.0 - occ / samples
            k = floor + (1.0 - floor) * k
            c = col.data[vi].color
            col.data[vi].color = (c[0] * k, c[1] * k, c[2] * k, 1.0)
        for d in col.data:
            c = d.color
            d.color = (_srgb(c[0]), _srgb(c[1]), _srgb(c[2]), 1.0)

    def _armature(self):
        data = bpy.data.armatures.new(self.name.title().replace("_", "") + "Skeleton")
        arm = bpy.data.objects.new(self.name.title().replace("_", "") + "Rig", data)
        bpy.context.collection.objects.link(arm)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        for name in self.order:
            head, tail, parent, deform = self.bones[name]
            b = data.edit_bones.new(name)
            b.head = bm.g(*head)
            b.tail = bm.g(*tail)
            b.roll = 0.0
            b.use_deform = deform
        for name in self.order:
            parent = self.bones[name][2]
            if parent:
                data.edit_bones[name].parent = data.edit_bones[parent]
                data.edit_bones[name].use_connect = False
        bpy.ops.object.mode_set(mode="OBJECT")
        self.arm = arm

    # --- Animation ---

    def leg_ik(self, upper, lower, foot, hip_offset=(0, 0, 0), carried=None):
        """Poses a two-bone leg so the tip of `lower` lands on `foot` (model space), with the
        hip moved by `hip_offset` (whatever the body is doing in this pose) and, if the body is
        also turned, `carried` = that turn as a Rot. The knee stays on the side it rests on.
        Returns {upper: Rot, lower: Rot} to merge into a pose."""
        h0, k0 = self.bones[upper][0], self.bones[upper][1]
        f0 = self.bones[lower][1]
        cm = carried.m if carried is not None else Matrix.Identity(3)
        h = h0 + V(hip_offset)
        a, b = (k0 - h0).length, (f0 - k0).length
        to = V(foot) - h
        d = min(max(to.length, abs(a - b) + 1e-4), (a + b) * 0.999)
        dirv = to.normalized()
        pole = cm @ (k0 - h0)
        n = pole - dirv * pole.dot(dirv)
        n = n.normalized() if n.length > 1e-6 else V((0, 1, 0))
        cos_a = (a * a + d * d - b * b) / (2 * a * d)
        sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
        knee = h + (dirv * cos_a + n * sin_a) * a
        tip = h + dirv * d
        r1 = (k0 - h0).rotation_difference(knee - h).to_matrix()
        r2 = (f0 - k0).rotation_difference(tip - knee).to_matrix()
        return {upper: Rot(cm.inverted() @ r1), lower: Rot(r1.inverted() @ r2)}

    def _key(self, frame, pose, offsets, scales, prev):
        for pb in self.arm.pose.bones:
            rest = pb.bone.matrix_local.to_3x3()
            d = pose.get(pb.name, (0, 0, 0))
            delta = _TO_BLENDER @ d.m @ _TO_BLENDER.inverted() if isinstance(d, Rot) else _godot_rot(d)
            q = (rest.inverted() @ delta @ rest).to_quaternion()
            if pb.name in prev:
                q.make_compatible(prev[pb.name])
            prev[pb.name] = q.copy()
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.location = rest.inverted() @ bm.g(*offsets.get(pb.name, (0, 0, 0)))
            pb.keyframe_insert("location", frame=frame)
            s = scales.get(pb.name, 1.0)
            pb.scale = (s, s, s) if isinstance(s, (int, float)) else s
            pb.keyframe_insert("scale", frame=frame)

    def clip(self, name, keys):
        """keys: [(frame, pose)] or [(frame, pose, offsets)] or [(frame, pose, offsets, scales)].
        pose {bone: (x, y, z) Godot degrees about the model's axes, on top of rest and of whatever
        the parent is doing}; offsets {bone: (x, y, z) metres}; scales {bone: s}."""
        arm = self.arm
        act = bpy.data.actions.new(name)
        arm.animation_data_create()
        arm.animation_data.action = act
        prev = {}
        for key in keys:
            frame, pose = key[0], key[1]
            offsets = key[2] if len(key) > 2 and key[2] else {}
            scales = key[3] if len(key) > 3 and key[3] else {}
            self._key(frame, pose, offsets, scales, prev)
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
        for pb in arm.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
            pb.scale = (1, 1, 1)
        return act

    def cycle(self, name, frames, fn, steps=8):
        """A looping clip sampled from fn(phase 0..2pi) -> pose | (pose, offsets) | (pose, offsets,
        scales); the last key repeats the first."""
        keys = []
        for i in range(steps + 1):
            out = fn(2 * math.pi * (i % steps) / steps)
            out = out if isinstance(out, tuple) else (out,)
            keys.append((round(frames * i / steps),) + out)
        return self.clip(name, keys)

    def export(self):
        os.makedirs(bm.OUT, exist_ok=True)
        path = os.path.join(bm.OUT, self.name + ".glb")
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, use_selection=True,
                                  export_animations=True, export_animation_mode="NLA_TRACKS",
                                  export_force_sampling=True, export_frame_range=False,
                                  export_def_bones=False, export_optimize_animation_size=False,
                                  export_vertex_color="ACTIVE", export_all_vertex_colors=False)
        print("exported", os.path.relpath(path, bm.ROOT))
        blend = os.path.join(bm.ROOT, "blender", self.name + ".blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
        print("saved", os.path.relpath(blend, bm.ROOT))


def _godot_rot(deg):
    """Godot Euler degrees (applied y, then x, then z, as Node3D does) -> Blender-space matrix."""
    x, y, z = (math.radians(a) for a in deg)
    rx = Matrix.Rotation(x, 3, V((1, 0, 0)))
    ry = Matrix.Rotation(y, 3, V((0, 0, 1)))
    rz = Matrix.Rotation(z, 3, V((0, -1, 0)))
    return ry @ rx @ rz


class Rot:
    """A rotation given outright (a 3x3 matrix in Godot space) instead of as Euler degrees:
    what leg_ik() returns, and what axis() builds."""

    def __init__(self, m):
        self.m = m


def axis(direction, deg):
    """A turn of `deg` degrees about any axis (Godot space)."""
    return Rot(Matrix.Rotation(math.radians(deg), 3, V(direction).normalized()))


# Godot axes -> Blender axes: (x, y, z) -> (x, -z, y).
_TO_BLENDER = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def merge(*dicts):
    """Adds poses (or offsets) together. Euler degrees add; where either side is a Rot the two
    turns are composed, the earlier one outermost."""
    out = {}
    for d in dicts:
        for k, v in d.items():
            if k not in out:
                out[k] = v
                continue
            a = out[k]
            if isinstance(a, Rot) or isinstance(v, Rot):
                am = a.m if isinstance(a, Rot) else godot_basis(a)
                vm = v.m if isinstance(v, Rot) else godot_basis(v)
                out[k] = Rot(am @ vm)
            else:
                out[k] = (a[0] + v[0], a[1] + v[1], a[2] + v[2])
    return out
