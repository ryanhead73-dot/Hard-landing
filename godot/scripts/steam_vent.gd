class_name SteamVent
extends Node3D
## Hot-spring vent. It hisses and its crust glows before each burst, then scalds anything standing
## in the column, scuttlers included, so a player can time a crossing or lure a pack into it.

signal burst_started

enum Phase { QUIET, WARNING, BURST }

const TICK := 0.25

@export var radius := 1.6
@export var quiet_time := 3.2
@export var warning_time := 0.9
@export var burst_time := 1.3
@export var damage_per_second := 32.0
## Seconds into the quiet phase at start, so neighbouring vents don't fire together.
@export var offset := 0.0

var phase := Phase.QUIET

var _timer := 0.0
var _tick := 0.0
var _area: Area3D
var _plume: CPUParticles3D
var _crust: StandardMaterial3D


func _ready() -> void:
	_build()
	_timer = maxf(quiet_time - fmod(offset, quiet_time), 0.05)


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_advance()
	if phase == Phase.WARNING:
		_crust.emission_energy_multiplier = 0.25 + 2.75 * (1.0 - _timer / warning_time)
	if phase != Phase.BURST:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	for body in _area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage_per_second * TICK, global_position)


## Skips straight to a burst. Used by tests and could be used by scripted moments.
func force_burst() -> void:
	phase = Phase.WARNING
	_timer = 0.0
	_advance()


func _advance() -> void:
	match phase:
		Phase.QUIET:
			phase = Phase.WARNING
			_timer = warning_time
			Sfx.play("steam_hiss", global_position, -6.0, 0.1)
		Phase.WARNING:
			phase = Phase.BURST
			_timer = burst_time
			_tick = 0.0
			_plume.amount = 48
			_plume.initial_velocity_min = 7.0
			_plume.initial_velocity_max = 10.0
			_plume.scale_amount_max = 1.4
			_crust.emission_energy_multiplier = 3.0
			Sfx.play("steam_burst", global_position, -2.0, 0.1)
			burst_started.emit()
		Phase.BURST:
			phase = Phase.QUIET
			_timer = quiet_time
			_plume.amount = 10
			_plume.initial_velocity_min = 0.6
			_plume.initial_velocity_max = 1.2
			_plume.scale_amount_max = 0.6
			_crust.emission_energy_multiplier = 0.25


func _build() -> void:
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius + 0.2
	disc.height = 0.06
	ring.mesh = disc
	_crust = StandardMaterial3D.new()
	_crust.albedo_color = Color("8a7a52")
	_crust.roughness = 0.9
	_crust.emission_enabled = true
	_crust.emission = Color("ff8a3d")
	_crust.emission_energy_multiplier = 0.25
	ring.material_override = _crust
	ring.position.y = 0.04
	add_child(ring)
	var mouth := MeshInstance3D.new()
	var mouth_mesh := CylinderMesh.new()
	mouth_mesh.top_radius = radius * 0.35
	mouth_mesh.bottom_radius = radius * 0.35
	mouth_mesh.height = 0.07
	mouth.mesh = mouth_mesh
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("0b0c0d")
	mouth.material_override = dark
	mouth.position.y = 0.05
	add_child(mouth)

	_plume = CPUParticles3D.new()
	_plume.amount = 10
	_plume.lifetime = 1.4
	_plume.direction = Vector3.UP
	_plume.spread = 8.0
	_plume.gravity = Vector3(0.0, 0.5, 0.0)
	_plume.initial_velocity_min = 0.6
	_plume.initial_velocity_max = 1.2
	_plume.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_plume.emission_sphere_radius = radius * 0.3
	_plume.scale_amount_min = 0.3
	_plume.scale_amount_max = 0.6
	var puff := QuadMesh.new()
	puff.size = Vector2(1.2, 1.2)
	puff.material = _puff_material(Color(0.88, 0.9, 0.88, 0.45))
	_plume.mesh = puff
	add_child(_plume)

	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = Game.LAYER_PLAYER | Game.LAYER_ENEMY
	var shape := CollisionShape3D.new()
	var column := CylinderShape3D.new()
	column.radius = radius
	column.height = 3.0
	shape.shape = column
	shape.position.y = 1.5
	_area.add_child(shape)
	add_child(_area)


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
