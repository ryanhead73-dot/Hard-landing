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
	CreatureLook.apply(n)
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


## Instances a model that never moves or changes (a site's buildings and wrecks) and folds its
## meshes into one mesh per material, so a set piece made of hundreds of parts costs a handful
## of draw calls instead of hundreds. Its pivots stay as empty nodes.
static func spawn_static(model: String, parent: Node) -> Node3D:
	var n := spawn(model, parent)
	batch(n)
	return n


## Merges every mesh under `root` (in root's space) into one MeshInstance3D per root, with one
## surface per material and shadow setting, and frees the originals. Skinned meshes are left
## alone.
static func batch(root: Node3D) -> MeshInstance3D:
	var tools := {}
	var order: Array = []
	var originals: Array[MeshInstance3D] = []
	_gather(root, Transform3D.IDENTITY, root, tools, order, originals)
	if originals.size() < 2:
		return null
	var mesh := ArrayMesh.new()
	var shadows := {}
	for key in order:
		var st: SurfaceTool = tools[key][0]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, tools[key][1])
		shadows[tools[key][2]] = true
	var out := MeshInstance3D.new()
	out.name = "Batched"
	out.mesh = mesh
	# Everything in a set piece casts; a piece that mixed in non-casting decals keeps casting.
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows.has(GeometryInstance3D.SHADOW_CASTING_SETTING_ON) or shadows.size() == 0 else shadows.keys()[0]
	root.add_child(out)
	for m in originals:
		m.get_parent().remove_child(m)
		m.free()
	return out


static func _gather(node: Node, xform: Transform3D, root: Node3D, tools: Dictionary, order: Array, originals: Array[MeshInstance3D]) -> void:
	for c in node.get_children():
		if not c is Node3D:
			continue
		var t: Transform3D = xform * (c as Node3D).transform
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh and mi.skeleton == NodePath() and mi.visible and not mi is SoftBody3D:
				for i in mi.mesh.get_surface_count():
					var mat := mi.get_active_material(i)
					var fmt: int = mi.mesh.surface_get_format(i) & (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2)
					var key := "%d/%d/%d" % [mat.get_instance_id() if mat else 0, fmt, mi.cast_shadow]
					if not tools.has(key):
						var st := SurfaceTool.new()
						tools[key] = [st, mat, mi.cast_shadow]
						order.append(key)
					(tools[key][0] as SurfaceTool).append_from(mi.mesh, i, t)
				originals.append(mi)
		_gather(c, t, root, tools, order, originals)


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


## For a skinned model: a node that follows `bone` with the axes the old rigid pivots had (model
## axes at rest), so anything hung on it sits the same way it did on a pivot. Named after the bone,
## so joint() finds it. Null if the model has no such bone.
static func attach(root: Node, bone: String) -> Node3D:
	var skel := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or skel.find_bone(bone) < 0:
		return null
	var att := BoneAttachment3D.new()
	att.name = bone + "Bone"
	skel.add_child(att)
	att.bone_name = bone
	var aligned := Node3D.new()
	aligned.name = bone
	aligned.basis = skel.get_bone_global_rest(skel.find_bone(bone)).basis.orthonormalized().inverse()
	att.add_child(aligned)
	return aligned
