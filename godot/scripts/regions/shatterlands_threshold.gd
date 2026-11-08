class_name ShatterlandsThreshold
extends RegionScene
## Expansion prototype (X1.3): the first pocket of the Shatterlands, past the canyon from the
## Kettle. A greybox to prove the region layer and set the look: a giant fungal canopy in purple
## and blue, stepped basalt shelves to climb, and a wrecked hull half-buried in the growth. Not
## final art; built in code so it costs nothing to change while the region is designed.
##
## Local space: Juno arrives at the canyon mouth on +Z and looks north (-Z) up the shelves.

const SEED := 44
const GROUND := Color("23222b")
const BASALT := Color("1b1d1f")
const CAP_TOP := Color("4a3a78")
const GILLS := Color("3fd1b5")
const STEM := Color("8d86a6")
const HULL := Color("d9d2c2")
const OXIDE := Color("bf6835")
const RIM := Color("a49cff")
const SPOT := Color("e6dcff")

## Giant fungi: [local position, stem height, cap radius].
const FUNGI := [
	[Vector3(-22.0, 0.0, 8.0), 18.0, 10.0], [Vector3(20.0, 0.0, 14.0), 14.0, 8.0],
	[Vector3(-6.0, 0.0, -30.0), 24.0, 13.0], [Vector3(26.0, 0.0, -30.0), 16.0, 9.0],
	[Vector3(-34.0, 6.0, -22.0), 20.0, 11.0], [Vector3(6.0, 0.0, 24.0), 11.0, 6.0],
	# "The big fungus": the one Voss's greenhouses shelter under.
	[Vector3(36.0, 0.0, -58.0), 34.0, 20.0],
]
## Stepped shelves: [centre, size]. The ramps between them are built from the same list.
const SHELVES := [
	[Vector3(-26.0, 1.5, -6.0), Vector3(16.0, 3.0, 14.0)],
	[Vector3(-30.0, 3.0, -22.0), Vector3(18.0, 6.0, 14.0)],
	[Vector3(-14.0, 4.5, -40.0), Vector3(26.0, 9.0, 12.0)],
]
const WRECK_POS := Vector3(16.0, 0.0, -10.0)
## Where the scuttlers nest: off the wreck's tail, under its lamp.
const NEST := Vector3(24.0, 0.0, 5.0)

## Voss's greenhouses, the Act 2 hub (greybox).
var greenhouses: Greenhouses
var _rng := RandomNumberGenerator.new()
var _spots: Array[Transform3D] = []
## Where Juno stands to open the wrecked hauler's dorsal locker (world space).
var locker_pos := Vector3.INF
var _locker_tell: MeshInstance3D
var _mats := {}


func _init() -> void:
	entry = Vector3(0.0, 0.3, 40.0)
	entry_yaw = 0.0
	exit_point = Vector3(0.0, 0.0, 45.0)
	# Laid out to teach the drifter, then pay it off:
	#   one alone by the way in, which comes to Juno and bursts, so she learns what it does;
	#   a pack nested under the wreck's lamp-lit tail with one moored over them, to be shot;
	#   a pair hung close under the big cap, so one popped sets off the other;
	#   a spitter up on the middle shelf, covering the climb.
	# The nest is what Reyes asks Juno to clear; once it is, it stays gone.
	var nest := {"wander_radius": 1.5, "_tag": "nest", "_unless": "nest_cleared"}
	var moored := {"wander_radius": 0.8}
	residents = [
		["drifter", Vector3(3.0, 3.0, 16.0)],
		["scuttler", NEST + Vector3(-1.5, 0.5, -1.0), nest], ["scuttler", NEST + Vector3(1.4, 0.5, -0.8), nest],
		["scuttler", NEST + Vector3(-0.6, 0.5, 1.6), nest], ["scuttler", NEST + Vector3(1.6, 0.5, 1.4), nest],
		["drifter", NEST + Vector3(0.0, 3.0, 0.0), moored],
		["drifter", Vector3(-6.0, 3.0, -26.0), moored], ["drifter", Vector3(-3.6, 3.0, -28.0), moored],
		["spitter", Vector3(-30.0, 6.5, -24.0)],
	]
	# The waypoint leads to the greenhouse gate.
	goal = Greenhouses.AT + Vector3(0.0, 1.0, Greenhouses.HALF.y + 2.0)
	look = {
		"fog_light_color": Color("3a3160"), "fog_density": 0.017,
		"ambient_light_color": Color("7d72b4"), "ambient_light_energy": 0.8,
		"background_energy_multiplier": 0.45,
		"sun_energy": 0.3, "sun_color": Color("a49cff"), "sun_rotation": Vector3(-24.0, 120.0, 0.0),
	}


func build() -> void:
	_rng.seed = SEED
	_ground()
	_canyon_mouth()
	# The shelves are the tops of basalt columns, the joints showing.
	for s in SHELVES:
		_box(s[0], s[1], _basalt(6.0), true)
	_ramp(Vector3(-15.0, 0.0, -2.0), Vector3(-19.0, 3.0, -8.0), 5.0)
	_ramp(Vector3(-30.0, 3.0, -12.0), Vector3(-30.0, 6.0, -16.0), 5.0)
	_ramp(Vector3(-24.0, 6.0, -26.0), Vector3(-17.0, 9.0, -34.0), 5.0)
	_spots.clear()
	for f in FUNGI:
		var base: Vector3 = f[0]
		_fungus(base, f[1], f[2])
	_build_spots()
	_wreck()
	greenhouses = Greenhouses.new()
	greenhouses.name = "Greenhouses"
	add_child(greenhouses)
	_undergrowth()
	_spores()


func spawn_residents(main: Node) -> Array[Enemy]:
	var out := super(main)
	for e in out:
		if e.is_in_group("resident_nest"):
			e.died.connect(_on_nest_death)
	return out


func nest_cleared() -> bool:
	return Game.flags.get("nest_cleared", false) == true


func _on_nest_death(_e: Enemy) -> void:
	if nest_cleared():
		return
	for e in get_tree().get_nodes_in_group("resident_nest"):
		if is_instance_valid(e) and not (e as Enemy).dead and e.is_inside_tree():
			return
	Game.set_flag("nest_cleared")
	var main := greenhouses._main() if greenhouses else null
	if main:
		main.voice.say(Story.NEST_CLEARED)


func interaction(pos: Vector3) -> Dictionary:
	if not locker_open() and pos.distance_to(locker_pos) < 2.2:
		return {"label": "[E] Open the hauler's dorsal locker", "action": open_locker}
	return greenhouses.interaction(pos) if greenhouses else {}


func _ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(140.0, 140.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _tex("shatterlands_ground", 2.5, true, Color.WHITE, _mat(GROUND, 0.85))
	add_child(mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(140.0, 1.0, 140.0)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)
	# Rim walls so the pocket reads as a valley and nobody walks off the edge: plain boxes for
	# collision, dressed with a ring of basalt columns (one multimesh).
	var cols: Array[Transform3D] = []
	for side in [[Vector3(0.0, 10.0, -66.0), Vector3(140.0, 20.0, 8.0)], [Vector3(-66.0, 10.0, 0.0), Vector3(8.0, 20.0, 140.0)], [Vector3(66.0, 10.0, 0.0), Vector3(8.0, 20.0, 140.0)], [Vector3(-38.0, 10.0, 62.0), Vector3(64.0, 20.0, 8.0)], [Vector3(38.0, 10.0, 62.0), Vector3(64.0, 20.0, 8.0)]]:
		_wall(side[0], side[1])
		var c: Vector3 = side[0]
		var sz: Vector3 = side[1]
		var along := Vector3(1.0, 0.0, 0.0) if sz.x > sz.z else Vector3(0.0, 0.0, 1.0)
		var length := maxf(sz.x, sz.z)
		var t := -length * 0.5
		while t < length * 0.5:
			var h := _rng.randf_range(14.0, 30.0)
			var r := _rng.randf_range(1.6, 3.2)
			var p := c + along * t + Vector3(_rng.randf_range(-2.5, 2.5), h * 0.5 - 10.0, _rng.randf_range(-2.5, 2.5)) * Vector3(1.0, 1.0, 1.0)
			var b := Basis(Vector3.UP, _rng.randf() * TAU).rotated(along.cross(Vector3.UP), _rng.randf_range(-0.12, 0.12))
			cols.append(Transform3D(b.scaled(Vector3(r, h, r)), p))
			t += r * 1.6
	_columns(cols)


## Two tall basalt slabs either side of the canyon Juno came through, with the way back between.
func _canyon_mouth() -> void:
	_box(Vector3(-5.5, 9.0, 50.0), Vector3(5.0, 18.0, 16.0), _basalt(8.0), true)
	_box(Vector3(5.5, 9.0, 50.0), Vector3(5.0, 18.0, 16.0), _basalt(8.0), true)
	_box(Vector3(0.0, 9.0, 58.0), Vector3(8.0, 18.0, 2.0), _basalt(8.0), true)


func _fungus(base: Vector3, height: float, radius: float) -> void:
	var stem := CylinderMesh.new()
	stem.top_radius = radius * 0.12
	stem.bottom_radius = radius * 0.2
	stem.height = height
	stem.radial_segments = 10
	var stem_mi := MeshInstance3D.new()
	stem_mi.mesh = stem
	stem_mi.material_override = _tex("fungus_stem", 2.5, true, Color.WHITE, _mat(STEM, 0.7))
	stem_mi.position = base + Vector3(0.0, height * 0.5, 0.0)
	add_child(stem_mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius * 0.18
	cyl.height = height
	shape.shape = cyl
	body.position = stem_mi.position
	body.add_child(shape)
	add_child(body)
	var cap := SphereMesh.new()
	cap.radius = radius
	cap.height = radius * 0.7
	cap.radial_segments = 20
	cap.rings = 8
	var cap_mi := MeshInstance3D.new()
	cap_mi.mesh = cap
	cap_mi.material_override = _mat(CAP_TOP, 0.6)
	cap_mi.position = base + Vector3(0.0, height, 0.0)
	add_child(cap_mi)
	# A bulb where the stem meets the ground, a ragged skirt (annulus) under the cap, and a pale
	# glowing rim so the canopy reads against the sky.
	var bulb := SphereMesh.new()
	bulb.radius = radius * 0.32
	bulb.height = radius * 0.4
	bulb.radial_segments = 12
	bulb.rings = 5
	var bulb_mi := MeshInstance3D.new()
	bulb_mi.mesh = bulb
	bulb_mi.material_override = _tex("fungus_stem", 2.0, true, Color(0.75, 0.72, 0.8), _mat(STEM.darkened(0.25), 0.8))
	bulb_mi.position = base + Vector3(0.0, radius * 0.08, 0.0)
	add_child(bulb_mi)
	var skirt := TorusMesh.new()
	skirt.inner_radius = radius * 0.13
	skirt.outer_radius = radius * 0.32
	skirt.rings = 16
	skirt.ring_segments = 6
	var skirt_mi := MeshInstance3D.new()
	skirt_mi.mesh = skirt
	skirt_mi.material_override = _mat(STEM.lightened(0.15), 0.7)
	skirt_mi.scale = Vector3(1.0, 0.35, 1.0)
	skirt_mi.position = base + Vector3(0.0, height * 0.72, 0.0)
	add_child(skirt_mi)
	var rim := TorusMesh.new()
	rim.inner_radius = radius * 0.94
	rim.outer_radius = radius * 1.0
	rim.rings = 28
	rim.ring_segments = 4
	var rim_mi := MeshInstance3D.new()
	rim_mi.mesh = rim
	rim_mi.material_override = _glow(RIM, 1.2)
	rim_mi.position = base + Vector3(0.0, height - radius * 0.05, 0.0)
	add_child(rim_mi)
	# Pale spots on the cap's crown, gathered into one multimesh for the whole pocket.
	for i in int(radius * 1.2):
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * radius * 0.75
		var y := sqrt(maxf(1.0 - (d / radius) * (d / radius), 0.0)) * radius * 0.35
		var sz := _rng.randf_range(0.25, 0.7) * radius * 0.08 + 0.15
		_spots.append(Transform3D(Basis().scaled(Vector3(sz, sz * 0.4, sz)), base + Vector3(cos(a) * d, height + y - 0.05, sin(a) * d)))
	# The glowing gills underneath: a flatter disc just under the cap.
	var gills := CylinderMesh.new()
	gills.top_radius = radius * 0.92
	gills.bottom_radius = radius * 0.6
	gills.height = 0.4
	gills.radial_segments = 20
	var gill_mi := MeshInstance3D.new()
	gill_mi.mesh = gills
	# Lilac gills whose ridges glow teal (the set's emission mask).
	gill_mi.material_override = _tex("fungus_cap_underside", 3.0, true, Color.WHITE, _glow(GILLS, 1.4), GILLS, 3.0)
	gill_mi.position = base + Vector3(0.0, height - radius * 0.2, 0.0)
	add_child(gill_mi)
	if radius >= 10.0:
		var light := OmniLight3D.new()
		light.light_color = GILLS
		light.light_energy = 1.6
		light.omni_range = radius * 1.6
		light.shadow_enabled = false
		light.position = base + Vector3(0.0, height - radius * 0.4, 0.0)
		add_child(light)


func _build_spots() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mm.mesh = sphere
	mm.instance_count = _spots.size()
	for i in _spots.size():
		mm.set_instance_transform(i, _spots[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _glow(SPOT, 0.6)
	add_child(mmi)


## Voss's supply hauler, the Marigold, that came down nose-first into the growth: a long ivory hull with oxide
## bands, tipped and half-buried, ribs showing where the plating tore away.
func _wreck() -> void:
	var hull := Node3D.new()
	hull.name = "Marigold"
	hull.position = WRECK_POS
	hull.rotation = Vector3(deg_to_rad(-9.0), deg_to_rad(28.0), deg_to_rad(6.0))
	add_child(hull)
	# Plated in Jake's hull set, mapped in the hull's own space so the seams follow the wreck.
	_box(Vector3(0.0, 2.6, 0.0), Vector3(7.0, 5.0, 26.0), _tex("hauler_hull", 6.0, false, Color.WHITE, _mat(HULL, 0.55)), true, hull)
	for z in [-9.0, 0.0, 9.0]:
		_box(Vector3(0.0, 2.6, z), Vector3(7.2, 5.2, 1.0), _mat(OXIDE, 0.6), false, hull)
	_box(Vector3(0.0, 1.0, -14.5), Vector3(5.0, 3.0, 4.0), _basalt(6.0), true, hull)
	for i in 5:
		_box(Vector3(-3.6, 4.0, 14.0 + i * 1.6), Vector3(0.4, 4.0, 0.4), _mat(Color("6c6a66"), 0.5), false, hull)
		_box(Vector3(3.6, 4.0, 14.0 + i * 1.6), Vector3(0.4, 4.0, 0.4), _mat(Color("6c6a66"), 0.5), false, hull)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("e8a44e")
	# Hung off the tail, so it lights the nest under it.
	lamp.light_energy = 1.8
	lamp.omni_range = 9.0
	lamp.position = Vector3(0.0, 3.4, 15.0)
	hull.add_child(lamp)
	_wreck_climb(hull)


## The way up: a torn-off hull plate leans from the ground onto the buried nose, and the hull's
## spine climbs from there to the raised tail, where the dorsal locker still holds. From the top
## Juno sees the whole pocket, the greenhouses' glow included.
func _wreck_climb(hull: Node3D) -> void:
	var foot := hull.transform * Vector3(-9.5, 0.0, -10.0)
	foot.y = 0.0
	# Ends just above the hull edge, so Juno steps down onto the spine instead of into its side.
	var lip := hull.transform * Vector3(-3.3, 5.5, -10.0)
	_ramp(foot, lip, 2.6, _tex("hauler_hull", 6.0, false, Color(0.85, 0.85, 0.85), _mat(HULL.darkened(0.15), 0.6)))
	# The locker: a squat oxide box on the spine near the tail, an amber tell-tale on top.
	var locker_local := Vector3(0.0, 5.1 + 0.45, 9.0)
	_box(locker_local, Vector3(1.4, 0.9, 1.0), _mat(OXIDE, 0.55), true, hull)
	var tell := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.25, 0.12, 0.25)
	tell.mesh = tm
	tell.material_override = _glow(Color("e8a44e"), 3.0)
	tell.position = locker_local + Vector3(0.45, 0.5, 0.0)
	hull.add_child(tell)
	locker_pos = hull.to_global(locker_local + Vector3(0.0, -0.45, -1.2))
	_locker_tell = tell
	_locker_tell.visible = not locker_open()


func locker_open() -> bool:
	return Game.flags.get("marigold_locker", false) == true


## Voss's hauler: the locker holds her log and what she left for whoever came next.
func open_locker() -> void:
	if locker_open():
		return
	Game.set_flag("marigold_locker")
	Game.find_log("voss_1")
	Game.add_charges(2)
	Game.add_scrap(20)
	if _locker_tell:
		_locker_tell.visible = false
	Sfx.play("scrap_pickup", locker_pos, 0.0)


## Small glowing caps scattered across the floor, instanced in one draw call.
func _undergrowth() -> void:
	var count := 260 if Game.graphics > Game.GRAPHICS_LOW else 120
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.3
	mesh.radial_segments = 8
	mesh.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var p := Vector3(_rng.randf_range(-58.0, 58.0), 0.08, _rng.randf_range(-58.0, 44.0))
		var s := _rng.randf_range(0.5, 2.2)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _glow(Color("7f6bd6"), 0.9)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _spores() -> void:
	var p := CPUParticles3D.new()
	p.amount = 300 if Game.graphics > Game.GRAPHICS_LOW else 120
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(50.0, 8.0, 50.0)
	p.position = Vector3(0.0, 9.0, -8.0)
	p.gravity = Vector3(0.0, 0.05, 0.0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.3
	p.direction = Vector3(0.3, 1.0, 0.0)
	p.spread = 80.0
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	dot.radial_segments = 4
	dot.rings = 2
	p.mesh = dot
	p.material_override = _glow(GILLS, 2.0)
	add_child(p)


func _wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = pos
	body.add_child(shape)
	add_child(body)


## Hexagonal basalt columns, unit-sized and scaled per instance (radius in x/z, height in y).
func _columns(xforms: Array[Transform3D]) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.85
	mesh.bottom_radius = 1.0
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
	mmi.multimesh = mm
	mmi.material_override = _basalt(8.0)
	add_child(mmi)


func _ramp(from: Vector3, to: Vector3, width: float, mat: Material = null) -> void:
	var run := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := Vector3(run.x, to.y - from.y, run.z).length()
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.6, length + 1.0)
	mi.mesh = mesh
	mi.material_override = mat if mat else _basalt(6.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	body.add_child(mi)
	body.add_child(shape)
	add_child(body)
	body.position = (from + to) * 0.5 + Vector3(0.0, -0.2, 0.0)
	# look_at takes a world-space target, and the region sits far from the world origin.
	body.look_at(body.global_position + Vector3(run.x, to.y - from.y, run.z), Vector3.UP)


func _box(pos: Vector3, size: Vector3, mat: Material, solid: bool, parent: Node3D = self) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.position = pos
		body.add_child(mi)
		body.add_child(shape)
		parent.add_child(body)
	else:
		mi.position = pos
		parent.add_child(mi)


func _mat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), roughness]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_mats[key] = m
	return _mats[key]


## A material from one of the Shatterlands PBR sets (`PbrSet`), or `fallback` if the set's
## textures aren't there.
func _tex(set_name: String, metres: float, world: bool, tint: Color, fallback: Material, emission := Color.BLACK, energy := 1.0) -> Material:
	if not PbrSet.exists("shatterlands", set_name):
		return fallback
	return PbrSet.material("shatterlands", set_name, metres, world, tint, emission, energy)


## Jake's hex-column basalt, for the rim, canyon, shelves and ramps; `metres` per repeat.
func _basalt(metres: float) -> Material:
	return _tex("basalt_hex_columns", metres, true, Color.WHITE, _mat(BASALT, 0.8))


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
