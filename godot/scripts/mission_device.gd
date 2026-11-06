class_name MissionDevice
extends Node3D
## A machine the player works during a mission stage: a breaker, a valve, a winch, a floodlight...
## Dormant until its stage comes up, then its lamp pulses amber; once worked it turns teal and
## plays a small motion (a lever flips, a wheel spins, a lamp lights). Local -Z faces the player's
## approach side is not assumed: the player can work it from any side within reach.

enum State { DORMANT, PENDING, DONE }

const AMBER := Color("ffb24d")
const TEAL := Color("3fd1b5")
const BODY := Color("4a4f52")
const TRIM := Color("c4622d")

var kind := "breaker"
## How fast the pending lamp pulses (a gauge reading: faster is more urgent).
var pulse_rate := 4.0
var state := State.DORMANT

var _lamp_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _moving: Node3D
var _spot: SpotLight3D
var _time := 0.0


func _ready() -> void:
	_build()
	_apply()


func _process(delta: float) -> void:
	_time += delta
	if state == State.PENDING and _lamp_mat:
		var k := 0.5 + 0.5 * sin(_time * pulse_rate)
		_lamp_mat.emission_energy_multiplier = 1.5 + 4.0 * k
		_lamp_light.light_energy = 0.4 + 0.8 * k


func set_state(value: State, animate := true) -> void:
	if state == value:
		return
	var was := state
	state = value
	_apply()
	if value == State.DONE and was != State.DONE:
		_play_done(animate)


## A search spot turned over and found empty: its lamp goes out.
func mark_empty() -> void:
	set_state(State.DONE, false)
	if _lamp_mat:
		_lamp_mat.emission = Color("2a2e30")
		_lamp_mat.emission_energy_multiplier = 0.2
		_lamp_light.visible = false


func _apply() -> void:
	if _lamp_mat == null:
		return
	match state:
		State.DORMANT:
			_lamp_mat.emission = Color("2a2e30")
			_lamp_mat.emission_energy_multiplier = 0.2
			_lamp_light.visible = false
		State.PENDING:
			_lamp_mat.emission = AMBER
			_lamp_light.light_color = AMBER
			_lamp_light.visible = true
		State.DONE:
			_lamp_mat.emission = TEAL
			_lamp_mat.emission_energy_multiplier = 2.5
			_lamp_light.light_color = TEAL
			_lamp_light.light_energy = 0.5
			_lamp_light.visible = true
	if _spot:
		_spot.visible = state == State.DONE


func _play_done(animate: bool) -> void:
	if _moving == null:
		return
	var target := _moving.rotation
	match kind:
		"breaker", "console", "keycard":
			target.x = -1.1
		"valve", "winch", "clamp":
			target.z = TAU * (1.5 if kind == "winch" else 1.0)
		"resonator", "transponder":
			target.y = PI
		_:
			return
	if not animate or not is_inside_tree():
		_moving.rotation = target
		return
	var tween := create_tween()
	tween.tween_property(_moving, "rotation", target, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Building -----------------------------------------------------------------------------

func _build() -> void:
	var body := _mat(BODY, 0.6, 0.4)
	var trim := _mat(TRIM, 0.7)
	match kind:
		"breaker", "console", "keycard":
			_box(Vector3(0.9, 1.3, 0.35), Vector3(0, 0.65, 0), body)
			_box(Vector3(0.94, 0.08, 0.39), Vector3(0, 1.32, 0), trim)
			_moving = Node3D.new()
			_moving.position = Vector3(0, 0.9, 0.2)
			add_child(_moving)
			var lever := _box(Vector3(0.08, 0.08, 0.45), Vector3(0, 0, 0.2), _mat(Color("d9d2bf"), 0.4), _moving)
			lever.rotation.x = 0.0
			_box(Vector3(0.16, 0.16, 0.12), Vector3(0, 0, 0.42), trim, _moving)
			if kind == "console":
				var screen := _box(Vector3(0.7, 0.4, 0.02), Vector3(0, 1.05, 0.19), _glow(Color("6fd8ff"), 1.5))
				screen.rotation.x = -0.2
		"valve", "clamp":
			var pipe := _cyl(0.22, 2.4, Vector3(0, 0.55, 0), _mat(Color("6b7478"), 0.4, 0.7))
			pipe.rotation.z = PI * 0.5
			_box(Vector3(0.6, 1.1, 0.6), Vector3(0, 0.55, 0), body)
			_moving = Node3D.new()
			_moving.position = Vector3(0, 1.3, 0)
			_moving.rotation.x = PI * 0.5
			add_child(_moving)
			var wheel := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.26
			torus.outer_radius = 0.34
			wheel.mesh = torus
			wheel.material_override = trim
			_moving.add_child(wheel)
			for a in 3:
				var spoke := _box(Vector3(0.6, 0.05, 0.05), Vector3.ZERO, trim, _moving)
				spoke.rotation.y = a * PI / 3.0
		"winch":
			_box(Vector3(1.2, 0.5, 0.9), Vector3(0, 0.25, 0), body)
			for x in [-0.55, 0.55]:
				_box(Vector3(0.1, 0.8, 0.5), Vector3(x, 0.8, 0), trim)
			_moving = Node3D.new()
			_moving.position = Vector3(0, 0.95, 0)
			add_child(_moving)
			var drum := _cyl(0.28, 1.0, Vector3.ZERO, _mat(Color("8c8f86"), 0.5, 0.6), _moving)
			drum.rotation.z = PI * 0.5
		"floodlight":
			_cyl(0.07, 3.2, Vector3(0, 1.6, 0), body)
			_box(Vector3(0.9, 0.25, 0.9), Vector3(0, 0.12, 0), body)
			var head := _box(Vector3(0.8, 0.45, 0.3), Vector3(0, 3.2, 0.1), trim)
			head.rotation.x = 0.5
			_spot = SpotLight3D.new()
			_spot.light_color = Color("fff1d6")
			_spot.light_energy = 6.0
			_spot.spot_range = 28.0
			_spot.spot_angle = 38.0
			_spot.shadow_enabled = true
			_spot.position = Vector3(0, 3.1, 0.3)
			_spot.rotation.x = -0.5
			add_child(_spot)
		"transponder":
			_cyl(0.05, 2.6, Vector3(0, 1.3, 0), body)
			_box(Vector3(0.5, 0.4, 0.5), Vector3(0, 0.2, 0), trim)
			_moving = Node3D.new()
			_moving.position = Vector3(0, 2.5, 0)
			add_child(_moving)
			_box(Vector3(0.9, 0.06, 0.06), Vector3.ZERO, _mat(Color("d9d2bf"), 0.4), _moving)
		"resonator":
			for i in 3:
				var fin := _box(Vector3(0.18, 1.6, 0.5), Vector3(0, 0.8, 0), _mat(Color("1b1d1f"), 0.3, 0.2))
				fin.rotation.y = i * TAU / 3.0
				fin.position = Vector3(sin(i * TAU / 3.0), 0, cos(i * TAU / 3.0)) * 0.35
			_moving = Node3D.new()
			_moving.position = Vector3(0, 1.9, 0)
			add_child(_moving)
			var crystal := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(0.4, 0.7, 0.4)
			crystal.mesh = prism
			crystal.material_override = _glow(TEAL, 2.0)
			_moving.add_child(crystal)
		"remains":
			# A spacer's last stand: a toppled locker, a pack, a scatter of kit.
			var locker := _box(Vector3(0.6, 0.45, 1.5), Vector3(0, 0.23, 0), body)
			locker.rotation.y = 0.3
			_box(Vector3(0.5, 0.35, 0.3), Vector3(0.55, 0.18, 0.5), trim)
			for k in 4:
				var bit := _box(Vector3(0.16, 0.08, 0.22), Vector3(-0.5 + k * 0.28, 0.04, -0.75 + (k % 2) * 0.3), _mat(Color("8c8f86"), 0.5, 0.4))
				bit.rotation.y = k * 0.9
		"cradle", "crane":
			_box(Vector3(1.4, 0.4, 1.0), Vector3(0, 0.2, 0), body)
			_box(Vector3(0.9, 1.2, 0.2), Vector3(0, 0.9, -0.35), trim)
			var screen := _box(Vector3(0.7, 0.4, 0.02), Vector3(0, 1.1, -0.24), _glow(Color("6fd8ff"), 1.5))
			screen.rotation.x = 0.0
		_:
			_box(Vector3(0.8, 1.0, 0.8), Vector3(0, 0.5, 0), body)
	# Status lamp on top of everything, and the light it throws.
	_lamp_mat = _glow(AMBER, 3.0)
	var top := 3.5 if kind == "floodlight" else (2.9 if kind == "transponder" else (0.75 if kind == "remains" else 1.6))
	var lamp := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	lamp.mesh = sphere
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0.3 if kind != "floodlight" else 0.0, top, 0)
	add_child(lamp)
	_lamp_light = OmniLight3D.new()
	_lamp_light.omni_range = 4.0
	_lamp_light.position = lamp.position + Vector3.UP * 0.2
	add_child(_lamp_light)
	# Collision, so it reads as a solid thing to walk round.
	var solid := StaticBody3D.new()
	solid.collision_layer = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.0, 0.5)
	shape.shape = box
	shape.position.y = 0.5
	solid.add_child(shape)
	add_child(solid)


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	(parent if parent else self).add_child(mesh)
	return mesh


func _cyl(radius: float, height: float, pos: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh.mesh = cyl
	mesh.material_override = mat
	mesh.position = pos
	(parent if parent else self).add_child(mesh)
	return mesh


static func _mat(color: Color, roughness := 0.7, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
