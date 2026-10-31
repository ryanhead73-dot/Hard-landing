@tool
class_name ExpeditionSite
extends Node3D
## Base for every expedition site: the component Kestrel needs, salvage crates, a resident pack,
## an ambush when the component is taken and a beacon that leads the player there.
## Local space: the approach faces +Z, toward Kestrel. Subclasses set the fields in _configure()
## and build their own layout in _build_site().

## Fires on each beacon flash, in the game only (not in the editor).
signal beacon_flashed(at: Vector3)

const CRATE_COLOR := Color("c4622d")

## Which Campaign component this site holds.
var component_id := ""
## Where the component sits, and where the player stands to take it.
var component_pos := Vector3.ZERO
var component_stand := Vector3.ZERO
var spawn_pts: Array = []
var ambush_pts: Array = []
var crate_pts: Array = []
var crate_scrap := 10
var beacon_pos := Vector3(0.0, 10.0, 0.0)
var beacon_color := Color.WHITE
var beacon_period := 1.6
## Seconds of each period the beacon is lit.
var beacon_on := 0.5
## How far from the site centre the resident pack wakes up.
var wake_radius := 55.0
## Enemy kind per spawn point and per ambush point, by index; scuttlers where unset.
var spawn_kinds: Array = []
var ambush_kinds: Array = []
## The mission worked before the component can be taken: stage dictionaries (see MissionRunner).
var mission: Array = []
## True when this is the site the player should head for: the beacon flashes bright.
var active := false
## The resident pack has been spawned (once per game).
var pack_spawned := false

var _crates: Array[Node3D] = []
var _crate_searched: Array[bool] = []
var _component: Node3D
var _component_light: OmniLight3D
var _beacon_mat: StandardMaterial3D
var _beacon_time := 0.0
var _mats: Dictionary = {}


func _ready() -> void:
	build()


func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_crates.clear()
	_crate_searched.clear()
	_configure()
	_build_site()
	_build_component()
	_build_crates()
	_build_beacon()


## Override: set component_id, positions, crates, spawns and beacon.
func _configure() -> void:
	pass


## Override: build the site's own layout.
func _build_site() -> void:
	pass


func _process(delta: float) -> void:
	var before := fmod(_beacon_time, beacon_period)
	_beacon_time += delta
	var phase := fmod(_beacon_time, beacon_period)
	if _beacon_mat:
		var lit := phase < beacon_on
		_beacon_mat.emission_energy_multiplier = (8.0 if lit else 0.5) if active else (1.2 if lit else 0.2)
	if phase < before and not Engine.is_editor_hint():
		beacon_flashed.emit(to_global(beacon_pos))


# --- Public API ---------------------------------------------------------------------------

func component_point() -> Vector3:
	return to_global(component_stand)


func has_component() -> bool:
	return _component != null and _component.visible


func take_component() -> void:
	_component.visible = false
	_component_light.visible = false


func spawn_points() -> Array[Vector3]:
	return _to_global_all(spawn_pts)


func ambush_points() -> Array[Vector3]:
	return _to_global_all(ambush_pts)


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
	# A searched crate's lid goes dark.
	var lid: StandardMaterial3D = _crates[i].get_meta("lid", null)
	if lid:
		lid.emission_enabled = false
		lid.albedo_color = Color("24282b")
	return crate_scrap


func spawn_kind(i: int) -> String:
	return spawn_kinds[i] if i < spawn_kinds.size() and spawn_kinds[i] != "" else "scuttler"


func ambush_kind(i: int) -> String:
	return ambush_kinds[i] if i < ambush_kinds.size() and ambush_kinds[i] != "" else "scuttler"


## Saved per site: whether the component is gone and which crates were searched.
func get_state() -> Dictionary:
	return {"component_taken": not has_component(), "crates": _crate_searched.duplicate(), "pack_spawned": pack_spawned}


func set_state(state: Dictionary) -> void:
	var taken: bool = state.get("component_taken", false)
	_component.visible = not taken
	_component_light.visible = not taken
	var searched: Array = state.get("crates", [])
	for i in mini(searched.size(), _crates.size()):
		_crate_searched[i] = false
		if searched[i]:
			search_crate(i)
	pack_spawned = state.get("pack_spawned", false)


## Where every mission device stands (local), so layouts can keep those spots clear.
func mission_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for st in mission:
		for d in st.get("devices", []):
			out.append(d["pos"])
		if st.has("device"):
			out.append(st["device"]["pos"])
	return out


## Mission hooks. Override to show a stage's effect on the site (vents shut, lights on).
## `animate` is false when snapping to a loaded save.
func on_stage_done(_stage: int, _animate: bool) -> void:
	pass


func on_device_done(_stage: int, _index: int, _animate: bool) -> void:
	pass


## Raises the component above its stand (a crane or cradle bringing it down during a defend).
func set_component_lift(height: float) -> void:
	if _component:
		_component.position = component_pos + Vector3.UP * height
		_component_light.position = component_pos + Vector3(0.0, 0.8 + height, 0.6)


# --- Building -----------------------------------------------------------------------------

func _build_component() -> void:
	var stand := _static_box(Vector3(1.2, 0.9, 0.8), component_pos + Vector3(0.0, -0.9, 0.0), _mat(Color("3a3f43"), 0.5))
	stand.name = "ComponentStand"
	_component = Node3D.new()
	_component.name = "Component"
	_component.position = component_pos
	add_child(_component)
	_build_component_visual(_component)
	var pack: Array = Campaign.PACKS.get(component_id, [Vector3.ONE * 0.5, Color.WHITE, 1.0])
	_component_light = OmniLight3D.new()
	_component_light.light_color = pack[1]
	_component_light.light_energy = 1.4
	_component_light.omni_range = 5.0
	_component_light.position = component_pos + Vector3(0.0, 0.8, 0.6)
	add_child(_component_light)


## Override for a bespoke component model. Default: the component's own model.
func _build_component_visual(holder: Node3D) -> void:
	Rig.spawn(component_id, holder)


func _build_crates() -> void:
	for p in crate_pts:
		var holder := Node3D.new()
		holder.position = p
		add_child(holder)
		var crate := Rig.spawn("crate", holder)
		holder.set_meta("lid", Rig.own_material(crate, "lid_glow"))
		var body := StaticBody3D.new()
		body.name = "SalvageCrate"
		body.position = p + Vector3(0.0, 0.4, 0.0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.4, 0.8, 0.9)
		shape.shape = box
		body.add_child(shape)
		add_child(body)
		_crates.append(holder)
		_crate_searched.append(false)


func _build_beacon() -> void:
	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	beacon.mesh = sphere
	_beacon_mat = _emissive(beacon_color, 6.0)
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon.material_override = _beacon_mat
	beacon.position = beacon_pos
	add_child(beacon)


# --- Helpers ------------------------------------------------------------------------------

func _to_global_all(points: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in points:
		out.append(to_global(p))
	return out


func _csg(parent: Node, size: Vector3, pos: Vector3, mat: Material, subtract := false) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	if subtract:
		b.operation = CSGShape3D.OPERATION_SUBTRACTION
	parent.add_child(b)
	return b


func _disc(pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	# The basin's own ground now reads better than a painted disc under a whole site.
	if radius >= 15.0 and mat is StandardMaterial3D and not (mat as StandardMaterial3D).emission_enabled:
		return mesh
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 40
	mesh.mesh = cyl
	mesh.material_override = mat
	mesh.position = pos + Vector3(0.0, height * 0.5, 0.0)
	add_child(mesh)
	return mesh


func _mesh_box(size: Vector3, pos: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = Bevel.box(size)
	mesh.material_override = mat
	mesh.position = pos
	(parent if parent else self).add_child(mesh)
	return mesh


func _static_box(size: Vector3, pos: Vector3, mat: Material, parent: Node = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	mesh.mesh = Bevel.box(size)
	mesh.material_override = mat
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(mesh)
	body.add_child(shape)
	(parent if parent else self).add_child(body)
	return body


## Upright prism (a basalt column when sides is 6), standing on y = base.
func _column(pos: Vector3, radius: float, height: float, mat: Material, sides := 6) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0.0, height * 0.5, 0.0)
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = sides
	cyl.rings = 1
	mesh.mesh = cyl
	# Dark stone columns share the world's basalt.
	var dark := mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_color.get_luminance() < 0.2
	mesh.material_override = WorldProps.rock_material() if dark else mat
	var shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = radius
	cyl_shape.height = height
	shape.shape = cyl_shape
	body.add_child(mesh)
	body.add_child(shape)
	add_child(body)
	return body


## Walkable slab whose top surface runs from one point to another (both on the top face).
## Overrun carries it on past `to`, so it rests over a ledge without leaving a lip at the edge.
func _slab(from: Vector3, to: Vector3, width: float, thickness: float, mat: Material, overrun := 0.0) -> StaticBody3D:
	to += (to - from).normalized() * overrun
	var d := to - from
	var length := d.length()
	var forward := d / length
	var across := Vector3.UP.cross(forward).normalized()
	var up := forward.cross(across).normalized()
	if up.y < 0.0:
		up = -up
		across = -across
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis(across, up, forward), (from + to) * 0.5 - up * thickness * 0.5)
	var size := Vector3(width, thickness, length)
	var mesh := MeshInstance3D.new()
	mesh.mesh = Bevel.box(size)
	mesh.material_override = mat
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(mesh)
	body.add_child(shape)
	add_child(body)
	return body


func _light(pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = light_range
	lamp.position = pos
	add_child(lamp)
	return lamp


func _mat(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [color.to_html(), roughness, metallic]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if color.get_luminance() < 0.18:
		Surfaces.apply_basalt(m, 5.0)
	else:
		Surfaces.apply_hull(m, 3.0)
	_mats[key] = m
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
