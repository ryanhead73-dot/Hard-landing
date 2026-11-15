class_name Drifter
extends Enemy
## Shatterlands drifter (X4.2): a gas-bladder the size of a barrel that hangs under the fungus
## caps on a skirt of tendrils, swelling with spores. It drifts toward anything warm, and close
## up it swells (a long, loud telegraph) and bursts in a cloud that hurts everything near it,
## its own kind and the scuttlers included. Shot first, it still bursts where it hangs: popping
## one over a pack is the point. The teal core inside the bladder is its weak spot.

enum State { DRIFT, CHASE, SWELL, DEAD }

@export var hover_height := 2.8
@export var burst_damage := 22.0
## Damage to anything else caught in the cloud (other creatures, and Juno if she pops it close).
@export var splash_damage := 30.0
@export var burst_radius := 3.6
@export var swell_time := 1.1
## How far from home it wanders while idle. A drifter moored over a nest keeps close.
@export var wander_radius := 7.0

## Starts swelling this close to its target.
const SWELL_RANGE := 3.0
## A burst Juno shot early still catches her, but less.
const SHOT_BURST_SCALE := 0.4
## The cloud sinks: below the burst, height counts for this much, so one popped over a pack
## reaches the creatures under it.
const CLOUD_SINK := 0.5
const VIOLET := Color("b49cff")
const CORE := Color("3fd1b5")

var state := State.DRIFT
var bursts := 0
var _timer := 0.0
var _bob := 0.0
var _ground_y := 0.0
var _ground_timer := 0.0
var _wander := Vector3.ZERO
var _visual: Node3D
var _tilt: Node3D
var _sac_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _sac_glow := 0.1
var _core_glow := 1.3


func _init() -> void:
	max_health = 24.0
	speed = 2.6
	# Slow, dim senses: it notices Juno late, so one hanging over a pack stays there to be shot.
	sight_range = 14.0
	alert_radius = 10.0
	drops = Vector2i(0, 1)
	death_puff = 0.5
	weak_joint = "Core"
	weak_offset = Vector3(0.0, 0.12, 0.0)
	weak_radius = 0.26


func _setup() -> void:
	add_to_group("drifters")
	# It floats over the undergrowth and through Juno's space; only rock and stems stop it.
	collision_mask = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.55
	shape.shape = s
	add_child(shape)
	_build()
	_bob = randf() * TAU
	_wander = home
	_timer = randf_range(0.5, 3.0)


func _build() -> void:
	# The tilt node leans into the drift; the visual under it turns slowly on its own axis.
	_tilt = Node3D.new()
	add_child(_tilt)
	_visual = Node3D.new()
	_tilt.add_child(_visual)
	_load_rig("drifter", _visual)
	_sac_mat = Rig.own_material(_rig, "drifter_membrane")
	_core_mat = Rig.own_material(_rig, "drifter_core")
	if _sac_mat:
		_sac_glow = _sac_mat.emission_energy_multiplier
	if _core_mat:
		_core_glow = _core_mat.emission_energy_multiplier


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_timer -= delta
	_bob += delta * 1.7
	_ground_timer -= delta
	if _ground_timer <= 0.0:
		_ground_timer = 0.3
		_ground_y = _ground_below()
	var want := Vector3.ZERO
	match state:
		State.DRIFT:
			want = _toward(_wander, speed * 0.5)
			if _flat(_wander - global_position).length() < 1.5 or _timer <= 0.0:
				_pick_wander()
			if _target_alive() and _can_see_target():
				alert(true)
				state = State.CHASE
		State.CHASE:
			if not _target_alive():
				state = State.DRIFT
			else:
				var aim: Vector3 = target.global_position + Vector3.UP * 1.2
				want = _toward(aim, speed)
				if global_position.distance_to(aim) < SWELL_RANGE:
					_start_swell()
				elif _out_of_leash(_flat(target.global_position - global_position)):
					calm()
					state = State.DRIFT
		State.SWELL:
			# Keeps edging in while it swells.
			if _target_alive():
				want = _toward(target.global_position + Vector3.UP * 1.2, speed * 0.4)
			var k := 1.0 - clampf(_timer / swell_time, 0.0, 1.0)
			# The swell clip balloons the bladder; the glow climbs with it.
			if _core_mat:
				_core_mat.emission_energy_multiplier = _core_glow + k * 7.0
			if _sac_mat:
				_sac_mat.emission_energy_multiplier = _sac_glow + k * 1.6
			if _timer <= 0.0:
				_burst(1.0)
				return
	# Hover over the ground; swelling, it sinks to chest height.
	var hover_y := _ground_y + (1.4 if state == State.SWELL else hover_height) + sin(_bob) * 0.25
	want.y = clampf((hover_y - global_position.y) * 2.0, -2.0, 2.5)
	velocity = velocity.move_toward(want, 6.0 * delta)
	move_and_slide()
	_visual.rotation.y += delta * 0.4
	# It tips into its drift, like a bladder dragged by its skirt.
	var lean := Vector3(velocity.z, 0.0, -velocity.x) * 0.07
	_tilt.rotation.x = lerp_angle(_tilt.rotation.x, clampf(lean.x, -0.3, 0.3), delta * 3.0)
	_tilt.rotation.z = lerp_angle(_tilt.rotation.z, clampf(lean.z, -0.3, 0.3), delta * 3.0)


func _toward(point: Vector3, spd: float) -> Vector3:
	var to := point - global_position
	if to.length() < 0.05:
		return Vector3.ZERO
	return to.normalized() * spd


func _pick_wander() -> void:
	var a := randf() * TAU
	_wander = home + Vector3(cos(a), 0.0, sin(a)) * randf_range(minf(2.0, wander_radius * 0.5), wander_radius)
	_timer = randf_range(4.0, 7.0)


func _start_swell() -> void:
	state = State.SWELL
	_timer = swell_time
	Sfx.play("lurker_hiss", global_position, 0.0, 0.15)


## The cloud: hurts everything inside `burst_radius`. `juno_scale` is how much of a full burst
## Juno takes (a drifter shot early, away from her, barely touches her).
func _burst(juno_scale: float) -> void:
	if state == State.DEAD and bursts > 0:
		return
	bursts += 1
	var at := global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not (e is Enemy) or (e as Enemy).dead:
			continue
		if (e as Node3D).global_position.distance_to(at) <= burst_radius:
			(e as Enemy).take_damage(splash_damage, at, Vector3.ZERO)
	for p in get_tree().get_nodes_in_group("player"):
		var chest: Vector3 = (p as Node3D).global_position + Vector3.UP * 1.0
		if chest.distance_to(at) <= burst_radius and p.has_method("take_damage"):
			p.take_damage(burst_damage * juno_scale, at)
			if p.has_method("add_trauma"):
				p.add_trauma(0.35 * juno_scale + 0.1)
	Sfx.play("charge_blast", at, -6.0, 0.1)
	if is_inside_tree():
		Vfx.burst(get_parent(), at, VIOLET.lightened(0.3), 40, 4.5, 0.18, 1.1, Vector3.UP, 180.0, -0.5)
		Vfx.burst(get_parent(), at, CORE, 14, 3.0, 0.08, 0.6, Vector3.UP, 180.0, -2.0)
	if state != State.DEAD:
		health = 0.0
		_die()


## Whether `point` is inside a burst at `at`: a sphere that sags below the bladder.
func in_cloud(point: Vector3, at: Vector3) -> bool:
	var d := point - at
	if d.y < 0.0:
		d.y *= CLOUD_SINK
	return d.length() <= burst_radius


func _die() -> void:
	var swelling := state == State.SWELL
	state = State.DEAD
	remove_from_group("drifters")
	super._die()
	_visual.visible = false
	# Shot down, it still goes off where it hangs, gentler on Juno unless it was already swelling.
	if bursts == 0:
		_burst(1.0 if swelling else SHOT_BURST_SCALE)
	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(queue_free)


func _ground_below() -> float:
	if not is_inside_tree():
		return 0.0
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0, Game.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else global_position.y - hover_height


func _on_hurt(_dir: Vector3) -> void:
	Sfx.play("lurker_hurt", global_position, -6.0, 0.2)


func anim_state() -> String:
	return String(State.find_key(state)).to_lower()
