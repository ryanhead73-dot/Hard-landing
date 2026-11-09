class_name WalkFinds
extends Node
## Small discoveries on the walks between sites (production pack, "ten walk discoveries"): each
## takes under a minute and a half, announces itself with its own sound or light, pays off on the
## spot and stays done (Game.flags "find_<id>"). They sit off the main routes to reward a look
## around. The Kettle's are built once and suspend with the basin; a region's are built into its
## scene when Juno arrives there and go with it.
##
##   rain_cup        Kettle  a cup of rain under a broken signpost: conductive fibre, scanner range
##   towing_marks    Kettle  scored basalt toward a crawlspace: a med-seal
##   silent_beacon   Kettle  a dead transmitter on a lookout: turn its dish, scrap and a bearing
##   glass_wind      Kettle  wind plays three notes through cracked panels: repeat them on a lock
##   hob_bolt        Kettle  (after the canopy) a loose Kestrel bolt: put it back, HOB notices
##   helmet          Kettle  a cracked helmet that hums the crash's triple click: lore and scrap
##   boot            Shatterlands  a boot with greenhouse coordinates and a ration: a med-seal
##   static_orchard  Gillwood  seed pods that flash if you run past: scan one for an arc charge
##   pocket_weather  Gillwood  rain from a clear sky, in threes: a Loom clue and spore fibre
##   signal_flag     Loom Expanse  a fibre flag that knots itself in still air, pulling west: it
##                   opens the bypass lane behind the Weave (LoomExpanse.bypass_open)

const USE := 2.2
const CUE_RANGE := 22.0
## Kettle finds: where (x, z) on the basin floor.
const KETTLE := {
	"rain_cup": Vector2(24.0, -30.0),
	"towing_marks": Vector2(-50.0, 14.0),
	"silent_beacon": Vector2(60.0, 100.0),
	"glass_wind": Vector2(-20.0, -40.0),
	"hob_bolt": Vector2(-6.0, -9.0),
	"helmet": Vector2(22.0, 52.0),
}
const MARKS_FROM := Vector2(-36.0, 29.0)
## Region finds, in each region's own space.
const REGIONAL := {
	"shatterlands": {"boot": Vector2(2.0, -24.0)},
	"gillwood": {"static_orchard": Vector2(-20.0, -6.0), "pocket_weather": Vector2(-30.0, -36.0)},
	"loom_expanse": {"signal_flag": Vector2(-40.0, 38.0)},
}
## Plan point (Kestrel.plan) on the fabricator bench where the bolt goes back.
const BOLT_HOME := Vector3(14.2, 0.97, 9.6)
const BOLT_RETURN_AT := Vector3(14.2, 0.0, 10.7)
## The glass wind's notes, low to high, and the order the wind plays them in.
## The three glass tones (Jake's recordings, low to high).
const TONES := ["glass_wind_low", "glass_wind_mid", "glass_wind_high"]
const TONE_ORDER := [0, 2, 1]
const AMBER := Color("e8a44e")
const TEAL := Color("3fd1b5")

var main: Node
## id -> the find's root node (Kettle finds persist; region finds go with their scene).
var nodes := {}
var _cue_t := {}
var _lock_input: Array[int] = []
var _flash_cooldown := 0.0


func setup(m: Node) -> void:
	main = m
	for id in KETTLE:
		var at: Vector2 = KETTLE[id]
		var root := Node3D.new()
		root.name = "Find_" + id
		root.position = Vector3(at.x, main.site.height_at(at.x, at.y), at.y)
		main.add_child(root)
		nodes[id] = root
		call("_build_" + id, root)
	main.regions.travelled.connect(_on_travelled)
	Game.flag_changed.connect(func(_f, _v): _sync())
	_sync()


static func found(id: String) -> bool:
	return bool(Game.flags.get("find_" + id, false))


static func all_ids() -> Array:
	var out: Array = KETTLE.keys()
	for r in REGIONAL:
		out.append_array(REGIONAL[r].keys())
	return out


func _on_travelled(_from: String, to: String) -> void:
	if not REGIONAL.has(to) or main.regions.scene == null:
		return
	var scene: RegionScene = main.regions.scene
	for id in REGIONAL[to]:
		var at: Vector2 = REGIONAL[to][id]
		var root := Node3D.new()
		root.name = "Find_" + id
		root.position = Vector3(at.x, scene.height_at(at.x, at.y), at.y)
		scene.add_child(root)
		nodes[id] = root
		call("_build_" + id, root)
	_sync()


func _live(id: String) -> Node3D:
	var n: Variant = nodes.get(id)
	if n == null or not is_instance_valid(n) or not (n as Node3D).is_inside_tree():
		return null
	return n


## The prompt a find offers at `pos`, or {}.
func interaction(pos: Vector3) -> Dictionary:
	if main.opening and main.opening.active():
		return {}
	for id in nodes:
		var root := _live(id)
		# The bolt's root hides once it is in her pocket, but the bench still takes it back.
		if root == null or not (root.visible or id == "hob_bolt"):
			continue
		var i: Dictionary = call("_use_" + id, root, pos)
		if not i.is_empty():
			return i
	return {}


func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	_flash_cooldown = maxf(_flash_cooldown - delta, 0.0)
	var at: Vector3 = main.player.global_position
	for id in nodes:
		var root := _live(id)
		if root == null or not root.visible or not root.is_visible_in_tree():
			continue
		if root.global_position.distance_to(at) > CUE_RANGE:
			continue
		_cue_t[id] = float(_cue_t.get(id, 0.0)) - delta
		if _cue_t[id] <= 0.0:
			_cue_t[id] = _cue(id, root)
		if id == "static_orchard" and not found(id):
			_orchard_tick(root, at)


## Plays a find's sound cue; returns seconds until the next one.
func _cue(id: String, root: Node3D) -> float:
	if found(id) and id not in ["silent_beacon", "pocket_weather"]:
		return 999.0
	match id:
		"rain_cup":
			Sfx.play("rain_cup_drip", root.global_position, -10.0, 0.05)
			return 2.6
		"silent_beacon":
			if found(id):
				Sfx.play("beacon_ping", root.global_position + Vector3.UP * 5.0, -14.0, 0.0)
				return 4.0
			Sfx.play("hull_groan", root.global_position, -18.0, 0.2)
			return 9.0
		"glass_wind":
			_play_tones(root)
			return 8.0
		"helmet":
			Sfx.play("helmet_humming", root.global_position, -14.0, 0.0)
			return 9.0
		"hob_bolt":
			Sfx.play("ui_click", root.global_position, -20.0, 0.3)
			return 5.0
		"signal_flag":
			Sfx.play("thread_spool", root.global_position + Vector3.UP * 2.0, -14.0, 0.3)
			return 6.0
	return 999.0


func _play_tones(root: Node3D) -> void:
	for i in TONE_ORDER.size():
		get_tree().create_timer(i * 1.1).timeout.connect(_tone.bind(root, TONE_ORDER[i], -8.0))


func _tone(root: Node3D, which: int, volume_db: float) -> void:
	if not is_instance_valid(root) or not Sfx.has_sound(TONES[which]):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = Sfx.stream(TONES[which])
	p.volume_db = volume_db
	p.bus = "SFX"
	p.position = Vector3(0.0, 1.6, 0.0)
	root.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Shows each find in its current state.
func _sync() -> void:
	var bolt := _live("hob_bolt")
	if bolt:
		# The bolt shakes loose once the canopy's back on; once picked up it is in her pocket.
		bolt.visible = Game.is_repaired("canopy") and not Game.flags.get("find_hob_bolt_taken", false)
	var home: Node3D = main.kestrel.get_node_or_null("ReturnedBolt") if main.kestrel else null
	if found("hob_bolt") and home == null and main.kestrel:
		var b := _mesh(main.kestrel, main.kestrel.plan(BOLT_HOME.x, BOLT_HOME.y, BOLT_HOME.z), _cyl(0.04, 0.22), _metal(Color("c9a46a")))
		b.name = "ReturnedBolt"
		b.rotation.z = PI * 0.5
	var beacon := _live("silent_beacon")
	if beacon:
		var lamp := beacon.get_node_or_null("Lamp") as OmniLight3D
		if lamp:
			lamp.visible = found("silent_beacon")
		var dish := beacon.get_node_or_null("Dish") as Node3D
		if dish:
			dish.rotation.x = -0.6 if found("silent_beacon") else 0.9
	var lid := _live("towing_marks")
	if lid and lid.get_node_or_null("Hatch"):
		(lid.get_node("Hatch") as Node3D).rotation.x = -1.3 if found("towing_marks") else 0.0
	var lock := _live("glass_wind")
	if lock and lock.get_node_or_null("LockLid"):
		(lock.get_node("LockLid") as Node3D).rotation.x = -1.2 if found("glass_wind") else 0.0


func _finish(id: String, lines: Array) -> void:
	Game.set_flag("find_" + id, true)
	main.player.anim.play("interact")
	main.voice.interrupt(lines)
	main.save_game()


# --- The finds ---------------------------------------------------------------------------------

func _build_rain_cup(root: Node3D) -> void:
	var post := _mesh(root, Vector3(0.0, 1.3, 0.0), _box(Vector3(0.12, 2.6, 0.12)), _metal(Color("5d6468")))
	post.rotation.z = 0.18
	var sign_plate := _mesh(root, Vector3(0.35, 2.3, 0.0), _box(Vector3(1.1, 0.5, 0.05)), _metal(Color("bf6835")))
	sign_plate.rotation.z = -0.5
	_mesh(root, Vector3(1.1, 0.95, 0.3), _box(Vector3(0.9, 0.06, 0.05)), _metal(Color("bf6835"))).rotation = Vector3(0.3, 0.4, 1.2)
	_mesh(root, Vector3(0.3, 0.1, 0.5), _cyl(0.14, 0.2), _metal(Color("9aa0a3")))
	_mesh(root, Vector3(0.3, 0.19, 0.5), _cyl(0.12, 0.01), _glow(Color(0.55, 0.8, 0.85), 0.6))


func _use_rain_cup(root: Node3D, pos: Vector3) -> Dictionary:
	if found("rain_cup") or not _near(root, pos):
		return {}
	return {"label": "[E] Analyse the rainwater in the cup", "action": func():
		var had: bool = Game.flags.get("scanner_battery", false)
		if had:
			Game.add_scrap(15)
		else:
			Game.set_flag("scanner_battery", true)
			main.hud.show_message("Conductive fibre in the rain: your suit scanner now marks salvage and wildlife nearby.")
		_finish("rain_cup", Story.FIND_RAIN_CUP_AGAIN if had else Story.FIND_RAIN_CUP)}


func _build_towing_marks(root: Node3D) -> void:
	# Pale scores in the basalt from the relay path to the crawlspace.
	var from := Vector3(MARKS_FROM.x, 0.0, MARKS_FROM.y) - root.position
	var steps := 9
	for i in steps:
		var f := float(i) / steps
		var p := from.lerp(Vector3.ZERO, f)
		var y: float = main.site.height_at(root.position.x + p.x, root.position.z + p.z) - root.position.y + 0.03
		var mark := _mesh(root, Vector3(p.x, y, p.z), _box(Vector3(0.12, 0.02, 1.6)), _glow(Color("d9d2c2"), 0.25))
		mark.rotation.y = atan2(p.x, p.z) + 0.08 * sin(i * 2.1)
	_mesh(root, Vector3(0.0, 0.25, 0.0), _box(Vector3(1.6, 0.5, 1.2)), _metal(Color("3a3f43")))
	var hinge := Node3D.new()
	hinge.name = "Hatch"
	hinge.position = Vector3(0.0, 0.52, -0.55)
	root.add_child(hinge)
	_mesh(hinge, Vector3(0.0, 0.0, 0.55), _box(Vector3(1.3, 0.06, 1.0)), _metal(Color("bf6835")))


func _use_towing_marks(root: Node3D, pos: Vector3) -> Dictionary:
	if found("towing_marks") or not _near(root, pos):
		return {}
	return {"label": "[E] Open the maintenance crawlspace", "action": func():
		Game.add_stims(1)
		main.hud.show_message("A med-seal, still sealed.")
		Sfx.play("repair_clunk", root.global_position, -4.0)
		_finish("towing_marks", Story.FIND_TOWING_MARKS)}


func _build_silent_beacon(root: Node3D) -> void:
	# A level concrete pad to stand on, on the slope.
	var pad := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 1.2, 4.0)
	shape.shape = box
	pad.add_child(shape)
	pad.position = Vector3(0.0, -0.3, 0.0)
	root.add_child(pad)
	_mesh(pad, Vector3.ZERO, _box(box.size), _metal(Color("6b6a62")))
	_mesh(root, Vector3(0.0, 0.5, 0.0), _box(Vector3(1.0, 0.4, 1.0)), _metal(Color("3a3f43")))
	_mesh(root, Vector3(0.0, 2.6, 0.0), _cyl(0.1, 4.6), _metal(Color("9aa0a3")))
	var dish := Node3D.new()
	dish.name = "Dish"
	dish.position = Vector3(0.0, 4.4, 0.25)
	root.add_child(dish)
	var bowl := _mesh(dish, Vector3(0.0, 0.0, 0.2), _cyl(0.9, 0.12), _metal(Color("d9d2c2")))
	bowl.rotation.x = PI * 0.5
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color("ff4030")
	lamp.light_energy = 1.2
	lamp.omni_range = 6.0
	lamp.position = Vector3(0.0, 5.1, 0.0)
	root.add_child(lamp)
	_mesh(root, Vector3(0.0, 5.0, 0.0), _sphere(0.1), _glow(Color("ff4030"), 2.0))


func _use_silent_beacon(root: Node3D, pos: Vector3) -> Dictionary:
	if found("silent_beacon") or not _near(root, pos, 3.0):
		return {}
	return {"label": "[Hold E] Turn the dish back to the sky", "hold": 1.5, "action": func():
		Game.add_scrap(15)
		Game.set_flag("find_beacon_bearing", true)
		Sfx.play("dish_restart", root.global_position + Vector3.UP * 3.0, 0.0, 0.0)
		main.hud.show_message("The beacon has a bearing on the canyon east: marked on your map.")
		_finish("silent_beacon", Story.FIND_BEACON)}


func _build_glass_wind(root: Node3D) -> void:
	var glass := _glow(Color(0.6, 0.78, 0.8), 0.15)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.5
	for i in 3:
		var pane := _mesh(root, Vector3(-1.4 + i * 1.4, 1.5 + 0.2 * i, -1.2), _box(Vector3(1.2, 2.6 + 0.4 * i, 0.06)), glass)
		pane.rotation.z = 0.05 * (i - 1)
		_mesh(root, Vector3(-2.1 + i * 1.4, 1.6, -1.2), _box(Vector3(0.1, 3.2, 0.12)), _metal(Color("5d6468")))
	# The salvage lock: three keys, low to high, left to right.
	_mesh(root, Vector3(0.0, 0.45, 0.6), _box(Vector3(1.4, 0.9, 0.7)), _metal(Color("3a3f43")))
	for i in 3:
		_mesh(root, Vector3(-0.4 + i * 0.4, 0.92, 0.6), _box(Vector3(0.22, 0.06, 0.22)), _glow(AMBER, 0.6 + i * 0.6))
	var lid := Node3D.new()
	lid.name = "LockLid"
	lid.position = Vector3(0.0, 0.9, 0.95)
	root.add_child(lid)
	_mesh(lid, Vector3(0.0, 0.03, -0.12), _box(Vector3(1.4, 0.04, 0.25)), _metal(Color("bf6835")))


func _use_glass_wind(root: Node3D, pos: Vector3) -> Dictionary:
	if found("glass_wind") or not _near(root, pos, 2.6):
		return {}
	# The key nearest where she stands along the lock.
	var local := root.to_local(pos)
	var key := clampi(int(round((local.x + 0.4) / 0.4)), 0, 2)
	var names := ["low", "middle", "high"]
	return {"label": "[E] Press the %s key   [%d/3]" % [names[key], _lock_input.size()], "action": func():
		_tone(root, key, -2.0)
		_lock_input.append(key)
		for i in _lock_input.size():
			if _lock_input[i] != TONE_ORDER[i]:
				_lock_input.clear()
				Sfx.play("rifle_empty", root.global_position, -4.0, 0.0)
				main.hud.show_message("The lock buzzes and resets. Listen to the wind.")
				return
		if _lock_input.size() == TONE_ORDER.size():
			_lock_input.clear()
			Game.add_scrap(30)
			main.hud.show_message("Spare rifle parts: 30 scrap toward your next upgrade.")
			_finish("glass_wind", Story.FIND_GLASS_WIND)}


func _build_hob_bolt(root: Node3D) -> void:
	var bolt := _mesh(root, Vector3(0.0, 0.06, 0.0), _cyl(0.04, 0.22), _metal(Color("c9a46a")))
	bolt.rotation.z = PI * 0.5
	var glint := OmniLight3D.new()
	glint.light_color = AMBER
	glint.light_energy = 0.4
	glint.omni_range = 1.5
	glint.position = Vector3(0.0, 0.3, 0.0)
	root.add_child(glint)


func _use_hob_bolt(root: Node3D, pos: Vector3) -> Dictionary:
	if found("hob_bolt"):
		return {}
	if not Game.flags.get("find_hob_bolt_taken", false):
		if not root.visible or not _near(root, pos):
			return {}
		return {"label": "[E] Pick up the loose ship's bolt", "action": func():
			Game.set_flag("find_hob_bolt_taken", true)
			main.player.anim.play("interact")
			main.voice.interrupt(Story.FIND_BOLT_TAKEN)}
	var at: Vector3 = main.kestrel.to_global(main.kestrel.plan(BOLT_RETURN_AT.x, BOLT_RETURN_AT.y, BOLT_RETURN_AT.z))
	if pos.distance_to(at) > USE:
		return {}
	return {"label": "[E] Put bolt 14-C back on the bench", "action": func():
		_finish("hob_bolt", Story.FIND_BOLT_RETURNED if Game.is_repaired("aux_power") else Story.FIND_BOLT_TAKEN)}


func _build_helmet(root: Node3D) -> void:
	for i in 5:
		var rock := _mesh(root, Vector3(cos(i * 1.3) * 0.9, 0.15, sin(i * 1.3) * 0.7), _box(Vector3(0.6, 0.3, 0.5)), _metal(Color("2a2c2e")))
		rock.rotation.y = i * 0.7
	_mesh(root, Vector3(0.0, 0.32, 0.0), _sphere(0.24), _metal(Color("d9d2c2")))
	_mesh(root, Vector3(0.0, 0.34, 0.18), _box(Vector3(0.3, 0.16, 0.08)), _glow(TEAL, 0.5))


func _use_helmet(root: Node3D, pos: Vector3) -> Dictionary:
	if found("helmet") or not _near(root, pos):
		return {}
	return {"label": "[E] Play the helmet's recorder", "action": func():
		Sfx.play("helmet_humming", root.global_position, 0.0, 0.0)
		Game.add_scrap(12)
		_finish("helmet", Story.FIND_HELMET)}


func _build_boot(root: Node3D) -> void:
	var boot := _mesh(root, Vector3(0.0, 0.15, 0.0), _box(Vector3(0.3, 0.3, 0.12)), _metal(Color("5a4a3c")))
	boot.rotation.y = 0.6
	_mesh(root, Vector3(0.12, 0.05, 0.2), _box(Vector3(0.32, 0.1, 0.12)), _metal(Color("4a3c30"))).rotation.y = 0.6
	_mesh(root, Vector3(-0.3, 0.04, -0.1), _box(Vector3(0.14, 0.05, 0.08)), _glow(AMBER, 0.4))


func _use_boot(root: Node3D, pos: Vector3) -> Dictionary:
	if found("boot") or not _near(root, pos):
		return {}
	return {"label": "[E] Look in the boot", "action": func():
		Game.add_stims(1)
		Game.set_flag("greenhouse_coords", true)
		main.hud.show_message("An unopened ration (a med-seal's worth of patching) and coordinates to Reyes's greenhouse.")
		_finish("boot", Story.FIND_BOOT)}


## A survey pole with a pale fibre flag that pulls taut toward the west wall with no wind.
func _build_signal_flag(root: Node3D) -> void:
	_mesh(root, Vector3(0.0, 1.2, 0.0), _cyl(0.04, 2.4), _metal(Color("c9c4b8")))
	var flag := _mesh(root, Vector3(-0.45, 2.15, 0.0), _box(Vector3(0.9, 0.35, 0.02)), _glow(Color("e6dcff"), 0.6))
	flag.name = "Flag"
	flag.rotation.z = 0.12
	_mesh(root, Vector3(-0.95, 2.1, 0.0), _cyl(0.07, 0.12), _glow(TEAL, 1.2)).rotation.z = PI * 0.5


func _use_signal_flag(root: Node3D, pos: Vector3) -> Dictionary:
	if found("signal_flag") or not _near(root, pos):
		return {}
	return {"label": "[E] Feel which way the flag pulls", "action": func():
		main.hud.show_message("The flag's knot points west, at the laced gap in the wall. The lacing goes slack: a lane round the Weave.")
		_finish("signal_flag", Story.FIND_SIGNAL_FLAG)}


func _build_static_orchard(root: Node3D) -> void:
	var scene: RegionScene = main.regions.scene
	for i in 8:
		var a := i * 0.8
		var r := 1.2 + (i % 3) * 0.9
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var g := (scene.height_at(root.position.x + p.x, root.position.z + p.z) - root.position.y) if scene else 0.0
		_mesh(root, Vector3(p.x, g + 0.35, p.z), _cyl(0.025, 0.7), _metal(Color("3d4a3a")))
		_mesh(root, Vector3(p.x, g + 0.75, p.z), _sphere(0.12), _glow(TEAL, 1.8))
	var flash := OmniLight3D.new()
	flash.name = "Flash"
	flash.light_color = Color(0.7, 1.0, 0.95)
	flash.light_energy = 0.0
	flash.omni_range = 9.0
	flash.position = Vector3(0.0, 1.2, 0.0)
	root.add_child(flash)


## Running past the pods sets them off: a harmless, startling flash. Walking doesn't.
func _orchard_tick(root: Node3D, at: Vector3) -> void:
	if _flash_cooldown > 0.0 or root.global_position.distance_to(at) > 4.5:
		return
	if not main.player.get("_sprinting"):
		return
	_flash_cooldown = 5.0
	var flash := root.get_node("Flash") as OmniLight3D
	var t := create_tween()
	t.tween_property(flash, "light_energy", 8.0, 0.05)
	t.tween_property(flash, "light_energy", 0.0, 0.5)
	Sfx.play("seedpod_flash", root.global_position, -2.0, 0.1)
	main.player.add_trauma(0.25)


func _use_static_orchard(root: Node3D, pos: Vector3) -> Dictionary:
	if found("static_orchard") or not _near(root, pos, 3.5):
		return {}
	return {"label": "[E] Scan the seed pods", "action": func():
		Sfx.play("scanner_ping", null, -4.0, 0.0)
		Game.add_charges(1)
		main.hud.show_message("A seed pod holds a field charge: +1 arc charge.")
		_finish("static_orchard", Story.FIND_ORCHARD)}


func _build_pocket_weather(root: Node3D) -> void:
	var rain := CPUParticles3D.new()
	rain.amount = 160
	rain.lifetime = 0.9
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	rain.emission_sphere_radius = 2.2
	rain.position = Vector3(0.0, 6.0, 0.0)
	rain.direction = Vector3.DOWN
	rain.spread = 2.0
	rain.gravity = Vector3(0.0, -9.0, 0.0)
	rain.initial_velocity_min = 4.0
	rain.initial_velocity_max = 6.0
	var drop := QuadMesh.new()
	drop.size = Vector2(0.02, 0.35)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.85, 0.9, 0.45)
	drop.material = m
	rain.mesh = drop
	root.add_child(rain)
	var puddle := _mesh(root, Vector3(0.0, 0.03, 0.0), _cyl(2.0, 0.02), _glow(Color(0.3, 0.42, 0.45), 0.2))
	puddle.name = "Puddle"
	if Sfx.has_sound("rain_loop"):
		var hiss := AudioStreamPlayer3D.new()
		hiss.stream = Sfx.stream("rain_loop")
		hiss.volume_db = -10.0
		hiss.unit_size = 4.0
		hiss.bus = "SFX"
		hiss.autoplay = true
		hiss.position = Vector3(0.0, 1.5, 0.0)
		root.add_child(hiss)


func _use_pocket_weather(root: Node3D, pos: Vector3) -> Dictionary:
	if found("pocket_weather") or not _near(root, pos, 3.0):
		return {}
	return {"label": "[E] Scan the rain from a clear sky", "action": func():
		Sfx.play("scanner_ping", null, -4.0, 0.0)
		Game.add_scrap(20)
		Game.set_flag("clue_loom_threes", true)
		_finish("pocket_weather", Story.FIND_POCKET_WEATHER)}


# --- Helpers ------------------------------------------------------------------------------------

func _near(root: Node3D, pos: Vector3, r := USE) -> bool:
	var d := root.global_position - pos
	d.y *= 0.5
	return d.length() < r


func _mesh(parent: Node3D, at: Vector3, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 12
	return c


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


func _metal(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.metallic = 0.3
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m
