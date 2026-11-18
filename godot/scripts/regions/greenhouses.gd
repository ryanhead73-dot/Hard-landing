class_name Greenhouses
extends Node3D
## Act 2 hub greybox (X4 prework): Voss's old greenhouses in the Shatterlands, where Lt. Reyes's
## eleven survivors hold out "under the big fungus". Three long arched glasshouses, two of them
## still lit, inside a palisade of scrap hull plate with one gate. Human things here are amber
## and ivory (the pack's rule: amber means people); the fungus outside is violet and teal.
## Juno hails the gate; Reyes won't open it until she's cleared the scuttler nest under the
## Marigold's tail (it took two of hers). Then the gate slides open, Reyes waits just inside, and
## the middle glasshouse can be walked into: grow beds under amber lamps.
##
## Built in the threshold pocket's local space; `Greenhouses.AT` is the compound's centre.
## State in Game.flags: reached_greenhouses (within REACH of the gate), met_reyes (hailed),
## nest_cleared (set by the pocket), greenhouse_open (the gate), reyes_talked.
## Teo's favour, the dark house: lamp_cell_asked (Teo's ask), lamp_cell_found (taken from Voss's
## cache, in the pocket), lamp_cell_fitted (the east house lights again).

const AT := Vector3(15.0, 0.0, -52.0)
## Palisade half-extents (x, z) round AT; the gate is in the south wall (+Z, toward the canyon).
const HALF := Vector2(15.0, 10.0)
const GATE_WIDTH := 4.0
const REACH := 22.0
const HAIL_RANGE := 2.6
const IVORY := Color("d9d2c2")
const OXIDE := Color("bf6835")
const AMBER := Color("e8a44e")
const SLATE := Color("3c4448")
const GLASS := Color(0.55, 0.85, 0.7, 0.35)
const LEAF := Color("5f8f4e")
## Where Jake's texture sets live (PbrSet folder).
const TEXTURES := "shatterlands"
## The glasshouses: length and radius, and how high they stand on their footings.
const HOUSE_LENGTH := 13.0
const HOUSE_RADIUS := 3.4
const FOOTING := 1.0
## Which one Juno can walk into (the middle one, straight up from the gate), and the east one,
## dark until Juno brings Teo a lamp cell.
const WALK_IN := 1
const EAST := 2
const TALK_RANGE := 2.4
const GATE_SLIDE := 3.6
## Crew colours, [suit, trim]: Ferro-9's rescue crew, and Ilse's survey expedition.
const FERRO := [Color("6f7d84"), Color("c98a3c")]
const EXPEDITION := [Color("8a7a62"), Color("5f8f4e")]
## The camp's heater, and the lookout platform's top, inside the west wall (local).
const HEATER := Vector3(-3.6, 0.0, 6.8)
const LOOKOUT := Vector3(-13.6, 1.6, 0.0)
## Some of the eleven: [name, local position, yaw, crew, loop]. Their words are Story.SURVIVORS.
const SURVIVORS := [
	["Okafor", HEATER + Vector3(1.0, 0.0, -0.6), -1.03, "ferro", "idle"],
	["Brandt", HEATER + Vector3(-1.1, 0.0, 0.4), 1.9, "ferro", "crouch"],
	["Haddad", LOOKOUT, -PI * 0.5, "expedition", "idle"],
	["Teo", Vector3(-1.0, FOOTING, -3.5), -PI * 0.5, "expedition", "crouch"],
]
## Where Reyes stands, inside the gate under its lamp (local).
const REYES_AT := Vector3(2.6, 0.0, 7.6)

var gate_pos := Vector3.ZERO
var intercom_pos := Vector3.ZERO
var reyes: Node3D
var survivors: Array[Node3D] = []
## The walk-in glasshouse's door and the middle of its floor (world space).
var house_door := Vector3.ZERO
var house_inside := Vector3.ZERO
var _gate_body: AnimatableBody3D
var _east_glass: StandardMaterial3D
var _mats := {}


func _ready() -> void:
	position = AT
	_palisade()
	for i in 3:
		var glass := _glasshouse(Vector3(-8.0 + i * 8.0, 0.0, -2.0), i != EAST, i == WALK_IN)
		if i == EAST:
			_east_glass = glass
	_gate()
	_reyes()
	_camp()
	_sync_gate(false)
	_sync_east(false)


func reached() -> bool:
	return Game.flags.get("reached_greenhouses", false) == true


func hailed() -> bool:
	return Game.flags.get("met_reyes", false) == true


func is_open() -> bool:
	return Game.flags.get("greenhouse_open", false) == true


func nest_cleared() -> bool:
	return Game.flags.get("nest_cleared", false) == true


func east_lit() -> bool:
	return Game.flags.get("lamp_cell_fitted", false) == true


## Teo has asked for a cell and Juno hasn't got one yet (the pocket offers the cache then).
static func cell_wanted() -> bool:
	return Game.flags.get("lamp_cell_asked", false) == true and Game.flags.get("lamp_cell_found", false) != true


func _process(_delta: float) -> void:
	var main := _main()
	if main == null or main.player.dead:
		return
	if not reached() and main.player.global_position.distance_to(gate_pos) < REACH:
		Game.set_flag("reached_greenhouses")
		main.voice.say(Story.GREENHOUSE_ARRIVE)
	# Back at the gate with the nest gone: Reyes opens up without being asked twice.
	if hailed() and nest_cleared() and not is_open() and main.player.global_position.distance_to(gate_pos) < 8.0:
		open_gate()
	if reyes and is_open():
		var to: Vector3 = main.player.global_position - reyes.global_position
		if to.length() < 9.0:
			reyes.rotation.y = lerp_angle(reyes.rotation.y, atan2(to.x, to.z), 0.08)


func interaction(pos: Vector3) -> Dictionary:
	if reyes and reyes.visible and pos.distance_to(reyes.global_position) < TALK_RANGE:
		return {"label": "[E] Talk to Reyes", "action": talk}
	for p in survivors:
		if pos.distance_to(p.global_position) < TALK_RANGE:
			if p.name == "Teo" and Game.flags.get("lamp_cell_found", false) and not east_lit():
				return {"label": "[E] Give Teo the lamp cell", "action": fit_cell}
			return {"label": "[E] Talk to %s" % p.name, "action": func(): _bark(p.name)}
	if pos.distance_to(intercom_pos) > HAIL_RANGE or is_open():
		return {}
	if hailed():
		return {"label": "The gate stays shut. Reyes: \"Clear that nest first, Vale.\""}
	return {"label": "[E] Hail the greenhouses", "action": hail}


func hail() -> void:
	if hailed():
		return
	Game.set_flag("met_reyes")
	if not reached():
		Game.set_flag("reached_greenhouses")
	Sfx.play("signal_ping", intercom_pos, -4.0)
	var main := _main()
	if main:
		main.voice.say(Story.GREENHOUSE_HAIL)
		main.voice.say(Story.GREENHOUSE_HAIL_CLEARED if nest_cleared() else Story.GREENHOUSE_ASK)
	if nest_cleared():
		open_gate()


func open_gate() -> void:
	if is_open():
		return
	Game.set_flag("greenhouse_open")
	var main := _main()
	if main:
		main.voice.say(Story.GREENHOUSE_OPEN)
	Sfx.play("airlock_open", gate_pos, 0.0)
	_sync_gate(true)


func talk() -> void:
	var main := _main()
	if main == null:
		return
	if Game.flags.get("reyes_talked", false):
		main.voice.say(Story.REYES_AGAIN)
		return
	Game.set_flag("reyes_talked")
	main.voice.say(Story.REYES_TALK)


func _bark(who: String) -> void:
	var main := _main()
	if main == null:
		return
	# Teo's favour: until the east house is lit, that's all Teo talks about.
	if who == "Teo" and not east_lit():
		if not Game.flags.get("lamp_cell_asked", false):
			Game.set_flag("lamp_cell_asked")
			main.voice.say(Story.TEO_ASK)
		else:
			main.voice.say(Story.TEO_WAITING)
		return
	main.voice.say(Story.SURVIVORS.get(who, []))


## Juno hands Teo the cell from Voss's cache; the east house lights up and Teo pays in charges.
func fit_cell() -> void:
	if east_lit():
		return
	Game.set_flag("lamp_cell_fitted")
	Game.add_charges(2)
	var main := _main()
	if main:
		main.voice.say(Story.TEO_THANKS)
	Sfx.play("power_up", to_global(Vector3(8.0, 1.5, -2.0)), -2.0)
	_sync_east(true)


## The east glasshouse glows amber like the others once its cell is in; dark glass until then.
func _sync_east(animate: bool) -> void:
	if _east_glass == null:
		return
	var lit := east_lit()
	_east_glass.emission_enabled = lit
	_east_glass.emission = AMBER
	if lit and animate and is_inside_tree():
		_east_glass.emission_energy_multiplier = 0.0
		create_tween().tween_property(_east_glass, "emission_energy_multiplier", 1.1, 2.5).set_trans(Tween.TRANS_SINE)
	else:
		_east_glass.emission_energy_multiplier = 1.1


## Gate and Reyes follow the flag: shut with nobody inside, or slid aside with Reyes waiting.
func _sync_gate(animate: bool) -> void:
	var open := is_open()
	if reyes:
		reyes.visible = open
	if _gate_body == null:
		return
	var to := Vector3(-GATE_SLIDE if open else 0.0, 1.6, HALF.y - 0.4 if open else HALF.y)
	if animate and is_inside_tree():
		create_tween().tween_property(_gate_body, "position", to, 1.6).set_trans(Tween.TRANS_SINE)
	else:
		_gate_body.position = to


func _main() -> Node:
	var n := get_parent()
	while n and n.get("voice") == null:
		n = n.get_parent()
	return n


## Scrap hull plates on posts, leaning a little, with collision as four long walls (gap at the gate).
func _palisade() -> void:
	var plates: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var walls := [
		[Vector3(0.0, 0.0, -HALF.y), Vector3(1.0, 0.0, 0.0), HALF.x * 2.0],
		[Vector3(-HALF.x, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), HALF.y * 2.0],
		[Vector3(HALF.x, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), HALF.y * 2.0],
	]
	# The south wall in two halves either side of the gate.
	var half_south := HALF.x - GATE_WIDTH * 0.5
	walls.append([Vector3(-(GATE_WIDTH * 0.5 + half_south * 0.5), 0.0, HALF.y), Vector3(1.0, 0.0, 0.0), half_south])
	walls.append([Vector3(GATE_WIDTH * 0.5 + half_south * 0.5, 0.0, HALF.y), Vector3(1.0, 0.0, 0.0), half_south])
	for w in walls:
		var c: Vector3 = w[0]
		var along: Vector3 = w[1]
		var length: float = w[2]
		_solid(c + Vector3(0.0, 1.6, 0.0), along * length + Vector3(0.0, 3.2, 0.0) + along.cross(Vector3.UP).abs() * 0.4, null)
		var t := -length * 0.5 + 0.9
		while t < length * 0.5:
			var h := rng.randf_range(2.6, 3.6)
			var b := Basis.looking_at(along.cross(Vector3.UP), Vector3.UP).rotated(along, rng.randf_range(-0.08, 0.08))
			plates.append(Transform3D(b.scaled(Vector3(1.9, h, 0.12)), c + along * t + Vector3(0.0, h * 0.5, 0.0)))
			t += 1.7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = plates.size()
	for i in plates.size():
		mm.set_instance_transform(i, plates[i])
		mm.set_instance_color(i, [IVORY, IVORY.darkened(0.25), OXIDE, SLATE][i % 4])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	if PbrSet.exists(TEXTURES, "greenhouse_palisade_scrap_hull"):
		# Jake's patched scrap plate, each plate tinted a little differently so the repeat breaks up.
		m = PbrSet.material(TEXTURES, "greenhouse_palisade_scrap_hull", 4.0).duplicate()
		for i in plates.size():
			mm.set_instance_color(i, [Color.WHITE, Color(0.82, 0.82, 0.8), Color(1.0, 0.88, 0.8), Color(0.78, 0.84, 0.88)][i % 4])
	else:
		m.roughness = 0.8
	m.vertex_color_use_as_albedo = true
	mmi.material_override = m
	add_child(mmi)


## A long arched house: a half-cylinder of greenish glass over ivory ribs, oxide end frames.
## Lit ones glow amber from inside (grow lamps). The walk-in one is open at the south end, walled
## inside rather than boxed over, with steps up to its floor, grow beds and a string of lamps.
func _glasshouse(at: Vector3, lit: bool, walk_in := false) -> StandardMaterial3D:
	var length := HOUSE_LENGTH
	var radius := HOUSE_RADIUS
	# Raised on a low footing so the lit arches show over the palisade.
	at.y += 1.3
	_solid(at + Vector3(0.0, -1.3 + FOOTING * 0.5, 0.0), Vector3(radius * 2.0 + 0.4, FOOTING, length + 0.4), _mat(SLATE, 0.8))
	var shell := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 16
	cyl.rings = 1
	# Rotated to lie along Z, the cylinder's top cap is the south end: the walk-in one's doorway.
	cyl.cap_top = not walk_in
	shell.mesh = cyl
	var glass := _glass(walk_in)
	if walk_in:
		glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	if lit:
		glass.emission_enabled = true
		glass.emission = AMBER
		glass.emission_energy_multiplier = 0.7 if walk_in else 1.1
	shell.material_override = glass
	shell.rotation.x = PI * 0.5
	shell.position = at
	add_child(shell)
	# Ribs: thin hoops round the arch, half of each buried.
	var ribs := MultiMesh.new()
	ribs.transform_format = MultiMesh.TRANSFORM_3D
	var rib := TorusMesh.new()
	rib.inner_radius = radius - 0.02
	rib.outer_radius = radius + 0.14
	rib.rings = 24
	rib.ring_segments = 4
	ribs.mesh = rib
	ribs.instance_count = 7
	for i in 7:
		var z := -length * 0.5 + 0.2 + i * (length - 0.4) / 6.0
		ribs.set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(0.0, 0.0, z)))
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = ribs
	rmi.material_override = _tex("glasshouse_frame_metal", 2.0, _mat(IVORY, 0.6))
	add_child(rmi)
	var floor_y := at.y - 1.3 + FOOTING
	# A plank ramp up the footing at the south end.
	_ramp(Vector3(at.x, 0.0, at.z + length * 0.5 + 0.2), 3.0, FOOTING, 1.8)
	if not walk_in:
		# One box collider over the arch, so Juno walks round, not through.
		_solid(at + Vector3(0.0, radius * 0.5, 0.0), Vector3(radius * 2.0, radius, length), null)
		_solid(at + Vector3(0.0, 1.1, length * 0.5 + 0.05), Vector3(1.6, 2.2, 0.12), _mat(OXIDE, 0.6))
		return glass
	# The walk-in house: side walls and the back, an open door frame, beds, lamps, a cot.
	var wall_x := radius - 0.35
	for side in [-1.0, 1.0]:
		_solid(Vector3(at.x + side * wall_x, floor_y + 1.4, at.z), Vector3(0.2, 2.8, length), null)
		_solid(Vector3(at.x + side * 1.05, floor_y + 1.15, at.z + length * 0.5 + 0.05), Vector3(0.2, 2.3, 0.2), _mat(OXIDE, 0.6))
		# A grow bed along each side, planted.
		_solid(Vector3(at.x + side * 2.1, floor_y + 0.3, at.z - 0.5), Vector3(1.3, 0.6, length - 3.0), _tex("greenhouse_grow_bed_soil", 1.5, _mat(Color("5a4636"), 0.95)))
		_plants(Vector3(at.x + side * 2.1, floor_y + 0.6, at.z - 0.5), length - 3.4)
	_solid(Vector3(at.x, floor_y + 2.35, at.z + length * 0.5 + 0.05), Vector3(2.3, 0.2, 0.2), _mat(OXIDE, 0.6))
	_solid(Vector3(at.x, floor_y + 1.4, at.z - length * 0.5 + 0.1), Vector3(radius * 2.0, 2.8, 0.2), null)
	# A cot at the back: somebody sleeps with the plants.
	_solid(Vector3(at.x, floor_y + 0.25, at.z - length * 0.5 + 1.6), Vector3(1.0, 0.5, 2.0), _mat(Color("6c6a66"), 0.9))
	# Grow lamps strung along the ridge, and the light they give.
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = AMBER.darkened(0.3)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = AMBER
	lamp_mat.emission_energy_multiplier = 3.5
	for k in 4:
		var lamp := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.9, 0.08, 0.3)
		lamp.mesh = lm
		lamp.material_override = lamp_mat
		lamp.position = Vector3(at.x, floor_y + 2.9, at.z - length * 0.5 + 2.0 + k * 3.0)
		add_child(lamp)
	var light := OmniLight3D.new()
	light.light_color = AMBER
	light.light_energy = 1.6
	light.omni_range = 8.0
	light.shadow_enabled = false
	light.position = Vector3(at.x, floor_y + 2.6, at.z)
	add_child(light)
	house_door = to_global(Vector3(at.x, 0.0, at.z + length * 0.5 + 2.0))
	house_inside = to_global(Vector3(at.x, floor_y, at.z))
	return glass


## Rows of leafy crowns on a bed: one MultiMesh of squashed spheres, a little irregular.
func _plants(centre: Vector3, length: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(centre.x * 10.0) + 7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var leaf := SphereMesh.new()
	leaf.radius = 0.28
	leaf.height = 0.4
	leaf.radial_segments = 8
	leaf.rings = 4
	mm.mesh = leaf
	var n := int(length / 0.6)
	mm.instance_count = n * 2
	for i in n * 2:
		var z := -length * 0.5 + (i / 2) * 0.6 + rng.randf_range(-0.1, 0.1)
		var x := (-0.3 if i % 2 == 0 else 0.3) + rng.randf_range(-0.08, 0.08)
		var sc := rng.randf_range(0.7, 1.25)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.4), sc)), centre + Vector3(x, 0.15 * sc, z)))
		mm.set_instance_color(i, LEAF.lerp(Color("8fae5a"), rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.75
	mmi.material_override = m
	add_child(mmi)


## Gate: two posts, a slab door, an amber work lamp and the intercom box beside it.
func _gate() -> void:
	var z := HALF.y
	for x in [-GATE_WIDTH * 0.5 - 0.3, GATE_WIDTH * 0.5 + 0.3]:
		_solid(Vector3(x, 2.0, z), Vector3(0.6, 4.0, 0.6), _mat(SLATE, 0.6))
	_gate_body = AnimatableBody3D.new()
	_gate_body.collision_layer = Game.LAYER_WORLD
	_gate_body.sync_to_physics = false
	var shape := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(GATE_WIDTH, 3.2, 0.3)
	shape.shape = gb
	_gate_body.add_child(shape)
	var slab := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = gb.size
	slab.mesh = sm
	slab.material_override = _mat(OXIDE, 0.55)
	_gate_body.add_child(slab)
	_gate_body.position = Vector3(0.0, 1.6, z)
	add_child(_gate_body)
	var lamp := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.6, 0.25, 0.3)
	lamp.mesh = lm
	var glow := StandardMaterial3D.new()
	glow.albedo_color = AMBER.darkened(0.4)
	glow.emission_enabled = true
	glow.emission = AMBER
	glow.emission_energy_multiplier = 3.0
	lamp.material_override = glow
	lamp.position = Vector3(GATE_WIDTH * 0.5 + 0.3, 4.15, z + 0.2)
	add_child(lamp)
	var light := OmniLight3D.new()
	light.light_color = AMBER
	light.light_energy = 2.2
	light.omni_range = 11.0
	light.shadow_enabled = false
	light.position = lamp.position + Vector3(0.0, -0.3, 0.6)
	add_child(light)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 0.5, 0.2)
	box.mesh = bm
	box.material_override = glow
	box.position = Vector3(-GATE_WIDTH * 0.5 - 0.3, 1.4, z + 0.4)
	add_child(box)
	gate_pos = to_global(Vector3(0.0, 0.0, z + 1.5))
	intercom_pos = to_global(Vector3(-GATE_WIDTH * 0.5 - 0.3, 0.0, z + 1.4))


## Lt. Sana Reyes: Juno's own suit model in Ferro-9's colours (slate with an amber stripe), standing
## easy inside the gate. Hidden until the gate opens.
func _reyes() -> void:
	reyes = _person("Reyes", REYES_AT, 0.0, FERRO, "idle")


## Some of the eleven, about the compound: around the heater by the gate, on the west wall's
## lookout, and at the beds in the walk-in house. Each has a word for Juno.
func _camp() -> void:
	# The heater: a drum with a glowing grate, and the warm light that fills the yard.
	var drum := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.42
	dm.bottom_radius = 0.45
	dm.height = 0.9
	dm.radial_segments = 12
	drum.mesh = dm
	drum.material_override = _mat(OXIDE.darkened(0.3), 0.7)
	drum.position = HEATER + Vector3(0.0, 0.45, 0.0)
	add_child(drum)
	var grate := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.38
	gm.bottom_radius = 0.38
	gm.height = 0.04
	gm.radial_segments = 12
	grate.mesh = gm
	var fire := StandardMaterial3D.new()
	fire.albedo_color = AMBER.darkened(0.2)
	fire.emission_enabled = true
	fire.emission = Color("ff9a3c")
	fire.emission_energy_multiplier = 4.0
	grate.material_override = fire
	grate.position = HEATER + Vector3(0.0, 0.91, 0.0)
	add_child(grate)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb060")
	light.light_energy = 1.5
	light.omni_range = 8.5
	light.shadow_enabled = false
	light.position = HEATER + Vector3(0.0, 1.4, 0.0)
	add_child(light)
	# Salvage stacked by the heater, and the lookout's platform on the west wall.
	_solid(HEATER + Vector3(-2.2, 0.45, 1.3), Vector3(1.1, 0.9, 0.9), _mat(SLATE, 0.7))
	_solid(HEATER + Vector3(-2.3, 1.15, 1.3), Vector3(0.8, 0.5, 0.7), _mat(IVORY.darkened(0.2), 0.7))
	_solid(LOOKOUT + Vector3(0.0, -0.8, 0.0), Vector3(1.6, 1.6, 1.6), _mat(SLATE, 0.8))
	for s in SURVIVORS:
		var at: Vector3 = s[1]
		var p := _person(s[0], at, s[2], FERRO if s[3] == "ferro" else EXPEDITION, s[4])
		survivors.append(p)


## A person on Juno's rig, recoloured: `palette` is [suit, trim]; `clip` is the loop they hold.
func _person(who: String, at: Vector3, yaw: float, palette: Array, clip: String) -> Node3D:
	var n := Node3D.new()
	n.name = who
	n.position = at
	n.rotation.y = yaw
	add_child(n)
	var rig := Rig.spawn("juno_rigged", n)
	for mi in Rig.meshes(rig):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mi.get_active_material(i) as StandardMaterial3D
			if src == null:
				continue
			var key := "%s/%d/%s" % [mesh.resource_path, i, palette[0].to_html()]
			if not _mats.has(key):
				var m := src.duplicate() as StandardMaterial3D
				# Ivory suit panels take the crew's colour; oxide trim takes the trim; dark parts stay.
				var c := m.albedo_color
				if c.get_luminance() > 0.55:
					m.albedo_color = palette[0]
				elif c.r > c.b * 1.6 and c.r > 0.35:
					m.albedo_color = palette[1]
				_mats[key] = m
			mi.set_surface_override_material(i, _mats[key])
	var clips := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if clips and clips.has_animation(clip):
		clips.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		clips.play(clip)
		# Not all in step.
		clips.seek(randf() * clips.current_animation_length, true)
	return n


## A ramp rising north to `rise` over `run` metres, its top edge at `edge` (local, ground level).
func _ramp(edge: Vector3, run: float, rise: float, width: float) -> void:
	var angle := atan2(rise, run)
	var length := sqrt(run * run + rise * rise)
	var normal := Vector3(0.0, cos(angle), sin(angle))
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(width, 0.3, length)
	shape.shape = b
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = b.size
	mi.mesh = mesh
	mi.material_override = _mat(Color("6c6a66"), 0.85)
	body.add_child(mi)
	body.rotation.x = angle
	body.position = edge + Vector3(0.0, rise * 0.5, run * 0.5) - normal * 0.15
	add_child(body)


## A collision box, dressed with a mesh when `mat` is given.
func _solid(pos: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	body.add_child(shape)
	if mat:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
		mi.material_override = mat
		body.add_child(mi)
	body.position = pos
	add_child(body)


## Jake's greenhouse PBR sets (assets/textures/shatterlands/), or the flat colour if a set is missing.
func _tex(set_name: String, metres: float, fallback: Material) -> Material:
	return PbrSet.material(TEXTURES, set_name, metres) if PbrSet.exists(TEXTURES, set_name) else fallback


## Each glasshouse gets its own glass (the east one's glow changes): Jake's clean glass on the
## walk-in house, his grimy glass on the other two.
func _glass(clean: bool) -> StandardMaterial3D:
	var set_name := "greenhouse_glass_clean" if clean else "greenhouse_glass_dirty"
	var glass: StandardMaterial3D
	if PbrSet.exists(TEXTURES, set_name):
		# Its normal and roughness only: the grime in the albedo's alpha broke the houses' amber glow
		# into blotches, so the tint stays flat and the grime shows as dull, streaky patches instead.
		glass = PbrSet.material(TEXTURES, set_name, 3.0).duplicate()
		glass.albedo_texture = null
		glass.albedo_color = GLASS
	else:
		glass = StandardMaterial3D.new()
		glass.albedo_color = GLASS
		glass.roughness = 0.15
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return glass


func _mat(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), roughness]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_mats[key] = m
	return _mats[key]
