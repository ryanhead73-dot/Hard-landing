@tool
class_name QuarryCrawler
extends ExpeditionSite
## A mining crawler abandoned in a terraced quarry. The strut pack is in its maintenance bay: up the
## rear ramp and into the dark (bring the flashlight). Loose rock keeps falling from the faces.
## The open end of the quarry faces +Z.

const ROCKFALL_POINTS := [
	Vector3(-9.0, 0.0, -4.0), Vector3(9.0, 0.0, -10.0), Vector3(-8.0, 0.0, -16.0),
	Vector3(8.5, 0.0, 2.0), Vector3(-3.0, 0.0, 6.5), Vector3(4.0, 0.0, -19.5),
]
const BAY_FLOOR := 1.1

var _rockfalls: Array[Node3D] = []


func _configure() -> void:
	component_id = "struts"
	component_pos = Vector3(0.0, BAY_FLOOR + 1.35, -13.4)
	component_stand = Vector3(0.0, BAY_FLOOR, -12.1)
	spawn_pts = [
		Vector3(-10.0, 0.3, -2.0), Vector3(10.0, 0.3, -6.0), Vector3(-12.0, 0.3, -18.0),
		Vector3(12.0, 0.3, -18.0), Vector3(0.0, 0.3, 8.0), Vector3(1.5, BAY_FLOOR + 0.3, -6.0),
	]
	ambush_pts = [Vector3(-14.0, 0.3, 8.0), Vector3(14.0, 0.3, 8.0), Vector3(0.0, 0.3, 14.0), Vector3(-6.0, 0.3, 10.0)]
	spawn_kinds = ["spitter", "", "", "spitter", "ram", ""]
	ambush_kinds = ["", "", "ram", ""]
	crate_pts = [Vector3(-13.0, 0.0, -10.0), Vector3(13.0, 0.0, -2.0), Vector3(-2.2, BAY_FLOOR, -5.0)]
	crate_scrap = 12
	beacon_pos = Vector3(0.0, 7.6, -17.0)
	beacon_color = Color("b07aff")
	beacon_period = 1.8
	beacon_on = 0.9
	mission = _mission()


func rockfalls() -> Array[Node3D]:
	return _rockfalls


func _build_site() -> void:
	_rockfalls.clear()
	_build_quarry()
	_build_crawler()
	_build_rockfalls()


func _build_quarry() -> void:
	var gravel := _mat(Color("4a4f52"), 0.95)
	_disc(Vector3(0.0, 0.0, -6.0), 22.0, 0.02, gravel)
	# Back face and two side faces cut into columnar basalt, each with a lower terrace in front.
	_basalt_block(Vector3(44.0, 9.0, 4.0), Vector3(0.0, 4.5, -26.0), 1, 1.4)
	_basalt_block(Vector3(40.0, 3.0, 3.0), Vector3(0.0, 1.5, -22.5), 2, 0.1)
	for side in [-1.0, 1.0]:
		_basalt_block(Vector3(4.0, 7.0, 28.0), Vector3(side * 21.0, 3.5, -10.0), 3 + int(side), 1.2)
		_basalt_block(Vector3(3.0, 2.5, 24.0), Vector3(side * 17.5, 1.25, -10.0), 6 + int(side), 0.1)
	# Spoil heaps and a conveyor gantry for cover on the floor.
	for p in [Vector3(-7.0, 0.0, 10.0), Vector3(11.0, 0.0, 9.0), Vector3(-12.0, 0.0, -1.0)]:
		var heap := _column(p, 2.2, 1.6, gravel, 7)
		heap.rotation.y = p.x
	_static_box(Vector3(0.4, 3.0, 0.4), Vector3(8.0, 1.5, -14.0), _mat(Color("8a4a2a"), 0.7, 0.4))
	_static_box(Vector3(0.4, 3.0, 0.4), Vector3(8.0, 1.5, -4.0), _mat(Color("8a4a2a"), 0.7, 0.4))
	_static_box(Vector3(1.4, 0.3, 11.0), Vector3(8.0, 3.1, -9.0), _mat(Color("8a4a2a"), 0.7, 0.4))


## The crawler is modelled in this site's coordinates (blender/build_sites.py): tracks, a hollow
## body with a rear door and ramp, the cab and the drill boom. Collision is plain boxes under it.
func _build_crawler() -> void:
	var steel := _mat(Color("3a3f43"), 0.5, 0.6)
	var inner := _mat(Color("2a2d30"), 0.9)
	Rig.spawn("site_crawler", self)
	for side in [-1.0, 1.0]:
		_collider(Vector3(1.6, 1.6, 15.0), Vector3(side * 4.4, 0.8, -8.0))
		_collider(Vector3(0.3, 4.0, 14.0), Vector3(side * 3.45, 2.6, -8.0))
		_collider(Vector3(2.1, 4.0, 0.4), Vector3(side * 2.55, 2.6, -1.2))
	_collider(Vector3(7.2, 0.3, 14.0), Vector3(0.0, 4.45, -8.0))
	_collider(Vector3(7.2, 4.0, 0.4), Vector3(0.0, 2.6, -14.8))
	_collider(Vector3(3.0, 0.8, 0.4), Vector3(0.0, 4.2, -1.2))
	# Everything under the bay floor, down to the ground.
	_collider(Vector3(7.2, BAY_FLOOR, 13.6), Vector3(0.0, BAY_FLOOR * 0.5, -8.2))
	_collider(Vector3(6.0, 3.0, 4.0), Vector3(0.0, 6.1, -13.0))
	_collider(Vector3(1.0, 1.0, 9.0), Vector3(0.0, 3.0, -19.0), Vector3(-0.25, 0.0, 0.0))
	# Bay floor plate, and the ramp up from the quarry floor.
	_static_box(Vector3(6.6, 0.1, 13.2), Vector3(0.0, BAY_FLOOR - 0.05, -8.0), inner)
	_slab(Vector3(0.0, 0.0, 2.6), Vector3(0.0, BAY_FLOOR, -1.6), 2.8, 0.3, steel)
	# Dim red emergency lamp inside; the rest is up to the flashlight.
	_light(Vector3(0.0, BAY_FLOOR + 2.8, -9.0), Color("ff3b2e"), 0.35, 5.0)
	_mesh_box(Vector3(0.6, 0.08, 0.2), Vector3(0.0, BAY_FLOOR + 3.0, -9.0), _emissive(Color("ff3b2e"), 2.0))


func _build_rockfalls() -> void:
	if Engine.is_editor_hint():
		for p in ROCKFALL_POINTS:
			_disc(p, 1.8, 0.04, _emissive(Color("d8b48a"), 0.4))
		return
	for i in ROCKFALL_POINTS.size():
		var r := Rockfall.new()
		r.position = ROCKFALL_POINTS[i]
		r.offset = i * 1.1
		add_child(r)
		_rockfalls.append(r)


func _build_component_visual(holder: Node3D) -> void:
	var steel := _mat(Color("9aa0a3"), 0.35, 0.8)
	var seal := _mat(Color("c4622d"), 0.7)
	for x in [-0.22, 0.0, 0.22]:
		var piston := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.1
		cyl.height = 1.2
		piston.mesh = cyl
		piston.material_override = steel
		piston.position.x = x
		holder.add_child(piston)
	_mesh_box(Vector3(0.6, 0.1, 0.25), Vector3(0.0, 0.55, 0.0), seal, holder)
	_mesh_box(Vector3(0.6, 0.1, 0.25), Vector3(0.0, -0.55, 0.0), seal, holder)

## The quarry's mission: get the floodlights back on, then hold the crawler while its crane
## lowers the strut pack out of the rafters.
func _mission() -> Array:
	var H := Story.HOB
	return [
		{
			"type": "activate", "text": "Restart the quarry floodlights",
			"devices": [
				{"pos": Vector3(-5.0, 0.0, 2.0), "kind": "floodlight", "label": "Restart the floodlight", "hold": 1.0},
				{"pos": Vector3(5.5, 0.0, 3.0), "kind": "floodlight", "label": "Restart the floodlight", "hold": 1.0},
				{"pos": Vector3(2.4, BAY_FLOOR, -9.0), "kind": "floodlight", "label": "Restart the floodlight", "hold": 1.0},
			],
			"say": [[H, "It's black as pitch in that quarry, and the rams like the dark. The crew left floodlights on battery."]],
		},
		{
			"type": "defend", "text": "Power the crawler's crane to lower the strut pack",
			"running_text": "Defend the crawler while its crane lowers the struts",
			"device": {"pos": Vector3(-2.4, BAY_FLOOR, -11.0), "kind": "crane", "label": "Power the crane", "yaw": PI * 0.5},
			"bar": "CRANE LOWERING", "seconds": 40.0, "radius": 12.0, "wave_every": 11.0, "lift": 1.5,
			"spawns": [Vector3(-11.0, 0.3, 8.0), Vector3(11.0, 0.3, 8.0), Vector3(0.0, 0.3, 13.0)],
			"waves": [["scuttler", "scuttler", "spitter"], ["ram", "scuttler", "scuttler"], ["spitter", "scuttler", "ram", "scuttler"]],
			"say": [[H, "Good. The strut pack's slung up in the crane. Power the console and it'll lower it, slowly."]],
			"start_say": [[H, "Crane's moving. The noise is carrying up the quarry walls. Brace."]],
			"done_say": [[H, "Pack's down. Take it before anything else wakes up."]],
		},
	]
