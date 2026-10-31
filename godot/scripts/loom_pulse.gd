class_name LoomPulse
extends Node3D
## The Loom breathes out: the spire brightens, then a ring of force rolls outward across the
## ground. Jump it or get thrown. The scuttlers are the Loom's own and ride it out.

signal pulsed

@export var period := 7.0
@export var warning_time := 1.2
@export var speed := 9.0
@export var max_radius := 30.0
@export var start_radius := 3.0
@export var ring_height := 0.7
@export var damage := 18.0
@export var knockback := 7.0
## Fires once (a Warden slam) and frees itself when the ring is done.
@export var one_shot := false

var radius := -1.0
var target: Node3D
## Glow material the warning brightens (the spire's veins). Optional.
var glow: StandardMaterial3D

var _timer := 0.0
var _warned := false
var _hit_this_pulse := false
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D


func _ready() -> void:
	_timer = period
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 64
	_ring.mesh = torus
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.25, 0.82, 0.71, 0.7)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color("3fd1b5")
	_ring_mat.emission_energy_multiplier = 3.0
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = _ring_mat
	_ring.visible = false
	add_child(_ring)


func _physics_process(delta: float) -> void:
	_timer -= delta
	if not one_shot and not _warned and _timer <= warning_time:
		_warned = true
		Sfx.play("loom_hum", global_position + Vector3.UP * 4.0, 0.0, 0.0)
	if glow:
		var t := clampf(1.0 - _timer / warning_time, 0.0, 1.0) if _warned else 0.0
		glow.emission_energy_multiplier = 1.5 + 6.0 * t
	if _timer <= 0.0 and not one_shot:
		fire()
	if radius < 0.0:
		return
	radius += speed * delta
	_ring.visible = true
	_ring.scale = Vector3(radius, ring_height * 4.0, radius)
	_ring.position.y = ring_height * 0.4
	_ring_mat.albedo_color.a = 0.7 * (1.0 - radius / max_radius)
	_check_hit()
	if radius >= max_radius:
		radius = -1.0
		_ring.visible = false
		if one_shot:
			queue_free()


## Sends a pulse now and restarts the cycle.
func fire() -> void:
	_timer = period
	_warned = false
	radius = start_radius
	_hit_this_pulse = false
	pulsed.emit()


func _check_hit() -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	if _hit_this_pulse or target == null or not is_instance_valid(target) or ("dead" in target and target.dead):
		return
	var offset := target.global_position - global_position
	var flat := Vector2(offset.x, offset.z).length()
	if absf(flat - radius) > 0.7 or offset.y > ring_height:
		return
	_hit_this_pulse = true
	if target.has_method("take_damage"):
		target.take_damage(damage, global_position)
	if "velocity" in target:
		var away := Vector3(offset.x, 0.0, offset.z).normalized()
		target.velocity += away * knockback + Vector3.UP * 3.0
