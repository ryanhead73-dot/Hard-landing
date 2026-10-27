"""Kestrel blockout for Blender 4.2+.

Builds the deck plan from godot/data/kestrel_layout.json as clean, named geometry that is
ready to model over, then saves a .blend and exports a .glb for Godot.

Run from a terminal:
    blender --background --python kestrel_blockout.py
    blender --background --python kestrel_blockout.py -- --layout path/to/layout.json --out path/to/file.glb
Or open this file in Blender's Text Editor and press Run Script.

Conventions (match the Godot side):
- 1 unit = 1 metre. Blender X = plan x - length/2 (nose toward -X), Blender Y = centreline - plan z
  (starboard toward -Y), Blender Z = height above the main deck. glTF export converts to Godot's Y-up,
  which lands everything at the same coordinates the Godot greybox uses.
- Every repair is an empty at its mount point named after the repair id, with two child empties
  "<id>_damaged" and "<id>_repaired". Model each state inside its child; keep the shared origin.
  scripts/repairable.gd toggles the two children by those suffixes.
- Name suffixes are Godot import hints: "-col" adds trimesh collision, "-convcol" convex collision,
  "-colonly" collision only.
"""

import argparse
import json
import math
import os
import sys

import bpy  # must load before bmesh when running as the standalone bpy module
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
DEFAULT_LAYOUT = os.path.join(HERE, "..", "godot", "data", "kestrel_layout.json")
DEFAULT_GLB = os.path.join(HERE, "..", "godot", "assets", "kestrel_blockout.glb")
DEFAULT_BLEND = os.path.join(HERE, "kestrel_blockout.blend")

PALETTE = {
    "hull": "e9e1cc",
    "oxide": "c4622d",
    "panel": "e3dccb",
    "deck": "2e3236",
    "metal": "3a3f43",
    "metal_dark": "24282b",
    "fabric": "5a4a3c",
    "crate": "6b6a52",
    "salvage": "7d8c84",
    "screen": "0a0c0c",
    "placeholder_damaged": "b5452a",
    "placeholder_repaired": "5f8f86",
}

WING_OUTLINE = [(13.4, 8.9), (15.5, 3.5), (16.6, 0.6), (20.0, 0.6), (21.0, 3.5), (23.5, 8.9)]


class Builder:
    def __init__(self, layout):
        self.layout = layout
        self.length = layout["length"]
        self.centre_z = layout["centreline_z"]
        self.materials = {}
        self.root = self._collection("Kestrel", bpy.context.scene.collection)
        self.shell_col = self._collection("Shell", self.root)
        self.interior_col = self._collection("Interior", self.root)
        self.exterior_col = self._collection("Exterior", self.root)
        self.repairs_col = self._collection("Repairs", self.root)
        self.cutters_col = self._collection("_Cutters", bpy.context.scene.collection)

    # --- coordinates -----------------------------------------------------------------------

    def bl(self, x, y, z):
        """Plan (x aft, y up, z from port line) to Blender (X, Y, Z-up)."""
        return (x - self.length * 0.5, self.centre_z - z, y)

    # --- building --------------------------------------------------------------------------

    def build(self):
        self.build_shell()
        self.build_interior()
        self.build_exterior()
        self.build_repairs()

    def build_shell(self):
        t = self.layout["wall"] * 0.5
        solids = []
        for r in self.layout["rooms"]:
            solids.append(self.box(f"solid_{r['id']}", [r["x"][0] - t, r["x"][1] + t], [-0.2, r["ceiling"] + 0.2],
                                   [r["z"][0] - t, r["z"][1] + t], "hull", self.cutters_col))
        solids.append(self.box("solid_nose", [0.8, 3.7], [-0.2, 2.0], [11.4, 14.6], "hull", self.cutters_col))
        for r in self.layout["rooms"]:
            self.box(f"cut_{r['id']}", [r["x"][0] + t, r["x"][1] - t], [r["floor"], r["ceiling"]],
                     [r["z"][0] + t, r["z"][1] - t], "panel", self.cutters_col)
        for o in self.layout["openings"]:
            self.box(f"cut_{o['id']}", o["x"], o["y"], o["z"], "panel", self.cutters_col)

        # Union the solids, then subtract every room volume and opening in one Exact boolean.
        base = solids[0]
        for other in solids[1:]:
            mod = base.modifiers.new(f"union_{other.name}", "BOOLEAN")
            mod.operation = "UNION"
            mod.solver = "EXACT"
            mod.material_mode = "TRANSFER"
            mod.object = other
        cut_set = self._collection("_CutSet", self.cutters_col)
        for obj in list(self.cutters_col.objects):
            if obj.name.startswith("cut_"):
                self.cutters_col.objects.unlink(obj)
                cut_set.objects.link(obj)
        diff = base.modifiers.new("cut_rooms", "BOOLEAN")
        diff.operation = "DIFFERENCE"
        diff.solver = "EXACT"
        diff.material_mode = "TRANSFER"
        diff.operand_type = "COLLECTION"
        diff.collection = cut_set

        depsgraph = bpy.context.evaluated_depsgraph_get()
        baked = bpy.data.meshes.new_from_object(base.evaluated_get(depsgraph))
        shell = bpy.data.objects.new("Shell-col", baked)
        shell.location = base.location
        self.shell_col.objects.link(shell)

        for obj in list(self.cutters_col.all_objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(cut_set)
        bpy.data.collections.remove(self.cutters_col)

    def build_interior(self):
        t = self.layout["wall"] * 0.5
        for r in self.layout["rooms"]:
            self.box(f"Floor_{r['id']}", [r["x"][0] + t, r["x"][1] - t], [r["floor"], r["floor"] + 0.02],
                     [r["z"][0] + t, r["z"][1] - t], "deck", self.interior_col)

        s = self.layout["stairs"]
        top_x, bottom_x = s["x"]
        steps, rise = int(s["steps"]), s["rise"]
        run = (bottom_x - top_x) / steps
        for i in range(steps):
            self.box(f"Stair_{i}", [bottom_x - (i + 1) * run, bottom_x - i * run], [0.0, (i + 1) * rise / steps],
                     s["z"], "metal", self.interior_col)
        mid_z = sum(s["z"]) * 0.5
        self.ramp("StairRamp-colonly", (bottom_x, 0.0, mid_z), (top_x, rise, mid_z), s["z"][1] - s["z"][0])

        d = self.layout["door_steps"]
        z0, z1 = d["z"]
        steps, drop = int(d["steps"]), d["drop"]
        run = (z1 - z0) / steps
        for i in range(steps):
            top = -drop * (i + 1) / (steps + 1)
            self.box(f"DoorStep_{i}", d["x"], [-drop - 0.6, top], [z0 + i * run, z0 + (i + 1) * run], "metal",
                     self.exterior_col)
        mid_x = sum(d["x"]) * 0.5
        self.ramp("DoorRamp-colonly", (mid_x, 0.0, z0), (mid_x, -drop - 0.4, z1 + 0.7), d["x"][1] - d["x"][0])

        for f in self.layout["fixtures"]:
            self.box(f"{f['id']}-convcol", f["x"], f["y"], f["z"], f["mat"], self.interior_col)
        for sc in self.layout["screens"]:
            self.box(sc["id"], sc["x"], sc["y"], sc["z"], "screen", self.interior_col)

    def build_exterior(self):
        self.wing("Wing_starboard", [(x, 26.0 - z) for x, z in WING_OUTLINE], "hull", self.exterior_col)
        self.cylinder("Engine_starboard", (29.0, 1.9, 18.4), 1.0, 9.0, "x", "metal", self.exterior_col)
        for side, zc in (("port", 7.6), ("starboard", 18.4)):
            self.box(f"Fin_{side}", [30.4, 33.2], [2.6, 5.4], [zc - 0.08, zc + 0.08], "hull", self.exterior_col)
        self.box("Stabiliser_port", [29.6, 33.2], [1.9, 2.05], [5.4, 5.9], "hull", self.exterior_col)
        self.box("Stabiliser_starboard", [29.6, 33.2], [1.9, 2.05], [20.1, 20.6], "hull", self.exterior_col)
        self.box("Pylon_port", [25.0, 28.6], [1.4, 2.4], [8.4, 9.3], "metal", self.exterior_col)
        self.box("Pylon_starboard", [25.0, 28.6], [1.4, 2.4], [16.7, 17.6], "metal", self.exterior_col)
        self.box("Spine", [11.0, 30.0], [3.2, 3.7], [12.4, 13.6], "hull", self.exterior_col)
        self.box("AftRamp", [30.1, 30.3], [0.0, 3.0], [10.7, 15.3], "metal", self.exterior_col)

    def build_repairs(self):
        for repair_id, spec in self.layout["repair_mounts"].items():
            mount = self.empty(repair_id, self.bl(*spec["mount"]), None)
            mount["repair_id"] = repair_id
            b = spec["bounds"]
            for state, mat in (("damaged", "placeholder_damaged"), ("repaired", "placeholder_repaired")):
                holder = self.empty(f"{repair_id}_{state}", (0.0, 0.0, 0.0), mount)
                part = self.box(f"{repair_id}_{state}_placeholder", b["x"], b["y"], b["z"], mat, self.repairs_col)
                part.parent = holder
                part.location = [part.location[i] - mount.location[i] for i in range(3)]
                if state == "repaired":
                    holder.hide_set(True)
                    part.hide_set(True)

    # --- primitives ------------------------------------------------------------------------

    def box(self, name, x, y, z, mat, collection):
        lo = self.bl(x[0], y[0], z[1])
        hi = self.bl(x[1], y[1], z[0])
        size = [hi[i] - lo[i] for i in range(3)]
        centre = [(hi[i] + lo[i]) * 0.5 for i in range(3)]
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=size, verts=bm.verts)
        return self._object(name, bm, centre, mat, collection)

    def cylinder(self, name, centre, radius, length, axis, mat, collection):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=radius, radius2=radius, depth=length)
        obj = self._object(name, bm, self.bl(*centre), mat, collection)
        if axis == "x":
            obj.rotation_euler = (0.0, math.pi * 0.5, 0.0)
        elif axis == "z":
            obj.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
        return obj

    def wing(self, name, outline, mat, collection):
        bm = bmesh.new()
        verts = [bm.verts.new(self.bl(px, 3.4, pz)) for px, pz in outline]
        face = bm.faces.new(verts)
        bmesh.ops.recalc_face_normals(bm, faces=[face])
        ext = bmesh.ops.extrude_face_region(bm, geom=[face])
        moved = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=(0.0, 0.0, 0.35), verts=moved)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self._object(name, bm, (0.0, 0.0, 0.0), mat, collection)

    def ramp(self, name, bottom, top, width):
        b, t = self.bl(*bottom), self.bl(*top)
        d = [t[i] - b[i] for i in range(3)]
        length = math.sqrt(sum(c * c for c in d))
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        horizontal = math.hypot(d[0], d[1])
        obj_scale = (length, width, 0.06)
        bmesh.ops.scale(bm, vec=obj_scale, verts=bm.verts)
        centre = [(b[i] + t[i]) * 0.5 for i in range(3)]
        centre[2] -= 0.03
        obj = self._object(name, bm, centre, "metal", self.interior_col)
        obj.rotation_euler = (0.0, -math.atan2(d[2], horizontal), math.atan2(d[1], d[0]))
        obj.display_type = "WIRE"
        return obj

    def empty(self, name, location, parent):
        obj = bpy.data.objects.new(name, None)
        obj.empty_display_type = "PLAIN_AXES"
        obj.empty_display_size = 0.5
        obj.location = location
        obj.parent = parent
        self.repairs_col.objects.link(obj)
        return obj

    def _object(self, name, bm, location, mat, collection):
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(self.material(mat))
        obj = bpy.data.objects.new(name, mesh)
        obj.location = location
        collection.objects.link(obj)
        return obj

    def material(self, mat_id):
        if mat_id in self.materials:
            return self.materials[mat_id]
        mat = bpy.data.materials.new(mat_id)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        rgb = _srgb_to_linear(PALETTE.get(mat_id, "ff00ff"))
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.85 if mat_id in ("hull", "panel", "fabric", "crate", "oxide") else 0.5
        bsdf.inputs["Metallic"].default_value = 0.6 if mat_id in ("metal", "metal_dark", "salvage") else 0.0
        mat.diffuse_color = (*rgb, 1.0)
        self.materials[mat_id] = mat
        return mat

    @staticmethod
    def _collection(name, parent):
        col = bpy.data.collections.new(name)
        parent.children.link(col)
        return col


def _srgb_to_linear(hex_color):
    out = []
    for i in (0, 2, 4):
        c = int(hex_color[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def _clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for col in list(bpy.data.collections):
        bpy.data.collections.remove(col)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Build the Kestrel blockout from the deck plan.")
    parser.add_argument("--layout", default=DEFAULT_LAYOUT)
    parser.add_argument("--out", default=DEFAULT_GLB, help="GLB export path ('' to skip)")
    parser.add_argument("--blend", default=DEFAULT_BLEND, help=".blend save path ('' to skip)")
    args = parser.parse_args(argv)

    with open(args.layout, encoding="utf-8") as fh:
        layout = json.load(fh)

    _clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    Builder(layout).build()

    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.blend))
        print(f"Saved {os.path.abspath(args.blend)}")
    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=os.path.abspath(args.out), export_format="GLB",
                                  export_extras=True, export_yup=True, use_visible=False)
        print(f"Exported {os.path.abspath(args.out)}")


if __name__ == "__main__":
    main()
