class_name PointDefense
extends Node3D
## Kestrel's wing turret: tracks the nearest hostile it can see around the ship and fires short
## bursts. Only runs while it is visible, which is while the wing repair is in place.

signal fired_at(target: Node3D)

@export var turret_range := 38.0
@export var damage := 9.0
@export var fire_interval := 0.3
@export var turn_speed := 6.0

var target: Node3D

var _cooldown := 0.0
var _retarget := 0.0
var _head: Node3D
var _tracer_mat: StandardMaterial3D
var _barrels: Array[Node3D] = []
var _scan := 0.0
var _kick := 0.0


func _ready() -> void:
	_head = Node3D.new()
	add_child(_head)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("3a3f43")
	metal.metallic = 0.6
	var housing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.35, 0.6)
	housing.mesh = box
	housing.material_override = metal
	_head.add_child(housing)
	for x in [-0.12, 0.12]:
		var barrel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		cyl.height = 0.9
		barrel.mesh = cyl
		barrel.material_override = metal
		barrel.rotation.x = PI * 0.5
		barrel.position = Vector3(x, 0.05, -0.6)
		_head.add_child(barrel)
		_barrels.append(barrel)
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.albedo_color = Color("ffd08a")
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color("ffb24d")
	_tracer_mat.emission_energy_multiplier = 4.0
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_visible_in_tree():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_retarget -= delta
	if _retarget <= 0.0 or not _valid(target):
		_retarget = 0.4
		target = _find_target()
	# Barrels run back out after each shot.
	_kick = maxf(_kick - delta * 6.0, 0.0)
	for b in _barrels:
		b.position.z = -0.6 + 0.18 * _kick
	if target == null:
		# Idle: the head sweeps slowly back and forth, watching the basin.
		_scan += delta
		var sweep := Basis(Vector3.UP, sin(_scan * 0.5) * 1.1) * Basis(Vector3.RIGHT, 0.08)
		_head.basis = _head.basis.orthonormalized().slerp(sweep, clampf(delta * 2.0, 0.0, 1.0)).orthonormalized()
		return
	var aim := target.global_position + Vector3.UP * 0.5
	var want := _head.global_transform.looking_at(aim, Vector3.UP).basis
	# Orthonormalize first: the wing springs into place with a little scale overshoot when fitted.
	_head.global_basis = _head.global_basis.orthonormalized().slerp(want.orthonormalized(), clampf(turn_speed * delta, 0.0, 1.0)).orthonormalized()
	if _cooldown <= 0.0 and (-_head.global_basis.z).dot((aim - _head.global_position).normalized()) > 0.97:
		_fire(aim)


func _valid(t) -> bool:
	return t != null and is_instance_valid(t) and t.is_in_group("enemies") and t.global_position.distance_to(global_position) < turret_range


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_d := turret_range
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = e.global_position.distance_to(global_position)
		if d < best_d and _can_see(e):
			best = e
			best_d = d
	return best


func _can_see(e: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, e.global_position + Vector3.UP * 0.5, Game.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _fire(aim: Vector3) -> void:
	_cooldown = fire_interval
	_kick = 1.0
	target.take_damage(damage, aim, (aim - global_position).normalized())
	fired_at.emit(target)
	Sfx.play("turret_shot", global_position, -6.0, 0.08)
	var tracer := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var length := global_position.distance_to(aim)
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = length
	cyl.radial_segments = 4
	tracer.mesh = cyl
	tracer.material_override = _tracer_mat
	tracer.top_level = true
	add_child(tracer)
	var axis := (aim - global_position) / length
	var side := axis.cross(Vector3.UP)
	side = (side if side.length() > 0.01 else Vector3.RIGHT).normalized()
	tracer.global_transform = Transform3D(Basis(side, axis, side.cross(axis)), (global_position + aim) * 0.5)
	get_tree().create_timer(0.05).timeout.connect(tracer.queue_free)
