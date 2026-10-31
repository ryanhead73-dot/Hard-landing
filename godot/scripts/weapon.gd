class_name Weapon
extends Node3D
## Salvage rifle: hitscan, magazine and reload. Shots are traced from the camera so they land on
## the crosshair, then drawn from the muzzle so they read in third person.

signal fired
signal ammo_changed(in_mag: int, mag_size: int, reloading: bool)
signal hit_confirmed(killed: bool)

@export var damage := 18.0
@export var fire_interval := 0.11
@export var base_mag_size := 24
@export var reload_time := 1.6
@export var hip_spread := 0.012
@export var aim_spread := 0.003
@export var max_range := 150.0

var camera: Camera3D
var shooter: CollisionObject3D
var in_mag := 24
var reloading := false

var _cooldown := 0.0
var _reload_left := 0.0
var _muzzle: Node3D
var _flash: OmniLight3D
var _tracer_mat: StandardMaterial3D


func _ready() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("24282b")
	metal.metallic = 0.6
	metal.roughness = 0.45
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color("c4622d")
	_part(Vector3(0.08, 0.11, 0.72), Vector3(0.0, 0.0, -0.1), metal)
	_part(Vector3(0.06, 0.16, 0.12), Vector3(0.0, -0.11, 0.06), metal)
	_part(Vector3(0.085, 0.03, 0.3), Vector3(0.0, 0.06, -0.12), stripe)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.0, 0.01, -0.48)
	add_child(_muzzle)
	_flash = OmniLight3D.new()
	_flash.light_color = Color("ffc070")
	_flash.light_energy = 3.0
	_flash.omni_range = 4.0
	_flash.visible = false
	_muzzle.add_child(_flash)
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.albedo_color = Color("ffd08a")
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color("ffb24d")
	_tracer_mat.emission_energy_multiplier = 4.0
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	in_mag = mag_size()
	Game.upgrades_changed.connect(_on_upgrades_changed)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			reloading = false
			in_mag = mag_size()
			ammo_changed.emit(in_mag, mag_size(), false)


func mag_size() -> int:
	return base_mag_size + (12 if Game.has_upgrade("extended_mag") else 0)


func shot_damage() -> float:
	return damage * (1.3 if Game.has_upgrade("heavy_rounds") else 1.0)


func start_reload() -> void:
	if reloading or in_mag == mag_size():
		return
	reloading = true
	_reload_left = reload_time
	Sfx.play("rifle_reload", null, -4.0, 0.0)
	ammo_changed.emit(in_mag, mag_size(), true)


func refill() -> void:
	reloading = false
	in_mag = mag_size()
	ammo_changed.emit(in_mag, mag_size(), false)


## Fires one round if the weapon is ready. Returns true when a round left the barrel.
func try_fire(aiming: bool) -> bool:
	if reloading or _cooldown > 0.0 or camera == null:
		return false
	if in_mag <= 0:
		Sfx.play("rifle_empty", null, -6.0)
		start_reload()
		return false
	in_mag -= 1
	_cooldown = fire_interval * (0.8 if Game.has_upgrade("rapid_cycler") else 1.0)

	var spread := aim_spread if aiming else hip_spread
	var dir := -camera.global_basis.z
	dir = dir.rotated(camera.global_basis.x, randf_range(-spread, spread))
	dir = dir.rotated(camera.global_basis.y, randf_range(-spread, spread)).normalized()
	# Start past the player so walls behind the camera never eat the shot.
	var skip := camera.global_position.distance_to(_muzzle.global_position) * 0.8
	var origin := camera.global_position + dir * skip
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, Game.LAYER_WORLD | Game.LAYER_ENEMY)
	if shooter:
		query.exclude = [shooter.get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var end: Vector3 = result.position if result else origin + dir * max_range
	if result:
		var target: Object = result.collider
		if target.has_method("take_damage"):
			var killed: bool = target.take_damage(shot_damage(), result.position, dir)
			hit_confirmed.emit(killed)
			Sfx.play("kill_tick" if killed else "hit_tick", null, -4.0, 0.0)
		elif target.has_meta("on_hit"):
			(target.get_meta("on_hit") as Callable).call()
		_impact(result.position, result.normal)
	_tracer(_muzzle.global_position, end)
	_show_flash()
	Sfx.play("rifle_shot", null, -3.0, 0.08)
	fired.emit()
	ammo_changed.emit(in_mag, mag_size(), false)
	if in_mag == 0:
		start_reload()
	return true


func _on_upgrades_changed() -> void:
	ammo_changed.emit(in_mag, mag_size(), reloading)


func _part(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	add_child(mesh)


func _show_flash() -> void:
	_flash.visible = true
	await get_tree().create_timer(0.04).timeout
	if is_instance_valid(_flash):
		_flash.visible = false


func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var tracer := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = length
	cyl.radial_segments = 4
	tracer.mesh = cyl
	tracer.material_override = _tracer_mat
	tracer.top_level = true
	add_child(tracer)
	var mid := (from + to) * 0.5
	var axis := (to - from) / length
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	tracer.global_transform = Transform3D(Basis(side, axis, side.cross(axis)), mid)
	get_tree().create_timer(0.05).timeout.connect(tracer.queue_free)


func _impact(pos: Vector3, normal: Vector3) -> void:
	var sparks := CPUParticles3D.new()
	sparks.top_level = true
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 10
	sparks.lifetime = 0.35
	sparks.direction = normal
	sparks.spread = 50.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.scale_amount_min = 0.03
	sparks.scale_amount_max = 0.06
	var quad := QuadMesh.new()
	quad.material = _tracer_mat
	sparks.mesh = quad
	add_child(sparks)
	sparks.global_position = pos
	sparks.emitting = true
	get_tree().create_timer(0.6).timeout.connect(sparks.queue_free)
