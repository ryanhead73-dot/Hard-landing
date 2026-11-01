class_name Lurker
extends Enemy
## Mire lurker: a long, low ambusher that lies in the basin's pools with only its eye stalks above
## the water. It bursts out when something wades or walks close, bites hard with a telegraphed
## gape, and never strays far from its pool: hurt or outrun, it dives home, heals under the water
## and waits again. Submerged it is almost impossible to hurt, so the answer is to bait it out
## (or flush it with an arc charge) and punish it on land.

enum State { SUBMERGED, EMERGE, CHASE, WINDUP, RECOVER, DIVE, DEAD }

@export var attack_damage := 24.0
@export var attack_range := 2.6
@export var windup_time := 0.55
@export var recover_time := 0.8
## How close something must come before it bursts out.
@export var ambush_range := 7.5
## How far from its pool it will chase.
@export var pool_leash := 13.0
@export var emerge_time := 0.6
## Its pool's radius: it strikes at anything wading in, and chases that much further.
var pool_radius := 0.0
@export var regen_per_second := 8.0
## Bites before it gives up and dives (it also dives when badly hurt).
@export var bites_before_dive := 3

const SUBMERGED_DEPTH := -0.42
const SUBMERGED_DAMAGE := 0.15

var state := State.SUBMERGED

var _timer := 0.0
var _bites := 0
var _fled_hurt := false
var _visual: Node3D
var _glow_mat: StandardMaterial3D
var _sink := 1.0


func _init() -> void:
	max_health = 150.0
	speed = 6.8
	sight_range = 18.0
	alert_radius = 0.0
	drops = Vector2i(3, 4)
	death_puff = 1.3


func _setup() -> void:
	add_to_group("lurkers")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 2.6
	shape.shape = capsule
	shape.rotation.x = PI * 0.5
	shape.position = Vector3(0.0, 0.45, 0.0)
	add_child(shape)
	_visual = Node3D.new()
	add_child(_visual)
	_load_rig("lurker", _visual)
	_glow_mat = Rig.own_material(_rig, "lurker_glow")
	_visual.position.y = SUBMERGED_DEPTH
	rotation.y = randf() * TAU


func is_submerged() -> bool:
	return state == State.SUBMERGED


func _physics_process(delta: float) -> void:
	_gravity_step(delta)
	_timer -= delta
	var flat_vel := Vector3.ZERO
	match state:
		State.SUBMERGED:
			_lurk(delta)
		State.EMERGE:
			if _target_alive():
				_face(target.global_position, delta * 6.0)
			if _timer <= 0.0:
				state = State.CHASE
		State.CHASE:
			flat_vel = _chase(delta)
		State.WINDUP:
			if _target_alive():
				_face(target.global_position, delta * 4.0)
			if _timer <= 0.0:
				_bite()
		State.RECOVER:
			flat_vel = Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 16.0 * delta)
			if _timer <= 0.0:
				if _bites >= bites_before_dive:
					_dive()
				else:
					state = State.CHASE
		State.DIVE:
			flat_vel = _swim_home(delta)
	if state == State.RECOVER:
		velocity.x = flat_vel.x
		velocity.z = flat_vel.z
	else:
		velocity.x = move_toward(velocity.x, flat_vel.x, 30.0 * delta)
		velocity.z = move_toward(velocity.z, flat_vel.z, 30.0 * delta)
	move_and_slide()
	_animate(delta)


## Waits under the water, healing, until something comes close enough to strike at.
func _lurk(delta: float) -> void:
	health = minf(health + regen_per_second * delta, max_health)
	if _timer > 0.0 or not _target_alive():
		return
	var to_target := _flat(target.global_position - global_position)
	if to_target.length() < maxf(ambush_range, pool_radius + 2.5) and _can_see_target():
		hunting = true
		_emerge()


func _on_alert() -> void:
	if state == State.SUBMERGED:
		_emerge()


func _emerge() -> void:
	state = State.EMERGE
	_timer = emerge_time
	_bites = 0
	_fled_hurt = false
	if is_inside_tree():
		Vfx.splash(get_parent(), global_position + Vector3.UP * 0.2, 2.4)
		Vfx.splash(get_parent(), global_position + _forward() * 0.9 + Vector3.UP * 0.2, 1.6)
	Sfx.play("lurker_emerge", global_position, 0.0, 0.1)
	_anim("attack")


func _chase(delta: float) -> Vector3:
	if not _target_alive():
		_dive()
		return Vector3.ZERO
	var to_target := _flat(target.global_position - global_position)
	var from_home := _flat(target.global_position - home).length()
	if from_home > pool_leash + pool_radius + 4.0:
		_dive()
		return Vector3.ZERO
	if to_target.length() < attack_range and is_on_floor():
		state = State.WINDUP
		_timer = windup_time
		Sfx.play("lurker_hiss", global_position, -3.0, 0.1)
		return Vector3.ZERO
	var dir := _steer_around_walls(to_target.normalized(), delta)
	_face(global_position + dir, delta * 8.0)
	return dir * speed


func _bite() -> void:
	state = State.RECOVER
	_timer = recover_time
	_bites += 1
	_anim("attack")
	Sfx.play("lurker_bite", global_position, -1.0, 0.1)
	if not _target_alive():
		return
	var to_target := _flat(target.global_position - global_position)
	velocity += to_target.normalized() * 9.0
	if to_target.length() < attack_range + 0.8 and target.has_method("take_damage"):
		target.take_damage(attack_damage, global_position)


func _dive() -> void:
	if state == State.DIVE or state == State.SUBMERGED or dead:
		return
	state = State.DIVE
	hunting = false


func _swim_home(delta: float) -> Vector3:
	var to_home := _flat(home - global_position)
	if to_home.length() < 0.8:
		state = State.SUBMERGED
		hunting = false
		# A short grace before it will strike again.
		_timer = 3.0
		if is_inside_tree():
			Vfx.splash(get_parent(), global_position + Vector3.UP * 0.2, 1.8)
		Sfx.play("lurker_dive", global_position, -3.0, 0.1)
		return Vector3.ZERO
	var dir := _steer_around_walls(to_home.normalized(), delta)
	_face(global_position + dir, delta * 8.0)
	return dir * speed * 1.15


func _damage_scale(_point: Vector3, _dir: Vector3) -> float:
	if state == State.SUBMERGED:
		return SUBMERGED_DAMAGE
	# Caught mid-gape, the soft mouth takes it hard.
	if state == State.WINDUP:
		return 1.5
	return 1.0


func _on_hurt(dir: Vector3) -> void:
	velocity += Vector3(dir.x, 0.0, dir.z).normalized() * 0.8
	Sfx.play("lurker_hurt", global_position, -5.0, 0.12)
	if state == State.SUBMERGED:
		alert(false)
	elif not _fled_hurt and health < max_health * 0.35 and state in [State.CHASE, State.RECOVER]:
		_fled_hurt = true
		_dive()


func _on_calm() -> void:
	_dive()


func _die() -> void:
	state = State.DEAD
	remove_from_group("lurkers")
	super._die()
	Sfx.play("lurker_death", global_position, 0.0, 0.08)
	_glow_mat.emission_energy_multiplier = 0.0
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(_visual, "position:y", -0.8, 1.4)
	tween.tween_callback(queue_free)


func _animate(delta: float) -> void:
	if state == State.DEAD:
		return
	var want := 1.0 if state == State.SUBMERGED else 0.0
	# Rises fast, sinks slowly.
	_sink = move_toward(_sink, want, delta * (3.0 if want < _sink else 1.2))
	_visual.position.y = SUBMERGED_DEPTH * ease(_sink, 0.6) + sin(Time.get_ticks_msec() * 0.002 + home.x) * 0.03 * _sink
	var glow := 0.5
	match state:
		State.WINDUP:
			glow = 4.0
		State.CHASE, State.EMERGE, State.RECOVER:
			glow = 1.6
	_glow_mat.emission_energy_multiplier = glow


func anim_state() -> String:
	return String(State.find_key(state)).to_lower()
