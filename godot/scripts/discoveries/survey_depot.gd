class_name SurveyDepot
extends Node3D
## Kettle discovery (X2.5): an abandoned survey depot on the northern flats, from an expedition
## that came before Ilse's. A squat ivory block with oxide trim, its door held by an old
## HOB-series lock: dead until Kestrel's aux power brings HOB back, after which HOB can talk it
## open. Inside, red emergency lamps, a broken console, storage racks and a dormant ship-mind
## core on a rack: the same make as HOB. Taking the core gives the depot's log and HOB a line
## or two about meeting a relative.
##
## State in Game.flags: seen_survey_depot (within 40 m), depot_open, depot_core_taken.

const ID := "survey_depot"
const AT := Vector2(31.5, -86.5)
const RANGE := 2.4
const HOLD := 1.5
const LOG_ID := "depot_1"
const IVORY := Color("d9d2c2")
const OXIDE := Color("bf6835")
const METAL := Color("3c4448")
const RED := Color("ff3b2e")
const TEAL := Color("3fd1b5")
## Inside, local: 10 m wide (x), 8 m deep (z), 3.2 m high; the door is in the +Z wall.
const W := 10.0
const D := 8.0
const H := 3.2

var main: Node
var door_pos := Vector3.ZERO
var core_pos := Vector3.ZERO
var _door: StaticBody3D
var _core: Node3D
var _hold := 0.0
var _mats := {}


func setup(m: Node) -> void:
	main = m
	position = Vector3(AT.x, main.site.height_at(AT.x, AT.y), AT.y)
	# The door faces Kestrel.
	rotation.y = atan2(-AT.x, -AT.y)
	_build()
	_door.visible = not is_open()
	_door.collision_layer = 0 if is_open() else Game.LAYER_WORLD
	_core.visible = not core_taken()


func is_open() -> bool:
	return Game.flags.get("depot_open", false) == true


func core_taken() -> bool:
	return Game.flags.get("depot_core_taken", false) == true


func _process(delta: float) -> void:
	if not main or main.player.dead:
		_hold = 0.0
		return
	var pos: Vector3 = main.player.global_position
	if not Game.flags.get("seen_survey_depot", false) and pos.distance_to(global_position) < 40.0:
		Game.set_flag("seen_survey_depot")
	if not is_open() and Game.is_repaired("aux_power") and pos.distance_to(door_pos) <= RANGE and Input.is_action_pressed("interact"):
		_hold += delta
		if _hold >= HOLD:
			open_door()
	else:
		_hold = 0.0


func interaction(pos: Vector3) -> Dictionary:
	if not is_open() and pos.distance_to(door_pos) <= RANGE:
		if not Game.is_repaired("aux_power"):
			return {"label": "A sealed door with an old HOB-series lock. Dead: no power, no handshake"}
		if _hold > 0.0:
			return {"label": "HOB is talking to the lock  %d%%" % int(_hold / HOLD * 100.0)}
		return {"label": "[Hold E] Let HOB talk to the lock"}
	if is_open() and not core_taken() and pos.distance_to(core_pos) <= RANGE:
		return {"label": "[E] Take the dormant ship-mind core", "action": take_core}
	return {}


func open_door() -> void:
	if is_open():
		return
	_hold = 0.0
	Game.set_flag("depot_open")
	_door.visible = false
	_door.collision_layer = 0
	Sfx.play("repair_clunk", door_pos, -2.0)
	main.voice.say([[Story.HOB, "Oh, I know this lock. It's one of ours. Hello, door. There we are."]])


func take_core() -> void:
	if core_taken() or not is_open():
		return
	Game.set_flag("depot_core_taken")
	_core.visible = false
	Game.find_log(LOG_ID)
	Game.add_scrap(15)
	Sfx.play("scrap_pickup", core_pos, 0.0)
	main.voice.say(Story.DEPOT_LINES)


func _build() -> void:
	var shell := _mat(IVORY, 0.75)
	# Floor, roof, back and side walls; the front wall has a doorway in the middle.
	_box(Vector3(0.0, -0.1, 0.0), Vector3(W, 0.2, D), _mat(METAL, 0.7), true)
	_box(Vector3(0.0, H + 0.15, 0.0), Vector3(W + 0.6, 0.3, D + 0.6), _mat(OXIDE, 0.6), true)
	_box(Vector3(0.0, H * 0.5, -D * 0.5), Vector3(W, H, 0.3), shell, true)
	_box(Vector3(-W * 0.5, H * 0.5, 0.0), Vector3(0.3, H, D), shell, true)
	_box(Vector3(W * 0.5, H * 0.5, 0.0), Vector3(0.3, H, D), shell, true)
	_box(Vector3(-3.2, H * 0.5, D * 0.5), Vector3(3.6, H, 0.3), shell, true)
	_box(Vector3(3.2, H * 0.5, D * 0.5), Vector3(3.6, H, 0.3), shell, true)
	_box(Vector3(0.0, H - 0.4, D * 0.5), Vector3(2.8, 0.8, 0.3), shell, true)
	# Oxide band and a stencilled-looking stripe round the outside.
	_box(Vector3(0.0, 0.5, D * 0.5 + 0.17), Vector3(W, 0.25, 0.04), _mat(OXIDE, 0.6), false)
	# The door: a slab that slides away (hides) when the lock lets go.
	_door = _box(Vector3(0.0, (H - 0.8) * 0.5, D * 0.5), Vector3(2.8, H - 0.8, 0.2), _mat(METAL, 0.45), true) as StaticBody3D
	door_pos = to_global(Vector3(0.0, 0.0, D * 0.5 + 1.0))
	# The lock: a small panel by the door, teal once HOB can see it.
	var lock := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.3, 0.4, 0.06)
	lock.mesh = lm
	lock.material_override = _glow(TEAL, 0.8)
	lock.position = Vector3(1.8, 1.3, D * 0.5 + 0.18)
	add_child(lock)
	# Inside: red emergency lamps, racks, a dead console, and the core on its cradle.
	for x in [-3.0, 3.0]:
		var lamp := OmniLight3D.new()
		lamp.light_color = RED
		lamp.light_energy = 1.4
		lamp.omni_range = 6.0
		lamp.shadow_enabled = false
		lamp.position = Vector3(x, H - 0.4, -1.0)
		add_child(lamp)
		var housing := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.5, 0.15, 0.3)
		housing.mesh = hm
		housing.material_override = _glow(RED, 2.0)
		housing.position = Vector3(x, H - 0.1, -1.0)
		add_child(housing)
	for i in 3:
		_box(Vector3(-4.2, 1.1, -2.6 + i * 1.8), Vector3(0.9, 2.2, 1.4), _mat(METAL, 0.6), true)
		_box(Vector3(-4.2, 1.5, -2.6 + i * 1.8), Vector3(0.95, 0.06, 1.45), _mat(OXIDE, 0.6), false)
	_box(Vector3(3.6, 0.5, -3.0), Vector3(1.8, 1.0, 0.9), _mat(METAL, 0.5), true)
	_box(Vector3(3.6, 1.2, -3.35), Vector3(1.4, 0.6, 0.06), _mat(Color("101418"), 0.3), false)
	# A tipped crate and loose sheets on the floor: whoever left, left in a hurry.
	var crate := _box(Vector3(1.5, 0.35, 1.6), Vector3(1.0, 0.7, 0.7), _mat(OXIDE, 0.7), true)
	crate.rotation.y = 0.4
	_core = Node3D.new()
	_core.position = Vector3(0.0, 0.0, -3.0)
	add_child(_core)
	var cradle := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.2, 0.9, 0.8)
	cradle.mesh = cm
	cradle.material_override = _mat(METAL, 0.5)
	cradle.position.y = 0.45
	_core.add_child(cradle)
	var core := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.28
	cyl.height = 0.7
	core.mesh = cyl
	core.material_override = _glow(Color("e8a44e"), 0.6)
	core.position.y = 1.25
	_core.add_child(core)
	core_pos = to_global(Vector3(0.0, 0.0, -2.0))


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _box(pos: Vector3, size: Vector3, mat: Material, solid: bool) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if not solid:
		mi.position = pos
		add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = pos
	body.add_child(mi)
	body.add_child(shape)
	add_child(body)
	return body


func _mat(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), roughness]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_mats[key] = m
	return _mats[key]
