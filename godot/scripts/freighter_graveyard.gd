@tool
class_name FreighterGraveyard
extends ExpeditionSite
## The bones of the freighter Long Patience: hull ribs, fallen plates that make a maze, and the
## engine section at the back, open at the nozzle. The drive coil is inside. Live conduits arc
## across the gaps in the maze. The approach faces +Z.

## Arc conduits across the maze gaps: [centre, span, yaw].
const ARCS := [
	[Vector3(0.6, 0.0, -5.0), 4.2, 0.0],
	[Vector3(0.0, 0.0, -14.6), 5.0, 0.0],
	[Vector3(-12.5, 0.0, -3.0), 3.6, PI * 0.5],
	[Vector3(12.0, 0.0, -14.0), 3.6, PI * 0.5],
]
const ENGINE_FLOOR := 0.6

var _arcs: Array[Node3D] = []


func _configure() -> void:
	component_id = "drive_coil"
	component_pos = Vector3(0.0, ENGINE_FLOOR + 1.35, -26.5)
	component_stand = Vector3(0.0, ENGINE_FLOOR, -25.2)
	spawn_pts = [
		Vector3(-8.0, 0.3, 6.0), Vector3(8.0, 0.3, 4.0), Vector3(-10.0, 0.3, -8.0), Vector3(10.0, 0.3, -11.0),
		Vector3(0.0, 0.3, -1.0), Vector3(-5.0, 0.3, -19.0), Vector3(6.0, 0.3, -21.0),
	]
	ambush_pts = [Vector3(-14.0, 0.3, 10.0), Vector3(14.0, 0.3, 10.0), Vector3(0.0, 0.3, 16.0), Vector3(-16.0, 0.3, -2.0)]
	spawn_kinds = ["", "spitter", "ram", "", "", "ram", "spitter"]
	ambush_kinds = ["ram", "", "spitter", ""]
	crate_pts = [Vector3(-7.0, 0.0, 1.0), Vector3(7.0, 0.0, -7.0), Vector3(-6.0, 0.0, -16.0), Vector3(7.5, 0.0, -19.0)]
	crate_scrap = 15
	beacon_pos = Vector3(0.0, 10.0, -26.0)
	beacon_color = Color("f4f4ff")
	beacon_period = 2.6
	beacon_on = 1.2
	mission = _mission()


func arcs() -> Array[Node3D]:
	return _arcs


func _build_site() -> void:
	_arcs.clear()
	var hull := _mat(Color("5a5f5c"), 0.75, 0.4)
	var rust := _mat(Color("6a4a3a"), 0.85, 0.2)
	var dark := _mat(Color("2a2d30"), 0.85)
	_disc(Vector3(0.0, 0.0, -8.0), 24.0, 0.02, _mat(Color("202325"), 0.95))
	# Ribs: arches of the old hull, the landmark from a distance.
	for z in [8.0, 2.0, -4.0, -10.0, -16.0]:
		for side in [-1.0, 1.0]:
			var post := _static_box(Vector3(1.0, 10.0, 1.0), Vector3(side * 10.5, 4.6, z), hull)
			post.rotation.z = side * 0.12
		_static_box(Vector3(20.0, 0.9, 0.9), Vector3(0.0, 9.4, z), hull)
	# Fallen plates: a loose zig-zag toward the engine.
	var plates := [
		[Vector3(8.0, 4.0, 0.5), Vector3(-5.0, 2.0, -2.0), 0.1],
		[Vector3(8.0, 4.0, 0.5), Vector3(5.2, 2.0, -8.0), -0.1],
		[Vector3(0.5, 4.0, 7.0), Vector3(-9.0, 2.0, -10.0), 0.0],
		[Vector3(6.0, 4.0, 0.5), Vector3(-4.5, 2.0, -12.5), 0.2],
		[Vector3(0.5, 3.5, 6.0), Vector3(9.5, 1.75, -1.0), 0.0],
	]
	for p in plates:
		var plate := _static_box(p[0], p[1], rust)
		plate.rotation = Vector3(0.0, p[2], 0.06)
	for p in [Vector3(-14.0, 0.0, 6.0), Vector3(15.0, 0.0, -6.0), Vector3(-15.0, 0.0, -18.0)]:
		var leaning := _static_box(Vector3(6.0, 0.4, 5.0), p + Vector3(0.0, 1.6, 0.0), hull)
		leaning.rotation = Vector3(0.0, p.x, 0.7)
	_build_engine(hull, dark)
	_build_arcs()


## The engine section lies along z with its nozzle open toward the maze.
func _build_engine(hull: Material, dark: Material) -> void:
	var engine := CSGCombiner3D.new()
	engine.name = "EngineSection"
	engine.use_collision = true
	add_child(engine)
	var outer := CSGCylinder3D.new()
	outer.radius = 4.2
	outer.height = 12.0
	outer.sides = 20
	outer.rotation.x = PI * 0.5
	outer.position = Vector3(0.0, 4.2, -24.0)
	outer.material = hull
	engine.add_child(outer)
	var inner := CSGCylinder3D.new()
	inner.radius = 3.8
	inner.height = 12.0
	inner.sides = 20
	inner.rotation.x = PI * 0.5
	inner.position = Vector3(0.0, 4.2, -23.6)
	inner.operation = CSGShape3D.OPERATION_SUBTRACTION
	inner.material = dark
	engine.add_child(inner)
	_static_box(Vector3(4.6, 0.2, 11.6), Vector3(0.0, ENGINE_FLOOR - 0.1, -23.8), _mat(Color("3a3f43"), 0.5, 0.6))
	_slab(Vector3(0.0, 0.0, -15.6), Vector3(0.0, ENGINE_FLOOR, -18.2), 3.0, 0.3, _mat(Color("3a3f43"), 0.5, 0.6))
	_light(Vector3(0.0, 3.4, -24.0), Color("ff9a5a"), 1.0, 7.0)
	for i in 6:
		var a := TAU * i / 6.0
		_mesh_box(Vector3(0.3, 0.3, 11.0), Vector3(cos(a) * 3.7, 4.2 + sin(a) * 3.7, -24.0), _emissive(Color("ff7a3a"), 0.4))


func _build_arcs() -> void:
	for i in ARCS.size():
		var a: Array = ARCS[i]
		if Engine.is_editor_hint():
			_mesh_box(Vector3(a[1], 0.1, 0.4), a[0] + Vector3.UP * 1.2, _emissive(Color("9fd8ff"), 1.0)).rotation.y = a[2]
			continue
		var arc := ArcGap.new()
		arc.span = a[1]
		arc.position = a[0]
		arc.rotation.y = a[2]
		arc.offset = i * 0.9
		add_child(arc)
		_arcs.append(arc)


func _build_component_visual(holder: Node3D) -> void:
	var coil := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.18
	torus.outer_radius = 0.36
	coil.mesh = torus
	coil.material_override = _emissive(Color("ff7a3a"), 2.5)
	coil.rotation.x = PI * 0.5
	holder.add_child(coil)
	var core := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.12
	cyl.height = 0.6
	core.mesh = cyl
	core.material_override = _mat(Color("9aa0a3"), 0.35, 0.8)
	core.rotation.x = PI * 0.5
	holder.add_child(core)

## The graveyard's mission: find the chief engineer's keycard, put down the yard's guardian,
## then hold the engine room while the coil housing unlocks.
func _mission() -> Array:
	var H := Story.HOB
	return [
		{
			"type": "activate", "text": "Find the chief engineer's keycard in the hull maze",
			"devices": [{"pos": Vector3(-12.5, 0.0, -12.0), "kind": "keycard", "label": "Take the keycard", "yaw": PI * 0.5}],
			"say": [[H, "The Long Patience locked her engine room when she came down. Sixty years ago. Her chief engineer died at his post, out in the maze, with the card."]],
		},
		{
			"type": "elite", "kind": "ram", "name": "YARD GUARDIAN", "pos": Vector3(0.0, 0.3, -12.0),
			"text": "Kill the yard guardian",
			"say": [[H, "Something heavy is moving between the ribs. It's been here as long as the wrecks. Don't let it pin you against a plate."]],
		},
		{
			"type": "defend", "text": "Unlock the drive coil's housing",
			"running_text": "Hold the engine room while the coil housing unlocks",
			"device": {"pos": Vector3(1.6, ENGINE_FLOOR, -22.5), "kind": "console", "label": "Swipe the keycard", "yaw": -PI * 0.5},
			"bar": "HOUSING UNLOCK", "seconds": 35.0, "radius": 10.0, "wave_every": 10.0, "lift": 0.0,
			"waves": [["spitter", "scuttler", "scuttler"], ["ram", "scuttler", "spitter"], ["scuttler", "scuttler", "ram", "spitter"]],
			"say": [[H, "Guardian's down. Swipe the card at the engine console. The housing will take its time."]],
			"start_say": [[H, "Housing's cycling. Sixty-year-old seals, Juno. It's loud."]],
			"done_say": [[H, "Housing open. The coil's yours."]],
		},
	]
