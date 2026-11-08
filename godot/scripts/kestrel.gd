@tool
class_name Kestrel
extends Node3D
## Greybox of Kestrel, generated from data/kestrel_layout.json so it always matches the deck plan.
## Plan coordinates: x = metres aft of the nose, z = metres from the port reference line
## (centreline at 13), y = metres above the main deck. plan() converts them to local space.

signal repair_changed(id: String, repaired: bool)
## The staged aux power-up (see power_up) has finished and every light is on.
signal power_up_finished

const LAYOUT_PATH := "res://data/kestrel_layout.json"
const REPAIR_ORDER: Array[String] = ["aux_power", "cooling", "canopy", "landing_gear", "wing", "engine", "navigation"]
const REPAIR_NAMES := {
	"aux_power": "Auxiliary power",
	"cooling": "Cooling manifold",
	"canopy": "Cockpit canopy",
	"landing_gear": "Landing gear",
	"wing": "Port wing",
	"engine": "Port engine",
	"navigation": "Navigation",
}

## Crash pose: deck sits low, rolled toward starboard and nose down. Fixing the gear levels it.
const CRASH_DECK_Y := 1.0
const LEVEL_DECK_Y := 1.4
const CRASH_ROLL_DEG := 4.0
const CRASH_PITCH_DEG := 3.0
## Cargo ramp: hinged just under the deck at the aft wall. Open, it slopes down to the ground.
const RAMP_HINGE_Y := -0.1
const RAMP_LENGTH := 3.0
const RAMP_OPEN_DEG := -118.0

# Materials from the Kestrel PBR sets (assets/textures/kestrel): set, metres per repeat, tint.
const PBR := {
	"hull": ["kestrel_ivory_hull", 4.0, Color.WHITE],
	"nacelle": ["kestrel_engine_nacelle", 3.0, Color(1.35, 1.35, 1.4)],
	"frame": ["kestrel_canopy_frame", 1.5, Color(0.55, 0.57, 0.6)],
	"deck": ["kestrel_interior_floor_grating", 1.6, Color.WHITE],
	"panel": ["kestrel_interior_wall_panels", 2.4, Color(0.95, 0.93, 0.88)],
}

const PALETTE := {
	"hull": Color("e9e1cc"),
	"oxide": Color("c4622d"),
	"panel": Color("e3dccb"),
	"deck": Color("2e3236"),
	"metal": Color("3a3f43"),
	"metal_dark": Color("24282b"),
	"fabric": Color("5a4a3c"),
	"crate": Color("6b6a52"),
	"salvage": Color("7d8c84"),
	"bare_metal": Color("9aa0a3"),
	"void": Color("0b0c0d"),
}

const AUX_LIGHTS := [
	Vector3(14.0, 3.0, 11.0), Vector3(14.0, 3.0, 15.0), Vector3(20.0, 3.0, 11.0), Vector3(20.0, 3.0, 15.0),
	Vector3(9.7, 2.4, 10.6), Vector3(9.7, 2.4, 15.4), Vector3(9.6, 3.4, 13.0), Vector3(6.0, 3.4, 13.0),
	Vector3(25.5, 2.8, 13.0), Vector3(28.5, 2.8, 13.0), Vector3(26.2, 1.2, 9.7), Vector3(26.2, 1.2, 16.3),
]
## Lamps that keep their shadows on Medium: the first four AUX_LIGHTS, over the workshop.
const SHADOW_LAMPS := 4
## The aux power-up: the emergency lights drop out, then the lamps strike one by one outward from
## the aux bay between LAMPS_FROM and LAMPS_TO seconds, and the cabin warms. Matches aux_restart.
const POWER_UP_TIME := 2.9
const LAMPS_FROM := 0.9
const LAMPS_TO := 2.4
const AUX_ENERGY := 0.8
const WARM_AMBIENT := Color(0.32, 0.25, 0.17)
const DARK_AMBIENT := Color(0.09, 0.11, 0.14)
const EMERGENCY_LIGHTS := [
	Vector3(12.0, 3.0, 13.0), Vector3(23.0, 3.0, 13.0), Vector3(9.6, 3.4, 13.0), Vector3(27.0, 2.8, 13.0),
]

# Wings sit through the engine pods at mid-hull, as on the model sheet: 20 m span.
const WING_Y := [1.75, 2.15]
const WING_OUTLINE := [
	Vector2(13.5, 8.8), Vector2(21.8, 3.0), Vector2(24.4, 3.0), Vector2(26.0, 6.5), Vector2(26.0, 8.8),
]
const PORT_WING_ROOT := [Vector2(13.5, 8.8), Vector2(18.94, 5.0), Vector2(25.31, 5.0), Vector2(26.0, 6.5), Vector2(26.0, 8.8)]
const PORT_WING_TIP := [Vector2(18.94, 5.0), Vector2(21.8, 3.0), Vector2(24.4, 3.0), Vector2(25.31, 5.0)]
const PORT_WING_BROKEN := [
	Vector2(13.5, 8.8), Vector2(18.94, 5.0), Vector2(20.2, 5.5), Vector2(21.3, 4.6), Vector2(22.6, 5.6),
	Vector2(23.8, 4.8), Vector2(25.31, 5.0), Vector2(26.0, 6.5), Vector2(26.0, 8.8),
]
# Oxide panels near each wing tip (plan view on the sheet).
const WING_OXIDE := [Vector2(21.3, 4.6), Vector2(22.3, 3.5), Vector2(24.0, 3.5), Vector2(24.4, 4.6)]
const POD_Z := [7.6, 18.4]
const POD_AFT := 33.0

var layout: Dictionary = {}
var repairs: Dictionary = {}
var interact_points: Dictionary = {}

var _length := 33.0
var _centre_z := 13.0
## Current exhaust power (see set_engine_power).
var engine_power := 0.0
var _exhausts: Array[CPUParticles3D] = []
var _mats: Dictionary = {}
var _aux_lights: Array[OmniLight3D] = []
var _emergency_lights: Array[OmniLight3D] = []
var _lamps: Array[MeshInstance3D] = []
var _screens: Array[MeshInstance3D] = []
var _interior_probes: Array[ReflectionProbe] = []
var _pose_tween: Tween
## True while the staged aux power-up plays.
var powering_up := false
var _power_tween: Tween
var _animate_next := false
var _ramp_hinge: Node3D
var _ramp_tween: Tween
## The wing's point-defence turret (live only while the wing is repaired).
var turret: PointDefense
## The pre-crash ship: no soot. Set before adding to the tree, or call set_pristine.
var pristine := false


func _ready() -> void:
	add_to_group("kestrel")
	rebuild()


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cancel_power_up()
	repairs.clear()
	interact_points.clear()
	_aux_lights.clear()
	_emergency_lights.clear()
	_lamps.clear()
	_screens.clear()
	layout = _load_layout()
	if layout.is_empty():
		return
	_length = layout["length"]
	_centre_z = layout["centreline_z"]
	_build_shell()
	_build_floors()
	_build_stairs()
	_build_door_steps()
	_build_fixtures()
	_build_exterior()
	_build_lighting()
	_batch_static()
	_build_repairs()
	_apply_aux(is_repaired("aux_power"))
	_apply_pose(is_repaired("landing_gear"), false)
	_apply_ramp(is_repaired("landing_gear"), false)


# --- Public API ---------------------------------------------------------------------------

func plan(x: float, y: float, z: float) -> Vector3:
	return Vector3(x - _length * 0.5, y, z - _centre_z)


## True when a world position is inside one of Kestrel's rooms.
func is_inside(world: Vector3) -> bool:
	if layout.is_empty():
		return false
	var l := to_local(world)
	var x := l.x + _length * 0.5
	var z := l.z + _centre_z
	for r in layout["rooms"]:
		if x >= r["x"][0] and x <= r["x"][1] and z >= r["z"][0] and z <= r["z"][1] and l.y >= float(r["floor"]) - 0.6 and l.y <= float(r["ceiling"]):
			return true
	return false


func set_pristine(on: bool) -> void:
	pristine = on
	var soot := get_node_or_null("Exterior/KestrelScorch")
	if soot:
		soot.visible = not on


func is_repaired(id: String) -> bool:
	return repairs.has(id) and (repairs[id] as Repairable).repaired


## Pass animate to stage the change for the player (the aux power-up); loads and debug toggles
## apply it at once.
func set_repaired(id: String, value: bool, animate := false) -> void:
	if repairs.has(id):
		_animate_next = animate
		(repairs[id] as Repairable).repaired = value
		_animate_next = false


func play_repair(id: String) -> void:
	if repairs.has(id):
		(repairs[id] as Repairable).play_repair()


func toggle_repair(id: String) -> void:
	set_repaired(id, not is_repaired(id))


# --- Layout -------------------------------------------------------------------------------

func _load_layout() -> Dictionary:
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		push_error("Kestrel: cannot open %s" % LAYOUT_PATH)
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Kestrel: %s is not valid JSON" % LAYOUT_PATH)
		return {}
	return data


## Hull and interior walls are one CSG solid: room volumes grown by half a wall are unioned,
## then the same volumes shrunk by half a wall are cut out, which leaves shared walls between
## neighbouring rooms. Openings are cut last.
func _build_shell() -> void:
	var shell := CSGCombiner3D.new()
	shell.name = "Shell"
	shell.use_collision = true
	add_child(shell)
	var t: float = layout["wall"] * 0.5
	for r in layout["rooms"]:
		_csg(shell, [r["x"][0] - t, r["x"][1] + t], [-0.2, r["ceiling"] + 0.2], [r["z"][0] - t, r["z"][1] + t], "hull")
	for r in layout["rooms"]:
		_csg(shell, [r["x"][0] + t, r["x"][1] - t], [r["floor"], r["ceiling"]], [r["z"][0] + t, r["z"][1] - t], "panel", true)
	for o in layout["openings"]:
		_csg(shell, o["x"], o["y"], o["z"], "panel", true)


func _build_floors() -> void:
	var t: float = layout["wall"] * 0.5
	for r in layout["rooms"]:
		var plate := _box(self, [r["x"][0] + t, r["x"][1] - t], [r["floor"], r["floor"] + 0.02], [r["z"][0] + t, r["z"][1] - t], "deck", false)
		plate.name = "Floor_%s" % r["id"]
	# Dev overlay: the 5 m circle the third-person camera needs to swing freely in the workshop.
	var ring := MeshInstance3D.new()
	ring.name = "CameraClearZone"
	var torus := TorusMesh.new()
	torus.inner_radius = 2.42
	torus.outer_radius = 2.5
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.1, 1.0)
	ring.position = plan(16.6, 0.03, 13.0)
	ring.material_override = _mat("camera_ring")
	add_child(ring)


func _build_stairs() -> void:
	var s: Dictionary = layout["stairs"]
	var top_x: float = s["x"][0]
	var bottom_x: float = s["x"][1]
	var steps := int(s["steps"])
	var rise: float = s["rise"]
	var run := (bottom_x - top_x) / steps
	for i in steps:
		_box(self, [bottom_x - (i + 1) * run, bottom_x - i * run], [0.0, (i + 1) * rise / steps], s["z"], "metal", false)
	var mid_z: float = (s["z"][0] + s["z"][1]) * 0.5
	_ramp(plan(bottom_x, 0.0, mid_z), plan(top_x, rise, mid_z), s["z"][1] - s["z"][0])


func _build_door_steps() -> void:
	var s: Dictionary = layout["door_steps"]
	var z0: float = s["z"][0]
	var z1: float = s["z"][1]
	var drop: float = s["drop"]
	var steps := int(s["steps"])
	var run := (z1 - z0) / steps
	for i in steps:
		var top := -drop * float(i + 1) / float(steps + 1)
		_box(self, s["x"], [-drop - 0.6, top], [z0 + i * run, z0 + (i + 1) * run], "metal", false)
	for rail_x in [s["x"][0], s["x"][1]]:
		_rot(_box(self, [rail_x - 0.03, rail_x + 0.03], [-drop + 0.9, 0.95], [z0, z1], "oxide", false), Vector3(-atan2(drop, z1 - z0) * 0.9, 0.0, 0.0))
	var mid_x: float = (s["x"][0] + s["x"][1]) * 0.5
	_ramp(plan(mid_x, 0.0, z0), plan(mid_x, -drop - 0.4, z1 + 0.7), s["x"][1] - s["x"][0])


func _build_fixtures() -> void:
	for f in layout["fixtures"]:
		var node := _box(self, f["x"], f["y"], f["z"], f["mat"])
		node.name = f["id"]
	for s in layout["screens"]:
		var screen := _box(self, s["x"], s["y"], s["z"], "screen_off", false) as MeshInstance3D
		screen.name = s["id"]
		_screens.append(screen)


func _build_exterior() -> void:
	var ext := Node3D.new()
	ext.name = "Exterior"
	add_child(ext)
	var stbd_wing: Array = []
	for pt in WING_OUTLINE:
		stbd_wing.append(Vector2(pt.x, 26.0 - pt.y))
	_wing(ext, stbd_wing, "hull")
	var stbd_oxide: Array = []
	for pt in WING_OXIDE:
		stbd_oxide.append(Vector2(pt.x, 26.0 - pt.y))
	_wing(ext, stbd_oxide, "oxide", WING_Y[1] - 0.06, WING_Y[1] + 0.025)
	# The modelled shell (blender/build_kestrel.py): faceted hull, canopy frame, fin, vents.
	var hull := _skin(ext, "kestrel_hull")
	_skin(ext, "kestrel_scorch").visible = not pristine
	var body := StaticBody3D.new()
	body.name = "HullCollision"
	for m in hull.find_children("*", "MeshInstance3D", true, false):
		if String(m.name).begins_with("hull"):
			var shape := CollisionShape3D.new()
			shape.shape = (m as MeshInstance3D).mesh.create_trimesh_shape()
			shape.transform = (m as Node3D).transform
			body.add_child(shape)
	ext.add_child(body)
	_nacelle(ext, POD_Z[1], "nacelle")
	# Jambs that close the gap between the shell and the rooms at the side door and stern ramp.
	var door: Array = layout["door_steps"]["x"]
	for x in [[door[0] - 0.12, door[0] - 0.02], [door[1] + 0.02, door[1] + 0.12]]:
		_box(ext, x, [-0.6, 2.5], [17.1, 17.42], "metal_dark", false)
	_box(ext, [door[0] - 0.12, door[1] + 0.12], [2.42, 2.52], [17.1, 17.42], "metal_dark", false)
	for z in [[10.6, 10.7], [15.3, 15.4]]:
		_box(ext, [30.1, 30.42], [-0.25, 3.05], z, "metal_dark", false)
	_box(ext, [30.1, 30.42], [2.95, 3.05], [10.6, 15.4], "metal_dark", false)
	# Aft ramp, jammed shut until the landing gear is fixed. It swings down on a hinge at deck level.
	_ramp_hinge = Node3D.new()
	_ramp_hinge.name = "CargoRamp"
	_ramp_hinge.position = plan(30.2, RAMP_HINGE_Y, 13.0)
	add_child(_ramp_hinge)
	var door_panel := _box(_ramp_hinge, [30.1, 30.3], [RAMP_HINGE_Y, RAMP_HINGE_Y + RAMP_LENGTH], [10.8, 15.2], "metal")
	door_panel.position -= _ramp_hinge.position
	for i in 4:
		var band := _box(_ramp_hinge, [30.3, 30.33], [0.3 + i * 0.6, 0.5 + i * 0.6], [10.9, 15.1], "oxide", false)
		band.position -= _ramp_hinge.position


func _build_lighting() -> void:
	for pos in AUX_LIGHTS:
		_aux_lights.append(_omni(pos, Color("ffb24d"), 0.8, 6.0))
		var lamp := _box(self, [pos.x - 0.4, pos.x + 0.4], [pos.y + 0.1, pos.y + 0.16], [pos.z - 0.1, pos.z + 0.1], "metal_dark", false) as MeshInstance3D
		_lamps.append(lamp)
	for pos in EMERGENCY_LIGHTS:
		_emergency_lights.append(_omni(pos, Color("ff3b2e"), 0.5, 5.0))
	# Keeps the sky's ambient light from flooding the interior, so the lights do the work. One
	# probe per room, fitted inside its walls, so the hull's outside faces stay daylit.
	for room in layout["rooms"]:
		var probe := ReflectionProbe.new()
		probe.name = "InteriorAmbient_%s" % room["id"]
		var x: Array = room["x"]
		var z: Array = room["z"]
		var y0 := float(room["floor"])
		var y1 := float(room["ceiling"])
		probe.size = Vector3(x[1] - x[0] - 0.02, y1 - y0 + 0.4, z[1] - z[0] - 0.02)
		probe.position = plan((x[0] + x[1]) * 0.5, (y0 + y1) * 0.5, (z[0] + z[1]) * 0.5)
		probe.interior = true
		probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
		probe.blend_distance = 0.3
		add_child(probe)
		_interior_probes.append(probe)
		# Sounds inside ring off the room's walls.
		AudioZones.reverb_area(self, probe.size, probe.position, 0.55, String(room["id"]))


# --- Repairs ------------------------------------------------------------------------------

func _build_repairs() -> void:
	var root := Node3D.new()
	root.name = "Repairs"
	add_child(root)
	for id in REPAIR_ORDER:
		var part := Repairable.new()
		part.name = id.to_pascal_case()
		part.repair_id = id
		part.display_name = REPAIR_NAMES[id]
		var damaged := Node3D.new()
		damaged.name = "Damaged"
		var fixed := Node3D.new()
		fixed.name = "Repaired"
		part.add_child(damaged)
		part.add_child(fixed)
		root.add_child(part)
		call("_build_%s" % id, damaged, fixed)
		part.apply_state()
		part.state_changed.connect(_on_repair_state_changed.bind(id))
		repairs[id] = part
	for id in layout["interact"]:
		var p: Array = layout["interact"][id]
		interact_points[id] = plan(p[0], p[1], p[2])


func _on_repair_state_changed(fixed: bool, id: String) -> void:
	match id:
		"aux_power":
			if fixed and _animate_next and not Engine.is_editor_hint():
				power_up()
			else:
				_cancel_power_up()
				_apply_aux(fixed)
		"landing_gear":
			_apply_pose(fixed, true)
			_apply_ramp(fixed, true)
	repair_changed.emit(id, fixed)


func _apply_aux(on: bool) -> void:
	for light in _aux_lights:
		light.visible = on
	for light in _emergency_lights:
		light.visible = not on
	for lamp in _lamps:
		lamp.material_override = _mat("amber_glow" if on else "metal_dark")
	for screen in _screens:
		screen.material_override = _screen_material() if on else _mat("screen_off")
	for light in _aux_lights:
		light.light_energy = AUX_ENERGY
	for probe in _interior_probes:
		probe.ambient_color = WARM_AMBIENT if on else DARK_AMBIENT
		probe.ambient_color_energy = 0.8 if on else 0.6


## The payoff for fitting the aux cell. The emergency circuit stutters and drops out, a beat of
## darkness, then the lamps strike one by one outward from the aux bay, each with a flicker and
## a surge, the screens wake and the cabin warms. Ends exactly in the _apply_aux(true) state.
func power_up() -> void:
	_cancel_power_up()
	_apply_aux(false)
	powering_up = true
	var bay: Vector3 = (repairs["aux_power"] as Node3D).global_position if repairs.has("aux_power") else global_position
	Sfx.play("aux_restart", bay, 0.0, 0.0)
	Sfx.duck(-12.0, POWER_UP_TIME)
	var tw := create_tween().set_parallel(true)
	_power_tween = tw
	for light in _emergency_lights:
		tw.tween_callback(light.hide).set_delay(0.06)
		tw.tween_callback(light.show).set_delay(0.14)
		tw.tween_callback(light.hide).set_delay(0.3)
	for probe in _interior_probes:
		tw.tween_property(probe, "ambient_color", Color(0.03, 0.035, 0.05), 0.35).set_delay(0.06)
		tw.tween_property(probe, "ambient_color", WARM_AMBIENT, LAMPS_TO - LAMPS_FROM + 0.4).set_delay(LAMPS_FROM)
		tw.tween_property(probe, "ambient_color_energy", 0.8, LAMPS_TO - LAMPS_FROM + 0.4).set_delay(LAMPS_FROM)
	var order: Array = range(_aux_lights.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return _aux_lights[a].global_position.distance_squared_to(bay) < _aux_lights[b].global_position.distance_squared_to(bay))
	for k in order.size():
		var i: int = order[k]
		var at := LAMPS_FROM + (LAMPS_TO - LAMPS_FROM) * float(k) / float(maxi(1, order.size() - 1))
		tw.tween_callback(_strike.bind(i, true, true)).set_delay(at)
		tw.tween_callback(_strike.bind(i, false, false)).set_delay(at + 0.06)
		tw.tween_callback(_strike.bind(i, true, false)).set_delay(at + 0.15)
		tw.tween_property(_aux_lights[i], "light_energy", AUX_ENERGY, 0.6).from(AUX_ENERGY * 1.8).set_delay(at + 0.15)
	for k in _screens.size():
		tw.tween_callback(_wake_screen.bind(k)).set_delay(minf(LAMPS_TO - 0.2 + 0.12 * k, POWER_UP_TIME - 0.05))
	tw.tween_callback(_finish_power_up).set_delay(POWER_UP_TIME)


func _strike(i: int, on: bool, loud: bool) -> void:
	_aux_lights[i].visible = on
	_lamps[i].material_override = _mat("amber_glow" if on else "metal_dark")
	if loud:
		Sfx.play("lamp_strike", _aux_lights[i].global_position, -6.0)


func _wake_screen(i: int) -> void:
	_screens[i].material_override = _screen_material()


func _finish_power_up() -> void:
	_power_tween = null
	powering_up = false
	_apply_aux(true)
	power_up_finished.emit()


func _cancel_power_up() -> void:
	if _power_tween and _power_tween.is_valid():
		_power_tween.kill()
	_power_tween = null
	powering_up = false


func _apply_pose(level: bool, animate: bool) -> void:
	var target_rot := Vector3.ZERO if level else Vector3(deg_to_rad(CRASH_ROLL_DEG), 0.0, deg_to_rad(CRASH_PITCH_DEG))
	var target_y := LEVEL_DECK_Y if level else CRASH_DECK_Y
	if _pose_tween:
		_pose_tween.kill()
	if not animate or not is_inside_tree():
		rotation = target_rot
		position.y = target_y
		return
	_pose_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pose_tween.tween_property(self, "rotation", target_rot, 3.0)
	_pose_tween.tween_property(self, "position:y", target_y, 3.0)


## Ground-level points around the hull that besieging wildlife goes for (local space). None under
## the nose: it's buried in the ploughed berm, and wildlife that picked it got stuck short of it.
func hull_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in [Vector2(14.0, 8.0), Vector2(22.0, 8.0), Vector2(16.0, 18.0), Vector2(22.0, 18.0), Vector2(31.5, 13.0), Vector2(8.0, 7.5), Vector2(8.0, 18.5)]:
		out.append(plan(p.x, -0.9, p.y))
	return out


## Jumps the ship's pose and ramp to match the current gear state (used after loading a save).
func snap_pose() -> void:
	_apply_pose(is_repaired("landing_gear"), false)
	_apply_ramp(is_repaired("landing_gear"), false)


func ramp_open() -> bool:
	return _ramp_hinge != null and absf(_ramp_hinge.rotation.z - deg_to_rad(RAMP_OPEN_DEG)) < 0.01


func _apply_ramp(open: bool, animate: bool) -> void:
	if _ramp_hinge == null:
		return
	var target := deg_to_rad(RAMP_OPEN_DEG) if open else 0.0
	if _ramp_tween:
		_ramp_tween.kill()
	if not animate or not is_inside_tree():
		_ramp_hinge.rotation.z = target
		return
	_ramp_tween = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_ramp_tween.tween_interval(1.0)
	_ramp_tween.tween_property(_ramp_hinge, "rotation:z", target, 2.0)


func _build_aux_power(damaged: Node3D, fixed: Node3D) -> void:
	_box(damaged, [8.2, 9.6], [0.0, 1.4], [15.6, 16.7], "metal_dark")
	_box(damaged, [9.58, 9.64], [0.5, 1.1], [15.8, 16.5], "void", false)
	_rot(_box(damaged, [9.6, 10.7], [0.0, 0.05], [15.9, 16.0], "oxide", false), Vector3(0.0, 0.3, 0.0))
	_box(fixed, [8.2, 9.6], [0.0, 1.4], [15.6, 16.7], "metal")
	_box(fixed, [9.6, 9.66], [0.3, 1.3], [15.7, 16.6], "salvage", false)
	_box(fixed, [9.64, 9.7], [0.6, 1.0], [15.9, 16.4], "amber_glow", false)
	_box(fixed, [8.5, 8.7], [1.4, 2.6], [16.3, 16.5], "salvage", false)


func _build_cooling(damaged: Node3D, fixed: Node3D) -> void:
	for seg in [[12.5, 15.4], [17.1, 19.0], [21.2, 23.3]]:
		for y in [2.55, 2.85]:
			_cyl(damaged, Vector3((seg[0] + seg[1]) * 0.5, y, 16.72), 0.08, seg[1] - seg[0], "x", "metal")
	_rot(_cyl(damaged, Vector3(16.2, 2.0, 16.6), 0.08, 1.6, "y", "metal"), Vector3(0.0, 0.0, 0.5))
	_box(damaged, [21.5, 22.5], [0.0, 0.03], [13.0, 14.0], "void", false)
	_rot(_box(damaged, [21.5, 22.5], [0.0, 1.0], [12.94, 13.0], "metal", false), Vector3(0.3, 0.0, 0.0))
	damaged.add_child(_coolant_leak(plan(16.2, 2.7, 16.6)))
	for y in [2.55, 2.85]:
		_cyl(fixed, Vector3(17.9, y, 16.72), 0.08, 10.8, "x", "salvage")
	var bx := 12.8
	while bx < 23.3:
		_box(fixed, [bx - 0.05, bx + 0.05], [2.4, 3.0], [16.6, 16.9], "metal_dark", false)
		# Bolted flanges where the salvaged lengths join, beside each bracket.
		for y in [2.55, 2.85]:
			_cyl(fixed, Vector3(bx + 0.14, y, 16.72), 0.115, 0.06, "x", "metal_dark")
		bx += 1.8
	_box(fixed, [21.5, 22.5], [0.0, 0.035], [13.0, 14.0], "salvage", false)


## Coolant venting from the cracked manifold: a visible fault that stops once it's repaired.
func _coolant_leak(at: Vector3) -> CPUParticles3D:
	var leak := CPUParticles3D.new()
	leak.position = at
	leak.amount = 16
	leak.lifetime = 1.2
	leak.direction = Vector3(0.0, -0.3, -1.0)
	leak.spread = 18.0
	leak.gravity = Vector3(0.0, 0.4, 0.0)
	leak.initial_velocity_min = 1.0
	leak.initial_velocity_max = 1.8
	leak.scale_amount_min = 0.2
	leak.scale_amount_max = 0.5
	var puff := QuadMesh.new()
	puff.size = Vector2(0.6, 0.6)
	puff.material = _puff_material(Color(0.75, 0.9, 1.0, 0.4))
	leak.mesh = puff
	return leak


## Soft round puff for steam particles, so they don't read as flat squares.
func _puff_material(color: Color) -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = texture
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	return m


func _build_canopy(damaged: Node3D, fixed: Node3D) -> void:
	_skin(damaged, "kestrel_canopy", "canopy_cracked")
	_skin(fixed, "kestrel_canopy", "canopy_glass")
	_box(damaged, [3.57, 3.63], [2.0, 3.3], [11.3, 14.7], "glass_cracked")
	_box(damaged, [4.2, 7.4], [2.3, 3.3], [15.37, 15.43], "glass_cracked")
	for angle in [0.6, -0.6]:
		_rot(_box(damaged, [3.66, 3.68], [2.6, 2.7], [11.6, 14.4], "oxide", false), Vector3(angle, 0.0, 0.0))
	_rot(_box(damaged, [4.6, 5.8], [2.2, 2.28], [10.55, 10.65], "metal", false), Vector3(0.0, 0.0, 0.4))
	_box(fixed, [3.57, 3.63], [2.0, 3.3], [11.3, 14.7], "glass")
	_box(fixed, [4.2, 7.4], [2.3, 3.3], [10.57, 10.63], "glass")
	_box(fixed, [4.2, 7.4], [2.3, 3.3], [15.37, 15.43], "glass")
	for z in [12.4, 13.6]:
		_box(fixed, [3.5, 3.7], [2.0, 3.3], [z - 0.04, z + 0.04], "salvage", false)
	for z in [10.6, 15.4]:
		_box(fixed, [5.76, 5.84], [2.3, 3.3], [z - 0.06, z + 0.06], "salvage", false)


func _build_landing_gear(damaged: Node3D, fixed: Node3D) -> void:
	for leg in [Vector2(18.0, 10.4), Vector2(18.0, 15.6), Vector2(2.6, 13.0)]:
		var x: float = leg.x
		var z: float = leg.y
		# The strut's collision stays a box; the look is the modelled leg (blender/build_props.py).
		var strut := _box(fixed, [x - 0.12, x + 0.12], [-1.0, -0.2], [z - 0.12, z + 0.12], "salvage")
		for mesh in strut.find_children("*", "MeshInstance3D", false, false):
			mesh.visible = false
		Rig.spawn("prop_gear", fixed).position = plan(x, 0.0, z)
		Rig.spawn("prop_gear_broken", damaged).position = plan(x, 0.0, z)


func _build_wing(damaged: Node3D, fixed: Node3D) -> void:
	_wing(damaged, PORT_WING_BROKEN, "hull")
	_box(damaged, [21.5, 21.7], [1.85, 2.05], [4.2, 5.2], "metal_dark", false)
	# The torn tip lies on the ground under the wing.
	var tip := _wing(damaged, PORT_WING_TIP, "hull", -1.05, -0.7)
	tip.position += Vector3(-0.8, 0.0, -1.5)
	var tip_oxide := _wing(damaged, WING_OXIDE, "oxide", -0.78, -0.68)
	tip_oxide.position = tip.position
	_wing(fixed, PORT_WING_ROOT, "hull")
	_wing(fixed, PORT_WING_TIP, "salvage")
	_wing(fixed, WING_OXIDE, "oxide", WING_Y[1] - 0.06, WING_Y[1] + 0.025)
	_box(fixed, [18.9, 25.35], [1.82, 2.2], [4.9, 5.1], "metal_dark", false)
	_sphere(fixed, Vector3(23.1, 1.95, 2.95), 0.1, "nav_red")
	# Point-defence turret on the wing root, salvaged from the dropship.
	_cyl(fixed, Vector3(21.5, 2.3, 5.8), 0.45, 0.3, "y", "metal_dark")
	turret = PointDefense.new()
	turret.name = "PointDefense"
	turret.position = plan(21.5, 2.7, 5.8)
	fixed.add_child(turret)


func _build_engine(damaged: Node3D, fixed: Node3D) -> void:
	# The port pod tore off in the crash: a stub at the wing and the pod's tail on the ground.
	_cyl(damaged, Vector3(18.8, 1.9, 7.6), 1.0, 1.6, "x", "metal_dark")
	_box(damaged, [19.55, 19.65], [1.0, 2.8], [6.7, 8.5], "void", false)
	# A thin wisp still curls out of the torn mount: the drive is cold, the wiring isn't.
	var wisp := Vfx.smoke(damaged, plan(19.8, 2.2, 7.6))
	wisp.amount = 26
	wisp.lifetime = 4.0
	wisp.initial_velocity_min = 0.3
	wisp.initial_velocity_max = 0.7
	wisp.gravity = Vector3(0.4, 0.5, 0.0)
	wisp.scale_amount_min = 0.5
	wisp.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([Color(0.2, 0.2, 0.2, 0.0), Color(0.22, 0.22, 0.22, 0.45), Color(0.45, 0.45, 0.45, 0.0)])
	wisp.color_ramp = fade
	var wreck := _cyl(damaged, Vector3(29.5, -0.55, 3.2), 0.95, 6.0, "x", "nacelle")
	wreck.rotation = Vector3(0.0, 0.32, PI * 0.5 + 0.06)
	for i in 4:
		_rot(_box(damaged, [21.0 + i * 1.3, 21.6 + i * 1.3], [-0.95, -0.65], [5.0 - i * 0.5, 5.6 - i * 0.5], "metal", false), Vector3(0.0, i * 0.7, 0.0))
	_nacelle(fixed, POD_Z[0], "bare_metal")
	_cyl(fixed, Vector3(19.0, 1.9, POD_Z[0]), 1.08, 0.25, "x", "oxide")


func _build_navigation(damaged: Node3D, fixed: Node3D) -> void:
	# Modelled mast and dish (blender/build_props.py): torn down by the crash, then re-stepped.
	var down := Rig.spawn("prop_mast_down", damaged)
	down.position = plan(19.5, 3.92, 13.0)
	down.rotation.y = 0.4
	Rig.spawn("prop_mast", fixed).position = plan(19.5, 3.92, 13.0)
	_sphere(fixed, Vector3(19.5, 6.05, 12.85), 0.08, "nav_red")
	_sphere(fixed, Vector3(19.5, 6.05, 13.15), 0.08, "nav_green")
	_sphere(fixed, Vector3(23.1, 1.95, 23.05), 0.1, "nav_green")
	var beacon := _omni(Vector3(19.5, 6.17, 13.0), Color("ff4030"), 0.8, 4.0)
	beacon.reparent(fixed)


# --- Geometry helpers ---------------------------------------------------------------------

func _csg(parent: Node, x: Array, y: Array, z: Array, mat_id: String, subtract := false) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = Vector3(x[1] - x[0], y[1] - y[0], z[1] - z[0])
	b.position = plan((x[0] + x[1]) * 0.5, (y[0] + y[1]) * 0.5, (z[0] + z[1]) * 0.5)
	b.material = _mat(mat_id)
	if subtract:
		b.operation = CSGShape3D.OPERATION_SUBTRACTION
	parent.add_child(b)
	return b


## Axis-aligned box from plan ranges [min, max], with a static collider unless collide is false.
func _box(parent: Node, x: Array, y: Array, z: Array, mat_id: String, collide := true) -> Node3D:
	var size := Vector3(x[1] - x[0], y[1] - y[0], z[1] - z[0])
	var centre := plan((x[0] + x[1]) * 0.5, (y[0] + y[1]) * 0.5, (z[0] + z[1]) * 0.5)
	var mesh := MeshInstance3D.new()
	mesh.mesh = Bevel.box(size)
	mesh.material_override = _mat(mat_id)
	if not collide:
		mesh.position = centre
		parent.add_child(mesh)
		return mesh
	var body := StaticBody3D.new()
	body.position = centre
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(mesh)
	body.add_child(shape)
	parent.add_child(body)
	return body


## Omni shadows are the interior's biggest cost (each is several extra passes). High: every
## lamp, full cube maps. Medium: the four workshop lamps and the emergency lights, dual-paraboloid
## (two passes each). Low: none.
func apply_graphics(level: int) -> void:
	var high := level == Game.GRAPHICS_HIGH
	var low := level == Game.GRAPHICS_LOW
	for i in _aux_lights.size():
		_aux_lights[i].shadow_enabled = high or (not low and i < SHADOW_LAMPS)
		_aux_lights[i].omni_shadow_mode = OmniLight3D.SHADOW_CUBE if high else OmniLight3D.SHADOW_DUAL_PARABOLOID
	for light in _emergency_lights:
		light.shadow_enabled = not low
		light.omni_shadow_mode = OmniLight3D.SHADOW_CUBE if high else OmniLight3D.SHADOW_DUAL_PARABOLOID


## Folds the hull's fixed parts (shell, decks, stairs, fixtures, trim) into one mesh with a
## surface per material: several hundred boxes become a dozen or so draw calls. Lamps and screens
## (their materials change with aux power) and everything under a moving or swapping node
## (repairs, the ramp) stay separate. Colliders are untouched.
func _batch_static() -> void:
	var keep := {}
	for m in _lamps:
		keep[m] = true
	for m in _screens:
		keep[m] = true
	var tools := {}
	var order: Array = []
	var originals: Array[MeshInstance3D] = []
	for child in get_children():
		var parts: Array = []
		var base := Transform3D.IDENTITY
		if child is MeshInstance3D:
			parts = [child]
		elif child is StaticBody3D:
			base = (child as Node3D).transform
			parts = child.get_children().filter(func(c): return c is MeshInstance3D)
		for m in parts:
			var mi := m as MeshInstance3D
			if keep.has(mi) or mi.get_child_count() > 0 or not mi.visible or mi.mesh == null:
				continue
			var xf: Transform3D = base * mi.transform if mi.get_parent() != self else mi.transform
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				var key := "%d/%d" % [mat.get_instance_id() if mat else 0, mi.cast_shadow]
				if not tools.has(key):
					var st := SurfaceTool.new()
					tools[key] = [st, mat]
					order.append(key)
				(tools[key][0] as SurfaceTool).append_from(mi.mesh, i, xf)
			originals.append(mi)
	if originals.size() < 2:
		return
	var mesh := ArrayMesh.new()
	for key in order:
		(tools[key][0] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, tools[key][1])
	var out := MeshInstance3D.new()
	out.name = "HullBatched"
	out.mesh = mesh
	add_child(out)
	for m in originals:
		m.get_parent().remove_child(m)
		m.free()


## Cylinder centred on a plan point, lying along "x", "y" or "z".
func _cyl(parent: Node, centre: Vector3, radius: float, length: float, axis: String, mat_id: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 20
	mesh.mesh = cyl
	mesh.material_override = _mat(mat_id)
	mesh.position = plan(centre.x, centre.y, centre.z)
	match axis:
		"x":
			mesh.rotation.z = PI * 0.5
		"z":
			mesh.rotation.x = PI * 0.5
	parent.add_child(mesh)
	return mesh


func _sphere(parent: Node, centre: Vector3, radius: float, mat_id: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	mesh.material_override = _mat(mat_id)
	mesh.position = plan(centre.x, centre.y, centre.z)
	parent.add_child(mesh)
	return mesh


## Wing panel from a plan-view outline (x, z), sitting on top of the hull at roof height.
## A wing panel from its plan outline: a plate with airfoil-tapered edges (visual only; the
## wings have never had collision).
func _wing(parent: Node, outline: Array, mat_id: String, y0: float = WING_Y[0], y1: float = WING_Y[1]) -> MeshInstance3D:
	var points := PackedVector2Array()
	for pt in outline:
		var v := plan(pt.x, 0.0, pt.y)
		points.append(Vector2(v.x, v.z))
	var mesh := MeshInstance3D.new()
	mesh.name = "WingPanel"
	mesh.mesh = Bevel.tapered_plate(points, y0, y1)
	mesh.material_override = _mat(mat_id)
	parent.add_child(mesh)
	return mesh


## Exhaust from both nacelles: 0 is off, 1 is full lift-off thrust.
func set_engine_power(power: float) -> void:
	if _exhausts.is_empty():
		for zc in POD_Z:
			_exhausts.append(Vfx.exhaust(self, plan(POD_AFT + 0.2, 1.9, zc), Vector3.RIGHT))
	for e in _exhausts:
		e.emitting = power > 0.01
		e.initial_velocity_min = 3.0 + 12.0 * power
		e.initial_velocity_max = 5.0 + 18.0 * power
		e.scale_amount_max = 0.4 + 1.2 * power
	engine_power = power


## Loads a part of the modelled skin. Meshes named oxide_* and dark_* take those materials;
## the rest take `mat_id`.
func _skin(parent: Node, part: String, mat_id := "hull") -> Node3D:
	var scene: PackedScene = load("res://assets/kestrel/%s.glb" % part)
	var node := scene.instantiate() as Node3D
	node.name = part.capitalize().replace(" ", "")
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var n := String(m.name)
		var id := mat_id
		if n.begins_with("oxide"):
			id = "oxide"
		elif n.begins_with("dark"):
			id = "metal_dark"
		elif n.begins_with("frame"):
			id = "frame"
		elif n.begins_with("decal"):
			id = "decal"
			(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(m as MeshInstance3D).material_override = _mat(id)
	parent.add_child(node)
	return node


## An engine nacelle on the line plan z = zc (the model is built on the centreline).
func _nacelle(parent: Node, zc: float, mat_id: String) -> void:
	var n := _skin(parent, "kestrel_nacelle", mat_id)
	n.position.z = zc - _centre_z


func _engine(parent: Node, zc: float, mat_id: String, length: float) -> void:
	var xc := 33.5 - length * 0.5
	_cyl(parent, Vector3(xc, 1.9, zc), 1.0, length, "x", mat_id)
	_cyl(parent, Vector3(33.5 - length - 0.02, 1.9, zc), 0.8, 0.1, "x", "void")
	_cyl(parent, Vector3(33.52, 1.9, zc), 0.75, 0.1, "x", "void")


## Invisible walkable slope over stairs so the capsule never snags on individual treads.
func _ramp(bottom: Vector3, top: Vector3, width: float) -> void:
	var d := top - bottom
	var length := d.length()
	var forward := d / length
	var across := Vector3.UP.cross(forward).normalized()
	var body := StaticBody3D.new()
	body.name = "StairRamp"
	body.transform = Transform3D(Basis(forward, forward.cross(across), -across), (bottom + top) * 0.5 + Vector3.DOWN * 0.03)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(length, 0.06, width)
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)


func _rot(node: Node3D, rot: Vector3) -> Node3D:
	node.rotation = rot
	return node


func _omni(pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = plan(pos.x, pos.y, pos.z)
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = true
	add_child(light)
	return light


## Live console readouts (shaders/screen.gdshader).
func _screen_material() -> Material:
	if not _mats.has("screen_live"):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/screen.gdshader")
		_mats["screen_live"] = m
	return _mats["screen_live"]


func _mat(id: String) -> StandardMaterial3D:
	if _mats.has(id):
		return _mats[id]
	var m := StandardMaterial3D.new()
	match id:
		"glass":
			m.albedo_color = Color(0.62, 0.78, 0.82, 0.18)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic = 0.3
		"glass_cracked":
			m.albedo_color = Color(0.85, 0.88, 0.86, 0.6)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.7
		"canopy_glass":
			m.albedo_color = Color(0.08, 0.17, 0.19, 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.06
			m.metallic = 0.6
			m.metallic_specular = 0.9
		"canopy_cracked":
			m.albedo_color = Color(0.42, 0.48, 0.48, 0.78)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.55
			m.metallic = 0.2
			Surfaces.apply_grime(m, 1.5, false)
		"decal":
			m.albedo_texture = load("res://assets/textures/kestrel/decal_atlas.png")
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.8
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"amber_glow":
			m.albedo_color = Color("f2a93b")
			m.emission_enabled = true
			m.emission = Color("f2a93b")
			m.emission_energy_multiplier = 3.0
		"screen_off":
			m.albedo_color = Color(0.04, 0.05, 0.05)
			m.roughness = 0.15
		"screen_on":
			m.albedo_color = Color("3fd1b5")
			m.emission_enabled = true
			m.emission = Color("3fd1b5")
			m.emission_energy_multiplier = 1.5
		"nav_red", "nav_green":
			var c: Color = Color("ff4030") if id == "nav_red" else Color("40ff70")
			m.albedo_color = c
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 4.0
		"camera_ring":
			m.albedo_color = Color(0.25, 0.82, 0.71, 0.6)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ when PBR.has(id) and PbrSet.exists("kestrel", PBR[id][0]):
			var spec: Array = PBR[id]
			m = PbrSet.material("kestrel", spec[0], spec[1], false, spec[2]).duplicate() as StandardMaterial3D
			if id == "nacelle":
				m.metallic = 0.55
		_:
			m.albedo_color = PALETTE.get(id, Color.MAGENTA)
			m.roughness = 0.85 if id in ["hull", "panel", "fabric", "crate", "oxide"] else 0.5
			m.metallic = 0.6 if id in ["metal", "metal_dark", "bare_metal", "salvage"] else 0.0
			if id in ["hull", "oxide", "salvage", "bare_metal"]:
				Surfaces.apply_hull(m, 4.0, false)
			else:
				Surfaces.apply_grime(m, 3.0, false)
	_mats[id] = m
	return m
