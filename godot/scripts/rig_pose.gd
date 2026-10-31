class_name RigPose
extends RefCounted
## Poses a Rig's joints relative to their rest pose. Each frame an animator sets rotations (in
## degrees, applied in the joint's parent space on top of the rest rotation) and offsets (metres,
## added to the rest position). Joints the rig doesn't have are ignored, so one animator can
## drive models that differ a little.

var root: Node3D
var _rest: Dictionary = {}


func _init(rig: Node3D) -> void:
	root = rig
	if rig:
		_collect(rig)


func _collect(node: Node) -> void:
	for c in node.get_children():
		if c is Node3D and not (c is MeshInstance3D):
			_rest[String(c.name)] = [c, (c as Node3D).transform]
		_collect(c)


func has(joint: String) -> bool:
	return _rest.has(joint)


func node(joint: String) -> Node3D:
	return _rest[joint][0] if _rest.has(joint) else null


func names() -> PackedStringArray:
	return PackedStringArray(_rest.keys())


## Rotation in degrees (x pitch, y yaw, z roll) on top of the rest pose.
func rot(joint: String, degrees: Vector3) -> void:
	if not _rest.has(joint):
		return
	var n: Node3D = _rest[joint][0]
	var rest: Transform3D = _rest[joint][1]
	var r := degrees * (PI / 180.0)
	n.transform.basis = Basis.from_euler(r) * rest.basis


func offset(joint: String, by: Vector3) -> void:
	if not _rest.has(joint):
		return
	var n: Node3D = _rest[joint][0]
	n.position = (_rest[joint][1] as Transform3D).origin + by


## The joint's rotation away from rest, in degrees (tests read poses back with this).
func rot_of(joint: String) -> Vector3:
	if not _rest.has(joint):
		return Vector3.ZERO
	var n: Node3D = _rest[joint][0]
	var rest: Transform3D = _rest[joint][1]
	return (n.transform.basis * rest.basis.inverse()).get_euler() * (180.0 / PI)


func reset() -> void:
	for j in _rest:
		(_rest[j][0] as Node3D).transform = _rest[j][1]
