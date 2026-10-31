class_name AcidPuddle
extends Area3D
## Hissing acid left where a glob lands. Burns the player while they stand in it, then dries up.

var lifetime := 3.0
var dps := 9.0
var radius := 1.3

var _tick := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("acid")
	collision_layer = 0
	collision_mask = Game.LAYER_PLAYER
	monitorable = false
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 1.0
	shape.shape = cyl
	shape.position.y = 0.5
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	mesh.mesh = disc
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.7, 0.85, 0.2, 0.7)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission = Color("b4e05a")
	_mat.emission_energy_multiplier = 1.2
	mesh.material_override = _mat
	add_child(mesh)


func _physics_process(delta: float) -> void:
	lifetime -= delta
	_mat.albedo_color.a = clampf(lifetime, 0.0, 0.7)
	if lifetime <= 0.0:
		queue_free()
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.25
		for body in get_overlapping_bodies():
			if body.has_method("take_damage"):
				body.take_damage(dps * 0.25, global_position)
