class_name ListeningPost
extends Node3D
## Kettle discovery (X2.2): one of Ilse Marrow's seismic listening posts, up on the south-east
## slope of the basin. A tall mast with a slow amber blink makes it a landmark from Kestrel; a
## metal walkway climbs the slope to a deck with a hut, dark but for a red emergency lamp, and a
## terminal. Waking the terminal (hold E) brings the post's lights up and gives Ilse's log.
##
## State lives in Game.flags, so it saves with the session:
##   seen_listening_post   Juno has come close enough to notice it (starts the quest).
##   post_awake            the terminal has been woken.

const ID := "listening_post"
## The deck, out on the slope; the walkway starts at the basin floor below it.
const DECK_AT := Vector2(78.4, 93.5)
const WALK_FROM := Vector2(64.3, 76.6)
const SEEN_RANGE := 45.0
const HOLD := 2.0
const RANGE := 2.4
const LOG_ID := "post_1"

const IVORY := Color("d9d2c2")
const OXIDE := Color("bf6835")
const METAL := Color("3c4448")
const AMBER := Color("e8a44e")

var main: Node
var terminal_pos := Vector3.ZERO
var _blink: StandardMaterial3D
var _blink_light: OmniLight3D
var _hut_light: OmniLight3D
var _screen: StandardMaterial3D
var _hold := 0.0
var _time := 0.0
var _mats := {}


## Call once the post is in the scene (it places itself on the terrain).
func setup(m: Node) -> void:
	main = m
	var deck_y: float = main.site.height_at(DECK_AT.x, DECK_AT.y) + 0.6
	position = Vector3(DECK_AT.x, deck_y, DECK_AT.y)
	# Face the open side of the hut back down toward Kestrel.
	rotation.y = atan2(-DECK_AT.x, -DECK_AT.y)
	_build_deck()
	_build_hut()
	_build_mast()
	_build_walkway()
	_apply_awake(Game.flags.get("post_awake", false) == true)


func is_awake() -> bool:
	return Game.flags.get("post_awake", false) == true


func _process(delta: float) -> void:
	_time += delta
	# The mast blinks slowly whether or not the post is awake: it's how Juno finds it.
	var on := fmod(_time, 2.4) < 0.8
	_blink.emission_energy_multiplier = 4.0 if on else 0.3
	_blink_light.light_energy = 2.0 if on else 0.0
	if main and not Game.flags.get("seen_listening_post", false):
		if main.player.global_position.distance_to(global_position) < SEEN_RANGE:
			Game.set_flag("seen_listening_post")
	# Hold E at the terminal to wake it; letting go or walking off starts over.
	if main and not is_awake() and not main.player.dead and main.player.global_position.distance_to(terminal_pos) <= RANGE and Input.is_action_pressed("interact"):
		_hold += delta
		if _hold >= HOLD:
			wake()
	else:
		_hold = 0.0


## The prompt at the terminal (with the hold's progress), or {}.
func interaction(pos: Vector3) -> Dictionary:
	if is_awake() or pos.distance_to(terminal_pos) > RANGE:
		return {}
	if _hold > 0.0:
		return {"label": "Waking the listening post  %d%%" % int(_hold / HOLD * 100.0)}
	return {"label": "[Hold E] Wake the listening post"}


## Brings the post up: lights, screen, Ilse's log, HOB's line.
func wake() -> void:
	if is_awake():
		return
	_hold = 0.0
	Game.set_flag("post_awake")
	_apply_awake(true)
	Sfx.play("power_up", terminal_pos, -4.0)
	Game.find_log(LOG_ID)
	if main and main.get("voice"):
		main.voice.say(Story.POST_LINES)


func _apply_awake(awake: bool) -> void:
	_hut_light.light_color = AMBER if awake else Color("ff3b2e")
	_hut_light.light_energy = 2.2 if awake else 1.0
	_screen.emission = Color("3fd1b5") if awake else Color("401010")
	_screen.emission_energy_multiplier = 1.6 if awake else 0.4


func _build_deck() -> void:
	_box(self, Vector3(0.0, -0.15, 0.0), Vector3(9.0, 0.3, 9.0), _mat(METAL, 0.6), true)
	# Stilts down to the slope (generous: the ground falls away toward the basin).
	for x in [-4.0, 4.0]:
		for z in [-4.0, 4.0]:
			_box(self, Vector3(x, -3.2, z), Vector3(0.35, 6.0, 0.35), _mat(METAL, 0.5), false)
	# A rail on the open sides, with a gap where the walkway arrives.
	_box(self, Vector3(-4.4, 0.55, 0.0), Vector3(0.12, 1.1, 9.0), _mat(OXIDE, 0.6), true)
	_box(self, Vector3(4.4, 0.55, 0.0), Vector3(0.12, 1.1, 9.0), _mat(OXIDE, 0.6), true)
	_box(self, Vector3(-2.6, 0.55, 4.4), Vector3(3.6, 1.1, 0.12), _mat(OXIDE, 0.6), true)


func _build_hut() -> void:
	var hut := Node3D.new()
	hut.position = Vector3(0.0, 0.0, -2.0)
	add_child(hut)
	var wall := _mat(IVORY, 0.7)
	_box(hut, Vector3(0.0, 1.4, -2.0), Vector3(5.0, 2.8, 0.2), wall, true)
	_box(hut, Vector3(-2.5, 1.4, 0.0), Vector3(0.2, 2.8, 4.0), wall, true)
	_box(hut, Vector3(2.5, 1.4, 0.0), Vector3(0.2, 2.8, 4.0), wall, true)
	_box(hut, Vector3(0.0, 2.9, 0.0), Vector3(5.4, 0.25, 4.6), _mat(OXIDE, 0.6), true)
	_box(hut, Vector3(-1.9, 1.4, 1.9), Vector3(1.2, 2.8, 0.2), wall, true)
	# The terminal: a console on a stand facing the doorway.
	_box(hut, Vector3(0.6, 0.55, -1.2), Vector3(1.4, 1.1, 0.7), _mat(METAL, 0.5), true)
	_screen = StandardMaterial3D.new()
	_screen.albedo_color = Color("101418")
	_screen.emission_enabled = true
	var screen := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(1.1, 0.6, 0.05)
	screen.mesh = quad
	screen.material_override = _screen
	screen.position = Vector3(0.6, 1.35, -1.45)
	screen.rotation.x = deg_to_rad(-15.0)
	hut.add_child(screen)
	terminal_pos = hut.to_global(Vector3(0.6, 0.0, -0.3))
	_hut_light = OmniLight3D.new()
	_hut_light.omni_range = 5.0
	_hut_light.shadow_enabled = false
	_hut_light.position = Vector3(0.0, 2.4, 0.0)
	hut.add_child(_hut_light)
	# Crates of spare sensor rigs stacked against the back wall.
	_box(hut, Vector3(-1.4, 0.35, -1.4), Vector3(0.9, 0.7, 0.7), _mat(OXIDE, 0.7), true)
	_box(hut, Vector3(-1.4, 0.95, -1.4), Vector3(0.7, 0.5, 0.6), _mat(IVORY, 0.7), false)


func _build_mast() -> void:
	var mast := Node3D.new()
	mast.position = Vector3(3.2, 0.0, -3.2)
	add_child(mast)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		_box(mast, Vector3(cos(a) * 0.5, 8.0, sin(a) * 0.5), Vector3(0.18, 16.0, 0.18), _mat(METAL, 0.4), false)
	for h in range(1, 16, 2):
		_box(mast, Vector3(0.0, float(h), 0.0), Vector3(0.75, 0.06, 0.75), _mat(METAL, 0.4), false)
	_box(mast, Vector3(0.0, 8.0, 0.0), Vector3(0.6, 16.0, 0.6), null, true)
	# A dish halfway up, turned to the spire in the west.
	var dish := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 1.1
	cone.bottom_radius = 0.15
	cone.height = 0.5
	dish.mesh = cone
	dish.material_override = _mat(IVORY, 0.5)
	dish.position = Vector3(0.0, 11.0, 0.6)
	dish.rotation.x = deg_to_rad(70.0)
	mast.add_child(dish)
	_blink = StandardMaterial3D.new()
	_blink.albedo_color = AMBER
	_blink.emission_enabled = true
	_blink.emission = AMBER
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	bulb.mesh = sphere
	bulb.material_override = _blink
	bulb.position = Vector3(0.0, 16.3, 0.0)
	mast.add_child(bulb)
	_blink_light = OmniLight3D.new()
	_blink_light.light_color = AMBER
	_blink_light.omni_range = 10.0
	_blink_light.shadow_enabled = false
	_blink_light.position = bulb.position
	mast.add_child(_blink_light)


## A plank walkway up the slope from the basin floor to the deck's open side: short level
## segments that follow the ground, each a little above it, so the climb reads as built.
func _build_walkway() -> void:
	var start := Vector3(WALK_FROM.x, 0.0, WALK_FROM.y)
	var end_local := Vector3(0.0, -0.15, 5.6)
	var end := to_global(end_local)
	var steps := 7
	var prev := Vector3(start.x, main.site.height_at(start.x, start.z) + 0.15, start.z)
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p := start.lerp(end, t)
		p.y = end.y if i == steps else maxf(main.site.height_at(p.x, p.z) + 0.3, prev.y)
		_plank(prev, p)
		if i < steps:
			# A post at each joint, down to the ground.
			var g: float = main.site.height_at(p.x, p.z)
			_box_global(Vector3(p.x, (p.y + g) * 0.5 - 0.2, p.z), Vector3(0.2, maxf(p.y - g, 0.2) + 0.4, 0.2), _mat(METAL, 0.5))
		prev = p


func _plank(a: Vector3, b: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	var mesh := BoxMesh.new()
	var length := a.distance_to(b)
	mesh.size = Vector3(2.0, 0.2, length + 0.4)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(METAL, 0.55)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	body.add_child(mi)
	body.add_child(shape)
	get_parent().add_child(body)
	body.global_position = (a + b) * 0.5
	body.look_at(b, Vector3.UP)
	# Oxide edge strips so the walkway reads from down on the basin floor.
	for side in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.08, 0.08, length + 0.4)
		strip.mesh = sm
		strip.material_override = _mat(OXIDE, 0.6)
		strip.position = Vector3(side * 0.96, 0.14, 0.0)
		body.add_child(strip)


func _box_global(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	get_parent().add_child(mi)
	mi.global_position = pos


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visible = mat != null
	if not solid:
		mi.position = pos
		parent.add_child(mi)
		return
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = pos
	body.add_child(mi)
	body.add_child(shape)
	parent.add_child(body)


func _mat(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), roughness]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_mats[key] = m
	return _mats[key]
