class_name TuningCrown
extends LoomScene
## Repair 7, "Between the beats" (production pack, milestone D2): the Tuning Crown, north of the
## Loom Expanse's overlook, down a drop only the suit thrusters make safe. Ilse Marrow's tuned nav
## core is in the Crown's heart, and the Cantor keeps it.
##
## Local space, Juno coming in at the south (+Z), looking north:
##   the lane       from the way in up to the terrace wall;
##   the bays       west and east of the lane, each with a resonator stone. The Crown beats
##                  every two seconds (a deep knock, and a pale light on each stone's crown); each
##                  stone beats at its own rate (its band flashes, and it knocks). Retune a stone
##                  until it beats with the Crown and after two beats in step it locks.
##                  Each lock retensions the paths: the old span from the lane into that bay
##                  closes, a shortcut from the bay to the terrace opens, and the terrace's own
##                  gate to the lane opens, so there is always a way out. A live ridge crosses
##                  each bay;
##   the terrace    the third stone, in front of the Crown's door. With all three locked the
##                  door opens;
##   the arena      the Crown's floor, under its arches: the Cantor (Cantor) slung from four
##                  anchors at the rim, and two shear walls that slide across from its second
##                  phase. Going down in the arena brings Juno back at its door with the fight
##                  set back to the start of the phase she was in.
## The core comes away when the Cantor falls, and goes home in Juno's pack
## (Game.deliver_component("nav_core")).
## Flags: reached_crown, crown_res_0..2, crown_arena, cantor_phase, cantor_down, crown_core.

const SEED := 131
const FIBRE := Color("7a5038")
const FIBRE_DARK := Color("4a3328")
const DUST := Color("4a3a48")
const STONE := Color("2a2a30")
const TEAL := Color("3fe0c8")
const PALE := Color("e6dcff")
const AMBER := Color("ffb04a")
const CROWN_GLOW := Color("8fd8ff")
## The Crown's beat, and the rates a stone can be tuned through.
const BEAT := 2.0
const RATES := [1.0, 1.5, 2.0, 2.5, 3.0]
const IN_STEP := 2
const RESONATORS := [Vector3(-40.0, 0.0, 30.0), Vector3(40.0, 0.0, 30.0), Vector3(8.0, 0.0, 2.0)]
## Where each stone's rate starts (an index into RATES), never in step.
const START := [4, 0, 3]
## Curtains of taut fibre across the openings: [centre, size].
const CURTAINS := {
	"old_w": [Vector3(-16.0, 2.5, 55.0), Vector3(1.0, 5.0, 6.0)],
	"old_e": [Vector3(16.0, 2.5, 55.0), Vector3(1.0, 5.0, 6.0)],
	"short_w": [Vector3(-16.0, 2.5, 5.0), Vector3(1.0, 5.0, 6.0)],
	"short_e": [Vector3(16.0, 2.5, 5.0), Vector3(1.0, 5.0, 6.0)],
	"terrace": [Vector3(0.0, 2.5, 20.0), Vector3(6.0, 5.0, 1.0)],
	"door": [Vector3(0.0, 3.0, -10.0), Vector3(8.0, 6.0, 1.2)],
}
## The live ridges across the bays: [from, to, period, offset, safe spans].
const RIDGES := [
	[Vector3(-58.0, 0.0, 42.0), Vector3(-18.0, 0.0, 42.0), 6.5, 0.0, [[0.42, 0.58]]],
	[Vector3(18.0, 0.0, 42.0), Vector3(58.0, 0.0, 42.0), 6.5, 3.0, [[0.42, 0.58]]],
]
const ARENA := Vector3(0.0, 0.0, -60.0)
const ARENA_R := 28.0
const ARENA_IN := Vector3(0.0, 0.3, -15.0)
const ANCHORS := [Vector3(-21.0, 0.0, -41.0), Vector3(21.0, 0.0, -41.0), Vector3(-21.0, 0.0, -79.0), Vector3(21.0, 0.0, -79.0)]
const ANCHOR_Y := 3.0
## Shear walls: their z, and how far across they slide.
const SHEARS := [-50.0, -70.0]
const SHEAR_SPAN := 18.0
const SHEAR_SIZE := Vector3(10.0, 3.2, 1.4)
const SHEAR_DAMAGE := 20.0
const USE_RANGE := 2.6

var cantor: Cantor
var ridges: Array[LoomRidge] = []
## Each stone's rate index, beats in step, and timers (tests read and set these).
var rate := [4, 0, 3]
var in_step := [0, 0, 0]
var beat_t := 0.0
var _res_t := [0.0, 0.0, 0.0]
var _band_mats: Array[StandardMaterial3D] = []
var _ref_mats: Array[StandardMaterial3D] = []
var _curtains := {}
var _anchor_mats: Array[StandardMaterial3D] = []
var _anchor_flash: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _shears: Array[Node3D] = []
var _shear_mats: Array[StandardMaterial3D] = []
## Each wall's side (-1 or 1) and where it's sliding from/to.
var _shear_side: Array[float] = [-1.0, 1.0]
var _shear_t: Array[float] = [1.0, 1.0]
var _shear_hit: Array[bool] = [false, false]
var _core: MeshInstance3D
var _t := 0.0


func _init() -> void:
	entry = Vector3(0.0, 0.3, 72.0)
	entry_yaw = 0.0
	exit_point = Vector3(0.0, 0.0, 77.5)
	exit_label = "Climb back up to the Loom Expanse"
	goal = RESONATORS[0] + Vector3(0.0, 2.0, 0.0)
	look = {
		"fog_light_color": Color("6b4a78"), "fog_density": 0.004,
		"ambient_light_color": Color("a088c8"), "ambient_light_energy": 0.8,
		"background_energy_multiplier": 0.6,
		"sun_energy": 0.7, "sun_color": Color("ffb48c"), "sun_rotation": Vector3(-12.0, 175.0, 0.0),
	}


func build() -> void:
	for i in 3:
		rate[i] = START[i]
	_begin_batch()
	_rng.seed = SEED
	_ground()
	_walls()
	_crown_arches()
	_stones()
	_arena()
	_commit_strands(_tex("fungus_stem", 0.5, false, FIBRE.lightened(0.35), _mat(FIBRE, 0.85)))
	_end_batch()
	_build_curtains()
	_build_resonators()
	_build_anchors()
	_build_shears()
	_build_core()
	for r in RIDGES:
		var ridge := LoomRidge.new()
		ridge.from = r[0]
		ridge.to = r[1]
		ridge.period = r[2]
		ridge.offset = r[3]
		ridge.safe = r[4]
		ridge.name = "Ridge%d" % ridges.size()
		add_child(ridge)
		ridges.append(ridge)
	if in_arena():
		entry = ARENA_IN
	_sync()
	Game.flag_changed.connect(_on_flag_changed)


func _ready() -> void:
	super()
	if not Game.flags.get("reached_crown", false):
		Game.set_flag("reached_crown")
		_say(Story.CROWN_ARRIVE)


func _exit_tree() -> void:
	Game.set_region_objective("")


func spawn_residents(main: Node) -> Array[Enemy]:
	var out := super(main)
	if in_arena() and not cantor_down():
		out.append(wake_cantor(main))
	return out


# --- State ---------------------------------------------------------------------------------

func calibrated(i: int) -> bool:
	return Game.flags.get("crown_res_%d" % i, false) == true


func calibrated_count() -> int:
	var n := 0
	for i in 3:
		if calibrated(i):
			n += 1
	return n


func in_arena() -> bool:
	return Game.flags.get("crown_arena", false) == true


func cantor_down() -> bool:
	return Game.flags.get("cantor_down", false) == true


func done() -> bool:
	return Game.flags.get("crown_core", false) == true or Game.is_repaired("navigation") or Game.delivered("nav_core")


func active() -> bool:
	return Game.current_repair() == "navigation" and not done()


func curtain_open(id: String) -> bool:
	match id:
		"old_w":
			return not calibrated(0)
		"old_e":
			return not calibrated(1)
		"short_w":
			return calibrated(0)
		"short_e":
			return calibrated(1)
		"terrace":
			return calibrated(0) or calibrated(1)
		"door":
			return calibrated_count() == 3
	return false


func rate_of(i: int) -> float:
	return RATES[rate[i]]


func in_tune(i: int) -> bool:
	return is_equal_approx(rate_of(i), BEAT)


# --- Actions -------------------------------------------------------------------------------

## Steps a stone to its next rate, and starts it on the Crown's beat so the two can be compared.
func retune(i: int) -> void:
	if calibrated(i):
		return
	rate[i] = (rate[i] + 1) % RATES.size()
	in_step[i] = 0
	_res_t[i] = beat_t
	Sfx.play("resonator_tick", to_global(RESONATORS[i] + Vector3.UP * 2.0), -4.0, 0.0)


func _lock(i: int) -> void:
	Game.set_flag("crown_res_%d" % i)
	Sfx.play("resonator_lock", to_global(RESONATORS[i] + Vector3.UP * 2.0), 0.0, 0.0)
	_say(Story.CROWN_LOCKS[calibrated_count() - 1])


## Brings the Cantor down from the arches (first time into the arena, or after a load there).
func wake_cantor(main: Node) -> Cantor:
	if cantor and is_instance_valid(cantor) and not cantor.dead:
		return cantor
	cantor = main.spawn_enemy("cantor", to_global(ARENA), "", self) as Cantor
	cantor.reset_to(int(Game.flags.get("cantor_phase", 0)))
	cantor.phase_changed.connect(_on_phase)
	cantor.note.connect(_on_note)
	cantor.died.connect(func(_e): _on_cantor_down())
	return cantor


func strike_anchor(i: int) -> void:
	if cantor == null or not is_instance_valid(cantor) or cantor.dead:
		return
	if cantor.anchor_struck():
		_anchor_flash[i] = 1.5
		Sfx.play("cantor_anchor", to_global(ANCHORS[i] + Vector3.UP * ANCHOR_Y), 0.0, 0.0)
		if not Game.flags.get("cantor_interrupted", false):
			Game.set_flag("cantor_interrupted")
			_say(Story.CANTOR_INTERRUPT)
	else:
		_anchor_flash[i] = -0.6
		Sfx.play("hit_armor", to_global(ANCHORS[i] + Vector3.UP * ANCHOR_Y), -2.0, 0.1)


func take_core() -> void:
	if not cantor_down() or done():
		return
	Game.set_flag("crown_core")
	Game.deliver_component("nav_core")
	Game.find_log(Story.log_at("navigation", "component"))
	Sfx.play("cell_pickup", to_global(ARENA + Vector3.UP), 0.0, 0.0)
	_say(Story.CROWN_CORE)
	_sync()


## Juno went down: in the arena, the fight goes back to the start of this phase.
func on_player_down() -> void:
	if in_arena():
		reset_fight()


func reset_fight() -> void:
	if cantor and is_instance_valid(cantor) and not cantor.dead:
		cantor.reset_to(int(Game.flags.get("cantor_phase", 0)))
	for k in _shears.size():
		_shear_t[k] = 1.0
		_shears[k].position.x = _shear_side[k] * SHEAR_SPAN
	for e in get_tree().get_nodes_in_group("chord_singers"):
		if is_ancestor_of(e):
			e.queue_free()


func interaction(pos: Vector3) -> Dictionary:
	var p := to_local(pos)
	for i in 3:
		if Vector2(p.x - RESONATORS[i].x, p.z - RESONATORS[i].z - 1.8).length() < USE_RANGE:
			if calibrated(i):
				return {"label": "Resonator: beating with the Crown"}
			return {"label": "[E] Retune the resonator", "action": retune.bind(i)}
	if Vector2(p.x - CURTAINS["door"][0].x, p.z - CURTAINS["door"][0].z - 1.4).length() < USE_RANGE + 1.0 and not curtain_open("door"):
		return {"label": "The Crown's door: fibres drawn tight, humming three notes out of step (%d of 3 in tune)" % calibrated_count()}
	if cantor_down() and not done() and Vector2(p.x - ARENA.x, p.z - ARENA.z).length() < USE_RANGE + 0.6:
		return {"label": "[E] Take Ilse Marrow's nav core", "action": take_core}
	return {}


# --- Running -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	beat_t += delta
	var crown_beat := false
	if beat_t >= BEAT:
		beat_t -= BEAT
		crown_beat = true
		Sfx.play("crown_tick", to_global(ARENA + Vector3.UP * 20.0), -6.0, 0.0)
	var p := _player()
	for i in 3:
		_tick_resonator(i, delta, crown_beat, p)
	for i in _anchor_mats.size():
		var f: float = _anchor_flash[i]
		_anchor_flash[i] = move_toward(f, 0.0, delta)
		_anchor_mats[i].emission = Color(1.0, 0.3, 0.2) if f < 0.0 else TEAL
		_anchor_mats[i].emission_energy_multiplier = 6.0 if absf(f) > 0.0 else (2.5 if cantor and is_instance_valid(cantor) and cantor.in_gap() else 0.8)
	_tick_shears(delta, p)
	if p and not in_arena() and curtain_open("door") and to_local(p.global_position).z < ARENA_IN.z + 1.0:
		Game.set_flag("crown_arena")
		entry = ARENA_IN
		var main := get_parent()
		if main and not cantor_down():
			wake_cantor(main)
			_say(Story.CANTOR_RISES)
	if _core:
		_core.visible = cantor_down() and not done()
	_update_goal()


func _tick_resonator(i: int, delta: float, crown_beat: bool, p: Node3D) -> void:
	_ref_mats[i].emission_energy_multiplier = move_toward(_ref_mats[i].emission_energy_multiplier, 0.3, delta * 8.0)
	if crown_beat:
		_ref_mats[i].emission_energy_multiplier = 5.0
	if calibrated(i):
		_band_mats[i].emission = TEAL
		_band_mats[i].emission_energy_multiplier = 2.5 + 0.5 * sin(_t * 3.0)
		return
	_band_mats[i].emission = AMBER
	_band_mats[i].emission_energy_multiplier = move_toward(_band_mats[i].emission_energy_multiplier, 0.3, delta * 8.0)
	_res_t[i] += delta
	if _res_t[i] >= rate_of(i):
		_res_t[i] -= rate_of(i)
		_band_mats[i].emission_energy_multiplier = 5.0
		if p and p.global_position.distance_to(to_global(RESONATORS[i])) < 30.0:
			Sfx.play("resonator_tick", to_global(RESONATORS[i] + Vector3.UP * 2.0), -6.0, 0.0)
	if crown_beat:
		if in_tune(i):
			in_step[i] += 1
			if in_step[i] >= IN_STEP:
				_lock(i)
		else:
			in_step[i] = 0


func _tick_shears(delta: float, p: Node3D) -> void:
	var live := cantor != null and is_instance_valid(cantor) and not cantor.dead and cantor.phase >= Cantor.Phase.RESPOND
	for k in _shears.size():
		_shear_mats[k].emission_energy_multiplier = move_toward(_shear_mats[k].emission_energy_multiplier, 0.4, delta * 3.0)
		if not live:
			continue
		if _shear_t[k] < 1.0:
			_shear_t[k] = minf(_shear_t[k] + delta / 1.4, 1.0)
			var x := lerpf(-_shear_side[k], _shear_side[k], _shear_t[k]) * SHEAR_SPAN
			_shears[k].position.x = x
			if p and not _shear_hit[k]:
				var off := to_local(p.global_position) - _shears[k].position
				if absf(off.x) < SHEAR_SIZE.x * 0.5 + 0.4 and absf(off.z) < SHEAR_SIZE.z * 0.5 + 0.6 and off.y < SHEAR_SIZE.y:
					_shear_hit[k] = true
					p.take_damage(SHEAR_DAMAGE, _shears[k].global_position)
					if "velocity" in p:
						p.velocity += Vector3(0.0, 4.0, signf(off.z) * 7.0)


func _on_note(which: int) -> void:
	if cantor == null or cantor.phase < Cantor.Phase.RESPOND:
		return
	# The seam glows on the high note; on the middle note the walls slide across.
	if which == 0:
		for m in _shear_mats:
			m.emission_energy_multiplier = 5.0
	elif which == 1:
		for k in _shears.size():
			_shear_side[k] = -_shear_side[k]
			_shear_t[k] = 0.0
			_shear_hit[k] = false
		Sfx.play("ridge_heave", to_global(ARENA), 0.0, 0.0)


func _on_phase(p: int) -> void:
	Game.set_flag("cantor_phase", p)
	if p == Cantor.Phase.RESPOND:
		_say(Story.CANTOR_RESPOND)
	elif p == Cantor.Phase.RESOLVE:
		_say(Story.CANTOR_RESOLVE)
		var main := get_parent()
		if main and main.has_method("spawn_enemy"):
			main.spawn_enemy("chord_singer", to_global(ARENA + Vector3(0.0, 0.0, 16.0)), "", self)


func _on_cantor_down() -> void:
	Game.set_flag("cantor_down")
	Game.set_flag("cantor_phase", 0)
	_say(Story.CANTOR_DOWN)


func _on_flag_changed(_flag: String, _value: Variant) -> void:
	_sync()


func _update_goal() -> void:
	if not active():
		Game.set_region_objective("")
		goal = exit_point + Vector3(0.0, 1.0, 0.0)
		return
	if calibrated_count() < 3:
		var next := 0
		while calibrated(next):
			next += 1
		# The terrace stone is reached through a bay's shortcut: lead to the bay first.
		if next == 2 and not (curtain_open("terrace")):
			next = 0
		goal = RESONATORS[next] + Vector3(0.0, 2.0, 0.0)
		Game.set_region_objective("Tune the resonators to the Crown's beat: %d of 3. Retune a stone until its flash keeps time with the light on top" % calibrated_count())
	elif not in_arena():
		goal = ARENA_IN + Vector3(0.0, 1.5, 0.0)
		Game.set_region_objective("The Crown's door is open. Go in")
	elif not cantor_down():
		goal = ARENA + Vector3(0.0, Cantor.HEART_Y, 0.0)
		if cantor and is_instance_valid(cantor) and cantor.phase == Cantor.Phase.RESOLVE:
			Game.set_region_objective("Shoot the Cantor's heart in the quiet after its low note, once its petals are open")
		else:
			Game.set_region_objective("Shoot an anchor in the quiet just after the Cantor's low note, then the heart")
	else:
		goal = ARENA + Vector3(0.0, 1.5, 0.0)
		Game.set_region_objective("Take Ilse Marrow's nav core from the Crown's heart")


func _player() -> Node3D:
	var main := get_parent()
	if main == null or main.get("player") == null:
		return null
	return main.player


func _sync() -> void:
	for id in _curtains:
		var node: Node3D = _curtains[id]
		var open := curtain_open(id)
		node.visible = not open
		for c in node.get_children():
			if c is CollisionObject3D:
				(c as CollisionObject3D).collision_layer = 0 if open else Game.LAYER_WORLD


# --- Building ------------------------------------------------------------------------------

func _ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(140.0, 200.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0.0, 0.0, -18.0)
	mi.material_override = _tex("shatterlands_ground", 2.5, true, Color(0.95, 0.78, 0.85), _mat(DUST, 0.9))
	add_child(mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(140.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, -18.0)
	body.add_child(shape)
	add_child(body)


## The rim, the bay walls with their openings, the terrace wall and the Crown's wall.
func _walls() -> void:
	var rim := _mat(FIBRE_DARK, 0.9)
	# The rim of the whole place.
	for w in [[Vector3(-64.0, 8.0, -18.0), Vector3(4.0, 16.0, 200.0)], [Vector3(64.0, 8.0, -18.0), Vector3(4.0, 16.0, 200.0)],
			[Vector3(0.0, 8.0, 82.0), Vector3(132.0, 16.0, 4.0)], [Vector3(0.0, 8.0, -114.0), Vector3(132.0, 16.0, 4.0)]]:
		_box(w[0], w[1], rim, true)
	var wall := _fibre_world_mat()
	# Bay walls at x = +-16 from z -10 to 70, with gaps at z 52..58 (old span) and 2..8 (shortcut).
	for side in [-1.0, 1.0]:
		for seg in [[-10.0, 2.0], [8.0, 52.0], [58.0, 70.0]]:
			var z0: float = seg[0]
			var z1: float = seg[1]
			_box(Vector3(side * 16.0, 3.0, (z0 + z1) * 0.5), Vector3(1.6, 6.0, z1 - z0), wall, true)
		# The bays' south walls, closing them off from the way in.
		_box(Vector3(side * 40.0, 3.0, 70.0), Vector3(48.0, 6.0, 1.6), wall, true)
	# The terrace wall across the lane at z 20, with its gate in the middle.
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 9.5, 3.0, 20.0), Vector3(13.0, 6.0, 1.6), wall, true)
	# The Crown's wall at z -10 with its door; beyond it the arena.
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 33.0, 5.0, -10.0), Vector3(58.0, 10.0, 2.0), wall, true)
	for side in [-1.0, 1.0]:
		_arch(Vector3(side * 4.5, 0.0, -9.0), Vector3(side * 4.5, 0.0, -11.0), 9.0, 1.4, 3, 6)
	_arch(Vector3(-5.0, 7.0, -10.0), Vector3(5.0, 7.0, -10.0), 3.0, 1.6, 3, 8)


func _fibre_world_mat() -> Material:
	return _tex("fungus_stem", 1.5, true, FIBRE.lightened(0.35), _mat(FIBRE, 0.85))


## The Crown itself: arches the height of a tower over the arena, a column of light in the middle.
func _crown_arches() -> void:
	for i in 4:
		var a := i * PI / 4.0
		var d := Vector3(cos(a), 0.0, sin(a)) * 46.0
		_arch(ARENA - d, ARENA + d, 70.0, 7.0, 4, 14)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.5
	cm.bottom_radius = 3.0
	cm.height = 60.0
	cm.radial_segments = 12
	beam.mesh = cm
	var m := _glow(CROWN_GLOW, 3.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(CROWN_GLOW, 0.35)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = m
	beam.position = ARENA + Vector3(0.0, 42.0, 0.0)
	add_child(beam)
	# Braids along the bay walls' crests and over the lane.
	for z in [60.0, 38.0]:
		_arch(Vector3(-62.0, 10.0, z), Vector3(-17.0, 6.0, z), 10.0, 2.2, 3, 10)
		_arch(Vector3(17.0, 6.0, z), Vector3(62.0, 10.0, z), 10.0, 2.2, 3, 10)


## Stepping stones on the ridges' safe spans and a few boulders in the bays.
func _stones() -> void:
	var stone := _mat(STONE, 0.7)
	for r in RIDGES:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var mid := a.lerp(b, 0.5)
		_box(mid + Vector3(0.0, 0.04, 0.0), Vector3(6.0, 0.08, 4.4), stone, false)
	for b in [Vector3(-50.0, 0.0, 20.0), Vector3(-52.0, 0.0, 58.0), Vector3(50.0, 0.0, 20.0), Vector3(52.0, 0.0, 58.0)]:
		_box(b + Vector3(0.0, 1.2, 0.0), Vector3(3.0, 2.4, 2.6), _basalt(6.0), true)


## The arena's floor ring and the anchor pylons at its rim, with cables to where the Cantor hangs.
func _arena() -> void:
	var ring := _mat(Color("3a2e3c"), 0.8)
	_box(ARENA + Vector3(0.0, 0.03, 0.0), Vector3(ARENA_R * 2.0, 0.06, ARENA_R * 2.0), ring, false)
	for a in ANCHORS:
		for k in 3:
			var ang := k * TAU / 3.0
			_strand(a + Vector3(cos(ang) * 1.4, -0.5, sin(ang) * 1.4), a + Vector3(0.0, 9.0, 0.0), 0.7)
		_strand(a + Vector3(0.0, 8.0, 0.0), ARENA + Vector3(0.0, Cantor.HEART_Y + 3.0, 0.0), 0.35)
		_box(a + Vector3(0.0, 1.5, 0.0), Vector3(2.0, 3.0, 2.0), _mat(FIBRE_DARK, 0.9), true)


func _build_curtains() -> void:
	var lace := _glow(PALE, 0.8)
	lace.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lace.albedo_color = Color(PALE, 0.6)
	for id in CURTAINS:
		var c: Array = CURTAINS[id]
		var node := Node3D.new()
		node.name = "Curtain_" + String(id)
		add_child(node)
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.position = c[0]
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = c[1]
		sh.shape = bx
		body.add_child(sh)
		node.add_child(body)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(maxf(c[1].x, 0.2) if c[1].x > c[1].z else 0.15, c[1].y, maxf(c[1].z, 0.2) if c[1].z > c[1].x else 0.15)
		mi.mesh = bm
		mi.material_override = lace
		mi.position = c[0]
		node.add_child(mi)
		_curtains[id] = node


func _build_resonators() -> void:
	var stone := _mat(STONE, 0.6)
	for i in 3:
		var at: Vector3 = RESONATORS[i]
		var body := StaticBody3D.new()
		body.position = at + Vector3(0.0, 1.4, 0.0)
		var sh := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.0
		cyl.height = 2.8
		sh.shape = cyl
		body.add_child(sh)
		add_child(body)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.7
		cm.bottom_radius = 1.1
		cm.height = 2.8
		cm.radial_segments = 8
		mi.mesh = cm
		mi.material_override = stone
		body.add_child(mi)
		var band_mat := _glow(AMBER, 0.3)
		var band := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.95
		tm.outer_radius = 1.15
		tm.rings = 14
		tm.ring_segments = 5
		band.mesh = tm
		band.material_override = band_mat
		band.position = Vector3(0.0, -0.2, 0.0)
		body.add_child(band)
		var ref_mat := _glow(PALE, 0.3)
		var ref := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.25
		sm.height = 0.5
		sm.radial_segments = 8
		sm.rings = 4
		ref.mesh = sm
		ref.material_override = ref_mat
		ref.position = Vector3(0.0, 1.7, 0.0)
		body.add_child(ref)
		_band_mats.append(band_mat)
		_ref_mats.append(ref_mat)


## The anchors' knots: shoot one in the quiet after the low note.
func _build_anchors() -> void:
	for i in ANCHORS.size():
		var at: Vector3 = ANCHORS[i] + Vector3.UP * ANCHOR_Y
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.position = at + (ARENA - ANCHORS[i]).normalized() * 1.1
		body.set_meta("on_hit", strike_anchor.bind(i))
		var sh := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.8
		sh.shape = sp
		body.add_child(sh)
		var mat := _glow(TEAL, 0.8)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.8
		sm.height = 1.6
		sm.radial_segments = 10
		sm.rings = 5
		mi.mesh = sm
		mi.material_override = mat
		body.add_child(mi)
		add_child(body)
		_anchor_mats.append(mat)


func _build_shears() -> void:
	for k in SHEARS.size():
		var wall := Node3D.new()
		wall.name = "Shear%d" % k
		wall.set_meta("no_batch", true)
		wall.position = Vector3(_shear_side[k] * SHEAR_SPAN, SHEAR_SIZE.y * 0.5, SHEARS[k])
		add_child(wall)
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = SHEAR_SIZE
		sh.shape = bx
		body.add_child(sh)
		wall.add_child(body)
		var mat := _glow(Color("e07ad8"), 0.4)
		mat.albedo_color = FIBRE
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = SHEAR_SIZE
		mi.mesh = bm
		mi.material_override = mat
		wall.add_child(mi)
		_shears.append(wall)
		_shear_mats.append(mat)


func _build_core() -> void:
	_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 10
	sm.rings = 5
	_core.mesh = sm
	_core.material_override = _glow(TEAL, 4.0)
	_core.position = ARENA + Vector3(0.0, 1.0, 0.0)
	_core.visible = false
	add_child(_core)
	var light := OmniLight3D.new()
	light.light_color = TEAL
	light.light_energy = 1.5
	light.omni_range = 14.0
	light.shadow_enabled = false
	light.position = ARENA + Vector3(0.0, 4.0, 0.0)
	add_child(light)
