class_name LoomRidge
extends Node3D
## A live ridge in the Loom Expanse (milestone C2): a low braid of fibre lying across the ground
## that a pulse runs along every few seconds, heaving the weave up as it passes. Caught on it as
## the swell goes by, Juno is thrown and bruised; standing on bare stone (a `safe` span, where the
## ridge dives under a slab) or just stepping back off it, she is not. The pulse is told twice
## before it runs: a low thrum from the end it starts at, and the ridge's seam brightening.
##
## Set `from`, `to` (local to the parent), `period` and `offset` (seconds into the cycle at
## start) before adding it; `safe` holds spans along it ([0..1, 0..1]) that the swell skips.

signal swelled

const WIDTH := 3.2
const SPEED := 10.0
## The thrum starts this long before the swell sets off.
const TELL := 1.4
const HEIGHT := 1.6
## Within this of the swell's front (along the ridge) counts as caught.
const FRONT := 1.3
const DAMAGE := 10.0
const THROW_UP := 6.5
const THROW_SIDE := 4.0
const STEP := 0.9
const FIBRE := Color("7a5038")
const SEAM := Color("e07ad8")

var from := Vector3.ZERO
var to := Vector3.ZERO
var period := 7.0
var offset := 0.0
var safe: Array = []
## Who it can throw (the player); found by group if unset.
var target: Node3D
## Swells sent, and how many caught her (tests read these).
var swells := 0
var throws := 0

var _t := 0.0
## Distance of the swell's front along the ridge, or -1 between swells.
var front := -1.0
var _told := false
var _caught := false
var _mm: MultiMesh
var _rest: Array[Transform3D] = []
var _along: Array[float] = []
var _seam_mat: StandardMaterial3D


func _ready() -> void:
	_t = offset
	var length := from.distance_to(to)
	var dir := (to - from).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var fibre := StandardMaterial3D.new()
	if PbrSet.exists("shatterlands", "fungus_stem"):
		fibre = PbrSet.material("shatterlands", "fungus_stem", 0.6, false, FIBRE.lightened(0.3), Color.BLACK)
	else:
		fibre.albedo_color = FIBRE
	# The braid: short humps lying along the ridge, three abreast, each a squashed cylinder.
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(from.x * 13.0 + from.z * 7.0)
	var d := STEP * 0.5
	while d < length:
		if not _is_safe(d / length):
			for lane in [-0.9, 0.0, 0.9]:
				var p: Vector3 = from + dir * d + side * (lane + rng.randf_range(-0.2, 0.2))
				var r := rng.randf_range(0.28, 0.42)
				var b := Basis(side * r, dir * STEP * 1.3, Vector3.UP * r * 0.6)
				b = b.rotated(Vector3.UP, rng.randf_range(-0.15, 0.15))
				_rest.append(Transform3D(b, p + Vector3.UP * 0.12))
				_along.append(d)
		d += STEP
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = _rest.size()
	for i in _rest.size():
		_mm.set_instance_transform(i, _rest[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Braid"
	mmi.multimesh = _mm
	mmi.material_override = fibre
	add_child(mmi)
	# The seam along its spine that brightens before a swell (colour and a pulse in brightness,
	# so it doesn't rest on colour alone).
	_seam_mat = StandardMaterial3D.new()
	_seam_mat.albedo_color = SEAM.darkened(0.5)
	_seam_mat.emission_enabled = true
	_seam_mat.emission = SEAM
	_seam_mat.emission_energy_multiplier = 0.3
	var seam := MeshInstance3D.new()
	seam.name = "Seam"
	var sm := BoxMesh.new()
	sm.size = Vector3(0.18, 0.08, length)
	seam.mesh = sm
	seam.material_override = _seam_mat
	add_child(seam)
	seam.position = (from + to) * 0.5 + Vector3.UP * 0.3
	seam.basis = Basis.looking_at(dir, Vector3.UP)


func _is_safe(f: float) -> bool:
	for s in safe:
		if f >= float(s[0]) and f <= float(s[1]):
			return true
	return false


func length() -> float:
	return from.distance_to(to)


## Seconds until the next swell sets off.
func time_to_swell() -> float:
	return fposmod(period - _t, period)


func _physics_process(delta: float) -> void:
	_t += delta
	if not _told and _t >= period - TELL:
		_told = true
		Sfx.play("ridge_thrum", to_global(from) + Vector3.UP, -2.0, 0.05)
	if _t >= period:
		_t -= period
		_told = false
		front = 0.0
		_caught = false
		swells += 1
		swelled.emit()
	var tell := clampf(1.0 - time_to_swell() / TELL, 0.0, 1.0) if _told else 0.0
	_seam_mat.emission_energy_multiplier = 0.3 + 3.5 * tell * (0.6 + 0.4 * sin(_t * 18.0)) + (2.5 if front >= 0.0 else 0.0)
	if front < 0.0:
		return
	front += SPEED * delta
	_heave()
	_check_hit()
	if front > length() + 2.0:
		front = -1.0
		_heave()


## Lifts the braid around the swell's front.
func _heave() -> void:
	for i in _rest.size():
		var lift := 0.0
		if front >= 0.0:
			var k := (_along[i] - front) / 1.1
			lift = HEIGHT * exp(-k * k)
		var tr := _rest[i]
		tr.origin.y += lift
		tr.basis = tr.basis.scaled(Vector3(1.0, 1.0 + lift * 1.6, 1.0))
		_mm.set_instance_transform(i, tr)


func _check_hit() -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	if _caught or target == null or not is_instance_valid(target) or ("dead" in target and target.dead):
		return
	var local := to_local(target.global_position)
	var dir := (to - from).normalized()
	var along := (local - from).dot(dir)
	var across := local - from - dir * along
	across.y = 0.0
	if across.length() > WIDTH * 0.5 or local.y > 1.2 or along < 0.0 or along > length():
		return
	if _is_safe(along / length()) or absf(along - front) > FRONT:
		return
	_caught = true
	throws += 1
	if target.has_method("take_damage"):
		target.take_damage(DAMAGE, to_global(from + dir * along))
	if "velocity" in target:
		var out := global_basis * (across.normalized() if across.length() > 0.05 else dir.cross(Vector3.UP))
		target.velocity += out.normalized() * THROW_SIDE + Vector3.UP * THROW_UP
	if target.has_method("add_trauma"):
		target.add_trauma(0.35)
	Sfx.play("ridge_heave", target.global_position, -2.0, 0.1)
