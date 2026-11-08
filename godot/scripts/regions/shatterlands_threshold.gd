class_name ShatterlandsThreshold
extends ShatterScene
## Expansion prototype (X1.3): the first pocket of the Shatterlands, past the canyon from the
## Kettle. A greybox to prove the region layer and set the look: a giant fungal canopy in purple
## and blue, stepped basalt shelves to climb, and a wrecked hull half-buried in the growth. Not
## final art; built in code so it costs nothing to change while the region is designed.
##
## Local space: Juno arrives at the canyon mouth on +Z and looks north (-Z) up the shelves.

const SEED := 44

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
## Voss's cache of spare grow-lamp cells, at the back of the high shelf (Teo's favour).
const CELL_CACHE := Vector3(-22.0, 9.0, -43.0)
## The split in the north rim that leads on to the Gillwood (RegionDB gate_pos is just inside it).
const NORTH_SPLIT := Vector3(-45.0, 0.0, -62.0)

## Voss's greenhouses, the Act 2 hub (greybox).
var greenhouses: Greenhouses
## Where Juno stands to open the wrecked hauler's dorsal locker (world space).
var locker_pos := Vector3.INF
var _locker_tell: MeshInstance3D
## Where Juno stands to take a cell from Voss's cache (world space).
var cache_pos := Vector3.INF
var _cache_tell: MeshInstance3D
## The survivors' barricade across the north split, until Reyes has it pulled back.
var _barricade: Node3D


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
	_north_split()
	# The shelves are the tops of basalt columns, the joints showing.
	for s in SHELVES:
		_box(s[0], s[1], _basalt(6.0), true)
	# Each ramp tops out at its shelf's edge (Juno has no step-up, so a lip there stops her).
	_ramp(Vector3(-12.0, 0.0, -6.0), Vector3(-18.0, 3.0, -6.0), 5.0)
	_ramp(Vector3(-30.0, 3.0, -10.0), Vector3(-30.0, 6.0, -15.0), 5.0)
	_ramp(Vector3(-24.0, 6.0, -26.0), Vector3(-17.0, 9.0, -34.0), 5.0)
	_spots.clear()
	for f in FUNGI:
		var base: Vector3 = f[0]
		_fungus(base, f[1], f[2])
	_build_spots()
	_wreck()
	_cell_cache()
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
	if pos.distance_to(cache_pos) < 2.2:
		if Greenhouses.cell_wanted():
			return {"label": "[E] Take a lamp cell from Voss's cache", "action": take_cell}
		if not Game.flags.get("lamp_cell_found", false):
			return {"label": "A sealed cache with Voss's mark on the lid"}
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
	# Rim walls so the pocket reads as a valley and nobody walks off the edge.
	# The north wall has a split in it at NORTH_SPLIT, the way on to the Gillwood.
	_rim([[Vector3(-60.0, 10.0, -66.0), Vector3(20.0, 20.0, 8.0)], [Vector3(15.0, 10.0, -66.0), Vector3(110.0, 20.0, 8.0)], [Vector3(-66.0, 10.0, 0.0), Vector3(8.0, 20.0, 140.0)], [Vector3(66.0, 10.0, 0.0), Vector3(8.0, 20.0, 140.0)], [Vector3(-38.0, 10.0, 62.0), Vector3(64.0, 20.0, 8.0)], [Vector3(38.0, 10.0, 62.0), Vector3(64.0, 20.0, 8.0)]])


## The north split: a passage through the rim between basalt slabs, teal light from the Gillwood
## at its far end, and the survivors' scrap barricade across it until Reyes opens the way. Once
## she has, the waypoint moves from the greenhouse gate to here.
func _north_split() -> void:
	var at := NORTH_SPLIT
	for side in [-1.0, 1.0]:
		_box(at + Vector3(side * 5.5, 9.0, -8.0), Vector3(5.0, 18.0, 16.0), _basalt(8.0), true)
	_box(at + Vector3(0.0, 9.0, -17.0), Vector3(8.0, 18.0, 2.0), _basalt(8.0), false)
	_box(at + Vector3(0.0, 6.0, -15.8), Vector3(6.0, 12.0, 0.3), _glow(GILLS, 1.5), false)
	_barricade = Node3D.new()
	_barricade.name = "Barricade"
	add_child(_barricade)
	var plates := [[Vector3(-1.6, 1.3, -3.0), Vector3(2.4, 2.6, 0.2), 0.08], [Vector3(1.4, 1.1, -2.8), Vector3(2.6, 2.2, 0.2), -0.12], [Vector3(0.0, 2.6, -3.2), Vector3(4.6, 1.2, 0.2), 0.03]]
	for i in plates.size():
		var pl: Array = plates[i]
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.position = at + pl[0]
		body.rotation.z = pl[2]
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pl[1]
		mi.mesh = bm
		mi.material_override = _tex("greenhouse_palisade_scrap_hull", 4.0, true, [Color.WHITE, Color(1.0, 0.88, 0.8), Color(0.82, 0.82, 0.8)][i], _mat([HULL, OXIDE, HULL.darkened(0.2)][i], 0.7))
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = pl[1]
		shape.shape = bs
		body.add_child(mi)
		body.add_child(shape)
		_barricade.add_child(body)
	_sync_way_north()
	Game.flag_changed.connect(_on_flag_changed)


func _on_flag_changed(_flag: String, _value: Variant) -> void:
	_sync_way_north()


func way_north_open() -> bool:
	return Game.flags.get("reyes_talked", false) == true


func _sync_way_north() -> void:
	if not is_instance_valid(_barricade):
		return
	var open := way_north_open()
	_barricade.visible = not open
	for b in _barricade.get_children():
		(b as CollisionObject3D).collision_layer = 0 if open else Game.LAYER_WORLD
	if open:
		goal = NORTH_SPLIT + Vector3(0.0, 1.0, 0.0)


## Two tall basalt slabs either side of the canyon Juno came through, with the way back between.
func _canyon_mouth() -> void:
	_box(Vector3(-5.5, 9.0, 50.0), Vector3(5.0, 18.0, 16.0), _basalt(8.0), true)
	_box(Vector3(5.5, 9.0, 50.0), Vector3(5.0, 18.0, 16.0), _basalt(8.0), true)
	_box(Vector3(0.0, 9.0, 58.0), Vector3(8.0, 18.0, 2.0), _basalt(8.0), true)


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
	# Bare ribs where the tail plating tore away, in one multimesh.
	var ribs := MultiMesh.new()
	ribs.transform_format = MultiMesh.TRANSFORM_3D
	var rib := BoxMesh.new()
	rib.size = Vector3(0.4, 4.0, 0.4)
	ribs.mesh = rib
	ribs.instance_count = 10
	for i in 10:
		ribs.set_instance_transform(i, Transform3D(Basis(), Vector3(-3.6 if i < 5 else 3.6, 4.0, 14.0 + (i % 5) * 1.6)))
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = ribs
	rmi.material_override = _mat(Color("6c6a66"), 0.5)
	hull.add_child(rmi)
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


## Voss's cache at the back of the high shelf: an oxide box with an amber tell-tale, where she kept
## spare grow-lamp cells out of the scuttlers' reach. The spitter on the middle shelf covers the way
## up. It opens only once Teo has asked for a cell (Greenhouses: the dark house).
func _cell_cache() -> void:
	_box(CELL_CACHE + Vector3(0.0, 0.4, 0.0), Vector3(1.3, 0.8, 0.9), _mat(OXIDE, 0.55), true)
	_box(CELL_CACHE + Vector3(0.0, 0.85, 0.0), Vector3(1.4, 0.1, 1.0), _mat(Color("6c6a66"), 0.5), false)
	var tell := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.25, 0.12, 0.25)
	tell.mesh = tm
	tell.material_override = _glow(Color("e8a44e"), 3.0)
	tell.position = CELL_CACHE + Vector3(0.45, 0.96, 0.0)
	add_child(tell)
	_cache_tell = tell
	_cache_tell.visible = not Game.flags.get("lamp_cell_found", false)
	cache_pos = to_global(CELL_CACHE + Vector3(0.0, 0.0, 1.3))


func take_cell() -> void:
	if not Greenhouses.cell_wanted():
		return
	Game.set_flag("lamp_cell_found")
	if _cache_tell:
		_cache_tell.visible = false
	Sfx.play("scrap_pickup", cache_pos, 0.0)
	var main := greenhouses._main() if greenhouses else null
	if main:
		main.voice.say(Story.CELL_FOUND)


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

