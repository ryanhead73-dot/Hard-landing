@tool
class_name MossDropship
extends ExpeditionSite
## The rescue dropship Ferro-9, broken in two in a field of giant glowing moss. Spore fog hangs
## low and cuts visibility; spore pods burst when you get close or shoot them. The wing-tip panel
## is still on the dropship's port wing. The approach faces +Z.

const POD_POINTS := [
	Vector3(-4.0, 0.0, 6.0), Vector3(5.0, 0.0, 4.0), Vector3(0.5, 0.0, 10.5), Vector3(-10.0, 0.0, 1.0),
	Vector3(9.0, 0.0, -3.0), Vector3(-1.5, 0.0, -0.5), Vector3(6.0, 0.0, -9.0), Vector3(-5.5, 0.0, -14.0),
]

var _pods: Array[Node3D] = []
var _fog: FogVolume


func _configure() -> void:
	component_id = "wing_panel"
	component_pos = Vector3(-9.0, 1.35, -2.6)
	component_stand = Vector3(-9.0, 0.0, -1.3)
	spawn_pts = [
		Vector3(-8.0, 0.3, 6.0), Vector3(8.0, 0.3, 8.0), Vector3(10.0, 0.3, -10.0),
		Vector3(-12.0, 0.3, -14.0), Vector3(0.0, 0.3, -18.0), Vector3(3.0, 0.3, 1.5),
	]
	ambush_pts = [Vector3(-14.0, 0.3, 12.0), Vector3(14.0, 0.3, 12.0), Vector3(0.0, 0.3, 18.0), Vector3(16.0, 0.3, 0.0)]
	spawn_kinds = ["", "spitter", "spitter", "", "ram", ""]
	ambush_kinds = ["spitter", "", "", "spitter"]
	crate_pts = [Vector3(7.5, 0.0, 8.5), Vector3(-12.5, 0.0, -8.5), Vector3(2.0, 0.0, -4.5)]
	crate_scrap = 14
	beacon_pos = Vector3(-3.0, 5.2, -6.0)
	beacon_color = Color("50ff7a")
	beacon_period = 1.0
	beacon_on = 0.25


func pods() -> Array[Node3D]:
	return _pods


func _build_site() -> void:
	_pods.clear()
	var carpet := _mat(Color("16302b"), 0.95)
	_disc(Vector3(0.0, 0.0, -3.0), 22.0, 0.02, carpet)
	_build_stalks()
	_build_dropship()
	_build_pods()
	_fog = FogVolume.new()
	_fog.name = "SporeFog"
	_fog.size = Vector3(46.0, 5.0, 46.0)
	_fog.position = Vector3(0.0, 2.0, -3.0)
	var fog_mat := FogMaterial.new()
	fog_mat.density = 0.12
	fog_mat.albedo = Color("8fbfa8")
	fog_mat.emission = Color("0f3a30")
	fog_mat.height_falloff = 0.6
	fog_mat.edge_fade = 0.3
	_fog.material = fog_mat
	add_child(_fog)


## Giant moss: thick stalks with glowing caps. Only the stalks block.
func _build_stalks() -> void:
	var stalk := _mat(Color("1d2b26"), 0.9)
	var cap := _emissive(Color("3fd1b5"), 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 400:
		tries += 1
		var p := Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-24.0, 16.0))
		if _keep_clear(p):
			continue
		var h := rng.randf_range(4.0, 9.5)
		_column(p, rng.randf_range(0.3, 0.6), h, stalk, 8)
		var top := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var r := rng.randf_range(1.4, 3.0)
		sphere.radius = r
		sphere.height = r * 0.8
		top.mesh = sphere
		top.material_override = cap
		top.position = p + Vector3(0.0, h, 0.0)
		add_child(top)
		placed += 1


## Clear of the dropship, the component, the crates, the pods and the way in.
func _keep_clear(p: Vector3) -> bool:
	if p.z > 4.0 and absf(p.x) < 4.0:
		return true
	if Rect2(-13.0, -16.0, 21.0, 14.0).has_point(Vector2(p.x, p.z)):
		return true
	for q in POD_POINTS + crate_pts + [component_stand]:
		if Vector2(p.x - q.x, p.z - q.z).length() < 3.0:
			return true
	return false


func _build_dropship() -> void:
	var paint := _mat(Color("8c9294"), 0.7, 0.3)
	var stripe := _mat(Color("e0b420"), 0.7)
	var dark := _mat(Color("24282b"), 0.6)
	# Rear section with the port wing still attached, dug in at an angle.
	var rear := Node3D.new()
	rear.name = "Ferro9Rear"
	rear.position = Vector3(-3.0, 0.0, -6.0)
	rear.rotation = Vector3(0.0, 0.25, 0.08)
	add_child(rear)
	_static_box(Vector3(4.0, 3.6, 9.0), Vector3(0.0, 1.8, 0.0), paint, rear)
	_mesh_box(Vector3(4.04, 0.4, 9.04), Vector3(0.0, 2.6, 0.0), stripe, rear)
	_mesh_box(Vector3(3.2, 2.8, 0.1), Vector3(0.0, 1.6, -4.52), dark, rear)
	var wing := _static_box(Vector3(6.4, 0.3, 2.8), Vector3(-5.0, 1.4, -0.4), paint, rear)
	wing.rotation.z = 0.18
	# Front section, nose down a little way off.
	var front := _static_box(Vector3(3.8, 3.0, 6.0), Vector3(4.5, 1.3, -13.0), paint)
	front.rotation = Vector3(0.3, -0.5, 0.1)
	_mesh_box(Vector3(2.4, 0.9, 0.1), Vector3(4.2, 2.2, -10.2), _emissive(Color("1c2a30"), 0.3))
	# Torn panels and cargo spilled between the halves.
	for i in 5:
		var plate := _mesh_box(Vector3(1.6, 0.06, 1.1), Vector3(1.0 + i * 0.6, 0.05, -9.0 + i * 0.4), paint)
		plate.rotation = Vector3(0.2 * i, i * 0.9, 0.1)
	_light(Vector3(-9.0, 2.6, -1.8), Color("ffe2a8"), 0.7, 5.0)


func _build_pods() -> void:
	if Engine.is_editor_hint():
		for p in POD_POINTS:
			_disc(p, 0.6, 0.6, _emissive(Color("b4e05a"), 0.8))
		return
	for p in POD_POINTS:
		var pod := SporePod.new()
		pod.position = p
		add_child(pod)
		_pods.append(pod)


func _build_component_visual(holder: Node3D) -> void:
	_mesh_box(Vector3(1.4, 0.9, 0.08), Vector3.ZERO, _mat(Color("e9e1cc"), 0.8), holder)
	_mesh_box(Vector3(1.42, 0.12, 0.1), Vector3(0.0, 0.3, 0.0), _mat(Color("c4622d"), 0.8), holder)
	_mesh_box(Vector3(0.08, 0.9, 0.12), Vector3(-0.66, 0.0, 0.0), _mat(Color("3a3f43"), 0.5, 0.6), holder)
