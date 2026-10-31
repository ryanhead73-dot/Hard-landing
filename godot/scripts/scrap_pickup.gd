class_name ScrapPickup
extends Node3D
## Something dropped on the ground: scrap, reserve ammo for a weapon (kind = weapon id) or a stim.
## Drifts toward the player when close and is collected on touch.

const COLORS := {"scrap": Color("ffb24d"), "scattergun": Color("e0603a"), "arc_lance": Color("7fd6ff"), "stim": Color("7dff9a")}

@export var kind := "scrap"
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
	mat.emission = COLORS.get(kind, Color.WHITE)
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
	if not _wanted():
		return
	if dist < collect_range:
		_collect()
		queue_free()
	elif dist < magnet_range:
		global_position += to_target.normalized() * minf(dist, 9.0 * delta)


## Full pouches leave stims and ammo on the ground for later.
func _wanted() -> bool:
	match kind:
		"scrap":
			return true
		"stim":
			return Game.stims < Game.max_stims()
	return Game.owns_weapon(kind) and Game.ammo_reserve(kind) < int(Weapon.SPECS[kind]["reserve_max"])


func _collect() -> void:
	match kind:
		"scrap":
			Game.add_scrap(amount)
		"stim":
			Game.add_stims(amount)
			Sfx.play("scrap_pickup", null, -6.0)
		_:
			Game.add_ammo(kind, amount)
			Sfx.play("scrap_pickup", null, -6.0)
