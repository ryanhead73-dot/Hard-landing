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
## Terrain grid: fine (and walkable, with collision) inside COLLIDE_HALF, coarse out to the
## mountains at FAR_HALF.
const FINE_STEP := 2.0
const COARSE_STEP := 8.0
const COLLIDE_HALF := 160.0
const FAR_HALF := 320.0
## Water sits just under the flat floor, in hollows pressed into the ground.
const WATER_Y := -0.14
const POOL_DEPTH := 0.8
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")

var _moss_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _terrain_mat: ShaderMaterial
var _water_mat: ShaderMaterial
## Pools: [centre, radius].
var pools: Array = []
var _hills: FastNoiseLite
var _rough: FastNoiseLite
var _heights: Dictionary = {}


func _ready() -> void:
	build()


func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_hills = FastNoiseLite.new()
	_hills.seed = SEED
	_hills.frequency = 0.018
	_hills.fractal_octaves = 3
	_rough = FastNoiseLite.new()
	_rough.seed = SEED + 1
	_rough.frequency = 0.006
	_rough.fractal_octaves = 4
	_moss_mat = _emissive(Color("3fd1b5"), 1.2)
	_rim_mat = _emissive(Color("3fd1b5"), 0.5)
	_place_pools(rng)
	_build_ground()
	_build_crash_marks(rng)
	_build_pools(rng)
	_build_columns(rng)
	_build_moss(rng)


func set_dusk(dusk: bool) -> void:
	set_glow(1.0 if dusk else 0.0)


## Moss, cracks and pool rims glow brighter as the light goes (0 day .. 1 dusk).
func set_glow(amount: float) -> void:
	WorldProps.set_glow(amount)
	_rim_mat.emission_energy_multiplier = lerpf(0.5, 1.6, amount)
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("glow", amount)
		_water_mat.set_shader_parameter("glow", amount)


# --- Terrain -------------------------------------------------------------------------------

## How much the ground must stay flat here, 0..1: round the ship, along the crash furrow, at
## every expedition site, along the walk from the ship to each, and round the pools.
func flatness(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var f := 1.0 - smoothstep(30.0, 46.0, p.length())
	if x > 8.0 and x < 95.0:
		f = maxf(f, 1.0 - smoothstep(8.0, 16.0, absf(z)))
	for zone in KEEP_CLEAR:
		var c := Vector2(zone[0].x, zone[0].z)
		var r: float = zone[1]
		f = maxf(f, 1.0 - smoothstep(r + 4.0, r + 16.0, p.distance_to(c)))
		# The way there from the ship.
		var t := clampf(p.dot(c) / c.length_squared(), 0.0, 1.0)
		f = maxf(f, 1.0 - smoothstep(6.0, 13.0, p.distance_to(c * t)))
		if f >= 1.0:
			return 1.0
	for pool in pools:
		var pc := Vector2(pool[0].x, pool[0].z)
		f = maxf(f, 1.0 - smoothstep(pool[1] + 2.0, pool[1] + 9.0, p.distance_to(pc)))
	return f


## True on the walk from the ship to any site (props keep off it).
func on_path(x: float, z: float, width := 9.0) -> bool:
	var p := Vector2(x, z)
	for zone in KEEP_CLEAR:
		var c := Vector2(zone[0].x, zone[0].z)
		var t := clampf(p.dot(c) / c.length_squared(), 0.0, 1.0)
		if p.distance_to(c * t) < width:
			return true
	return false


## Ground height at a point: hummocks of basalt between the paths, the ring of ridges that
## closes the basin, mountains beyond, and the pool hollows.
func height_at(x: float, z: float) -> float:
	var key := Vector2i(roundi(x * 4.0), roundi(z * 4.0))
	if _heights.has(key):
		return _heights[key]
	var r := Vector2(x, z).length()
	var n := _hills.get_noise_2d(x, z) * 0.5 + 0.5
	var big := _rough.get_noise_2d(x, z) * 0.5 + 0.5
	var hummocks := pow(n, 2.2) * 4.5 * (1.0 - smoothstep(100.0, 135.0, r))
	var rim := smoothstep(98.0, 150.0, r) * (14.0 + 22.0 * big) + smoothstep(170.0, 300.0, r) * (30.0 + 50.0 * big)
	var h := (hummocks + rim) * (1.0 - flatness(x, z))
	for pool in pools:
		var d := Vector2(x - pool[0].x, z - pool[0].z).length()
		if d < pool[1] + 1.5:
			h -= POOL_DEPTH * (1.0 - smoothstep(pool[1] * 0.5, pool[1] + 1.2, d))
	_heights[key] = h
	return h


func _place_pools(rng: RandomNumberGenerator) -> void:
	pools.clear()
	for i in 16:
		pools.append([_scatter(rng, 26.0, 100.0), rng.randf_range(3.0, 9.0)])


func _grid_coords() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var c := -FAR_HALF
	while c < -COLLIDE_HALF:
		out.append(c)
		c += COARSE_STEP
	c = -COLLIDE_HALF
	while c < COLLIDE_HALF:
		out.append(c)
		c += FINE_STEP
	c = COLLIDE_HALF
	while c <= FAR_HALF:
		out.append(c)
		c += COARSE_STEP
	return out


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	add_child(body)
	var coords := _grid_coords()
	var n := coords.size()
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			heights[j * n + i] = height_at(coords[i], coords[j])
	# Mesh: one grid, normals from neighbouring heights, masks in vertex colour.
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	for j in n:
		for i in n:
			var x := coords[i]
			var z := coords[j]
			var h := heights[j * n + i]
			var hl := heights[j * n + maxi(i - 1, 0)]
			var hr := heights[j * n + mini(i + 1, n - 1)]
			var hd := heights[maxi(j - 1, 0) * n + i]
			var hu := heights[mini(j + 1, n - 1) * n + i]
			var dx := coords[mini(i + 1, n - 1)] - coords[maxi(i - 1, 0)]
			var dz := coords[mini(j + 1, n - 1)] - coords[maxi(j - 1, 0)]
			var normal := Vector3(-(hr - hl) / dx, 1.0, -(hu - hd) / dz).normalized()
			verts[j * n + i] = Vector3(x, h, z)
			normals[j * n + i] = normal
			colors[j * n + i] = _masks(x, z, h, normal)
	var indices := PackedInt32Array()
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var view := MeshInstance3D.new()
	view.name = "Terrain"
	view.mesh = mesh
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = TERRAIN_SHADER
	var tex: Array = Surfaces._textures("basalt")
	_terrain_mat.set_shader_parameter("basalt_tex", tex[0])
	_terrain_mat.set_shader_parameter("basalt_normal", tex[1])
	_terrain_mat.set_shader_parameter("detail_noise", _noise_texture(SEED + 5, 0.02, false))
	view.material_override = _terrain_mat
	body.add_child(view)
	# Collision: the fine part of the grid as a height map, one cell per FINE_STEP.
	var first := 0
	while coords[first] < -COLLIDE_HALF:
		first += 1
	var cells := int(COLLIDE_HALF * 2.0 / FINE_STEP) + 1
	var map := PackedFloat32Array()
	map.resize(cells * cells)
	for j in cells:
		for i in cells:
			map[j * cells + i] = heights[(first + j) * n + first + i]
	var shape := HeightMapShape3D.new()
	shape.map_width = cells
	shape.map_depth = cells
	shape.map_data = map
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(FINE_STEP, 1.0, FINE_STEP)
	body.add_child(col)


## Vertex-colour masks for the terrain shader: r wet, g moss, b cliff.
func _masks(x: float, z: float, h: float, normal: Vector3) -> Color:
	var wet := clampf(-h * 3.0, 0.0, 1.0)
	var moss := 0.0
	for pool in pools:
		var d: float = Vector2(x - pool[0].x, z - pool[0].z).length() - pool[1]
		if d < 6.0:
			wet = maxf(wet, 1.0 - smoothstep(0.0, 5.0, d))
			moss = maxf(moss, 1.0 - smoothstep(0.5, 4.5, absf(d - 1.0)))
	# Moss gathers at the feet of the hummocks and in the creases.
	var slope := 1.0 - normal.y
	moss = maxf(moss, smoothstep(0.03, 0.12, slope) * (1.0 - smoothstep(0.25, 0.4, slope)) * 0.8)
	var cliff := smoothstep(0.3, 0.55, slope)
	return Color(wet, moss, cliff)


func _noise_texture(seed_value: int, frequency: float, normal: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = normal
	tex.generate_mipmaps = true
	tex.noise = noise
	return tex


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


func _build_pools(_rng: RandomNumberGenerator) -> void:
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = WATER_SHADER
	_water_mat.set_shader_parameter("ripple_noise", _noise_texture(SEED + 9, 0.05, true))
	for i in pools.size():
		var pos: Vector3 = pools[i][0]
		var radius: float = pools[i][1]
		var water := MeshInstance3D.new()
		water.name = "Pool"
		water.mesh = _pool_mesh(radius + 0.6)
		water.material_override = _water_mat
		water.position = Vector3(pos.x, WATER_Y, pos.z)
		add_child(water)
		if i % 3 == 0:
			_steam(Vector3(pos.x, 0.0, pos.z), radius)


## A flat disc whose UV.x runs from 0 at the centre to 1 at the rim (the shader's edge glow).
func _pool_mesh(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 40
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(Vector3.ZERO)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(Vector3(cos(a1), 0.0, sin(a1)) * radius)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(Vector3(cos(a0), 0.0, sin(a0)) * radius)
	return st.commit()


## Basalt column clusters out in the basin, boulders among the hummocks, crags on the rim.
func _build_columns(rng: RandomNumberGenerator) -> void:
	var clusters := ["basalt_cluster_0", "basalt_cluster_1", "basalt_cluster_2", "basalt_step_0"]
	for c in 14:
		var at := _scatter(rng, 30.0, 95.0)
		while on_path(at.x, at.z, 12.0):
			at = _scatter(rng, 30.0, 95.0)
		var prop: String = clusters[c % clusters.size()]
		WorldProps.place(self, prop, at + Vector3.UP * (height_at(at.x, at.z) - 0.2), rng.randf_range(0.0, TAU), rng.randf_range(0.8, 1.25))
	# Boulders where the ground rises, a few as cover on the flats.
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 2000:
		tries += 1
		var at := _scatter(rng, 30.0, 135.0)
		var f := flatness(at.x, at.z)
		if on_path(at.x, at.z) or (f > 0.85 and rng.randf() > 0.15):
			continue
		var prop := "boulder_%d" % (placed % 3)
		WorldProps.place(self, prop, at + Vector3.UP * (height_at(at.x, at.z) - 0.1), rng.randf_range(0.0, TAU), rng.randf_range(0.7, 1.6))
		placed += 1
	# The rim: crags and tall clusters on the ridges, the skyline from anywhere in the basin.
	for i in 64:
		var a := TAU * i / 64.0 + rng.randf_range(-0.04, 0.04)
		var d := rng.randf_range(120.0, 200.0)
		var at := Vector3(cos(a) * d, 0.0, sin(a) * d)
		if flatness(at.x, at.z) > 0.3:
			continue
		var prop: String = ["crag_0", "crag_1", "basalt_cluster_2", "basalt_cluster_0"][i % 4]
		var size := rng.randf_range(1.2, 2.2) if prop.begins_with("crag") else rng.randf_range(1.8, 3.2)
		WorldProps.place(self, prop, at + Vector3.UP * (height_at(at.x, at.z) - 1.5), rng.randf_range(0.0, TAU), size, d < COLLIDE_HALF)


func _build_moss(rng: RandomNumberGenerator) -> void:
	var clumps: Array[Transform3D] = []
	var tries := 0
	while clumps.size() < 7000 and tries < 60000:
		tries += 1
		var pos := _scatter(rng, SHIP_CLEAR_RADIUS, 140.0)
		var h := height_at(pos.x, pos.z)
		var mask := _masks(pos.x, pos.z, h, Vector3.UP)
		if rng.randf() > mask.g + 0.12:
			continue
		var spread := rng.randf_range(0.35, 1.1)
		var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(spread, rng.randf_range(0.8, 1.6), spread))
		clumps.append(Transform3D(turn, Vector3(pos.x, h - 0.03, pos.z)))
	_moss_mat = WorldProps.moss_material()
	WorldProps.scatter(self, "moss_clump", clumps, _moss_mat).name = "Moss"
	# Reeds stand round the pool rims.
	var tufts: Array[Transform3D] = []
	for pool in pools:
		for k in 26:
			var a := rng.randf_range(0.0, TAU)
			var d: float = pool[1] + rng.randf_range(-0.6, 1.8)
			var p := Vector3(pool[0].x + cos(a) * d, 0.0, pool[0].z + sin(a) * d)
			var size := rng.randf_range(0.7, 1.4)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
			tufts.append(Transform3D(basis, Vector3(p.x, maxf(height_at(p.x, p.z), WATER_Y) - 0.05, p.z)))
	WorldProps.scatter(self, "reeds", tufts, WorldProps.reed_material())


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
