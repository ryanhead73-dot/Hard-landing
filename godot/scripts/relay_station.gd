@tool
class_name RelayStation
extends Node3D
## Abandoned relay station: the vertical slice's expedition site. One building holds the aux power
## cell; broken walls, a tipped container and crates give cover for fights on the approach.
## Local space: the main doorway faces +Z. The mast beacon makes the site findable from Kestrel.

const SPAWN_POINTS := [
	Vector3(-6.0, 0.3, 4.0), Vector3(6.0, 0.3, 5.0), Vector3(0.0, 0.3, 10.0),
	Vector3(-9.0, 0.3, -9.0), Vector3(9.0, 0.3, -10.0),
]
const CRATE_POINTS := [
	Vector3(-3.8, 0.1, -3.2), Vector3(-8.0, 0.0, -1.2), Vector3(8.5, 0.0, 6.5), Vector3(3.5, 0.0, -10.4),
]
const CRATE_SCRAP := 10
const CELL_POSITION := Vector3(0.0, 1.35, -7.6)
const BEACON_POSITION := Vector3(6.0, 16.3, -8.0)
const BEACON_PERIOD := 1.6

## Fires at the start of each beacon flash, in the game only (not in the editor).
signal beacon_flashed(at: Vector3)

var _crates: Array[Node3D] = []
var _crate_searched: Array[bool] = []
var _cell: MeshInstance3D
var _cell_light: OmniLight3D
var _beacon_mat: StandardMaterial3D
var _beacon_time := 0.0


func _ready() -> void:
	build()


func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_crates.clear()
	_crate_searched.clear()
	_build_pad_and_building()
	_build_cover()
	_build_cell()
	_build_crates()
	_build_mast()


func _process(delta: float) -> void:
	var before := fmod(_beacon_time, BEACON_PERIOD)
	_beacon_time += delta
	var phase := fmod(_beacon_time, BEACON_PERIOD)
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 6.0 if phase < 0.5 else 0.6
	if phase < before and not Engine.is_editor_hint():
		beacon_flashed.emit(to_global(BEACON_POSITION))


func cell_point() -> Vector3:
	return to_global(CELL_POSITION + Vector3(0.0, -1.35, 1.3))


func has_cell() -> bool:
	return _cell != null and _cell.visible


func take_cell() -> void:
	_cell.visible = false
	_cell_light.visible = false


func spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in SPAWN_POINTS:
		out.append(to_global(p))
	return out


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


func _build_pad_and_building() -> void:
	_static_box(Vector3(26.0, 0.2, 24.0), Vector3(0.0, 0.0, -1.0), _mat(Color("4a4f52"), 0.95))
	var shell := CSGCombiner3D.new()
	shell.name = "Building"
	shell.use_collision = true
	add_child(shell)
	var wall := _mat(Color("8a8f86"), 0.9)
	var inner := _mat(Color("5c615c"), 0.9)
	_csg(shell, Vector3(10.0, 4.0, 7.0), Vector3(0.0, 2.0, -5.5), wall)
	_csg(shell, Vector3(9.6, 3.7, 6.6), Vector3(0.0, 1.95, -5.5), inner, true)
	_csg(shell, Vector3(2.0, 2.5, 0.8), Vector3(0.0, 1.35, -2.0), inner, true)
	_csg(shell, Vector3(2.0, 1.0, 0.8), Vector3(3.2, 1.9, -2.0), inner, true)
	_csg(shell, Vector3(2.0, 1.0, 0.8), Vector3(-3.2, 1.9, -2.0), inner, true)
	_csg(shell, Vector3(0.8, 2.3, 1.5), Vector3(5.0, 1.25, -5.8), inner, true)
	# Collapsed roof section lets a shaft of daylight onto the cell.
	_csg(shell, Vector3(3.0, 0.8, 3.0), Vector3(1.5, 4.0, -6.8), inner, true)
	var slab := _static_box(Vector3(3.0, 0.2, 2.6), Vector3(2.4, 0.9, -4.6), wall)
	slab.rotation = Vector3(0.5, 0.2, 0.3)
	_static_box(Vector3(0.6, 1.0, 3.0), Vector3(-4.4, 0.6, -6.0), _mat(Color("24282b"), 0.5))
	_static_box(Vector3(2.4, 1.0, 0.6), Vector3(-2.5, 0.6, -8.5), _mat(Color("24282b"), 0.5))
	_static_box(Vector3(1.6, 0.6, 0.05), Vector3(-2.5, 1.6, -8.75), _emissive(Color("3fd1b5"), 0.4))


func _build_cover() -> void:
	var concrete := _mat(Color("6f746e"), 0.95)
	var rust := _mat(Color("8a4a2a"), 0.8)
	_static_box(Vector3(4.0, 1.2, 0.4), Vector3(-7.5, 0.7, 3.0), concrete)
	_static_box(Vector3(0.4, 1.2, 5.0), Vector3(7.0, 0.7, 1.0), concrete)
	var low_wall := _static_box(Vector3(5.0, 1.1, 0.4), Vector3(-1.5, 0.65, 7.0), concrete)
	low_wall.rotation.y = 0.25
	var broken_wall := _static_box(Vector3(3.0, 1.0, 0.4), Vector3(10.5, 0.6, -6.0), concrete)
	broken_wall.rotation.y = -0.6
	var container := _static_box(Vector3(6.0, 2.6, 2.4), Vector3(-10.0, 1.3, -5.0), rust)
	container.rotation = Vector3(0.0, 0.3, 0.08)
	for p in [Vector3(3.0, 0.6, 4.5), Vector3(9.0, 0.6, -3.0), Vector3(-5.5, 0.6, 9.0), Vector3(4.2, 0.6, 9.5)]:
		var crate := _static_box(Vector3(1.1, 1.1, 1.1), p, _mat(Color("6b6a52"), 0.9))
		crate.rotation.y = p.x


func _build_cell() -> void:
	_static_box(Vector3(1.2, 0.9, 0.8), CELL_POSITION + Vector3(0.0, -0.9, 0.0), _mat(Color("3a3f43"), 0.5))
	_cell = MeshInstance3D.new()
	_cell.name = "AuxPowerCell"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.7, 0.3)
	_cell.mesh = box
	_cell.material_override = _emissive(Color("f2a93b"), 2.5)
	_cell.position = CELL_POSITION
	add_child(_cell)
	_cell_light = OmniLight3D.new()
	_cell_light.light_color = Color("ffb24d")
	_cell_light.light_energy = 1.5
	_cell_light.omni_range = 5.0
	_cell_light.position = CELL_POSITION + Vector3(0.0, 0.8, 0.6)
	add_child(_cell_light)


func _build_crates() -> void:
	for p in CRATE_POINTS:
		var holder := Node3D.new()
		holder.position = p
		add_child(holder)
		var body := _static_box(Vector3(1.4, 0.8, 0.9), p + Vector3(0.0, 0.4, 0.0), _mat(Color("c4622d"), 0.8))
		var lid := MeshInstance3D.new()
		var lid_mesh := BoxMesh.new()
		lid_mesh.size = Vector3(1.45, 0.08, 0.95)
		lid.mesh = lid_mesh
		lid.material_override = _emissive(Color("f2a93b"), 0.8)
		lid.position = Vector3(0.0, 0.84, 0.0)
		holder.add_child(lid)
		body.name = "SalvageCrate"
		_crates.append(holder)
		_crate_searched.append(false)


func _build_mast() -> void:
	_static_box(Vector3(0.3, 16.0, 0.3), Vector3(6.0, 8.0, -8.0), _mat(Color("3a3f43"), 0.5))
	_static_box(Vector3(2.0, 0.1, 0.1), Vector3(6.0, 14.0, -8.0), _mat(Color("3a3f43"), 0.5))
	var beacon := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	beacon.mesh = sphere
	_beacon_mat = _emissive(Color("ff4030"), 6.0)
	beacon.material_override = _beacon_mat
	beacon.position = BEACON_POSITION
	add_child(beacon)


func _csg(parent: Node, size: Vector3, pos: Vector3, mat: Material, subtract := false) -> void:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	if subtract:
		b.operation = CSGShape3D.OPERATION_SUBTRACTION
	parent.add_child(b)


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
	var m := _mat(color, 0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
