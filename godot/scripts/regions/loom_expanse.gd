class_name LoomExpanse
extends ShatterScene
## The first pocket of the Loom Expanse (production pack, milestone C): through a cleft in the
## Shatterlands' west rim, a valley roofed by arches of braided fibre, the Loom's ridges where
## they break the surface. Far to the north, framed by a gap in the rim, the Tuning Crown.
##
## One loop round a central massif of woven fibre (local space; Juno comes in at the south mouth,
## +Z, looking north):
##   the Weave (west)      soft woven floor over bare stone stepping slabs, crossed by two live
##                         ridges (LoomRidge) and hunted from below by ridge divers;
##   the Listening Bowl    the north hollow: a chord singer walking between resonant patches,
##                         basalt boulders to break its voice, the overlook on the Tuning Crown,
##                         the survey team's locker (weave grips) and, up a ledge, their marker
##                         (lore: "Tension memory");
##   the Spindles (east)   a lane through fibre pillars where pinweavers string trip-threads;
##   the shortcut          a tunnel through the massif, laced shut at its south end and opened by
##                         cutting the tension knot at its north end;
##   the bypass            a lane behind the Weave's west wall, opened by the signal flag find
##                         (WalkFinds "signal_flag").
## State in Game.flags: reached_loom, loom_crown_seen, weave_grips, loom_shortcut, seen_diver,
## seen_pinweaver, seen_singer (and find_signal_flag).

const SEED := 97
const FIBRE := Color("7a5038")
const FIBRE_DARK := Color("4a3328")
const DUST := Color("4a3a48")
const BLOOM := Color("d050d0")
const STONE := Color("2a2a30")
const AMBER := Color("e8a44e")
const CROWN_GLOW := Color("8fd8ff")

## The massif in the middle of the loop: [centre, size] for each half, and the tunnel between.
const MASSIF_Z := 24.0
const TUNNEL_HALF := 2.0
const TUNNEL_TOP := 4.2
const KNOT := Vector3(0.0, 2.2, -MASSIF_Z - 0.8)
const CURTAIN := Vector3(0.0, 0.0, MASSIF_Z + 0.4)
## The Weave: where ridge divers can travel (x0, z0, x1, z1), and the stone slabs in it (centre,
## half size) that they can't.
const WEAVE := Rect2(-46.0, -30.0, 33.0, 60.0)
const STONES := [
	[Vector2(-26.0, 26.0), Vector2(1.6, 1.4)], [Vector2(-30.0, 21.0), Vector2(1.4, 1.6)],
	[Vector2(-38.0, 12.0), Vector2(2.2, 2.4)], [Vector2(-33.0, 5.0), Vector2(1.5, 1.4)],
	[Vector2(-28.0, -1.0), Vector2(1.4, 1.5)], [Vector2(-24.0, -6.0), Vector2(1.5, 1.4)],
	[Vector2(-18.0, -12.0), Vector2(2.2, 2.4)], [Vector2(-22.0, -19.0), Vector2(1.4, 1.5)],
	[Vector2(-27.0, -25.0), Vector2(1.6, 1.5)],
]
## The live ridges crossing the Weave: from, to, period, offset, safe spans (where a slab sits).
const RIDGES := [
	[Vector3(-46.0, 0.0, 12.0), Vector3(-13.0, 0.0, 12.0), 6.0, 0.0, [[0.17, 0.30]]],
	[Vector3(-13.0, 0.0, -12.0), Vector3(-46.0, 0.0, -12.0), 7.5, 3.0, [[0.0, 0.14]]],
]
## The Spindles: fibre pillars down the east lane, [x, z, radius, height].
const SPINDLES := [
	[19.0, 26.0, 0.9, 9.0], [37.0, 22.0, 1.0, 11.0], [27.0, 15.0, 0.7, 8.0],
	[19.0, 8.0, 0.8, 10.0], [37.0, 4.0, 0.9, 9.0], [28.0, -3.0, 0.7, 7.0],
	[19.0, -10.0, 1.0, 12.0], [37.0, -14.0, 0.8, 10.0], [27.0, -21.0, 0.8, 8.0],
	[20.0, -28.0, 0.9, 9.0], [36.0, -30.0, 1.0, 11.0],
]
## The Listening Bowl: the singer's resonant patches, the boulders that break its voice.
const PATCHES := [Vector3(-16.0, 0.0, -54.0), Vector3(0.0, 0.0, -64.0), Vector3(16.0, 0.0, -54.0)]
const BOULDERS := [[Vector3(-8.0, 0.0, -46.0), Vector3(3.4, 3.6, 2.6)], [Vector3(9.0, 0.0, -60.0), Vector3(3.0, 3.4, 3.2)], [Vector3(-24.0, 0.0, -64.0), Vector3(3.6, 3.2, 2.8)], [Vector3(24.0, 0.0, -44.0), Vector3(2.8, 3.0, 3.0)]]
const OVERLOOK := Vector3(0.0, 0.0, -74.0)
## The survey team: their locker in the bowl's south-west, their marker up the north-east ledge.
const LOCKER := Vector3(-40.0, 0.0, -62.0)
const LEDGE := [Vector3(41.0, 1.5, -66.0), Vector3(14.0, 3.0, 14.0)]
const MARKER := Vector3(43.0, 3.0, -68.0)
## The bypass lane behind the Weave's west wall, and where it's laced shut.
const BYPASS_GATE := Vector3(-52.0, 0.0, 31.0)
## The Tuning Crown, far off in the north (out of reach in this pocket).
const CROWN := Vector3(0.0, 0.0, -250.0)
const USE_RANGE := 2.6
const SEE_RANGE := 16.0

var ridges: Array[LoomRidge] = []
var curtain: Node3D
var knot: Node3D
var bypass: Node3D
var locker_lid: Node3D
var _strands: Array[Transform3D] = []
var _knot_mat: StandardMaterial3D
var _t := 0.0


func _init() -> void:
	entry = Vector3(0.0, 0.3, 60.0)
	entry_yaw = 0.0
	exit_point = Vector3(0.0, 0.0, 67.0)
	exit_label = "Go back east to the Shatterlands"
	goal = OVERLOOK + Vector3(0.0, 1.5, 0.0)
	residents = [
		["ridge_diver", Vector3(-32.0, 0.0, 18.0)],
		["ridge_diver", Vector3(-20.0, 0.0, -22.0)],
		["pinweaver", Vector3(28.0, 0.0, 10.0)],
		["pinweaver", Vector3(28.0, 0.0, -16.0)],
		["chord_singer", PATCHES[0]],
	]
	look = {
		"fog_light_color": Color("6b4a78"), "fog_density": 0.0035,
		"ambient_light_color": Color("a088c8"), "ambient_light_energy": 0.85,
		"background_energy_multiplier": 0.6,
		"sun_energy": 0.75, "sun_color": Color("ffb48c"), "sun_rotation": Vector3(-14.0, 165.0, 0.0),
	}


func build() -> void:
	_begin_batch()
	_rng.seed = SEED
	_ground()
	_rim_walls()
	_mouth()
	_massif()
	_weave()
	_spindles()
	_bowl()
	_crown()
	_overhead()
	_build_strands()
	_blooms()
	_end_batch()
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
	_sync()
	Game.flag_changed.connect(_on_flag_changed)


func _ready() -> void:
	super()
	if not Game.flags.get("reached_loom", false):
		Game.set_flag("reached_loom")
		_say(Story.LOOM_ARRIVE)


func _on_flag_changed(_flag: String, _value: Variant) -> void:
	_sync()


func _process(delta: float) -> void:
	_t += delta
	if _knot_mat:
		_knot_mat.emission_energy_multiplier = 1.5 + 1.2 * sin(_t * 3.0)
	var main := get_parent()
	if main == null or main.get("player") == null or main.player.dead:
		return
	var at: Vector3 = to_local(main.player.global_position)
	if not Game.flags.get("loom_crown_seen", false) and Vector2(at.x - OVERLOOK.x, at.z - OVERLOOK.z).length() < 9.0:
		Game.set_flag("loom_crown_seen")
		_say(Story.LOOM_CROWN)
	_first_sightings(main.player.global_position)
	_update_goal()


## The first time Juno gets a good look at each Loom creature, she and HOB size it up.
func _first_sightings(at: Vector3) -> void:
	for pair in [["ridge_divers", "seen_diver", Story.DIVER_SEEN], ["pinweavers", "seen_pinweaver", Story.PINWEAVER_SEEN], ["chord_singers", "seen_singer", Story.SINGER_SEEN]]:
		if Game.flags.get(pair[1], false):
			continue
		for e in get_tree().get_nodes_in_group(pair[0]):
			if e.global_position.distance_to(at) < SEE_RANGE and e.is_visible_in_tree():
				Game.set_flag(pair[1])
				_say(pair[2])
				return


## The waypoint: the overlook until Juno has seen the Crown, then the survey locker, then home.
func _update_goal() -> void:
	if not Game.flags.get("loom_crown_seen", false):
		goal = OVERLOOK + Vector3(0.0, 1.5, 0.0)
	elif not Game.flags.get("weave_grips", false):
		goal = LOCKER + Vector3(0.0, 1.2, 0.0)
	else:
		goal = exit_point + Vector3(0.0, 1.0, 0.0)


## Where a ridge diver can travel: the Weave's soft floor, not its stone slabs (world space).
func on_weave(world: Vector3) -> bool:
	var p := to_local(world)
	if not WEAVE.has_point(Vector2(p.x, p.z)):
		return false
	for s in STONES:
		var c: Vector2 = s[0]
		var h: Vector2 = s[1]
		if absf(p.x - c.x) <= h.x + 0.3 and absf(p.z - c.y) <= h.y + 0.3:
			return false
	return true


## Points a pinweaver can anchor a line to (world space): knee-high on each spindle's lane side.
func anchors() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s in SPINDLES:
		out.append(to_global(Vector3(s[0], 0.45, s[1])))
	return out


## The chord singer's resonant patches (world space).
func patches() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in PATCHES:
		out.append(to_global(p))
	return out


func shortcut_open() -> bool:
	return Game.flags.get("loom_shortcut", false)


func bypass_open() -> bool:
	return Game.flags.get("find_signal_flag", false)


## Cuts the tension knot: the curtain at the tunnel's far end goes slack for good.
func cut_knot() -> void:
	if shortcut_open():
		return
	Game.set_flag("loom_shortcut")
	Sfx.play("thread_snap", to_global(KNOT), 0.0, 0.0)
	Sfx.play("thread_snap", to_global(CURTAIN + Vector3.UP * 2.0), -4.0, 0.1)
	_say(Story.LOOM_SHORTCUT)


func open_locker() -> void:
	if Game.flags.get("weave_grips", false):
		return
	Game.set_flag("weave_grips")
	Sfx.play("crawlspace_hatch", to_global(LOCKER), -2.0, 0.0)
	_say(Story.WEAVE_GRIPS)


func read_marker() -> void:
	Game.find_log("loom_survey")
	Sfx.play("log_chime", to_global(MARKER), -4.0, 0.0)


func interaction(pos: Vector3) -> Dictionary:
	var p := to_local(pos)
	if not shortcut_open() and p.distance_to(KNOT + Vector3(0.0, -2.2, -1.2)) < USE_RANGE:
		return {"label": "[E] Cut the tension knot", "action": cut_knot}
	if not shortcut_open() and Vector2(p.x - CURTAIN.x, p.z - CURTAIN.z - 1.2).length() < USE_RANGE:
		return {"label": "Taut fibres, tied off from the far end of the tunnel"}
	if not Game.flags.get("weave_grips", false) and Vector2(p.x - LOCKER.x, p.z - LOCKER.z - 1.4).length() < USE_RANGE:
		return {"label": "[E] Open the survey team's locker", "action": open_locker}
	if not Game.has_log("loom_survey") and p.distance_to(MARKER + Vector3(-1.2, 0.0, 1.2)) < USE_RANGE:
		return {"label": "[E] Read the survey marker", "action": read_marker}
	if not bypass_open() and Vector2(p.x - BYPASS_GATE.x, p.z - BYPASS_GATE.z - 1.0).length() < USE_RANGE:
		return {"label": "Fibres laced across a gap in the wall, humming"}
	return {}


func _sync() -> void:
	if curtain:
		_set_open(curtain, shortcut_open())
	if knot:
		knot.visible = not shortcut_open()
		for c in knot.get_children():
			if c is CollisionObject3D:
				(c as CollisionObject3D).collision_layer = 0 if shortcut_open() else Game.LAYER_WORLD
	if bypass:
		_set_open(bypass, bypass_open())
	if locker_lid:
		locker_lid.rotation.x = -1.6 if Game.flags.get("weave_grips", false) else 0.0


## A collider with nothing to see (what the curtain's and the bypass's strands hold shut).
func _blocker(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.position = pos
	parent.add_child(body)


func _set_open(node: Node3D, open: bool) -> void:
	node.visible = not open
	for c in node.get_children():
		if c is CollisionObject3D:
			(c as CollisionObject3D).collision_layer = 0 if open else Game.LAYER_WORLD


# --- Building ------------------------------------------------------------------------------

func _fibre(metres := 0.6, tint := FIBRE) -> Material:
	return _tex("fungus_stem", metres, false, tint.lightened(0.35), _mat(tint, 0.85))


func _fibre_world(metres := 1.5, tint := FIBRE) -> Material:
	return _tex("fungus_stem", metres, true, tint.lightened(0.35), _mat(tint, 0.85))


## One straight fibre strand from a to b, for the shared multimesh.
func _strand(a: Vector3, b: Vector3, r: float) -> void:
	var y := b - a
	if y.length() < 0.01:
		return
	var up := y.normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var fwd := side.cross(up)
	_strands.append(Transform3D(Basis(side * r, y, fwd * r), (a + b) * 0.5))


## A braided arch from a to b rising `height` over the straight line between them.
func _arch(a: Vector3, b: Vector3, height: float, thick: float, count := 4, segs := 10) -> void:
	var tangent := (b - a).normalized()
	var side := tangent.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var twist := _rng.randf_range(2.0, 4.0)
	for k in count:
		var phase := float(k) / count * TAU
		var r := thick * _rng.randf_range(0.22, 0.34)
		var prev := Vector3.INF
		for i in segs + 1:
			var s := float(i) / segs
			var centre := a.lerp(b, s) + Vector3.UP * height * 4.0 * s * (1.0 - s)
			var normal := side.cross(tangent).normalized()
			var ang := phase + s * twist
			var p := centre + (side * cos(ang) + normal * sin(ang)) * thick * 0.4
			if prev != Vector3.INF:
				_strand(prev, p, r)
			prev = p


func _build_strands() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.15
	mesh.radial_segments = 7
	mesh.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _strands.size()
	for i in _strands.size():
		mm.set_instance_transform(i, _strands[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Strands"
	mmi.multimesh = mm
	mmi.material_override = _fibre(0.5)
	add_child(mmi)


func _ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(140.0, 180.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0.0, 0.0, -10.0)
	mi.material_override = _tex("shatterlands_ground", 2.5, true, Color(0.95, 0.78, 0.85), _mat(DUST, 0.9))
	add_child(mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(140.0, 1.0, 180.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, -10.0)
	body.add_child(shape)
	add_child(body)


## The valley's walls: collision boxes dressed in leaning fibre bundles. The north wall has a
## gap for the overlook; the west wall stands back for the bypass lane, with the Weave's own
## wall inside it.
func _rim_walls() -> void:
	var walls := [
		[Vector3(-60.0, 10.0, -6.0), Vector3(8.0, 20.0, 160.0)],
		[Vector3(60.0, 10.0, -6.0), Vector3(8.0, 20.0, 160.0)],
		[Vector3(-34.0, 10.0, -84.0), Vector3(52.0, 20.0, 8.0)],
		[Vector3(34.0, 10.0, -84.0), Vector3(52.0, 20.0, 8.0)],
		[Vector3(-34.0, 10.0, 72.0), Vector3(56.0, 20.0, 8.0)],
		[Vector3(34.0, 10.0, 72.0), Vector3(56.0, 20.0, 8.0)],
	]
	for w in walls:
		_wall(w[0], w[1])
		_dress_wall(w[0], w[1], 1.0)
	# Behind the overlook rail the ground falls away to a low lip.
	_wall(Vector3(0.0, 1.0, -88.0), Vector3(16.0, 2.0, 2.0))
	_box(OVERLOOK + Vector3(0.0, 0.55, -3.0), Vector3(16.0, 1.1, 0.5), _fibre_world(1.0, FIBRE_DARK), true)
	for x in [-6.0, -2.0, 2.0, 6.0]:
		_strand(OVERLOOK + Vector3(x, 0.0, -3.0), OVERLOOK + Vector3(x + 0.6, 1.4, -3.2), 0.18)
	# The Weave's west wall, with the bypass lane behind it (x -56 to -48).
	_wall(Vector3(-47.0, 4.0, 0.0), Vector3(2.0, 8.0, 60.0))
	_dress_wall(Vector3(-47.0, 4.0, 0.0), Vector3(2.0, 8.0, 60.0), 0.5)
	# The east lane's outer side: thick growth from x 41 to the rim.
	_wall(Vector3(48.5, 5.0, -2.0), Vector3(15.0, 10.0, 64.0))
	_dress_wall(Vector3(48.5, 5.0, -2.0), Vector3(15.0, 10.0, 64.0), 0.6)


## Fibre bundles leaning on a wall's faces, so it reads as a ridge of the Loom.
func _dress_wall(c: Vector3, sz: Vector3, scale: float) -> void:
	var along := Vector3(1.0, 0.0, 0.0) if sz.x > sz.z else Vector3(0.0, 0.0, 1.0)
	var across := Vector3(1.0, 0.0, 1.0) - along
	var length := maxf(sz.x, sz.z)
	var half_w := minf(sz.x, sz.z) * 0.5
	var top := c.y + sz.y * 0.5
	var t := -length * 0.5 + 1.0
	while t < length * 0.5 - 0.5:
		for face in [-1.0, 1.0]:
			var foot: Vector3 = c + along * t + across * face * (half_w + _rng.randf_range(0.2, 1.2))
			foot.y = -0.5
			var head: Vector3 = c + along * (t + _rng.randf_range(-3.0, 3.0)) + across * face * _rng.randf_range(-half_w, half_w * 0.3)
			head.y = top * _rng.randf_range(0.8, 1.3)
			_strand(foot, head, _rng.randf_range(0.45, 0.9) * scale + 0.15)
		t += _rng.randf_range(1.6, 2.6)
	# A couple of long braids along the crest.
	for k in 2:
		var a := c - along * length * 0.5 + across * _rng.randf_range(-half_w, half_w) + Vector3(0.0, top - c.y - 0.5, 0.0)
		_arch(a, a + along * length, _rng.randf_range(1.0, 3.0) * scale, 1.6 * scale, 3, int(length / 6.0) + 2)


## The south mouth: the cleft Juno comes in by from the Shatterlands, closed behind her.
func _mouth() -> void:
	_wall(Vector3(0.0, 10.0, 78.0), Vector3(14.0, 20.0, 4.0))
	for side in [-1.0, 1.0]:
		_arch(Vector3(side * 6.5, 0.0, 74.0), Vector3(side * 5.0, 0.0, 58.0), 13.0, 2.2, 4, 10)
	_arch(Vector3(-7.0, 0.0, 64.0), Vector3(7.0, 0.0, 64.0), 14.0, 2.0, 4, 10)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("f0a0e0")
	lamp.light_energy = 1.2
	lamp.omni_range = 12.0
	lamp.shadow_enabled = false
	lamp.position = Vector3(0.0, 4.0, 66.0)
	add_child(lamp)


## The massif: two woven blocks with the shortcut tunnel between them, roofed over, arched
## lengthwise with braids. The curtain laces the south end; the knot ties it off at the north.
func _massif() -> void:
	var z := MASSIF_Z
	var block := _fibre_world(2.0, FIBRE_DARK)
	_box(Vector3(-7.5, 6.0, 0.0), Vector3(11.0, 12.0, z * 2.0), block, true)
	_box(Vector3(9.0, 6.0, 0.0), Vector3(14.0, 12.0, z * 2.0), block, true)
	_box(Vector3(0.0, (TUNNEL_TOP + 12.0) * 0.5, 0.0), Vector3(TUNNEL_HALF * 2.0, 12.0 - TUNNEL_TOP, z * 2.0), block, true)
	for x in [-11.0, -7.0, -3.0, 3.0, 8.0, 13.0]:
		_arch(Vector3(x, 0.0, z + 2.0), Vector3(x + _rng.randf_range(-2.0, 2.0), 0.0, -z - 2.0), 16.0, 3.2, 4, 14)
	for i in 6:
		var zz := -z + 4.0 + i * (z * 2.0 - 8.0) / 5.0
		_arch(Vector3(-14.0, 0.0, zz), Vector3(16.0, 0.0, zz + _rng.randf_range(-3.0, 3.0)), 13.0, 2.4, 3, 10)
	var glow := OmniLight3D.new()
	glow.light_color = GILLS
	glow.light_energy = 1.4
	glow.omni_range = 14.0
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, 3.0, 0.0)
	add_child(glow)
	_box(Vector3(0.0, 0.03, 0.0), Vector3(TUNNEL_HALF * 2.0 - 0.6, 0.06, z * 2.0), _glow(GILLS, 0.6), false)
	# The curtain: taut strands across the south end, and a body that stops her.
	curtain = Node3D.new()
	curtain.name = "Curtain"
	curtain.set_meta("no_batch", true)
	add_child(curtain)
	var taut := _glow(Color("e6dcff"), 0.9)
	for i in 7:
		var x := -TUNNEL_HALF + 0.25 + i * (TUNNEL_HALF * 2.0 - 0.5) / 6.0
		_box(CURTAIN + Vector3(x, TUNNEL_TOP * 0.5, 0.0), Vector3(0.07, TUNNEL_TOP, 0.07), taut, false, curtain, Basis(Vector3.FORWARD, (i - 3) * 0.12))
	_blocker(curtain, CURTAIN + Vector3(0.0, TUNNEL_TOP * 0.5, 0.0), Vector3(TUNNEL_HALF * 2.0, TUNNEL_TOP, 0.4))
	# The knot: a glowing tangle at the north mouth. Shoot it or cut it by hand.
	knot = Node3D.new()
	knot.name = "Knot"
	knot.set_meta("no_batch", true)
	add_child(knot)
	_knot_mat = _glow(GILLS, 2.0)
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.position = KNOT
	body.set_meta("on_hit", cut_knot)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.8
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.material_override = _knot_mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.55
	cs.shape = ss
	body.add_child(cs)
	knot.add_child(body)
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		_strand(KNOT, KNOT + Vector3(cos(a) * TUNNEL_HALF * 1.1, sin(a) * 1.8, 0.4), 0.06)


## The Weave: the soft woven floor (laid in strips), the stone slabs through it, the live ridges
## (added in build), and the bypass gate in its west wall.
func _weave() -> void:
	var mat := _fibre_world(1.2, Color("6a4a42"))
	var z := WEAVE.position.y
	while z < WEAVE.end.y:
		var w := minf(4.0, WEAVE.end.y - z)
		_box(Vector3(WEAVE.get_center().x + _rng.randf_range(-0.3, 0.3), 0.025, z + w * 0.5), Vector3(WEAVE.size.x, 0.05, w - 0.15), mat, false)
		z += w
	for s in STONES:
		var c: Vector2 = s[0]
		var h: Vector2 = s[1]
		_box(Vector3(c.x, 0.04, c.y), Vector3(h.x * 2.0, 0.08, h.y * 2.0), _basalt(3.0), false)
	# The bypass gate: fibres laced across the gap at the lane's south end.
	bypass = Node3D.new()
	bypass.name = "Bypass"
	bypass.set_meta("no_batch", true)
	add_child(bypass)
	var taut := _glow(Color("e6dcff"), 0.7)
	for i in 6:
		var y := 0.4 + i * 0.55
		_box(BYPASS_GATE + Vector3(0.0, y, 0.0), Vector3(7.8, 0.06, 0.06), taut, false, bypass, Basis(Vector3.FORWARD, (i % 3 - 1) * 0.05))
	_blocker(bypass, BYPASS_GATE + Vector3(0.0, 2.0, 0.0), Vector3(8.0, 4.0, 0.4))
	# The lane's north end opens on the bowl beside the locker.
	_arch(Vector3(-56.0, 0.0, -31.0), Vector3(-46.0, 0.0, -31.0), 8.0, 1.6, 3, 8)


## The Spindles: fibre pillars for the pinweavers' lines, braced to the massif and the growth.
func _spindles() -> void:
	for s in SPINDLES:
		var base := Vector3(s[0], 0.0, s[1])
		var r: float = s[2]
		var h: float = s[3]
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = h
		cs.shape = cyl
		body.position = base + Vector3(0.0, h * 0.5, 0.0)
		body.add_child(cs)
		add_child(body)
		for k in 3:
			var a := k * TAU / 3.0 + _rng.randf() * 0.5
			var off := Vector3(cos(a), 0.0, sin(a)) * r * 0.45
			_strand(base + off * 1.4 + Vector3.DOWN * 0.3, base - off + Vector3(_rng.randf_range(-0.8, 0.8), h, _rng.randf_range(-0.8, 0.8)), r * 0.5)
		var lean := Vector3(12.0 if s[0] < 28.0 else 44.0, h + 4.0, s[1] + _rng.randf_range(-4.0, 4.0))
		_strand(base + Vector3(0.0, h * 0.8, 0.0), lean, r * 0.35)


## The Listening Bowl: patches, boulders, the survey locker and the ledge with the marker.
func _bowl() -> void:
	for p in PATCHES:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.2
		cm.bottom_radius = 2.4
		cm.height = 0.1
		cm.radial_segments = 16
		mi.mesh = cm
		mi.material_override = _glow(GILLS, 0.8)
		mi.position = p + Vector3(0.0, 0.05, 0.0)
		add_child(mi)
		_arch(p + Vector3(-2.4, 0.0, 0.0), p + Vector3(2.4, 0.0, 0.0), 3.0, 0.6, 2, 6)
	for b in BOULDERS:
		_box(b[0] + Vector3(0.0, b[1].y * 0.5, 0.0), b[1], _basalt(3.0), true, self, Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)))
	var light := OmniLight3D.new()
	light.light_color = GILLS
	light.light_energy = 1.2
	light.omni_range = 22.0
	light.shadow_enabled = false
	light.position = Vector3(0.0, 5.0, -56.0)
	add_child(light)
	# The survey team's locker: an amber-striped field case under a tarp of fibre.
	_box(LOCKER + Vector3(0.0, 0.45, 0.0), Vector3(1.6, 0.9, 0.9), _mat(Color("5c6066"), 0.5), true)
	_box(LOCKER + Vector3(0.0, 0.62, 0.46), Vector3(1.6, 0.12, 0.02), _glow(AMBER, 1.2), false)
	locker_lid = Node3D.new()
	locker_lid.name = "LockerLid"
	locker_lid.set_meta("no_batch", true)
	locker_lid.position = LOCKER + Vector3(0.0, 0.9, -0.45)
	add_child(locker_lid)
	_box(Vector3(0.0, 0.05, 0.45), Vector3(1.64, 0.1, 0.94), _mat(Color("6a6e74"), 0.5), false, locker_lid)
	var lamp := OmniLight3D.new()
	lamp.light_color = AMBER
	lamp.light_energy = 1.0
	lamp.omni_range = 6.0
	lamp.shadow_enabled = false
	lamp.position = LOCKER + Vector3(0.0, 2.0, 1.0)
	add_child(lamp)
	for i in 3:
		_strand(LOCKER + Vector3(-1.5 + i * 1.5, 0.0, -1.2), LOCKER + Vector3(-1.0 + i, 2.6, -0.2), 0.12)
	# The ledge, a ramp up its west side, and the survey marker: a tripod over a sample case.
	_box(LEDGE[0], LEDGE[1], _basalt(4.0), true)
	_ramp(Vector3(26.0, 0.0, -62.0), Vector3(34.0, 3.0, -62.0), 4.0)
	for i in 3:
		var a := i * TAU / 3.0
		_box(MARKER + Vector3(cos(a) * 0.35, 0.8, sin(a) * 0.35), Vector3(0.05, 1.7, 0.05), _mat(Color("c9c4b8"), 0.4), false, self, Basis(Vector3(sin(a), 0.0, -cos(a)), 0.2))
	_box(MARKER + Vector3(0.0, 1.7, 0.0), Vector3(0.3, 0.2, 0.3), _glow(AMBER, 1.6), false)
	_box(MARKER + Vector3(-0.8, 0.2, 0.6), Vector3(0.7, 0.4, 0.45), _mat(Color("5c6066"), 0.5), true)
	var mlamp := OmniLight3D.new()
	mlamp.light_color = AMBER
	mlamp.light_energy = 0.9
	mlamp.omni_range = 5.0
	mlamp.shadow_enabled = false
	mlamp.position = MARKER + Vector3(0.0, 2.2, 0.0)
	add_child(mlamp)


## The Tuning Crown: crossed arches the height of a tower, a pale column of light inside.
func _crown() -> void:
	for i in 4:
		var a := i * PI / 4.0
		var d := Vector3(cos(a), 0.0, sin(a)) * 50.0
		_arch(CROWN - d, CROWN + d, 110.0, 10.0, 5, 16)
	for i in 6:
		var a := i * TAU / 6.0 + 0.3
		_strand(CROWN + Vector3(cos(a) * 60.0, -2.0, sin(a) * 60.0), CROWN + Vector3(cos(a) * 9.0, 90.0, sin(a) * 9.0), 3.0)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.0
	cm.bottom_radius = 5.0
	cm.height = 110.0
	cm.radial_segments = 12
	beam.mesh = cm
	var m := _glow(CROWN_GLOW, 4.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(CROWN_GLOW, 0.5)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = m
	beam.position = CROWN + Vector3(0.0, 55.0, 0.0)
	add_child(beam)
	# Far ridges either side, so the Crown stands in a landscape and not on a plate.
	for i in 8:
		var x := -260.0 + i * 74.0 + _rng.randf_range(-10.0, 10.0)
		var z := CROWN.z + _rng.randf_range(-60.0, 80.0)
		if absf(x) < 90.0:
			continue
		_arch(Vector3(x - 30.0, -5.0, z), Vector3(x + 30.0, -5.0, z + _rng.randf_range(-20.0, 20.0)), _rng.randf_range(40.0, 90.0), 10.0, 3, 10)


## Arches over the two lanes, from the rim to the massif: what "under the ridges" means.
func _overhead() -> void:
	for z in [26.0, 6.0, -16.0]:
		_arch(Vector3(-56.0, 16.0, z), Vector3(-12.0, 12.0, z + _rng.randf_range(-6.0, 6.0)), 14.0, 2.6, 4, 12)
		_arch(Vector3(56.0, 16.0, z - 4.0), Vector3(14.0, 12.0, z + _rng.randf_range(-6.0, 6.0)), 16.0, 2.8, 4, 12)
	_arch(Vector3(-56.0, 18.0, -50.0), Vector3(56.0, 18.0, -60.0), 18.0, 3.0, 4, 18)


## Magenta blooms along the edges of the lanes, one multimesh.
func _blooms() -> void:
	var xforms: Array[Transform3D] = []
	for i in 180:
		var p := Vector3(_rng.randf_range(-54.0, 54.0), 0.0, _rng.randf_range(-78.0, 66.0))
		# Keep the lanes and the massif clear.
		if absf(p.x) < 15.0 and absf(p.z) < MASSIF_Z + 1.0:
			continue
		if on_weave_local(p) and _rng.randf() < 0.7:
			continue
		var s := _rng.randf_range(0.25, 0.6)
		xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 1.8, s)), p + Vector3(0.0, s * 0.6, 0.0)))
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.7
	mesh.bottom_radius = 0.0
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Blooms"
	mmi.multimesh = mm
	mmi.material_override = _glow(BLOOM, 1.4)
	add_child(mmi)


func on_weave_local(p: Vector3) -> bool:
	return WEAVE.has_point(Vector2(p.x, p.z))
