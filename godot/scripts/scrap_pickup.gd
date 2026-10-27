class_name ScrapPickup
extends Node3D
## A bit of salvage on the ground. Drifts toward the player when close and is collected on touch.

@export var amount := 5
@export var magnet_range := 4.0
@export var collect_range := 0.9

var target: Node3D

var _spin := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("scrap")
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.12, 0.3)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("9aa0a3")
	mat.metallic = 0.7
	mat.emission_enabled = true
	mat.emission = Color("ffb24d")
	mat.emission_energy_multiplier = 0.6
	_mesh.material_override = mat
	_mesh.position.y = 0.35
	add_child(_mesh)


func _process(delta: float) -> void:
	_spin += delta
	_mesh.rotation.y = _spin * 2.0
	_mesh.position.y = 0.35 + sin(_spin * 3.0) * 0.06
	if target == null or ("dead" in target and target.dead):
		return
	var to_target := target.global_position + Vector3.UP * 0.6 - global_position
	var dist := to_target.length()
	if dist < collect_range:
		Game.add_scrap(amount)
		queue_free()
	elif dist < magnet_range:
		global_position += to_target.normalized() * minf(dist, 9.0 * delta)
