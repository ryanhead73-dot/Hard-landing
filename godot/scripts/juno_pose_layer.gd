class_name JunoPoseLayer
extends SkeletonModifier3D
## Runs after Juno's AnimationTree each frame and turns a few bones on top of the clips: the chest
## pitches with the camera while she aims (the rifle and both hands ride on it), recoil kicks it
## back, a hit flinches her, and a carried component bends her forward.

var animator: JunoAnimator
## Every bone's global pose as last shown, after this layer: the skeleton puts the clip's pose back
## once it has drawn the frame, so readers (tests, effects) ask here.
var shown: Array[Transform3D] = []


func _process_modification_with_delta(_delta: float) -> void:
	var a := animator
	if a == null or a.player == null:
		return
	var sk := get_skeleton()
	var pitch := rad_to_deg(a.player._pitch.rotation.x)
	var live := 1.0 - a._down
	_turn(sk, "Spine", Vector3(-7.0 * a._carry * live, 0.0, 0.0))
	_turn(sk, "Chest", Vector3((clampf(pitch * 0.55, -30.0, 30.0) * a._aim + 3.0 * a._recoil + 9.0 * a._flinch) * live, 0.0, 0.0))
	_turn(sk, "Head", Vector3((clampf(pitch * 0.35, -25.0, 25.0) * a._aim - 8.0 * a._flinch) * live, 0.0, 0.0))
	shown.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		shown[b] = sk.get_bone_global_pose(b)


## Turns a bone about its own head by `degrees` about the model's axes.
func _turn(sk: Skeleton3D, bone: String, degrees: Vector3) -> void:
	if degrees.is_zero_approx():
		return
	var b := sk.find_bone(bone)
	if b < 0:
		return
	var r := Basis.from_euler(degrees * (PI / 180.0))
	var p := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var local := Basis(sk.get_bone_pose_rotation(b))
	sk.set_bone_pose_rotation(b, (pg.inverse() * r * pg * local).get_rotation_quaternion())
