class_name PatienceGuardian
extends Enemy
## The Long Patience's guardian (production pack, repair 6): a plated thing the size of a cargo
## loader that has lived in the stern's engine hall since she came down. It has no eyes worth the
## name. It hunts by vibration: a run, a hard landing, a gunshot, and, once the drive coil is out
## of its cage, the coil itself, which rings on every Loom pulse. Walking near it is enough when
## it's close; crouching is nearly silent.
##
## It sleeps in its alcove until something wakes it: a surveillance mirror catching Juno, a shot
## nearby, a run right past it, or the coil leaving the cage (the extraction ambush). Awake, it
## walks to where it last felt her, and when it's close and sure it braces and charges. Its plate
## turns almost every shot. The hall's ceiling cargo magnets can grab it: one fired while it's under
## it yanks it up off its feet and tears its back plate open, and for a few seconds it can be hurt.
## It never leaves the hall.

enum State { DORMANT, HUNT, SEARCH, BRACE, CHARGE, RECOVER, PINNED, DEAD }

## How far each kind of vibration carries.
const HEAR_RUN := 30.0
const HEAR_LAND := 20.0
const HEAR_SHOT := 45.0
const HEAR_WALK := 4.5
const HEAR_CROUCH := 1.8
## Asleep, it only stirs to a shot or to someone running right past it.
const WAKE_SHOT := 25.0
const WAKE_RUN := 8.0
const LOUD_SPEED := 5.0
const WALK_SPEED := 3.0
const BRACE_RANGE := 6.5
const BRACE_TIME := 0.9
const CHARGE_SPEED := 11.0
const CHARGE_TIME := 0.6
const CHARGE_DAMAGE := 28.0
const RECOVER_TIME := 1.1
const SEARCH_TIME := 3.5
const PINNED_TIME := 6.0
## Its plate: the share of a hit that gets through, and through the torn-open back.
const PLATE := 0.15
const SHELL := Color("3b3633")
const RUST := Color("6e3b22")
const SENSE := Color("ff5a3a")

## Metres between footfalls.
const STRIDE := 2.6
var _stride := 0.0
var _groan := 0.0
var _search: Node
var state := State.DORMANT
var heard_at := Vector3.INF
## The hall it's held to (world-space x/z rectangle, set by the region).
var bounds := Rect2()
## Charges that hit her, times it was pinned (tests read these).
var hits := 0
var pins := 0
var _timer := 0.0
var _charge_dir := Vector3.ZERO
var _charge_hit := false
var _body: Node3D
var _back: Node3D
var _sense_mat: StandardMaterial3D
var _vent_mat: StandardMaterial3D
var _was_floor := true
var _fall_speed := 0.0


func _init() -> void:
	max_health = 700.0
	speed = WALK_SPEED
	sight_range = HEAR_RUN
	alert_radius = 0.0
	leash_range = 999.0
	drops = Vector2i(10, 14)
	death_puff = 2.0
	weak_radius = 0.9


func display_name() -> String:
	return "THE PATIENCE GUARDIAN"


func _setup() -> void:
	add_to_group("guardians")
	add_to_group("bosses")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.2, 3.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.1, 0.0)
	add_child(shape)
	_build()


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = SHELL
	shell.roughness = 0.5
	shell.metallic = 0.4
	_flashes(shell)
	var rust := StandardMaterial3D.new()
	rust.albedo_color = RUST
	rust.roughness = 0.85
	_flashes(rust)
	# A low, broad carapace in three overlapping plates, a blunt ram of a head and four short legs.
	for i in 3:
		var plate := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.1 - i * 0.2, 0.7, 1.3)
		plate.mesh = bm
		plate.material_override = shell if i != 1 else rust
		plate.position = Vector3(0.0, 1.55 + i * 0.12, 0.9 - i * 0.95)
		plate.rotation.x = -0.12 + i * 0.1
		_body.add_child(plate)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(1.3, 0.9, 0.8)
	head.mesh = hm
	head.material_override = shell
	head.position = Vector3(0.0, 1.0, -1.65)
	_body.add_child(head)
	for x in [-0.85, 0.85]:
		for z in [-0.9, 0.9]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.35, 1.1, 0.45)
			leg.mesh = lm
			leg.material_override = rust
			leg.position = Vector3(x, 0.55, z)
			leg.rotation.z = signf(x) * 0.18
			_body.add_child(leg)
	# The sensing pits along its brow: they flare when it feels her.
	_sense_mat = StandardMaterial3D.new()
	_sense_mat.albedo_color = SENSE.darkened(0.5)
	_sense_mat.emission_enabled = true
	_sense_mat.emission = SENSE
	_sense_mat.emission_energy_multiplier = 0.4
	var pits := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.0, 0.12, 0.06)
	pits.mesh = pm
	pits.material_override = _sense_mat
	pits.position = Vector3(0.0, 1.25, -2.06)
	_body.add_child(pits)
	# The back vent under the rear plate: shut until a magnet tears the plate up.
	_vent_mat = StandardMaterial3D.new()
	_vent_mat.albedo_color = Color("ffb04a").darkened(0.6)
	_vent_mat.emission_enabled = true
	_vent_mat.emission = Color("ffb04a")
	_vent_mat.emission_energy_multiplier = 0.0
	_back = MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(1.0, 0.2, 0.8)
	(_back as MeshInstance3D).mesh = vm
	(_back as MeshInstance3D).material_override = _vent_mat
	_back.position = Vector3(0.0, 1.95, 1.0)
	_body.add_child(_back)
	_weak = _back


func asleep() -> bool:
	return state == State.DORMANT


## Wakes it with a fix on `at` (a mirror's alarm, the coil leaving its cage).
func wake(at: Vector3) -> void:
	if dead:
		return
	heard_at = at
	if state in [State.DORMANT, State.SEARCH]:
		state = State.HUNT
		alert(false)
		Sfx.play("guardian_wake", global_position, 0.0, 0.05)


## A vibration it feels at `at` (the region reports the coil's ring and the mirrors through this).
func hear(at: Vector3) -> void:
	if dead or state in [State.PINNED, State.CHARGE, State.BRACE]:
		return
	if state == State.DORMANT:
		wake(at)
		return
	heard_at = at
	if state == State.SEARCH:
		state = State.HUNT


## Caught under a firing cargo magnet: up off its feet with the back plate torn open.
func pin() -> void:
	if dead or state == State.PINNED:
		return
	state = State.PINNED
	_timer = PINNED_TIME
	pins += 1
	velocity = Vector3.ZERO
	Sfx.play("hit_armor", global_position + Vector3.UP * 2.0, 2.0, 0.0)


func pinned() -> bool:
	return state == State.PINNED


## What it feels from her this frame, or Vector3.INF.
func _felt() -> Vector3:
	if not _target_alive():
		return Vector3.INF
	var at: Vector3 = target.global_position
	var d := _flat(at - global_position).length()
	var v: Vector3 = target.velocity if "velocity" in target else Vector3.ZERO
	var flat_speed := Vector2(v.x, v.z).length()
	var crouched: bool = target.get("crouching") == true
	var on_floor: bool = target.is_on_floor() if target.has_method("is_on_floor") else true
	var landed := on_floor and not _was_floor and _fall_speed < -4.0
	_was_floor = on_floor
	_fall_speed = v.y if not on_floor else 0.0
	if state == State.DORMANT:
		return at if flat_speed > LOUD_SPEED and d < WAKE_RUN else Vector3.INF
	if flat_speed > LOUD_SPEED and d < HEAR_RUN:
		return at
	if landed and d < HEAR_LAND:
		return at
	if flat_speed > 0.5 and d < (HEAR_CROUCH if crouched else HEAR_WALK):
		return at
	return Vector3.INF


## The region's weapon hook: a shot fired somewhere in the hall.
func shot_fired(at: Vector3) -> void:
	var d := _flat(at - global_position).length()
	if d < (WAKE_SHOT if state == State.DORMANT else HEAR_SHOT):
		hear(at)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_gravity_step(delta)
	_timer -= delta
	_groan -= delta
	_footfalls(delta)
	# The low scanning rumble while it stands and listens for her.
	if state == State.SEARCH and _search == null:
		_search = Sfx.loop("guardian_search", self, -2.0)
	elif state != State.SEARCH and _search:
		_search.queue_free()
		_search = null
	var felt := _felt()
	if felt != Vector3.INF:
		hear(felt)
	_sense_mat.emission_energy_multiplier = 0.4 if state == State.DORMANT else (5.0 if state == State.BRACE else 1.8)
	match state:
		State.DORMANT:
			velocity.x = 0.0
			velocity.z = 0.0
		State.HUNT:
			_walk_to(heard_at, delta)
			if _target_alive() and _flat(target.global_position - global_position).length() < BRACE_RANGE and _flat(heard_at - target.global_position).length() < 2.5:
				_brace()
			elif _flat(heard_at - global_position).length() < 1.2:
				state = State.SEARCH
				_timer = SEARCH_TIME
		State.SEARCH:
			velocity.x = 0.0
			velocity.z = 0.0
			rotation.y += delta * 1.2
			if _timer <= 0.0:
				# Nothing: it drifts back toward the middle of the hall, still listening.
				heard_at = Vector3(bounds.get_center().x, global_position.y, bounds.get_center().y)
				state = State.HUNT
		State.BRACE:
			velocity.x = 0.0
			velocity.z = 0.0
			if _target_alive():
				_face(target.global_position, clampf(8.0 * delta, 0.0, 1.0))
			_body.position.z = 0.15 * sin(_timer * 40.0)
			if _timer <= 0.0:
				_charge()
		State.CHARGE:
			velocity.x = _charge_dir.x * CHARGE_SPEED
			velocity.z = _charge_dir.z * CHARGE_SPEED
			if not _charge_hit and _target_alive() and global_position.distance_to(target.global_position) < 2.4:
				_charge_hit = true
				hits += 1
				target.take_damage(CHARGE_DAMAGE, global_position)
				Sfx.play("guardian_impact", global_position + Vector3.UP, 0.0, 0.05)
				if "velocity" in target:
					target.velocity += _charge_dir * 8.0 + Vector3.UP * 4.0
				if target.has_method("add_trauma"):
					target.add_trauma(0.5)
			if _timer <= 0.0 or (is_on_wall() and _timer < CHARGE_TIME - 0.1):
				if is_on_wall():
					Sfx.play("guardian_impact", global_position + Vector3.UP, -2.0, 0.1)
				state = State.RECOVER
				_timer = RECOVER_TIME
		State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
			if _timer <= 0.0:
				state = State.HUNT
		State.PINNED:
			velocity = Vector3.ZERO
			_body.position.y = lerpf(_body.position.y, 0.7, clampf(6.0 * delta, 0.0, 1.0))
			_back.position.y = 2.25
			_vent_mat.emission_energy_multiplier = 3.5
			if _timer <= 0.0:
				_body.position.y = 0.0
				_back.position.y = 1.95
				_vent_mat.emission_energy_multiplier = 0.0
				state = State.RECOVER
				_timer = RECOVER_TIME
	if state != State.PINNED:
		_body.position.y = lerpf(_body.position.y, 0.0, clampf(8.0 * delta, 0.0, 1.0))
	move_and_slide()
	_keep_in_hall()


func _walk_to(goal: Vector3, delta: float) -> void:
	if goal == Vector3.INF:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to := _flat(goal - global_position)
	if to.length() < 0.3:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var dir := _steer_around_walls(to.normalized(), delta)
	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	_face(global_position + dir, clampf(5.0 * delta, 0.0, 1.0))


func _brace() -> void:
	state = State.BRACE
	_timer = BRACE_TIME
	Sfx.play("guardian_roar", global_position, 0.0, 0.12)


func _charge() -> void:
	state = State.CHARGE
	_timer = CHARGE_TIME
	_charge_hit = false
	var to := _flat(target.global_position - global_position) if _target_alive() else _forward()
	_charge_dir = to.normalized() if to.length() > 0.1 else _forward()
	_body.position.z = 0.0
	Sfx.play("ram_charge", global_position, 0.0, 0.1)


## Heavy footfalls while it walks or charges: faster with speed, felt across the hall.
func _footfalls(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.5 or not is_on_floor():
		_stride = 0.0
		return
	_stride += delta * speed
	if _stride >= STRIDE:
		_stride = 0.0
		Sfx.play("guardian_step", global_position, -4.0 if state != State.CHARGE else 0.0, 0.06)


func _keep_in_hall() -> void:
	if bounds.size == Vector2.ZERO:
		return
	var p := global_position
	p.x = clampf(p.x, bounds.position.x, bounds.end.x)
	p.z = clampf(p.z, bounds.position.y, bounds.end.y)
	global_position = p


func _damage_scale(_point: Vector3, _dir: Vector3) -> float:
	return 1.0 if state == State.PINNED else PLATE


func _weak_open() -> bool:
	return state == State.PINNED


func _on_hurt(_dir: Vector3) -> void:
	# Only a hit through the open back really hurts it.
	if state == State.PINNED and _groan <= 0.0:
		_groan = 1.2
		Sfx.play("guardian_hurt", global_position + Vector3.UP * 2.0, 0.0, 0.08)
	if state == State.DORMANT and _target_alive():
		wake(target.global_position)


func _die() -> void:
	state = State.DEAD
	remove_from_group("guardians")
	Game.set_flag("patience_guardian_down")
	super._die()
	if is_inside_tree():
		Vfx.burst(get_parent(), global_position + Vector3.UP * 1.5, SENSE, 16, 3.0, 0.08, 0.6, Vector3.UP, 180.0, -3.0)
	var tween := create_tween()
	tween.tween_property(_body, "position:y", -0.6, 1.2)
	tween.tween_property(_body, "rotation:z", 0.25, 0.4)


func anim_state() -> String:
	return String(State.find_key(state)).to_lower()
