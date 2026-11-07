class_name Geyser
extends Node3D
## The Chimney (X2.7): a geyser on a terraced mound of pale sinter. It breathes steam, rumbles,
## then throws a plume twenty-odd metres up. Juno standing on the vent when it goes is thrown
## high (there's no fall damage), which is the fastest way to see the whole basin.

const IDLE := 24.0
const RUMBLE := 2.5
const ERUPT := 5.0
const CYCLE := IDLE + RUMBLE + ERUPT
## How close to the vent (flat distance) Juno must be to be thrown.
const VENT_RADIUS := 1.6
const LAUNCH_SPEED := 17.0
const SINTER := Color("d9cdb4")
const SINTER_STAIN := Color("bf8a55")
const VENT := Color("1b1d1f")

var main: Node
## Seconds into the cycle.
var time := 0.0
var launches := 0
var _steam: CPUParticles3D
var _plume: CPUParticles3D
var _launched_this_burst := false
var _rumbled := false
var _vent_top := 0.0


func setup(m: Node, at: Vector3) -> void:
	main = m
	position = at
	_build()


func erupting() -> bool:
	return time >= IDLE + RUMBLE


func rumbling() -> bool:
	return time >= IDLE and not erupting()


func vent_point() -> Vector3:
	return to_global(Vector3(0.0, _vent_top, 0.0))


## Jumps the cycle to `t` seconds in (for tests and the dev panel).
func set_time(t: float) -> void:
	time = fposmod(t, CYCLE)
	_launched_this_burst = false
	_rumbled = time >= IDLE


func _process(delta: float) -> void:
	time += delta
	if time >= CYCLE:
		time -= CYCLE
		_launched_this_burst = false
		_rumbled = false
	_steam.initial_velocity_max = 6.0 if rumbling() else 2.5
	_plume.emitting = erupting()
	if not main or not main.player:
		return
	var p: Vector3 = main.player.global_position
	var near := p.distance_to(global_position) < 40.0
	if rumbling() and not _rumbled:
		_rumbled = true
		if near:
			Sfx.play("thunder", global_position, -16.0)
			if p.distance_to(global_position) < 10.0:
				main.player.add_trauma(0.15)
	if erupting() and not _launched_this_burst:
		var flat := Vector2(p.x - global_position.x, p.z - global_position.z).length()
		if flat <= VENT_RADIUS and absf(p.y - vent_point().y) < 1.5 and not main.player.dead:
			_launched_this_burst = true
			launches += 1
			main.player.velocity.y = LAUNCH_SPEED
			main.player.global_position.y += 0.2
			Sfx.play("splash_0", vent_point(), 0.0)
			main.player.add_trauma(0.3)


func _build() -> void:
	var sinter := StandardMaterial3D.new()
	sinter.albedo_color = SINTER
	sinter.roughness = 0.7
	var stain := StandardMaterial3D.new()
	stain.albedo_color = SINTER_STAIN
	stain.roughness = 0.5
	# Terraces: stacked, slightly off-centre discs, each a low step Juno can walk up.
	var tiers := [[5.2, 0.45, sinter], [4.0, 0.45, stain], [2.9, 0.45, sinter], [1.9, 0.4, stain]]
	var y := -0.25
	for i in tiers.size():
		var t: Array = tiers[i]
		var r: float = t[0]
		var h: float = t[1]
		var mesh := CylinderMesh.new()
		mesh.top_radius = r * 0.92
		mesh.bottom_radius = r
		mesh.height = h
		mesh.radial_segments = 20
		mesh.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = t[2]
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = h
		shape.shape = cyl
		body.position = Vector3(0.15 * i, y + h * 0.5, -0.1 * i)
		body.add_child(mi)
		body.add_child(shape)
		add_child(body)
		y += h
	_vent_top = y
	var vent := MeshInstance3D.new()
	var vm := CylinderMesh.new()
	vm.top_radius = 0.7
	vm.bottom_radius = 0.7
	vm.height = 0.04
	vent.mesh = vm
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = VENT
	vmat.roughness = 0.2
	vent.material_override = vmat
	vent.position = Vector3(0.45, y + 0.01, -0.3)
	add_child(vent)
	_steam = _particles(40, 3.0, Vector2(1.0, 2.5), 0.6, 1.4)
	_steam.emitting = true
	_plume = _particles(160, 2.4, Vector2(14.0, 20.0), 0.25, 3.6)
	_plume.emitting = false


func _particles(amount: int, life: float, speed: Vector2, spread: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.position = Vector3(0.45, _vent_top + 0.1, -0.3)
	p.direction = Vector3.UP
	p.spread = spread * 30.0
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.92, 0.94, 0.95, 0.55)
	# A soft round puff, not a square.
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	puff.width = 64
	puff.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = g
	m.albedo_texture = puff
	quad.material = m
	p.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	add_child(p)
	return p
