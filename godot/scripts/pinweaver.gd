class_name Pinweaver
extends Enemy
## Loom Expanse pinweaver (milestone C3): a slate-black six-legged tension frame that never runs
## at you. It steps sideways to a fibre pillar, plants two legs and anchors (the amber valve at the
## base of its left back-spool opens: the moment to shoot it), then spools a pale trip-thread at
## shin height across to another pillar, across where Juno is heading. Run through a live thread
## and it snags her: a slow walk, no sprint, for a moment. Crouch through it (or wear the survey
## team's weave grips) and it slides off; shoot it and it snaps back across its length. Shoot
## both of a thread's anchor knots, one after the other, and the weaver has to unspool and
## recover, standing open. When a trap fails it moves somewhere new.
##
## Its region gives it pillars to anchor to with `anchors()`; with none it picks points round
## its home.

enum State { IDLE, MOVE, ANCHOR, SPOOL, WATCH, RECOVER, DEAD }

const STEP_SPEED := 3.0
const RELOCATE_SPEED := 5.0
const KEEP_FROM := 9.0
const KEEP_TO := 15.0
const ANCHOR_TIME := 2.0
const SPOOL_TIME := 1.0
const WATCH_TIME := 3.5
const RECOVER_TIME := 5.0
## A thread snags within this of its line, from her feet up to this high.
const SNAG_REACH := 0.5
const SNAG_HEIGHT := 1.0
const SNAG_TIME := 1.4
const SNAP_REACH := 1.8
const SNAP_DAMAGE := 8.0
## Both knots of a thread shot within this long of each other forces a recovery.
const KNOT_WINDOW := 3.0
const MAX_THREADS := 2
const SPAN_MIN := 5.0
const SPAN_MAX := 17.0
const FRAME := Color("26282c")
const THREAD := Color("e8e2d0")
const VALVE := Color("ffa63a")

## A trip-thread between two anchor points (world space), owned by its weaver.
class TripThread:
	extends Node3D
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var grown := 0.0
	var live := false
	var knots_hit := {}
	var weaver: Pinweaver
	var _line: MeshInstance3D
	var _body: StaticBody3D
	var _shape: BoxShape3D
	var _mat: StandardMaterial3D
	var _knots: Array[StaticBody3D] = []

	func _ready() -> void:
		top_level = true
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = THREAD
		_mat.emission_enabled = true
		_mat.emission = THREAD
		_mat.emission_energy_multiplier = 0.7
		_line = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 1.0)
		_line.mesh = bm
		_line.material_override = _mat
		add_child(_line)
		_body = StaticBody3D.new()
		_body.collision_layer = Game.LAYER_SHOT
		_body.collision_mask = 0
		var cs := CollisionShape3D.new()
		_shape = BoxShape3D.new()
		_shape.size = Vector3(0.25, 0.25, 1.0)
		cs.shape = _shape
		_body.add_child(cs)
		_body.set_meta("on_hit", _on_line_hit)
		add_child(_body)
		var km := StandardMaterial3D.new()
		km.albedo_color = VALVE.darkened(0.3)
		km.emission_enabled = true
		km.emission = VALVE
		km.emission_energy_multiplier = 1.4
		for i in 2:
			var k := StaticBody3D.new()
			k.collision_layer = Game.LAYER_SHOT
			k.collision_mask = 0
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.16
			sm.height = 0.32
			sm.radial_segments = 8
			sm.rings = 4
			mi.mesh = sm
			mi.material_override = km
			k.add_child(mi)
			var kc := CollisionShape3D.new()
			var ks := SphereShape3D.new()
			ks.radius = 0.28
			kc.shape = ks
			k.add_child(kc)
			k.set_meta("on_hit", _on_knot_hit.bind(k, i))
			add_child(k)
			_knots.append(k)
		layout()

	func _on_line_hit() -> void:
		if weaver and is_instance_valid(weaver):
			weaver.cut(self, true)

	func _on_knot_hit(knot: Node, which: int) -> void:
		if weaver and is_instance_valid(weaver):
			weaver.knot_hit(knot, which)

	## Places the line, its collider and the knots for how far it has grown.
	func layout() -> void:
		var end := a.lerp(b, clampf(grown, 0.02, 1.0))
		var length := a.distance_to(end)
		var mid := (a + end) * 0.5
		var basis := Basis.looking_at(end - a, Vector3.UP) if length > 0.01 else Basis()
		global_transform = Transform3D(Basis(), Vector3.ZERO)
		_line.global_transform = Transform3D(Basis(basis.x, basis.y, basis.z * length), mid)
		_body.global_transform = Transform3D(basis, mid)
		_shape.size = Vector3(0.25, 0.25, maxf(length, 0.05))
		_knots[0].global_position = a
		_knots[1].global_position = end
		_knots[1].visible = grown >= 1.0
		_mat.emission_energy_multiplier = 1.4 if live else 0.5

	## Distance from a point to the line, flat, and the point's height over it.
	func reach(p: Vector3) -> Vector2:
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(p.x - a.x, p.z - a.z)
		var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var closest := a.lerp(b, t)
		return Vector2(Vector2(p.x - closest.x, p.z - closest.z).length(), p.y - (closest.y - 0.45))


var state := State.IDLE
var threads: Array[TripThread] = []
## Traps that caught her, failed (crouched through, cut) and recoveries forced (tests read these).
var snags := 0
var fails := 0
var recoveries := 0
## A chord singer's call speeds its anchoring until this runs out.
var called := 0.0
var _timer := 0.0
var _goal := Vector3.INF
var _pair: Array = []
var _pending: TripThread
var _gait := 0.0
var _visual: Node3D
var _legs: Array[Node3D] = []
var _valve_mat: StandardMaterial3D
var _was_near := {}
var _click_t := 0.0


func _init() -> void:
	max_health = 70.0
	speed = STEP_SPEED
	sight_range = 22.0
	alert_radius = 10.0
	drops = Vector2i(1, 3)
	death_puff = 0.9
	weak_radius = 0.35


func _setup() -> void:
	add_to_group("pinweavers")
	var shape := CollisionShape3D.new()
	var s := CapsuleShape3D.new()
	s.radius = 0.6
	s.height = 1.8
	shape.shape = s
	shape.position = Vector3(0.0, 1.1, 0.0)
	add_child(shape)
	_build()
	_timer = randf_range(0.2, 1.0)
	_click_t = randf_range(0.0, 2.0)


func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = FRAME
	frame.roughness = 0.5
	frame.metallic = 0.3
	_flashes(frame)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.6
	sm.radial_segments = 10
	sm.rings = 5
	body.mesh = sm
	body.material_override = frame
	body.position = Vector3(0.0, 1.5, 0.0)
	body.scale = Vector3(1.0, 0.8, 1.5)
	_visual.add_child(body)
	# Back-spools, asymmetric: the left one bigger, with the valve at its base.
	for side in [-1.0, 1.0]:
		var spool := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2 if side < 0.0 else 0.14
		cm.bottom_radius = cm.top_radius
		cm.height = 0.5 if side < 0.0 else 0.36
		cm.radial_segments = 8
		spool.mesh = cm
		spool.material_override = frame
		spool.position = Vector3(side * 0.28, 1.95, 0.35)
		spool.rotation.z = PI * 0.5
		_visual.add_child(spool)
	_valve_mat = StandardMaterial3D.new()
	_valve_mat.albedo_color = VALVE.darkened(0.5)
	_valve_mat.emission_enabled = true
	_valve_mat.emission = VALVE
	_valve_mat.emission_energy_multiplier = 0.2
	var valve := MeshInstance3D.new()
	var vm := SphereMesh.new()
	vm.radius = 0.14
	vm.height = 0.28
	vm.radial_segments = 8
	vm.rings = 4
	valve.mesh = vm
	valve.material_override = _valve_mat
	valve.position = Vector3(-0.3, 1.74, 0.5)
	_visual.add_child(valve)
	_weak = valve
	# Six caliper legs: one long thin strut each, from the hip down and out to the foot.
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.07, 1.0, 0.07)
	for i in 6:
		var pivot := Node3D.new()
		var side := -1.0 if i < 3 else 1.0
		pivot.position = Vector3(side * 0.35, 1.5, (i % 3 - 1) * 0.45)
		_visual.add_child(pivot)
		var leg := MeshInstance3D.new()
		leg.mesh = leg_mesh
		leg.material_override = frame
		pivot.add_child(leg)
		_legs.append(pivot)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_timer -= delta
	called = maxf(called - delta, 0.0)
	_gravity_step(delta)
	var want := Vector3.ZERO
	var pace := 0.0
	match state:
		State.IDLE:
			if _timer <= 0.0:
				_timer = 0.3
				if _target_alive() and _can_see_target():
					alert(true)
				if hunting:
					_plan()
		State.MOVE:
			var to := _flat(_goal - global_position)
			if to.length() < 0.5 or _timer <= 0.0:
				_start_anchor()
			else:
				want = to.normalized()
				pace = RELOCATE_SPEED if fails > 0 and _timer > 4.0 else STEP_SPEED
		State.ANCHOR:
			if _timer <= 0.0:
				_start_spool()
		State.SPOOL:
			if _pending and is_instance_valid(_pending):
				_pending.grown = clampf(1.0 - _timer / SPOOL_TIME, 0.0, 1.0)
				_pending.layout()
			if _timer <= 0.0:
				if _pending and is_instance_valid(_pending):
					_pending.grown = 1.0
					_pending.live = true
					_pending.layout()
				_pending = null
				state = State.WATCH
				_timer = WATCH_TIME
		State.WATCH:
			# Keeps its distance, sidestepping; then strings another line.
			if _target_alive():
				var off := _flat(global_position - target.global_position)
				var d := off.length()
				if d < KEEP_FROM:
					want = off.normalized()
				elif d > KEEP_TO + 6.0:
					want = -off.normalized()
				else:
					want = off.normalized().cross(Vector3.UP) * (1.0 if int(Time.get_ticks_msec() / 2500) % 2 == 0 else -1.0) * 0.5
				pace = STEP_SPEED
			if _timer <= 0.0:
				if hunting:
					_plan()
				else:
					state = State.IDLE
		State.RECOVER:
			if _timer <= 0.0:
				state = State.IDLE
				_timer = 0.2
	if want != Vector3.ZERO:
		var dir := _steer_around_walls(want, delta)
		velocity.x = dir.x * pace
		velocity.z = dir.z * pace
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	move_and_slide()
	if _target_alive() and state != State.MOVE:
		_face(target.global_position, clampf(5.0 * delta, 0.0, 1.0))
	elif want != Vector3.ZERO:
		_face(global_position + want, clampf(6.0 * delta, 0.0, 1.0))
	_check_threads()
	_animate(delta)
	_click_t -= delta
	if _click_t <= 0.0:
		_click_t = 0.35 if state == State.ANCHOR or state == State.SPOOL else 2.8
		Sfx.play("pinweaver_click", global_position + Vector3.UP * 1.5, -6.0 if state == State.ANCHOR else -12.0, 0.2)


## Picks two pillars to string a line between, across where Juno is (or is heading), and
## steps over to the nearer one.
func _plan() -> void:
	var pts := _anchor_points()
	var best: Array = []
	var best_score := INF
	var her: Vector3 = target.global_position if _target_alive() else home
	var heading: Vector3 = _flat(target.velocity) if _target_alive() and "velocity" in target else Vector3.ZERO
	var ahead := her + heading.normalized() * 4.0 if heading.length() > 0.5 else her
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var span := _flat(pts[j] - pts[i]).length()
			if span < SPAN_MIN or span > SPAN_MAX:
				continue
			var mid: Vector3 = (pts[i] + pts[j]) * 0.5
			var d := _flat(mid - ahead).length()
			# Not right on top of her: she'd have to see it go up.
			if _flat(mid - her).length() < 3.0 or _taken(pts[i], pts[j]):
				continue
			var score := d + randf() * 2.0
			if score < best_score:
				best_score = score
				best = [pts[i], pts[j]]
	if best.is_empty():
		state = State.WATCH
		_timer = WATCH_TIME
		return
	# Anchor at the end further from her, standing off the pillar on the far side.
	if _flat(best[0] - her).length() < _flat(best[1] - her).length():
		best = [best[1], best[0]]
	_pair = best
	var away := _flat(best[0] - her).normalized()
	_goal = best[0] + away * 1.4
	_goal.y = global_position.y
	state = State.MOVE
	_timer = 8.0


func _taken(a: Vector3, b: Vector3) -> bool:
	for t in threads:
		if is_instance_valid(t) and ((t.a.is_equal_approx(a) and t.b.is_equal_approx(b)) or (t.a.is_equal_approx(b) and t.b.is_equal_approx(a))):
			return true
	return false


func _anchor_points() -> Array[Vector3]:
	var region := get_parent()
	if region and region.has_method("anchors"):
		var all: Array[Vector3] = region.anchors()
		return all.filter(func(p): return _flat(p - home).length() < 26.0)
	var out: Array[Vector3] = []
	for i in 6:
		var a := i * TAU / 6.0
		out.append(home + Vector3(cos(a) * 7.0, 0.45, sin(a) * 7.0))
	return out


func _start_anchor() -> void:
	state = State.ANCHOR
	_timer = ANCHOR_TIME * (0.5 if called > 0.0 else 1.0)
	Sfx.play("pinweaver_click", global_position + Vector3.UP * 1.5, -2.0, 0.0)


func _start_spool() -> void:
	if _pair.is_empty():
		state = State.WATCH
		_timer = WATCH_TIME
		return
	while threads.size() >= MAX_THREADS:
		_drop(threads[0])
	var t := TripThread.new()
	t.a = _pair[0]
	t.b = _pair[1]
	t.weaver = self
	add_child(t)
	threads.append(t)
	_pending = t
	state = State.SPOOL
	_timer = SPOOL_TIME
	Sfx.play("thread_spool", global_position + Vector3.UP * 1.5, -4.0, 0.1)


func _drop(t: TripThread) -> void:
	threads.erase(t)
	_was_near.erase(t)
	if _pending == t:
		_pending = null
	if is_instance_valid(t):
		t.queue_free()


## Shot through (or tripped): the thread snaps back along its length, lashing anyone close.
func cut(t: TripThread, lash: bool) -> void:
	if not t in threads:
		return
	_drop(t)
	Sfx.play("thread_snap", (t.a + t.b) * 0.5, 0.0, 0.1)
	if is_inside_tree():
		Vfx.burst(get_parent(), (t.a + t.b) * 0.5, THREAD, 10, 3.0, 0.05, 0.4, Vector3.UP, 90.0, -2.0)
	if lash and _target_alive() and t.reach(target.global_position).x < SNAP_REACH:
		target.take_damage(SNAP_DAMAGE, (t.a + t.b) * 0.5)
	_failed()


## One of a thread's anchor knots shot: the second within KNOT_WINDOW forces a recovery.
func knot_hit(knot: Node, which: int) -> void:
	var t := knot.get_parent() as TripThread
	if t == null or not t in threads:
		return
	var now := Time.get_ticks_msec() / 1000.0
	t.knots_hit[which] = now
	Sfx.play("hit_tick", knot.global_position, -4.0, 0.0)
	if t.knots_hit.size() == 2 and absf(float(t.knots_hit[0]) - float(t.knots_hit[1])) <= KNOT_WINDOW:
		_drop(t)
		recoveries += 1
		state = State.RECOVER
		_timer = RECOVER_TIME
		velocity = Vector3.ZERO
		Sfx.play("thread_snap", global_position + Vector3.UP * 1.5, 0.0, 0.0)


## A trap that didn't work: it goes somewhere new.
func _failed() -> void:
	fails += 1
	if state == State.DEAD or state == State.RECOVER:
		return
	if hunting:
		_plan()
		_timer = 10.0


## Juno crossing a live thread: snagged, unless she's crouching or in weave grips.
func _check_threads() -> void:
	if not _target_alive():
		return
	var at: Vector3 = target.global_position
	for t in threads.duplicate():
		if not is_instance_valid(t) or not t.live:
			continue
		var r: Vector2 = t.reach(at)
		var near: bool = r.x < SNAG_REACH and r.y > -0.6 and r.y < SNAG_HEIGHT
		if near and not _was_near.get(t, false):
			var slides: bool = ("crouching" in target and target.crouching) or Game.flags.get("weave_grips", false)
			if slides:
				Sfx.play("thread_spool", at, -8.0, 0.2)
				_drop(t)
				_failed()
			else:
				snags += 1
				if target.has_method("snag"):
					target.snag(SNAG_TIME)
				Sfx.play("thread_snap", at, -2.0, 0.1)
				_drop(t)
				alert(true)
		_was_near[t] = near


func _damage_scale(_point: Vector3, _dir: Vector3) -> float:
	# The tension frame shrugs off most of a hit; the valve doesn't.
	return 1.0 if _weak_open() else 0.6


func _weak_open() -> bool:
	return state in [State.ANCHOR, State.SPOOL, State.RECOVER]


func _on_hurt(_dir_hit: Vector3) -> void:
	Sfx.play("scuttler_hurt", global_position, -6.0, 0.4)
	if state == State.IDLE:
		alert(true)


func _on_calm() -> void:
	if state != State.DEAD:
		state = State.IDLE


func _animate(delta: float) -> void:
	var moving := _flat(velocity).length() > 0.2
	_gait += delta * (9.0 if moving else 0.0)
	var planted := state in [State.ANCHOR, State.SPOOL, State.RECOVER]
	_valve_mat.emission_energy_multiplier = lerpf(_valve_mat.emission_energy_multiplier, 3.5 if _weak_open() else 0.2, clampf(8.0 * delta, 0.0, 1.0))
	for i in _legs.size():
		var side := -1.0 if i < 3 else 1.0
		var row := float(i % 3 - 1)
		var lift := maxf(sin(_gait + (i % 2) * PI), 0.0) * 0.35 if moving else 0.0
		var spread := 1.9 if planted else 1.5
		var foot := Vector3(side * spread, -1.5 + lift, row * 0.9)
		var hip := Vector3.ZERO
		var mid := (hip + foot) * 0.5 + Vector3(side * 0.2, 0.55, 0.0)
		# A caliper: one strut up to the knee, shown as the line hip-to-foot bowed out.
		var leg := _legs[i].get_child(0) as Node3D
		var dir := foot - hip
		leg.position = mid * 0.9
		leg.basis = Basis(Quaternion(Vector3.UP, dir.normalized())).scaled(Vector3(1.0, dir.length() * 1.05, 1.0))


func _die() -> void:
	state = State.DEAD
	for t in threads.duplicate():
		_drop(t)
	remove_from_group("pinweavers")
	super._die()
	if is_inside_tree():
		Vfx.burst(get_parent(), global_position + Vector3.UP * 1.4, VALVE, 12, 2.5, 0.08, 0.6, Vector3.UP, 180.0, -3.0)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3(1.4, 0.05, 1.4), 0.5)
	tween.tween_callback(queue_free)


func anim_state() -> String:
	return String(State.find_key(state)).to_lower()
