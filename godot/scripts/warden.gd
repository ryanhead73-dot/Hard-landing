class_name Warden
extends Enemy
## The Warden: the Loom's oldest scuttler, the size of a hauler cab. It rises when the nav core
## is taken. It cycles slams (a ring of force you jump), charges (it stuns itself on stone) and
## acid volleys, and calls the pack at two-thirds and one-third health. Its carapace turns most
## of the damage; it's open while stunned or right after a slam.

signal phase_changed(phase: int)

enum State { IDLE, APPROACH, SLAM_WINDUP, CHARGE_WINDUP, CHARGE, VOLLEY_WINDUP, OPEN, RECOVER, DEAD }

@export var armor := 0.55
@export var open_bonus := 1.8
@export var slam_damage := 24.0
@export var charge_damage := 34.0
@export var charge_speed := 13.0

var state := State.IDLE
## 0 above two-thirds, 1 above one-third, 2 below. Each drop calls the pack.
var phase := 0
## Main hands this in so the Warden can call scuttlers.
var summon: Callable

var _timer := 0.0
var _attack := 0
var _charge_dir := Vector3.ZERO
var _charge_hit := false
var _visual: Node3D
var _core: StandardMaterial3D
var _shell: StandardMaterial3D


func _init() -> void:
	max_health = 1400.0
	speed = 3.2
	sight_range = 45.0
	leash_range = 60.0
	alert_radius = 30.0
	drops = Vector2i(10, 12)


func _setup() -> void:
	add_to_group("bosses")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.4, 4.2)
	shape.shape = box
	shape.position.y = 1.3
	add_child(shape)
	_build_visual()


func _physics_process(delta: float) -> void:
	_gravity_step(delta)
	_timer -= delta
	var flat_vel := Vector3.ZERO
	match state:
		State.IDLE:
			if _target_alive() and _can_see_target():
				alert()
		State.APPROACH:
			flat_vel = _approach(delta)
		State.SLAM_WINDUP:
			_visual.position.y = 1.2 * (1.0 - _timer / 1.1)
			_core.emission_energy_multiplier = 1.0 + 5.0 * (1.0 - _timer / 1.1)
			if _timer <= 0.0:
				_slam()
		State.CHARGE_WINDUP:
			if _target_alive():
				_face(target.global_position, delta * 3.0)
			if _timer <= 0.0:
				_start_charge()
		State.CHARGE:
			flat_vel = _charge_step()
		State.VOLLEY_WINDUP:
			if _target_alive():
				_face(target.global_position, delta * 4.0)
			if _timer <= 0.0:
				_volley()
		State.OPEN, State.RECOVER:
			_visual.position.y = move_toward(_visual.position.y, 0.0, delta * 4.0)
			if _timer <= 0.0:
				state = State.APPROACH
				_core.emission_energy_multiplier = 1.0
	if state == State.CHARGE:
		velocity.x = flat_vel.x
		velocity.z = flat_vel.z
	else:
		velocity.x = move_toward(velocity.x, flat_vel.x, 12.0 * delta)
		velocity.z = move_toward(velocity.z, flat_vel.z, 12.0 * delta)
	move_and_slide()
	if state == State.CHARGE:
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var collider := c.get_collider()
			if collider is CollisionObject3D and (collider as CollisionObject3D).collision_layer & Game.LAYER_WORLD and c.get_normal().y < 0.5 and c.get_normal().dot(-_charge_dir) > 0.4:
				_open(2.6)
				Sfx.play("ram_stun", global_position, 3.0, 0.0)
				break


func _approach(delta: float) -> Vector3:
	if not _target_alive():
		calm()
		return Vector3.ZERO
	var to_target := _flat(target.global_position - global_position)
	if _timer <= 0.0 and to_target.length() < 22.0:
		_choose_attack(to_target.length())
		return Vector3.ZERO
	var dir := _steer_around_walls(to_target.normalized(), delta)
	_face(global_position + dir, delta * 3.0)
	return dir * speed


## Close: slam. Mid: charge. Far: acid. Cycles so it never repeats one move forever.
func _choose_attack(dist: float) -> void:
	_attack = (_attack + 1) % 3
	var pick := _attack
	if dist < 6.0:
		pick = 0
	elif dist > 16.0:
		pick = 2
	match pick:
		0:
			state = State.SLAM_WINDUP
			_timer = 1.1
			Sfx.play("warden_roar", global_position, 0.0, 0.05)
		1:
			state = State.CHARGE_WINDUP
			_timer = 0.9
			Sfx.play("ram_paw", global_position, 4.0, 0.0)
		2:
			state = State.VOLLEY_WINDUP
			_timer = 0.8
			Sfx.play("spitter_charge", global_position, 4.0, 0.0)


func _slam() -> void:
	Sfx.play("rock_impact", global_position, 6.0, 0.0)
	var ring := LoomPulse.new()
	ring.one_shot = true
	ring.period = 999.0
	ring.damage = slam_damage
	ring.max_radius = 16.0
	ring.speed = 11.0
	ring.start_radius = 2.5
	ring.target = target if target and target.is_in_group("player") else null
	get_parent().add_child(ring)
	ring.global_position = Vector3(global_position.x, global_position.y, global_position.z)
	ring.fire()
	_open(1.4)


func _start_charge() -> void:
	state = State.CHARGE
	_timer = 1.6
	_charge_hit = false
	_charge_dir = _flat(target.global_position - global_position).normalized() if _target_alive() else _forward()
	_face(global_position + _charge_dir, 1.0)
	Sfx.play("ram_charge", global_position, 4.0, 0.0)


func _charge_step() -> Vector3:
	if _timer <= 0.0:
		state = State.RECOVER
		_timer = 1.0
		return Vector3.ZERO
	if not _charge_hit and _target_alive() and _flat(target.global_position - global_position).length() < 3.0:
		_charge_hit = true
		target.take_damage(charge_damage, global_position)
		if "velocity" in target:
			target.velocity += _charge_dir * 10.0 + Vector3.UP * 4.0
	return _charge_dir * charge_speed


func _volley() -> void:
	state = State.RECOVER
	_timer = 1.2
	if not _target_alive():
		return
	var mouth := global_position + Vector3.UP * 2.6 + _forward() * 1.6
	for i in 3:
		var aim_at := target.global_position + _forward().cross(Vector3.UP) * (i - 1) * 2.5
		var glob := AcidGlob.new()
		glob.splash_damage = 16.0
		glob.intended = target
		glob.velocity = AcidGlob.aim(mouth, aim_at, clampf(mouth.distance_to(aim_at) / 14.0, 0.6, 1.5))
		get_parent().add_child(glob)
		glob.global_position = mouth
	Sfx.play("spitter_spit", global_position, 4.0, 0.0)


func _open(seconds: float) -> void:
	state = State.OPEN
	_timer = seconds
	_core.emission_energy_multiplier = 6.0


func is_open() -> bool:
	return state == State.OPEN


func _damage_scale(_point: Vector3, _dir: Vector3) -> float:
	return open_bonus if state == State.OPEN else armor


func _on_hurt(_dir: Vector3) -> void:
	var new_phase := 0 if health > max_health * 2.0 / 3.0 else (1 if health > max_health / 3.0 else 2)
	if new_phase > phase and health > 0.0:
		phase = new_phase
		phase_changed.emit(phase)
		Sfx.play("warden_roar", global_position, 3.0, 0.0)
		if summon.is_valid():
			for i in 3:
				var a := TAU * i / 3.0
				summon.call(global_position + Vector3(cos(a) * 6.0, 0.5, sin(a) * 6.0))


func _on_alert() -> void:
	if state == State.IDLE:
		state = State.APPROACH
		_timer = 1.5
		Sfx.play("warden_roar", global_position, 2.0, 0.0)


func _on_calm() -> void:
	state = State.IDLE


func _die() -> void:
	state = State.DEAD
	remove_from_group("bosses")
	super._die()
	Sfx.play("warden_roar", global_position, 4.0, 0.0)
	_core.emission_energy_multiplier = 0.0
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3(1.1, 0.4, 1.1), 0.8)
	tween.tween_interval(6.0)
	tween.tween_property(_visual, "position:y", -2.5, 2.0)
	tween.tween_callback(queue_free)


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_shell = StandardMaterial3D.new()
	_shell.albedo_color = Color("16181a")
	_shell.roughness = 0.7
	_flashes(_shell)
	_core = _glow(Color("3fd1b5"), 1.0)
	var carapace := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.8
	sphere.height = 2.4
	sphere.radial_segments = 9
	sphere.rings = 5
	carapace.mesh = sphere
	carapace.material_override = _shell
	carapace.position.y = 1.6
	carapace.scale = Vector3(1.0, 1.0, 1.35)
	_visual.add_child(carapace)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.6
	core_mesh.height = 1.2
	core.mesh = core_mesh
	core.material_override = _core
	core.position = Vector3(0.0, 2.6, 0.8)
	_visual.add_child(core)
	for i in 7:
		var spine := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.7, 0.18)
		spine.mesh = box
		spine.material_override = _core
		spine.position = Vector3(0.0, 2.9, -1.6 + i * 0.5)
		spine.rotation.x = -0.4
		_visual.add_child(spine)
	for side in [-1.0, 1.0]:
		for j in 3:
			var leg := MeshInstance3D.new()
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(1.6, 0.2, 0.2)
			leg.mesh = leg_mesh
			leg.material_override = _shell
			leg.position = Vector3(1.6 * side, 0.7, -1.0 + j * 1.0)
			leg.rotation.z = 0.6 * side
			_visual.add_child(leg)
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.16
		eye_mesh.height = 0.32
		eye.mesh = eye_mesh
		eye.material_override = _core
		eye.position = Vector3(0.5 * side, 1.7, -2.3)
		_visual.add_child(eye)
