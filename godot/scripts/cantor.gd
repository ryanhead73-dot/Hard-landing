class_name Cantor
extends Enemy
## The Cantor (production pack, 03_LOOM_CREATURES): the Tuning Crown's keeper, a hollow rib cage
## of braided cable slung over the arena from four anchors at its rim. It never chases. It sings a
## three-note phrase, high, middle, low, and then holds a quiet gap before it sings again; on the
## low note it plucks the arena, and a pressure wave rolls out across the floor (jump it).
##
## Its teal heart-node hangs in the middle of the cage behind three woven petals that turn every
## shot. Break an anchor in the quiet just after the low note (an anchor hit any other time only
## rings) and the cycle is interrupted: the petals fall open and the heart can be hurt for a few
## seconds. Three phases, each a third of its health, and the arena changes with each:
##   LISTEN   the phrase and the wave; break an anchor in the gap.
##   RESPOND  the same, and two shear walls slide across the arena on the middle note (their seam
##            glows on the high note first).
##   RESOLVE  a chord singer joins (Chorus); no more anchors: one petal unfurls in each quiet gap,
##            and with all three open the heart is bare in every gap after that.
## The region (TuningCrown) owns the anchors and the walls and tells it when an anchor breaks;
## dying in the fight puts the phase back to its start, never further.

signal phase_changed(phase: int)
signal note(which: int)

enum Phase { LISTEN, RESPOND, RESOLVE }

## The phrase: notes at these times into the cycle, then the quiet gap until CYCLE.
const NOTES := [0.0, 0.8, 1.6]
const CYCLE := 4.6
## The window after the low note in which an anchor hit interrupts the cycle.
const GAP_FROM := 1.7
const GAP_TO := 3.6
const OPEN_TIME := 6.0
const HEART_Y := 7.0
const WAVE_DAMAGE := 15.0
const TEAL := Color("3fe0c8")
const CABLE := Color("6a4a3a")

var phase := Phase.LISTEN
var cycle_t := 0.0
## Seconds the heart stays open after an interrupt.
var open_t := 0.0
## Petals unfurled in RESOLVE (0..3).
var petals := 0
var interrupts := 0
var waves := 0
var _sung := [false, false, false]
var _petal_done := false
var _heart: MeshInstance3D
var _heart_mat: StandardMaterial3D
var _petals: Array[Node3D] = []
var _cage: Node3D
var _drone: Node


func _init() -> void:
	max_health = 900.0
	speed = 0.0
	sight_range = 80.0
	alert_radius = 0.0
	leash_range = 999.0
	drops = Vector2i(0, 0)
	death_puff = 3.0
	weak_radius = 1.6


func display_name() -> String:
	return "THE CANTOR"


func _setup() -> void:
	add_to_group("bosses")
	add_to_group("cantors")
	collision_mask = 0
	_drone = Sfx.loop("cantor_drone", self, -4.0)
	if _drone is AudioStreamPlayer3D:
		(_drone as AudioStreamPlayer3D).max_distance = 90.0
		(_drone as AudioStreamPlayer3D).unit_size = 18.0
	Sfx.play("cantor_windup", global_position + Vector3.UP * HEART_Y, 0.0, 0.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.6
	shape.shape = sphere
	shape.position = Vector3(0.0, HEART_Y, 0.0)
	add_child(shape)
	_build()


func _build() -> void:
	_cage = Node3D.new()
	add_child(_cage)
	var cable := StandardMaterial3D.new()
	cable.albedo_color = CABLE
	cable.roughness = 0.8
	_flashes(cable)
	# The rib cage: hooped ribs round the heart, top to bottom.
	for i in 8:
		var a := i * TAU / 8.0
		var rib := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 3.6
		tm.outer_radius = 4.0
		tm.rings = 16
		tm.ring_segments = 5
		rib.mesh = tm
		rib.material_override = cable
		rib.position = Vector3(0.0, HEART_Y, 0.0)
		rib.rotation = Vector3(PI * 0.5, a, 0.0)
		rib.scale = Vector3(1.0, 1.0, 1.4)
		_cage.add_child(rib)
	_heart_mat = StandardMaterial3D.new()
	_heart_mat.albedo_color = TEAL.darkened(0.5)
	_heart_mat.emission_enabled = true
	_heart_mat.emission = TEAL
	_heart_mat.emission_energy_multiplier = 1.0
	_heart = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.1
	sm.height = 2.2
	sm.radial_segments = 14
	sm.rings = 8
	_heart.mesh = sm
	_heart.material_override = _heart_mat
	_heart.position = Vector3(0.0, HEART_Y, 0.0)
	add_child(_heart)
	_weak = _heart
	var petal_mat := StandardMaterial3D.new()
	petal_mat.albedo_color = Color("8a6a5a")
	petal_mat.roughness = 0.7
	for i in 3:
		var hinge := Node3D.new()
		hinge.position = Vector3(0.0, HEART_Y, 0.0)
		hinge.rotation.y = i * TAU / 3.0
		add_child(hinge)
		var petal := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 1.6
		pm.height = 3.2
		pm.radial_segments = 10
		pm.rings = 6
		petal.mesh = pm
		petal.material_override = petal_mat
		petal.scale = Vector3(0.9, 1.1, 0.35)
		petal.position = Vector3(0.0, 0.0, -0.9)
		hinge.add_child(petal)
		_petals.append(hinge)


## The heart can be hurt now.
func heart_open() -> bool:
	if dead:
		return false
	if phase == Phase.RESOLVE:
		return petals >= 3 and in_gap()
	return open_t > 0.0


## In the quiet just after the low note.
func in_gap() -> bool:
	return cycle_t >= GAP_FROM and cycle_t < GAP_TO


## The health this phase starts at (its checkpoint).
func phase_health(p: int) -> float:
	return max_health * (1.0 - p / 3.0)


## An anchor was struck. In the gap after the low note it breaks and the cycle is interrupted;
## any other time it only rings. Returns whether it broke.
func anchor_struck() -> bool:
	if dead or phase == Phase.RESOLVE or not in_gap() or open_t > 0.0:
		return false
	interrupts += 1
	open_t = OPEN_TIME
	Sfx.play("cantor_heart", global_position + Vector3.UP * HEART_Y, 0.0, 0.0)
	return true


## Back to the start of phase `p` (Juno went down, or a load mid-fight).
func reset_to(p: int) -> void:
	phase = p as Phase
	health = phase_health(p)
	open_t = 0.0
	petals = 0
	cycle_t = 0.0
	_sung = [false, false, false]
	_petal_done = false


func _physics_process(delta: float) -> void:
	if dead:
		return
	cycle_t += delta
	if cycle_t >= CYCLE:
		cycle_t -= CYCLE
		_sung = [false, false, false]
		_petal_done = false
	for i in 3:
		if not _sung[i] and cycle_t >= NOTES[i]:
			_sung[i] = true
			_sing(i)
	if phase == Phase.RESOLVE and in_gap() and not _petal_done:
		_petal_done = true
		petals = mini(petals + 1, 3)
		Sfx.play("thread_snap", global_position + Vector3.UP * HEART_Y, 0.0, 0.0)
	open_t = maxf(open_t - delta, 0.0)
	var opening := 1.0 if heart_open() or (phase == Phase.RESOLVE and petals > 0) else 0.0
	for i in _petals.size():
		var want := 1.2 if (heart_open() or (phase == Phase.RESOLVE and i < petals)) else 0.0
		_petals[i].rotation.x = lerpf(_petals[i].rotation.x, want, clampf(6.0 * delta, 0.0, 1.0))
	_heart_mat.emission_energy_multiplier = 4.0 if heart_open() else 1.0 + opening
	# It sways on its cables.
	_cage.rotation.y += delta * 0.1
	position.y = sin(Time.get_ticks_msec() * 0.0008) * 0.3


func _sing(i: int) -> void:
	note.emit(i)
	Sfx.play(["cantor_high", "cantor_mid", "cantor_low"][i], global_position + Vector3.UP * HEART_Y, 0.0, 0.0)
	if i == 2:
		_wave()


## The plucked chord: a pressure wave rolling out over the floor from under it.
func _wave() -> void:
	waves += 1
	Sfx.play("cantor_wave", global_position, 0.0, 0.0)
	var ring := LoomPulse.new()
	ring.one_shot = true
	ring.speed = 9.0
	ring.max_radius = 30.0
	ring.damage = WAVE_DAMAGE
	ring.knockback = 6.0
	ring.target = target
	get_parent().add_child(ring)
	ring.global_position = Vector3(global_position.x, get_parent().global_position.y, global_position.z)
	ring.fire()


func _damage_scale(_point: Vector3, _dir: Vector3) -> float:
	return 1.0 if heart_open() else 0.0


func _weak_open() -> bool:
	return heart_open()


func take_damage(amount: float, point: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO) -> bool:
	if not heart_open():
		# The petals turn it.
		if dir != Vector3.ZERO:
			_armor_effect(point, dir)
		return false
	var killed := super(amount, point, dir)
	if not killed:
		var next := Phase.RESOLVE if health <= phase_health(2) else (Phase.RESPOND if health <= phase_health(1) else phase)
		if next != phase:
			phase = next
			Sfx.play("cantor_windup", global_position + Vector3.UP * HEART_Y, 0.0, 0.0)
			open_t = 0.0
			petals = 0
			phase_changed.emit(phase)
	return killed


func _die() -> void:
	remove_from_group("cantors")
	if _drone and is_instance_valid(_drone):
		create_tween().tween_property(_drone, "volume_db", -40.0, 2.0)
	super._die()
	if is_inside_tree():
		Vfx.burst(get_parent(), global_position + Vector3.UP * HEART_Y, TEAL, 30, 6.0, 0.1, 1.0, Vector3.UP, 180.0, -4.0)
	var tween := create_tween()
	tween.tween_property(_cage, "scale", Vector3(1.0, 0.2, 1.0), 2.0)
	tween.parallel().tween_property(_heart, "position:y", 1.0, 2.0)
	tween.tween_callback(queue_free)


func anim_state() -> String:
	return String(Phase.find_key(phase)).to_lower()
