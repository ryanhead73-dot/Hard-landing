class_name Scuttler
extends Enemy
## Basalt scuttler: native fauna that hides as rock until something gets close, then rushes it.
## Readable at distance by its teal spine glow. Telegraphs every bite with a crouch before lunging.

enum State { IDLE, CHASE, WINDUP, RECOVER, DEAD }

@export var attack_damage := 14.0
@export var attack_range := 1.9
@export var windup_time := 0.45
@export var recover_time := 0.7
## Without an attack slot it circles this far out, waiting its turn.
const RING := 4.2

var state := State.IDLE

var _timer := 0.0
var _wander := Vector3.ZERO
var _gait := 0.0
var _visual: Node3D
var _glow_mat: StandardMaterial3D
var _shell: StandardMaterial3D
var _circle_side := 1.0
var _circle_timer := 0.0
## After a bite it hangs back a moment before asking for another turn.
var _rest := 0.0


func _init() -> void:
	max_health = 60.0
	speed = 5.0
	stagger_damage = 30.0
	# The glowing spine ridge along its back.
	weak_joint = "Body"
	weak_offset = Vector3(0.0, 0.42, 0.05)
	weak_radius = 0.45


func _setup() -> void:
	add_to_group("scuttlers")
	_wander = home
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	shape.shape = sphere
	shape.position.y = 0.55
	add_child(shape)
	_build_visual()


func _physics_process(delta: float) -> void:
	_gravity_step(delta)
	_timer -= delta
	_rest -= delta
	var flat_vel := Vector3.ZERO
	match state:
		State.IDLE:
			flat_vel = _idle()
		State.CHASE:
			flat_vel = _chase(delta)
		State.WINDUP:
			if _target_alive():
				_face(target.global_position, delta * 3.0)
			if _timer <= 0.0:
				_lunge()
		State.RECOVER:
			flat_vel = Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 14.0 * delta)
			if _timer <= 0.0:
				state = State.CHASE
				# Give someone else a go.
				_release_slot()
				_rest = 1.2
	if state != State.RECOVER:
		velocity.x = move_toward(velocity.x, flat_vel.x, 25.0 * delta)
		velocity.z = move_toward(velocity.z, flat_vel.z, 25.0 * delta)
	else:
		velocity.x = flat_vel.x
		velocity.z = flat_vel.z
	move_and_slide()
	_animate(delta)


func _on_hurt(dir: Vector3) -> void:
	velocity += Vector3(dir.x, 0.0, dir.z).normalized() * 1.5
	Sfx.play("scuttler_hurt", global_position, -6.0, 0.15)


## A bite in the wind-up is cancelled: it reels back and has to start again.
func _stagger(dir: Vector3) -> bool:
	if state != State.CHASE and state != State.WINDUP:
		return false
	state = State.RECOVER
	_timer = 0.6
	velocity += Vector3(dir.x, 0.0, dir.z).normalized() * 4.0 + Vector3.UP * 1.5
	Sfx.play("scuttler_hurt", global_position, -1.0, 0.2)
	return true


func _on_alert() -> void:
	if state == State.IDLE:
		state = State.CHASE
		Sfx.play("scuttler_alert", global_position, -2.0, 0.15)


func _on_calm() -> void:
	state = State.IDLE
	_wander = home


func _idle() -> Vector3:
	if _target_alive() and _can_see_target():
		alert()
		return Vector3.ZERO
	if _flat(global_position).distance_to(_flat(_wander)) < 0.8:
		if _timer <= 0.0:
			var a := randf() * TAU
			_wander = home + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, 6.0)
			_timer = randf_range(1.5, 4.0)
		return Vector3.ZERO
	var dir := _flat(_wander - global_position).normalized()
	_face(global_position + dir, 0.1)
	return dir * speed * 0.3


func _chase(delta: float) -> Vector3:
	if not _target_alive():
		calm()
		return Vector3.ZERO
	var to_target := _flat(target.global_position - global_position)
	if to_target.length() < attack_range and is_on_floor():
		state = State.WINDUP
		_timer = windup_time
		Sfx.play("scuttler_lunge", global_position, -4.0, 0.1)
		return Vector3.ZERO
	if _out_of_leash(to_target):
		calm()
		return Vector3.ZERO
	if to_target.length() < RING + 1.5 and (_rest > 0.0 or not _has_slot()):
		return _circle(to_target, delta)
	var dir := _steer_around_walls(to_target.normalized(), delta)
	_face(global_position + dir, delta * 10.0)
	return dir * speed


## Waiting its turn: skitters sideways round the ring, facing its prey, changing direction now
## and then.
func _circle(to_target: Vector3, delta: float) -> Vector3:
	_circle_timer -= delta
	if _circle_timer <= 0.0:
		_circle_timer = randf_range(1.2, 2.6)
		_circle_side = -_circle_side if randf() < 0.6 else _circle_side
	var dist := to_target.length()
	var inward := to_target / maxf(dist, 0.01)
	var tangent := inward.cross(Vector3.UP) * _circle_side
	var want := (tangent + inward * clampf((dist - RING) / 1.5, -1.0, 1.0)).normalized()
	want = _steer_around_walls(want, delta)
	_face(global_position + inward, delta * 8.0)
	return want * speed * 0.55


## Circling without a turn (not just backing off after a bite).
func is_waiting() -> bool:
	return state == State.CHASE and _rest <= 0.0 and _target_alive() and not self in _slots.get(target.get_instance_id(), [])


func _lunge() -> void:
	state = State.RECOVER
	_anim("attack")
	_timer = recover_time
	if not _target_alive():
		return
	var to_target := _flat(target.global_position - global_position)
	velocity += to_target.normalized() * 7.0
	if to_target.length() < attack_range + 0.6 and target.has_method("take_damage"):
		target.take_damage(attack_damage, global_position)


func _die() -> void:
	state = State.DEAD
	remove_from_group("scuttlers")
	super._die()
	Sfx.play("scuttler_death", global_position, 0.0, 0.1)
	_glow_mat.emission_energy_multiplier = 0.0
	var tween := create_tween()
	# Knocked back along the shot that killed it, rolling as it goes.
	var push := Vector3(last_hit_dir.x, 0.0, last_hit_dir.z)
	if push.length() > 0.01:
		var slide := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		slide.tween_property(self, "global_position", global_position + push.normalized() * 1.3, 0.3)
		slide.parallel().tween_property(_visual, "rotation:z", randf_range(-0.6, 0.6), 0.3)
	tween.tween_property(_visual, "scale", Vector3(1.2, 0.25, 1.2), 0.25)
	tween.tween_interval(2.5)
	tween.tween_property(_visual, "position:y", -0.6, 1.0)
	tween.tween_callback(queue_free)


func _animate(delta: float) -> void:
	if state == State.DEAD:
		return
	var moving := Vector2(velocity.x, velocity.z).length()
	_gait += delta * (4.0 + moving * 3.0)
	var crouch := 0.0
	if state == State.WINDUP:
		crouch = -0.18 * (1.0 - _timer / windup_time)
	_visual.position.y = absf(sin(_gait)) * 0.06 * minf(moving, 1.0) + crouch
	_glow_mat.emission_energy_multiplier = 4.0 if state == State.WINDUP else (2.0 if state != State.IDLE else 0.8)


func anim_state() -> String:
	return String(State.find_key(state)).to_lower()


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_load_rig("scuttler", _visual)
	_glow_mat = Rig.own_material(_rig, "moss_glow")
	_shell = Rig.own_material(_rig, "scuttler_shell")
