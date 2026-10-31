class_name Ram
extends Enemy
## Basalt ram: a heavy grazer with a slab of armour on its head. It paws the ground and its crest
## flares, then it charges in a straight line. Shots off the front plate barely scratch it; hit
## it from the side or behind, or make it charge into a wall and it's stunned and open.

enum State { IDLE, APPROACH, PAW, CHARGE, STUNNED, RECOVER, DEAD }

@export var charge_range := 16.0
@export var paw_time := 0.9
@export var charge_speed := 14.0
@export var charge_time := 1.3
@export var charge_damage := 30.0
@export var stun_time := 1.8
@export var front_armor := 0.25
@export var rear_bonus := 1.5
@export var stun_bonus := 2.0

var state := State.IDLE

var _timer := 0.0
var _charge_dir := Vector3.ZERO
var _charge_hit := false
var _wander := Vector3.ZERO
var _visual: Node3D
var _crest: StandardMaterial3D
var _hide: StandardMaterial3D


func _init() -> void:
	max_health = 170.0
	speed = 3.6
	sight_range = 26.0
	drops = Vector2i(3, 4)


func _setup() -> void:
	death_puff = 1.6
	_wander = home
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.4, 2.4)
	shape.shape = box
	shape.position.y = 0.75
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
			else:
				flat_vel = _wander_step()
		State.APPROACH:
			flat_vel = _approach(delta)
		State.PAW:
			if _target_alive():
				_face(target.global_position, delta * 4.0)
			_crest.emission_energy_multiplier = 0.6 + 5.0 * (1.0 - _timer / paw_time)
			if _timer <= 0.0:
				_start_charge()
		State.CHARGE:
			flat_vel = _charge_step()
		State.STUNNED, State.RECOVER:
			if _timer <= 0.0:
				state = State.APPROACH
				_crest.emission_energy_multiplier = 0.6
	if state == State.CHARGE:
		velocity.x = flat_vel.x
		velocity.z = flat_vel.z
	else:
		velocity.x = move_toward(velocity.x, flat_vel.x, 18.0 * delta)
		velocity.z = move_toward(velocity.z, flat_vel.z, 18.0 * delta)
	move_and_slide()
	if state == State.CHARGE and get_slide_collision_count() > 0:
		_check_wall()
	_visual.rotation.z = sin(Time.get_ticks_msec() * 0.03) * 0.08 if state == State.STUNNED else 0.0


func _wander_step() -> Vector3:
	if _flat(global_position).distance_to(_flat(_wander)) < 1.0:
		if _timer <= 0.0:
			var a := randf() * TAU
			_wander = home + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, 5.0)
			_timer = randf_range(3.0, 6.0)
		return Vector3.ZERO
	var dir := _flat(_wander - global_position).normalized()
	_face(global_position + dir, 0.05)
	return dir * speed * 0.3


func _approach(delta: float) -> Vector3:
	if not _target_alive():
		calm()
		return Vector3.ZERO
	var to_target := _flat(target.global_position - global_position)
	if _out_of_leash(to_target):
		calm()
		return Vector3.ZERO
	if to_target.length() < charge_range and is_on_floor() and _can_see_target():
		state = State.PAW
		_timer = paw_time
		Sfx.play("ram_paw", global_position, 0.0, 0.1)
		return Vector3.ZERO
	var dir := _steer_around_walls(to_target.normalized(), delta)
	_face(global_position + dir, delta * 5.0)
	return dir * speed


func _start_charge() -> void:
	state = State.CHARGE
	_timer = charge_time
	_charge_hit = false
	_charge_dir = _flat(target.global_position - global_position).normalized() if _target_alive() else _forward()
	_face(global_position + _charge_dir, 1.0)
	Sfx.play("ram_charge", global_position, 0.0, 0.05)


func _charge_step() -> Vector3:
	if _timer <= 0.0:
		_end_charge(false)
		return Vector3.ZERO
	if not _charge_hit and _target_alive() and _flat(target.global_position - global_position).length() < 1.9:
		_charge_hit = true
		target.take_damage(charge_damage, global_position)
		if "velocity" in target:
			target.velocity += _charge_dir * 8.0 + Vector3.UP * 3.0
	return _charge_dir * charge_speed


func _check_wall() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var collider := c.get_collider()
		# Only solid scenery stuns it: not the player, not other wildlife, not a gentle slope.
		if collider is CollisionObject3D and (collider as CollisionObject3D).collision_layer & Game.LAYER_WORLD and n.y < 0.5 and n.dot(-_charge_dir) > 0.5:
			_end_charge(true)
			return


func _end_charge(hit_wall: bool) -> void:
	_anim("attack")
	state = State.STUNNED if hit_wall else State.RECOVER
	_timer = stun_time if hit_wall else 0.8
	velocity = -_charge_dir * (3.0 if hit_wall else 0.0)
	_crest.emission_energy_multiplier = 0.1 if hit_wall else 0.6
	if hit_wall:
		Sfx.play("ram_stun", global_position, 0.0, 0.05)


## The head plate shrugs off shots from the front; flanks, rear and a stunned ram take more.
func _damage_scale(_point: Vector3, dir: Vector3) -> float:
	if state == State.STUNNED:
		return stun_bonus
	var facing := _forward().dot(-_flat(dir).normalized())
	if facing > 0.5:
		return front_armor
	if facing < -0.2:
		return rear_bonus
	return 1.0


func is_stunned() -> bool:
	return state == State.STUNNED


func _on_hurt(_dir: Vector3) -> void:
	Sfx.play("scuttler_hurt", global_position, -2.0, 0.1)


func _on_alert() -> void:
	if state == State.IDLE:
		state = State.APPROACH
		Sfx.play("ram_paw", global_position, -2.0, 0.2)


func _on_calm() -> void:
	state = State.IDLE
	_wander = home


func _die() -> void:
	state = State.DEAD
	super._die()
	Sfx.play("scuttler_death", global_position, 2.0, 0.0)
	_crest.emission_energy_multiplier = 0.0
	var tween := create_tween()
	tween.tween_property(_visual, "rotation:z", 1.3, 0.5)
	tween.tween_interval(3.0)
	tween.tween_property(_visual, "position:y", -1.5, 1.2)
	tween.tween_callback(queue_free)


func anim_state() -> String:
	return String(State.find_key(state)).to_lower()


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_load_rig("ram", _visual)
	_crest = Rig.own_material(_rig, "moss_glow")
	_hide = Rig.own_material(_rig, "ram_hide")
