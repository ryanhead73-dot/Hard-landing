class_name RidgeDiver
extends Enemy
## Loom Expanse ridge diver (milestone C3): a blunt-snouted burrower that travels under the soft
## weave as a moving bulge of dust, hunting by footfall. It can't go through bare stone, so the
## slabs in the Weave are safe ground. Run on the weave near it and it turns your way; when it's
## under where you were, a ring of grit marks the spot and it grinds for a moment before it
## erupts straight up there. Out of the ground it hangs for a breath with the turquoise gill ring
## under its neck open (the weak spot), then sinks, leaving a loose pocket that drags at the feet.
## Rolling clear of an eruption makes it overreach: it hangs there longer.
##
## Different from the Kettle's lurker (an ambusher in water that waits) and the scuttler (a
## pack that runs at you): this one is a floor you read, by sound and by the bulge.
## The region it lives in tells it where the weave is with `on_weave(world_pos)`.

enum State { PROWL, TRACK, MARK, SURFACED, DIVE, DEAD }

const HEAR_RANGE := 22.0
## Faster than a walk on the weave is loud (a run, a landing); walking and crouching are not.
const LOUD_SPEED := 5.0
const PROWL_SPEED := 1.6
const TRACK_SPEED := 3.6
## Close enough under her to mark the spot.
const STRIKE_RANGE := 1.4
const MARK_TIME := 0.9
const ERUPT_RADIUS := 1.5
const ERUPT_DAMAGE := 22.0
## How long it hangs out of the ground, and how much of that its gills are open (inhaling).
const SURFACE_TIME := 2.4
const INHALE_TIME := 2.0
## After a dodged eruption it overreaches: longer out, longer open.
const OVERREACH := 1.6
const DIVE_TIME := 0.6
const REST := 1.8
const POCKET_TIME := 3.0
const POCKET_RADIUS := 1.5
## With the survey team's weave grips, a run carries this much less far.
const GRIPS_HEARING := 0.5
const PLATE := Color("2c2a2e")
const DUST := Color("6e5a54")
const GILL := Color("38f0d8")
const MARK := Color("ffb050")

var state := State.PROWL
## Where it last heard her, and where it is about to come up.
var heard_at := Vector3.INF
var mark_at := Vector3.INF
## Eruptions that hit, and ones she dodged (tests read these).
var hits := 0
var dodged := 0
var _timer := 0.0
var _open_for := INHALE_TIME
var _wander := Vector3.INF
var _grind_t := 0.0
var _shape: CollisionShape3D
var _mound: MeshInstance3D
var _body: Node3D
var _ring: MeshInstance3D
var _pocket: MeshInstance3D
var _pocket_at := Vector3.INF
var _pocket_t := 0.0
var _gill_mat: StandardMaterial3D


func _init() -> void:
	max_health = 60.0
	speed = TRACK_SPEED
	sight_range = HEAR_RANGE
	alert_radius = 0.0
	drops = Vector2i(1, 2)
	death_puff = 0.8
	weak_joint = "Gill"
	weak_radius = 0.5


func _setup() -> void:
	add_to_group("ridge_divers")
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 2.0
	_shape.shape = cap
	_shape.position = Vector3(0.0, 1.0, 0.0)
	add_child(_shape)
	_build()
	_bury(true)
	_timer = randf_range(0.0, 2.0)
	_grind_t = randf_range(0.0, 3.0)


func _build() -> void:
	var dust := StandardMaterial3D.new()
	dust.albedo_color = DUST
	dust.roughness = 1.0
	_mound = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.8
	sm.height = 0.7
	sm.radial_segments = 10
	sm.rings = 4
	_mound.mesh = sm
	_mound.material_override = dust
	_mound.scale = Vector3(1.0, 0.6, 1.5)
	add_child(_mound)
	_body = Node3D.new()
	add_child(_body)
	_load_rig("ridge_diver", _body)
	# The gill ring under the neck: the weak spot, bright while it inhales.
	_gill_mat = Rig.own_material(_rig, "diver_gill")
	# The grit ring that marks where it will come up.
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = MARK
	ring_mat.emission_enabled = true
	ring_mat.emission = MARK
	ring_mat.emission_energy_multiplier = 1.6
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring = MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = ERUPT_RADIUS - 0.15
	rm.outer_radius = ERUPT_RADIUS
	rm.rings = 24
	rm.ring_segments = 4
	_ring.mesh = rm
	_ring.material_override = ring_mat
	_ring.top_level = true
	_ring.visible = false
	add_child(_ring)
	# The loose pocket it leaves behind.
	_pocket = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = POCKET_RADIUS
	pm.bottom_radius = POCKET_RADIUS * 0.8
	pm.height = 0.06
	pm.radial_segments = 14
	_pocket.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color("1e1618")
	pmat.roughness = 1.0
	_pocket.material_override = pmat
	_pocket.top_level = true
	_pocket.visible = false
	add_child(_pocket)


func underground() -> bool:
	return state in [State.PROWL, State.TRACK, State.MARK]


func _bury(on: bool) -> void:
	_shape.disabled = on
	collision_layer = 0 if on else Game.LAYER_ENEMY
	_mound.visible = on
	_body.visible = not on


func take_damage(amount: float, point: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO) -> bool:
	# Under the weave nothing reaches it, blasts included.
	if underground():
		return false
	return super(amount, point, dir)


func _weave_ok(p: Vector3) -> bool:
	var region := get_parent()
	if region and region.has_method("on_weave"):
		return region.on_weave(p)
	return true


## She's loud: on the weave, within earshot, moving faster than a walk.
func _hears_target() -> bool:
	if not _target_alive():
		return false
	var at: Vector3 = target.global_position
	var reach := HEAR_RANGE * (GRIPS_HEARING if Game.flags.get("weave_grips", false) else 1.0)
	if _flat(at - global_position).length() > reach or not _weave_ok(at):
		return false
	var v: Vector3 = target.velocity if "velocity" in target else Vector3.ZERO
	return Vector2(v.x, v.z).length() > LOUD_SPEED or v.y < -4.0


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_timer -= delta
	_tick_pocket(delta)
	match state:
		State.PROWL:
			if _timer <= 0.0 and _hears_target():
				heard_at = target.global_position
				alert(false)
				state = State.TRACK
			else:
				if _wander == Vector3.INF or _flat(_wander - global_position).length() < 0.3 or _timer < -5.0:
					_timer = randf_range(0.5, 1.0)
					var a := randf() * TAU
					_wander = home + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 8.0)
				_crawl(_wander, PROWL_SPEED, delta)
		State.TRACK:
			if _hears_target():
				heard_at = target.global_position
			_crawl(heard_at, TRACK_SPEED, delta)
			if _flat(heard_at - global_position).length() < STRIKE_RANGE:
				if _target_alive() and _flat(target.global_position - global_position).length() < 3.0 and _weave_ok(target.global_position):
					_start_mark(target.global_position)
				else:
					_lose()
			elif not _hears_target() and _flat(heard_at - global_position).length() > HEAR_RANGE:
				_lose()
		State.MARK:
			_mound.position.x = sin(_timer * 60.0) * 0.06
			if _timer <= 0.0:
				_erupt()
		State.SURFACED:
			var rise := clampf((SURFACE_TIME + _open_for - INHALE_TIME - _timer) / 0.2, 0.0, 1.0)
			_body.position.y = lerpf(-2.0, 0.0, rise)
			_gill_mat.emission_energy_multiplier = 3.5 if _weak_open() else 0.5
			if _target_alive():
				_face(target.global_position, clampf(4.0 * delta, 0.0, 1.0))
			if _timer <= 0.0:
				_start_dive()
		State.DIVE:
			_body.position.y = lerpf(0.0, -2.0, clampf(1.0 - _timer / DIVE_TIME, 0.0, 1.0))
			if _timer <= 0.0:
				_bury(true)
				_body.position.y = 0.0
				state = State.PROWL
				_timer = REST
				_wander = Vector3.INF
	if underground():
		_grind_t -= delta
		if _grind_t <= 0.0:
			_grind_t = 0.9 if state != State.PROWL else 3.2
			Sfx.play("diver_grind", global_position, -6.0 if state != State.PROWL else -12.0, 0.15)
		_mound.scale = Vector3(1.0, 0.6 + 0.12 * sin(Time.get_ticks_msec() * 0.008), 1.5)


## Moves under the weave toward `goal`, never onto stone.
func _crawl(goal: Vector3, pace: float, delta: float) -> void:
	var to := _flat(goal - global_position)
	if to.length() < 0.05:
		return
	var step := to.normalized() * minf(pace * delta, to.length())
	for s in [step, Vector3(step.x, 0.0, 0.0), Vector3(0.0, 0.0, step.z)]:
		if s.length() > 0.001 and _weave_ok(global_position + s * 4.0):
			global_position += s
			_mound.rotation.y = atan2(-s.x, -s.z)
			return


func _lose() -> void:
	state = State.PROWL
	heard_at = Vector3.INF
	_timer = REST
	calm()


func _start_mark(at: Vector3) -> void:
	state = State.MARK
	mark_at = Vector3(at.x, global_position.y, at.z)
	global_position = mark_at
	_timer = MARK_TIME
	_ring.visible = true
	_ring.global_position = mark_at + Vector3.UP * 0.05
	Sfx.play("diver_grind", mark_at, 0.0, 0.0)


func _erupt() -> void:
	state = State.SURFACED
	_ring.visible = false
	_mound.position.x = 0.0
	_bury(false)
	_body.position.y = -2.0
	# It comes up facing what it heard, stretched straight, and whips forward.
	if _target_alive():
		var to: Vector3 = target.global_position - global_position
		if _flat(to).length() > 0.2:
			_body.rotation.y = atan2(-to.x, -to.z)
	_anim("attack")
	Sfx.play("diver_erupt", global_position, 0.0, 0.1)
	if is_inside_tree():
		Vfx.burst(get_parent(), global_position + Vector3.UP * 0.3, DUST, 18, 4.0, 0.1, 0.8, Vector3.UP, 50.0, -9.0)
	_open_for = INHALE_TIME
	if _target_alive():
		var off: Vector3 = target.global_position - global_position
		var flat := _flat(off).length()
		var rolling: bool = target.has_method("is_dodging") and target.is_dodging()
		if flat < ERUPT_RADIUS and off.y < 1.6 and not rolling:
			hits += 1
			target.take_damage(ERUPT_DAMAGE, global_position)
			if "velocity" in target:
				target.velocity += Vector3.UP * 5.0 + _flat(off).normalized() * 3.0
		elif flat < 4.0:
			# Grit across the visor, and it has overreached.
			dodged += 1
			_open_for = INHALE_TIME + OVERREACH
		if flat < 4.0 and target.has_method("add_trauma"):
			target.add_trauma(0.25)
	_timer = SURFACE_TIME + (_open_for - INHALE_TIME)


func _start_dive() -> void:
	state = State.DIVE
	_timer = DIVE_TIME
	_shape.disabled = true
	collision_layer = 0
	Sfx.play("lurker_dive", global_position, -4.0, 0.15)
	_pocket_at = global_position
	_pocket_t = POCKET_TIME
	_pocket.visible = true
	_pocket.global_position = _pocket_at + Vector3.UP * 0.03


## The loose pocket: for a few seconds it drags at the feet of anyone standing in it.
func _tick_pocket(delta: float) -> void:
	if _pocket_t <= 0.0:
		return
	_pocket_t -= delta
	if _pocket_t <= 0.0:
		_pocket.visible = false
		return
	if _target_alive() and _flat(target.global_position - _pocket_at).length() < POCKET_RADIUS and target.has_method("snag"):
		target.snag(0.25)


func _weak_open() -> bool:
	return state == State.SURFACED and _timer > SURFACE_TIME + (_open_for - INHALE_TIME) - _open_for


func _on_hurt(_dir_hit: Vector3) -> void:
	Sfx.play("lurker_hurt", global_position, -4.0, 0.2)


func _die() -> void:
	state = State.DEAD
	_ring.visible = false
	_pocket.visible = false
	remove_from_group("ridge_divers")
	super._die()
	if is_inside_tree():
		Vfx.burst(get_parent(), global_position + Vector3.UP * 1.2, GILL, 12, 2.5, 0.08, 0.6, Vector3.UP, 180.0, -3.0)
	var tween := create_tween()
	tween.tween_property(_body, "position:y", -2.2, 0.8)
	tween.tween_callback(queue_free)


func anim_state() -> String:
	return String(State.find_key(state)).to_lower()
