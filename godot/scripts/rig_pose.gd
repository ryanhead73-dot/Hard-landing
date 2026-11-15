class_name RigPose
extends RefCounted
## Poses a Rig's joints relative to their rest pose. Each frame an animator sets rotations (in
## degrees, applied in the joint's parent space on top of the rest rotation) and offsets (metres,
## added to the rest position). Joints the rig doesn't have are ignored, so one animator can
## drive models that differ a little.
##
## Works the same on the two kinds of model: rigid-part rigs (a pivot node per joint) and skinned
## ones (blender/creature_kit.py: a bone per joint). For a bone, "parent space" means the model's
## axes as they are carried by the parent bone, the frame the Blender clips are written in, so
## rot_of() reads the same numbers off either kind.

var root: Node3D
var skeleton: Skeleton3D
var _rest: Dictionary = {}
## Bone name -> index, for a skinned model.
var _bones: Dictionary = {}


func _init(rig: Node3D) -> void:
	root = rig
	if rig:
		skeleton = rig.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton:
			for i in skeleton.get_bone_count():
				_bones[skeleton.get_bone_name(i)] = i
		_collect(rig)


func _collect(node: Node) -> void:
	for c in node.get_children():
		if c is Node3D and not (c is MeshInstance3D) and not (c is Skeleton3D) and not (c is BoneAttachment3D):
			if not _bones.has(String(c.name)):
				_rest[String(c.name)] = [c, (c as Node3D).transform]
		if not (c is BoneAttachment3D):
			_collect(c)


func has(joint: String) -> bool:
	return _rest.has(joint) or _bones.has(joint)


## The pivot node for a rigid joint (null for a bone: scale bones through their clips instead).
func node(joint: String) -> Node3D:
	return _rest[joint][0] if _rest.has(joint) else null


func names() -> PackedStringArray:
	var out := PackedStringArray(_rest.keys())
	out.append_array(PackedStringArray(_bones.keys()))
	return out


## Rotation in degrees (x pitch, y yaw, z roll) on top of the rest pose.
func rot(joint: String, degrees: Vector3) -> void:
	var r := Basis.from_euler(degrees * (PI / 180.0))
	if _bones.has(joint):
		var b: int = _bones[joint]
		var g := skeleton.get_bone_global_rest(b).basis.orthonormalized()
		var local := skeleton.get_bone_rest(b).basis.orthonormalized()
		skeleton.set_bone_pose_rotation(b, (local * g.inverse() * r * g).get_rotation_quaternion())
		return
	if not _rest.has(joint):
		return
	var n: Node3D = _rest[joint][0]
	var rest: Transform3D = _rest[joint][1]
	n.transform.basis = r * rest.basis


func offset(joint: String, by: Vector3) -> void:
	if _bones.has(joint):
		var b: int = _bones[joint]
		var p := skeleton.get_bone_parent(b)
		var pg := skeleton.get_bone_global_rest(p).basis.orthonormalized() if p >= 0 else Basis()
		skeleton.set_bone_pose_position(b, skeleton.get_bone_rest(b).origin + pg.inverse() * by)
		return
	if not _rest.has(joint):
		return
	var n: Node3D = _rest[joint][0]
	n.position = (_rest[joint][1] as Transform3D).origin + by


## The joint's rotation away from rest, in degrees (tests read poses back with this).
func rot_of(joint: String) -> Vector3:
	if _bones.has(joint):
		var b: int = _bones[joint]
		var g := skeleton.get_bone_global_rest(b).basis.orthonormalized()
		var local := skeleton.get_bone_rest(b).basis.orthonormalized()
		var q := Basis(skeleton.get_bone_pose_rotation(b))
		return (g * local.inverse() * q * g.inverse()).get_euler() * (180.0 / PI)
	if not _rest.has(joint):
		return Vector3.ZERO
	var n: Node3D = _rest[joint][0]
	var rest: Transform3D = _rest[joint][1]
	return (n.transform.basis * rest.basis.inverse()).get_euler() * (180.0 / PI)


func reset() -> void:
	for j in _rest:
		(_rest[j][0] as Node3D).transform = _rest[j][1]
	if skeleton:
		skeleton.reset_bone_poses()
