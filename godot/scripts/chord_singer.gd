class_name ChordSinger
extends Enemy
## Loom Expanse chord singer (milestone C4): a tall tripod, mostly empty space, with a hollow
## fluted chest, a translucent bell for a throat and rib fins forked over its head. It walks,
## slow and ceremonial, between resonant patches; at each it plants its feet, draws breath (the
## pale teal membrane inside the bell shows: the weak spot) and sings. It doesn't bite or spit.
## Its songs, in a fixed order:
##   dissonance  a wide ring rolls out along the ground; caught in the open, Juno's reloads drag
##               for a few seconds (Weapon.detune);
##   pull        rings close in on it and a low tone tugs her a little toward it;
##   call        a pale flare from its fork: pinweavers nearby anchor twice as fast for a while.
## Rock between it and her breaks the song. A shot through the membrane while it inhales stops
## the song; it staggers and retreats to another patch.
## Each song has its own ring shape and sound, not just its own colour.

enum State { WALK, PLANT, INHALE, SING, STAGGER, REST, DEAD }
enum Song { DISSONANCE, PULL, CALL }

const SONGS := [Song.DISSONANCE, Song.PULL, Song.DISSONANCE, Song.CALL]
const WALK_SPEED := 1.3
const PLANT_TIME := 0.8
const INHALE_TIME := 1.6
const STAGGER_TIME := 1.4
const REST_TIME := 2.5
const RING_SPEED := 8.0
const RING_RANGE := 26.0
const PULL_RANGE := 18.0
const PULL_TIME := 1.4
const PULL_SPEED := 2.4
const DETUNE_TIME := 3.5
const CALL_RANGE := 30.0
const CALL_TIME := 6.0
const HEIGHT := 3.5
const SKIN := Color("8a7aa8")
const BELL := Color("c8d8ff")
const MEMBRANE := Color("9ff0e0")
const DISSONANCE := Color("f07ac8")
const PULL := Color("8fb8ff")

var state := State.WALK
## Songs sung, songs cut short, and who was caught (tests read these).
var sung := 0
var interrupted := 0
var detuned_her := 0
var pulled_her := 0
var song_index := 0
var _timer := 0.0
var _patch := 0
var _goal := Vector3.INF
var _ring_r := -1.0
var _ring_song := Song.DISSONANCE
var _ring_hit := false
var _pull_t := 0.0
var _drone_t := 0.0
var _visual: Node3D
var _membrane_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _flare: OmniLight3D


func _init() -> void:
	max_health = 140.0
	speed = WALK_SPEED
	sight_range = 26.0
	alert_radius = 0.0
	drops = Vector2i(2, 4)
	death_puff = 1.4
	weak_joint = "Membrane"
	weak_radius = 0.45


func _setup() -> void:
	add_to_group("chord_singers")
	var shape := CollisionShape3D.new()
	var s := CapsuleShape3D.new()
	s.radius = 0.7
	s.height = HEIGHT
	shape.shape = s
	shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(shape)
	_build()
	_timer = randf_range(0.5, 2.0)
	_drone_t = randf_range(0.0, 3.0)


func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_load_rig("chord_singer", _visual)
	# The membrane inside the bell: the weak spot, bright while it draws breath.
	_membrane_mat = Rig.own_material(_rig, "singer_membrane")
	# The song's ring on the ground: a wide jagged band for dissonance, a thin double one for
	# the pull (drawn closing in).
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.emission_enabled = true
	_ring_mat.emission_energy_multiplier = 2.5
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 4
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_ring.top_level = true
	_ring.visible = false
	add_child(_ring)
	_flare = OmniLight3D.new()
	_flare.light_color = MEMBRANE
	_flare.light_energy = 0.0
	_flare.omni_range = 8.0
	_flare.position = Vector3(0.0, 4.6, 0.0)
	add_child(_flare)


func _patches() -> Array[Vector3]:
	var region := get_parent()
	if region and region.has_method("patches"):
		return region.patches()
	var out: Array[Vector3] = [home, home + Vector3(8.0, 0.0, 0.0), home + Vector3(0.0, 0.0, 8.0)]
	return out


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_timer -= delta
	_gravity_step(delta)
	var want := Vector3.ZERO
	match state:
		State.WALK:
			if _goal == Vector3.INF:
				_next_patch(false)
			var to := _flat(_goal - global_position)
			if to.length() < 0.6 or _timer < -20.0:
				state = State.PLANT
				_timer = PLANT_TIME
				Sfx.play("ram_paw", global_position, -6.0, 0.2)
			else:
				want = to.normalized()
		State.PLANT:
			if _timer <= 0.0:
				if _target_alive() and _flat(target.global_position - global_position).length() < sight_range:
					state = State.INHALE
					_timer = INHALE_TIME
					Sfx.play("singer_inhale", global_position + Vector3.UP * 3.0, 0.0, 0.0)
				else:
					state = State.REST
					_timer = REST_TIME
		State.INHALE:
			if _membrane_mat:
				_membrane_mat.emission_energy_multiplier = lerpf(0.6, 4.0, clampf(1.0 - _timer / INHALE_TIME, 0.0, 1.0))
			if _target_alive():
				_face(target.global_position, clampf(3.0 * delta, 0.0, 1.0))
			if _timer <= 0.0:
				_sing()
		State.SING:
			if _ring_r < 0.0 and _pull_t <= 0.0 and _timer <= 0.0:
				state = State.REST
				_timer = REST_TIME
		State.STAGGER:
			_visual.rotation.z = sin(_timer * 20.0) * 0.08
			if _timer <= 0.0:
				_visual.rotation.z = 0.0
				_next_patch(true)
				state = State.WALK
		State.REST:
			if _timer <= 0.0:
				_next_patch(false)
				state = State.WALK
	if state != State.INHALE:
		if _membrane_mat:
			_membrane_mat.emission_energy_multiplier = lerpf(_membrane_mat.emission_energy_multiplier, 0.3, clampf(5.0 * delta, 0.0, 1.0))
	if want != Vector3.ZERO:
		var dir := _steer_around_walls(want, delta)
		velocity.x = dir.x * WALK_SPEED
		velocity.z = dir.z * WALK_SPEED
		_face(global_position + dir, clampf(3.0 * delta, 0.0, 1.0))
	else:
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
	move_and_slide()
	_tick_ring(delta)
	_tick_pull(delta)
	_flare.light_energy = maxf(_flare.light_energy - delta * 3.0, 0.0)
	_drone_t -= delta
	if _drone_t <= 0.0:
		_drone_t = 4.0
		Sfx.play("singer_drone", global_position + Vector3.UP * 3.0, -10.0, 0.1)


## Off to the next patch along (or, retreating, the one furthest from Juno).
func _next_patch(retreat: bool) -> void:
	var pts := _patches()
	if pts.is_empty():
		_goal = home
		return
	if retreat and _target_alive():
		var far := -1.0
		for i in pts.size():
			var d := _flat(pts[i] - target.global_position).length()
			if i != _patch and d > far:
				far = d
				_patch = i
	else:
		_patch = (_patch + 1) % pts.size()
	_goal = pts[_patch]
	_timer = 0.0


func _sing() -> void:
	state = State.SING
	_timer = 0.6
	sung += 1
	var song: int = SONGS[song_index % SONGS.size()]
	song_index += 1
	match song:
		Song.DISSONANCE:
			_ring_song = Song.DISSONANCE
			_ring_r = 1.0
			_ring_hit = false
			_ring_mat.albedo_color = Color(DISSONANCE, 0.8)
			_ring_mat.emission = DISSONANCE
			(_ring.mesh as TorusMesh).inner_radius = 0.82
			Sfx.play("singer_chord", global_position + Vector3.UP * 3.0, 2.0, 0.0)
		Song.PULL:
			_ring_song = Song.PULL
			_ring_r = PULL_RANGE
			_ring_hit = false
			_ring_mat.albedo_color = Color(PULL, 0.7)
			_ring_mat.emission = PULL
			(_ring.mesh as TorusMesh).inner_radius = 0.96
			_pull_t = PULL_TIME
			Sfx.play("singer_pull", global_position + Vector3.UP * 3.0, 0.0, 0.0)
		Song.CALL:
			_flare.light_energy = 6.0
			Sfx.play("singer_call", global_position + Vector3.UP * 4.0, 0.0, 0.0)
			for p in get_tree().get_nodes_in_group("pinweavers"):
				if p.global_position.distance_to(global_position) < CALL_RANGE:
					p.called = CALL_TIME


## True when rock stands between its throat and Juno.
func sheltered() -> bool:
	if not _target_alive() or not is_inside_tree():
		return true
	var from := global_position + Vector3.UP * 3.55
	var to: Vector3 = target.global_position + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.LAYER_WORLD)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The dissonance rolls out (the pull's rings close in); either catches her once as it passes.
func _tick_ring(delta: float) -> void:
	if _ring_r < 0.0:
		_ring.visible = false
		return
	if _ring_song == Song.DISSONANCE:
		_ring_r += RING_SPEED * delta
		if _ring_r > RING_RANGE:
			_ring_r = -1.0
			return
	else:
		_ring_r -= RING_SPEED * 1.2 * delta
		if _ring_r < 1.0:
			_ring_r = -1.0
			return
	_ring.visible = true
	_ring.global_position = Vector3(global_position.x, global_position.y + 0.15, global_position.z)
	_ring.scale = Vector3(_ring_r, 3.0, _ring_r)
	if _ring_song != Song.DISSONANCE or _ring_hit or not _target_alive():
		return
	var d := _flat(target.global_position - global_position).length()
	if absf(d - _ring_r) < 0.9 and target.global_position.y - global_position.y < 2.0:
		_ring_hit = true
		if not sheltered():
			detuned_her += 1
			var w = target.get("weapon")
			if w and w.has_method("detune"):
				w.detune(DETUNE_TIME)
			if target.has_method("add_trauma"):
				target.add_trauma(0.2)
			Sfx.play("singer_chord", target.global_position, -6.0, 0.3)


## The pull: a gentle tug toward it while the tone lasts, unless she's behind rock.
func _tick_pull(delta: float) -> void:
	if _pull_t <= 0.0:
		return
	_pull_t -= delta
	if not _target_alive() or not "velocity" in target:
		return
	var off := _flat(global_position - target.global_position)
	if off.length() > PULL_RANGE or off.length() < 2.5 or sheltered():
		return
	if _pull_t + delta >= PULL_TIME:
		pulled_her += 1
	target.velocity += off.normalized() * PULL_SPEED * 6.0 * delta


func _damage_scale(_point: Vector3, _dir: Vector3) -> float:
	# Mostly air: shots through the frame do little.
	return 0.5


func _weak_open() -> bool:
	return state == State.INHALE


func _on_hurt(_dir_hit: Vector3) -> void:
	Sfx.play("skimmer_hurt", global_position + Vector3.UP * 3.0, -4.0, 0.3)
	if state == State.INHALE and last_hit_crit:
		interrupted += 1
		state = State.STAGGER
		_timer = STAGGER_TIME
		Sfx.play("singer_chord", global_position + Vector3.UP * 3.0, -8.0, 0.6)


func _die() -> void:
	state = State.DEAD
	_ring.visible = false
	remove_from_group("chord_singers")
	super._die()
	if is_inside_tree():
		Vfx.burst(get_parent(), global_position + Vector3.UP * 3.0, MEMBRANE, 16, 3.0, 0.08, 0.8, Vector3.UP, 180.0, -3.0)
	# The die clip topples it; it lies a moment, then sinks into the weave.
	if _membrane_mat:
		_membrane_mat.emission_energy_multiplier = 0.0
	var tween := create_tween()
	tween.tween_interval(2.6)
	tween.tween_property(_visual, "position:y", -1.4, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func anim_state() -> String:
	return String(State.find_key(state)).to_lower()
