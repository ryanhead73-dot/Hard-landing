class_name RegionManager
extends Node
## Moves Juno between regions (RegionDB). The Kettle is main's own world and always stays
## loaded; while Juno is elsewhere it is hidden and paused (creatures, missions, weather, the day
## cycle) and the other region is built at its own origin, far from the basin. Travel goes
## through a gate in the world and a short fade with the region's name, and Game.region records
## where she is, so a save made away from the Kettle loads back there.

signal travelled(from: String, to: String)

const FADE := 0.35
## Kettle nodes that keep running while away: they hold Juno, the camera, the look and the UI.
const KEEP_TYPES := ["WorldEnvironment", "DirectionalLight3D"]

var main: Node
## The region Juno is in now.
var current := "kettle"
## The built region while away from the Kettle, or null.
var scene: RegionScene
## Gates standing in the Kettle, by the region they lead to.
var gates := {}
var travelling := false

var _suspended: Array[Node] = []
var _old_modes := {}
var _old_look := {}
var _old_day_cycle := true
var _fade: ColorRect
var _title: Label


func setup(m: Node) -> void:
	main = m
	_build_fade()
	for id in RegionDB.travel_regions():
		var r := RegionDB.get_region(id)
		if r.get("from", "") == "kettle":
			gates[id] = _build_gate(id, r)
	Game.flag_changed.connect(_on_flag_changed)


func _on_flag_changed(_flag: String, _value: Variant) -> void:
	for id in gates:
		_set_rubble(gates[id], is_open(id))


## Rubble blocks a shut gate and is cleared (hidden, no collision) once it opens.
func _set_rubble(gate: Node3D, open: bool) -> void:
	var rubble := gate.get_node("Rubble") as Node3D
	rubble.visible = not open
	for b in rubble.get_children():
		(b as CollisionObject3D).collision_layer = 0 if open else Game.LAYER_WORLD


func in_kettle() -> bool:
	return current == "kettle"


func is_open(id: String) -> bool:
	return Game.flags.get(String(RegionDB.get_region(id).get("unlock_flag", "")), false) == true


## After a load: put Juno back in the region the save was made in.
func restore() -> void:
	var id := Game.region
	if id != current and (id == "kettle" or id in RegionDB.travel_regions()):
		await travel(id, true)


## Where Juno comes back to life after going down: the region's entry while away.
func respawn_point() -> Vector3:
	return scene.entry_global() if scene else main.SPAWN


func waypoint():
	if scene == null or scene.goal == null:
		return null
	return scene.to_global(scene.goal)


## The prompt and action for a gate within reach, or {}.
func interaction(pos: Vector3) -> Dictionary:
	if travelling:
		return {}
	if scene:
		if pos.distance_to(scene.exit_global()) < 3.0:
			return {"label": "[E] " + scene.exit_label, "action": travel.bind("kettle")}
		return scene.interaction(pos)
	for id in gates:
		var gate: Node3D = gates[id]
		if pos.distance_to(gate.global_position) >= 6.0:
			continue
		var r := RegionDB.get_region(id)
		if not is_open(id):
			return {"label": String(r["locked_text"])}
		if _busy():
			return {"label": "Not now: Kestrel needs you"}
		return {"label": "[E] " + String(r["enter_text"]), "action": travel.bind(id)}
	return {}


func _busy() -> bool:
	return Game.launched or Game.launch_objective != "" or main.siege.is_active()


## Takes Juno to region `to` (or home to the Kettle). `instant` skips the fade (loading a save).
func travel(to: String, instant := false) -> void:
	if travelling or to == current:
		return
	travelling = true
	var from := current
	if not instant:
		await _fade_to(1.0, RegionDB.display_name(to))
	if scene:
		_leave_scene()
	if to == "kettle":
		_resume_kettle()
		var gate: Node3D = gates.get(from)
		main.player.revive(gate.to_global(Vector3(0.0, 0.5, 4.0)) if gate else main.SPAWN, false)
		if gate:
			main.player.face(gate.global_rotation.y)
	else:
		if from == "kettle":
			_suspend_kettle()
		_enter_scene(to)
	current = to
	Game.region = to
	travelled.emit(from, to)
	if not instant:
		await get_tree().create_timer(0.25).timeout
		await _fade_to(0.0, "")
	travelling = false


func _enter_scene(id: String) -> void:
	var r := RegionDB.get_region(id)
	scene = load(String(r["scene"])).new()
	scene.name = "Region_" + id
	scene.position = r["origin"]
	main.add_child(scene)
	_old_look = scene.apply_environment(main._env, main._sun)
	main.player.revive(scene.entry_global(), false)
	main.player.face(scene.entry_yaw)


func _leave_scene() -> void:
	RegionScene.restore_environment(_old_look, main._env, main._sun)
	_old_look = {}
	scene.queue_free()
	scene = null


## Hides and pauses the basin: everything main built except Juno, the camera rig, the light and
## the UI. Storms end first so the rain doesn't follow her.
func _suspend_kettle() -> void:
	main.weather.clear_storm(true)
	_old_day_cycle = main.day_cycle
	main.day_cycle = false
	_suspended.clear()
	_old_modes.clear()
	for child in main.get_children():
		if child == main.player or child == self or child.get_class() in KEEP_TYPES or child is CanvasLayer or child is Camera3D:
			continue
		if child is Node3D or child in [main.wildlife, main.weather, main.missions, main.siege]:
			_suspended.append(child)
			_old_modes[child] = [child.process_mode, child.visible if child is Node3D else true]
			child.process_mode = Node.PROCESS_MODE_DISABLED
			if child is Node3D:
				child.visible = false


func _resume_kettle() -> void:
	for child in _suspended:
		if is_instance_valid(child):
			child.process_mode = _old_modes[child][0]
			if child is Node3D:
				child.visible = _old_modes[child][1]
	_suspended.clear()
	_old_modes.clear()
	main.day_cycle = _old_day_cycle
	main.set_daylight(main.daylight_at(main.day_time))


## A canyon mouth at the basin's edge: two basalt slabs, a band of the far region's light between
## them, and rubble across it until the way is open.
func _build_gate(id: String, r: Dictionary) -> Node3D:
	var gate := Node3D.new()
	gate.name = "Gate_" + id
	var p: Vector3 = r["gate_pos"]
	p.y = main.site.height_at(p.x, p.z)
	gate.position = p
	# The way through (-Z) leads outward, away from the middle of the basin.
	gate.rotation.y = atan2(-p.x, -p.z)
	main.add_child(gate)
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color("1b1d1f")
	rock.roughness = 0.9
	# Leaning basalt columns either side of the cut, solid boxes behind them for collision.
	for x in [-4.6, 4.6]:
		_slab(gate, Vector3(x, 7.0, -3.0), Vector3(3.2, 14.0, 10.0), null, true)
		for i in 4:
			var col := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.radial_segments = 6
			mesh.rings = 1
			mesh.top_radius = 0.9 + 0.2 * (i % 2)
			mesh.bottom_radius = mesh.top_radius + 0.25
			mesh.height = 15.0 - i * 1.8 + (2.0 if x > 0.0 else 0.0) * (i % 2)
			col.mesh = mesh
			col.material_override = rock
			col.position = Vector3(x + signf(x) * (0.2 * i) - signf(x) * 0.6, mesh.height * 0.5 - 0.5, 1.0 - i * 2.4)
			col.rotation = Vector3(0.0, i * 0.7, signf(x) * -0.06 * (i + 1))
			gate.add_child(col)
	# Far-off fungal light down the cut: the only hint of colour from the other side.
	var hint := OmniLight3D.new()
	hint.light_color = Color("7f6bd6")
	hint.light_energy = 2.5
	hint.omni_range = 9.0
	hint.shadow_enabled = false
	hint.position = Vector3(0.0, 3.0, -7.0)
	gate.add_child(hint)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("100d18")
	glow.emission_enabled = true
	glow.emission = Color("4a3a78")
	glow.emission_energy_multiplier = 0.5
	_slab(gate, Vector3(0.0, 6.0, -8.0), Vector3(6.4, 12.0, 0.3), glow, false)
	var rubble := Node3D.new()
	rubble.name = "Rubble"
	gate.add_child(rubble)
	# A slumped heap across the mouth, tallest in the middle.
	for i in 7:
		var x := -3.0 + i
		var tall := 3.4 - absf(x) * 0.6
		_slab(rubble, Vector3(x, tall * 0.5 - 0.3, 1.5 + (i % 3) * 0.7), Vector3(1.7, tall, 1.9), rock, true)
		(rubble.get_child(rubble.get_child_count() - 1) as Node3D).rotation = Vector3(0.15 * (i % 3), 0.5 * i, 0.12 * ((i + 1) % 3))
	_set_rubble(gate, is_open(id))
	return gate


func _slab(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	# A slab with no material is collision only (dressed by other meshes).
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


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.03, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.add_theme_font_size_override("font_size", 40)
	_title.modulate.a = 0.0
	layer.add_child(_title)


func _fade_to(alpha: float, title: String) -> void:
	if title != "":
		_title.text = title.to_upper()
	var t := create_tween().set_parallel()
	t.tween_property(_fade, "color:a", alpha, FADE)
	t.tween_property(_title, "modulate:a", alpha, FADE)
	await t.finished
