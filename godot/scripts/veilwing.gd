class_name Veilwing
extends Enemy
## Gillwood veilwing (X5.3): a leathery glider the span of a door that roosts hanging under the
## gill caps. When it sees Juno it lets go, flares its wings with a shriek (the telegraph, and
## the moment to shoot it), then swoops through her chest height in one long dive it can barely
## steer at the end: step aside and it overshoots, climbs away, circles and comes again. The
## teal gill-strip under its body is its weak spot, and it shows when the wings flare.

enum State { ROOST, FLARE, SWOOP, CLIMB, DEAD }

@export var swoop_damage := 14.0
@export var swoop_speed := 12.0
@export var flare_time := 0.7
## Height over the ground it circles at between passes.
@export var circle_height := 6.0

## Within this of Juno's chest, a pass hits.
const HIT_RANGE := 1.0
## In the last few metres of a dive it can hardly turn: that is the dodge window.
const COMMIT_RANGE := 7.0
const TURN_RATE := 2.4
const LEAD := 0.35
const BODY := Color("3a3550")
const MEMBRANE := Color("5b4f8a")
const GILL := Color("3fd1b5")

var state := State.ROOST
var passes := 0
var hits := 0
var _timer := 0.0
var _flap := 0.0
var _dir := Vector3.FORWARD
var _hit_this_pass := false
var _closest := INF
var _circle_at := Vector3.ZERO
var _visual: Node3D
var _wings: Array[Node3D] = []
var _gill_mat: StandardMaterial3D


func _init() -> void:
	max_health = 30.0
	speed = 6.0
	sight_range = 18.0
	alert_radius = 12.0
	drops = Vector2i(0, 1)
	death_puff = 0.6
	weak_offset = Vector3.ZERO
	weak_radius = 0.3


func _setup() -> void:
	add_to_group("veilwings")
	collision_mask = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.45
	shape.shape = s
	add_child(shape)
	_build()
	_flap = randf() * TAU
	_timer = randf_range(0.0, 1.0)


func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = BODY
	body_mat.roughness = 0.6
	_flashes(body_mat)
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.35
	bm.height = 1.3
	bm.radial_segments = 10
	bm.rings = 5
	body.mesh = bm
	body.rotation.x = PI * 0.5
	body.material_override = body_mat
	_visual.add_child(body)
	# The gill-strip along its belly: the weak spot, glowing brighter when it flares.
	_gill_mat = StandardMaterial3D.new()
	_gill_mat.albedo_color = GILL.darkened(0.4)
	_gill_mat.emission_enabled = true
	_gill_mat.emission = GILL
	_gill_mat.emission_energy_multiplier = 1.2
	var gill := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.22, 0.08, 0.8)
	gill.mesh = gm
	gill.material_override = _gill_mat
	gill.position = Vector3(0.0, -0.3, 0.0)
	_visual.add_child(gill)
	_weak = gill
	var membrane := StandardMaterial3D.new()
	membrane.albedo_color = MEMBRANE
	membrane.roughness = 0.5
	membrane.cull_mode = BaseMaterial3D.CULL_DISABLED
	membrane.rim_enabled = true
	membrane.rim = 0.6
	_flashes(membrane)
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.25, 0.05, 0.0)
		_visual.add_child(pivot)
		var wing := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(1.3, 0.04, 0.9)
		wing.mesh = wm
		wing.material_override = membrane
		wing.position = Vector3(side * 0.65, 0.0, 0.1)
		pivot.add_child(wing)
		_wings.append(pivot)
	var tail := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.08
	tm.bottom_radius = 0.01
	tm.height = 0.9
	tm.radial_segments = 5
	tail.mesh = tm
	tail.material_override = body_mat
	tail.rotation.x = PI * 0.5
	tail.position = Vector3(0.0, 0.0, 0.95)
	_visual.add_child(tail)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_timer -= delta
	var flap_rate := 2.0
	var flap_amp := 0.25
	match state:
		State.ROOST:
			# Hangs folded at its roost, swaying a little.
			velocity = (home - global_position) * 2.0
			flap_amp = 0.08
			flap_rate = 1.0
			if _target_alive() and _timer <= 0.0:
				_timer = 0.3
				if _can_see_target():
					alert(true)
					_start_flare()
		State.FLARE:
			velocity = velocity.move_toward(Vector3.ZERO, 8.0 * delta)
			flap_rate = 7.0
			flap_amp = 0.9
			_gill_mat.emission_energy_multiplier = 4.0
			if _timer <= 0.0:
				_start_swoop()
		State.SWOOP:
			flap_amp = 0.05
			if _target_alive():
				var chest: Vector3 = target.global_position + Vector3.UP * 1.2
				var to := chest - global_position
				# Steers while far off; in the last few metres it's committed.
				if to.length() > COMMIT_RANGE:
					_dir = _dir.slerp(to.normalized(), clampf(TURN_RATE * delta, 0.0, 1.0)).normalized()
				var d := global_position.distance_to(chest)
				if not _hit_this_pass and d < HIT_RANGE:
					_hit_this_pass = true
					hits += 1
					target.take_damage(swoop_damage, global_position)
					if target.has_method("add_trauma"):
						target.add_trauma(0.3)
				_closest = minf(_closest, d)
				# Past her (or long gone): pull up.
				if d > _closest + 2.5 or _timer <= 0.0:
					_start_climb()
			else:
				_start_climb()
			velocity = _dir * swoop_speed
		State.CLIMB:
			flap_rate = 5.0
			flap_amp = 0.6
			var to := _circle_at - global_position
			velocity = velocity.move_toward(to.normalized() * speed * 1.4 if to.length() > 0.5 else Vector3.ZERO, 10.0 * delta)
			if _timer <= 0.0 or to.length() < 1.0:
				if _target_alive() and _can_see_target() and global_position.distance_to(target.global_position) < sight_range * 1.5:
					_start_flare()
				elif to.length() < 1.0 or _timer < -6.0:
					calm()
					state = State.ROOST
	move_and_slide()
	_flap += delta * flap_rate * TAU
	for i in _wings.size():
		_wings[i].rotation.z = sin(_flap) * flap_amp * (-1.0 if i == 0 else 1.0)
	# Faces the way it flies (or Juno, while it flares).
	var face := velocity
	if state == State.FLARE and _target_alive():
		face = target.global_position - global_position
	if Vector2(face.x, face.z).length() > 0.1:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-face.x, -face.z), clampf(8.0 * delta, 0.0, 1.0))
	_visual.rotation.x = lerpf(_visual.rotation.x, -0.5 if state == State.SWOOP else 0.0, clampf(6.0 * delta, 0.0, 1.0))
	if state != State.FLARE:
		_gill_mat.emission_energy_multiplier = lerpf(_gill_mat.emission_energy_multiplier, 1.2, clampf(4.0 * delta, 0.0, 1.0))


func _start_flare() -> void:
	state = State.FLARE
	_timer = flare_time
	Sfx.play("veilwing_screech", global_position, 2.0, 0.1)


func _start_swoop() -> void:
	state = State.SWOOP
	passes += 1
	_hit_this_pass = false
	_closest = INF
	_timer = 3.0
	Sfx.play("veilwing_dive", global_position, 0.0, 0.08)
	if _target_alive():
		var lead: Vector3 = target.velocity * LEAD if "velocity" in target else Vector3.ZERO
		_dir = (target.global_position + Vector3.UP * 1.2 + lead - global_position).normalized()


## Up and away to a point over the ground past where it was heading, to circle back from.
func _start_climb() -> void:
	state = State.CLIMB
	_timer = 2.2
	Sfx.play("veilwing_flap", global_position, -2.0, 0.08)
	var flat := Vector3(_dir.x, 0.0, _dir.z).normalized()
	var ground := global_position.y
	if is_inside_tree():
		var from := global_position + Vector3.UP * 0.5
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0, Game.LAYER_WORLD)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			ground = (hit.position as Vector3).y
	_circle_at = Vector3(global_position.x, ground + circle_height, global_position.z) + flat * 6.0
	# Not too far from its roost.
	var off := _circle_at - home
	off.y = 0.0
	if off.length() > 20.0:
		_circle_at -= off.normalized() * (off.length() - 20.0)


## Startled (a chime rung near it): it breaks off and climbs away from `from` for `secs`
## before it looks for its target again.
func scare(from: Vector3, secs := 4.0) -> void:
	if state == State.DEAD:
		return
	var away := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	_dir = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	_start_climb()
	_circle_at += _dir * 6.0 + Vector3.UP * 3.0
	_timer = secs


func _weak_open() -> bool:
	return state == State.FLARE or state == State.CLIMB


func _on_hurt(_dir_hit: Vector3) -> void:
	Sfx.play("skimmer_hurt", global_position, -4.0, 0.25)
	# Hit while hanging still, it goes for her at once.
	if state == State.ROOST:
		alert(true)
		_start_flare()


func _die() -> void:
	state = State.DEAD
	remove_from_group("veilwings")
	super._die()
	if is_inside_tree():
		Vfx.burst(get_parent(), global_position, GILL, 12, 2.5, 0.08, 0.6, Vector3.UP, 180.0, -3.0)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.4)
	tween.tween_callback(queue_free)


func anim_state() -> String:
	return String(State.find_key(state)).to_lower()
