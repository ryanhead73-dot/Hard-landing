@tool
class_name HaulerWreck
extends ExpeditionSite
## A coolant hauler that came down in the hot springs: the second expedition. The manifold Kestrel
## needs is still racked at the back of its hold. Steam vents in the pool guard the approach.
## The open cargo door faces +Z. The tail strobe makes it findable.

const VENT_POINTS := [
	Vector3(-3.5, 0.0, 9.0), Vector3(2.8, 0.0, 11.5), Vector3(-0.8, 0.0, 14.2),
	Vector3(5.2, 0.0, 14.0), Vector3(-6.2, 0.0, 12.8), Vector3(1.0, 0.0, 6.6),
]
const CRATE_SCRAP := 12
const MANIFOLD_POSITION := Vector3(0.0, 1.25, -14.6)

var _vents: Array[Node3D] = []


func _configure() -> void:
	component_id = "manifold"
	component_pos = MANIFOLD_POSITION
	component_stand = Vector3(0.0, 0.0, -13.3)
	spawn_pts = [Vector3(-9.0, 0.3, 4.0), Vector3(9.0, 0.3, 2.0), Vector3(8.0, 0.3, -12.0), Vector3(-8.0, 0.3, -15.0)]
	ambush_pts = [Vector3(-12.0, 0.3, 12.0), Vector3(12.0, 0.3, 14.0), Vector3(0.0, 0.3, 20.0)]
	crate_pts = [Vector3(-1.9, 0.0, -10.6), Vector3(1.9, 0.0, -3.0), Vector3(-7.5, 0.0, -4.0)]
	crate_scrap = CRATE_SCRAP
	beacon_pos = Vector3(0.0, 9.6, 1.0)
	beacon_color = Color("bfe8ff")
	beacon_period = 2.2
	beacon_on = 0.12


func _build_site() -> void:
	_vents.clear()
	_build_pool()
	_build_hull()
	_build_hold()
	_build_vents()


## Backwards-compatible name for the manifold pickup point.
func manifold_point() -> Vector3:
	return component_point()


func vents() -> Array[Node3D]:
	return _vents


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


func _build_component_visual(holder: Node3D) -> void:
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
		holder.add_child(pipe)
	for x in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(0.12, 0.62, 0.22)
		cap.mesh = cap_mesh
		cap.material_override = frost
		cap.position.x = x
		holder.add_child(cap)


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
