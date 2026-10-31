class_name Vfx
extends RefCounted
## One-shot and looping particle effects built in code (CPU particles, so they work on every
## renderer): bursts for deaths and splashes, the muzzle flash star, Kestrel's engine exhaust and
## the drifting moss motes that hang over the basin.

static var _mats: Dictionary = {}


## Unshaded additive glow for particles and flashes, cached per colour.
static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "%s/%.1f" % [color.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	_mats[key] = m
	return m


## A one-shot spray at `at`, freed when done. Returns it (tests check what's spawned).
static func burst(parent: Node, at: Vector3, color: Color, amount := 16, speed := 3.0, size := 0.08, life := 0.6, up := Vector3.UP, spread := 60.0, gravity := -4.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Burst"
	p.add_to_group("vfx_burst")
	p.top_level = true
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = life
	p.direction = up
	p.spread = spread
	p.gravity = Vector3(0.0, gravity, 0.0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = glow(color)
	p.mesh = quad
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	parent.get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)
	return p


## A foot comes down in a pool: a low spray of droplets.
static func splash(parent: Node, at: Vector3, size := 1.0) -> CPUParticles3D:
	var p := burst(parent, at, Color("b8c8c4"), int(10 * size), 2.2 * size, 0.05, 0.45, Vector3.UP, 35.0, -9.8)
	(p.mesh as QuadMesh).material = soft(Color(0.75, 0.82, 0.8, 0.8))
	return p


## Wildlife dies: a puff of the Loom's teal light leaves the body.
static func death(parent: Node, at: Vector3, size := 1.0) -> CPUParticles3D:
	return burst(parent, at + Vector3.UP * 0.5 * size, Color("3fd1b5"), int(18 * size), 2.0 * size, 0.12 * size, 1.1, Vector3.UP, 70.0, 1.5)


static func acid(parent: Node, at: Vector3) -> CPUParticles3D:
	return burst(parent, at, Color("b4e05a"), 22, 4.0, 0.1, 0.7, Vector3.UP, 55.0, -9.0)


## The muzzle flash: a short-lived star of crossed quads at the barrel.
static func muzzle_star(color: Color) -> MeshInstance3D:
	var star := MeshInstance3D.new()
	star.name = "MuzzleStar"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	var m := glow(color, 3.0).duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = false
	quad.material = m
	star.mesh = quad
	star.visible = false
	return star


## Kestrel's engine: a glowing exhaust that grows with `power` (0..1). Returns the emitter.
static func exhaust(parent: Node3D, at: Vector3, back: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Exhaust"
	p.amount = 60
	p.lifetime = 0.6
	p.local_coords = false
	p.direction = back
	p.spread = 8.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 10.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.9
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.85, 0.6, 0.9))
	fade.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.material = glow(Color("ff9a4a"), 1.6)
	p.mesh = quad
	p.position = at
	p.emitting = false
	parent.add_child(p)
	return p


## Moss motes drifting around a point (the player): ambient life for the basin.
static func motes(parent: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Motes"
	p.amount = 40
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14.0, 3.0, 14.0)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0.0, 0.05, 0.0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = glow(Color("3fd1b5"), 2.5)
	p.mesh = quad
	p.position = Vector3(0.0, 1.5, 0.0)
	parent.add_child(p)
	p.emitting = true
	return p


## Soft, non-glowing particles for smoke and dust, cached per colour.
static func soft(color: Color) -> StandardMaterial3D:
	var key := "soft/%s" % color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	_mats[key] = m
	return m


## A trail of dark smoke streaming from a moving point (Kestrel coming down). Returns the emitter.
static func smoke(parent: Node3D, at: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.amount = 90
	p.lifetime = 2.6
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 40.0
	p.gravity = Vector3(0.0, 1.2, 0.0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 0.6, 0.3, 0.9), Color(0.25, 0.24, 0.23, 0.8), Color(0.4, 0.4, 0.4, 0.0)])
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 2.2)
	quad.material = soft(Color(1, 1, 1))
	p.mesh = quad
	p.position = at
	parent.add_child(p)
	p.emitting = true
	return p


## A low ring of dust and steam thrown up by an impact, freed when done.
static func dust(parent: Node, at: Vector3, size := 1.0) -> CPUParticles3D:
	var p := burst(parent, at, Color.WHITE, int(70 * size), 9.0 * size, 2.2 * size, 2.4, Vector3.UP, 85.0, 1.0)
	(p.mesh as QuadMesh).material = soft(Color("8d918f"))
	p.damping_min = 3.0
	p.damping_max = 5.0
	return p
