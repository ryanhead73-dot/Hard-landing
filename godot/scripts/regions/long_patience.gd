class_name LongPatience
extends ShatterScene
## Repair 6, "The cold core" (production pack, milestone D1): the stern of the freighter Long
## Patience. She broke in two coming down sixty years ago; her bow is the Kettle's graveyard, and
## her stern, engine and all, fell through the Loom Expanse's east rim. HOB finds its drive
## signature from the Loom's overlook, and a cleft in the east rim leads to it.
##
## Local space, Juno coming in at the south end (+Z) of a fibre-choked ravine, looking north:
##   the ravine     up to the hull and the breach in its stern plating;
##   the engine hall  x -14..14, z -38..28, dark but for four emergency lamps. Three surveillance
##                  mirrors sweep it. They see far into a lamp's pool and only a few metres into
##                  the dark, and they shutter for a moment after every Loom pulse: that's when to
##                  move. A mirror that catches Juno flares red and wakes the guardian;
##   the cage       the drive coil hangs at the north end in a cold magnetic cage. Its breaker is
##                  on the east wall; cutting it drops the cage bars and kills the lamps too;
##   the guardian   (PatienceGuardian) sleeps in an alcove by the cage. When the coil comes out of
##                  the cage it wakes, and the coil rings on every pulse, so it always knows where
##                  she is. Three ceiling cargo magnets, shot when it's under them, grab it and
##                  tear its back plate open;
##   the hoist      by the breach. Load the coil and it rises through the roof hatch; Reyes's
##                  runners take it from the rim (Game.deliver_component("drive_coil"));
##   the bridge     a side cabin by the breach with a medical distress call that turns out to be
##                  a recording from before the crash (lore, scrap).
## Flags: reached_patience, patience_power_off, patience_coil_out, patience_hoist, patience_coil
## (done), patience_distress, patience_guardian_down, patience_spotted.

const SEED := 61
const HALL := Rect2(-14.0, -38.0, 28.0, 66.0)
const ROOF_Y := 12.0
const BREACH_HALF := 2.5
## Emergency lamps hung over the aisle: their pools are where the mirrors see furthest.
const LAMPS := [Vector3(-4.0, 5.0, 17.0), Vector3(3.0, 5.0, 4.0), Vector3(-3.0, 5.0, -10.0), Vector3(4.0, 5.0, -22.0)]
const LAMP_POOL := 6.5
## Mirrors: [position, the angle it sweeps about (radians in x/z, 0 = +X), sweep, rate, phase].
const MIRRORS := [
	[Vector3(-11.5, 0.0, 12.0), 0.0, 0.75, 0.55, 0.0],
	[Vector3(11.5, 0.0, -2.0), PI, 0.75, 0.5, 1.7],
	[Vector3(-11.5, 0.0, -18.0), 0.0, 0.7, 0.6, 3.1],
]
const MIRROR_Y := 3.2
const SEE_LIT := 13.0
const SEE_DARK := 5.5
const SEE_COS := 0.95
## The Loom's beat in the hall, and how long the mirrors are shuttered after each pulse.
const PULSE := 6.0
const SHUTTER := 2.2
const CAGE := Vector3(0.0, 0.0, -30.0)
const CAGE_R := 2.2
const COIL_USE := Vector3(0.0, 0.0, -27.0)
const BREAKER := Vector3(13.4, 0.0, -26.0)
const HOIST := Vector3(-10.0, 0.0, 21.0)
const HOIST_TIME := 20.0
const DISTRESS := Vector3(12.6, 0.0, 25.0)
const MAGNETS := [Vector3(0.0, 0.0, -16.0), Vector3(-4.0, 0.0, -2.0), Vector3(-7.0, 0.0, 10.0)]
const MAGNET_Y := 9.6
const MAGNET_REACH := 3.2
const MAGNET_RECHARGE := 3.0
const ALCOVE := Vector3(-10.0, 0.0, -34.0)
const COVER := [
	[Vector3(0.0, 0.9, 12.0), Vector3(6.0, 1.8, 2.0)], [Vector3(-1.0, 0.9, -8.0), Vector3(5.0, 1.8, 2.5)],
	[Vector3(6.0, 0.9, -14.0), Vector3(2.0, 1.8, 4.0)], [Vector3(-6.5, 0.6, 2.0), Vector3(2.0, 1.2, 2.0)],
	[Vector3(5.0, 0.9, 18.0), Vector3(3.0, 1.8, 2.0)], [Vector3(-5.0, 0.9, -24.0), Vector3(2.5, 1.8, 3.0)],
]
const USE_RANGE := 2.4
const HULL_IN := Color("57534c")
const AMBER := Color("ffb04a")
const COLD := Color("8fd8ff")

var guardian: PatienceGuardian
var spotted := 0
## Seconds since the last pulse, and how many pulses (tests read these).
var pulse_t := 0.0
var pulses := 0
var hoist_t := 0.0
var _lamps: Array[OmniLight3D] = []
var _lamp_mat: StandardMaterial3D
var _cage_light: OmniLight3D
var _bars: Node3D
var _bar_bodies: Array[CollisionShape3D] = []
var _coil: MeshInstance3D
var _coil_mat: StandardMaterial3D
var _hoist: Node3D
var _hoist_coil: MeshInstance3D
var _dishes: Array[Node3D] = []
var _beams: Array[MeshInstance3D] = []
var _beam_mats: Array[StandardMaterial3D] = []
var _alarm: Array[float] = [0.0, 0.0, 0.0]
var _magnet_mats: Array[StandardMaterial3D] = []
var _magnet_cool: Array[float] = [0.0, 0.0, 0.0]
var _distress_mat: StandardMaterial3D
var _t := 0.0
var _weapon: Node


func _init() -> void:
	entry = Vector3(0.0, 0.3, 58.0)
	entry_yaw = 0.0
	exit_point = Vector3(0.0, 0.0, 63.5)
	exit_label = "Go back west to the Loom Expanse"
	goal = BREAKER + Vector3(-1.2, 1.2, 0.0)
	residents = [["guardian", ALCOVE, {"_unless": "patience_guardian_down"}]]
	look = {
		"fog_light_color": Color("4a3a58"), "fog_density": 0.009,
		"ambient_light_color": Color("8a78a8"), "ambient_light_energy": 0.45,
		"background_energy_multiplier": 0.45,
		"sun_energy": 0.55, "sun_color": Color("ffb48c"), "sun_rotation": Vector3(-20.0, 200.0, 0.0),
	}


func build() -> void:
	_begin_batch()
	_rng.seed = SEED
	_ground()
	_ravine()
	_hull()
	_cover()
	_cage_base()
	_bridge()
	_hoist_frame()
	_magnet_gantry()
	_end_batch()
	# Moving or switching parts, each its own mesh.
	_build_lamps()
	_build_mirrors()
	_build_cage()
	_build_hoist()
	_build_magnets()
	_restore()
	Game.flag_changed.connect(_on_flag_changed)


func _ready() -> void:
	super()
	if not Game.flags.get("reached_patience", false):
		Game.set_flag("reached_patience")
		_say(Story.PATIENCE_ARRIVE)
	var main := get_parent()
	if main and main.get("player") and main.player.get("weapon"):
		_weapon = main.player.weapon
		_weapon.fired.connect(_on_fired)


func _exit_tree() -> void:
	Game.set_region_objective("")
	if _weapon and is_instance_valid(_weapon) and _weapon.fired.is_connected(_on_fired):
		_weapon.fired.disconnect(_on_fired)


func spawn_residents(main: Node) -> Array[Enemy]:
	var out := super(main)
	for e in out:
		if e is PatienceGuardian:
			adopt_guardian(e)
	return out


## Holds the guardian to the hall, and wakes it if the coil is already out.
func adopt_guardian(g: PatienceGuardian) -> void:
	guardian = g
	var a := to_global(Vector3(HALL.position.x + 1.6, 0.0, HALL.position.y + 1.6))
	var b := to_global(Vector3(HALL.end.x - 1.6, 0.0, HALL.end.y - 1.6))
	g.bounds = Rect2(Vector2(a.x, a.z), Vector2(b.x - a.x, b.z - a.z))
	g.rotation.y = PI * 0.5
	if coil_out() and not hoisting():
		var p := _player()
		if p:
			g.wake(p.global_position)


# --- State ---------------------------------------------------------------------------------

func power_off() -> bool:
	return Game.flags.get("patience_power_off", false) == true


func coil_out() -> bool:
	return Game.flags.get("patience_coil_out", false) == true


func hoisting() -> bool:
	return Game.flags.get("patience_hoist", false) == true and not done()


func done() -> bool:
	return Game.flags.get("patience_coil", false) == true or Game.is_repaired("engine") or Game.delivered("drive_coil")


## The mission is live: the engine is the repair Kestrel needs and the coil isn't home yet.
func active() -> bool:
	return Game.current_repair() == "engine" and not done()


func shuttered() -> bool:
	return pulse_t < SHUTTER


func lamps_on() -> bool:
	return not power_off()


## Inside a lamp's pool (local x/z), with the lamps on.
func lit(local: Vector3) -> bool:
	if not lamps_on():
		return false
	for l in LAMPS:
		if Vector2(local.x - l.x, local.z - l.z).length() < LAMP_POOL:
			return true
	return false


## Where mirror `i` is looking now (local, flat).
func mirror_aim(i: int) -> Vector3:
	var m: Array = MIRRORS[i]
	var a: float = m[1] + m[2] * sin(_t * m[3] + m[4])
	return Vector3(cos(a), 0.0, sin(a))


## Whether mirror `i` sees a point (world space) now: not shuttered, in its cone, in reach (far
## in a lamp's pool, near in the dark) and in the clear.
func mirror_sees(i: int, world: Vector3) -> bool:
	if shuttered():
		return false
	var m: Array = MIRRORS[i]
	var eye: Vector3 = m[0] + Vector3.UP * MIRROR_Y
	var p := to_local(world)
	var to := Vector3(p.x - eye.x, 0.0, p.z - eye.z)
	var reach := SEE_LIT if lit(p) else SEE_DARK
	if to.length() > reach or to.length() < 0.5:
		return false
	if to.normalized().dot(mirror_aim(i)) < SEE_COS:
		return false
	var space := get_world_3d().direct_space_state
	# From just in front of the dish, clear of its own post.
	var from := to_global(eye + to.normalized() * 0.6)
	var q := PhysicsRayQueryParameters3D.create(from, world + Vector3.UP * 1.1, Game.LAYER_WORLD)
	return space.intersect_ray(q).is_empty()


# --- Actions ---------------------------------------------------------------------------------

## Pulls the cage breaker: the bars drop, and the lamps die with them.
func cut_power() -> void:
	if power_off():
		return
	Game.set_flag("patience_power_off")
	Sfx.play("breaker_clunk", to_global(BREAKER), 0.0, 0.0)
	Sfx.play("cage_drop", to_global(CAGE + Vector3.UP * 2.0), 0.0, 0.0)
	_say(Story.PATIENCE_POWER)


func take_coil() -> void:
	if not power_off() or coil_out() or done() or Game.carrying != "":
		return
	Game.set_flag("patience_coil_out")
	Game.take_component("drive_coil")
	Game.find_log(Story.log_at("engine", "component"))
	Sfx.play("repair_clunk", to_global(CAGE + Vector3.UP), 0.0, 0.0)
	_say(Story.PATIENCE_AMBUSH)
	if guardian and is_instance_valid(guardian):
		guardian.wake(to_global(COIL_USE))


func load_hoist() -> void:
	if Game.carrying != "drive_coil" or hoisting() or done():
		return
	Game.carrying = ""
	Game.carrying_changed.emit("")
	Game.set_flag("patience_hoist")
	hoist_t = 0.0
	Sfx.play("hoist_winch", to_global(HOIST), 0.0, 0.0)
	_say(Story.PATIENCE_HOIST)


func answer_distress() -> void:
	if Game.flags.get("patience_distress", false):
		return
	Game.set_flag("patience_distress")
	Game.find_log("patience_distress")
	Game.add_scrap(25)
	Sfx.play("log_chime", to_global(DISTRESS), -4.0, 0.0)
	_say(Story.PATIENCE_DISTRESS)


## A shot hit cargo magnet `i`: if the guardian is under it, it's caught.
func fire_magnet(i: int) -> bool:
	if _magnet_cool[i] > 0.0:
		return false
	_magnet_cool[i] = MAGNET_RECHARGE
	var under := to_global(MAGNETS[i])
	Sfx.play("magnet_clamp", to_global(MAGNETS[i] + Vector3.UP * MAGNET_Y), 0.0, 0.0)
	if guardian and is_instance_valid(guardian) and not guardian.dead:
		var off := guardian.global_position - under
		if Vector2(off.x, off.z).length() < MAGNET_REACH:
			guardian.pin()
			if not Game.flags.get("patience_magnet_used", false):
				Game.set_flag("patience_magnet_used")
				_say(Story.PATIENCE_MAGNET)
			return true
	return false


func interaction(pos: Vector3) -> Dictionary:
	var p := to_local(pos)
	if Vector2(p.x - BREAKER.x + 1.2, p.z - BREAKER.z).length() < USE_RANGE:
		if power_off():
			return {"label": "Cage breaker: off"}
		return {"label": "[E] Cut power to the magnetic cage", "action": cut_power}
	if Vector2(p.x - COIL_USE.x, p.z - COIL_USE.z).length() < USE_RANGE:
		if done() or coil_out():
			return {"label": "An empty cradle"}
		if not power_off():
			return {"label": "The drive coil hangs in a cold magnetic cage. Its breaker is on the east wall"}
		if Game.carrying != "":
			return {"label": "Drive coil: your hands are full"}
		return {"label": "[E] Unbolt the drive coil", "action": take_coil}
	if Vector2(p.x - HOIST.x, p.z - HOIST.z).length() < USE_RANGE + 0.6:
		if hoisting():
			return {"label": "The hoist is lifting the coil: %d s" % ceili(HOIST_TIME - hoist_t)}
		if Game.carrying == "drive_coil":
			return {"label": "[E] Load the coil onto the cargo hoist", "action": load_hoist}
		return {"label": "Cargo hoist: it runs up through the roof hatch to the rim"}
	if not Game.flags.get("patience_distress", false) and Vector2(p.x - DISTRESS.x + 1.2, p.z - DISTRESS.z).length() < USE_RANGE:
		return {"label": "[E] Answer the medical distress call", "action": answer_distress}
	return {}


# --- Running -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	pulse_t += delta
	if pulse_t >= PULSE:
		pulse_t = 0.0
		_pulse()
	for i in _magnet_cool.size():
		_magnet_cool[i] = maxf(_magnet_cool[i] - delta, 0.0)
		_magnet_mats[i].emission_energy_multiplier = 0.4 if _magnet_cool[i] > 0.0 else 2.2 + 0.6 * sin(_t * 4.0 + i)
	if _distress_mat:
		_distress_mat.emission_energy_multiplier = (5.0 if fmod(_t, 1.2) < 0.3 else 0.4) if not Game.flags.get("patience_distress", false) else 0.2
	if _coil_mat:
		_coil_mat.emission_energy_multiplier = 2.0 + (2.5 if pulse_t < 0.4 else 0.0)
	_tick_hoist(delta)
	_tick_mirrors(delta)
	_update_goal()


func _pulse() -> void:
	pulses += 1
	Sfx.play("loom_hum", to_global(Vector3(0.0, 6.0, -5.0)), -10.0, 0.0)
	# Out of its cage the coil rings with the Loom, and the guardian feels it.
	if Game.carrying == "drive_coil":
		var p := _player()
		if p:
			Sfx.play("ridge_thrum", p.global_position, -2.0, 0.0)
			if guardian and is_instance_valid(guardian):
				guardian.hear(p.global_position)


func _tick_mirrors(delta: float) -> void:
	var p := _player()
	for i in MIRRORS.size():
		var aim := mirror_aim(i)
		_dishes[i].rotation.y = atan2(-aim.x, -aim.z)
		_alarm[i] = maxf(_alarm[i] - delta, 0.0)
		var col := Color(1.0, 0.25, 0.15, 0.32) if _alarm[i] > 0.0 else Color(COLD, 0.0 if shuttered() else 0.16)
		_beam_mats[i].albedo_color = col
		_beams[i].visible = col.a > 0.0
		if p and _alarm[i] <= 0.0 and not p.dead and mirror_sees(i, p.global_position):
			_spot(i, p.global_position)


func _spot(i: int, at: Vector3) -> void:
	_alarm[i] = 2.0
	spotted += 1
	Sfx.play("mirror_alarm", to_global(MIRRORS[i][0] + Vector3.UP * MIRROR_Y), 0.0, 0.0)
	if not Game.flags.get("patience_spotted", false):
		Game.set_flag("patience_spotted")
		_say(Story.PATIENCE_SPOTTED)
	if guardian and is_instance_valid(guardian):
		guardian.wake(at)


func _tick_hoist(delta: float) -> void:
	if not hoisting():
		return
	hoist_t += delta
	var k := clampf(hoist_t / HOIST_TIME, 0.0, 1.0)
	_hoist.position.y = k * (ROOF_Y + 1.5)
	if hoist_t >= HOIST_TIME:
		_finish()


## The coil's up and away: Reyes's runners take it from the rim.
func _finish() -> void:
	if Game.flags.get("patience_coil", false):
		return
	Game.set_flag("patience_coil")
	Game.deliver_component("drive_coil")
	_say(Story.PATIENCE_DONE)


func _on_fired() -> void:
	var p := _player()
	if p and guardian and is_instance_valid(guardian):
		guardian.shot_fired(p.global_position)


func _on_flag_changed(_flag: String, _value: Variant) -> void:
	_sync()


func _update_goal() -> void:
	if not active():
		Game.set_region_objective("")
		goal = exit_point + Vector3(0.0, 1.0, 0.0)
		return
	if hoisting():
		goal = HOIST + Vector3(0.0, 2.0, 0.0)
		Game.set_region_objective("Hold out while the hoist lifts the coil to the rim: %d s" % ceili(HOIST_TIME - hoist_t))
	elif Game.carrying == "drive_coil":
		goal = HOIST + Vector3(0.0, 1.5, 0.0)
		Game.set_region_objective("Get the coil to the cargo hoist by the breach. The guardian feels every pulse it rings")
	elif power_off():
		goal = COIL_USE + Vector3(0.0, 1.5, 0.0)
		Game.set_region_objective("Unbolt the drive coil from its cradle")
	else:
		goal = BREAKER + Vector3(-1.2, 1.2, 0.0)
		Game.set_region_objective("Reach the cage breaker on the east wall. Move while the mirrors are shuttered, after each pulse")


func _player() -> Node3D:
	var main := get_parent()
	if main == null or main.get("player") == null:
		return null
	return main.player


## After a load or a death mid-carry: put things back the way the flags say.
func _restore() -> void:
	if coil_out() and not hoisting() and not done() and Game.carrying != "drive_coil":
		# Lost between the cage and the hoist (a load from before the carry): it's back in its cradle.
		Game.flags["patience_coil_out"] = false
	if Game.flags.get("patience_hoist", false) and not Game.flags.get("patience_coil", false):
		_finish()
	_sync()


func _sync() -> void:
	var off := power_off()
	for l in _lamps:
		l.light_energy = 0.0 if off else 1.6
	if _lamp_mat:
		_lamp_mat.emission_energy_multiplier = 0.05 if off else 3.0
	if _cage_light:
		_cage_light.light_color = AMBER if off else COLD
		_cage_light.light_energy = 0.8 if off else 1.4
	if _bars:
		_bars.position.y = -3.6 if off else 0.0
		for s in _bar_bodies:
			s.disabled = off
	if _coil:
		_coil.visible = not (coil_out() or done())
	if _hoist:
		_hoist_coil.visible = Game.flags.get("patience_hoist", false) == true and not Game.flags.get("patience_coil", false)
		if not hoisting():
			_hoist.position.y = (ROOF_Y + 1.5) if Game.flags.get("patience_coil", false) and Game.flags.get("patience_hoist", false) else 0.0


# --- Building ------------------------------------------------------------------------------

func _ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(60.0, 120.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0.0, 0.0, 10.0)
	mi.material_override = _tex("shatterlands_ground", 2.5, true, Color(0.9, 0.75, 0.82), _mat(Color("3a2e38"), 0.9))
	add_child(mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 120.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 10.0)
	body.add_child(shape)
	add_child(body)
	# The hall's deck plating over it.
	_box(Vector3(0.0, 0.02, -5.0), Vector3(28.0, 0.04, 66.0), _mat(Color("2c2b2a"), 0.7), false)


## The way in from the Loom: fibre walls closing on the stern, a south wall behind the entry.
func _ravine() -> void:
	var fibre := _mat(Color("6a4434"), 0.95)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 13.0, 7.0, 48.0), Vector3(6.0, 14.0, 40.0), fibre, true)
		for k in 7:
			var z := 32.0 + k * 5.0 + _rng.randf_range(-1.0, 1.0)
			var lean := Basis(Vector3(0.0, 0.0, 1.0), side * _rng.randf_range(0.15, 0.4))
			_box(Vector3(side * 9.6, 5.0, z), Vector3(1.2, 11.0, 1.4), fibre, false, self, lean)
	_box(Vector3(0.0, 7.0, 68.0), Vector3(20.0, 14.0, 2.0), fibre, true)
	# The outer walls of the whole pocket, behind the hull.
	_wall(Vector3(-17.0, 8.0, -6.0), Vector3(2.0, 16.0, 70.0))
	_wall(Vector3(17.0, 8.0, -6.0), Vector3(2.0, 16.0, 70.0))
	_wall(Vector3(0.0, 8.0, -41.0), Vector3(36.0, 16.0, 2.0))


## The stern's hull around the engine hall: plated walls with ribs, a roof with the hoist hatch,
## and the breach at the south end.
func _hull() -> void:
	var plate := _tex("hauler_hull", 6.0, true, Color(0.85, 0.8, 0.74), _mat(HULL, 0.6))
	var inner := _mat(HULL_IN, 0.75)
	var rib := _mat(Color("3a3532"), 0.6)
	var oxide := _mat(OXIDE, 0.8)
	var h := ROOF_Y
	# Side walls, north wall, south wall either side of the breach.
	_box(Vector3(-15.0, h * 0.5, -5.0), Vector3(2.0, h, 68.0), inner, true)
	_box(Vector3(15.0, h * 0.5, -5.0), Vector3(2.0, h, 68.0), inner, true)
	_box(Vector3(0.0, h * 0.5, -39.0), Vector3(32.0, h, 2.0), inner, true)
	var seg := (14.0 - BREACH_HALF)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * (BREACH_HALF + seg * 0.5), h * 0.5, 29.0), Vector3(seg, h, 2.0), plate, true)
	_box(Vector3(0.0, h - 2.5, 29.0), Vector3(BREACH_HALF * 2.0, 5.0, 2.0), plate, true)
	# Torn plating curling out of the breach.
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 2.9, 3.0, 30.6), Vector3(0.2, 6.0, 2.4), oxide, false, self, Basis(Vector3.UP, side * 0.7))
	# The roof, with a hatch over the hoist.
	_box(Vector3(0.0, h + 0.5, -12.0), Vector3(32.0, 1.0, 54.0), inner, true)
	_box(Vector3(0.0, h + 0.5, 26.5), Vector3(32.0, 1.0, 5.0), inner, true)
	_box(Vector3(-13.0, h + 0.5, 19.5), Vector3(6.0, 1.0, 9.0), inner, true)
	_box(Vector3(3.0, h + 0.5, 19.5), Vector3(18.0, 1.0, 9.0), inner, true)
	# Outside, the hull's skin over all of it, and the long cowl over the engine.
	_box(Vector3(0.0, h + 1.2, -12.0), Vector3(33.0, 0.4, 56.0), plate, false)
	_box(Vector3(0.0, h + 3.5, -20.0), Vector3(16.0, 4.0, 36.0), plate, false)
	# Ribs every six metres down the hall.
	var z := 24.0
	while z > -37.0:
		for side in [-1.0, 1.0]:
			_box(Vector3(side * 13.7, h * 0.5, z), Vector3(0.6, h, 0.8), rib, false)
		_box(Vector3(0.0, h - 0.4, z), Vector3(28.0, 0.8, 0.8), rib, false)
		z -= 6.0
	var name_plate := Label3D.new()
	name_plate.text = "LONG PATIENCE   KV-1120"
	name_plate.font_size = 220
	name_plate.pixel_size = 0.01
	name_plate.modulate = Color("d9d2c2")
	name_plate.outline_size = 0
	name_plate.position = Vector3(-6.5, 8.0, 30.05)
	name_plate.rotation.z = 0.08
	add_child(name_plate)


func _cover() -> void:
	var crate := _mat(Color("4a5052"), 0.7)
	var band := _mat(OXIDE, 0.8)
	for c in COVER:
		_box(c[0], c[1], crate, true)
		_box(c[0] + Vector3(0.0, c[1].y * 0.5 + 0.02, 0.0), Vector3(c[1].x + 0.05, 0.08, c[1].z * 0.3), band, false)
	# Hazard squares under the cargo magnets.
	var hazard := _mat(Color("c9a032"), 0.8)
	for m in MAGNETS:
		for k in 4:
			var a := k * PI * 0.5
			_box(m + Vector3(cos(a) * 1.6, 0.05, sin(a) * 1.6), Vector3(0.3 if k % 2 == 0 else 3.4, 0.03, 3.4 if k % 2 == 0 else 0.3), hazard, false)
	# The guardian's alcove: a low hood of hull plate.
	_box(ALCOVE + Vector3(0.0, 3.2, -1.0), Vector3(5.0, 0.6, 4.0), _mat(HULL_IN, 0.7), false)


func _cage_base() -> void:
	var dark := _mat(Color("2a2c30"), 0.5)
	_box(CAGE + Vector3(0.0, 0.25, 0.0), Vector3(5.0, 0.5, 5.0), dark, true)
	_box(CAGE + Vector3(0.0, 4.0, 0.0), Vector3(5.0, 0.4, 5.0), dark, false)
	# The breaker cabinet on the east wall.
	_box(BREAKER + Vector3(0.6, 1.4, 0.0), Vector3(0.6, 2.0, 1.4), _mat(Color("3d4a52"), 0.6), true)
	_box(BREAKER + Vector3(0.25, 1.9, 0.0), Vector3(0.1, 0.5, 0.2), _glow(Color("ff3a2a"), 1.5), false)
	# Conduits from the cabinet to the cage, along the floor.
	_box(Vector3(6.5, 0.12, -26.0), Vector3(13.0, 0.24, 0.3), dark, false)


## The bridge cabin by the breach: three walls and a doorway on its west side.
func _bridge() -> void:
	var wall := _mat(Color("4f4b45"), 0.7)
	_box(Vector3(8.0, 1.6, 19.5), Vector3(0.3, 3.2, 5.0), wall, true)
	_box(Vector3(8.0, 1.6, 26.5), Vector3(0.3, 3.2, 3.0), wall, true)
	_box(Vector3(11.0, 1.6, 17.0), Vector3(6.0, 3.2, 0.3), wall, true)
	_box(Vector3(11.0, 3.3, 22.0), Vector3(6.0, 0.2, 10.0), wall, false)
	_box(DISTRESS + Vector3(0.6, 0.8, 0.0), Vector3(0.8, 1.6, 1.4), _mat(Color("3d4a52"), 0.6), true)


func _hoist_frame() -> void:
	var rib := _mat(Color("3a3532"), 0.6)
	for x in [-1.8, 1.8]:
		for z in [-1.8, 1.8]:
			_box(HOIST + Vector3(x, ROOF_Y * 0.5, z), Vector3(0.3, ROOF_Y, 0.3), rib, false)


func _magnet_gantry() -> void:
	var rib := _mat(Color("3a3532"), 0.6)
	_box(Vector3(-3.5, MAGNET_Y + 0.9, -3.0), Vector3(0.6, 0.6, 30.0), rib, false)


func _build_lamps() -> void:
	_lamp_mat = _glow(AMBER, 3.0)
	var holder := Node3D.new()
	holder.name = "Lamps"
	add_child(holder)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.35, 0.6)
	var cable := BoxMesh.new()
	cable.size = Vector3(0.05, ROOF_Y - 5.0, 0.05)
	for l in LAMPS:
		st.append_from(bm, 0, Transform3D(Basis(), l))
		st.append_from(cable, 0, Transform3D(Basis(), l + Vector3(0.0, (ROOF_Y - l.y) * 0.5, 0.0)))
		var light := OmniLight3D.new()
		light.light_color = AMBER
		light.omni_range = LAMP_POOL + 2.0
		light.light_energy = 1.6
		light.shadow_enabled = false
		light.position = l + Vector3(0.0, -0.6, 0.0)
		holder.add_child(light)
		_lamps.append(light)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _lamp_mat
	holder.add_child(mi)


func _build_mirrors() -> void:
	var post := _mat(Color("3a3d42"), 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pm := BoxMesh.new()
	pm.size = Vector3(0.4, MIRROR_Y, 0.4)
	for m in MIRRORS:
		st.append_from(pm, 0, Transform3D(Basis(), m[0] + Vector3(0.0, MIRROR_Y * 0.5, 0.0)))
		var body := StaticBody3D.new()
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = pm.size
		sh.shape = bx
		body.position = m[0] + Vector3(0.0, MIRROR_Y * 0.5, 0.0)
		body.add_child(sh)
		add_child(body)
	var posts := MeshInstance3D.new()
	posts.mesh = st.commit()
	posts.material_override = post
	add_child(posts)
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color("c8d4dc")
	silver.metallic = 0.9
	silver.roughness = 0.15
	for i in MIRRORS.size():
		var dish := Node3D.new()
		dish.position = MIRRORS[i][0] + Vector3.UP * MIRROR_Y
		add_child(dish)
		var face := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.35
		cm.height = 0.2
		cm.radial_segments = 12
		face.mesh = cm
		face.material_override = silver
		face.rotation.x = PI * 0.5
		face.position.z = -0.2
		dish.add_child(face)
		var beam := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.2
		bm.bottom_radius = SEE_LIT * tan(acos(SEE_COS))
		bm.height = SEE_LIT
		bm.radial_segments = 10
		bm.cap_top = false
		bm.cap_bottom = false
		beam.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(COLD, 0.16)
		beam.material_override = mat
		# The cone lies along the dish's facing (-Z), its tip at the dish, sloping to the floor.
		beam.rotation.x = -PI * 0.5 + 0.18
		beam.position = Vector3(0.0, -SEE_LIT * 0.5 * sin(0.18), -SEE_LIT * 0.5)
		dish.add_child(beam)
		_dishes.append(dish)
		_beams.append(beam)
		_beam_mats.append(mat)


func _build_cage() -> void:
	_bars = Node3D.new()
	_bars.name = "CageBars"
	add_child(_bars)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bar := CylinderMesh.new()
	bar.top_radius = 0.08
	bar.bottom_radius = 0.08
	bar.height = 3.4
	bar.radial_segments = 6
	var body := StaticBody3D.new()
	_bars.add_child(body)
	for k in 12:
		var a := k * TAU / 12.0
		var at := CAGE + Vector3(cos(a) * CAGE_R, 2.2, sin(a) * CAGE_R)
		st.append_from(bar, 0, Transform3D(Basis(), at))
		var sh := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.15
		cyl.height = 3.4
		sh.shape = cyl
		sh.position = at
		body.add_child(sh)
		_bar_bodies.append(sh)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _glow(COLD, 2.0)
	_bars.add_child(mi)
	_coil_mat = _glow(Color("ff7a3a"), 2.0)
	_coil = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 0.6
	cm.height = 1.8
	cm.radial_segments = 14
	_coil.mesh = cm
	_coil.material_override = _coil_mat
	_coil.rotation.z = PI * 0.5
	_coil.position = CAGE + Vector3(0.0, 1.6, 0.0)
	add_child(_coil)
	_cage_light = OmniLight3D.new()
	_cage_light.omni_range = 7.0
	_cage_light.shadow_enabled = false
	_cage_light.position = CAGE + Vector3(0.0, 3.0, 2.0)
	add_child(_cage_light)
	# The distress beacon's lamp in the bridge cabin.
	_distress_mat = _glow(Color("ff4040"), 0.4)
	var lamp := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.2, 0.2, 0.4)
	lamp.mesh = lm
	lamp.material_override = _distress_mat
	lamp.position = DISTRESS + Vector3(0.5, 1.75, 0.0)
	add_child(lamp)


func _build_hoist() -> void:
	_hoist = Node3D.new()
	_hoist.name = "Hoist"
	_hoist.position = Vector3.ZERO
	add_child(_hoist)
	var deck := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.4, 0.25, 3.4)
	deck.mesh = bm
	deck.material_override = _mat(Color("5a5e60"), 0.6)
	deck.position = HOIST + Vector3(0.0, 0.15, 0.0)
	_hoist.add_child(deck)
	_hoist_coil = MeshInstance3D.new()
	_hoist_coil.mesh = _coil.mesh
	_hoist_coil.material_override = _coil_mat
	_hoist_coil.rotation.z = PI * 0.5
	_hoist_coil.position = HOIST + Vector3(0.0, 0.9, 0.0)
	_hoist.add_child(_hoist_coil)
	var light := OmniLight3D.new()
	light.light_color = AMBER
	light.light_energy = 0.9
	light.omni_range = 5.0
	light.shadow_enabled = false
	light.position = HOIST + Vector3(0.0, 3.0, 0.0)
	add_child(light)


## The cargo magnets: a housing on the gantry, its coil ring glowing when charged. Shoot it.
func _build_magnets() -> void:
	var housing := _mat(Color("5a4a3a"), 0.6)
	for i in MAGNETS.size():
		var at: Vector3 = MAGNETS[i] + Vector3.UP * MAGNET_Y
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.position = at
		body.set_meta("on_hit", fire_magnet.bind(i))
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(2.4, 0.8, 2.4)
		sh.shape = bx
		body.add_child(sh)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bx.size
		mi.mesh = bm
		mi.material_override = housing
		body.add_child(mi)
		var mat := _glow(Color("ffd06a"), 2.2)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.7
		tm.outer_radius = 0.95
		tm.rings = 16
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = mat
		ring.position.y = -0.45
		body.add_child(ring)
		add_child(body)
		_magnet_mats.append(mat)
