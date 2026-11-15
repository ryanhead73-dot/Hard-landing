"""Builds the skinned wildlife with creature_kit and exports each as a GLB with its clips.

    python blender/build_creatures.py              # all of them (with `pip install bpy==4.2.0`)
    python blender/build_creatures.py -- drifter   # just one

Each creature is one skinned mesh on one armature, painted in vertex colour, with keyframed
clips named after the states its script reports (creature_animator.gd plays the clip that
matches the state, blends idle and walk by speed, and fires attack / hurt as one-shots).
Output: godot/assets/models/<name>.glb and blender/<name>.blend.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from creature_kit import (C, Creature, Gait, Rot, V, axis, cells, ellipsoid, fbm, flat, hollow, lathe, merge, mix, mottled,  # noqa: E402,F401
                          sheet, shell, slab, smooth, spike, tube)

TAU = 2 * math.pi


def ring(n, radius, y=0.0, phase=0.0):
    """n points round a circle in the xz plane: [(angle, Vector)]."""
    return [(TAU * i / n + phase, V((math.cos(TAU * i / n + phase) * radius, y, math.sin(TAU * i / n + phase) * radius)))
            for i in range(n)]


# --- Drifter -----------------------------------------------------------------------------

def drifter():
    """Shatterlands drifter: a spore bladder the size of a barrel. A ribbed violet membrane you
    can see the teal core through, a leathery cap studded with spore pustules, a frilled skirt
    round the vent underneath, and long trailing tendrils. Origin is the core (its weak spot)."""
    c = Creature("drifter")
    c.material("drifter_membrane", rough=0.22, emit="b49cff", energy=0.12, alpha=0.62)
    c.material("drifter_hide", rough=0.7)
    c.material("drifter_core", rough=0.3, emit="3fd1b5", energy=1.3)
    c.material("drifter_glow", rough=0.4, emit="b9a4ff", energy=0.7)

    c.bone("Sac", (0, -0.3, 0), (0, 0.5, 0))
    c.bone("Core", (0, -0.12, 0), (0, 0.16, 0))
    c.bone("Cap", (0, 0.45, 0), (0, 0.8, 0), "Sac")
    c.bone("Skirt", (0, -0.5, 0), (0, -0.75, 0), "Sac")

    LOBES = 9

    def lobes(u):
        # Vertical ribs like a gourd; flatter underneath, a soft point on top.
        th = math.atan2(u.z, u.x)
        rib = 0.5 + 0.5 * math.cos(th * LOBES)
        side = 1.0 - abs(u.y) ** 1.5
        k = 1.0 + 0.085 * (rib ** 0.7 - 0.6) * side
        if u.y < 0:
            k *= 1.0 - 0.14 * (-u.y) ** 2
        else:
            k *= 1.0 + 0.06 * u.y ** 6
        return k

    def membrane_paint(p, n):
        th = math.atan2(p.z, p.x)
        rib = 0.5 + 0.5 * math.cos(th * LOBES)
        base = mix(C("6f58c9"), C("c5b2ff"), smooth(-0.5, 0.6, p.y))
        # Darker veins down the grooves, branching a little.
        vein = smooth(0.22, 0.0, rib) * 0.75 + smooth(0.55, 0.75, 0.5 + 0.5 * fbm(p, 9.0, 2, 1.0)) * 0.25
        return mix(base, C("3a2a80"), vein * 0.8)

    sac = ellipsoid((0, 0, 0), (0.7, 0.64, 0.7), segs=36, rings=20, fn=lobes)
    sac.bumps(0.012, 5.0, 0.3, 2)
    c.part(sac, "Sac", "drifter_membrane", membrane_paint, ao=False)

    # The cap: leathery, overlapping the top of the bladder, with a scalloped lip.
    def cap_fn(u):
        th = math.atan2(u.z, u.x)
        return 1.0 + 0.05 * math.cos(th * LOBES) * (1.0 - u.y) + 0.03 * fbm(u, 3.0, 2, 4.0)

    cap = shell((0, 0.02, 0), (0.74, 0.7, 0.74), cover=0.36, thick=0.05, segs=36, rings=7, fn=cap_fn, lip=0.07)
    cap.plates(0.014, 7.0, 2.0)
    c.part(cap, ["Sac", "Cap"], "drifter_hide",
           mottled("2c2350", "55408f", freq=5.0, seed=2.0), falloff=2.0)
    # Spore pustules on the cap: little glowing blisters, bigger toward the crown.
    for i, (a, _) in enumerate(ring(7, 1.0, phase=0.3)):
        for j, tilt in enumerate((0.34, 0.62)):
            if j == 1 and i % 2:
                continue
            aa = a + j * 0.45
            d = V((math.cos(aa) * math.sin(tilt * 1.5), math.cos(tilt * 1.5), math.sin(aa) * math.sin(tilt * 1.5)))
            at = V((d.x * 0.74, d.y * 0.7 + 0.02, d.z * 0.74))
            r = 0.05 - 0.012 * j + 0.008 * (i % 3)
            c.part(ellipsoid(at, (r, r * 0.8, r), segs=8, rings=5), "Cap", "drifter_glow", "d9ccff", ao=False)
    c.part(ellipsoid((0, 0.7, 0), (0.1, 0.07, 0.1), segs=10, rings=6), "Cap", "drifter_glow", "e6dcff", ao=False)

    # The collar and vent underneath, and a frilled skirt of lappets hanging from it.
    collar = lathe([(0.2, -0.72), (0.34, -0.66), (0.42, -0.56), (0.4, -0.47), (0.3, -0.44), (0.16, -0.5), (0.12, -0.62)], segs=24)
    collar.bumps(0.012, 9.0, 5.0, 2)
    c.part(collar, ["Sac", "Skirt"], "drifter_hide", mottled("2a2150", "4a3a86", freq=7.0, seed=3.0), falloff=2.0)
    N_FRILL = 14
    for i, (a, _) in enumerate(ring(N_FRILL, 1.0)):
        w = TAU / N_FRILL * 0.62
        drop = 0.24 + 0.07 * ((i * 5) % 3)
        ea, eb = [], []
        for k in range(4):
            aa = a - w * 0.5 + w * k / 3
            ea.append((math.cos(aa) * 0.4, -0.56, math.sin(aa) * 0.4))
            flare = 0.47 + 0.03 * math.sin(k * 2.1 + i)
            sag = drop * (1.0 - 0.45 * abs(k - 1.5) / 1.5)
            eb.append((math.cos(aa) * flare, -0.56 - sag, math.sin(aa) * flare))
        frill = sheet(ea, eb, nv=3, thick=0.022, taper=0.4)
        c.part(frill, ["Skirt"], "drifter_hide",
               lambda p, n: mix(C("43347c"), C("9a86e0"), smooth(-0.6, -0.86, p.y)))

    # The core: a knotted teal organ hung in the middle, on a stalk from the vent.
    def core_fn(u):
        return 1.0 + 0.16 * math.sin(u.x * 7.0 + 1.0) * math.sin(u.y * 6.0) * math.sin(u.z * 7.0 + 2.0)

    core = ellipsoid((0, 0.0, 0), (0.2, 0.24, 0.2), segs=22, rings=14, fn=core_fn)
    c.part(core, "Core", "drifter_core",
           lambda p, n: mix(C("1c8f7c"), C("7df5dc"), 0.5 + 0.5 * fbm(p, 12.0, 2, 6.0)), ao=False)
    c.part(tube([(0, -0.2, 0), (0.03, -0.38, 0.02), (0, -0.56, 0)], [0.05, 0.035, 0.06], sides=7),
           ["Core", "Skirt"], "drifter_hide", "2a2150", falloff=2.0)

    # Tendrils: six long ones with four bones each, six short feelers between them.
    long_names = []
    for i, (a, _) in enumerate(ring(6, 1.0, phase=0.2)):
        length = 1.55 + 0.3 * (i % 2)
        dx, dz = math.cos(a), math.sin(a)
        pts = []
        for k in range(5):
            t = k / 4
            out = 0.3 + 0.1 * math.sin(t * 2.6)
            pts.append(V((dx * out, -0.6 - length * t, dz * out)))
        names = c.chain("Tendril%d" % (i + 1), pts, "Skirt")
        long_names.append(names)
        radii = [0.055, 0.045, 0.034, 0.024, 0.012]
        t_geo = tube(pts, radii, sides=7, samples=4, caps=("round", "round"),
                     profile=lambda ang, t: 1.0 + 0.18 * math.sin(t * 46.0))
        c.part(t_geo, names, "drifter_hide",
               lambda p, n: mix(C("3b2d70"), C("8f7ad8"), smooth(-1.0, -2.3, p.y)), falloff=3.0)
        tip = pts[-1]
        c.part(ellipsoid(tip, (0.035, 0.05, 0.035), segs=8, rings=5), names[-1], "drifter_glow", "d9ccff", ao=False)
    short_names = []
    for i, (a, _) in enumerate(ring(6, 1.0, phase=0.2 + TAU / 12)):
        dx, dz = math.cos(a), math.sin(a)
        pts = [V((dx * 0.2, -0.62, dz * 0.2)), V((dx * 0.24, -0.9, dz * 0.24)), V((dx * 0.2, -1.2, dz * 0.2))]
        names = c.chain("Feeler%d" % (i + 1), pts, "Skirt")
        short_names.append(names)
        c.part(tube(pts, [0.03, 0.022, 0.008], sides=6, samples=3), names, "drifter_hide",
               lambda p, n: mix(C("4a3a86"), C("a996ea"), smooth(-0.7, -1.2, p.y)), falloff=3.0)

    c.build()

    def tendrils(ph, amp, trail=0.0, flare=0.0, curl=0.0):
        """A wave running down every tendril. trail leans them back (+z), flare splays them
        out from the centre, curl rolls the tips up."""
        pose = {}
        for i, names in enumerate(long_names):
            a = TAU * i / 6 + 0.2
            dx, dz = math.cos(a), math.sin(a)
            for k, n in enumerate(names):
                w = math.sin(ph - k * 1.1 + i * 1.7) * amp * (0.5 + 0.35 * k)
                # Splaying outward: rotate about the horizontal axis square to the radial.
                out = -(flare * (1.0 if k == 0 else 0.35) + curl * k * 0.6)
                pose[n] = (w * dz + out * dz + trail * (0.6 if k == 0 else 0.25),
                           0.0,
                           -w * dx - out * dx)
        for i, names in enumerate(short_names):
            a = TAU * i / 6 + 0.2 + TAU / 12
            dx, dz = math.cos(a), math.sin(a)
            for k, n in enumerate(names):
                w = math.sin(ph * 2.0 - k * 1.3 + i) * amp * 0.8
                out = -(flare * 0.7 + curl * k)
                pose[n] = (w * dz + out * dz + trail * 0.4, 0.0, -w * dx - out * dx)
        return pose

    c.cycle("idle", 96, lambda ph: (
        merge(tendrils(ph, 7.0), {"Cap": (2.0 * math.sin(ph), 0, 2.0 * math.cos(ph))}),
        {"Core": (0, 0.02 * math.sin(ph * 2), 0)},
        {"Sac": 1.0 + 0.035 * math.sin(ph), "Core": 1.0 + 0.06 * math.sin(ph * 2 + 1.0),
         "Skirt": 1.0 - 0.05 * math.sin(ph)}), steps=12)
    # Drifting: the skirt pumps like a jellyfish and the tendrils stream.
    c.cycle("walk", 40, lambda ph: (
        tendrils(ph, 11.0, trail=5.0, flare=8.0 * math.sin(ph)),
        {"Skirt": (0, 0.03 * math.sin(ph), 0)},
        {"Sac": 1.0 + 0.05 * math.sin(ph + 0.5), "Skirt": 1.0 - 0.14 * math.sin(ph),
         "Core": 1.0 + 0.08 * math.sin(ph * 2)}), steps=10)
    # Swelling to burst (1.1 s): the bladder balloons, the tendrils splay stiff and shiver.
    keys = []
    for f in range(0, 34, 3):
        k = f / 33.0
        shiver = math.sin(f * 2.4) * 3.0 * k
        keys.append((f, merge(tendrils(f * 0.9, 3.0 + 6.0 * k, flare=38.0 * k, curl=-10.0 * k),
                              {"Cap": (shiver, 0, -shiver)}), {},
                     {"Sac": 1.0 + 0.55 * k ** 0.8 + 0.03 * math.sin(f * 1.7) * k, "Core": 1.0 + 0.5 * k,
                      "Skirt": 1.0 - 0.2 * k}))
    c.clip("swell", keys)
    c.clip("hurt", [(0, {}, {}, {}),
                    (2, tendrils(0.0, 0.0, flare=16.0, curl=-14.0), {"Sac": (0, -0.03, 0)}, {"Sac": 0.86, "Core": 1.2}),
                    (5, tendrils(1.0, 6.0, flare=-8.0), {}, {"Sac": 1.07}),
                    (9, {}, {}, {})])
    c.clip("die", [(0, {}, {}, {}), (4, tendrils(0.0, 0.0, flare=30.0), {}, {"Sac": 1.5, "Core": 1.6}),
                   (6, tendrils(0.0, 0.0, flare=-20.0, curl=30.0), {}, {"Sac": 0.3, "Core": 0.5})])
    c.export()


# --- Wings (veilwing, skimmer) -------------------------------------------------------------

def membrane_wing(c, s, pts, chords, bones, mat, paint, arm_mat, arm_paint, arm_r=0.045, fingers=(0.33, 0.62, 0.86),
                  scallop=0.16, thick=0.014, camber=0.06, n=15):
    """One wing on side s (-1 left, 1 right): an arm along the leading edge through `pts`
    (root, elbow, wrist, tip, mirrored by s), a membrane trailing back by `chords` (one per
    point), scalloped between finger struts at the given span fractions."""
    lead = [V((p[0] * s, p[1], p[2])) for p in pts]
    c.part(tube(lead, [arm_r, arm_r * 0.85, arm_r * 0.6, arm_r * 0.25], sides=7, samples=4, caps=("round", "point")),
           bones, arm_mat, arm_paint, falloff=3.0)

    def along(t):
        x = t * (len(lead) - 1)
        i = min(int(x), len(lead) - 2)
        f = x - i
        return lead[i].lerp(lead[i + 1], f), chords[i] + (chords[i + 1] - chords[i]) * f

    marks = [0.0] + list(fingers) + [1.0]
    ea, eb = [], []
    for k in range(n):
        t = k / (n - 1)
        p, chord = along(t)
        # Scallops: the trailing edge pulls in between the struts.
        seg = max(i for i in range(len(marks) - 1) if marks[i] <= t + 1e-9)
        f = (t - marks[seg]) / (marks[seg + 1] - marks[seg])
        chord *= 1.0 - scallop * math.sin(f * math.pi)
        ea.append(p + V((0, -0.004, 0.01)))
        eb.append(p + V((-0.12 * s * t * chord, -0.02, chord)))
    web = sheet(ea, eb, nv=5, thick=thick, taper=0.5, camber=lambda u, v: camber * math.sin(v * math.pi) * (1.0 - 0.5 * u))
    if s > 0:
        web = Geo_flip(web)
    c.part(web, bones, mat, paint, falloff=3.0)
    for t in fingers:
        p, chord = along(t)
        end = p + V((-0.12 * s * t * chord, -0.02, chord * 0.98))
        mid = p.lerp(end, 0.5) + V((0, camber * 0.9, 0))
        c.part(tube([p, mid, end], [arm_r * 0.42, arm_r * 0.3, arm_r * 0.12], sides=5, samples=3, caps=("flat", "point")),
               bones, arm_mat, arm_paint, falloff=3.0)


def Geo_flip(geo):
    geo.faces = [tuple(reversed(f)) for f in geo.faces]
    return geo


# --- Veilwing ----------------------------------------------------------------------------

def veilwing():
    """Gillwood veilwing: a leathery glider the span of a door. A flat, keeled body with a
    broad horned head, two membrane wings on finger struts, a whip tail with a fin, and the
    teal gill-strip along its belly that shows when it flares. Faces -z; origin is its middle."""
    c = Creature("veilwing")
    c.material("veilwing_hide", rough=0.62)
    c.material("veilwing_membrane", rough=0.5)
    c.material("veilwing_gill", rough=0.35, emit="3fd1b5", energy=1.2)
    c.material("veilwing_eye", rough=0.3, emit="d7fff4", energy=1.0)

    c.bone("Body", (0, 0, 0.35), (0, 0, -0.3))
    c.bone("Head", (0, 0.0, -0.42), (0, 0.0, -0.8), "Body")
    c.bone("Gill", (0, -0.15, 0.0), (0, -0.15, -0.3), "Body")
    tail_pts = [V((0, 0.0, 0.5)), V((0, 0.0, 0.85)), V((0, -0.01, 1.2)), V((0, -0.02, 1.55))]
    tail = c.chain("Tail", tail_pts, "Body")
    for side, s in (("L", -1.0), ("R", 1.0)):
        c.bone("Wing" + side, (0.2 * s, 0.03, -0.12), (0.8 * s, 0.06, -0.2), "Body")
        c.bone("WingTip" + side, (0.8 * s, 0.06, -0.2), (1.55 * s, 0.02, 0.1), "Wing" + side)

    hide = mottled("2c2840", "4a4368", freq=6.0, seed=1.0, belly="6a6488", belly_at=-0.3)

    def body_fn(u):
        k = 1.0
        # A dorsal keel, a flat belly, shoulders where the wings root.
        k += 0.22 * smooth(0.5, 1.0, u.y) * (1.0 - abs(u.x) * 3.0 if abs(u.x) < 0.33 else 0.0)
        k += 0.12 * smooth(0.4, 0.9, abs(u.x)) * smooth(0.5, -0.4, u.z)
        if u.y < 0:
            k *= 1.0 - 0.25 * (-u.y) ** 2
        return k

    body = ellipsoid((0, 0, 0.02), (0.3, 0.17, 0.62), segs=24, rings=16, fn=body_fn)
    body.plates(0.008, 9.0, 1.0)
    c.part(body, ["Body", "Head", tail[0]], "veilwing_hide", hide, falloff=2.5)
    # Dorsal ridge of low fins.
    for i in range(5):
        z = -0.3 + i * 0.17
        h = 0.075 - abs(i - 1.5) * 0.012
        c.part(spike((0, 0.17, z), (0, 0.19 + h, z + 0.1), 0.028, sides=5), "Body", "veilwing_hide", "1f1c30")

    # Head: a broad shovel with two horn-lobes that funnel air to the gills.
    def head_fn(u):
        k = 1.0 + 0.25 * smooth(0.3, 0.9, abs(u.x)) * smooth(0.2, -0.6, u.z)
        k *= 1.0 - 0.3 * smooth(0.2, 1.0, -u.z) * (1.0 - abs(u.x))
        return k

    head = ellipsoid((0, 0.0, -0.6), (0.27, 0.11, 0.3), segs=20, rings=12, fn=head_fn)
    head.plates(0.006, 12.0, 2.0)
    c.part(head, ["Head", "Body"], "veilwing_hide", hide, falloff=3.0)
    for side, s in (("L", -1.0), ("R", 1.0)):
        c.part(tube([(0.2 * s, 0.0, -0.7), (0.27 * s, 0.01, -0.86), (0.23 * s, -0.03, -1.0)], [0.055, 0.04, 0.012],
                    sides=6, samples=3, caps=("round", "point")), "Head", "veilwing_hide", "1f1c30")
        c.part(ellipsoid((0.16 * s, 0.07, -0.66), (0.035, 0.022, 0.045), segs=8, rings=5), "Head", "veilwing_eye", "e8fff8", ao=False)
    # Mouth slit and gill-strip under the body: the weak spot.
    gill = ellipsoid((0, -0.15, 0.02), (0.11, 0.035, 0.42), segs=14, rings=10,
                     fn=lambda u: 1.0 + 0.12 * math.sin(u.z * 22.0))
    c.part(gill, "Gill", "veilwing_gill", lambda p, n: mix(C("1f9c86"), C("8af7e0"), 0.5 + 0.5 * math.sin(p.z * 52.0)), ao=False)
    for i in range(6):
        z = -0.3 + i * 0.13
        for s in (-1.0, 1.0):
            c.part(tube([(0.1 * s, -0.14, z), (0.17 * s, -0.12, z + 0.03), (0.22 * s, -0.08, z + 0.05)], [0.018, 0.014, 0.006],
                        sides=5, samples=2, caps=("flat", "point")), "Body", "veilwing_hide", "191628")

    # Tail whip with a leaf fin.
    c.part(tube([(0, 0.0, 0.4)] + tail_pts, [0.12, 0.085, 0.05, 0.03, 0.012], sides=8, samples=4, up=(0, 1, 0)),
           ["Body"] + tail, "veilwing_hide", hide, falloff=3.0)
    fin_a = [(0, 0.0, 1.25), (0, 0.0, 1.4), (0, 0.0, 1.55), (0, 0.0, 1.68)]
    for s in (-1.0, 1.0):
        fin_b = [(0.0, 0.0, 1.3), (0.11 * s, 0.01, 1.5), (0.1 * s, 0.01, 1.65), (0.0, 0.0, 1.72)]
        f = sheet(fin_a, fin_b, nv=2, thick=0.012)
        c.part(Geo_flip(f) if s > 0 else f, tail[-1], "veilwing_membrane", "6b5fa0")

    def web_paint(p, n):
        # Paler toward the trailing edge, dark veins fanning from the shoulder.
        r = math.hypot(abs(p.x) - 0.2, p.z + 0.1)
        ang = math.atan2(p.z + 0.12, abs(p.x) - 0.15)
        vein = smooth(0.82, 1.0, abs(math.sin(ang * 9.0))) * smooth(0.15, 0.5, r)
        base = mix(C("3d3562"), C("8273bd"), smooth(0.0, 0.75, p.z + 0.15))
        base = mix(base, C("5b4f8a"), 0.35 + 0.35 * fbm(p, 7.0, 2, 3.0))
        return mix(base, C("231d3e"), vein * 0.7)

    for side, s in (("L", -1.0), ("R", 1.0)):
        membrane_wing(c, s, [(0.2, 0.03, -0.14), (0.8, 0.07, -0.24), (1.25, 0.05, -0.12), (1.58, 0.02, 0.14)],
                      [0.92, 0.95, 0.7, 0.2], ["Wing" + side, "WingTip" + side], "veilwing_membrane", web_paint,
                      "veilwing_hide", "262238")
    c.build()

    def wings(up, tip=0.0, sweep=0.0, fold=0.0):
        """up: degrees the wings lift; tip: extra at the outer joint; sweep: back; fold: the
        outer wing folding in under."""
        return {"WingL": (0, sweep, -up), "WingR": (0, -sweep, up),
                "WingTipL": (0, fold, -tip), "WingTipR": (0, -fold, tip)}

    def tail_wave(ph, amp, droop=0.0):
        return {t: (droop + math.sin(ph - i * 0.9) * amp * 0.4, math.cos(ph - i * 0.9) * amp, 0) for i, t in enumerate(tail)}

    # Hanging at its roost: head down, wings wrapped round itself, swaying.
    def roost(ph):
        sway = math.sin(ph) * 3.0
        return (merge(wings(-72, -78, 12, 0), tail_wave(ph, 4.0), {"Body": (-84 + sway * 0.5, 0, sway), "Head": (18 + sway, 0, 0)}),
                {"Body": (0, -0.35, 0)})
    c.cycle("roost", 90, roost, steps=8)
    c.cycle("idle", 90, roost, steps=8)
    # The flare: reared back, wings thrown wide and shivering, gills bared.
    c.cycle("flare", 8, lambda ph: (merge(wings(28 + 9 * math.sin(ph), 16 * math.cos(ph)), tail_wave(ph, 14.0, -12),
                                           {"Body": (38, 0, 0), "Head": (-30, 0, 0), "Gill": (0, 0, 0)}),
                                     {"Gill": (0, -0.02, 0)}, {"Gill": 1.25 + 0.1 * math.sin(ph)}), steps=4)
    # The dive: wings swept back and half shut, body a dart.
    c.cycle("swoop", 12, lambda ph: merge(wings(8 + 2 * math.sin(ph), -10, 52, 28), tail_wave(ph, 3.0),
                                           {"Head": (8, 0, 0)}), steps=4)
    # Climbing away: deep, heavy beats, the tips lagging the arms.
    def beat(ph, amp=38.0):
        return (merge(wings(amp * math.sin(ph) + 6, amp * 0.6 * math.sin(ph - 0.9), 8 * math.cos(ph)),
                      tail_wave(ph, 8.0), {"Body": (10 + 5 * math.cos(ph), 0, 0), "Head": (-8, 0, 0)}),
                {"Body": (0, -0.06 * math.sin(ph), 0)})
    c.cycle("climb", 10, beat, steps=8)
    c.cycle("walk", 24, lambda ph: beat(ph, 22.0), steps=8)
    c.clip("hurt", [(0, {}), (2, merge(wings(-25, -30, 0, 0), {"Body": (-14, 0, 9), "Head": (20, 0, 0)})),
                    (6, merge(wings(20, 10), {"Body": (6, 0, -4)})), (9, {})])
    c.clip("die", [(0, wings(10, 0)), (5, merge(wings(50, 30, 10), {"Body": (-20, 0, 25), "Head": (25, 0, 0)})),
                   (12, merge(wings(-60, -70, 20), tail_wave(0.0, 20.0, 20), {"Body": (-50, 0, 70), "Head": (30, 0, 0)}))])
    c.export()


# --- Ridge diver -------------------------------------------------------------------------

def ridge_diver():
    """Loom ridge diver: a legless burrower, modelled the way it stands out of the ground after
    an eruption. Overlapping basalt plates down a thick trunk, a pale ribbed belly, a blunt
    shovel snout fringed with whisker-fibres, and the turquoise gill ring under its neck that
    opens while it inhales. Origin is the ground where it comes up; it faces -z."""
    c = Creature("ridge_diver")
    c.material("diver_plate", rough=0.42, metal=0.15)
    c.material("diver_belly", rough=0.75)
    c.material("diver_gill", rough=0.3, emit="38f0d8", energy=0.5)

    pts = [V((0, -0.6, 0.06)), V((0, 0.05, 0.04)), V((0, 0.65, 0.0)), V((0, 1.2, -0.05)), V((0, 1.66, -0.17)), V((0, 1.93, -0.36))]
    spine = c.chain("Spine", pts)
    c.bone("Head", pts[-1], (0, 2.0, -0.95), spine[-1])
    c.bone("Gill", (0, 1.45, -0.1), (0, 1.75, -0.2), spine[3])
    c.bone("WhiskL", (-0.3, 1.95, -0.8), (-0.42, 1.8, -1.0), "Head")
    c.bone("WhiskR", (0.3, 1.95, -0.8), (0.42, 1.8, -1.0), "Head")

    SEGS = 9

    def saw(t):
        x = (t * SEGS) % 1.0
        return x

    def plate_profile(ang, t):
        # Each plate flares toward its lower lip and tucks under the next; flatter in front.
        lip = 1.0 + 0.13 * (1.0 - saw(t)) ** 2
        front = 1.0 - 0.1 * max(0.0, -math.sin(ang))
        return lip * front

    def plate_paint(p, n):
        t = smooth(-0.6, 1.95, p.y)
        edge = (1.0 - saw(t)) ** 3
        base = mix(C("1d1c20"), C("34323a"), 0.5 + 0.5 * fbm(p, 6.0, 3, 1.0))
        base = mix(base, C("596068"), edge * 0.55)
        # The weave's dust lies on everything that faces up.
        base = mix(base, C("7a655c"), smooth(0.35, 0.9, n.y) * 0.6)
        return base

    trunk = tube(pts, [0.3, 0.37, 0.37, 0.35, 0.31, 0.27], sides=18, samples=9, caps=("round", "round"), profile=plate_profile)
    trunk.plates(0.006, 10.0, 2.0)
    c.part(trunk, spine, "diver_plate", plate_paint, falloff=3.0)
    # The belly: a paler ribbed strip down the front.
    belly_pts = [p + V((0, 0, -0.2 - 0.02 * i)) for i, p in enumerate(pts[:5])]
    belly = tube(belly_pts, [(0.2, 0.14), (0.25, 0.17), (0.25, 0.17), (0.23, 0.16), (0.2, 0.13)], sides=12, samples=8, up=(0, 0, -1),
                 profile=lambda ang, t: 1.0 + 0.07 * math.sin(t * 60.0))
    c.part(belly, spine, "diver_belly",
           lambda p, n: mix(C("5c4e49"), C("9a857a"), 0.5 + 0.5 * math.sin(p.y * 31.0)), falloff=3.0)

    # Head: a spade, wider at the front, with a chipped rim and a plated brow.
    def snout_fn(u):
        k = 1.0 + 0.32 * smooth(0.1, -0.9, u.z) * (abs(u.x) ** 0.8)
        k += 0.05 * fbm(u, 4.0, 2, 7.0) * smooth(0.0, -0.7, u.z)
        return k

    snout = ellipsoid((0, 1.99, -0.66), (0.33, 0.12, 0.44), segs=22, rings=12, fn=snout_fn, rot=(-24, 0, 0))
    snout.plates(0.012, 7.0, 3.0)

    def snout_paint(p, n):
        base = mix(C("1d1c20"), C("3a3840"), 0.5 + 0.5 * fbm(p, 9.0, 3, 5.0))
        # Scoured pale along the digging edge, dusty only in the hollows.
        base = mix(base, C("7f8890"), smooth(-0.85, -1.08, p.z) * 0.6)
        return mix(base, C("7a655c"), smooth(0.5, 0.95, n.y) * 0.22)

    c.part(snout, ["Head", spine[-1]], "diver_plate", snout_paint, falloff=3.5)
    # Chevron ridges across the top of the spade and blunt digging teeth along its rim.
    for i in range(3):
        z = -0.5 - i * 0.16
        y = 2.07 - i * 0.07
        w = 0.2 + i * 0.05
        c.part(tube([(-w, y - 0.03, z + 0.07), (0, y + 0.012, z - 0.05), (w, y - 0.03, z + 0.07)], [0.02, 0.034, 0.02], sides=6, samples=4),
               "Head", "diver_plate", "111013")
    for i in range(7):
        a = (i / 6.0 - 0.5) * 1.9
        base = V((math.sin(a) * 0.4, 1.83 - 0.02 * math.cos(a), -0.68 - 0.36 * math.cos(a)))
        c.part(spike(base, base + V((math.sin(a) * 0.07, -0.05, -0.1 * math.cos(a) - 0.02)), 0.035, sides=5),
               "Head", "diver_belly", "c9c0b4")
    brow = shell((0, 2.0, -0.42), (0.31, 0.2, 0.3), cover=0.45, thick=0.05, segs=16, rings=5, rot=(-30, 0, 0), lip=0.1)
    c.part(brow, "Head", "diver_plate", plate_paint)
    # The underjaw: a paler wedge that shows its throat when the head goes back.
    jaw = ellipsoid((0, 1.86, -0.6), (0.24, 0.09, 0.34), segs=14, rings=8, rot=(-24, 0, 0))
    c.part(jaw, "Head", "diver_belly", mottled("6b5a54", "8f7c72", freq=8.0, seed=4.0))
    # Whisker-fibres fringing the snout.
    for i in range(11):
        f = i / 10.0
        a = (f - 0.5) * 2.6
        base = V((math.sin(a) * 0.36, 1.88 - 0.22 * math.cos(a), -0.72 - 0.42 * math.cos(a)))
        end = base + V((math.sin(a) * 0.22, -0.24 - 0.05 * (i % 3), -0.1 * math.cos(a)))
        mid = base.lerp(end, 0.5) + V((math.sin(a) * 0.06, 0.03, -0.04))
        bone = "WhiskL" if a < -0.2 else ("WhiskR" if a > 0.2 else "Head")
        c.part(tube([base, mid, end], [0.014, 0.01, 0.003], sides=4, samples=3, caps=("flat", "point")),
               bone, "diver_belly", "b7a69a", ao=False)

    # The gill ring: rows of fine lamellae round the neck that fan open when it breathes in.
    for i in range(26):
        a = TAU * i / 26
        d = V((math.cos(a), 0, math.sin(a)))
        at = V((0, 1.45, -0.1)) + d * 0.31 + V((0, -d.z * 0.07, 0))
        tip = at + d * 0.13 + V((0, -0.11, 0))
        mid = at.lerp(tip, 0.5) + d * 0.03
        lam = tube([at, mid, tip], [(0.012, 0.05), (0.01, 0.045), (0.004, 0.012)], sides=6, samples=3, up=(0, 1, 0),
                   caps=("flat", "point"))
        c.part(lam, "Gill", "diver_gill",
               lambda p, n: mix(C("0c5a53"), C("7bfaea"), smooth(0.31, 0.45, math.hypot(p.x, p.z + 0.1))), ao=False)
    collar = lathe([(0.3, -0.07), (0.345, -0.03), (0.35, 0.03), (0.3, 0.07)], at=(0, 1.45, -0.1), segs=18, rot=(-14, 0, 0))
    c.part(collar, [spine[3], spine[4]], "diver_plate", "17161a")
    c.build()

    def sway(ph, amp=1.0, lean=0.0):
        """A slow S through the trunk; lean tips the whole column forward."""
        pose = {}
        for i, b in enumerate(spine):
            k = i / (len(spine) - 1)
            pose[b] = (lean * (0.3 + 0.7 * k) / len(spine) * 2.0 + math.sin(ph - i * 0.7) * 2.2 * amp,
                       math.sin(ph * 0.5 + i * 0.5) * 3.0 * amp * k,
                       math.cos(ph - i * 0.7) * 2.6 * amp)
        return pose

    def out(ph):
        breathe = 0.5 + 0.5 * math.sin(ph * 2.0)
        return (merge(sway(ph, 1.0, -8.0), {"Head": (10 * math.sin(ph) - 6, 16 * math.sin(ph * 0.5), 0),
                                              "WhiskL": (6 * math.sin(ph * 3), 0, 8 * math.sin(ph * 2)),
                                              "WhiskR": (6 * math.sin(ph * 3 + 1), 0, -8 * math.sin(ph * 2))}),
                {}, {"Gill": 1.15 + 0.3 * breathe})
    c.cycle("surfaced", 72, out, steps=12)
    c.cycle("idle", 72, out, steps=12)
    c.cycle("walk", 30, lambda ph: sway(ph, 1.6, -10.0), steps=8)
    # Coming up: it punches out of the weave stretched straight, head thrown back, then whips forward.
    c.clip("attack", [(0, merge(sway(0, 0.0, 26.0), {"Head": (38, 0, 0)}), {}, {"Gill": 0.7}),
                      (4, merge(sway(0, 0.0, 12.0), {"Head": (30, 0, 0)}), {spine[0]: (0, 0.18, 0)}, {"Gill": 0.7}),
                      (8, merge(sway(0, 0.0, -30.0), {"Head": (-26, 0, 0), "WhiskL": (0, 0, 30), "WhiskR": (0, 0, -30)}),
                       {spine[0]: (0, 0.05, 0)}, {"Gill": 1.2}),
                      (11, out(0.0)[0], {}, {"Gill": 1.15})])
    # Going back under: the head tucks and the whole column corkscrews down.
    c.clip("dive", [(0, out(0.0)[0], {}, {"Gill": 1.0}),
                    (6, merge(sway(0, 0.0, -44.0), {"Head": (-40, 0, 0), spine[0]: (0, 40, 0)}), {}, {"Gill": 0.6}),
                    (18, merge(sway(1.0, 2.0, -70.0), {"Head": (-55, 0, 0), spine[0]: (0, 150, 0)}), {spine[0]: (0, -0.3, 0)}, {"Gill": 0.5})])
    c.clip("hurt", [(0, {}), (2, merge(sway(0, 0.0, 22.0), {"Head": (24, 0, 14)}), {}, {"Gill": 0.6}),
                    (6, merge(sway(0, 0.0, -10.0), {"Head": (-8, 0, -6)})), (9, {})])
    c.clip("die", [(0, {}, {}, {"Gill": 1.3}),
                   (6, merge(sway(0, 0.0, 30.0), {"Head": (40, 0, 20)}), {}, {"Gill": 0.8}),
                   (20, {spine[0]: (0, 0, 8), spine[1]: (0, 0, 16), spine[2]: (-6, 0, 20), spine[3]: (-8, 0, 20),
                         spine[4]: (-6, 0, 14), "Head": (-14, 20, 12)}, {}, {"Gill": 0.4})])
    c.export()


# --- Pinweaver ---------------------------------------------------------------------------

def pinweaver():
    """Loom pinweaver: a slate-black tension frame on six caliper legs, knees higher than its
    back, feet like pins. A narrow ribbed body, a small head with caliper mandibles and a
    cluster of teal eyes, two thread spools on its back (the left one bigger, the amber valve
    at its base is the weak spot) and taut teal filaments from the spools to its knees."""
    c = Creature("pinweaver")
    c.material("weaver_frame", rough=0.42, metal=0.25)
    c.material("weaver_thread", rough=0.8, emit="e8e2d0", energy=0.15)
    c.material("weaver_valve", rough=0.3, emit="ffa63a", energy=0.2)
    c.material("weaver_glow", rough=0.4, emit="3fd1b5", energy=1.0)

    c.bone("Body", (0, 1.5, 0.45), (0, 1.5, -0.3))
    c.bone("Head", (0, 1.47, -0.5), (0, 1.4, -0.85), "Body")
    c.bone("JawL", (-0.07, 1.4, -0.8), (-0.1, 1.28, -1.05), "Head")
    c.bone("JawR", (0.07, 1.4, -0.8), (0.1, 1.28, -1.05), "Head")
    c.bone("SpoolL", (-0.3, 1.95, 0.32), (-0.3, 2.3, 0.32), "Body")
    c.bone("SpoolR", (0.26, 1.9, 0.38), (0.26, 2.15, 0.38), "Body")
    c.bone("Valve", (-0.3, 1.74, 0.5), (-0.3, 1.74, 0.7), "Body")

    frame = mottled("1d2026", "363c46", freq=7.0, seed=1.0)

    def frame_edge(p, n):
        # A cold sheen on whatever faces up, like oiled slate.
        return mix(frame(p, n), C("5a6878"), smooth(0.3, 1.0, n.y) * 0.6)

    def body_fn(u):
        # A wasp waist behind the leg block, then a ribbed abdomen.
        k = 1.0 - 0.3 * math.exp(-((u.z - 0.05) / 0.22) ** 2)
        k += 0.05 * math.sin(u.z * 20.0) * smooth(0.1, 0.5, u.z)
        k += 0.14 * smooth(0.6, 1.0, u.y) * smooth(0.3, -0.5, u.z)
        return k

    body = ellipsoid((0, 1.5, 0.05), (0.33, 0.27, 0.7), segs=22, rings=18, fn=body_fn)
    body.plates(0.007, 9.0, 1.0)
    c.part(body, "Body", "weaver_frame", frame_edge)
    # Struts over the back that carry the spools, like a rack.
    for s in (-1.0, 1.0):
        c.part(tube([(0.2 * s, 1.62, -0.2), (0.3 * s, 1.9, 0.1), (0.29 * s, 1.92, 0.5), (0.18 * s, 1.6, 0.68)], [0.035, 0.03, 0.03, 0.035],
                    sides=6, samples=4), "Body", "weaver_frame", "111317")
    # Head: small, wedge-shaped, with eyes in a cluster and long caliper mandibles.
    head = ellipsoid((0, 1.45, -0.66), (0.17, 0.13, 0.24), segs=16, rings=10,
                     fn=lambda u: 1.0 - 0.3 * smooth(0.0, 1.0, -u.z) * (1.0 - abs(u.x)))
    c.part(head, ["Head", "Body"], "weaver_frame", frame_edge, falloff=4.0)
    c.part(tube([(0, 1.48, -0.42), (0, 1.47, -0.52)], [0.1, 0.09], sides=8, samples=1), ["Body", "Head"], "weaver_frame", "0f1114")
    for i, (x, y, z, r) in enumerate([(0.07, 1.53, -0.78, 0.028), (0.12, 1.5, -0.7, 0.02), (0.035, 1.56, -0.7, 0.016),
                                      (0.1, 1.45, -0.8, 0.014)]):
        for s in (-1.0, 1.0):
            c.part(ellipsoid((x * s, y, z), (r, r, r), segs=8, rings=5), "Head", "weaver_glow", "9ffbe9", ao=False)
    for side, s in (("L", -1.0), ("R", 1.0)):
        c.part(tube([(0.07 * s, 1.4, -0.8), (0.15 * s, 1.34, -0.95), (0.11 * s, 1.27, -1.08), (0.03 * s, 1.25, -1.1)],
                    [0.03, 0.024, 0.016, 0.004], sides=6, samples=3, caps=("round", "point")), "Jaw" + side, "weaver_frame", "0d0f12")

    # The spools: flanged bobbins wound with pale thread.
    def spool(bone, at, r, h, turns):
        x, y, z = at
        core = lathe([(r * 0.45, -h / 2), (r * 1.25, -h / 2), (r * 1.25, -h / 2 + 0.03), (r * 0.5, -h / 2 + 0.05),
                      (r * 0.5, h / 2 - 0.05), (r * 1.25, h / 2 - 0.03), (r * 1.25, h / 2), (r * 0.45, h / 2)],
                     at=(x, y, z), segs=14, rot=(0, 0, 90))
        c.part(core, bone, "weaver_frame", frame_edge, hard=40)
        wound = lathe([(r * 0.55, -h / 2 + 0.05)] + [(r * (0.92 + 0.05 * math.sin(i * 1.7)), -h / 2 + 0.06 + (h - 0.12) * i / turns)
                                                    for i in range(turns + 1)] + [(r * 0.55, h / 2 - 0.05)],
                      at=(x, y, z), segs=14, rot=(0, 0, 90))
        c.part(wound, bone, "weaver_thread",
               lambda p, n: mix(C("b9b29d"), C("efe9d6"), 0.5 + 0.5 * math.sin(p.x * 160.0)))

    spool("SpoolL", (-0.3, 1.97, 0.32), 0.2, 0.5, 10)
    spool("SpoolR", (0.27, 1.92, 0.38), 0.13, 0.34, 7)
    # The tension valve at the base of the left spool: a ribbed amber bulb in a dark collar.
    valve = ellipsoid((-0.3, 1.74, 0.52), (0.13, 0.13, 0.15), segs=14, rings=10,
                      fn=lambda u: 1.0 + 0.08 * math.cos(math.atan2(u.y, u.x) * 8.0))
    c.part(valve, "Valve", "weaver_valve", lambda p, n: mix(C("b35f12"), C("ffc56a"), smooth(0.5, 0.68, p.z)), ao=False)
    c.part(lathe([(0.15, -0.03), (0.17, 0.0), (0.15, 0.03), (0.1, 0.03), (0.1, -0.03)], at=(-0.3, 1.74, 0.44), segs=12, rot=(90, 0, 0)),
           "Body", "weaver_frame", "0f1114")

    # Six caliper legs.
    legs = []
    for side, s in (("L", -1.0), ("R", 1.0)):
        for row in (1, 2, 3):
            r = row - 2
            hip = V((0.3 * s, 1.5, r * 0.4))
            knee = V((0.78 * s, 2.25 - 0.06 * abs(r), r * 0.66))
            foot = V((1.62 * s, 0.0, r * 1.0))
            thigh = c.bone("Leg%s%d" % (side, row), hip, knee, "Body")
            shin = c.bone("Shin%s%d" % (side, row), knee, foot, thigh)
            legs.append((side, s, row, thigh, shin, hip, knee, foot))
            bow = hip.lerp(knee, 0.5) + V((0.05 * s, 0.06, 0))
            c.part(tube([hip, bow, knee], [0.05, 0.034, 0.04], sides=7, samples=4), [thigh], "weaver_frame", frame_edge)
            c.part(ellipsoid(hip, (0.075, 0.075, 0.075), segs=10, rings=6), ["Body", thigh], "weaver_frame", "0f1114")
            c.part(ellipsoid(knee, (0.07, 0.085, 0.07), segs=10, rings=6), [thigh, shin], "weaver_frame",
                   lambda p, n: mix(C("23272d"), C("5a6672"), smooth(0.2, 1.0, n.y)), falloff=2.0)
            bow2 = knee.lerp(foot, 0.45) + V((0.07 * s, 0.0, 0))
            c.part(tube([knee, bow2, foot + V((-0.02 * s, 0.12, 0)), foot], [0.04, 0.03, 0.022, 0.004], sides=7, samples=4,
                        caps=("round", "point")), [shin], "weaver_frame",
                   lambda p, n: mix(frame(p, n), C("8f8a7a"), smooth(0.35, 0.0, p.y) * 0.6))
            # A spur above the foot, to hook a line round.
            spur_at = knee.lerp(foot, 0.82)
            c.part(spike(spur_at, spur_at + V((0.16 * s, 0.1, 0)), 0.02, sides=5), shin, "weaver_frame", "0d0f12")
            # A taut teal filament from the spool rack to the knee.
            rack = V((0.3 * s, 1.92, 0.1 + 0.2 * (row - 1)))
            c.part(tube([rack, knee + V((0, 0.03, 0))], [0.007, 0.007], sides=4, samples=1, caps=("flat", "flat")),
                   ["Body", shin], "weaver_glow", "7df5dc", ao=False, falloff=1.0)
    c.build()

    def stand(drop=0.0, spread=1.0, reach=0.0, shift=(0, 0, 0), lift=None):
        """Every foot planted (by IK) with the body lowered by `drop` and moved by `shift`.
        spread scales how far out the feet stand; reach throws the front pair forward;
        lift {(side, row): metres} raises single feet."""
        pose = {}
        off = V((shift[0], shift[1] - drop, shift[2]))
        for side, s, row, thigh, shin, _, _, foot in legs:
            f = V((foot.x * spread, 0.0, foot.z * spread - (reach if row == 1 else 0.0)))
            if lift and (side, row) in lift:
                f.y += lift[(side, row)]
            pose.update(c.leg_ik(thigh, shin, f, off))
        return pose, {"Body": tuple(off)}

    STRIDE = 0.9  # metres the body covers while a foot is down

    def step(ph, stride=STRIDE, lift=0.28, bob=0.03):
        """Alternating tripods with the feet planted: each foot stays put on the ground for half
        the cycle (sliding back under the body as it advances) and swings forward for the other."""
        pose = {}
        off = V((0, bob * math.sin(ph * 2), 0))
        for side, s, row, thigh, shin, _, _, foot in legs:
            psi = (ph + (math.pi if (row + (1 if s > 0 else 0)) % 2 else 0.0)) % TAU
            if psi < math.pi:
                z = -stride * 0.5 + stride * psi / math.pi
                y = 0.0
            else:
                t = (psi - math.pi) / math.pi
                z = stride * 0.5 - stride * (0.5 - 0.5 * math.cos(t * math.pi))
                y = lift * math.sin(t * math.pi)
            pose.update(c.leg_ik(thigh, shin, foot + V((0, y, z)), off))
        return pose, {"Body": tuple(off)}

    def with_body(posed, extra, more_offsets=None, scales=None):
        pose, offsets = posed
        return (merge(pose, extra), merge(offsets, more_offsets or {}), scales or {})

    c.cycle("idle", 80, lambda ph: with_body(
        stand(0.03 * math.sin(ph)),
        {"Body": (1.5 * math.sin(ph), 0, 1.0 * math.cos(ph)), "Head": (4 * math.sin(ph * 2), 9 * math.sin(ph), 0),
         "JawL": (0, -8 - 8 * math.sin(ph * 2), 0), "JawR": (0, 8 + 8 * math.sin(ph * 2), 0)}), steps=8)
    c.cycle("walk", 24, lambda ph: with_body(
        step(ph), {"Body": (0, 0, 2.0 * math.sin(ph)), "Head": (0, 0, -2.0 * math.sin(ph))}), steps=12)
    # Anchoring: the front pair planted wide and forward, body pulled low and shaking with the
    # strain, valve swollen open.
    c.cycle("anchor", 12, lambda ph: with_body(
        stand(0.3 - 0.012 * math.sin(ph * 2), 1.06, reach=0.5, shift=(0, 0, -0.08)),
        {"Body": (7 + 1.5 * math.sin(ph * 2), 0, 1.5 * math.sin(ph)), "Head": (-14, 0, 0),
         "JawL": (0, -26, 0), "JawR": (0, 26, 0), "SpoolL": (40 * math.sin(ph), 0, 0)},
        scales={"Valve": 1.5 + 0.12 * math.sin(ph * 2)}), steps=8)
    # Spooling a line out: the big spool runs, the body rocks back against it.
    c.cycle("spool", 10, lambda ph: with_body(
        stand(0.2, 1.06, reach=0.5, shift=(0, 0, 0.12)),
        {"Body": (-6 + 2 * math.sin(ph), 0, 0), "Head": (4, 0, 0), "SpoolL": (math.degrees(ph), 0, 0),
         "SpoolR": (-math.degrees(ph) * 0.5, 0, 0), "JawL": (0, -10, 0), "JawR": (0, 10, 0)}), steps=8)
    # Unspooled: sagging between its knees, legs splayed, swaying.
    c.cycle("recover", 60, lambda ph: with_body(
        stand(0.6 - 0.05 * math.sin(ph * 2), 1.12, shift=(0.08 * math.sin(ph), 0, 0.05 * math.cos(ph))),
        {"Body": (5 * math.sin(ph), 0, 5 * math.cos(ph)), "Head": (22, 12 * math.sin(ph), 0),
         "JawL": (0, -30, 0), "JawR": (0, 30, 0), "SpoolL": (-math.degrees(ph), 0, 0)},
        scales={"Valve": 1.5}), steps=8)
    c.clip("hurt", [(0,) + with_body(stand(), {}),
                    (2,) + with_body(stand(-0.1, shift=(0, 0, 0.14)), {"Body": (-9, 0, 6), "Head": (18, 0, 0)}),
                    (6,) + with_body(stand(0.1), {"Body": (4, 0, -3)}),
                    (9,) + with_body(stand(), {})])
    # Death: the frame loses its tension: a jolt up, then the feet skate out from under it and
    # the body drops between its knees.
    jaws = {"JawL": (0, -35, 0), "JawR": (0, 35, 0)}
    c.clip("die", [(0,) + with_body(stand(), {}),
                   (4,) + with_body(stand(-0.12, 0.94), {"Body": (-12, 0, 0)}),
                   (12,) + with_body(stand(0.75, 1.2), merge({"Body": (6, 0, 9), "Head": (26, 0, 0)}, jaws)),
                   (17,) + with_body(stand(1.2, 1.42), merge({"Body": (8, 0, 14), "Head": (30, 0, 0)}, jaws)),
                   (22,) + with_body(stand(1.26, 1.45), merge({"Body": (7, 0, 16), "Head": (34, 0, 0)}, jaws))])
    c.export()


# --- Chord singer ------------------------------------------------------------------------

def chord_singer():
    """Loom chord singer: a tall tripod, mostly empty space. Three long stilt legs with splayed
    toes, a hollow fluted chest you can see into, a glassy bell throat hung in front of it with
    the pale teal membrane inside (the weak spot), a tuning fork of rib fins over its head, and
    resonator strings hanging down through the chest. Faces -z; 5 m to the tips of the fork."""
    c = Creature("chord_singer")
    c.material("singer_skin", rough=0.6)
    c.material("singer_bone", rough=0.45)
    c.material("singer_bell", rough=0.1, alpha=0.38)
    c.material("singer_membrane", rough=0.3, emit="9ff0e0", energy=0.3)
    c.material("singer_string", rough=0.5, emit="9ff0e0", energy=0.25)

    c.bone("Body", (0, 2.2, 0), (0, 3.1, 0))
    c.bone("Bell", (0, 3.55, 0.1), (0, 3.53, -0.5), "Body")
    c.bone("Membrane", (0, 3.545, -0.22), (0, 3.54, -0.42), "Bell")
    c.bone("Strings", (0, 3.1, 0), (0, 1.8, 0), "Body")
    for side, s in (("L", -1.0), ("R", 1.0)):
        c.bone("Fork" + side, (0.22 * s, 3.4, 0.3), (0.3 * s, 5.0, 0.25), "Body")

    def skin(p, n):
        base = mix(C("5f5380"), C("8f80b0"), 0.5 + 0.5 * fbm(p, 3.0, 3, 1.0))
        return mix(base, C("b8aed0"), smooth(0.4, 1.0, n.y) * 0.3)

    def bone_paint(p, n):
        return mix(C("b9b0c9"), C("e6e0f0"), 0.5 + 0.5 * fbm(p, 6.0, 2, 2.0))

    # The chest: an open cage of bowed ribs between two rings. You can see straight through it,
    # and the resonator strings hang down the middle like a harp's.
    def torus(radius, y, r, segs=28):
        return hollow([(radius + r * math.cos(TAU * k / 8), y + r * math.sin(TAU * k / 8)) for k in range(8)], segs=segs)

    c.part(torus(0.4, 3.12, 0.05), "Body", "singer_bone", bone_paint)
    c.part(torus(0.2, 2.2, 0.05), "Body", "singer_bone", bone_paint)
    RIBS = 11
    for i in range(RIBS):
        a = TAU * i / RIBS
        dx, dz = math.cos(a), math.sin(a)
        rib = tube([(dx * 0.2, 2.2, dz * 0.2), (dx * 0.4, 2.42, dz * 0.4), (dx * 0.52, 2.74, dz * 0.52), (dx * 0.4, 3.12, dz * 0.4)],
                   [(0.03, 0.045), (0.026, 0.05), (0.026, 0.05), (0.03, 0.04)], sides=6, samples=5, up=(dx, 0, dz))
        c.part(rib, "Body", "singer_bone",
               lambda p, n: mix(bone_paint(p, n), C("5f5380"), smooth(0.5, 0.0, abs(math.sin(p.y * 22.0))) * 0.35))
    # A pelvis knot under the cage that the legs root in.
    pelvis = ellipsoid((0, 2.1, 0), (0.3, 0.14, 0.3), segs=18, rings=10,
                       fn=lambda u: 1.0 + 0.2 * max(0.0, math.cos(math.atan2(u.z, u.x) * 3 - math.pi * 1.5)))
    pelvis.bumps(0.012, 7.0, 2.0, 2)
    c.part(pelvis, "Body", "singer_skin", skin)

    # The bell: glass-thin, flaring forward, on a neck that arcs up out of the front of the cage.
    by = 3.55
    bell = hollow([(0.08, 0.0), (0.14, 0.12), (0.27, 0.3), (0.39, 0.5), (0.45, 0.64), (0.43, 0.64), (0.37, 0.5),
                   (0.25, 0.3), (0.12, 0.12), (0.05, 0.0)], at=(0, by, 0.1), segs=28, rot=(-88, 0, 0),
                  fn=lambda th, r, h: r * (1.0 + 0.05 * math.cos(th * 7) * h / 0.64))
    c.part(bell, "Bell", "singer_bell",
           lambda p, n: mix(C("8fa6ea"), C("e3ecff"), smooth(0.1, -0.5, p.z)), ao=False)
    c.part(tube([(0, 3.12, -0.36), (0, 3.36, -0.3), (0, 3.52, -0.08), (0, by, 0.1)], [0.06, 0.055, 0.06, 0.08], sides=8, samples=4),
           ["Body", "Bell"], "singer_skin", skin, falloff=2.0)
    # The membrane stretched across inside it, veined, and a rim of little teeth round the lip.
    mem = ellipsoid((0, by - 0.005, -0.22), (0.27, 0.27, 0.03), segs=20, rings=8)
    c.part(mem, "Membrane", "singer_membrane",
           lambda p, n: mix(C("4fb0a2"), C("c9fff4"), smooth(0.28, 0.0, math.hypot(p.x, p.y - by))
                            * (0.6 + 0.4 * abs(math.sin(math.atan2(p.y - by, p.x) * 6.0)))), ao=False)
    for i in range(12):
        a = TAU * i / 12
        base = V((math.cos(a) * 0.44, by - 0.02 + math.sin(a) * 0.44, -0.53))
        c.part(spike(base, base + V((math.cos(a) * 0.04, math.sin(a) * 0.04, -0.1)), 0.018, sides=5),
               "Bell", "singer_bone", "f0ebf8", ao=False)

    # The fork: two long slender tines on a yoke behind the bell, bowing apart and back in.
    c.part(tube([(-0.22, 3.42, 0.3), (-0.12, 3.24, 0.3), (0, 3.14, 0.34), (0.12, 3.24, 0.3), (0.22, 3.42, 0.3)],
                [0.05, 0.06, 0.07, 0.06, 0.05], sides=8, samples=4), "Body", "singer_skin", skin)
    for side, s in (("L", -1.0), ("R", 1.0)):
        lead = [V(p) for p in [(0.22 * s, 3.4, 0.24), (0.3 * s, 3.9, 0.2), (0.33 * s, 4.5, 0.2), (0.27 * s, 5.05, 0.24)]]
        trail = [V(p) for p in [(0.22 * s, 3.4, 0.38), (0.31 * s, 3.9, 0.36), (0.34 * s, 4.5, 0.33), (0.27 * s, 5.02, 0.28)]]

        def dense(pts, n=10):
            out = []
            for i in range(n):
                t = i / (n - 1) * (len(pts) - 1)
                k = min(int(t), len(pts) - 2)
                out.append(pts[k].lerp(pts[k + 1], t - k))
            return out
        fin = sheet(dense(lead), dense(trail), nv=2, thick=0.045, taper=0.6)
        if s > 0:
            Geo_flip(fin)
        c.part(fin, ["Fork" + side], "singer_bone",
               lambda p, n: mix(bone_paint(p, n), C("5f5380"), smooth(0.25, 0.0, abs(math.sin(p.y * 18.0))) * 0.5))

    # Resonator strings down the middle of the cage, each with a small weight below it.
    for i in range(7):
        a = TAU * i / 7 + 0.3
        rr = 0.1 + 0.05 * (i % 2)
        top = V((math.cos(a) * rr * 2.2, 3.1, math.sin(a) * rr * 2.2))
        ln = 1.25 + 0.3 * ((i * 3) % 4) / 3
        end = V((math.cos(a) * rr, 3.1 - ln, math.sin(a) * rr))
        c.part(tube([top, end], [0.007, 0.007], sides=4, samples=1, caps=("flat", "flat")), ["Body", "Strings"],
               "singer_string", "bff5ea", ao=False, falloff=1.5)
        c.part(ellipsoid(end, (0.03, 0.05, 0.03), segs=8, rings=5), "Strings", "singer_bone", "e6e0f0")

    # Three stilt legs: one behind, two in front, each with a high knee and three toes.
    legs = []
    for i, ang in enumerate((math.pi * 0.5, math.pi * 0.5 + TAU / 3, math.pi * 0.5 + 2 * TAU / 3)):
        d = V((math.cos(ang), 0, math.sin(ang)))
        hip = d * 0.3 + V((0, 2.08, 0))
        knee = d * 0.95 + V((0, 1.42, 0))
        foot = d * 1.2 + V((0, 0.0, 0))
        thigh = c.bone("Leg%d" % (i + 1), hip, knee, "Body")
        shin = c.bone("Shin%d" % (i + 1), knee, foot, thigh)
        legs.append((i, d, thigh, shin, hip, knee, foot))
        c.part(tube([hip, hip.lerp(knee, 0.5) + V((0, 0.03, 0)), knee], [0.085, 0.05, 0.055], sides=8, samples=4),
               [thigh], "singer_skin", skin)
        c.part(ellipsoid(knee, (0.08, 0.09, 0.08), segs=10, rings=6), [thigh, shin], "singer_bone", bone_paint, falloff=2.0)
        c.part(tube([knee, knee.lerp(foot, 0.5) + d * 0.02, foot + V((0, 0.12, 0))], [0.055, 0.038, 0.036], sides=8, samples=4),
               [shin], "singer_skin", lambda p, n: mix(skin(p, n), C("3a3058"), smooth(0.5, 0.0, p.y) * 0.6))
        side = V((-d.z, 0, d.x))
        for k in (-1, 0, 1):
            td = (d * (1.0 if k == 0 else 0.45) + side * 0.8 * k).normalized()
            if k == 0:
                td = d
            c.part(tube([foot + V((0, 0.1, 0)), foot + td * 0.2 + V((0, 0.05, 0)), foot + td * 0.42 + V((0, 0.0, 0))],
                        [0.05, 0.04, 0.012], sides=6, samples=3, caps=("round", "point")), shin, "singer_bone", bone_paint)
    c.build()

    def stand(drop=0.0, spread=1.0, shift=(0, 0, 0), lift=None):
        pose = {}
        off = V((shift[0], shift[1] - drop, shift[2]))
        for i, d, thigh, shin, _, _, foot in legs:
            f = V((foot.x * spread, (lift or {}).get(i, 0.0), foot.z * spread))
            pose.update(c.leg_ik(thigh, shin, f, off))
        return pose, {"Body": tuple(off)}

    def with_body(posed, extra, scales=None):
        pose, offsets = posed
        return (merge(pose, extra), offsets, scales or {})

    def fork(open_deg=0.0, ring=0.0):
        return {"ForkL": (ring, 0, open_deg), "ForkR": (-ring, 0, -open_deg)}

    def strings(ph, amp=6.0):
        return {"Strings": (amp * math.sin(ph), 0, amp * math.cos(ph * 0.5))}

    c.cycle("idle", 96, lambda ph: with_body(
        stand(0.04 * math.sin(ph)),
        merge({"Body": (2 * math.sin(ph), 3 * math.sin(ph * 0.5), 1.5 * math.cos(ph)), "Bell": (3 * math.sin(ph * 2), 0, 0)},
              fork(1.5 * math.sin(ph)), strings(ph)),
        {"Membrane": 0.9 + 0.05 * math.sin(ph * 2)}), steps=8)

    STRIDE = 1.0

    def step(ph):
        """One leg at a time, each down for two thirds of the cycle: a slow, deliberate walk."""
        pose = {}
        off = V((0, 0.05 * math.sin(ph * 3), 0))
        for i, d, thigh, shin, _, _, foot in legs:
            psi = (ph + i * TAU / 3) % TAU
            duty = TAU * 2 / 3
            if psi < duty:
                z = -STRIDE * 0.5 + STRIDE * psi / duty
                y = 0.0
            else:
                t = (psi - duty) / (TAU - duty)
                z = STRIDE * 0.5 - STRIDE * (0.5 - 0.5 * math.cos(t * math.pi))
                y = 0.45 * math.sin(t * math.pi)
            pose.update(c.leg_ik(thigh, shin, foot + V((0, y, z)), off))
        return (merge(pose, {"Body": (3 + 1.5 * math.sin(ph * 3), 0, 2.5 * math.sin(ph))}, strings(ph * 3, 9.0), fork(1.0 * math.sin(ph * 3))),
                {"Body": tuple(off)}, {"Membrane": 0.9})
    c.cycle("walk", 24, step, steps=12)
    # Planting: feet driven wide, body settling down between them.
    c.cycle("plant", 30, lambda ph: with_body(
        stand(0.22 + 0.02 * math.sin(ph), 1.1), merge({"Body": (-2, 0, 0)}, strings(ph, 3.0)), {"Membrane": 0.95}), steps=4)
    # Drawing breath: it rises and arches back, the bell swells and tips up, the fork spreads.
    keys = []
    for f in range(0, 49, 6):
        k = f / 48.0
        e = smooth(0.0, 1.0, k)
        keys.append((f,) + with_body(stand(0.22 - 0.3 * e, 1.1),
                                     merge({"Body": (-2 + 12 * e, 0, 0), "Bell": (10 * e, 0, 0)}, fork(7 * e), strings(f * 0.3, 3.0)),
                                     {"Bell": 1.0 + 0.22 * e, "Membrane": 0.95 + 0.3 * e}))
    c.clip("inhale", keys)
    # Singing: thrown forward over its front feet, the fork ringing, the bell beating.
    c.cycle("sing", 8, lambda ph: with_body(
        stand(0.1, 1.1, shift=(0, 0, -0.18)),
        merge({"Body": (-11 + 1.5 * math.sin(ph), 0, 0), "Bell": (-8, 0, 0)}, fork(3 + 2.5 * math.sin(ph * 2), 2.0 * math.sin(ph)),
              strings(ph * 2, 12.0)),
        {"Bell": 1.12 + 0.07 * math.sin(ph), "Membrane": 1.1 + 0.12 * math.sin(ph)}), steps=8)
    # Song broken: it reels, one foot coming off the ground.
    c.cycle("stagger", 20, lambda ph: with_body(
        stand(0.15, 1.0, shift=(0.22 * math.sin(ph), 0, 0.15 + 0.1 * math.cos(ph)), lift={1: 0.35 * max(0.0, math.sin(ph))}),
        merge({"Body": (16 + 5 * math.cos(ph), 0, 12 * math.sin(ph)), "Bell": (20, 0, 0)}, fork(-4, 6 * math.sin(ph * 2)), strings(ph * 2, 18.0)),
        {"Membrane": 0.8}), steps=8)
    c.clip("hurt", [(0,) + with_body(stand(), {}),
                    (2,) + with_body(stand(0.05, shift=(0, 0, 0.14)), merge({"Body": (9, 0, 5), "Bell": (12, 0, 0)}, fork(-3))),
                    (6,) + with_body(stand(0.08), {"Body": (-3, 0, -2)}), (9,) + with_body(stand(), {})])
    # Death: the legs buckle and it topples over sideways, fork folding shut.
    c.clip("die", [(0,) + with_body(stand(), {}),
                   (5,) + with_body(stand(0.3, 1.05), merge({"Body": (10, 0, 4)}, fork(8))),
                   (14,) + with_body(stand(0.95, 1.2), merge({"Body": (-6, 0, 28), "Bell": (-14, 0, 0)}, fork(-4)), {"Membrane": 0.6}),
                   (24,) + with_body(stand(1.62, 1.3, shift=(0.5, 0, 0)), merge({"Body": (-12, 0, 74), "Bell": (-24, 0, 0), "Strings": (0, 0, -50)}, fork(-9)),
                                     {"Membrane": 0.4}),
                   (30,) + with_body(stand(1.66, 1.3, shift=(0.52, 0, 0)), merge({"Body": (-12, 0, 77), "Bell": (-25, 0, 0), "Strings": (0, 0, -54)}, fork(-9)),
                                     {"Membrane": 0.4})])
    c.export()


# --- Patience guardian -------------------------------------------------------------------

def patience_guardian():
    """The Long Patience's guardian: a plated quadruped the size of a cargo loader. Three
    overlapping carapace plates streaked with rust (the rear one hinges up when a cargo magnet
    tears at it, baring the amber vent underneath: the weak spot), a blunt ram of a head with a
    row of red sensing pits along the brow and no eyes, and four pillar legs. Faces -z."""
    c = Creature("patience_guardian")
    c.material("guardian_shell", rough=0.5, metal=0.35)
    c.material("guardian_hide", rough=0.85)
    c.material("guardian_sense", rough=0.4, emit="ff5a3a", energy=1.2)
    c.material("guardian_vent", rough=0.4, emit="ffb04a", energy=0.0)

    c.bone("Body", (0, 1.25, 0.9), (0, 1.25, -0.8))
    c.bone("Head", (0, 1.1, -1.25), (0, 0.95, -2.1), "Body")
    c.bone("Jaw", (0, 0.8, -1.4), (0, 0.6, -2.0), "Head")
    c.bone("PlateBack", (0, 1.8, 0.3), (0, 1.75, 1.5), "Body")
    c.bone("Vent", (0, 1.7, 1.0), (0, 1.95, 1.0), "Body")

    def shell_paint(p, n):
        base = mix(C("2a2624"), C("4a433f"), 0.5 + 0.5 * fbm(p, 2.5, 3, 1.0))
        # Rust runs down from the ridges and pools at the plate edges.
        streak = smooth(0.1, 0.7, 0.5 + 0.5 * fbm(V((p.x * 6.0, p.y * 0.8, p.z * 6.0)), 1.0, 2, 3.0))
        rust = streak * smooth(0.6, -0.2, n.y) * 0.55
        base = mix(base, C("6e3b22"), rust)
        return mix(base, C("6d6a66"), smooth(0.75, 1.0, n.y) * 0.3)

    def hide_paint(p, n):
        return mix(C("3a2a22"), C("6e4a36"), 0.5 + 0.5 * fbm(p, 4.0, 3, 5.0))

    core = ellipsoid((0, 1.2, 0.05), (0.88, 0.6, 1.45), segs=24, rings=16,
                     fn=lambda u: 1.0 - 0.18 * max(0.0, -u.y) ** 2)
    core.plates(0.02, 3.5, 4.0)
    c.part(core, "Body", "guardian_hide", hide_paint)

    def ridge(u):
        # A keel down the middle and two shoulders of ridge either side.
        k = 1.0 + 0.07 * math.exp(-(u.x / 0.12) ** 2) + 0.04 * math.exp(-((abs(u.x) - 0.5) / 0.1) ** 2)
        return k + 0.03 * fbm(u, 5.0, 2, 2.0)

    plates = [("Body", (0, 1.22, -0.72), (1.06, 0.82, 0.78), -8), ("Body", (0, 1.3, 0.12), (1.02, 0.84, 0.74), 2),
              ("PlateBack", (0, 1.24, 0.95), (0.95, 0.8, 0.8), 12)]
    for i, (bone, at, radii, tilt) in enumerate(plates):
        sh = shell(at, radii, cover=0.5, thick=0.09, segs=26, rings=9, fn=ridge, rot=(tilt, 0, 0), lip=0.08)
        sh.plates(0.012, 5.0, float(i))
        c.part(sh, bone, "guardian_shell", shell_paint)
        # Bosses along the rim, like rivets grown rather than driven.
        # A ridge of worn knobs down the keel.
        for k in range(3):
            z = at[2] - radii[2] * 0.45 + k * radii[2] * 0.45
            c.part(ellipsoid((0, at[1] + radii[1] * 0.98 + 0.06, z), (0.09, 0.07, 0.16), segs=10, rings=6), bone,
                   "guardian_shell", "1c1917")
    # Tail stub.
    c.part(tube([(0, 1.25, 1.35), (0, 1.1, 1.7), (0, 0.85, 1.9)], [0.3, 0.2, 0.08], sides=10, samples=4), "Body", "guardian_hide", hide_paint)

    # The vent under the rear plate: a bed of amber slats.
    for i in range(6):
        z = 0.62 + i * 0.14
        c.part(ellipsoid((0, 1.74 - 0.012 * i * i, z), (0.46 - 0.03 * i, 0.07, 0.05), segs=12, rings=6), "Vent", "guardian_vent",
               lambda p, n: mix(C("5a3208"), C("ffc56a"), smooth(0.2, 1.0, n.y)), ao=False)

    # Head: a ram. A domed boss plate, a flat striking face, heavy lower jaw, two horn stubs.
    def head_fn(u):
        k = 1.0 + 0.15 * smooth(0.2, 0.9, u.y) * smooth(0.6, -0.4, u.z)
        k *= 1.0 - 0.22 * smooth(0.55, 1.0, -u.z)
        return k

    head = ellipsoid((0, 1.05, -1.62), (0.68, 0.52, 0.62), segs=24, rings=14, fn=head_fn)
    head.plates(0.014, 5.0, 7.0)
    c.part(head, ["Head", "Body"], "guardian_shell", shell_paint, falloff=5.0)
    face = shell((0, 1.02, -1.75), (0.62, 0.5, 0.5), cover=0.42, thick=0.08, segs=20, rings=6, rot=(-82, 0, 0), lip=0.05)
    c.part(face, "Head", "guardian_shell", lambda p, n: mix(shell_paint(p, n), C("8a8884"), 0.35 * smooth(-2.1, -2.26, p.z)))
    c.part(tube([(0, 1.3, -1.1), (0, 1.25, -1.35)], [0.5, 0.48], sides=12, samples=1), ["Body", "Head"], "guardian_hide", hide_paint)
    jaw = ellipsoid((0, 0.68, -1.68), (0.5, 0.2, 0.5), segs=16, rings=10, fn=lambda u: 1.0 - 0.2 * smooth(0.4, 1.0, -u.z))
    c.part(jaw, "Jaw", "guardian_hide", mottled("2a1e18", "5a3a2a", freq=5.0, seed=8.0))
    for k in range(6):
        x = -0.3 + k * 0.12
        c.part(spike((x, 0.76, -2.05 + abs(x) * 0.4), (x, 0.92, -2.1 + abs(x) * 0.4), 0.04, sides=5), "Jaw", "guardian_hide", "b8ab96")
    for s in (-1.0, 1.0):
        c.part(tube([(0.55 * s, 1.2, -1.5), (0.82 * s, 1.3, -1.62), (0.9 * s, 1.22, -1.86)], [0.14, 0.1, 0.03], sides=8, samples=3,
                    caps=("round", "point")), "Head", "guardian_shell", "1c1917")
    # Sensing pits along the brow.
    for k in range(7):
        x = -0.42 + k * 0.14
        z = -2.14 + abs(x) * 0.42
        c.part(ellipsoid((x, 1.3 - abs(x) * 0.1, z), (0.065, 0.05, 0.05), segs=8, rings=5), "Head", "guardian_sense", "ffb09a", ao=False)

    # Legs: short thick pillars, a plated knee, three blunt toes.
    legs = []
    for fb, zs in (("F", -1.0), ("B", 1.0)):
        for side, s in (("L", -1.0), ("R", 1.0)):
            hip = V((0.72 * s, 1.05, 0.92 * zs))
            knee = V((0.98 * s, 0.62, (0.92 - 0.14) * zs + 0.12))
            foot = V((0.92 * s, 0.0, 0.95 * zs))
            up = c.bone("Leg%s%s" % (fb, side), hip, knee, "Body")
            lo = c.bone("Shin%s%s" % (fb, side), knee, foot, up)
            legs.append((fb, side, s, zs, up, lo, hip, knee, foot))
            c.part(tube([hip, knee], [0.3, 0.24], sides=10, samples=3), [up, "Body"], "guardian_hide", hide_paint, falloff=5.0)
            c.part(tube([knee, knee.lerp(foot, 0.6), foot + V((0, 0.14, 0))], [0.23, 0.19, 0.24], sides=10, samples=3), [lo], "guardian_hide", hide_paint)
            cap = shell(knee + V((0.1 * s, 0.0, 0)), (0.3, 0.32, 0.3), cover=0.45, thick=0.06, segs=12, rings=5, rot=(0, 0, -70 * s))
            c.part(cap, up, "guardian_shell", shell_paint)
            for k in (-1, 0, 1):
                tp = foot + V((0.1 * s * (1 - abs(k)) + 0.0, 0.07, -0.26 + 0.0)) + V((0.2 * k, 0, 0.06 * abs(k)))
                c.part(ellipsoid(tp, (0.1, 0.08, 0.15), segs=8, rings=5), lo, "guardian_shell", "1c1917")
    c.build()

    def stand(drop=0.0, spread=1.0, shift=(0, 0, 0), lift=None, tuck=0.0):
        pose = {}
        off = V((shift[0], shift[1] - drop, shift[2]))
        for fb, side, s, zs, up, lo, _, _, foot in legs:
            f = V((foot.x * spread, (lift or {}).get(fb + side, 0.0), foot.z * (1.0 - tuck)))
            pose.update(c.leg_ik(up, lo, f, off))
        return pose, {"Body": tuple(off)}

    def with_body(posed, extra, scales=None):
        pose, offsets = posed
        return (merge(pose, extra), offsets, scales or {})

    def step(ph, stride, lift, bob):
        """A trot: diagonal pairs."""
        pose = {}
        off = V((0, bob * math.sin(ph * 2), 0))
        for fb, side, s, zs, up, lo, _, _, foot in legs:
            psi = (ph + (math.pi if (fb == "F") != (side == "L") else 0.0)) % TAU
            if psi < math.pi:
                z, y = -stride * 0.5 + stride * psi / math.pi, 0.0
            else:
                t = (psi - math.pi) / math.pi
                z, y = stride * 0.5 - stride * (0.5 - 0.5 * math.cos(t * math.pi)), lift * math.sin(t * math.pi)
            pose.update(c.leg_ik(up, lo, foot + V((0, y, z)), off))
        return pose, {"Body": tuple(off)}

    c.cycle("idle", 90, lambda ph: with_body(
        stand(0.03 + 0.03 * math.sin(ph)),
        {"Body": (1.0 * math.sin(ph), 0, 0), "Head": (4 * math.sin(ph), 12 * math.sin(ph * 0.5), 0), "Jaw": (-4 - 3 * math.sin(ph), 0, 0)}), steps=8)
    c.cycle("walk", 24, lambda ph: with_body(
        step(ph, 1.2, 0.22, 0.04), {"Body": (1.5 * math.sin(ph * 2), 0, 2.5 * math.sin(ph)), "Head": (3 * math.sin(ph * 2 + 1), -4 * math.sin(ph), 0)}), steps=12)
    # Asleep in its alcove: down on its belly, head on the floor, breathing slow.
    c.cycle("dormant", 120, lambda ph: with_body(
        stand(0.6 + 0.02 * math.sin(ph), 1.12), {"Body": (0, 0, 0), "Head": (-16, 0, 0), "Jaw": (0, 0, 0)}), steps=4)
    # Braced to charge: weight thrown back on its haunches, head down behind the plate, shaking.
    c.cycle("brace", 6, lambda ph: with_body(
        stand(0.26, 1.05, shift=(0.02 * math.sin(ph), 0, 0.3)),
        {"Body": (-7, 0, 1.0 * math.sin(ph)), "Head": (-20, 0, 0), "Jaw": (-14, 0, 0)}), steps=4)
    c.cycle("charge", 10, lambda ph: with_body(
        step(ph, 1.7, 0.4, 0.1), {"Body": (-6 + 3 * math.sin(ph * 2), 0, 2 * math.sin(ph)), "Head": (-24, 0, 0), "Jaw": (-6, 0, 0)}), steps=10)
    c.cycle("recover", 30, lambda ph: with_body(
        stand(0.14 + 0.04 * math.sin(ph * 2), 1.04), {"Body": (3, 0, 0), "Head": (8, 16 * math.sin(ph), 6 * math.sin(ph)), "Jaw": (-18 - 6 * math.sin(ph * 2), 0, 0)}), steps=8)
    # Hauled up by a cargo magnet: legs off the floor and working at nothing, the back plate wrenched open.
    def pinned(ph):
        lift = {fb + side: 0.3 + 0.16 * math.sin(ph * 2 + i * 1.7) for i, (fb, side, *_r) in enumerate(legs)}
        return with_body(stand(0.0, 0.86, lift=lift, tuck=0.2),
                         {"Body": (5 * math.sin(ph), 0, 6 * math.cos(ph)), "Head": (-18 + 8 * math.sin(ph * 2), 14 * math.sin(ph), 0),
                          "Jaw": (-26, 0, 0), "PlateBack": (34 + 3 * math.sin(ph * 4), 0, 0)}, {"Vent": 1.15 + 0.08 * math.sin(ph * 4)})
    c.cycle("pinned", 24, pinned, steps=8)
    c.clip("hurt", [(0,) + with_body(stand(), {}), (2,) + with_body(stand(0.08, shift=(0, 0, 0.1)), {"Body": (3, 0, 3), "Head": (10, 0, 6)}),
                    (6,) + with_body(stand(0.02), {"Head": (-4, 0, -2)}), (9,) + with_body(stand(), {})])
    c.clip("die", [(0,) + with_body(stand(), {}),
                   (6,) + with_body(stand(-0.08, 0.98), {"Body": (8, 0, 0), "Head": (26, 0, 0), "Jaw": (-30, 0, 0)}),
                   (18,) + with_body(stand(0.5, 1.12), {"Body": (-4, 0, 8), "Head": (-10, 0, 10), "Jaw": (-20, 0, 0), "PlateBack": (10, 0, 0)}),
                   (30,) + with_body(stand(0.66, 1.2, shift=(0.1, 0, 0)), {"Body": (-2, 0, 16), "Head": (-20, 10, 16), "Jaw": (-10, 0, 0), "PlateBack": (14, 0, 0)})])
    c.export()


# --- The Cantor --------------------------------------------------------------------------

def braid(pts, radius, strands=3, twist=5.0, sides=6, samples=6):
    """A cable of `strands` thinner tubes wound round each other along pts (a Geo)."""
    from creature_kit import Geo
    path = [V(p) for p in pts]
    n = 40
    # Resample the path evenly.
    lens = [0.0]
    for i in range(1, len(path)):
        lens.append(lens[-1] + (path[i] - path[i - 1]).length)
    total = lens[-1]

    def at(d):
        for i in range(1, len(path)):
            if lens[i] >= d:
                f = (d - lens[i - 1]) / max(lens[i] - lens[i - 1], 1e-9)
                return path[i - 1].lerp(path[i], f), (path[i] - path[i - 1]).normalized()
        return path[-1], (path[-1] - path[-2]).normalized()
    geo = Geo()
    for k in range(strands):
        pts_k = []
        side = None
        for i in range(n + 1):
            p, t = at(total * i / n)
            if side is None:
                side = t.cross(V((0, 1, 0)) if abs(t.y) < 0.9 else V((1, 0, 0))).normalized()
            side = (side - t * side.dot(t)).normalized()
            up = side.cross(t)
            a = TAU * k / strands + twist * TAU * i / n
            pts_k.append(p + (side * math.cos(a) + up * math.sin(a)) * radius * 0.55)
        geo.add(tube(pts_k, [radius * 0.55] * len(pts_k), sides=sides, samples=1, caps=("round", "round")))
    return geo


def cantor():
    """The Cantor: a hollow rib cage of braided living cable hung over the Tuning Crown's floor,
    the heart-node (teal, the weak spot) in the middle behind three woven petals that fold open,
    a crown of cable at the top where the four anchor lines meet, and a frayed knot of root
    tendrils hanging below. Origin is the floor under it; the heart is at 7 m."""
    HY = 7.0
    c = Creature("cantor")
    c.material("cantor_cable", rough=0.75)
    c.material("cantor_heart", rough=0.3, emit="3fe0c8", energy=1.0)
    c.material("cantor_petal", rough=0.6)
    c.material("cantor_glow", rough=0.4, emit="ff9a5a", energy=0.9)

    c.bone("Cage", (0, HY - 4.8, 0), (0, HY + 4.8, 0))
    c.bone("Heart", (0, HY - 1.0, 0), (0, HY + 1.0, 0), "Cage")
    c.bone("Crown", (0, HY + 4.6, 0), (0, HY + 6.0, 0), "Cage")
    for i in range(3):
        a = TAU * i / 3
        d = V((math.sin(a), 0, -math.cos(a)))
        c.bone("Petal%d" % (i + 1), V((0, HY + 1.55, 0)) + d * 0.35, V((0, HY - 1.4, 0)) + d * 1.25, "Cage")

    def cable_paint(p, n):
        base = mix(C("3e2a24"), C("7a5544"), 0.5 + 0.5 * fbm(p, 1.6, 3, 1.0))
        base = mix(base, C("a07a62"), smooth(0.5, 1.0, n.y) * 0.3)
        # Faint violet sheen in the crevices, like the Loom's light caught in the fibre.
        return mix(base, C("4a3060"), smooth(0.0, -0.8, n.y) * 0.35)

    # Ribs: eight braided hoops round the heart, swelling at the equator.
    RIBS = 8
    for i in range(RIBS):
        a = TAU * i / RIBS + 0.2
        d = V((math.cos(a), 0, math.sin(a)))
        pts = []
        for k in range(17):
            th = math.pi * k / 16
            r = 4.0 * math.sin(th) * (1.0 + 0.06 * math.sin(th * 3 + i))
            y = HY + 5.2 * math.cos(th)
            pts.append(d * r + V((0, y, 0)) + V((-d.z, 0, d.x)) * 0.35 * math.sin(th * 2))
        c.part(braid(pts, 0.28, strands=3, twist=4.0 + i % 3, sides=6), "Cage", "cantor_cable", cable_paint, ao=False)
    # Two girdles round the cage holding the ribs.
    for y, r in ((HY + 2.6, 3.45), (HY - 2.6, 3.45)):
        pts = [V((math.cos(TAU * k / 24) * r, y + 0.2 * math.sin(TAU * k / 8), math.sin(TAU * k / 24) * r)) for k in range(25)]
        c.part(braid(pts, 0.18, strands=2, twist=14.0, sides=5), "Cage", "cantor_cable", cable_paint, ao=False)
    # Crown: a knot where the ribs and anchor lines meet, with glowing fruit-like nodes.
    crown = ellipsoid((0, HY + 5.3, 0), (0.9, 0.7, 0.9), segs=18, rings=12,
                      fn=lambda u: 1.0 + 0.18 * math.sin(math.atan2(u.z, u.x) * 6) * (1 - abs(u.y)))
    crown.bumps(0.08, 2.5, 3.0, 2)
    c.part(crown, "Crown", "cantor_cable", cable_paint)
    for i in range(4):
        a = TAU * i / 4 + math.pi / 4
        d = V((math.cos(a), 0, math.sin(a)))
        c.part(braid([V((0, HY + 5.4, 0)) + d * 0.5, V((0, HY + 6.2, 0)) + d * 1.6, V((0, HY + 6.6, 0)) + d * 2.6], 0.24, strands=3,
                     twist=3.0), "Crown", "cantor_cable", cable_paint, ao=False)
        c.part(ellipsoid(V((0, HY + 5.0, 0)) + d * 0.9, (0.22, 0.28, 0.22), segs=10, rings=6), "Crown", "cantor_glow", "ffc49a", ao=False)
    # Bottom knot and the frayed root tendrils trailing toward the floor.
    knot = ellipsoid((0, HY - 5.2, 0), (0.75, 0.55, 0.75), segs=16, rings=10)
    knot.bumps(0.08, 2.5, 4.0, 2)
    c.part(knot, "Cage", "cantor_cable", cable_paint)
    for i in range(9):
        a = TAU * i / 9 + 0.3
        d = V((math.cos(a), 0, math.sin(a)))
        ln = 2.4 + 1.2 * ((i * 5) % 3) / 2
        pts = [V((0, HY - 5.4, 0)) + d * 0.4, V((0, HY - 5.4 - ln * 0.4, 0)) + d * 0.9, V((0, HY - 5.4 - ln, 0)) + d * 1.3]
        c.part(tube(pts, [0.12, 0.08, 0.02], sides=6, samples=4, caps=("round", "point")), "Cage", "cantor_cable", cable_paint, ao=False)

    # The heart-node: a knotted teal organ, lobed, with veins.
    def heart_fn(u):
        return 1.0 + 0.12 * math.sin(u.x * 5 + 1) * math.sin(u.y * 4) * math.sin(u.z * 5 + 2) + 0.05 * math.sin(math.atan2(u.z, u.x) * 5)

    heart = ellipsoid((0, HY, 0), (1.05, 1.2, 1.05), segs=28, rings=18, fn=heart_fn)
    heart.bumps(0.03, 3.0, 5.0, 2)
    c.part(heart, "Heart", "cantor_heart",
           lambda p, n: mix(C("0f6a5c"), C("8cfbea"), smooth(0.25, 0.75, 0.5 + 0.5 * fbm(p, 2.2, 3, 6.0))), ao=False)
    # The cables it hangs from inside the cage.
    for i in range(3):
        a = TAU * i / 3 + 0.5
        d = V((math.cos(a), 0, math.sin(a)))
        c.part(tube([V((0, HY + 1.0, 0)) + d * 0.3, V((0, HY + 3.0, 0)) + d * 0.7, V((0, HY + 4.9, 0)) + d * 0.3], [0.1, 0.08, 0.12],
                    sides=6, samples=4), ["Heart", "Crown"], "cantor_cable", cable_paint, ao=False, falloff=2.0)
        c.part(tube([V((0, HY - 1.0, 0)) + d * 0.3, V((0, HY - 3.0, 0)) + d * 0.7, V((0, HY - 5.0, 0)) + d * 0.3], [0.1, 0.08, 0.12],
                    sides=6, samples=4), ["Heart", "Cage"], "cantor_cable", cable_paint, ao=False, falloff=2.0)

    # Petals: woven shields round the heart, hinged at the top, each a curved leaf of cable.
    for i in range(3):
        a = TAU * i / 3
        d = V((math.sin(a), 0, -math.cos(a)))
        side = V((-d.z, 0, d.x))
        ea, eb = [], []
        for k in range(9):
            t = k / 8
            y = HY + 1.6 - 3.2 * t
            w = 1.75 * math.sin(math.pi * (0.08 + 0.84 * t)) + 0.05
            bulge = 1.3 + 0.3 * math.sin(math.pi * t)
            ea.append(V((0, y, 0)) + d * bulge - side * w)
            eb.append(V((0, y, 0)) + d * bulge + side * w)
        pet = sheet(ea, eb, nv=8, thick=0.16, camber=lambda u, v: 0.45 * math.sin(v * math.pi))
        pet.plates(0.03, 3.0, float(i))

        def petal_paint(p, n, i=i):
            weave = 0.5 + 0.5 * math.sin(p.y * 9.0) * math.sin((p.x + p.z) * 9.0)
            return mix(mix(C("4a3028"), C("8a6a5a"), weave), C("c08a70"), smooth(0.7, 1.0, n.y) * 0.3)
        c.part(pet, "Petal%d" % (i + 1), "cantor_petal", petal_paint)
        # A spine of cable down the middle of each petal.
        c.part(tube([V((0, HY + 1.6, 0)) + d * 1.35, V((0, HY, 0)) + d * 1.95, V((0, HY - 1.6, 0)) + d * 1.4], [0.13, 0.15, 0.06],
                    sides=6, samples=5, caps=("round", "point")), "Petal%d" % (i + 1), "cantor_cable", cable_paint)
    c.build(ao_reach=1.5)

    def petals(open_deg):
        out = {}
        for i in range(3):
            a = TAU * i / 3
            d = V((math.sin(a), 0, -math.cos(a)))
            ax = V((-d.z, 0, d.x))
            out["Petal%d" % (i + 1)] = axis(ax, open_deg)
        return out

    c.cycle("idle", 120, lambda ph: ({"Cage": (1.2 * math.sin(ph), 0, 1.2 * math.cos(ph)), "Crown": (0, 4 * math.sin(ph), 0)},
                                     {"Heart": (0, 0.05 * math.sin(ph * 2), 0)}, {"Heart": 1.0 + 0.04 * math.sin(ph * 2)}), steps=8)
    for name in ("listen", "respond", "resolve"):
        c.cycle(name, 138, lambda ph: (
            merge({"Cage": (1.5 * math.sin(ph), 0, 1.5 * math.cos(ph)), "Crown": (0, 6 * math.sin(ph), 0)}),
            {"Heart": (0, 0.06 * math.sin(ph * 3), 0)}, {"Heart": 1.0 + 0.06 * math.sin(ph * 3)}), steps=12)
    c.cycle("walk", 60, lambda ph: ({"Cage": (2 * math.sin(ph), 0, 0)},), steps=4)
    # Held open (the game crossfades into it), the heart beating.
    c.cycle("open", 24, lambda ph: (merge(petals(68.0 + 3 * math.sin(ph)), {"Cage": (1.0 * math.sin(ph), 0, 0)}), {},
                                    {"Heart": 1.08 + 0.06 * math.sin(ph * 2)}), steps=8)
    c.clip("hurt", [(0, {}, {}, {}), (3, {"Cage": (3, 0, 2)}, {}, {"Heart": 0.9}), (8, {}, {}, {"Heart": 1.04}), (12, {}, {}, {})])
    c.clip("die", [(0, petals(66.0)), (20, merge(petals(95.0), {"Cage": (6, 0, 4)}), {}, {"Heart": 1.25}),
                   (50, merge(petals(110.0), {"Cage": (10, 0, 8)}), {"Heart": (0, -1.5, 0)}, {"Heart": 0.6})])
    c.export()


# --- Scuttler ----------------------------------------------------------------------------

BASALT = "1b1d20"
OXIDE = "b4612a"


def basalt_shell(seed=0.0, rim=0.6):
    """Basalt-dark chitin that passes for rock, its plate edges weathered to oxide orange."""
    base = mottled("181a1d", "2e3236", freq=6.0, seed=seed)

    def paint(p, n):
        c = base(p, n)
        edge = smooth(0.62, 0.12, n.y) * rim
        c = mix(c, mix(C("7a3a1a"), C(OXIDE), 0.5 + 0.5 * fbm(p, 9.0, 2, seed)), edge * (0.55 + 0.45 * fbm(p, 5.0, 2, seed + 3)))
        return mix(c, C("4c555c"), smooth(0.55, 1.0, n.y) * 0.35)
    return paint


def scuttler():
    """Basin scuttler: a basalt-backed hunter the size of a big dog, on six spiked legs with the
    knees above its back. Overlapping dorsal plates with oxide rims and side spines, a ridge of
    teal moss crystals down the spine (the weak spot), a low wedge head with four teal eyes and
    sickle mandibles."""
    c = Creature("scuttler")
    c.material("scuttler_shell", rough=0.5, metal=0.15)
    c.material("scuttler_belly", rough=0.8)
    c.material("moss_glow", rough=0.4, emit="3fd1b5", energy=3.0)

    c.bone("Body", (0, 0.5, 0.05), (0, 0.5, -0.45))
    c.bone("Head", (0, 0.52, -0.6), (0, 0.47, -0.9), "Body")
    for side, s in (("L", -1.0), ("R", 1.0)):
        c.bone("Jaw" + side, (0.1 * s, 0.43, -0.86), (0.07 * s, 0.4, -1.14), "Head")

    shell_paint = basalt_shell(1.0)
    leg_paint = basalt_shell(4.0, rim=0.3)
    belly = mottled("24272a", "33383b", freq=8.0, seed=2.0)

    # Core and underside.
    core = ellipsoid((0, 0.5, 0.12), (0.4, 0.24, 0.66), segs=22, rings=14,
                     fn=lambda u: 1.0 + 0.06 * math.sin(u.z * 18.0) * smooth(0.2, -0.6, u.y))
    c.part(core, "Body", "scuttler_belly", belly)
    # Rear: the abdomen narrows to a blunt point.
    c.part(tube([(0, 0.52, 0.55), (0, 0.5, 0.82), (0, 0.44, 0.98)], [0.24, 0.16, 0.05], sides=10, samples=3, caps=("flat", "point")),
           "Body", "scuttler_belly", belly)
    # Overlapping dorsal plates, front to back, each one riding up over the next.
    for i, z in enumerate((-0.36, -0.08, 0.2, 0.48, 0.74)):
        w = (0.46, 0.52, 0.5, 0.42, 0.3)[i]
        plate = shell((0, 0.56 - 0.02 * i, z), (w, 0.27 - 0.02 * i, 0.24), cover=0.44, thick=0.05, segs=18, rings=7,
                      rot=(8, 0, 0), lip=0.12)
        plate.plates(0.006, 14.0, float(i))
        c.part(plate, "Body", "scuttler_shell", shell_paint, hard=50)
        # Side spines off each plate's rim, raked back.
        for s in (-1.0, 1.0):
            base = V((w * 0.86 * s, 0.6 - 0.02 * i, z + 0.05))
            c.part(spike(base, base + V((0.16 * s, 0.14, 0.2)), 0.045, sides=5, bend=base + V((0.12 * s, 0.04, 0.08))),
                   "Body", "scuttler_shell", shell_paint)
    # The moss ridge: teal crystals down the spine, tallest over the middle.
    for i, z in enumerate((-0.3, -0.06, 0.18, 0.42, 0.64)):
        h = (0.14, 0.24, 0.28, 0.22, 0.14)[i]
        y0 = 0.8 - 0.02 * i
        c.part(spike((0, y0, z), (0, y0 + h, z + 0.12), 0.06, sides=6), "Body", "moss_glow",
               lambda p, n: mix(C("1f8f7a"), C("9ffbe9"), smooth(0.8, 1.05, p.y)), ao=False)
        for s in (-1.0, 1.0):
            c.part(spike((0.08 * s, y0 - 0.02, z + 0.04), (0.14 * s, y0 + h * 0.5, z + 0.12), 0.035, sides=5), "Body", "moss_glow",
                   lambda p, n: mix(C("1f8f7a"), C("7df5dc"), smooth(0.8, 1.0, p.y)), ao=False)

    # Head: a low wedge under a brow shield that ends in two short horns.
    head = ellipsoid((0, 0.5, -0.74), (0.22, 0.14, 0.2), segs=16, rings=10,
                     fn=lambda u: 1.0 - 0.25 * smooth(0.0, 1.0, -u.z) * smooth(-0.2, 0.6, -u.y))
    c.part(head, ["Head", "Body"], "scuttler_belly", belly, falloff=5.0)
    brow = shell((0, 0.52, -0.72), (0.27, 0.17, 0.26), cover=0.42, thick=0.04, segs=16, rings=6, rot=(-6, 0, 0), lip=0.1)
    c.part(brow, "Head", "scuttler_shell", shell_paint, hard=50)
    for s in (-1.0, 1.0):
        b = V((0.15 * s, 0.6, -0.86))
        c.part(spike(b, b + V((0.08 * s, 0.1, -0.14)), 0.04, sides=5), "Head", "scuttler_shell", "3a2a20")
        # Eyes: a big pair and a small pair, under the brow.
        for x, y, z, r in ((0.11, 0.53, -0.92, 0.04), (0.05, 0.56, -0.95, 0.026)):
            c.part(ellipsoid((x * s, y, z), (r, r, r), segs=8, rings=5), "Head", "moss_glow", "9ffbe9", ao=False)
    # Sickle mandibles and a pair of palps.
    for side, s in (("L", -1.0), ("R", 1.0)):
        c.part(tube([(0.1 * s, 0.43, -0.86), (0.15 * s, 0.41, -1.0), (0.11 * s, 0.39, -1.12), (0.02 * s, 0.38, -1.17)],
                    [0.04, 0.032, 0.02, 0.004], sides=6, samples=3, caps=("round", "point")),
               "Jaw" + side, "scuttler_shell", lambda p, n: mix(C("2a1d17"), C("c27a3e"), smooth(-1.0, -1.16, p.z)))
        c.part(tube([(0.06 * s, 0.42, -0.88), (0.09 * s, 0.34, -0.98), (0.07 * s, 0.3, -1.04)], [0.018, 0.014, 0.01], sides=5, samples=2),
               "Head", "scuttler_belly", "3a3f42")

    # Six legs, knees high, feet like picks.
    legs = []
    for side, s in (("L", -1.0), ("R", 1.0)):
        for row in (1, 2, 3):
            hz, kz, fz = ((-0.32, -0.62, -1.0), (0.02, 0.0, 0.02), (0.34, 0.62, 0.95))[row - 1]
            hip = V((0.34 * s, 0.47, hz))
            knee = V((0.8 * s, 0.9 - 0.04 * (row == 3), kz))
            foot = V(((1.18 if row == 2 else 1.08) * s, 0.0, fz))
            thigh = c.bone("Leg%s%d" % (side, row), hip, knee, "Body")
            shin = c.bone("Foot%s%d" % (side, row), knee, foot, thigh)
            phase = math.pi * ((row - 1 + (1 if s > 0 else 0)) % 2)
            legs.append((thigh, shin, phase))
            bow = hip.lerp(knee, 0.5) + V((0, 0.05, 0))
            c.part(tube([hip, bow, knee], [(0.075, 0.09), (0.065, 0.08), 0.055], sides=8, samples=4),
                   thigh, "scuttler_shell", leg_paint)
            c.part(ellipsoid(hip, (0.09, 0.09, 0.09), segs=10, rings=6), ["Body", thigh], "scuttler_belly", belly)
            c.part(ellipsoid(knee, (0.07, 0.08, 0.07), segs=10, rings=6), [thigh, shin], "scuttler_shell",
                   lambda p, n: mix(C("2a2c30"), C(OXIDE), smooth(0.2, 1.0, n.y) * 0.6), falloff=2.0)
            # A spur off the top of the knee.
            c.part(spike(knee + V((0, 0.04, 0)), knee + V((0.1 * s, 0.2, 0.06)), 0.035, sides=5), thigh, "scuttler_shell", "2a2220")
            mid = knee.lerp(foot, 0.45) + V((0.06 * s, 0, 0))
            c.part(tube([knee, mid, foot + V((-0.02 * s, 0.14, 0)), foot], [0.05, 0.04, 0.026, 0.004], sides=7, samples=4,
                        caps=("round", "point")), shin, "scuttler_shell",
                   lambda p, n: mix(mix(C("1c1e21"), C("33373b"), smooth(0.3, 1.0, n.y)), C("8a5a36"), smooth(0.25, 0.0, p.y) * 0.7))
            # Little back-raked barbs down the shin.
            for k in (0.3, 0.6):
                at = knee.lerp(foot, k)
                c.part(spike(at, at + V((0.06 * s, 0.03, 0.08)), 0.018, sides=4), shin, "scuttler_shell", "2a2220")
    c.build()

    g = Gait(c, "Body", legs)

    def body(posed, extra=None, offsets=None, scales=None):
        pose, offs = posed
        return (merge(pose, extra or {}), merge(offs, offsets or {}), scales or {})

    def jaws(deg):
        return {"JawL": (0, deg, 0), "JawR": (0, -deg, 0)}

    # Idle (2.7 s): breathing, head tasting the air, one foot then another shifting.
    def idle(ph):
        lift = {}
        if 0.6 < ph < 1.6:
            lift["LegL2"] = (0, 0.1 * math.sin((ph - 0.6) * math.pi), -0.06 * math.sin((ph - 0.6) * math.pi))
        if 3.6 < ph < 4.6:
            lift["LegR1"] = (0, 0.12 * math.sin((ph - 3.6) * math.pi), -0.08 * math.sin((ph - 3.6) * math.pi))
        return body(g.stand((0, 0.015 * math.sin(ph), 0), (1.5 * math.sin(ph), 0, 0), feet=lift),
                    merge({"Head": (3 * math.sin(ph * 2), 14 * math.sin(ph), 0)}, jaws(5 + 5 * math.sin(ph * 3))))
    c.cycle("idle", 80, idle, steps=16)
    # Walk (0.8 s, 1.5 m): alternating tripods, feet planted, the body rolling over them.
    c.cycle("walk", 24, lambda ph: body(
        g.step(ph, 0.75, 0.26, (0, 0.02 * math.sin(ph * 2), 0), (0, 2 * math.sin(ph * 2), 3 * math.sin(ph))),
        merge({"Head": (0, -6 * math.sin(ph), 0)}, jaws(4))), steps=12)
    # Wind-up: crouched at the back, front reared, front feet raised and jaws gaping, trembling.
    rear = {"LegL1": (0, 0.42, -0.1), "LegR1": (0, 0.42, -0.1)}
    c.cycle("windup", 15, lambda ph: body(
        g.stand((0, 0.04, 0.12), (13 + 1.0 * math.sin(ph * 2), 0, 0), spread=1.05, feet=rear),
        merge({"Head": (8, 0, 0)}, jaws(32 + 4 * math.sin(ph * 2)))), steps=6)
    # Attack (0.35 s): thrown forward and down from the wind-up, front feet driving in, jaws snapping.
    lunge = {"LegL1": (0, 0.0, -0.35), "LegR1": (0, 0.0, -0.35)}
    c.clip("attack", [(0,) + body(g.stand((0, 0.04, 0.12), (13, 0, 0), 1.05, rear), merge({"Head": (8, 0, 0)}, jaws(34))),
                      (4,) + body(g.stand((0, -0.1, -0.32), (-14, 0, 0), 1.05, lunge), merge({"Head": (-12, 0, 0)}, jaws(-12))),
                      (10,) + body(g.stand((0, -0.06, -0.2), (-8, 0, 0), 1.05, lunge), merge({"Head": (-6, 0, 0)}, jaws(6)))])
    c.clip("hurt", [(0,) + body(g.stand()),
                    (2,) + body(g.stand((0.05, 0.02, 0.06), (-6, 0, 9)), {"Head": (12, 8, 0)}),
                    (5,) + body(g.stand((-0.02, 0, 0), (2, 0, -6)), {"Head": (6, -4, 0)}),
                    (9,) + body(g.stand())])
    # Stagger: reeling, legs splayed wide to catch itself, head hanging.
    c.cycle("stagger", 12, lambda ph: body(
        g.stand((0.05 * math.sin(ph), -0.08, 0.04), (-5, 6 * math.sin(ph), 10 * math.sin(ph)), spread=1.15),
        merge({"Head": (-18, 0, 0)}, jaws(14))), steps=4)
    # Die (0.6 s; the game rolls it over): legs spasm, then curl up under the shell.
    curl = {}
    for thigh, shin, _ in legs:
        s = -1.0 if thigh[3] == "L" else 1.0
        curl[thigh] = (0, 0, -s * 52)
        curl[shin] = (0, 0, -s * 60)
    c.clip("die", [(0,) + body(g.stand()),
                   (4,) + body(g.step(1.0, 0.7, 0.35, (0, 0.06, 0), (-8, 0, 6)), {"Head": (14, 0, 0)}),
                   (10, merge(curl, {"Head": (-25, 0, 0)}, jaws(22)), {"Body": (0, -0.1, 0)}),
                   (18, merge(curl, {"Head": (-26, 0, 0)}, jaws(26)), {"Body": (0, -0.12, 0)})])
    c.export()


# --- Spitter -----------------------------------------------------------------------------

def spitter():
    """Spitter: a stilt-legged acid lobber. A small armoured thorax slung between four tall
    legs, a long arched neck ending in a ringed spout, and a swollen yellow-green acid sac on its
    back (the weak spot) that glows brighter as it draws up a shot."""
    c = Creature("spitter")
    c.material("spitter_hide", rough=0.75)
    c.material("spitter_plate", rough=0.5, metal=0.2)
    c.material("acid_sac", rough=0.3, emit="b4e05a", energy=2.0)
    c.material("moss_glow", rough=0.4, emit="3fd1b5", energy=3.0)

    c.bone("Body", (0, 0.9, 0.2), (0, 0.9, -0.3))
    c.bone("Sac", (0, 1.22, 0.32), (0, 1.5, 0.32), "Body")
    c.bone("Neck", (0, 1.0, -0.32), (0, 1.32, -0.58), "Body")
    c.bone("Head", (0, 1.34, -0.6), (0, 1.32, -0.88), "Neck")

    hide = mottled("23281f", "39402f", freq=7.0, seed=5.0, belly="5a5a48", belly_at=-0.3)
    plate = basalt_shell(6.0, rim=0.8)

    # Thorax and a short segmented abdomen under the sac.
    c.part(ellipsoid((0, 0.9, -0.05), (0.3, 0.24, 0.36), segs=18, rings=12), "Body", "spitter_hide", hide)
    c.part(ellipsoid((0, 0.92, 0.38), (0.26, 0.22, 0.3), segs=16, rings=10,
                     fn=lambda u: 1.0 + 0.05 * math.sin(u.z * 16.0)), "Body", "spitter_hide", hide)
    for i, z in enumerate((-0.28, -0.08, 0.12)):
        pl = shell((0, 0.94, z), (0.32, 0.22, 0.17), cover=0.42, thick=0.04, segs=16, rings=6, rot=(8, 0, 0), lip=0.1)
        c.part(pl, "Body", "spitter_plate", plate, hard=50)
    # The sac: a swollen bladder in a cradle of ribs.
    sac = ellipsoid((0, 1.28, 0.34), (0.3, 0.26, 0.36), segs=20, rings=14,
                    fn=lambda u: 1.0 + 0.04 * math.sin(math.atan2(u.z, u.x) * 6.0) * (1.0 - abs(u.y)))

    def sac_paint(p, n):
        vein = smooth(0.08, 0.0, abs(fbm(p, 6.0, 2, 4.0)))
        return mix(mix(C("8fbf2e"), C("e6ff8a"), smooth(1.15, 1.5, p.y)), C("3d5a12"), vein * 0.7)
    c.part(sac, "Sac", "acid_sac", sac_paint, ao=False)
    for k in range(5):
        a = math.pi * (0.15 + 0.7 * k / 4)
        x = math.cos(a)
        c.part(tube([(0.2 * x, 1.06, 0.34 + 0.32 * x * 0), (0.33 * x, 1.24, 0.34 - 0.24 * (k - 2) / 2),
                     (0.18 * x, 1.48, 0.34 - 0.3 * (k - 2) / 2)], [0.025, 0.022, 0.012], sides=5, samples=3),
               ["Body", "Sac"], "spitter_plate", "2b2a22", falloff=2.0)
    # Neck: arched and ringed, thick at the shoulders.
    neck_pts = [(0, 0.98, -0.3), (0, 1.16, -0.42), (0, 1.3, -0.56)]
    c.part(tube(neck_pts, [0.15, 0.11, 0.09], sides=10, samples=4,
                profile=lambda a, t: 1.0 + 0.1 * max(0.0, math.sin(t * 28.0))), ["Body", "Neck", "Head"], "spitter_hide", hide, falloff=3.0)
    # Head: narrow, with a ringed spout and eyes set back on the sides.
    head = ellipsoid((0, 1.33, -0.68), (0.13, 0.11, 0.17), segs=14, rings=9,
                     fn=lambda u: 1.0 - 0.2 * smooth(0.0, 1.0, -u.z) * abs(u.x))
    c.part(head, "Head", "spitter_hide", hide)
    c.part(shell((0, 1.36, -0.68), (0.15, 0.1, 0.19), cover=0.4, thick=0.03, segs=14, rings=5, lip=0.12), "Head", "spitter_plate", plate, hard=50)
    spout = hollow([(0.06, 0.0), (0.075, 0.08), (0.065, 0.16), (0.075, 0.2), (0.05, 0.2), (0.045, 0.1), (0.04, 0.0)],
                   at=(0, 1.31, -0.8), segs=12, rot=(-90, 0, 0))
    c.part(spout, "Head", "spitter_plate", lambda p, n: mix(C("2c2a22"), C(OXIDE), smooth(-0.9, -1.0, p.z)), hard=60)
    c.part(ellipsoid((0, 1.31, -0.98), (0.045, 0.045, 0.02), segs=10, rings=5), "Head", "acid_sac", "e6ff8a", ao=False)
    for s in (-1.0, 1.0):
        c.part(ellipsoid((0.1 * s, 1.38, -0.74), (0.03, 0.03, 0.03), segs=8, rings=5), "Head", "moss_glow", "9ffbe9", ao=False)
        c.part(ellipsoid((0.07 * s, 1.41, -0.8), (0.018, 0.018, 0.018), segs=6, rings=4), "Head", "moss_glow", "9ffbe9", ao=False)

    # Four stilt legs, knees out and up.
    legs = []
    for side, s in (("L", -1.0), ("R", 1.0)):
        for row in (1, 2):
            hip = V((0.24 * s, 0.84, -0.2 if row == 1 else 0.2))
            knee = V((0.66 * s, 1.3, -0.5 if row == 1 else 0.55))
            foot = V((0.92 * s, 0.0, -0.78 if row == 1 else 0.86))
            thigh = c.bone("Leg%s%d" % (side, row), hip, knee, "Body")
            shin = c.bone("Foot%s%d" % (side, row), knee, foot, thigh)
            legs.append((thigh, shin, math.pi * ((row - 1 + (1 if s > 0 else 0)) % 2)))
            c.part(tube([hip, hip.lerp(knee, 0.5) + V((0, 0.05, 0)), knee], [0.07, 0.055, 0.045], sides=8, samples=4),
                   thigh, "spitter_hide", hide)
            c.part(ellipsoid(knee, (0.06, 0.07, 0.06), segs=10, rings=6), [thigh, shin], "spitter_plate",
                   lambda p, n: mix(C("3a2a20"), C(OXIDE), smooth(0.0, 1.0, n.y) * 0.8), falloff=2.0)
            c.part(tube([knee, knee.lerp(foot, 0.5) + V((0.05 * s, 0, 0)), foot + V((0, 0.1, 0)), foot], [0.045, 0.034, 0.022, 0.004],
                        sides=7, samples=4, caps=("round", "point")), shin, "spitter_plate",
                   lambda p, n: mix(C("22251e"), C("8a5a36"), smooth(0.3, 0.0, p.y) * 0.7))
            c.part(spike(knee + V((0, 0.03, 0)), knee + V((0.06 * s, 0.16, 0.05 if row == 2 else -0.05)), 0.03, sides=5),
                   thigh, "spitter_plate", "2a2220")
    c.build()

    g = Gait(c, "Body", legs)

    def body(posed, extra=None, scales=None):
        pose, offs = posed
        return (merge(pose, extra or {}), offs, scales or {})

    c.cycle("idle", 60, lambda ph: body(
        g.stand((0, 0.015 * math.sin(ph), 0), (2 * math.sin(ph), 0, 0)),
        {"Neck": (3 * math.sin(ph), 6 * math.sin(ph), 0), "Head": (-2 * math.sin(ph), 10 * math.sin(ph * 2), 0)},
        {"Sac": 1.0 + 0.05 * math.sin(ph * 2)}), steps=8)
    c.cycle("walk", 24, lambda ph: body(
        g.step(ph, 0.75, 0.22, (0, 0.03 * math.sin(ph * 2), 0), (0, 0, 3 * math.sin(ph))),
        {"Neck": (4 * math.sin(ph * 2), 0, 0)}, {"Sac": 1.0 + 0.04 * math.sin(ph * 2)}), steps=12)
    # Wind-up: up on its toes, neck drawn back, head kept level to aim, the sac swelling.
    brace = {"LegL1": (0, 0, -0.12), "LegR1": (0, 0, -0.12)}
    c.cycle("windup", 18, lambda ph: body(
        g.stand((0, 0.16, 0.06), (8, 0, 0), feet=brace),
        {"Neck": (32 + 2 * math.sin(ph * 2), 0, 0), "Head": (-14, 0, 0)}, {"Sac": 1.3 + 0.05 * math.sin(ph * 3)}), steps=6)
    # Attack: the neck whips forward and spits; the sac empties.
    c.clip("attack", [(0,) + body(g.stand((0, 0.16, 0.06), (8, 0, 0), feet=brace), {"Neck": (34, 0, 0), "Head": (-14, 0, 0)}, {"Sac": 1.32}),
                      (3,) + body(g.stand((0, 0.05, -0.1), (-6, 0, 0), feet=brace), {"Neck": (-40, 0, 0), "Head": (8, 0, 0)}, {"Sac": 0.75}),
                      (10,) + body(g.stand((0, 0.0, -0.04), (-3, 0, 0)), {"Neck": (-18, 0, 0), "Head": (4, 0, 0)}, {"Sac": 0.9})])
    c.clip("hurt", [(0,) + body(g.stand()),
                    (2,) + body(g.stand((0.04, 0, 0.05), (-5, 0, 8)), {"Neck": (10, 0, 0), "Head": (10, 6, 0)}, {"Sac": 0.9}),
                    (5,) + body(g.stand((-0.02, 0, 0), (2, 0, -5))),
                    (9,) + body(g.stand())])
    # Die: the legs splay and the body drops between them, neck sagging (the game tips it over).
    c.clip("die", [(0,) + body(g.stand()),
                   (5,) + body(g.stand((0, 0.08, 0), (-10, 0, 0)), {"Neck": (20, 0, 0)}, {"Sac": 1.2}),
                   (13,) + body(g.stand((0, -0.62, 0), (4, 0, 6), spread=1.35), {"Neck": (-25, 0, 0), "Head": (-25, 0, 0)}, {"Sac": 0.85}),
                   (19,) + body(g.stand((0, -0.66, 0), (5, 0, 7), spread=1.38), {"Neck": (-30, 0, 0), "Head": (-25, 0, 0)}, {"Sac": 0.8})])
    c.export()


CREATURES = {"drifter": drifter, "veilwing": veilwing, "ridge_diver": ridge_diver, "pinweaver": pinweaver, "chord_singer": chord_singer, "patience_guardian": patience_guardian, "cantor": cantor, "scuttler": scuttler, "spitter": spitter}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in args or list(CREATURES):
        CREATURES[name]()


if __name__ == "__main__":
    main()
