class_name Finale
extends Node
## The departure crisis (production pack, act 4). With the nav core in, the pilot's seat starts a
## 90 second engine spool. The noise brings every animal in the basin down on Kestrel
## (ShipSiege.FINALE), and the planet tries to keep her, using every system Juno fixed:
##   30%  fibre tethers knot onto the gear, the wing and the nose strut. The spool stalls until
##        their knots are shot through (the cockpit scanner marks each one).
##   55%  the new drive overheats. Vent it at the cooling manifold inside VENT_TIME seconds or
##        the spool drops back a quarter.
##   80%  the drive trips the aux breaker: the lights go to emergency red and the spool stalls
##        until the power is rerouted at the aux bay.
## Gerald (the wing turret) keeps shooting wildlife throughout. Hold the hull until the spool is
## full, then launch from the seat in the quiet between two Loom pulses; a launch on the pulse
## is called off with no harm done. A breached hull dumps the spool and every crisis with it.

signal state_changed(state: int)
signal crisis_changed(crisis: int)

enum State { IDLE, SPOOLING, READY, LAUNCHING }
enum Crisis { NONE, TETHERS, OVERHEAT, POWER }

const SPOOL_TIME := 90.0
## Spool fractions at which each crisis strikes, in order.
const CRISES := [[0.3, Crisis.TETHERS], [0.55, Crisis.OVERHEAT], [0.8, Crisis.POWER]]
const VENT_TIME := 15.0
## How much of the spool an unvented overheat costs.
const OVERHEAT_COST := 0.25
## Hits to shoot a knot through.
const KNOT_HITS := 4
## Where the tethers knot on (Kestrel's plan coordinates) and which way their fibres run to the
## ground: the port main gear, the port wing's tip and the nose strut.
const KNOTS := [
	[Vector3(18.0, 0.9, 10.2), Vector3(0.3, 0.0, -1.0)],
	[Vector3(22.0, 1.6, 1.8), Vector3(0.4, 0.0, -1.0)],
	[Vector3(2.4, 0.9, 13.0), Vector3(-1.0, 0.0, 0.2)],
]
const TETHER_REACH := 7.0
## The Loom's beat at the launch: a pulse every PULSE_PERIOD seconds, and the gap after it in
## which Kestrel can lift without being slapped back down.
const PULSE_PERIOD := 9.0
const GAP_FROM := 2.0
const GAP_TO := 7.5
const FIBRE := Color("3fe0c8")

var state := State.IDLE
var spool := 0.0
var crisis := Crisis.NONE
## How many of CRISES have struck this spool.
var stage := 0
## Seconds left to vent an overheat.
var vent_t := 0.0
## Hits left on each knot (0 = cut).
var knot_hits: Array[int] = []
var pulse_t := 0.0
var pulses := 0
var aborts := 0

var siege: ShipSiege
var voice: Voice
var hud: Hud

var _spool_sound: AudioStreamPlayer3D
var _said_half := false
var _said_late := false
var _knots: Array[Node3D] = []
var _klaxon: Node


func _ready() -> void:
	siege.ended.connect(_on_siege_ended)


func can_start() -> bool:
	return state == State.IDLE and Game.current_repair() == "" and not Game.launched and not siege.is_active()


func start() -> void:
	if not can_start():
		return
	spool = 0.0
	stage = 0
	_said_half = false
	_said_late = false
	_set_state(State.SPOOLING)
	# The finale is the last assault: one still waiting to happen is folded into it.
	siege.pending = -1
	siege.start_finale()
	voice.interrupt(Story.FINALE_START)
	Sfx.play("power_up", null, -4.0, 0.0)


## Tests: skip straight past every crisis (the spool and the assault still run).
func skip_crises() -> void:
	_end_crisis()
	stage = CRISES.size()


func begin_launch() -> void:
	if state == State.READY:
		_set_state(State.LAUNCHING)


func progress() -> float:
	return clampf(spool / SPOOL_TIME, 0.0, 1.0)


## True when the spool can't climb: a crisis is holding it.
func stalled() -> bool:
	return crisis == Crisis.TETHERS or crisis == Crisis.POWER


## In the quiet after a Loom pulse, when a launch gets away.
func in_gap() -> bool:
	return pulse_t >= GAP_FROM and pulse_t < GAP_TO


## Seconds until the launch gap opens (0 while it's open).
func gap_in() -> float:
	if in_gap():
		return 0.0
	return GAP_FROM - pulse_t if pulse_t < GAP_FROM else PULSE_PERIOD - pulse_t + GAP_FROM


## The pilot's seat in the gap: lift. On the pulse: call it off, no harm done. Returns whether
## Kestrel can go.
func try_launch() -> bool:
	if state != State.READY:
		return false
	if in_gap():
		return true
	aborts += 1
	voice.interrupt([Story.LAUNCH_ABORT])
	Sfx.play("hob_warning", null, -2.0, 0.0)
	return false


## The text for the shared top bar while the spool runs.
func bar_text() -> String:
	var text := "ENGINE SPOOL %d%%" % int(progress() * 100.0)
	match crisis:
		Crisis.TETHERS:
			text += "  STALLED: TETHERS %d" % knots_left()
		Crisis.OVERHEAT:
			text += "  OVERHEAT: VENT IN %d" % ceili(vent_t)
		Crisis.POWER:
			text += "  STALLED: AUX TRIPPED"
	return text


func knots_left() -> int:
	return knot_hits.filter(func(h): return h > 0).size()


## Where a live knot is (world space), for the scanner.
func knot_position(i: int) -> Vector3:
	return siege.kestrel.to_global(siege.kestrel.plan(KNOTS[i][0].x, KNOTS[i][0].y, KNOTS[i][0].z))


## The scanner's mark while a crisis runs, or null: the nearest knot, the cooling manifold or the
## aux bay.
func waypoint(from: Vector3):
	match crisis:
		Crisis.TETHERS:
			var best = null
			var best_d := INF
			for i in knot_hits.size():
				if knot_hits[i] <= 0:
					continue
				var d := knot_position(i).distance_to(from)
				if d < best_d:
					best_d = d
					best = knot_position(i)
			return best
		Crisis.OVERHEAT:
			return siege.kestrel.to_global(siege.kestrel.interact_points["cooling"])
		Crisis.POWER:
			return siege.kestrel.to_global(siege.kestrel.interact_points["aux_power"])
	return null


## A knot was shot.
func hit_knot(i: int) -> void:
	if crisis != Crisis.TETHERS or i >= knot_hits.size() or knot_hits[i] <= 0:
		return
	knot_hits[i] -= 1
	if knot_hits[i] > 0:
		Sfx.play("thread_spool", knot_position(i), -4.0, 0.15)
		return
	Sfx.play("thread_snap", knot_position(i), 2.0, 0.1)
	if is_inside_tree():
		Vfx.burst(siege.kestrel.get_parent(), knot_position(i), FIBRE, 14, 4.0, 0.06, 0.6, Vector3.UP, 120.0, -6.0)
	if i < _knots.size() and is_instance_valid(_knots[i]):
		_knots[i].queue_free()
	if knots_left() == 0:
		_end_crisis()
		voice.say_line(Story.FINALE_TETHERS_CUT)
	else:
		Game.launch_objective = _objective()
		Game.objective_changed.emit(Game.objective_text())


func vent() -> void:
	if crisis != Crisis.OVERHEAT:
		return
	Sfx.play("steam_burst", siege.kestrel.to_global(siege.kestrel.interact_points["cooling"]), 0.0, 0.0)
	_end_crisis()
	voice.say_line(Story.FINALE_VENTED)


func reroute() -> void:
	if crisis != Crisis.POWER:
		return
	Sfx.play("breaker_clunk", siege.kestrel.to_global(siege.kestrel.interact_points["aux_power"]), 0.0, 0.0)
	siege.kestrel._apply_aux(true)
	_end_crisis()
	voice.say_line(Story.FINALE_POWER_BACK)


func _physics_process(delta: float) -> void:
	if state == State.READY:
		_beat(delta)
		return
	if state != State.SPOOLING:
		return
	if not stalled():
		spool += delta
	if stage < CRISES.size() and crisis == Crisis.NONE and progress() >= CRISES[stage][0]:
		stage += 1
		_begin_crisis(CRISES[stage - 1][1])
	if crisis == Crisis.OVERHEAT:
		vent_t -= delta
		if vent_t <= 0.0:
			spool = maxf(spool - SPOOL_TIME * OVERHEAT_COST, 0.0)
			_end_crisis()
			voice.interrupt([Story.FINALE_OVERHEAT_LOST])
	if not _said_half and progress() >= 0.5 and crisis == Crisis.NONE:
		_said_half = true
		voice.say_line(Story.FINALE_HALF)
	if not _said_late and spool >= SPOOL_TIME - 10.0 and crisis == Crisis.NONE:
		_said_late = true
		voice.say_line(Story.FINALE_LATE)
	siege.kestrel.set_engine_power(0.15 + 0.45 * progress())
	if _spool_sound:
		_spool_sound.pitch_scale = 0.6 + 0.8 * progress()
	if spool >= SPOOL_TIME and crisis == Crisis.NONE:
		spool = SPOOL_TIME
		pulse_t = 0.0
		_set_state(State.READY)
		siege.stand_down()
		voice.interrupt([Story.FINALE_READY])
		_pulse()
	elif hud:
		hud.set_hull(siege.hull / ShipSiege.MAX_HULL, bar_text())


## The ground answers the full spool: a Loom pulse rolls out under Kestrel every PULSE_PERIOD.
func _beat(delta: float) -> void:
	pulse_t += delta
	if pulse_t >= PULSE_PERIOD:
		pulse_t -= PULSE_PERIOD
		_pulse()


func _pulse() -> void:
	pulses += 1
	Sfx.play("loom_hum", null, -2.0, 0.0)
	if not is_inside_tree() or siege.kestrel == null:
		return
	var ring := LoomPulse.new()
	ring.one_shot = true
	ring.damage = 0.0
	ring.knockback = 0.0
	ring.speed = 30.0
	ring.max_radius = 70.0
	ring.ring_height = 1.2
	siege.kestrel.get_parent().add_child(ring)
	ring.global_position = Vector3(siege.kestrel.global_position.x, 0.2, siege.kestrel.global_position.z)
	ring.fire()


func _begin_crisis(c: Crisis) -> void:
	crisis = c
	match c:
		Crisis.TETHERS:
			_spawn_knots()
			voice.interrupt(Story.FINALE_TETHERS)
			Sfx.play("thread_spool", siege.kestrel.global_position, 2.0, 0.0)
		Crisis.OVERHEAT:
			vent_t = VENT_TIME
			voice.interrupt(Story.FINALE_OVERHEAT)
			Sfx.play("hob_warning", null, 0.0, 0.0)
		Crisis.POWER:
			siege.kestrel._apply_aux(false)
			voice.interrupt(Story.FINALE_POWER)
			Sfx.play("relay_surge", siege.kestrel.to_global(siege.kestrel.interact_points["aux_power"]), 0.0, 0.0)
	if _klaxon == null:
		_klaxon = Sfx.loop("finale_klaxon", siege.kestrel, -6.0)
		if _klaxon is AudioStreamPlayer3D:
			(_klaxon as AudioStreamPlayer3D).max_distance = 110.0
			(_klaxon as AudioStreamPlayer3D).unit_size = 12.0
	Game.launch_objective = _objective()
	Game.objective_changed.emit(Game.objective_text())
	crisis_changed.emit(c)


func _end_crisis() -> void:
	if crisis == Crisis.POWER:
		siege.kestrel._apply_aux(Game.is_repaired("aux_power"))
	crisis = Crisis.NONE
	vent_t = 0.0
	if _klaxon and is_instance_valid(_klaxon):
		_klaxon.queue_free()
	_klaxon = null
	for k in _knots:
		if is_instance_valid(k):
			k.queue_free()
	_knots.clear()
	knot_hits.clear()
	if state == State.SPOOLING:
		Game.launch_objective = _objective()
		Game.objective_changed.emit(Game.objective_text())
	crisis_changed.emit(crisis)


## The tethers: a knot of teal fibre on each strut and spar, and the fibre running down into the
## ground, taut.
func _spawn_knots() -> void:
	knot_hits.clear()
	_knots.clear()
	var k := siege.kestrel
	var fibre := StandardMaterial3D.new()
	fibre.albedo_color = FIBRE.darkened(0.55)
	fibre.emission_enabled = true
	fibre.emission = FIBRE
	fibre.emission_energy_multiplier = 1.6
	for i in KNOTS.size():
		knot_hits.append(KNOT_HITS)
		var at := knot_position(i)
		var out: Vector3 = k.global_basis * (KNOTS[i][1] as Vector3).normalized()
		out.y = 0.0
		out = out.normalized()
		var ground := at + out * TETHER_REACH
		ground.y = k.global_position.y - 0.6
		var root := Node3D.new()
		root.name = "Tether%d" % i
		k.get_parent().add_child(root)
		root.global_position = at
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.set_meta("on_hit", hit_knot.bind(i))
		var sh := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.55
		sh.shape = sp
		body.add_child(sh)
		root.add_child(body)
		var knot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.8
		sm.radial_segments = 10
		sm.rings = 6
		knot.mesh = sm
		knot.material_override = fibre
		root.add_child(knot)
		# The fibre: a bundle of three strands from the knot to the ground.
		var run := ground - at
		for s in 3:
			var strand := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.07
			cm.height = run.length()
			cm.radial_segments = 5
			cm.rings = 1
			strand.mesh = cm
			strand.material_override = fibre
			root.add_child(strand)
			var side := Vector3(cos(s * TAU / 3.0), 0.0, sin(s * TAU / 3.0)) * 0.12
			strand.position = run * 0.5 + side
			var y := run.normalized()
			var x := y.cross(Vector3.UP).normalized() if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
			strand.basis = Basis(x, y, x.cross(y))
		_knots.append(root)


func _on_siege_ended(success: bool) -> void:
	if state != State.SPOOLING or success:
		return
	spool = 0.0
	_end_crisis()
	stage = 0
	siege.kestrel.set_engine_power(0.0)
	_set_state(State.IDLE)
	voice.interrupt([Story.FINALE_FAILED])


const OBJECTIVES := {
	State.IDLE: "",
	State.SPOOLING: "Hold Kestrel's hull while the engine spools",
	State.READY: "Get to the pilot's seat and launch in the quiet between Loom pulses",
	State.LAUNCHING: "",
}


func _objective() -> String:
	if state != State.SPOOLING:
		return OBJECTIVES[state]
	match crisis:
		Crisis.TETHERS:
			return "Shoot through the tether knots holding Kestrel down: %d left" % knots_left()
		Crisis.OVERHEAT:
			return "The drive is overheating: vent it at the cooling manifold"
		Crisis.POWER:
			return "The aux breaker tripped: reroute power at the aux bay"
	return OBJECTIVES[state]


func _set_state(s: State) -> void:
	state = s
	# The spool whine rises with the spool, holds while she's ready, and gives way to the launch.
	if s == State.SPOOLING and _spool_sound == null:
		_spool_sound = Sfx.loop("spool_loop", siege.kestrel, 2.0) as AudioStreamPlayer3D
		if _spool_sound:
			_spool_sound.max_distance = 120.0
			_spool_sound.unit_size = 14.0
			_spool_sound.pitch_scale = 0.6
	elif (s == State.IDLE or s == State.LAUNCHING) and _spool_sound:
		_spool_sound.queue_free()
		_spool_sound = null
	Game.launch_objective = _objective()
	Game.objective_changed.emit(Game.objective_text())
	state_changed.emit(s)
