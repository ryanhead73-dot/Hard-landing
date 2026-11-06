"""Keyframed animation for the wildlife, exported with the models.

    python blender/build_creature_anims.py [-- scuttler]      # with `pip install bpy==4.2.0`

The creatures are hard-shelled, so they stay rigid-part rigs (named pivots with meshes under
them, from build_models.py) and their clips animate the pivots directly, the way you'd animate an
armoured insect in Blender: no skin to deform, every plate moves with its joint. Each clip is a set
of object actions on one NLA track per pivot, all with the clip's name, which the glTF exporter
merges into one animation. The game plays them with an AnimationTree (creature_animator.gd).

Poses are written like the game's procedural animator: per joint, degrees about Godot's x, y and z
on top of the joint's rest rotation, in its parent's space, and offsets in metres.

Output: godot/assets/models/<creature>.glb (replacing the static export) and
blender/<creature>_anim.blend for editing by hand.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_models as bm  # noqa: E402

FPS = 30


def _godot_rot(deg):
    """Godot Euler degrees (y, then x, then z, as Node3D applies them) -> Blender-space matrix."""
    x, y, z = (math.radians(a) for a in deg)
    rx = Matrix.Rotation(x, 3, Vector((1, 0, 0)))
    ry = Matrix.Rotation(y, 3, Vector((0, 0, 1)))
    rz = Matrix.Rotation(z, 3, Vector((0, -1, 0)))
    return ry @ rx @ rz


class Rig:
    """The pivots of a freshly built model, with their rest transforms."""

    def __init__(self, root_name):
        bpy.context.view_layer.update()
        self.root = bpy.data.objects[root_name]
        self.joints = {}
        for o in bpy.data.objects:
            if o.type == "EMPTY" and o is not self.root:
                self.joints[o.name] = (o, o.location.copy(), o.rotation_euler.to_matrix())
        self.prev = {}

    def key(self, frame, pose, offsets=None):
        """Keys every pivot: rotation = delta (Godot degrees, parent space) on top of rest."""
        for name, (o, loc, rot) in self.joints.items():
            q = (_godot_rot(pose.get(name, (0, 0, 0))) @ rot).to_quaternion()
            if name in self.prev:
                q.make_compatible(self.prev[name])
            self.prev[name] = q.copy()
            o.rotation_mode = "QUATERNION"
            o.rotation_quaternion = q
            o.keyframe_insert("rotation_quaternion", frame=frame)
            o.location = loc + bm.g(*(offsets or {}).get(name, (0, 0, 0)))
            o.keyframe_insert("location", frame=frame)

    def clip(self, name, keys):
        """keys: [(frame, pose, offsets)]. One action per pivot, each on an NLA track named `name`."""
        actions = {}
        for o, _, _ in self.joints.values():
            o.animation_data_create()
            act = bpy.data.actions.new("%s_%s" % (name, o.name))
            o.animation_data.action = act
            actions[o.name] = act
        self.prev = {}
        for frame, pose, offsets in keys:
            self.key(frame, pose, offsets)
        for o, loc, rot in self.joints.values():
            act = actions[o.name]
            for fc in act.fcurves:
                for kp in fc.keyframe_points:
                    kp.interpolation = "BEZIER"
                    kp.handle_left_type = "AUTO_CLAMPED"
                    kp.handle_right_type = "AUTO_CLAMPED"
            track = o.animation_data.nla_tracks.new()
            track.name = name
            strip = track.strips.new(name, int(keys[0][0]), act)
            strip.name = name
            track.mute = True
            o.animation_data.action = None
            act.use_fake_user = True
            o.location = loc
            o.rotation_quaternion = rot.to_quaternion()


def _merge(*dicts):
    out = {}
    for d in dicts:
        for k, v in d.items():
            a = out.get(k, (0, 0, 0))
            out[k] = (a[0] + v[0], a[1] + v[1], a[2] + v[2])
    return out


# --- Scuttler ----------------------------------------------------------------------------

# Six splayed legs, tripod gait: L1, R2, L3 step together, then R1, L2, R3.
SCUTTLER_LEGS = [("L", 1, -1, 0.0), ("L", 2, -1, math.pi), ("L", 3, -1, 0.0),
                 ("R", 1, 1, math.pi), ("R", 2, 1, 0.0), ("R", 3, 1, math.pi)]


def _scuttler_legs(phase, swing, lift, plant=0.0):
    """Splayed legs sweep forward about the vertical, lift about the long axis on the way back."""
    p = {}
    for side, i, s, off in SCUTTLER_LEGS:
        psi = phase + off
        up = max(0.0, math.cos(psi))
        p["Leg%s%d" % (side, i)] = (0, s * math.sin(psi) * swing, s * (up * lift - plant))
        # The foot reaches as the leg lifts, then digs in.
        p["Foot%s%d" % (side, i)] = (0, 0, s * (up * lift * 0.6 - plant * 0.5))
    return p


def scuttler_clips(rig):
    # Idle (2 s): a slow breath, feet shifting one at a time, the head tasting the air.
    keys = []
    for f in range(9):
        t = f / 8.0 * math.tau
        pose = _scuttler_legs(0.0, 0.0, 0.0)
        shift = ("L", 2, -1) if f in (2, 3) else (("R", 1, 1) if f in (5, 6) else None)
        if shift:
            pose["Leg%s%d" % shift[:2]] = (0, shift[2] * 8.0, shift[2] * 14.0)
        pose = _merge(pose, {"Body": (math.sin(t) * 1.5, 0, 0), "Head": (math.sin(t * 2) * 3.0, math.sin(t) * 14.0, 0),
                             "JawL": (0, 4 + math.sin(t * 3) * 4.0, 0), "JawR": (0, -4 - math.sin(t * 3) * 4.0, 0)})
        keys.append((1 + f * 7.5, pose, {"Body": (0, math.sin(t) * 0.01, 0)}))
    rig.clip("idle", keys)

    # Walk (0.8 s per cycle, 1.1 m at normal speed; the game matches it to her speed).
    keys = []
    for f in range(9):
        ph = f / 8.0 * math.tau
        pose = _merge(_scuttler_legs(ph, 24.0, 22.0), {"Body": (0, math.sin(ph * 2) * 2.0, math.sin(ph) * 3.0),
                                                        "Head": (0, -math.sin(ph) * 6.0, 0)})
        keys.append((1 + f * 3, pose, {"Body": (0, abs(math.sin(ph)) * 0.025, 0)}))
    rig.clip("walk", keys)

    # Wind-up (0.5 s loop): rears its front, jaws gaping and trembling, front legs raised.
    rear = {"Body": (12, 0, 0), "Head": (10, 0, 0), "LegL1": (0, -14, -30), "LegR1": (0, 14, 30),
            "FootL1": (0, 0, -20), "FootR1": (0, 0, 20), "LegL3": (0, 0, 8), "LegR3": (0, 0, -8)}
    keys = []
    for f in range(5):
        tremble = 4.0 if f % 2 else -4.0
        keys.append((1 + f * 3.75, _merge(rear, {"JawL": (0, 32 + tremble, 0), "JawR": (0, -32 - tremble, 0)}),
                     {"Body": (0, 0.08, 0.06)}))
    rig.clip("windup", keys)

    # Attack (0.35 s): a lunge from the wind-up, body thrown forward and down, jaws snapping shut.
    lunge = {"Body": (-16, 0, 0), "Head": (-12, 0, 0), "JawL": (0, -12, 0), "JawR": (0, 12, 0),
             "LegL1": (0, 26, 10), "LegR1": (0, -26, -10), "LegL3": (0, -20, 0), "LegR3": (0, 20, 0)}
    rig.clip("attack", [(1, _merge(rear, {"JawL": (0, 34, 0), "JawR": (0, -34, 0)}), {"Body": (0, 0.08, 0.06)}),
                        (5, lunge, {"Body": (0, -0.05, -0.3)}),
                        (11, _merge(lunge, {"JawL": (0, 6, 0), "JawR": (0, -6, 0)}), {"Body": (0, -0.03, -0.2)})])

    # Hurt (0.3 s): a sideways jolt and the head snapping up.
    rig.clip("hurt", [(1, {}, {}), (3, {"Body": (0, 0, 9), "Head": (12, 8, 0)}, {"Body": (0.04, 0, 0)}),
                      (6, {"Body": (0, 0, -6), "Head": (6, -4, 0)}, {}), (10, {}, {})])

    # Stagger (0.4 s loop): reeling, legs splayed to catch itself, head hanging.
    splay = {"LegL1": (0, -10, -14), "LegR1": (0, 10, 14), "LegL2": (0, 0, -18), "LegR2": (0, 0, 18),
             "LegL3": (0, 10, -14), "LegR3": (0, -10, 14), "Head": (-18, 0, 0), "JawL": (0, 14, 0), "JawR": (0, -14, 0)}
    rig.clip("stagger", [(1, _merge(splay, {"Body": (-4, 6, 10)}), {"Body": (0.05, -0.06, 0)}),
                         (7, _merge(splay, {"Body": (-6, -6, -10)}), {"Body": (-0.05, -0.08, 0)}),
                         (13, _merge(splay, {"Body": (-4, 6, 10)}), {"Body": (0.05, -0.06, 0)})])

    # Die (0.6 s): legs spasm, then curl up underneath; the head drops.
    curl = {}
    for side, i, s, _ in SCUTTLER_LEGS:
        curl["Leg%s%d" % (side, i)] = (0, 0, -s * 50)
        curl["Foot%s%d" % (side, i)] = (0, 0, -s * 45)
    rig.clip("die", [(1, {}, {}),
                     (5, _merge(_scuttler_legs(1.0, 30.0, 30.0), {"Body": (-8, 0, 6), "Head": (14, 0, 0)}), {}),
                     (12, _merge(curl, {"Body": (0, 0, 6), "Head": (-25, 0, 0), "JawL": (0, 20, 0), "JawR": (0, -20, 0)}),
                      {"Body": (0, -0.12, 0)}),
                     (18, _merge(curl, {"Body": (0, 0, 7), "Head": (-25, 0, 0), "JawL": (0, 24, 0), "JawR": (0, -24, 0)}),
                      {"Body": (0, -0.15, 0)})])


CREATURES = {"scuttler": ("Scuttler", bm.scuttler, scuttler_clips)}


def build(name):
    root_name, builder, clips = CREATURES[name]
    bm.reset()
    bpy.context.scene.render.fps = FPS
    real_export = bm.export
    bm.export = lambda n: None
    try:
        builder()
    finally:
        bm.export = real_export
    rig = Rig(root_name)
    clips(rig)
    os.makedirs(bm.OUT, exist_ok=True)
    path = os.path.join(bm.OUT, name + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True,
                              use_selection=True, export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_frame_range=False,
                              export_optimize_animation_size=False, export_optimize_animation_keep_anim_object=True)
    print("exported", os.path.relpath(path, bm.ROOT))
    blend = os.path.join(bm.ROOT, "blender", name + "_anim.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    print("saved", os.path.relpath(blend, bm.ROOT))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in args or list(CREATURES):
        build(name)


if __name__ == "__main__":
    main()
