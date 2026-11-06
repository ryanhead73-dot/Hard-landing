class_name Skimmer
extends Enemy
## Basin skimmer: a lean glider that wheels high over whatever it has picked out, then hangs in
## the air for a moment, its belly sac flaring, and dives to rake with its talons on the way past
## before climbing away to go round again. Fragile, and a straight dive is the moment to shoot
## it: hit it hard as it hangs or dives and it tumbles out of the air, stunned on the ground.
## The glowing belly sac is its weak spot. They come with the packs once Kestrel's half-mended.

enum State { CLIMB, CIRCLE, WINDUP, DIVE, GROUNDED, DEAD }

@export var attack_damage := 12.0
@export var cruise_height := 6.5
@export var circle_radius := 9.0
@export var dive_speed := 17.0
@export var windup_time := 0.75
@export var grounded_time := 1.8
## Damage taken in one hit, while hanging or diving, that knocks it out of the air.
@export var knockdown_damage := 16.0

const RAKE_RANGE := 1.5
const DIVE_TIME := 1.6
## Seconds circling before each dive.
const CIRCLE_TIME := Vector2(2.2, 3.6)
const GROUNDED_DAMAGE := 1.5

var state := State.CLIMB
var dives := 0
var rakes := 0

var _timer := 0.0
var _angle := 0.0
var _turn := 1.0
var _ground_y := 0.0
var _ground_timer := 0.0
var _dive_dir := Vector3.FORWARD
var _raked := false
var _visual: Node3D
var _glow_mat: StandardMaterial3D
var _flap_timer := 0.0


func _init() -> void:
	max_health = 40.0
	speed = 8.0
	sight_range = 30.0
	alert_radius = 18.0
	drops = Vector2i(1, 2)
	death_puff = 0.8
	# The belly sac.
	weak_joint = "Core"
	weak_offset = Vector3.ZERO
	weak_radius = 0.32


func _setup() -> void:
	add_to_group("skimmers")
	# It flies over everything and through Juno's space; only rock stops it.
	collision_mask = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var body := CapsuleShape3D.new()
	body.radius = 0.3
	body.height = 1.4
	shape.shape = body
	shape.rotation.x = PI * 0.5
	add_child(shape)
	_visual = Node3D.new()
	add_child(_visual)
	_load_rig("skimmer", _visual)
	_glow_mat = Rig.own_material(_rig, "skimmer_glow")
	_angle = randf() * TAU
	_turn = 1.0 if randf() < 0.5 else -1.0
	_timer = randf_range(CIRCLE_TIME.x, CIRCLE_TIME.y)


func _physics_process(delta: float) -> void:
	_timer -= delta
	_ground_timer -= delta
	if _ground_timer <= 0.0:
		_ground_timer = 0.25
		_ground_y = _ground_below()
	var want := Vector3.ZERO
	match state:
		State.CLIMB:
			want = _orbit_velocity(delta)
			if global_position.y > _ground_y + cruise_height - 0.6:
				state = State.CIRCLE
				_timer = randf_range(CIRCLE_TIME.x, CIRCLE_TIME.y)
		State.CIRCLE:
			want = _orbit_velocity(delta)
			if not hunting and _target_alive() and _can_see_target():
				alert(true)
			if hunting and _timer <= 0.0 and _target_alive():
				state = State.WINDUP
				_timer = windup_time
				Sfx.play("skimmer_screech", global_position, 0.0, 0.1)
		State.WINDUP:
			# Hangs in the air, beating hard, and lines up.
			want = Vector3.ZERO
			if _target_alive():
				_face(target.global_position, delta * 8.0)
			if _timer <= 0.0:
				_start_dive()
		State.DIVE:
			want = _dive_dir * dive_speed
			_face(global_position + _dive_dir, delta * 10.0)
			_try_rake()
			if _timer <= 0.0 or (global_position.y < _ground_y + 0.7 and _dive_dir.y < 0.0) or is_on_wall():
				_pull_up()
		State.GROUNDED:
			velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
			if not is_on_floor():
				velocity.y -= _gravity * delta
			move_and_slide()
			if _timer <= 0.0:
				state = State.CLIMB
			_animate(delta)
			return
		State.DEAD:
			if not is_on_floor():
				velocity.y -= _gravity * delta
			velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
			move_and_slide()
			return
	var accel := 40.0 if state == State.DIVE else 12.0
	velocity = velocity.move_toward(want, accel * delta)
	move_and_slide()
	_animate(delta)


## Wheels round its target (or home) at cruise height.
func _orbit_velocity(delta: float) -> Vector3:
	var centre := target.global_position if hunting and _target_alive() else home
	var radius := circle_radius if hunting else circle_radius * 1.4
	_angle += _turn * speed / radius * delta
	var goal := centre + Vector3(cos(_angle), 0.0, sin(_angle)) * radius
	goal.y = maxf(_ground_y, centre.y) + cruise_height
	var to := goal - global_position
	var v := to.normalized() * minf(to.length() * 2.0, speed * 1.3)
	_face(global_position + Vector3(v.x, 0.0, v.z), delta * 4.0)
	if hunting and _target_alive() and _out_of_leash(_flat(target.global_position - global_position)):
		calm()
	return v


func _start_dive() -> void:
	state = State.DIVE
	_timer = DIVE_TIME
	_raked = false
	dives += 1
	var aim := global_position + _forward() * 6.0
	if _target_alive():
		# Leads its prey a little.
		var tv: Vector3 = target.velocity if "velocity" in target else Vector3.ZERO
		aim = target.global_position + Vector3.UP * 1.0 + Vector3(tv.x, 0.0, tv.z) * 0.35
	_dive_dir = (aim - global_position).normalized()
	_anim("attack")
	Sfx.play("skimmer_dive", global_position, -2.0, 0.1)


func _try_rake() -> void:
	if _raked or not _target_alive():
		return
	var chest: Vector3 = target.global_position + Vector3.UP * 1.0
	if global_position.distance_to(chest) < RAKE_RANGE:
		_raked = true
		rakes += 1
		if target.has_method("take_damage"):
			target.take_damage(attack_damage, global_position)
		Sfx.play("skimmer_rake", global_position, 0.0, 0.1)
		# Carries on through, then climbs.
		_timer = minf(_timer, 0.25)


func _pull_up() -> void:
	state = State.CLIMB
	_dive_dir = Vector3.FORWARD
	velocity.y = maxf(velocity.y, 4.0)


func _ground_below() -> float:
	if not is_inside_tree():
		return 0.0
	var from := global_position + Vector3.UP * 2.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0, Game.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else global_position.y - cruise_height


func _damage_scale(_point: Vector3, _dir: Vector3) -> float:
	return GROUNDED_DAMAGE if state == State.GROUNDED else 1.0


func _on_hurt(_dir: Vector3) -> void:
	Sfx.play("skimmer_hurt", global_position, -3.0, 0.12)


## Knocked out of the air: big hits (or a crit) while it hangs or dives bring it down.
func take_damage(amount: float, point: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO) -> bool:
	var before := health
	var killed := super.take_damage(amount, point, dir)
	if not killed and state in [State.WINDUP, State.DIVE] and (before - health >= knockdown_damage or last_hit_crit):
		_knock_down()
	return killed


func _knock_down() -> void:
	state = State.GROUNDED
	_timer = grounded_time
	velocity = Vector3(velocity.x * 0.3, -2.0, velocity.z * 0.3)
	Sfx.play("skimmer_hurt", global_position, 2.0, 0.05)


func is_grounded() -> bool:
	return state == State.GROUNDED


func _on_calm() -> void:
	if state in [State.WINDUP, State.DIVE]:
		_pull_up()


func _die() -> void:
	state = State.DEAD
	remove_from_group("skimmers")
	super._die()
	Sfx.play("skimmer_death", global_position, 0.0, 0.1)
	if _glow_mat:
		_glow_mat.emission_energy_multiplier = 0.0
	var tween := create_tween()
	tween.tween_interval(3.5)
	tween.tween_property(_visual, "scale", Vector3(1.0, 0.2, 1.0), 0.8)
	tween.tween_callback(queue_free)


func _animate(delta: float) -> void:
	if _glow_mat:
		var glow := 1.2
		match state:
			State.WINDUP:
				glow = 5.0
			State.DIVE:
				glow = 3.0
			State.GROUNDED:
				glow = 0.4 + absf(sin(Time.get_ticks_msec() * 0.02)) * 1.5
		_glow_mat.emission_energy_multiplier = glow
	# Banks into its turns and pitches with its climb or dive.
	var pitch := 0.0
	var roll := 0.0
	match state:
		State.DIVE:
			pitch = asin(clampf(_dive_dir.y, -1.0, 1.0))
		State.CLIMB:
			pitch = 0.35
		State.CIRCLE:
			roll = -_turn * 0.4
	_visual.rotation.x = lerp_angle(_visual.rotation.x, pitch, clampf(delta * 6.0, 0.0, 1.0))
	_visual.rotation.z = lerp_angle(_visual.rotation.z, roll, clampf(delta * 4.0, 0.0, 1.0))
	# A wingbeat now and then.
	_flap_timer -= delta
	if _flap_timer <= 0.0 and state in [State.CLIMB, State.WINDUP]:
		_flap_timer = 0.32 if state == State.WINDUP else 0.5
		Sfx.play("skimmer_flap", global_position, -10.0, 0.15)


func anim_state() -> String:
	return String(State.find_key(state)).to_lower()
