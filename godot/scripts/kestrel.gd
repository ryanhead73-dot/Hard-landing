@tool
class_name Kestrel
extends Node3D
## Greybox of Kestrel, generated from data/kestrel_layout.json so it always matches the deck plan.
## Plan coordinates: x = metres aft of the nose, z = metres from the port reference line
## (centreline at 13), y = metres above the main deck. plan() converts them to local space.

signal repair_changed(id: String, repaired: bool)

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

# Outer oxide stripes: [x range, y range, z range]. Each sits 0.04 m proud of the hull face.
const OXIDE_BANDS := [
	[[11.35, 23.65], [0.55, 0.85], [8.86, 8.92]],
	[[11.35, 23.65], [0.55, 0.85], [17.08, 17.14]],
	[[7.95, 11.25], [0.55, 0.85], [9.06, 9.12]],
	[[7.95, 11.25], [0.55, 0.85], [16.88, 16.94]],
	[[28.65, 30.05], [0.55, 0.85], [10.06, 10.12]],
	[[28.65, 30.05], [0.55, 0.85], [15.88, 15.94]],
	[[23.95, 28.55], [0.55, 0.85], [9.06, 9.12]],
	[[23.95, 28.55], [0.55, 0.85], [16.88, 16.94]],
	[[3.55, 8.05], [1.6, 1.9], [10.46, 10.52]],
	[[3.55, 8.05], [1.6, 1.9], [15.48, 15.54]],
]

const AUX_LIGHTS := [
	Vector3(14.0, 3.0, 11.0), Vector3(14.0, 3.0, 15.0), Vector3(20.0, 3.0, 11.0), Vector3(20.0, 3.0, 15.0),
	Vector3(9.7, 2.4, 10.6), Vector3(9.7, 2.4, 15.4), Vector3(9.6, 3.4, 13.0), Vector3(6.0, 3.4, 13.0),
	Vector3(25.5, 2.8, 13.0), Vector3(28.5, 2.8, 13.0), Vector3(26.2, 1.2, 9.7), Vector3(26.2, 1.2, 16.3),
]
const EMERGENCY_LIGHTS := [
	Vector3(12.0, 3.0, 13.0), Vector3(23.0, 3.0, 13.0), Vector3(9.6, 3.4, 13.0), Vector3(27.0, 2.8, 13.0),
]

const WING_OUTLINE := [
	Vector2(13.4, 8.9), Vector2(15.5, 3.5), Vector2(16.6, 0.6), Vector2(20.0, 0.6), Vector2(21.0, 3.5), Vector2(23.5, 8.9),
]
const PORT_WING_ROOT := [Vector2(13.4, 8.9), Vector2(15.5, 3.5), Vector2(21.0, 3.5), Vector2(23.5, 8.9)]
const PORT_WING_TIP := [Vector2(15.5, 3.5), Vector2(16.6, 0.6), Vector2(20.0, 0.6), Vector2(21.0, 3.5)]
const PORT_WING_BROKEN := [
	Vector2(13.4, 8.9), Vector2(15.5, 3.5), Vector2(16.7, 3.9), Vector2(17.6, 3.1),
	Vector2(18.8, 4.2), Vector2(20.1, 3.4), Vector2(21.0, 3.5), Vector2(23.5, 8.9),
]

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
var _ramp_hinge: Node3D
var _ramp_tween: Tween
## The wing's point-defence turret (live only while the wing is repaired).
var turret: PointDefense


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
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


func is_repaired(id: String) -> bool:
	return repairs.has(id) and (repairs[id] as Repairable).repaired


func set_repaired(id: String, value: bool) -> void:
	if repairs.has(id):
		(repairs[id] as Repairable).repaired = value


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
	for band in OXIDE_BANDS:
		_csg(shell, band[0], band[1], band[2], "oxide")
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
	_box(ext, [16.6, 20.0], [3.0, 3.8], [24.9, 25.4], "oxide", false)
	# The modelled skin (blender/build_kestrel.py): arched roof, keel, nose, fins, nacelle.
	for part in ["kestrel_roof", "kestrel_keel", "kestrel_fins"]:
		_skin(ext, part)
	var nose := _skin(ext, "kestrel_nose")
	var nose_body := StaticBody3D.new()
	nose_body.name = "NoseCollision"
	var nose_shape := CollisionShape3D.new()
	for m in nose.find_children("*", "MeshInstance3D", true, false):
		if String(m.name).begins_with("nose"):
			nose_shape.shape = (m as MeshInstance3D).mesh.create_convex_shape(true, true)
			break
	nose_body.add_child(nose_shape)
	ext.add_child(nose_body)
	_nacelle(ext, 18.4, "hull")
	_box(ext, [29.6, 33.2], [1.9, 2.05], [5.4, 5.9], "hull", false)
	_box(ext, [29.6, 33.2], [1.9, 2.05], [20.1, 20.6], "hull", false)
	_box(ext, [25.0, 28.6], [1.4, 2.4], [8.4, 9.3], "metal", false)
	_box(ext, [25.0, 28.6], [1.4, 2.4], [16.7, 17.6], "metal", false)
	# Aft ramp, jammed shut until the landing gear is fixed. It swings down on a hinge at deck level.
	_ramp_hinge = Node3D.new()
	_ramp_hinge.name = "CargoRamp"
	_ramp_hinge.position = plan(30.2, RAMP_HINGE_Y, 13.0)
	add_child(_ramp_hinge)
	var door := _box(_ramp_hinge, [30.1, 30.3], [RAMP_HINGE_Y, RAMP_HINGE_Y + RAMP_LENGTH], [10.8, 15.2], "metal")
	door.position -= _ramp_hinge.position
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
		screen.material_override = _mat("screen_on" if on else "screen_off")
	for probe in _interior_probes:
		probe.ambient_color = Color(0.32, 0.25, 0.17) if on else Color(0.09, 0.11, 0.14)
		probe.ambient_color_energy = 0.8 if on else 0.6


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
		_box(fixed, [x - 0.12, x + 0.12], [-1.0, -0.2], [z - 0.12, z + 0.12], "salvage")
		_cyl(fixed, Vector3(x, -0.95, z), 0.45, 0.35, "z", "metal_dark")
		_box(fixed, [x - 0.4, x + 0.4], [-0.27, -0.2], [z - 0.4, z + 0.4], "oxide", false)
		_rot(_box(damaged, [x - 0.5, x + 0.5], [-0.45, -0.25], [z - 0.12, z + 0.12], "metal", false), Vector3(0.0, 0.0, 0.25))
		_rot(_cyl(damaged, Vector3(x + 0.6, -0.6, z + 0.2), 0.45, 0.3, "y", "metal_dark"), Vector3(0.3, 0.0, 0.0))


func _build_wing(damaged: Node3D, fixed: Node3D) -> void:
	_wing(damaged, PORT_WING_BROKEN, "hull")
	_box(damaged, [17.4, 17.6], [3.45, 3.65], [2.6, 3.8], "metal_dark", false)
	var tip := _box(damaged, [16.6, 20.2], [-1.75, -1.55], [0.8, 3.4], "hull", false)
	tip.rotation = Vector3(0.0, 0.3, 0.15)
	_rot(_box(damaged, [16.6, 20.2], [-1.6, -1.5], [0.7, 0.9], "oxide", false), Vector3(0.0, 0.3, 0.15))
	_wing(fixed, PORT_WING_ROOT, "hull")
	_wing(fixed, PORT_WING_TIP, "salvage")
	_box(fixed, [15.4, 21.1], [3.0, 3.8], [3.4, 3.6], "metal_dark", false)
	_box(fixed, [16.6, 20.0], [3.0, 3.8], [0.6, 1.1], "oxide", false)
	# Point-defence turret on the wing root, salvaged from the dropship.
	_cyl(fixed, Vector3(19.5, 4.2, 6.5), 0.45, 0.3, "y", "metal_dark")
	turret = PointDefense.new()
	turret.name = "PointDefense"
	turret.position = plan(19.5, 4.6, 6.5)
	fixed.add_child(turret)


func _build_engine(damaged: Node3D, fixed: Node3D) -> void:
	var wreck := _cyl(damaged, Vector3(30.0, 1.4, 7.4), 1.0, 7.0, "x", "metal_dark")
	wreck.rotation = Vector3(0.0, 0.08, PI * 0.5 + 0.12)
	_box(damaged, [26.2, 26.8], [0.9, 1.9], [6.9, 7.9], "void", false)
	for i in 4:
		_rot(_box(damaged, [24.0 + i * 0.9, 24.6 + i * 0.9], [-0.9, -0.6], [5.6 - i * 0.4, 6.2 - i * 0.4], "metal", false), Vector3(0.0, i * 0.7, 0.0))
	_nacelle(fixed, 7.6, "bare_metal")
	_cyl(fixed, Vector3(25.3, 1.9, 7.6), 1.05, 0.25, "x", "oxide")


func _build_navigation(damaged: Node3D, fixed: Node3D) -> void:
	_rot(_box(damaged, [26.5, 28.5], [3.7, 3.9], [12.9, 13.1], "metal", false), Vector3(0.0, 0.4, 0.0))
	_cyl(damaged, Vector3(27.5, 3.75, 13.8), 0.5, 0.06, "y", "hull")
	_box(fixed, [26.4, 26.6], [3.7, 5.7], [12.9, 13.1], "salvage", false)
	_cyl(fixed, Vector3(26.5, 5.2, 13.4), 0.5, 0.08, "z", "hull")
	_sphere(fixed, Vector3(26.5, 5.78, 12.85), 0.08, "nav_red")
	_sphere(fixed, Vector3(26.5, 5.78, 13.15), 0.08, "nav_green")
	_sphere(fixed, Vector3(18.3, 3.4, 25.45), 0.1, "nav_green")
	var beacon := _omni(Vector3(26.5, 5.9, 13.0), Color("ff4030"), 0.8, 4.0)
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
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
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
func _wing(parent: Node, outline: Array, mat_id: String) -> CSGPolygon3D:
	var poly := CSGPolygon3D.new()
	var points := PackedVector2Array()
	for pt in outline:
		var v := plan(pt.x, 0.0, pt.y)
		points.append(Vector2(v.x, -v.z))
	poly.polygon = points
	poly.depth = 0.35
	poly.rotation.x = -PI * 0.5
	poly.position.y = 3.75
	poly.material = _mat(mat_id)
	parent.add_child(poly)
	return poly


## Exhaust from both nacelles: 0 is off, 1 is full lift-off thrust.
func set_engine_power(power: float) -> void:
	if _exhausts.is_empty():
		for zc in [18.4, 7.6]:
			_exhausts.append(Vfx.exhaust(self, plan(33.7, 1.9, zc), Vector3.RIGHT))
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
		(m as MeshInstance3D).material_override = _mat("oxide" if n.begins_with("oxide") else ("metal_dark" if n.begins_with("dark") else mat_id))
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
