class_name TimedHazard
extends Node3D
## Shared cycle for site hazards: quiet, then a readable warning, then an active phase that hurts
## whatever stands in the zone. Subclasses build the visuals and the zone shape.

signal triggered

enum Phase { QUIET, WARNING, ACTIVE }

const TICK := 0.25

@export var quiet_time := 4.0
## Extra random quiet time per cycle, so a field of hazards never settles into one rhythm.
@export var quiet_jitter := 0.0
@export var warning_time := 1.0
@export var active_time := 1.0
## Damage dealt once to everything in the zone as the active phase starts.
@export var burst_damage := 0.0
## Damage per second while active, dealt in ticks.
@export var damage_per_second := 0.0
@export var hurts_enemies := true
## Seconds into the first quiet phase at start.
@export var offset := 0.0
## Only fires when trigger() is called (by proximity or a shot), never on a timer.
@export var manual := false

var phase := Phase.QUIET

var _timer := 0.0
var _tick := 0.0
var _area: Area3D


func _ready() -> void:
	_build()
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = Game.LAYER_PLAYER | (Game.LAYER_ENEMY if hurts_enemies else 0)
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	shape.shape = _zone_shape()
	shape.transform = _zone_transform()
	_area.add_child(shape)
	add_child(_area)
	_timer = 0.0 if manual else maxf(quiet_time - fmod(offset, maxf(quiet_time, 0.01)), 0.05)
	_enter(Phase.QUIET)


func _physics_process(delta: float) -> void:
	if not (manual and phase == Phase.QUIET and _timer <= 0.0):
		_timer -= delta
	if _timer <= 0.0 and not (manual and phase == Phase.QUIET):
		_advance()
	if phase == Phase.WARNING:
		_warning(1.0 - clampf(_timer / warning_time, 0.0, 1.0))
	elif phase == Phase.ACTIVE and damage_per_second > 0.0:
		_tick -= delta
		if _tick <= 0.0:
			_tick = TICK
			_hurt(damage_per_second * TICK)


## Starts the warning now. Used by proximity triggers, shots, tests and scripted moments.
func trigger() -> void:
	if phase != Phase.QUIET or (manual and _timer > 0.0):
		return
	_enter(Phase.WARNING)
	_timer = warning_time
	triggered.emit()


## Skips straight to the active phase.
func force_active() -> void:
	_enter(Phase.ACTIVE)
	_timer = active_time
	_tick = 0.0
	if burst_damage > 0.0:
		_hurt.call_deferred(burst_damage)


## Back to the start of a quiet phase, ready to trigger (tests and scripted moments).
func reset() -> void:
	_enter(Phase.QUIET)
	_timer = 0.0 if manual else quiet_time
	_tick = 0.0


func is_active() -> bool:
	return phase == Phase.ACTIVE


func _advance() -> void:
	match phase:
		Phase.QUIET:
			trigger()
		Phase.WARNING:
			force_active()
		Phase.ACTIVE:
			_enter(Phase.QUIET)
			_timer = quiet_time + randf() * quiet_jitter


func _enter(p: Phase) -> void:
	phase = p
	_phase_changed(p)


func _hurt(amount: float) -> void:
	for body in _area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(amount, global_position)


# --- Overrides ----------------------------------------------------------------------------

func _build() -> void:
	pass


func _zone_shape() -> Shape3D:
	var s := CylinderShape3D.new()
	s.radius = 1.5
	s.height = 3.0
	return s


func _zone_transform() -> Transform3D:
	return Transform3D(Basis(), Vector3(0.0, 1.5, 0.0))


func _phase_changed(_p: Phase) -> void:
	pass


## Progress 0..1 through the warning, every physics frame.
func _warning(_t: float) -> void:
	pass


static func _glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _puff_material(color: Color) -> StandardMaterial3D:
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


static func _particles(amount: int, lifetime: float, color: Color, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = _puff_material(color)
	p.mesh = quad
	return p
