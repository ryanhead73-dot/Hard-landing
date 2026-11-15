"""Builds the survivors at the greenhouses as skinned people, one GLB each, with creature_kit.

    python blender/build_people.py                # all of them (with `pip install bpy==4.2.0`)
    python blender/build_people.py -- reyes       # just one

Each person is one skinned mesh (painted in vertex colour) on a skeleton named like Juno's
(Hips, Spine, Chest, Neck, Head, ArmL/R, ForearmL/R, LegL/R, ShinL/R), built from a spec: height
and build, skin, face, hair, clothes and kit, and the crew colours (Ferro-9 grey and amber, the
Voss expedition's khaki and green). Clips: idle, crouch (working low, hands busy), watch
(shading the eyes, scanning), at_ease (hands behind the back) and talk.
Output: godot/assets/models/person_<name>.glb and blender/person_<name>.blend.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from creature_kit import (C as _C, Creature, Rot, godot_basis, V, ellipsoid, fbm, lathe, merge, mix, shell, slab, smooth, spike, tube)  # noqa: E402

TAU = 2 * math.pi


def C(hexcol):
    """A colour as a Vector, so it can be scaled and added."""
    return V(_C(hexcol))

FERRO = ("5f6b72", "c98a3c")
EXPEDITION = ("7d6e58", "5f8f4e")

PEOPLE = {
    # Lieutenant Sana Reyes, Ferro-9's commander: tall, officer's jacket with amber boards, hair
    # pulled back in a bun, sidearm.
    "reyes": {"height": 1.03, "build": 0.95, "skin": "b07a55", "hair": "1d1612", "style": "bun", "crew": FERRO,
              "jacket": True, "boards": True, "holster": True},
    # Okafor, the medic: medium height, cropped hair, a med satchel and a pale armband.
    "okafor": {"height": 0.98, "build": 1.0, "skin": "5a3a28", "hair": "120d0b", "style": "crop", "crew": FERRO,
               "satchel": True, "armband": True},
    # Brandt, Ferro-9's pilot: older and broad, beard, flight jacket with a fleece collar, cap.
    "brandt": {"height": 1.0, "build": 1.15, "skin": "c99a7a", "hair": "7a7068", "style": "cap", "beard": True, "crew": FERRO,
               "jacket": True, "fleece": True},
    # Haddad, the lookout: lean, hooded, a scarf, binoculars on the chest.
    "haddad": {"height": 1.01, "build": 0.88, "skin": "9a6b4a", "hair": "1a1410", "style": "hood", "crew": EXPEDITION,
               "scarf": True, "binoculars": True},
    # Teo, who keeps the beds: short and stocky, beanie, apron, sleeves rolled, gloves.
    "teo": {"height": 0.94, "build": 1.1, "skin": "c08a62", "hair": "3a2a1e", "style": "beanie", "crew": EXPEDITION,
            "apron": True, "rolled": True, "gloves": True},
}


def person(name, spec):
    c = Creature("person_" + name)
    c.material("person_cloth", rough=0.88)
    c.material("person_skin", rough=0.55)
    c.material("person_hair", rough=0.75)
    c.material("person_gear", rough=0.45, metal=0.3)

    k = spec["height"]
    w = spec["build"]
    suit, trim = C(spec["crew"][0]), C(spec["crew"][1])
    skin = C(spec["skin"])

    def P(x, y, z):
        """Model space for this person: taller people are scaled up, broader ones widened."""
        return V((x * k * w, y * k, z * k * (0.5 + 0.5 * w)))

    # Skeleton (Juno's names, so poses read the same).
    c.bone("Hips", P(0, 0.95, 0), P(0, 1.07, 0))
    c.bone("Spine", P(0, 1.07, 0), P(0, 1.32, 0), "Hips")
    c.bone("Chest", P(0, 1.32, 0), P(0, 1.66, 0), "Spine")
    c.bone("Neck", P(0, 1.66, 0), P(0, 1.75, 0), "Chest")
    c.bone("Head", P(0, 1.75, 0), P(0, 1.98, 0), "Neck")
    for side, s in (("L", -1.0), ("R", 1.0)):
        c.bone("Arm" + side, P(0.2 * s, 1.58, 0), P(0.235 * s, 1.3, 0.02), "Chest")
        c.bone("Forearm" + side, P(0.235 * s, 1.3, 0.02), P(0.25 * s, 1.04, -0.02), "Arm" + side)
        c.bone("Leg" + side, P(0.1 * s, 0.9, 0), P(0.1 * s, 0.49, -0.025), "Hips")
        c.bone("Shin" + side, P(0.1 * s, 0.49, -0.025), P(0.1 * s, 0.08, 0), "Leg" + side)

    def cloth(base, seed=0.0, dark=0.25):
        """Woven cloth: a little noise, darker in folds and underneath."""
        def paint(p, n):
            col = mix(base, base * 0.75, 0.5 + 0.5 * fbm(p, 18.0, 2, seed))
            return mix(col, base * (1.0 - dark), smooth(0.0, -0.8, n.y))
        return paint

    trousers = C("3a3d40") if spec["crew"] == FERRO else C("4e4a3e")
    top = suit

    def body_paint(p, n):
        y = p.y / k
        if y < 0.985:
            col = cloth(trousers, 1.0)(p, n)
        else:
            col = cloth(top, 2.0)(p, n)
        if 0.975 < y < 1.03:  # belt
            col = C("2a2522")
        return col

    # Torso: hips to collar, one blended tube.
    rr = lambda a, b: (a * k * w, b * k * (0.5 + 0.5 * w))
    torso = tube([P(0, 0.86, 0), P(0, 0.98, 0), P(0, 1.12, 0), P(0, 1.32, 0), P(0, 1.5, 0), P(0, 1.63, 0), P(0, 1.68, 0)],
                 [rr(0.16, 0.11), rr(0.165, 0.115), rr(0.145, 0.105), rr(0.165, 0.115), rr(0.19, 0.125), rr(0.17, 0.11), rr(0.07, 0.07)],
                 sides=14, samples=3, caps=("round", "flat"))
    c.part(torso, ["Hips", "Spine", "Chest"], "person_cloth", body_paint, falloff=3.0)
    # Shoulders.
    for s in (-1.0, 1.0):
        c.part(ellipsoid(P(0.17 * s, 1.58, 0), (0.08 * k * w, 0.07 * k, 0.075 * k), segs=10, rings=7), ["Chest", "Arm" + ("L" if s < 0 else "R")],
               "person_cloth", cloth(top, 3.0), falloff=3.0)
    # Neck.
    c.part(tube([P(0, 1.62, 0.0), P(0, 1.72, 0.005), P(0, 1.79, 0.01)], [0.055 * k, 0.05 * k, 0.05 * k], sides=10, samples=2),
           ["Chest", "Neck", "Head"], "person_skin", lambda p, n: skin * 0.92, falloff=3.0)

    # Jacket over the shirt: a looser layer from the waist to the collar, with a collar.
    if spec.get("jacket"):
        jacket = tube([P(0, 0.9, 0), P(0, 1.0, 0), P(0, 1.2, 0), P(0, 1.42, 0), P(0, 1.6, 0), P(0, 1.66, 0)],
                      [rr(0.18, 0.13), rr(0.175, 0.125), rr(0.17, 0.122), rr(0.2, 0.135), rr(0.185, 0.125), rr(0.1, 0.085)],
                      sides=14, samples=3, caps=("flat", "flat"))
        jcol = C("4a4038") if spec.get("fleece") else suit * 0.85

        def jacket_paint(p, n, jcol=jcol):
            col = cloth(jcol, 5.0, 0.3)(p, n)
            # A zip and seam down the front.
            if p.z < 0 and abs(p.x) < 0.01:
                col = C("1c1c1c")
            return col
        c.part(jacket, ["Hips", "Spine", "Chest"], "person_cloth", jacket_paint, falloff=3.0)
        collar = C("d8ccb4") if spec.get("fleece") else jcol
        c.part(lathe([(0.075 * k, 0.0), (0.1 * k, 0.02), (0.11 * k, 0.07), (0.085 * k, 0.08)], at=P(0, 1.62, 0.01), segs=14),
               ["Chest", "Neck"], "person_cloth", cloth(collar, 6.0), falloff=2.0)
        if spec.get("boards"):
            for s in (-1.0, 1.0):
                c.part(slab((0.09 * k, 0.012, 0.05 * k), at=P(0.15 * s, 1.645, 0), rot=(0, 0, -14 * s)), "Chest", "person_gear",
                       lambda p, n: trim)
    # Pockets on the chest.
    for s in (-1.0, 1.0):
        c.part(slab((0.08 * k, 0.09 * k, 0.02), at=P(0.09 * s, 1.43, -0.125 - (0.012 if spec.get("jacket") else 0.0)), bevel=0.005),
               "Chest", "person_cloth", cloth(top * 0.9, 7.0))
    # Crew patch on the left shoulder.
    c.part(ellipsoid(P(-0.235, 1.52, 0.0), (0.012, 0.035 * k, 0.035 * k), segs=8, rings=5), "ArmL", "person_cloth", lambda p, n: trim)

    # Arms: sleeves (or rolled to the elbow), hands.
    for side, s in (("L", -1.0), ("R", 1.0)):
        sh, el, wr = P(0.2 * s, 1.58, 0), P(0.235 * s, 1.3, 0.02), P(0.25 * s, 1.04, -0.02)
        sleeve = suit * 0.85 if spec.get("jacket") else top
        c.part(tube([sh, sh.lerp(el, 0.5), el], [0.06 * k * w, 0.055 * k * w, 0.048 * k * w], sides=10, samples=2),
               ["Arm" + side], "person_cloth", cloth(sleeve, 8.0), falloff=3.0)
        if spec.get("rolled"):
            c.part(tube([el, el + (wr - el) * 0.12], [0.056 * k * w, 0.054 * k * w], sides=10, samples=1), ["Arm" + side, "Forearm" + side],
                   "person_cloth", cloth(sleeve * 1.1, 9.0), falloff=3.0)
            fore = lambda p, n: skin
            mat = "person_skin"
        else:
            fore = cloth(sleeve, 10.0)
            mat = "person_cloth"
        c.part(tube([el, el.lerp(wr, 0.5), wr], [0.046 * k * w, 0.042 * k * w, 0.034 * k * w], sides=10, samples=2),
               ["Arm" + side, "Forearm" + side], mat, fore, falloff=4.0)
        if spec.get("armband") and side == "L":
            c.part(tube([sh.lerp(el, 0.45), sh.lerp(el, 0.62)], [0.062 * k * w, 0.058 * k * w], sides=10, samples=1, caps=("flat", "flat")),
                   "Arm" + side, "person_cloth", lambda p, n: C("e8e4dc"))
        hand_col = C("3a3328") if spec.get("gloves") else skin
        hand_mat = "person_cloth" if spec.get("gloves") else "person_skin"
        d = (wr - el).normalized()
        palm = wr + d * 0.07 * k
        c.part(ellipsoid(palm, (0.03 * k, 0.05 * k, 0.045 * k), segs=10, rings=7), "Forearm" + side, hand_mat, lambda p, n: hand_col)
        c.part(tube([palm + V((0, 0.01, -0.035 * k)), palm + V((0.01 * s, -0.035 * k, -0.05 * k))], [0.013 * k, 0.011 * k], sides=6, samples=1),
               "Forearm" + side, hand_mat, lambda p, n: hand_col)

    # Legs and boots.
    for side, s in (("L", -1.0), ("R", 1.0)):
        hp, kn, an = P(0.1 * s, 0.9, 0), P(0.1 * s, 0.49, -0.025), P(0.1 * s, 0.1, 0)
        c.part(tube([hp, hp.lerp(kn, 0.5), kn], [0.085 * k * w, 0.075 * k * w, 0.06 * k * w], sides=10, samples=2), ["Leg" + side, "Hips"],
               "person_cloth", cloth(trousers, 11.0), falloff=4.0)
        c.part(tube([kn, kn.lerp(an, 0.5), an + V((0, 0.08, 0))], [0.058 * k * w, 0.05 * k * w, 0.048 * k * w], sides=10, samples=2),
               ["Leg" + side, "Shin" + side], "person_cloth", cloth(trousers, 12.0), falloff=4.0)
        boot = ellipsoid(P(0.1 * s, 0.07, -0.045), (0.055 * k * w, 0.07 * k, 0.12 * k), segs=12, rings=8,
                         fn=lambda u: 1.0 - 0.35 * smooth(0.0, 1.0, u.y) * smooth(-0.2, -0.9, u.z))
        boot.deform(lambda v: V((v.x, max(v.y, 0.0), v.z)))
        c.part(boot, "Shin" + side, "person_gear", lambda p, n: mix(C("2a2420"), C("4a3e32"), smooth(0.02, 0.1, p.y)))
        c.part(tube([an + V((0, 0.02, 0)), an + V((0, 0.14 * k, 0))], [0.058 * k * w, 0.055 * k * w], sides=10, samples=1, caps=("flat", "flat")),
               "Shin" + side, "person_gear", lambda p, n: C("33291f"))

    # Head: skull, jaw, face.
    hc = P(0, 1.87, 0.0)

    def head_fn(u):
        r = 1.0
        r -= 0.16 * smooth(-0.2, -1.0, u.y) * smooth(-0.3, 0.6, abs(u.x))  # narrower jaw
        r += 0.06 * smooth(0.0, 0.8, u.z) * smooth(-0.2, 0.6, u.y)          # back of the skull
        r -= 0.08 * smooth(0.4, 1.0, abs(u.x)) * smooth(0.2, -0.4, u.y)     # temples
        return r

    def face_paint(p, n):
        q = p - hc
        col = skin
        col = mix(col, skin * 1.08 + V((0.02, 0.0, 0.0)), smooth(0.02, 0.0, abs(q.y + 0.01)) * smooth(-0.05, -0.09, q.z) *
                  smooth(0.02, 0.05, abs(q.x)))
        # Lips.
        if q.z < -0.07 and abs(q.x) < 0.03 * k and -0.065 * k < q.y < -0.045 * k:
            col = skin * 0.72 + V((0.06, 0.0, 0.0))
        # Brows.
        if q.z < -0.07 and 0.018 * k < abs(q.x) < 0.055 * k and 0.03 * k < q.y < 0.042 * k:
            col = C(spec["hair"]) * 1.1
        return col
    head = ellipsoid(hc, (0.085 * k, 0.115 * k, 0.1 * k), segs=20, rings=14, fn=head_fn)
    c.part(head, ["Head", "Neck"], "person_skin", face_paint, falloff=6.0)
    # Nose, brow ridge, ears, eyes.
    c.part(tube([hc + V((0, 0.025 * k, -0.095 * k)), hc + V((0, -0.02 * k, -0.115 * k)), hc + V((0, -0.035 * k, -0.105 * k))],
                [0.012 * k, 0.017 * k, 0.014 * k], sides=6, samples=2), "Head", "person_skin", lambda p, n: skin * 1.02)
    c.part(tube([hc + V((-0.055 * k, 0.035 * k, -0.08 * k)), hc + V((0, 0.04 * k, -0.096 * k)), hc + V((0.055 * k, 0.035 * k, -0.08 * k))],
                [0.012 * k, 0.014 * k, 0.012 * k], sides=6, samples=3), "Head", "person_skin", lambda p, n: skin * 0.95)
    for s in (-1.0, 1.0):
        c.part(ellipsoid(hc + V((0.086 * k * s, 0.0, 0.005)), (0.012 * k, 0.03 * k, 0.02 * k), segs=8, rings=5), "Head", "person_skin",
               lambda p, n: skin * 0.9)
        c.part(ellipsoid(hc + V((0.035 * k * s, 0.018 * k, -0.084 * k)), (0.014 * k, 0.009 * k, 0.008 * k), segs=8, rings=5), "Head",
               "person_skin", lambda p, n: C("efe9e0"), ao=False)
        c.part(ellipsoid(hc + V((0.035 * k * s, 0.018 * k, -0.091 * k)), (0.0065 * k, 0.0065 * k, 0.003), segs=6, rings=4), "Head",
               "person_skin", lambda p, n: C("2a1f18"), ao=False)

    hair = C(spec["hair"])
    hair_paint = lambda p, n: mix(hair, hair * 1.35 + V((0.02, 0.02, 0.02)), 0.5 + 0.5 * fbm(p, 40.0, 2, 3.0))
    style = spec["style"]
    if style in ("crop", "bun"):
        cap = shell(hc + V((0, 0.012 * k, 0.008)), (0.092 * k, 0.122 * k, 0.108 * k), cover=0.42 if style == "crop" else 0.5,
                    thick=0.012, segs=20, rings=8, rot=(24, 0, 0), fn=head_fn)
        c.part(cap, "Head", "person_hair", hair_paint)
        if style == "bun":
            c.part(ellipsoid(hc + V((0, 0.03 * k, 0.11 * k)), (0.04 * k, 0.038 * k, 0.035 * k), segs=10, rings=7), "Head", "person_hair", hair_paint)
    elif style == "beanie":
        cap = shell(hc + V((0, 0.02 * k, 0.005)), (0.098 * k, 0.13 * k, 0.11 * k), cover=0.4, thick=0.016, segs=20, rings=8, rot=(14, 0, 0))
        knit = C(spec["crew"][1]) * 0.8
        c.part(cap, "Head", "person_cloth", lambda p, n: mix(knit, knit * 0.7, 0.5 + 0.5 * math.sin(math.atan2(p.x, p.z) * 40.0)))
        c.part(ellipsoid(hc + V((0, -0.01 * k, 0.07 * k)), (0.06 * k, 0.03 * k, 0.03 * k), segs=8, rings=5), "Head", "person_hair", hair_paint)
    elif style == "cap":
        cap = shell(hc + V((0, 0.025 * k, 0.005)), (0.095 * k, 0.11 * k, 0.105 * k), cover=0.36, thick=0.012, segs=20, rings=8, rot=(4, 0, 0))
        capc = C("3c4248")
        c.part(cap, "Head", "person_cloth", cloth(capc, 13.0))
        c.part(slab((0.12 * k, 0.008, 0.075 * k), at=hc + V((0, 0.06 * k, -0.115 * k)), rot=(-12, 0, 0), bevel=0.003), "Head", "person_cloth",
               lambda p, n: capc * 0.8)
        c.part(shell(hc + V((0, -0.005, 0.01)), (0.09 * k, 0.12 * k, 0.106 * k), cover=0.5, thick=0.01, segs=20, rings=8, rot=(90, 0, 0)),
               "Head", "person_hair", hair_paint)
    elif style == "hood":
        hood = shell(hc + V((0, 0.0, 0.02 * k)), (0.12 * k, 0.15 * k, 0.13 * k), cover=0.62, thick=0.018, segs=20, rings=9, rot=(50, 0, 0))
        c.part(hood, ["Head", "Neck"], "person_cloth", cloth(suit * 0.8, 14.0), falloff=6.0)
        c.part(shell(hc + V((0, 0.012 * k, 0.008)), (0.09 * k, 0.12 * k, 0.106 * k), cover=0.3, thick=0.01, segs=18, rings=6, rot=(40, 0, 0)),
               "Head", "person_hair", hair_paint)
    if spec.get("beard"):
        beard = shell(hc + V((0, -0.005, -0.004)), (0.09 * k, 0.12 * k, 0.106 * k), cover=0.33, thick=0.016, segs=20, rings=7, rot=(-160, 0, 0),
                      fn=head_fn)
        c.part(beard, "Head", "person_hair", hair_paint)

    # Kit.
    if spec.get("scarf"):
        ring = lathe([(0.07 * k, 0.0), (0.095 * k, 0.015), (0.1 * k, 0.05), (0.08 * k, 0.07)], at=P(0, 1.62, 0.0), segs=14)
        scarf = C("8a4a32")
        c.part(ring, ["Chest", "Neck"], "person_cloth", cloth(scarf, 15.0), falloff=2.0)
        c.part(tube([P(0.05, 1.64, -0.1), P(0.07, 1.5, -0.13), P(0.06, 1.38, -0.135)], [0.035 * k, 0.03 * k, 0.03 * k], sides=6, samples=2),
               "Chest", "person_cloth", cloth(scarf, 16.0))
    if spec.get("binoculars"):
        for s in (-1.0, 1.0):
            c.part(lathe([(0.022, -0.05), (0.025, 0.0), (0.022, 0.05)], at=P(0.03 * s, 1.36, -0.15), segs=10), "Chest", "person_gear",
                   lambda p, n: C("2b2d2f"))
        c.part(tube([P(-0.12, 1.6, -0.06), P(-0.04, 1.42, -0.14)], [0.006, 0.006], sides=4, samples=1), "Chest", "person_gear", lambda p, n: C("2a2522"))
        c.part(tube([P(0.12, 1.6, -0.06), P(0.04, 1.42, -0.14)], [0.006, 0.006], sides=4, samples=1), "Chest", "person_gear", lambda p, n: C("2a2522"))
    if spec.get("satchel"):
        c.part(slab((0.07 * k, 0.17 * k, 0.24 * k), at=P(0.21, 0.96, 0.02), bevel=0.012), ["Hips"], "person_cloth",
               lambda p, n: mix(C("e8e4dc"), C("b8b0a2"), smooth(0.0, -0.8, n.y)))
        c.part(tube([P(-0.15, 1.62, -0.02), P(0.0, 1.38, -0.15), P(0.2, 1.06, -0.02)], [0.012, 0.012, 0.012], sides=5, samples=3),
               ["Chest", "Spine"], "person_cloth", lambda p, n: C("3a3530"), falloff=2.0)
    if spec.get("holster"):
        c.part(slab((0.05 * k, 0.15 * k, 0.07 * k), at=P(0.19, 0.91, 0.01), bevel=0.01), "Hips", "person_gear", lambda p, n: C("231f1c"))
    if spec.get("apron"):
        apron = slab((0.3 * k * w, 0.62 * k, 0.012), at=P(0, 1.08, -0.14), taper=None, bevel=0.004)
        apron.deform(lambda v: V((v.x, v.y, v.z - 0.06 * (1.0 - (abs(v.x) / (0.15 * k * w)) ** 2) * smooth(1.2 * k, 0.9 * k, v.y))))
        c.part(apron, ["Hips", "Spine"], "person_cloth", cloth(C("6a5a3c"), 17.0), falloff=3.0)
    c.build(ao_reach=0.12)

    # --- Clips ---
    bones = c.bones

    def head_of(b):
        return V(bones[b][0])

    def pose(drop=0.0, shift=(0, 0), spine=(0, 0, 0), chest=(0, 0, 0), wrists=None, feet=None, extra=None):
        """A whole-body pose: hips lowered by `drop` and shifted, feet planted by IK (feet
        {side: model point} moves them), spine and chest turned, and hands placed by IK at
        `wrists` {side: model point} (the rest hang)."""
        off = V((shift[0], -drop, shift[1]))
        out = {}
        for side, s in (("L", -1.0), ("R", 1.0)):
            f = (feet or {}).get(side, P(0.1 * s, 0.08, 0.0))
            out.update(c.leg_ik("Leg" + side, "Shin" + side, f, off))
        rs, rc = godot_basis(spine), godot_basis(chest)
        sh0, ch0 = head_of("Spine"), head_of("Chest")
        out["Spine"] = tuple(spine)
        out["Chest"] = tuple(chest)
        for side, s in (("L", -1.0), ("R", 1.0)):
            if wrists and side in wrists:
                a0 = head_of("Arm" + side)
                at = off + sh0 + rs @ (ch0 - sh0 + rc @ (a0 - ch0))
                out.update(c.leg_ik("Arm" + side, "Forearm" + side, wrists[side], at - a0, Rot(rs @ rc)))
            else:
                out["Arm" + side] = (0, 0, 4 * s)
                out["Forearm" + side] = (8, 0, 0)
        return merge(out, extra or {}), {"Hips": tuple(off)}

    c.cycle("idle", 120, lambda ph: pose(0.005 * math.sin(ph * 2), (0.012 * math.sin(ph), 0), (1.5 * math.sin(ph * 2), 0, 1.5 * math.sin(ph)),
                                         (1.0 * math.sin(ph * 2), 0, 0),
                                         extra={"Head": (3 * math.sin(ph * 2), 18 * math.sin(ph), 0),
                                                "ArmL": (2 * math.sin(ph), 0, -4), "ArmR": (-2 * math.sin(ph), 0, 4)}), steps=12)

    # Crouched, working at something on the ground, hands busy.
    def crouch(ph):
        work = math.sin(ph * 2)
        return pose(0.42 * k, (0, 0.05), (-28, 0, 0), (-14, 0, 0),
                    wrists={"L": P(-0.14 + 0.03 * work, 0.32, -0.42), "R": P(0.16, 0.3 + 0.05 * max(0.0, -work), -0.4 - 0.05 * work)},
                    feet={"L": P(-0.14, 0.08, -0.06), "R": P(0.14, 0.08, 0.14)},
                    extra={"Head": (-14, 8 * math.sin(ph), 0)})
    c.cycle("crouch", 90, crouch, steps=12)
    # On watch: a hand shading the eyes, scanning slowly.
    c.cycle("watch", 150, lambda ph: pose(0.0, (0.01 * math.sin(ph), 0), (0, 4 * math.sin(ph), 0), (0, 8 * math.sin(ph), 0),
                                          wrists={"R": P(0.1, 1.68, -0.2)}, extra={"Head": (6, 12 * math.sin(ph), 0)}), steps=12)
    # At ease: hands behind the back, weight shifting.
    c.cycle("at_ease", 140, lambda ph: pose(0.004 * math.sin(ph * 2), (0.015 * math.sin(ph), 0), (0, 0, 0), (2, 0, 0),
                                            wrists={"L": P(-0.08, 1.02, 0.16), "R": P(0.08, 1.02, 0.16)},
                                            extra={"Head": (2, 10 * math.sin(ph), 0)}), steps=12)
    # Talking: one hand making a point.
    c.cycle("talk", 60, lambda ph: pose(0.0, (0.01 * math.sin(ph), 0), (0, 0, 0), (0, 3 * math.sin(ph), 0),
                                        wrists={"R": P(0.2, 1.22 + 0.04 * math.sin(ph * 2), -0.3)},
                                        extra={"Head": (3 * math.sin(ph * 2), 6 * math.sin(ph), 0)}), steps=12)
    c.export()


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in args or list(PEOPLE):
        person(name, PEOPLE[name])


if __name__ == "__main__":
    main()
