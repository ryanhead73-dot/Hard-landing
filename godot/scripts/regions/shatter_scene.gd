class_name ShatterScene
extends RegionScene
## What the Shatterlands' areas are built from: the palette, Jake's PBR sets (PbrSet), basalt rim
## walls and columns, giant fungi, ramps and boxes. The threshold pocket and the areas beyond it
## extend this. Fungus caps add their pale spots to `_spots`; call _build_spots() once after the
## last _fungus().

const GROUND := Color("23222b")
const BASALT := Color("1b1d1f")
const CAP_TOP := Color("4a3a78")
const GILLS := Color("3fd1b5")
const STEM := Color("8d86a6")
const HULL := Color("d9d2c2")
const OXIDE := Color("bf6835")
const RIM := Color("a49cff")
const SPOT := Color("e6dcff")

var _rng := RandomNumberGenerator.new()
var _spots: Array[Transform3D] = []
var _mats := {}


## Rim walls round a valley: plain boxes for collision, each [centre, size], dressed with basalt
## columns along its length (one multimesh for all of them).
func _rim(sides: Array) -> void:
	var cols: Array[Transform3D] = []
	for side in sides:
		_wall(side[0], side[1])
		var c: Vector3 = side[0]
		var sz: Vector3 = side[1]
		var along := Vector3(1.0, 0.0, 0.0) if sz.x > sz.z else Vector3(0.0, 0.0, 1.0)
		var length := maxf(sz.x, sz.z)
		# Kept inside the wall's ends, so a gap left between two walls stays open.
		var across := Vector3(1.0, 0.0, 1.0) - along
		var t := -length * 0.5 + 3.2
		while t < length * 0.5 - 3.2:
			var h := _rng.randf_range(14.0, 30.0)
			var r := _rng.randf_range(1.6, 3.2)
			var p := c + along * t + across * _rng.randf_range(-2.5, 2.5) + Vector3(0.0, h * 0.5 - 10.0, 0.0)
			var b := Basis(Vector3.UP, _rng.randf() * TAU).rotated(along.cross(Vector3.UP), _rng.randf_range(-0.12, 0.12))
			cols.append(Transform3D(b.scaled(Vector3(r, h, r)), p))
			t += r * 1.6
	_columns(cols)


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
