class_name AcidGlob
extends Node3D
## A lobbed glob of acid from a spitter or the Warden. Flies on a ballistic arc, bursts on contact
## with the ground, a wall or the player, splashes whatever is close and leaves a hissing puddle.

const GRAVITY := 14.0

@export var splash_damage := 14.0
@export var splash_radius := 1.7
@export var puddle_time := 3.0
@export var puddle_dps := 9.0

var velocity := Vector3.ZERO
## What the glob was thrown at (the player or a point on Kestrel's hull).
var intended: Node3D

var _age := 0.0


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	mesh.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("c8e83a")
	m.emission_enabled = true
	m.emission = Color("b4e05a")
	m.emission_energy_multiplier = 3.0
	mesh.material_override = m
	add_child(mesh)


## Velocity that lands at `to` from `from` after `time` seconds.
static func aim(from: Vector3, to: Vector3, time: float) -> Vector3:
	var d := to - from
	return Vector3(d.x / time, (d.y + 0.5 * GRAVITY * time * time) / time, d.z / time)


func _physics_process(delta: float) -> void:
	_age += delta
	velocity.y -= GRAVITY * delta
	var step := velocity * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, Game.LAYER_WORLD | Game.LAYER_PLAYER)
	var hit := space.intersect_ray(query)
	if not hit.is_empty() or _age > 6.0:
		_burst(hit.get("position", global_position))
		return
	global_position += step


func _burst(at: Vector3) -> void:
	set_physics_process(false)
	Sfx.play("acid_splash", at, -2.0, 0.1)
	Vfx.acid(get_parent(), at)
	for body in get_tree().get_nodes_in_group("player"):
		if body.global_position.distance_to(at) < splash_radius + 0.4:
			body.take_damage(splash_damage, at)
	if intended and is_instance_valid(intended) and not intended.is_in_group("player") and intended.has_method("take_damage") and intended.global_position.distance_to(at) < 3.0:
		intended.take_damage(splash_damage, at)
	var puddle := AcidPuddle.new()
	puddle.lifetime = puddle_time
	puddle.dps = puddle_dps
	get_parent().add_child(puddle)
	puddle.global_position = Vector3(at.x, at.y + 0.02, at.z)
	queue_free()
