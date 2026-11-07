class_name Greenhouses
extends Node3D
## Act 2 hub greybox (X4 prework): Voss's old greenhouses in the Shatterlands, where Lt. Reyes's
## eleven survivors hold out "under the big fungus". Three long arched glasshouses, two of them
## still lit, inside a palisade of scrap hull plate with one gate. Human things here are amber
## and ivory (the pack's rule: amber means people); the fungus outside is violet and teal.
## For now Juno can reach the gate and hail it; the inside opens with the Act 2 work.
##
## Built in the threshold pocket's local space; `Greenhouses.AT` is the compound's centre.
## State in Game.flags: reached_greenhouses (within REACH of the gate), met_reyes (hailed).

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

var gate_pos := Vector3.ZERO
var intercom_pos := Vector3.ZERO
var _mats := {}


func _ready() -> void:
	position = AT
	_palisade()
	for i in 3:
		_glasshouse(Vector3(-8.0 + i * 8.0, 0.0, -2.0), i < 2)
	_gate()


func reached() -> bool:
	return Game.flags.get("reached_greenhouses", false) == true


func hailed() -> bool:
	return Game.flags.get("met_reyes", false) == true


func _process(_delta: float) -> void:
	var main := _main()
	if main == null or main.player.dead:
		return
	if not reached() and main.player.global_position.distance_to(gate_pos) < REACH:
		Game.set_flag("reached_greenhouses")
		main.voice.say(Story.GREENHOUSE_ARRIVE)


func interaction(pos: Vector3) -> Dictionary:
	if pos.distance_to(intercom_pos) > HAIL_RANGE:
		return {}
	if hailed():
		return {"label": "The gate stays shut. Reyes: \"Not until we're sure of you. Soon.\""}
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
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	mmi.material_override = m
	add_child(mmi)


## A long arched house: a half-cylinder of greenish glass over ivory ribs, oxide end frames.
## Lit ones glow amber from inside (grow lamps).
func _glasshouse(at: Vector3, lit: bool) -> void:
	var length := 13.0
	var radius := 3.4
	# Raised on a low footing so the lit arches show over the palisade.
	at.y += 1.3
	_solid(at + Vector3(0.0, -1.3 + 0.5, 0.0), Vector3(radius * 2.0 + 0.4, 1.0, length + 0.4), _mat(SLATE, 0.8))
	var shell := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 16
	cyl.rings = 1
	shell.mesh = cyl
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = GLASS
	glass.roughness = 0.15
	if lit:
		glass.emission_enabled = true
		glass.emission = AMBER
		glass.emission_energy_multiplier = 1.1
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
	rmi.material_override = _mat(IVORY, 0.6)
	add_child(rmi)
	# One box collider over the arch, so Juno walks round, not through.
	_solid(at + Vector3(0.0, radius * 0.5, 0.0), Vector3(radius * 2.0, radius, length), null)
	# A door frame on the south end, with steps down from the footing.
	_solid(at + Vector3(0.0, 1.1, length * 0.5 + 0.05), Vector3(1.6, 2.2, 0.12), _mat(OXIDE, 0.6))
	_solid(at + Vector3(0.0, -0.95, length * 0.5 + 0.7), Vector3(1.8, 0.7, 1.0), _mat(SLATE, 0.8))


## Gate: two posts, a slab door, an amber work lamp and the intercom box beside it.
func _gate() -> void:
	var z := HALF.y
	for x in [-GATE_WIDTH * 0.5 - 0.3, GATE_WIDTH * 0.5 + 0.3]:
		_solid(Vector3(x, 2.0, z), Vector3(0.6, 4.0, 0.6), _mat(SLATE, 0.6))
	_solid(Vector3(0.0, 1.6, z), Vector3(GATE_WIDTH, 3.2, 0.3), _mat(OXIDE, 0.55))
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


func _mat(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), roughness]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_mats[key] = m
	return _mats[key]
