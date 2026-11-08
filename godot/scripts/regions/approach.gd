class_name Approach
extends RegionScene
## The opening's first two beats, aboard a Kestrel that still works, in orbit over HD-4471 b.
## Juno wakes to a proximity chime in the bunk room, can catch a sliding cup, read her contract,
## check the relay survey and look at the fish Mira carved, then takes the copilot's seat. From
## the seat she turns the scanner to a wreck beacon, traces the spike across three points, tries
## to override the autopilot as it drifts, holds her harness and braces twice as Kestrel falls.
## Then the screen goes black and Opening takes her down to the Kettle.
##
## Beats live in `beat`; Opening reads it, and tests drive it through the same prompts.

signal fell(braced: int)

enum Beat { ABOARD, SEATED, TRACING, DRIFT, HARNESS, BRACE, FALLEN }

const SPACE := Color("04060a")
const PLANET := Color("2a3a3a")
const PLANET_LIT := Color("5f7f74")
const TEAL := Color("3fd1b5")
const AMBER := Color("e8a44e")
## Plan coordinates (see Kestrel.plan) of what she can use.
const BUNK := Vector3(9.4, 0.1, 11.2)
const CUP_FROM := Vector3(13.8, 0.98, 9.6)
const CUP_TO := Vector3(18.4, 0.98, 9.6)
const CONTRACT := Vector3(8.6, 0.58, 9.8)
const RELAY_SCREEN := Vector3(15.2, 1.6, 9.2)
const KEEPSAKE := Vector3(5.0, 2.0, 11.6)
const SEAT := Vector3(5.7, 1.25, 13.9)
const USE_RANGE := 1.7
## How long she has for each brace, and how long the harness hold is.
const BRACE_WINDOW := 1.1
const HARNESS_HOLD := 1.2

var beat := Beat.ABOARD
var kestrel: Kestrel
var cup_caught := false
var read: Dictionary = {}
var traced := 0
var braced := 0
var _cup: MeshInstance3D
var _cup_t := 0.0
var _trace_dots: Array[MeshInstance3D] = []
var _beacon: MeshInstance3D
var _arc: MeshInstance3D
var _nudge := 22.0
var _brace_left := 0.0
var _brace_prompted := 0
var _main: Node
## Everything outside the hull: the drift turns this, never the ship she stands in.
var _sky: Node3D


func _init() -> void:
	exit_point = Vector3(0.0, -500.0, 0.0)
	look = {
		"background_mode": Environment.BG_COLOR, "background_color": SPACE,
		"fog_enabled": false, "volumetric_fog_enabled": false,
		"ambient_light_source": Environment.AMBIENT_SOURCE_COLOR,
		"ambient_light_color": Color("33405a"), "ambient_light_energy": 0.5,
		"sun_energy": 1.3, "sun_color": Color("fff1dc"), "sun_rotation": Vector3(-28.0, -60.0, 0.0),
	}


func build() -> void:
	_main = get_parent()
	kestrel = Kestrel.new()
	kestrel.name = "KestrelAloft"
	add_child(kestrel)
	kestrel.remove_from_group("kestrel")
	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, true)
	# In flight: level, ramp shut.
	kestrel._apply_ramp(false, false)
	entry = kestrel.transform * kestrel.plan(BUNK.x, BUNK.y, BUNK.z)
	entry_yaw = PI * 0.5
	goal = kestrel.transform * kestrel.plan(SEAT.x, SEAT.y, SEAT.z)
	_sky = Node3D.new()
	add_child(_sky)
	_planet()
	_stars()
	_props()
	Sfx.loop("ship_hum_loop", kestrel, -8.0)


func _ready() -> void:
	super._ready()
	Sfx.play("log_chime", null, -4.0, 0.0)
	if _main and _main.get("voice"):
		_main.voice.say(Story.APPROACH_WAKE)


func _process(delta: float) -> void:
	if not cup_caught and _cup:
		_cup_t += delta * 0.35
		var f := 0.5 - 0.5 * cos(_cup_t * TAU * 0.25)
		_cup.position = kestrel.plan(lerpf(CUP_FROM.x, CUP_TO.x, f), CUP_FROM.y, CUP_FROM.z)
	if _beacon:
		_beacon.visible = fmod(Time.get_ticks_msec() / 1000.0, 1.2) < 0.35
	match beat:
		Beat.ABOARD:
			_nudge -= delta
			if _nudge <= 0.0 and _main:
				_nudge = 40.0
				_main.voice.say(Story.APPROACH_NUDGE)
		Beat.BRACE:
			_brace_left -= delta
			if _brace_left <= 0.0:
				_next_brace()
	if _arc and _arc.visible:
		_arc.rotation.y += delta * 0.35


func interaction(pos: Vector3) -> Dictionary:
	match beat:
		Beat.ABOARD:
			if pos.distance_to(_at(SEAT)) < USE_RANGE:
				return {"label": "[E] Take the copilot's seat", "action": sit}
			# Played it before: the bunk offers to sleep through to the crash site.
			if Opening.seen_before() and pos.distance_to(_at(Vector3(9.3, 0.3, 10.2))) < USE_RANGE + 0.4:
				return {"label": "[E] Sleep through the approach (skip the opening)", "action": func(): _main.opening.skip()}
			if not cup_caught and _cup and pos.distance_to(_cup.global_position) < USE_RANGE:
				return {"label": "[E] Catch the cup before it goes over", "action": catch_cup}
			for id in [["contract", CONTRACT, "[E] Read the salvage contract"], ["relay", RELAY_SCREEN, "[E] Check the relay survey"], ["keepsake", KEEPSAKE, "[E] Look at Mira's fish"]]:
				if pos.distance_to(_at(id[1])) < USE_RANGE + 0.3:
					return {"label": id[2], "action": inspect.bind(id[0])}
			if pos.distance_to(_at(SEAT)) < USE_RANGE:
				return {"label": "[E] Take the copilot's seat", "action": sit}

		Beat.SEATED:
			return {"label": "[E] Turn the scanner to the wreck beacon", "action": trace}
		Beat.TRACING:
			return {"label": "[E] Trace the spike (%d/3)" % (traced + 1), "action": trace}
		Beat.DRIFT:
			return {"label": "[E] Override the autopilot", "action": override}
		Beat.HARNESS:
			return {"label": "[Hold E] Hold on to the harness", "hold": HARNESS_HOLD, "action": hold_harness}
		Beat.BRACE:
			return {"label": "[E] BRACE", "action": brace}
	return {}


func catch_cup() -> void:
	cup_caught = true
	Sfx.play("ui_click", null, -4.0, 0.0)
	_main.player.anim.play("interact")
	_main.voice.say(Story.APPROACH_CUP)


func inspect(id: String) -> void:
	read[id] = true
	_main.player.anim.play("interact")
	match id:
		"contract":
			_main.voice.interrupt(Story.APPROACH_CONTRACT)
		"relay":
			_main.voice.interrupt(Story.APPROACH_RELAY)
		"keepsake":
			_main.voice.interrupt(Story.APPROACH_KEEPSAKE)


func sit() -> void:
	beat = Beat.SEATED
	var p: Player = _main.player
	p.global_position = _at(SEAT)
	p.velocity = Vector3.ZERO
	p.face(PI * 0.5)
	p.seated = true
	goal = null
	_main.voice.interrupt(Story.APPROACH_SEATED)


func trace() -> void:
	if beat == Beat.SEATED:
		beat = Beat.TRACING
		for d in _trace_dots:
			d.visible = true
		Sfx.play("signal_ping", null, -6.0, 0.0)
		return
	if traced < _trace_dots.size():
		(_trace_dots[traced].material_override as StandardMaterial3D).emission = TEAL
		(_trace_dots[traced].material_override as StandardMaterial3D).emission_energy_multiplier = 4.0
	traced += 1
	Sfx.play("signal_ping", null, -4.0 + traced, 0.0)
	if traced >= 3:
		beat = Beat.DRIFT
		_main.voice.interrupt(Story.APPROACH_TRACE)
		# The autopilot slips a degree off course.
		create_tween().tween_property(_sky, "rotation:z", deg_to_rad(1.5), 1.5).set_trans(Tween.TRANS_SINE)


func override() -> void:
	beat = Beat.HARNESS
	Sfx.play("ui_click", null, -2.0, 0.0)
	# The correction takes, then is lost: down is somewhere else now.
	var t := create_tween()
	t.tween_property(_sky, "rotation:z", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	t.tween_property(_sky, "rotation:z", deg_to_rad(8.0), 1.6).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(_sky, "rotation:x", deg_to_rad(-5.0), 1.6).set_trans(Tween.TRANS_SINE)
	_main.voice.interrupt(Story.APPROACH_DRIFT)
	_arc.visible = true
	Sfx.play("loom_hum", null, 0.0, 0.0)
	_main.player.add_trauma(0.35)


func hold_harness() -> void:
	beat = Beat.BRACE
	braced = 0
	_brace_prompted = 0
	_main.voice.interrupt(Story.APPROACH_FALL)
	Sfx.play("hull_groan", null, 2.0, 0.0)
	_next_brace()


func brace() -> void:
	if beat != Beat.BRACE:
		return
	braced += 1
	Sfx.play("repair_clunk", null, -4.0, 0.0)
	_next_brace()


## Each brace has a short window: the next one comes when it is taken or missed.
func _next_brace() -> void:
	_main.player.add_trauma(0.5)
	Sfx.play("rock_impact", null, 0.0, 0.1)
	if _brace_prompted >= 2:
		beat = Beat.FALLEN
		fell.emit(braced)
		return
	_brace_prompted += 1
	_brace_left = BRACE_WINDOW


## A plan point (see Kestrel.plan) in world space.
func _at(p: Vector3) -> Vector3:
	return kestrel.to_global(kestrel.plan(p.x, p.y, p.z))


# --- Building -----------------------------------------------------------------------------

func _planet() -> void:
	var planet := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 900.0
	sm.height = 1800.0
	sm.radial_segments = 64
	sm.rings = 32
	planet.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = PLANET
	m.roughness = 1.0
	m.rim_enabled = true
	m.rim = 1.0
	m.rim_tint = 0.2
	m.emission_enabled = true
	m.emission = PLANET_LIT
	m.emission_energy_multiplier = 0.15
	planet.material_override = m
	planet.position = Vector3(-650.0, -1000.0, 80.0)
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.add_child(planet)
	# The wreck beacon down on the surface, blinking.
	_beacon = MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 1.6
	bm.height = 3.2
	_beacon.mesh = bm
	_beacon.material_override = _glow(Color("ff5a3a"), 6.0)
	_beacon.position = Vector3(-330.0, -150.0, 60.0)
	_sky.add_child(_beacon)
	# The thin teal arc that sweeps the atmosphere when the drift starts.
	_arc = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 560.0
	tm.outer_radius = 563.0
	tm.rings = 96
	tm.ring_segments = 4
	_arc.mesh = tm
	_arc.material_override = _glow(TEAL, 3.0)
	_arc.position = Vector3(-650.0, -420.0, 80.0)
	_arc.rotation = Vector3(0.35, 0.0, 0.2)
	_arc.visible = false
	_sky.add_child(_arc)


func _stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := SphereMesh.new()
	q.radius = 0.9
	q.height = 1.8
	q.radial_segments = 4
	q.rings = 2
	mm.mesh = q
	mm.instance_count = 500
	for i in mm.instance_count:
		var d := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.15, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.4, 1.4)), d * 700.0))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	stars.material_override = _glow(Color("dfe8ff"), 2.0)
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.add_child(stars)


func _props() -> void:
	_cup = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.04
	cm.height = 0.11
	_cup.mesh = cm
	_cup.material_override = _mat(Color("d9d2c2"), 0.5)
	kestrel.add_child(_cup)
	var pad := _box(kestrel.plan(CONTRACT.x, CONTRACT.y, CONTRACT.z), Vector3(0.24, 0.02, 0.32), _glow(Color("bfe3ea"), 0.8))
	pad.rotation.y = 0.4
	var fish := _box(kestrel.plan(KEEPSAKE.x, KEEPSAKE.y, KEEPSAKE.z), Vector3(0.05, 0.08, 0.16), _mat(Color("a0703c"), 0.7))
	fish.rotation.x = 0.3
	_box(kestrel.plan(RELAY_SCREEN.x, RELAY_SCREEN.y, RELAY_SCREEN.z + 0.02), Vector3(0.9, 0.5, 0.01), _glow(AMBER, 1.2))
	# A grow lamp over the workshop: something alive on board.
	_box(kestrel.plan(20.4, 1.1, 16.4), Vector3(1.6, 0.25, 0.5), _mat(Color("5f8f4e"), 0.9))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("ffd9a0")
	lamp.light_energy = 0.8
	lamp.omni_range = 3.0
	lamp.position = kestrel.plan(20.4, 2.2, 16.2)
	kestrel.add_child(lamp)
	# The cockpit display's signal graph: three points to trace.
	for i in 3:
		var dot := _box(kestrel.plan(4.78, 1.75 + 0.1 * float(i % 2), 12.4 + 0.5 * float(i)), Vector3(0.02, 0.08, 0.08), _glow(Color("4a5560"), 0.5))
		dot.visible = false
		_trace_dots.append(dot)


func _box(at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	kestrel.add_child(mi)
	return mi


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.3)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m
