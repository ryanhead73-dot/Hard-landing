class_name Rig
extends RefCounted
## Loads the Blender-built models (blender/build_models.py -> assets/models/<name>.glb). Each is a
## rigid-part rig: named pivots at the joints (Hips, ArmL, LegL1, Head...) with meshes under them,
## so code can pose and animate the pivots directly.

const PATH := "res://assets/models/%s.glb"


static func exists(model: String) -> bool:
	return ResourceLoader.exists(PATH % model)


## Instances a model under `parent`. Falls back to an empty node if the model is missing, so a
## missing export never breaks the game (the tests check every model is there).
static func spawn(model: String, parent: Node) -> Node3D:
	var n: Node3D
	if exists(model):
		n = (load(PATH % model) as PackedScene).instantiate() as Node3D
	else:
		push_warning("Rig: missing model %s" % model)
		n = Node3D.new()
	n.name = model.to_pascal_case()
	parent.add_child(n)
	return n


## A pivot by name anywhere in the rig, or null.
static func joint(root: Node, joint_name: String) -> Node3D:
	return root.find_child(joint_name, true, false) as Node3D


static func meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(meshes(c))
	return out


## Gives this instance its own copy of a named material (as set in Blender) and returns it, so
## one creature's glow can pulse without lighting up the whole pack. Null if the rig has none.
static func own_material(root: Node, material_name: String) -> StandardMaterial3D:
	var copy: StandardMaterial3D = null
	for m in meshes(root):
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i)
			if src and (src.resource_name == material_name or (src == copy)):
				if copy == null:
					copy = src.duplicate() as StandardMaterial3D
				m.set_surface_override_material(i, copy)
	return copy
