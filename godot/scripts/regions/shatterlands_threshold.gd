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

## Voss's greenhouses, the Act 2 hub (greybox).
var greenhouses: Greenhouses
var _rng := RandomNumberGenerator.new()
var _mats := {}


func _init() -> void:
	entry = Vector3(0.0, 0.3, 40.0)
	entry_yaw = 0.0
	exit_point = Vector3(0.0, 0.0, 45.0)
	# The waypoint leads to the greenhouse gate.
	goal = Greenhouses.AT + Vector3(0.0, 1.0, Greenhouses.HALF.y + 2.0)
	look = {
		"fog_light_color": Color("2a2442"), "fog_density": 0.02,
		"ambient_light_color": Color("6a5f9a"), "ambient_light_energy": 0.5,
		"background_energy_multiplier": 0.3,
		"sun_energy": 0.3, "sun_color": Color("a49cff"), "sun_rotation": Vector3(-24.0, 120.0, 0.0),
	}


func build() -> void:
	_rng.seed = SEED
	_ground()
	_canyon_mouth()
	for s in SHELVES:
		_box(s[0], s[1], _mat(BASALT), true)
	_ramp(Vector3(-15.0, 0.0, -2.0), Vector3(-19.0, 3.0, -8.0), 5.0)
	_ramp(Vector3(-30.0, 3.0, -12.0), Vector3(-30.0, 6.0, -16.0), 5.0)
	_ramp(Vector3(-24.0, 6.0, -26.0), Vector3(-17.0, 9.0, -34.0), 5.0)
	for f in FUNGI:
		var base: Vector3 = f[0]
		_fungus(base, f[1], f[2])
	_wreck()
	greenhouses = Greenhouses.new()
	greenhouses.name = "Greenhouses"
	add_child(greenhouses)
	_undergrowth()
	_spores()


func interaction(pos: Vector3) -> Dictionary:
	return greenhouses.interaction(pos) if greenhouses else {}


func _ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(140.0, 140.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(GROUND, 0.85)
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
	_box(Vector3(-5.5, 9.0, 50.0), Vector3(5.0, 18.0, 16.0), _mat(BASALT), true)
	_box(Vector3(5.5, 9.0, 50.0), Vector3(5.0, 18.0, 16.0), _mat(BASALT), true)
	_box(Vector3(0.0, 9.0, 58.0), Vector3(8.0, 18.0, 2.0), _mat(BASALT), true)


func _fungus(base: Vector3, height: float, radius: float) -> void:
	var stem := CylinderMesh.new()
	stem.top_radius = radius * 0.12
	stem.bottom_radius = radius * 0.2
	stem.height = height
	stem.radial_segments = 10
	var stem_mi := MeshInstance3D.new()
	stem_mi.mesh = stem
	stem_mi.material_override = _mat(STEM, 0.7)
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
	# The glowing gills underneath: a flatter disc just under the cap.
	var gills := CylinderMesh.new()
	gills.top_radius = radius * 0.92
	gills.bottom_radius = radius * 0.6
	gills.height = 0.4
	gills.radial_segments = 20
	var gill_mi := MeshInstance3D.new()
	gill_mi.mesh = gills
	gill_mi.material_override = _glow(GILLS, 1.4)
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


## A survey hauler that came down nose-first into the growth: a long ivory hull with oxide
## bands, tipped and half-buried, ribs showing where the plating tore away.
func _wreck() -> void:
	var hull := Node3D.new()
	hull.position = WRECK_POS
	hull.rotation = Vector3(deg_to_rad(-9.0), deg_to_rad(28.0), deg_to_rad(6.0))
	add_child(hull)
	_box(Vector3(0.0, 2.6, 0.0), Vector3(7.0, 5.0, 26.0), _mat(HULL, 0.55), true, hull)
	for z in [-9.0, 0.0, 9.0]:
		_box(Vector3(0.0, 2.6, z), Vector3(7.2, 5.2, 1.0), _mat(OXIDE, 0.6), false, hull)
	_box(Vector3(0.0, 1.0, -14.5), Vector3(5.0, 3.0, 4.0), _mat(BASALT), true, hull)
	for i in 5:
		_box(Vector3(-3.6, 4.0, 14.0 + i * 1.6), Vector3(0.4, 4.0, 0.4), _mat(Color("6c6a66"), 0.5), false, hull)
		_box(Vector3(3.6, 4.0, 14.0 + i * 1.6), Vector3(0.4, 4.0, 0.4), _mat(Color("6c6a66"), 0.5), false, hull)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("e8a44e")
	lamp.light_energy = 1.2
	lamp.omni_range = 7.0
	lamp.position = Vector3(0.0, 3.0, 13.0)
	hull.add_child(lamp)


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
	mmi.material_override = _mat(BASALT, 0.8)
	add_child(mmi)


func _ramp(from: Vector3, to: Vector3, width: float) -> void:
	var run := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := Vector3(run.x, to.y - from.y, run.z).length()
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.6, length + 1.0)
	mi.mesh = mesh
	mi.material_override = _mat(BASALT)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	body.add_child(mi)
	body.add_child(shape)
	add_child(body)
	body.position = (from + to) * 0.5 + Vector3(0.0, -0.2, 0.0)
	body.look_at(body.position + Vector3(run.x, to.y - from.y, run.z), Vector3.UP)


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


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
