class_name Gillwood
extends ShatterScene
## The Gillwood (X5.1 greybox): the second area of the Shatterlands, north through the rim from
## Voss's greenhouses. A low forest of gill-trees whose undersides glow teal, and in a clearing
## the Ferro-9, the rescue ship Brandt put down here, broken in two. Her canopy and landing-gear
## strut are what Act 2 salvages for Kestrel (quest `ferro_9`; the repairs themselves are wired
## in the campaign later).
##
## Local space: Juno comes in from the greenhouses through the south mouth (+Z) and looks north.
## State in Game.flags: reached_gillwood, found_ferro9, ferro_canopy, ferro_gear.

const SEED := 71
## The forest's own gill-tree palette: shorter, bluer caps than the pocket's giants.
const TREE_CAP := Color("3b3f7a")
const FERRO_HULL := Color("6f7d84")
const FERRO_TRIM := Color("c98a3c")
const AMBER := Color("e8a44e")
## Ferro-9's fore section (the nose, with the canopy) and its yaw; the aft lies off to the east.
const WRECK := Vector3(4.0, 0.0, -28.0)
const WRECK_YAW := 0.45
## Where the gear strut hangs under the aft section, and where the scuttlers den below it.
const AFT_OFFSET := Vector3(9.0, 0.0, 9.0)
## The outcrop the spitter holds, over the clearing.
const OUTCROP := Vector3(-16.0, 0.0, -42.0)
## Giant fungi: [base, stem height, cap radius].
const GIANTS := [[Vector3(-30.0, 0.0, 20.0), 22.0, 12.0], [Vector3(34.0, 0.0, -56.0), 26.0, 13.0]]
## Juno counts as having found the wreck within this distance of the fore section.
const FIND_RANGE := 18.0
const USE_RANGE := 2.4

## Ferro-9's two halves, and the parts that come off (world-space use points are below).
var fore: Node3D
var aft: Node3D
var canopy: Node3D
var strut: Node3D
var cockpit_pos := Vector3.INF
var canopy_pos := Vector3.INF
var strut_pos := Vector3.INF
var _beacon: OmniLight3D
var _t := 0.0


func _init() -> void:
	entry = Vector3(0.0, 0.3, 66.0)
	entry_yaw = 0.0
	exit_point = Vector3(0.0, 0.0, 72.0)
	exit_label = "Go back south to the greenhouses"
	goal = WRECK + Vector3(0.0, 2.0, 0.0)
	# A drifter hung over the path in, to remind Juno; pairs moored in the trees; the den of
	# scuttlers under the aft section, guarding the gear; the spitter on the outcrop.
	var moored := {"wander_radius": 0.8}
	var den := WRECK + AFT_OFFSET + Vector3(2.0, 0.5, 4.0)
	residents = [
		["drifter", Vector3(-3.0, 3.0, 44.0)],
		["drifter", Vector3(-18.0, 3.2, 8.0), moored], ["drifter", Vector3(-15.8, 3.0, 6.6), moored],
		["drifter", Vector3(22.0, 3.4, -4.0), moored], ["drifter", Vector3(24.0, 3.0, -6.0), moored],
		["scuttler", den + Vector3(-1.4, 0.0, -0.8), {"wander_radius": 2.0}], ["scuttler", den + Vector3(1.2, 0.0, -1.0), {"wander_radius": 2.0}],
		["scuttler", den + Vector3(0.0, 0.0, 1.5), {"wander_radius": 2.0}],
		["spitter", OUTCROP + Vector3(0.0, 4.5, 0.0)],
	]
	look = {
		"fog_light_color": Color("2a3f5c"), "fog_density": 0.022,
		"ambient_light_color": Color("6f8ac0"), "ambient_light_energy": 0.8,
		"background_energy_multiplier": 0.4,
		"sun_energy": 0.25, "sun_color": Color("a4c8ff"), "sun_rotation": Vector3(-30.0, 150.0, 0.0),
	}


func build() -> void:
	_rng.seed = SEED
	_ground()
	_mouth()
	for g in GIANTS:
		_fungus(g[0], g[1], g[2])
	_build_spots()
	_trees()
	_outcrop()
	_ferro()
	_undergrowth()
	_sync_parts()


func _ready() -> void:
	super()
	if not Game.flags.get("reached_gillwood", false):
		Game.set_flag("reached_gillwood")
		_say(Story.GILLWOOD_ARRIVE)


func _process(delta: float) -> void:
	_t += delta
	# Ferro-9's emergency beacon still blinks, slow, on what's left of her battery.
	if _beacon:
		_beacon.light_energy = 2.2 if fmod(_t, 2.4) < 0.3 else 0.15
	var main := get_parent()
	if main == null or main.get("player") == null or main.player.dead:
		return
	if not Game.flags.get("found_ferro9", false) and main.player.global_position.distance_to(to_global(WRECK)) < FIND_RANGE:
		Game.set_flag("found_ferro9")
		_say(Story.FERRO_FOUND)


func interaction(pos: Vector3) -> Dictionary:
	if pos.distance_to(cockpit_pos) < USE_RANGE and not Game.has_log("ferro_1"):
		return {"label": "[E] Pull Ferro-9's flight recorder", "action": read_recorder}
	if pos.distance_to(canopy_pos) < USE_RANGE and not salvaged("ferro_canopy"):
		return {"label": "[E] Unbolt Ferro-9's canopy", "action": free_canopy}
	if pos.distance_to(strut_pos) < USE_RANGE and not salvaged("ferro_gear"):
		return {"label": "[E] Cut the landing-gear strut free", "action": free_strut}
	return {}


func salvaged(flag: String) -> bool:
	return Game.flags.get(flag, false) == true


func read_recorder() -> void:
	Game.find_log("ferro_1")
	Sfx.play("log_chime", cockpit_pos, -2.0)


func free_canopy() -> void:
	if salvaged("ferro_canopy"):
		return
	Game.set_flag("ferro_canopy")
	Sfx.play("repair_clunk", canopy_pos, 0.0)
	_say(Story.FERRO_CANOPY)
	_sync_parts(true)


func free_strut() -> void:
	if salvaged("ferro_gear"):
		return
	Game.set_flag("ferro_gear")
	Sfx.play("hull_groan", strut_pos, -2.0)
	_say(Story.FERRO_GEAR)
	_sync_parts(true)


## The canopy sits on the nose until it's unbolted, then on skids beside it; the strut hangs
## under the aft section until it's cut, then lies on the ground. Once both are off, the
## waypoint points home.
func _sync_parts(animate := false) -> void:
	if canopy:
		var to := Vector3(0.0, 3.35, -3.4) if not salvaged("ferro_canopy") else Vector3(-4.2, 0.9, -3.0)
		if animate and is_inside_tree():
			create_tween().tween_property(canopy, "position", to, 1.2).set_trans(Tween.TRANS_SINE)
		else:
			canopy.position = to
	if strut:
		var down := salvaged("ferro_gear")
		var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5 if down else 0.25), Vector3(1.6, 0.35, 1.0) if down else Vector3(1.6, 0.4, 1.0))
		if animate and is_inside_tree():
			create_tween().tween_property(strut, "transform", xf, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		else:
			strut.transform = xf
	if salvaged("ferro_canopy") and salvaged("ferro_gear"):
		goal = exit_point + Vector3(0.0, 1.0, 0.0)


func _say(lines: Array) -> void:
	var main := get_parent()
	if main and main.get("voice"):
		main.voice.say(lines)


func _ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(120.0, 170.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	# The pocket's grit, a little bluer under the trees.
	mi.material_override = _tex("shatterlands_ground", 2.5, true, Color(0.85, 0.92, 1.0), _mat(GROUND, 0.85))
	add_child(mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 170.0)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)
	# The south wall has the mouth in it, back toward the greenhouses.
	_rim([[Vector3(0.0, 10.0, -89.0), Vector3(128.0, 20.0, 8.0)], [Vector3(-64.0, 10.0, 0.0), Vector3(8.0, 20.0, 178.0)], [Vector3(64.0, 10.0, 0.0), Vector3(8.0, 20.0, 178.0)], [Vector3(-34.0, 10.0, 81.0), Vector3(60.0, 20.0, 8.0)], [Vector3(34.0, 10.0, 81.0), Vector3(60.0, 20.0, 8.0)]])


## The way back south: the other end of the split, between two basalt slabs.
func _mouth() -> void:
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 5.5, 9.0, 76.0), Vector3(5.0, 18.0, 12.0), _basalt(8.0), true)
	_box(Vector3(0.0, 9.0, 82.0), Vector3(8.0, 18.0, 2.0), _basalt(8.0), true)


## The forest: gill-trees in three multimeshes (stems, caps, glowing gills), each with a stem
## collider. Kept out of the clearing round the wreck, the path in, and the outcrop.
func _trees() -> void:
	var xforms: Array = []
	var tries := 0
	while xforms.size() < 46 and tries < 2000:
		tries += 1
		var p := Vector3(_rng.randf_range(-56.0, 56.0), 0.0, _rng.randf_range(-82.0, 62.0))
		if Vector2(p.x - WRECK.x - 4.0, p.z - WRECK.z - 4.0).length() < 20.0:
			continue
		if absf(p.x) < 7.0 and p.z > 30.0:
			continue
		if Vector2(p.x - OUTCROP.x, p.z - OUTCROP.z).length() < 9.0:
			continue
		var clear := true
		for g in GIANTS:
			if Vector2(p.x - g[0].x, p.z - g[0].z).length() < 6.0:
				clear = false
		for x in xforms:
			if Vector2(p.x - x[0].x, p.z - x[0].z).length() < 5.0:
				clear = false
		if not clear:
			continue
		xforms.append([p, _rng.randf_range(5.0, 11.0), _rng.randf_range(2.4, 4.6)])
	var stems := MultiMesh.new()
	var caps := MultiMesh.new()
	var gills := MultiMesh.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.6
	stem_mesh.bottom_radius = 1.0
	stem_mesh.height = 1.0
	stem_mesh.radial_segments = 8
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 1.0
	cap_mesh.height = 0.7
	cap_mesh.radial_segments = 14
	cap_mesh.rings = 6
	var gill_mesh := CylinderMesh.new()
	gill_mesh.top_radius = 0.92
	gill_mesh.bottom_radius = 0.55
	gill_mesh.height = 0.12
	gill_mesh.radial_segments = 14
	for pair in [[stems, stem_mesh], [caps, cap_mesh], [gills, gill_mesh]]:
		pair[0].transform_format = MultiMesh.TRANSFORM_3D
		pair[0].mesh = pair[1]
		pair[0].instance_count = xforms.size()
	for i in xforms.size():
		var p: Vector3 = xforms[i][0]
		var h: float = xforms[i][1]
		var r: float = xforms[i][2]
		var lean := Basis(Vector3.UP, _rng.randf() * TAU).rotated(Vector3.RIGHT, _rng.randf_range(-0.06, 0.06))
		stems.set_instance_transform(i, Transform3D(lean.scaled(Vector3(r * 0.16, h, r * 0.16)), p + Vector3(0.0, h * 0.5, 0.0)))
		caps.set_instance_transform(i, Transform3D(lean.scaled(Vector3(r, r, r)), p + Vector3(0.0, h, 0.0)))
		gills.set_instance_transform(i, Transform3D(lean.scaled(Vector3(r, 1.0, r)), p + Vector3(0.0, h - r * 0.18, 0.0)))
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r * 0.15
		cyl.height = h
		shape.shape = cyl
		body.position = p + Vector3(0.0, h * 0.5, 0.0)
		body.add_child(shape)
		add_child(body)
	var mats := [
		_tex("fungus_stem", 2.0, true, Color(0.85, 0.9, 1.0), _mat(STEM, 0.7)),
		_mat(TREE_CAP, 0.6),
		_tex("fungus_cap_underside", 2.5, true, Color(0.8, 0.85, 1.0), _glow(GILLS, 1.4), GILLS, 3.5),
	]
	var i := 0
	for mm in [stems, caps, gills]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mats[i]
		add_child(mmi)
		i += 1


## A basalt outcrop over the clearing, a ramp up its back: the spitter's perch, and Juno's if
## she takes it from it.
func _outcrop() -> void:
	_box(OUTCROP + Vector3(0.0, 2.0, 0.0), Vector3(9.0, 4.0, 8.0), _basalt(6.0), true)
	_ramp(OUTCROP + Vector3(-9.5, 0.0, -2.0), OUTCROP + Vector3(-4.5, 4.0, -2.0), 3.0)


## Ferro-9: a slate rescue ship with amber trim, broken in two. The fore section holds the
## cockpit (the recorder) and the canopy on its nose; the aft lies twisted off to the east with
## the landing-gear strut hanging under it, an emergency beacon still blinking on its fin.
func _ferro() -> void:
	var hull_mat := _tex("hauler_hull", 6.0, false, Color(0.62, 0.7, 0.76), _mat(FERRO_HULL, 0.55))
	var trim := _mat(FERRO_TRIM, 0.5)
	fore = Node3D.new()
	fore.name = "Ferro9Fore"
	fore.position = WRECK
	fore.rotation = Vector3(deg_to_rad(4.0), WRECK_YAW, deg_to_rad(-7.0))
	add_child(fore)
	_box(Vector3(0.0, 1.6, 0.0), Vector3(5.0, 3.2, 9.0), hull_mat, true, fore)
	_box(Vector3(0.0, 1.3, -5.6), Vector3(4.2, 2.4, 2.4), hull_mat, true, fore)
	_box(Vector3(0.0, 1.0, -7.1), Vector3(3.0, 1.6, 1.0), hull_mat, false, fore)
	for z in [-2.0, 2.5]:
		_box(Vector3(0.0, 1.6, z), Vector3(5.1, 0.35, 0.5), trim, false, fore)
	# Torn edge where she broke: ribs standing out of the back.
	for x in [-2.0, -0.7, 0.7, 2.0]:
		_box(Vector3(x, 1.8, 4.9), Vector3(0.25, 2.8, 0.8), _mat(Color("4a4f52"), 0.5), false, fore)
	# The canopy: a glass dome on a frame ring, lit amber from inside.
	canopy = Node3D.new()
	canopy.name = "Canopy"
	fore.add_child(canopy)
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 1.7
	dm.height = 1.7
	dm.is_hemisphere = true
	dm.radial_segments = 16
	dm.rings = 6
	dome.mesh = dm
	var glass := StandardMaterial3D.new()
	if PbrSet.exists("shatterlands", "greenhouse_glass_clean"):
		glass = PbrSet.material("shatterlands", "greenhouse_glass_clean", 3.0).duplicate()
		glass.albedo_texture = null
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.85, 0.9, 0.35)
	glass.emission_enabled = true
	glass.emission = AMBER
	glass.emission_energy_multiplier = 0.25
	dome.material_override = glass
	dome.scale = Vector3(1.0, 1.0, 1.25)
	canopy.add_child(dome)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 1.6
	rm.outer_radius = 1.85
	rm.rings = 18
	rm.ring_segments = 4
	ring.mesh = rm
	ring.material_override = trim
	ring.scale = Vector3(1.0, 1.0, 1.25)
	canopy.add_child(ring)
	var lamp := OmniLight3D.new()
	lamp.light_color = AMBER
	lamp.light_energy = 1.2
	lamp.omni_range = 6.0
	lamp.position = Vector3(0.0, 2.2, -3.0)
	fore.add_child(lamp)
	cockpit_pos = fore.to_global(Vector3(-3.4, 0.0, -3.0))
	canopy_pos = fore.to_global(Vector3(-3.4, 0.0, -5.6))
	# The aft section, twisted away, nacelles still on, the strut hanging under its belly.
	aft = Node3D.new()
	aft.name = "Ferro9Aft"
	aft.position = WRECK + AFT_OFFSET
	aft.rotation = Vector3(deg_to_rad(-6.0), WRECK_YAW + 0.7, deg_to_rad(18.0))
	add_child(aft)
	# Propped up on its starboard side, so there's room under its belly.
	_box(Vector3(0.0, 2.6, 0.0), Vector3(4.6, 3.0, 8.0), hull_mat, true, aft)
	_box(Vector3(0.0, 2.6, 0.0), Vector3(4.7, 0.35, 0.5), trim, false, aft)
	for side in [-1.0, 1.0]:
		var nacelle := MeshInstance3D.new()
		var nm := CylinderMesh.new()
		nm.top_radius = 0.8
		nm.bottom_radius = 0.95
		nm.height = 4.0
		nm.radial_segments = 10
		nacelle.mesh = nm
		nacelle.material_override = _mat(Color("4a4f52"), 0.45)
		nacelle.rotation.x = PI * 0.5
		nacelle.position = Vector3(side * 3.0, 2.8, 2.6)
		aft.add_child(nacelle)
	_box(Vector3(0.0, 5.0, 3.0), Vector3(0.3, 2.2, 2.4), hull_mat, false, aft)
	_beacon = OmniLight3D.new()
	_beacon.light_color = AMBER
	_beacon.omni_range = 10.0
	_beacon.position = Vector3(0.0, 6.4, 3.0)
	aft.add_child(_beacon)
	var tell := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = 0.2
	tm.height = 0.4
	tell.mesh = tm
	tell.material_override = _glow(AMBER, 3.0)
	tell.position = Vector3(0.0, 6.2, 3.0)
	aft.add_child(tell)
	# The strut: a long leg and a wheel, from a pivot under the belly.
	strut = Node3D.new()
	strut.name = "GearStrut"
	aft.add_child(strut)
	var leg := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.18
	lm.bottom_radius = 0.22
	lm.height = 2.2
	lm.radial_segments = 8
	leg.mesh = lm
	leg.material_override = _mat(Color("8a9094"), 0.35)
	leg.position = Vector3(0.0, -1.1, 0.0)
	strut.add_child(leg)
	var wheel := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.55
	wm.bottom_radius = 0.55
	wm.height = 0.35
	wm.radial_segments = 12
	wheel.mesh = wm
	wheel.material_override = _mat(Color("2a2b2d"), 0.9)
	wheel.rotation.z = PI * 0.5
	wheel.position = Vector3(0.0, -2.2, 0.0)
	strut.add_child(wheel)
	strut_pos = aft.to_global(Vector3(-3.6, 0.0, 1.0))
	strut_pos.y = global_position.y


func _undergrowth() -> void:
	var count := 220 if Game.graphics > Game.GRAPHICS_LOW else 100
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
		var p := Vector3(_rng.randf_range(-56.0, 56.0), 0.08, _rng.randf_range(-82.0, 66.0))
		var s := _rng.randf_range(0.5, 2.0)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _glow(Color("4fa3c9"), 0.8)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
