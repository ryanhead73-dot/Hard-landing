@tool
class_name CrashSite
extends Node3D
## Basalt wetland basin around the crash site. Fixed seed so the landmark is identical every run.

const SEED := 7
const SIZE := 400.0
const SHIP_CLEAR_RADIUS := 22.0
## Other sites that props must keep clear of: [centre, radius]. Matches main.tscn.
const KEEP_CLEAR := [
	[Vector3(-60.0, 0.0, 58.0), 22.0], [Vector3(48.0, 0.0, -58.0), 30.0], [Vector3(-82.0, 0.0, -28.0), 24.0],
	[Vector3(14.0, 0.0, 86.0), 34.0], [Vector3(86.0, 0.0, 28.0), 26.0], [Vector3(-28.0, 0.0, -90.0), 36.0],
	[Vector3(-102.0, 0.0, 20.0), 24.0],
]

var _moss_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D


func _ready() -> void:
	build()


func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_moss_mat = _emissive(Color("3fd1b5"), 1.2)
	_rim_mat = _emissive(Color("3fd1b5"), 0.5)
	_build_ground()
	_build_ridges(rng)
	_build_crash_marks(rng)
	_build_pools(rng)
	_build_columns(rng)
	_build_moss(rng)


func set_dusk(dusk: bool) -> void:
	set_glow(1.0 if dusk else 0.0)


## Moss and pool rims glow brighter as the light goes (0 day .. 1 dusk).
func set_glow(amount: float) -> void:
	_moss_mat.emission_energy_multiplier = lerpf(1.2, 3.0, amount)
	_rim_mat.emission_energy_multiplier = lerpf(0.5, 1.6, amount)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	mesh.mesh = plane
	var basalt := _mat(Color("1b1d1f"), 0.95)
	basalt.metallic_specular = 0.2
	mesh.material_override = basalt
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE, 2.0, SIZE)
	shape.shape = box
	shape.position.y = -1.0
	body.add_child(mesh)
	body.add_child(shape)
	add_child(body)


## Ring of slate ridges that closes the basin, so the ship is visible from the rim on the way home.
func _build_ridges(rng: RandomNumberGenerator) -> void:
	var slate := _mat(Color("3c4448"), 0.85)
	for i in 40:
		var angle := TAU * i / 40.0 + rng.randf_range(-0.05, 0.05)
		var dist := rng.randf_range(115.0, 150.0)
		var size := Vector3(rng.randf_range(25.0, 45.0), rng.randf_range(12.0, 36.0), rng.randf_range(20.0, 35.0))
		# Push the ridge outward until it clears every expedition site.
		var reach := maxf(size.x, size.z) * 0.6
		for step in 30:
			var at := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			var clear := true
			for zone in KEEP_CLEAR:
				clear = clear and at.distance_to(zone[0]) > zone[1] + reach
			if clear:
				break
			dist += 3.0
		var rock := _static_box(size, slate)
		rock.position = Vector3(cos(angle) * dist, size.y * 0.5 - 3.0, sin(angle) * dist)
		rock.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.0, TAU), rng.randf_range(-0.15, 0.15))


## Ploughed berm under the fuselage and a scorched furrow with hull debris behind the ship.
func _build_crash_marks(rng: RandomNumberGenerator) -> void:
	var rock := _mat(Color("26292b"), 0.95)
	for berm in [[Vector3(-14.0, 0.0, 0.0), Vector3(7.0, 0.8, 7.0)], [Vector3(-6.0, 0.0, -0.3), Vector3(9.0, 1.0, 6.0)], [Vector3(3.0, 0.0, -0.5), Vector3(8.0, 1.2, 7.0)]]:
		var mound := _static_box(berm[1], rock)
		mound.position = berm[0]
		mound.rotation.y = rng.randf_range(-0.15, 0.15)
	var furrow := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70.0, 7.0)
	furrow.mesh = plane
	furrow.material_override = _mat(Color("121314"), 1.0)
	furrow.position = Vector3(50.0, 0.01, 0.5)
	furrow.rotation.y = -0.04
	add_child(furrow)
	var debris_mats := [_mat(Color("e9e1cc"), 0.85), _mat(Color("c4622d"), 0.85), _mat(Color("3a3f43"), 0.5)]
	for i in 26:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(rng.randf_range(0.3, 1.8), rng.randf_range(0.05, 0.3), rng.randf_range(0.3, 1.4))
		piece.mesh = box
		piece.material_override = debris_mats[rng.randi() % debris_mats.size()]
		piece.position = Vector3(rng.randf_range(18.0, 80.0), 0.1, rng.randf_range(-5.0, 5.0))
		piece.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, TAU), rng.randf_range(-0.4, 0.4))
		add_child(piece)


func _build_pools(rng: RandomNumberGenerator) -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("1f2a30")
	water.metallic = 0.4
	water.roughness = 0.04
	for i in 16:
		var pos := _scatter(rng, 26.0, 100.0)
		var radius := rng.randf_range(3.0, 9.0)
		_disc(pos, radius + 0.25, 0.01, _rim_mat)
		_disc(pos, radius, 0.025, water)
		if i % 3 == 0:
			_steam(pos, radius)


func _build_columns(rng: RandomNumberGenerator) -> void:
	var basalt := _mat(Color("141618"), 0.8)
	for c in 12:
		var centre := _scatter(rng, 30.0, 95.0)
		for i in rng.randi_range(4, 9):
			var r := rng.randf_range(0.6, 1.2)
			var h := rng.randf_range(3.0, 12.0)
			var body := StaticBody3D.new()
			var mesh := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = r
			cyl.bottom_radius = r
			cyl.height = h
			cyl.radial_segments = 6
			mesh.mesh = cyl
			mesh.material_override = basalt
			var shape := CollisionShape3D.new()
			var cyl_shape := CylinderShape3D.new()
			cyl_shape.radius = r
			cyl_shape.height = h
			shape.shape = cyl_shape
			body.add_child(mesh)
			body.add_child(shape)
			body.position = centre + Vector3(rng.randf_range(-3.5, 3.5), h * 0.5, rng.randf_range(-3.5, 3.5))
			body.rotation.y = rng.randf_range(0.0, TAU)
			add_child(body)


func _build_moss(rng: RandomNumberGenerator) -> void:
	var tuft := BoxMesh.new()
	tuft.size = Vector3(0.18, 0.05, 0.18)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = tuft
	multimesh.instance_count = 3000
	for i in multimesh.instance_count:
		var pos := _scatter(rng, SHIP_CLEAR_RADIUS, 110.0)
		var spread := rng.randf_range(0.6, 2.2)
		var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(spread, 1.0, spread))
		multimesh.set_instance_transform(i, Transform3D(turn, pos + Vector3.UP * 0.02))
	var moss := MultiMeshInstance3D.new()
	moss.name = "Moss"
	moss.multimesh = multimesh
	moss.material_override = _moss_mat
	add_child(moss)


func _steam(pos: Vector3, radius: float) -> void:
	var steam := CPUParticles3D.new()
	steam.amount = 24
	steam.lifetime = 6.0
	steam.position = pos
	steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	steam.emission_sphere_radius = radius * 0.6
	steam.direction = Vector3.UP
	steam.spread = 12.0
	steam.gravity = Vector3(0.3, 0.25, 0.0)
	steam.initial_velocity_min = 0.3
	steam.initial_velocity_max = 0.6
	steam.scale_amount_min = 2.0
	steam.scale_amount_max = 4.0
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.88, 0.88, 0.08)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	steam.mesh = quad
	add_child(steam)


## Random point on the ground between two distances from the ship, kept out of the crash furrow.
func _scatter(rng: RandomNumberGenerator, min_dist: float, max_dist: float) -> Vector3:
	while true:
		var p := Vector3(rng.randf_range(-max_dist, max_dist), 0.0, rng.randf_range(-max_dist, max_dist))
		var d := Vector2(p.x, p.z).length()
		var in_furrow := p.x > 15.0 and p.x < 85.0 and absf(p.z) < 6.0
		var blocked := in_furrow
		for zone in KEEP_CLEAR:
			blocked = blocked or p.distance_to(zone[0]) < zone[1]
		if d >= min_dist and d <= max_dist and not blocked:
			return p
	return Vector3.ZERO


func _disc(pos: Vector3, radius: float, height: float, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	cyl.radial_segments = 32
	mesh.mesh = cyl
	mesh.material_override = mat
	mesh.position = pos + Vector3.UP * height
	add_child(mesh)


func _static_box(size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(mesh)
	body.add_child(shape)
	add_child(body)
	return body


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	# Stone gets basalt columns; the cream and oxide debris gets hull panelling.
	if color.get_luminance() < 0.5 and color.s < 0.4:
		Surfaces.apply_basalt(m)
	else:
		Surfaces.apply_hull(m, 3.0)
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
