class_name FerroCanopy
extends Node3D
## Repair 3, "The half that remains" (milestone B1): Ferro-9's canopy, salvaged in the Gillwood.
##
## Ferro-9's fore section hangs nose-down in the trees. Juno walks a fallen trunk up to its port
## wing; her weight shifts the nose and the canopy assembly starts to creep down its tilted spar.
## She has a slide timer (75/60/45 s by difficulty) to lock three emergency stay-lines: one by
## the cockpit hatch, one at the nose, one on a branch platform across a plank. Too slow and the
## canopy catches on the lip, the lines spring, and the brakes pull it back up to try again.
##
## With the lines on, Ferro-9's winch console under the nose lowers the canopy onto a receiver
## pad: a 75 s hold-out. Veilwings go for the exposed power coupler (a hit shorts it for a few
## seconds); ringing one of the hanging chimes scatters them. Progress only counts while Juno is
## near the console and pauses, never resets, if she leaves. At 100% the canopy is on the pad and
## Reyes's runners sled it home: Game.deliver_component("glazing").
##
## Flags: ferro_lines (all three locked), ferro_winch (seconds wound), ferro_canopy (done).

const SLIDE_TIME := [75.0, 60.0, 45.0]
const WINCH_TIME := 75.0
## Seconds a hit on the coupler stops the winch.
const SHORT_TIME := 3.0
## The winch only counts while Juno is this close to the console.
const WINCH_RANGE := 9.0
const LOCK_HOLD := 1.0
const USE_RANGE := 2.2
## Veilwings that come for the coupler: at the start, then one more at each of these marks.
const WAVES := [[0.0, 2], [25.0, 1], [50.0, 1]]
const SCARE_RADIUS := 25.0
const SCARE_TIME := 4.0
## Where the canopy sits on the nose, and where the slide takes it (fore space).
const CANOPY_ON := Vector3(0.0, 3.35, -3.4)
const CANOPY_EDGE := Vector3(0.0, 2.6, -6.4)
## The stay-line anchors, in the fore section's space (the third is on the branch platform).
const ANCHORS := [Vector3(-4.3, 1.15, 1.6), Vector3(-4.0, 1.15, -5.0), Vector3(-8.0, 1.15, -3.2)]
## The winch console and the receiver pad, in front of the nose (fore space, put on the ground).
const CONSOLE_AT := Vector3(-3.0, 0.0, -12.0)
const PAD_AT := Vector3(2.6, 0.0, -12.5)
const AMBER := Color("e8a44e")
const TEAL := Color("3fd1b5")

var gw: Gillwood
var console_pos := Vector3.INF
var pad_pos := Vector3.INF
var anchor_pos: Array[Vector3] = []
var locked: Array[bool] = [false, false, false]
## The slide: running once Juno's on the wing, seconds left.
var sliding := false
var slide_left := 0.0
var slides := 0
## The hold-out.
var winching := false
var wound := 0.0
var shorted := 0.0
var shorts := 0
var chimes_rung := 0
var veilwings: Array[Veilwing] = []
var coupler: Coupler
var _waves_sent := 0
var _lines: Array[MeshInstance3D] = []
var _tells: Array[StandardMaterial3D] = []
var _coupler_mat: StandardMaterial3D
var _chimes: Array[StaticBody3D] = []
var _chime_cool := 0.0
var _creak := 0.0
var _save_mark := 0.0
var _told_short := false
## After a slip: a breath while the brakes haul the canopy back up.
var _grace := 0.0


## Hit by a veilwing's swoop, the coupler shorts out. It stands where the veilwings aim (they go
## for a point 1.2 m over their target), so its origin is 1.2 m under the glowing coupler.
class Coupler extends Node3D:
	var dead := false
	var velocity := Vector3.ZERO
	var on_hit: Callable

	func take_damage(_amount: float, _from := Vector3.ZERO) -> void:
		if on_hit.is_valid():
			on_hit.call()


func _ready() -> void:
	var fore := gw.fore
	for a in ANCHORS:
		anchor_pos.append(fore.to_global(a))
	console_pos = _on_ground(fore.to_global(CONSOLE_AT))
	pad_pos = _on_ground(fore.to_global(PAD_AT))
	wound = float(Game.flags.get("ferro_winch", 0.0))
	if lines_done():
		locked = [true, true, true]
	_build()
	_sync()


func _exit_tree() -> void:
	Game.set_region_objective("")


func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, gw.global_position.y, p.z)


## True while the canopy is still Juno's to salvage here (not on old saves, where Kestrel's
## canopy was sealed from the skiff and Ferro-9's just unbolts).
func active() -> bool:
	return not done() and not Game.is_repaired("canopy")


func done() -> bool:
	return Game.flags.get("ferro_canopy", false) == true


func lines_done() -> bool:
	return Game.flags.get("ferro_lines", false) == true


func progress() -> float:
	return clampf(wound / WINCH_TIME, 0.0, 1.0)


func slide_time() -> float:
	return SLIDE_TIME[clampi(Game.difficulty, 0, 2)]


## The next place the waypoint points (world space).
func goal_point() -> Vector3:
	if lines_done():
		return console_pos + Vector3.UP * 1.6
	if not on_wing():
		return gw.ramp_foot + Vector3.UP * 1.0
	for i in 3:
		if not locked[i]:
			return anchor_pos[i] + Vector3.UP * 0.8
	return console_pos + Vector3.UP * 1.6


func on_wing() -> bool:
	var p := _player_pos()
	if p == Vector3.INF:
		return false
	var walk := gw.fore.to_global(Gillwood.WALK)
	return p.y > gw.global_position.y + 2.4 and Vector2(p.x - walk.x, p.z - walk.z).length() < 9.0


func interaction(pos: Vector3) -> Dictionary:
	if not active():
		return {}
	if not lines_done():
		for i in 3:
			if not locked[i] and pos.distance_to(anchor_pos[i]) < USE_RANGE:
				return {"label": "[Hold E] Lock stay-line %d" % (i + 1), "action": lock_line.bind(i), "hold": LOCK_HOLD}
		return {}
	if pos.distance_to(console_pos) < USE_RANGE + 0.6:
		if winching:
			return {"label": "Ferro-9's winch: %d%%" % roundi(progress() * 100.0)}
		return {"label": "[E] %s Ferro-9's winch" % ("Restart" if wound > 0.0 else "Start"), "action": start_winch}
	return {}


func lock_line(i: int) -> void:
	if locked[i] or lines_done():
		return
	if not sliding:
		_start_slide()
	locked[i] = true
	Sfx.play("repair_clunk", anchor_pos[i], -3.0)
	if not locked.has(false):
		sliding = false
		Game.set_flag("ferro_lines")
		Sfx.play("relay_two_note", anchor_pos[i], -4.0)
		gw._say(Story.FERRO_LINES_SET)
	_sync()


func start_winch() -> void:
	if winching or done() or not lines_done():
		return
	winching = true
	coupler.dead = false
	Sfx.play("breaker_clunk", console_pos, -2.0)
	gw._say(Story.FERRO_WINCH_START)
	_sync()


## Rung by a shot (or Juno's hand, in tests): every veilwing near it scatters for a while.
func ring_chime(i: int) -> void:
	if _chime_cool > 0.0:
		return
	_chime_cool = 0.8
	chimes_rung += 1
	var at := _chimes[i].global_position
	Sfx.play("log_chime", at, -1.0, 0.0)
	Vfx.burst(gw, at, TEAL, 10, 2.0, 0.05, 0.5, Vector3.UP, 180.0, 0.0)
	for vw in veilwings:
		if is_instance_valid(vw) and not vw.dead and vw.global_position.distance_to(at) < SCARE_RADIUS:
			vw.scare(at, SCARE_TIME)


func _process(delta: float) -> void:
	_chime_cool = maxf(0.0, _chime_cool - delta)
	if not active():
		return
	if not lines_done():
		_tick_slide(delta)
	elif winching:
		_tick_winch(delta)
	_update_lines()
	Game.set_region_objective(objective())


func _tick_slide(delta: float) -> void:
	if _grace > 0.0:
		_grace -= delta
		return
	if not sliding:
		if on_wing():
			_start_slide()
		return
	slide_left -= delta
	_creak -= delta
	var t := 1.0 - clampf(slide_left / slide_time(), 0.0, 1.0)
	gw.canopy.position = CANOPY_ON.lerp(CANOPY_EDGE, t)
	if _creak <= 0.0:
		_creak = lerpf(6.0, 2.0, t)
		Sfx.play("hull_groan", gw.canopy.global_position, lerpf(-10.0, -3.0, t), 0.15)
	if slide_left <= 0.0:
		_slipped()


func _start_slide() -> void:
	sliding = true
	slide_left = slide_time()
	_creak = 0.0
	if slides == 0:
		gw._say(Story.FERRO_CLIMB)
	slides += 1


## Out of time: it catches on the spar's lip, the lines spring, and the brakes haul it back up.
func _slipped() -> void:
	locked = [false, false, false]
	sliding = false
	_grace = 2.0
	Sfx.play("relay_surge", gw.canopy.global_position, -2.0)
	gw._say(Story.FERRO_SLIPPED)
	if is_inside_tree():
		create_tween().tween_property(gw.canopy, "position", CANOPY_ON, 1.5).set_trans(Tween.TRANS_SINE)
	_sync()


func _tick_winch(delta: float) -> void:
	# The veilwings come in waves as the winch runs.
	while _waves_sent < WAVES.size() and wound >= WAVES[_waves_sent][0]:
		for k in int(WAVES[_waves_sent][1]):
			_send_veilwing(veilwings.size())
		_waves_sent += 1
	if shorted > 0.0:
		shorted -= delta
		if shorted <= 0.0:
			Sfx.play("relay_two_note", console_pos, -6.0)
	var near := _player_pos().distance_to(console_pos) < WINCH_RANGE
	if shorted <= 0.0 and near:
		wound += delta
		_creak -= delta
		if _creak <= 0.0:
			_creak = 2.5
			Sfx.play("repair_clunk", gw.canopy.global_position, -12.0, 0.2)
	if wound - _save_mark >= 5.0:
		_save_mark = wound
		Game.set_flag("ferro_winch", wound)
	_coupler_mat.emission_energy_multiplier = 0.4 if shorted > 0.0 else 3.0 + sin(Time.get_ticks_msec() * 0.012) * 1.2
	if wound >= WINCH_TIME:
		_finish()


func _send_veilwing(n: int) -> void:
	var main := gw.get_parent()
	if main == null or not main.has_method("spawn_enemy"):
		return
	var ang := 0.9 + n * 2.1
	var at := console_pos + Vector3(cos(ang) * 13.0, 8.0, sin(ang) * 13.0)
	var vw := main.spawn_enemy("veilwing", at, "", gw) as Veilwing
	if vw == null:
		return
	vw.target = coupler
	vw.add_to_group("ferro_veilwings")
	veilwings.append(vw)


func _on_coupler_hit() -> void:
	if not winching:
		return
	shorted = SHORT_TIME
	shorts += 1
	Sfx.play("arc_zap", coupler.global_position + Vector3.UP * 1.2, 0.0)
	Vfx.burst(gw, coupler.global_position + Vector3.UP * 1.2, Color("9fe8ff"), 18, 4.0, 0.05, 0.4, Vector3.UP, 120.0, -6.0)
	if not _told_short:
		_told_short = true
		gw._say(Story.FERRO_SHORTED)


func _finish() -> void:
	winching = false
	wound = WINCH_TIME
	coupler.dead = true
	for vw in veilwings:
		if is_instance_valid(vw) and not vw.dead:
			vw.scare(console_pos, 2.0)
	Game.set_flag("ferro_winch", wound)
	Game.set_flag("ferro_canopy")
	Sfx.play("repair_clunk", pad_pos, 0.0)
	gw._sync_parts(true)
	if not Game.is_repaired("canopy"):
		Game.deliver_component(String(Campaign.get_repair("canopy")["component"]))
	gw._say(Story.FERRO_WINCH_DONE)
	Game.set_region_objective("")
	_sync()


func objective() -> String:
	if done():
		return ""
	if not lines_done():
		var n := locked.count(true)
		if not sliding:
			return "Climb the fallen trunk to Ferro-9's wing and reach her cockpit"
		return "Lock the stay-lines before the canopy slides: %d/3 locked, %d s" % [n, ceili(slide_left)]
	if not winching:
		return "%s the winch at the console under Ferro-9's nose (%d%%)" % ["Restart" if wound > 0.0 else "Start", roundi(progress() * 100.0)]
	var state := ""
	if shorted > 0.0:
		state = ": coupler shorted, ring a chime"
	elif _player_pos().distance_to(console_pos) >= WINCH_RANGE:
		state = ": paused, get back to the console"
	return "Hold the winch: %d%%%s" % [roundi(progress() * 100.0), state]


func _player_pos() -> Vector3:
	var main := gw.get_parent()
	if main == null or main.get("player") == null:
		return Vector3.INF
	return main.player.global_position


## Anchors with their tell-tales (amber till locked, then teal), the lines from each locked
## anchor to the canopy ring, the console with its coupler, the pad, and three chimes on a frame.
func _build() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("3a3f44")
	dark.roughness = 0.5
	dark.metallic = 0.6
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color("d9cfa8")
	line_mat.roughness = 0.6
	for i in 3:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.12
		pm.bottom_radius = 0.16
		pm.height = 0.6
		post.mesh = pm
		post.material_override = dark
		gw.fore.add_child(post)
		post.position = ANCHORS[i] + Vector3(0.0, 0.3, 0.0)
		var tell := MeshInstance3D.new()
		var tm := SphereMesh.new()
		tm.radius = 0.1
		tm.height = 0.2
		tell.mesh = tm
		var tmat := StandardMaterial3D.new()
		tmat.emission_enabled = true
		tell.material_override = tmat
		_tells.append(tmat)
		gw.fore.add_child(tell)
		tell.position = ANCHORS[i] + Vector3(0.0, 0.66, 0.0)
		var line := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.035
		lm.bottom_radius = 0.035
		lm.height = 1.0
		lm.radial_segments = 6
		line.mesh = lm
		line.material_override = line_mat
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gw.add_child(line)
		_lines.append(line)
	# The console: a slate cabinet, the coupler glowing on top behind a broken guard.
	var console := StaticBody3D.new()
	var cmi := MeshInstance3D.new()
	var cbm := BoxMesh.new()
	cbm.size = Vector3(1.2, 1.1, 0.8)
	cmi.mesh = cbm
	cmi.material_override = gw.ferro_hull()
	var cshape := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = cbm.size
	cshape.shape = cbox
	console.add_child(cmi)
	console.add_child(cshape)
	gw.add_child(console)
	console.global_position = console_pos + Vector3(0.0, 0.55, 0.0)
	console.rotation.y = Gillwood.WRECK_YAW
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.22, 0.14, 0.82)
	stripe.mesh = sm
	stripe.material_override = gw._mat(Gillwood.FERRO_TRIM, 0.5)
	stripe.position = Vector3(0.0, 0.3, 0.0)
	console.add_child(stripe)
	coupler = Coupler.new()
	coupler.name = "Coupler"
	coupler.on_hit = _on_coupler_hit
	coupler.dead = not active()
	gw.add_child(coupler)
	coupler.global_position = console_pos + Vector3(0.0, 1.3 - 1.2, 0.0)
	var glow := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.16
	gm.bottom_radius = 0.2
	gm.height = 0.28
	glow.mesh = gm
	_coupler_mat = gw._glow(Color("9fe8ff"), 1.0)
	glow.material_override = _coupler_mat
	glow.position = Vector3(0.0, 1.3, 0.0)
	coupler.add_child(glow)
	# The receiver pad: a low amber-ringed plate the canopy is lowered onto.
	var pad := MeshInstance3D.new()
	var padm := CylinderMesh.new()
	padm.top_radius = 2.1
	padm.bottom_radius = 2.2
	padm.height = 0.2
	padm.radial_segments = 20
	pad.mesh = padm
	pad.material_override = dark
	gw.add_child(pad)
	pad.global_position = pad_pos + Vector3(0.0, 0.1, 0.0)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 1.95
	rm.outer_radius = 2.15
	rm.rings = 24
	rm.ring_segments = 4
	ring.mesh = rm
	ring.material_override = gw._glow(AMBER, 1.6)
	gw.add_child(ring)
	ring.global_position = pad_pos + Vector3(0.0, 0.22, 0.0)
	# Brandt's chimes: three pipes hung off a frame by the console, struck with a shot.
	var frame_at := console_pos + (pad_pos - console_pos) * 0.5 + Vector3(0.0, 0.0, 0.0)
	var side := (pad_pos - console_pos).normalized().cross(Vector3.UP)
	frame_at += side * 2.6
	for k in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var legm := BoxMesh.new()
		legm.size = Vector3(0.14, 3.4, 0.14)
		leg.mesh = legm
		leg.material_override = dark
		gw.add_child(leg)
		leg.global_position = frame_at + (pad_pos - console_pos).normalized() * 1.4 * k + Vector3(0.0, 1.7, 0.0)
	var bar := MeshInstance3D.new()
	var barm := BoxMesh.new()
	barm.size = Vector3(0.12, 0.12, 3.0)
	bar.mesh = barm
	bar.material_override = dark
	gw.add_child(bar)
	bar.global_position = frame_at + Vector3(0.0, 3.4, 0.0)
	bar.look_at(bar.global_position + (pad_pos - console_pos), Vector3.UP)
	var chime_mat := StandardMaterial3D.new()
	chime_mat.albedo_color = Color("c9c3b0")
	chime_mat.metallic = 0.9
	chime_mat.roughness = 0.25
	for i in 3:
		var body := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		var chm := CylinderMesh.new()
		chm.top_radius = 0.07
		chm.bottom_radius = 0.07
		chm.height = 1.0 + i * 0.25
		mi.mesh = chm
		mi.material_override = chime_mat
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.16
		cyl.height = chm.height
		shape.shape = cyl
		body.add_child(mi)
		body.add_child(shape)
		body.set_meta("on_hit", ring_chime.bind(i))
		gw.add_child(body)
		body.global_position = frame_at + (pad_pos - console_pos).normalized() * (i - 1) * 0.9 + Vector3(0.0, 3.3 - chm.height * 0.5, 0.0)
		_chimes.append(body)


func _sync() -> void:
	for i in 3:
		var on := locked[i] or lines_done() or done()
		_tells[i].albedo_color = (TEAL if on else AMBER).darkened(0.4)
		_tells[i].emission = TEAL if on else AMBER
		_tells[i].emission_energy_multiplier = 2.5
	_update_lines()
	if coupler:
		coupler.dead = not winching
	if _coupler_mat:
		_coupler_mat.emission_energy_multiplier = 3.0 if winching else 0.8


## Each locked line runs from its anchor to the canopy ring (until the canopy's on the pad).
func _update_lines() -> void:
	for i in 3:
		var line := _lines[i]
		var show := (locked[i] or lines_done()) and not done()
		line.visible = show
		if not show:
			continue
		var a := anchor_pos[i] + Vector3.UP * 0.55
		var b := gw.canopy.global_position + (a - gw.canopy.global_position).normalized() * 1.7
		var d := b - a
		if d.length() < 0.05:
			continue
		line.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, d.normalized())) * Basis.from_scale(Vector3(1.0, d.length(), 1.0)), (a + b) * 0.5)


func chime_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c in _chimes:
		out.append(c.global_position)
	return out
