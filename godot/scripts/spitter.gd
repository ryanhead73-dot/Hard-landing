class_name Spitter
extends Enemy
## Spitter: keeps its distance, circles, then rears up with its acid sac glowing and lobs a glob
## where you're heading. Fragile up close. Its sac glows yellow-green, unlike the scuttlers' teal.

enum State { IDLE, MOVE, WINDUP, RECOVER, DEAD }

@export var keep_min := 8.0
@export var keep_max := 16.0
@export var windup_time := 0.75
@export var spit_cooldown := Vector2(2.4, 3.4)
@export var spit_damage := 14.0

var state := State.IDLE

var _timer := 0.0
var _spit_timer := 2.0
var _strafe := 1.0
var _visual: Node3D
var _sac: StandardMaterial3D
var _body_mat: StandardMaterial3D
var _wander := Vector3.ZERO


func _init() -> void:
	max_health = 45.0
	speed = 4.2
	sight_range = 30.0
	drops = Vector2i(1, 2)


func _setup() -> void:
	_wander = home
	_strafe = 1.0 if randf() < 0.5 else -1.0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.5
	shape.shape = capsule
	shape.position.y = 0.75
	add_child(shape)
	_build_visual()


func _physics_process(delta: float) -> void:
	_gravity_step(delta)
	_timer -= delta
	_spit_timer -= delta
	var flat_vel := Vector3.ZERO
	match state:
		State.IDLE:
			if _target_alive() and _can_see_target():
				alert()
			else:
				flat_vel = _wander_step()
		State.MOVE:
			flat_vel = _move(delta)
		State.WINDUP:
			if _target_alive():
				_face(target.global_position, delta * 6.0)
			_sac.emission_energy_multiplier = 1.0 + 6.0 * (1.0 - _timer / windup_time)
			_visual.position.y = 0.25 * (1.0 - _timer / windup_time)
			if _timer <= 0.0:
				_spit()
		State.RECOVER:
			if _timer <= 0.0:
				state = State.MOVE
	velocity.x = move_toward(velocity.x, flat_vel.x, 20.0 * delta)
	velocity.z = move_toward(velocity.z, flat_vel.z, 20.0 * delta)
	move_and_slide()
	if state != State.WINDUP:
		_visual.position.y = move_toward(_visual.position.y, 0.0, delta)


func _wander_step() -> Vector3:
	if _flat(global_position).distance_to(_flat(_wander)) < 0.8:
		if _timer <= 0.0:
			var a := randf() * TAU
			_wander = home + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, 5.0)
			_timer = randf_range(2.0, 4.0)
		return Vector3.ZERO
	var dir := _flat(_wander - global_position).normalized()
	_face(global_position + dir, 0.1)
	return dir * speed * 0.3


func _move(delta: float) -> Vector3:
	if not _target_alive():
		calm()
		return Vector3.ZERO
	var to_target := _flat(target.global_position - global_position)
	var dist := to_target.length()
	if _out_of_leash(to_target):
		calm()
		return Vector3.ZERO
	_face(target.global_position, delta * 8.0)
	if _spit_timer <= 0.0 and dist < keep_max + 6.0 and _can_see_target():
		state = State.WINDUP
		_timer = windup_time
		Sfx.play("spitter_charge", global_position, -3.0, 0.1)
		return Vector3.ZERO
	var want := to_target.normalized()
	if dist > keep_max:
		pass
	elif dist < keep_min:
		want = -want
	else:
		want = want.cross(Vector3.UP) * _strafe
	if randf() < delta * 0.3:
		_strafe = -_strafe
	return _steer_around_walls(want.normalized(), delta) * speed


func _spit() -> void:
	state = State.RECOVER
	_timer = 0.5
	_spit_timer = randf_range(spit_cooldown.x, spit_cooldown.y)
	_sac.emission_energy_multiplier = 1.0
	if not _target_alive():
		return
	var mouth := global_position + Vector3.UP * 1.4 + _forward() * 0.6
	var aim_at := target.global_position + Vector3.UP * 0.4
	var flight := clampf(mouth.distance_to(aim_at) / 14.0, 0.5, 1.4)
	if "velocity" in target:
		var v: Vector3 = target.velocity
		aim_at += Vector3(v.x, 0.0, v.z) * flight * 0.6
	var glob := AcidGlob.new()
	glob.splash_damage = spit_damage
	glob.intended = target
	glob.velocity = AcidGlob.aim(mouth, aim_at, flight)
	get_parent().add_child(glob)
	glob.global_position = mouth
	Sfx.play("spitter_spit", global_position, -2.0, 0.1)


func _on_hurt(_dir: Vector3) -> void:
	Sfx.play("scuttler_hurt", global_position, -4.0, 0.25)


func _on_alert() -> void:
	if state == State.IDLE:
		state = State.MOVE
		_spit_timer = randf_range(0.6, 1.6)
		Sfx.play("scuttler_alert", global_position, -2.0, 0.3)


func _on_calm() -> void:
	state = State.IDLE
	_wander = home


func _die() -> void:
	state = State.DEAD
	super._die()
	Sfx.play("scuttler_death", global_position, 0.0, 0.25)
	_sac.emission_energy_multiplier = 0.0
	var tween := create_tween()
	tween.tween_property(_visual, "rotation:z", 1.4, 0.35)
	tween.tween_interval(2.5)
	tween.tween_property(_visual, "position:y", -1.0, 1.0)
	tween.tween_callback(queue_free)


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color("2a2f2c")
	_body_mat.roughness = 0.85
	_flashes(_body_mat)
	_sac = _glow(Color("b4e05a"), 1.0)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.4
	body.mesh = capsule
	body.material_override = _body_mat
	body.position.y = 0.9
	body.rotation.x = -0.35
	_visual.add_child(body)
	var sac := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.5
	sac.mesh = sphere
	sac.material_override = _sac
	sac.position = Vector3(0.0, 1.35, 0.15)
	_visual.add_child(sac)
	for side in [-1.0, 1.0]:
		for j in 2:
			var leg := MeshInstance3D.new()
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(0.07, 0.9, 0.07)
			leg.mesh = leg_mesh
			leg.material_override = _body_mat
			leg.position = Vector3(0.35 * side, 0.4, -0.2 + j * 0.4)
			leg.rotation.z = -0.35 * side
			_visual.add_child(leg)
	var mouth := MeshInstance3D.new()
	var mouth_mesh := SphereMesh.new()
	mouth_mesh.radius = 0.1
	mouth_mesh.height = 0.2
	mouth.mesh = mouth_mesh
	mouth.material_override = _sac
	mouth.position = Vector3(0.0, 1.45, -0.5)
	_visual.add_child(mouth)
