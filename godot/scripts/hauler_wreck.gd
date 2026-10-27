@tool
class_name HaulerWreck
extends Node3D
## A coolant hauler that came down in the hot springs: the second expedition site. The manifold
## Kestrel needs is still racked at the back of its hold. Steam vents in the pool guard the
## approach. Local space: the open cargo door faces +Z. The tail strobe makes it findable.

## Fires on each tail strobe flash, in the game only (not in the editor).
signal strobe_flashed(at: Vector3)

const SPAWN_POINTS := [
	Vector3(-9.0, 0.3, 4.0), Vector3(9.0, 0.3, 2.0), Vector3(8.0, 0.3, -12.0), Vector3(-8.0, 0.3, -15.0),
]
const AMBUSH_POINTS := [Vector3(-12.0, 0.3, 12.0), Vector3(12.0, 0.3, 14.0), Vector3(0.0, 0.3, 20.0)]
const VENT_POINTS := [
	Vector3(-3.5, 0.0, 9.0), Vector3(2.8, 0.0, 11.5), Vector3(-0.8, 0.0, 14.2),
	Vector3(5.2, 0.0, 14.0), Vector3(-6.2, 0.0, 12.8), Vector3(1.0, 0.0, 6.6),
]
const CRATE_POINTS := [Vector3(-1.9, 0.0, -10.6), Vector3(1.9, 0.0, -3.0), Vector3(-7.5, 0.0, -4.0)]
const CRATE_SCRAP := 12
const MANIFOLD_POSITION := Vector3(0.0, 1.25, -14.6)
const STROBE_POSITION := Vector3(0.0, 9.6, 1.0)
const STROBE_PERIOD := 2.2

var _crates: Array[Node3D] = []
var _crate_searched: Array[bool] = []
var _vents: Array[Node3D] = []
var _manifold: Node3D
var _manifold_light: OmniLight3D
var _strobe_mat: StandardMaterial3D
var _strobe_time := 0.0


func _ready() -> void:
	build()


func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_crates.clear()
	_crate_searched.clear()
	_vents.clear()
	_build_pool()
	_build_hull()
	_build_hold()
	_build_manifold()
	_build_crates()
	_build_vents()


func _process(delta: float) -> void:
	var before := fmod(_strobe_time, STROBE_PERIOD)
	_strobe_time += delta
	var phase := fmod(_strobe_time, STROBE_PERIOD)
	if _strobe_mat:
		_strobe_mat.emission_energy_multiplier = 8.0 if phase < 0.12 or (phase > 0.3 and phase < 0.42) else 0.3
	if phase < before and not Engine.is_editor_hint():
		strobe_flashed.emit(to_global(STROBE_POSITION))


func manifold_point() -> Vector3:
	return to_global(Vector3(MANIFOLD_POSITION.x, 0.0, MANIFOLD_POSITION.z + 1.3))


func has_manifold() -> bool:
	return _manifold != null and _manifold.visible


func take_manifold() -> void:
	_manifold.visible = false
	_manifold_light.visible = false


func spawn_points() -> Array[Vector3]:
	return _to_global_all(SPAWN_POINTS)


func ambush_points() -> Array[Vector3]:
	return _to_global_all(AMBUSH_POINTS)


func vents() -> Array[Node3D]:
	return _vents


func crate_count() -> int:
	return _crates.size()


func crate_point(i: int) -> Vector3:
	return _crates[i].global_position


func crate_searched(i: int) -> bool:
	return _crate_searched[i]


## Marks a crate as searched and returns the scrap found in it.
func search_crate(i: int) -> int:
	if _crate_searched[i]:
		return 0
	_crate_searched[i] = true
	(_crates[i].get_child(0) as MeshInstance3D).material_override = _mat(Color("24282b"))
	return CRATE_SCRAP


func _to_global_all(points: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in points:
		out.append(to_global(p))
	return out


## Mineral-rimmed hot pool the hauler sank into. Meshes only: the ground underneath is walkable.
func _build_pool() -> void:
	var rim := _mat(Color("6e6446"), 0.95)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("142a27")
	water.metallic = 0.2
	water.roughness = 0.3
	water.emission_enabled = true
	water.emission = Color("3fd1b5")
	water.emission_energy_multiplier = 0.15
	_disc(Vector3(0.0, 0.0, 3.0), 14.0, 0.012, rim)
	_disc(Vector3(0.0, 0.0, 3.0), 13.3, 0.03, water)


func _build_hull() -> void:
	var paint := _mat(Color("5d6b73"), 0.75)
	var inner := _mat(Color("3a4247"), 0.85)
	var hull := CSGCombiner3D.new()
	hull.name = "Hull"
	hull.use_collision = true
	add_child(hull)
	_csg(hull, Vector3(6.0, 4.5, 20.0), Vector3(0.0, 2.0, -6.0), paint)
	_csg(hull, Vector3(5.4, 3.9, 19.4), Vector3(0.0, 1.95, -6.0), inner, true)
	# Open cargo door at the back, cut down through the floor so the threshold is flush with the ground.
	_csg(hull, Vector3(4.6, 3.6, 1.0), Vector3(0.0, 1.6, 4.0), inner, true)
	# Breach in the starboard side, a second way in, clear of the fallen container.
	_csg(hull, Vector3(1.0, 2.4, 3.0), Vector3(3.0, 1.4, -10.5), inner, true)
	# Torn-off nose: the front of the hold is open to the sky and the pool.
	_csg(hull, Vector3(5.0, 2.0, 1.0), Vector3(0.0, 3.3, -16.0), inner, true)

	var hazard := _mat(Color("e0b420"), 0.7)
	var black := _mat(Color("1a1a1a"), 0.7)
	for i in 6:
		for side in [-3.03, 3.03]:
			_mesh_box(Vector3(0.04, 0.5, 0.9), Vector3(side, 3.6, 3.4 - i * 0.9), hazard if i % 2 == 0 else black)
	# Tail fin and strobe: the landmark seen from Kestrel.
	var fin := _static_box(Vector3(0.4, 5.5, 3.5), Vector3(0.0, 6.9, 1.6), paint)
	fin.rotation.z = 0.12
	var strobe := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	strobe.mesh = sphere
	_strobe_mat = _emissive(Color("bfe8ff"), 8.0)
	strobe.material_override = _strobe_mat
	strobe.position = STROBE_POSITION
	add_child(strobe)
	# The nose section, broken off and half sunk ahead of the hull.
	var nose := _static_box(Vector3(5.2, 3.6, 5.0), Vector3(1.5, 0.9, -20.5), paint)
	nose.rotation = Vector3(0.35, 0.4, 0.2)


func _build_hold() -> void:
	var rack := _mat(Color("2b3033"), 0.5)
	var cargo := _mat(Color("6b6a52"), 0.9)
	# Shelving down the port wall, a fallen container across the middle for cover.
	_static_box(Vector3(0.8, 2.4, 6.0), Vector3(-2.2, 1.2, -6.0), rack)
	var fallen := _static_box(Vector3(2.2, 1.2, 1.4), Vector3(1.7, 0.6, -6.5), cargo)
	fallen.rotation.y = 0.5
	_static_box(Vector3(1.2, 1.2, 1.2), Vector3(2.0, 0.6, 0.5), cargo)
	_static_box(Vector3(1.0, 0.8, 1.0), Vector3(-1.9, 0.4, 1.8), cargo)
	# Work light that still runs off the hauler's emergency battery.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("ffd9a0")
	lamp.light_energy = 0.6
	lamp.omni_range = 7.0
	lamp.position = Vector3(0.0, 3.4, -2.0)
	add_child(lamp)


func _build_manifold() -> void:
	_static_box(Vector3(2.6, 0.7, 1.0), MANIFOLD_POSITION + Vector3(0.0, -0.9, 0.0), _mat(Color("2b3033"), 0.5))
	_manifold = Node3D.new()
	_manifold.name = "CoolantManifold"
	_manifold.position = MANIFOLD_POSITION
	add_child(_manifold)
	var pipe_mat := _mat(Color("a9b4b8"), 0.35)
	pipe_mat.metallic = 0.7
	var frost := _emissive(Color("7fd6ff"), 2.2)
	for y in [-0.2, 0.0, 0.2]:
		var pipe := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = 2.0
		pipe.mesh = cyl
		pipe.material_override = pipe_mat
		pipe.rotation.z = PI * 0.5
		pipe.position.y = y
		_manifold.add_child(pipe)
	for x in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(0.12, 0.62, 0.22)
		cap.mesh = cap_mesh
		cap.material_override = frost
		cap.position.x = x
		_manifold.add_child(cap)
	_manifold_light = OmniLight3D.new()
	_manifold_light.light_color = Color("7fd6ff")
	_manifold_light.light_energy = 1.4
	_manifold_light.omni_range = 5.0
	_manifold_light.position = MANIFOLD_POSITION + Vector3(0.0, 0.8, 0.8)
	add_child(_manifold_light)


func _build_crates() -> void:
	for p in CRATE_POINTS:
		var holder := Node3D.new()
		holder.position = p
		add_child(holder)
		var body := _static_box(Vector3(1.4, 0.8, 0.9), p + Vector3(0.0, 0.4, 0.0), _mat(Color("c4622d"), 0.8))
		body.name = "SalvageCrate"
		var lid := MeshInstance3D.new()
		var lid_mesh := BoxMesh.new()
		lid_mesh.size = Vector3(1.45, 0.08, 0.95)
		lid.mesh = lid_mesh
		lid.material_override = _emissive(Color("f2a93b"), 0.8)
		lid.position = Vector3(0.0, 0.84, 0.0)
		holder.add_child(lid)
		_crates.append(holder)
		_crate_searched.append(false)


func _build_vents() -> void:
	if Engine.is_editor_hint():
		for p in VENT_POINTS:
			_disc(p, 1.6, 0.05, _emissive(Color("8a7a52"), 0.6))
		return
	for i in VENT_POINTS.size():
		var vent := SteamVent.new()
		vent.position = VENT_POINTS[i]
		vent.offset = i * 0.55
		add_child(vent)
		_vents.append(vent)


func _csg(parent: Node, size: Vector3, pos: Vector3, mat: Material, subtract := false) -> void:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	if subtract:
		b.operation = CSGShape3D.OPERATION_SUBTRACTION
	parent.add_child(b)


func _disc(pos: Vector3, radius: float, height: float, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 40
	mesh.mesh = cyl
	mesh.material_override = mat
	mesh.position = pos + Vector3(0.0, height * 0.5, 0.0)
	add_child(mesh)


func _mesh_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	add_child(mesh)
	return mesh


func _static_box(size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(mesh)
	body.add_child(shape)
	add_child(body)
	return body


func _mat(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(color, 0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
