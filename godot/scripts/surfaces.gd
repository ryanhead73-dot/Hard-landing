class_name Surfaces
extends RefCounted
## Procedural surface detail, generated once at startup and shared: hull panelling with seams,
## rivets and grime for Kestrel and the wrecks; cellular basalt for the ground and columns; a
## fine grime for everything else. Applied world-space triplanar, so CSG and generated meshes
## need no UVs. Colour still comes from each material's albedo_color (the textures are greyscale).

const SIZE := 256

static var _cache: Dictionary = {}


## Kestrel and wreck hulls: tile = metres per texture repeat. Things that move (Kestrel lifting
## off) pass world = false so the pattern rides with them instead of sliding across.
static func apply_hull(m: StandardMaterial3D, tile := 4.0, world := true) -> void:
	_apply(m, "hull", tile, world)


## Seamless greyscale value noise shared by the hull shader (grime, chips, streaks, mud).
static func noise_texture() -> NoiseTexture2D:
	if _cache.has("noise"):
		return _cache["noise"]
	var noise := FastNoiseLite.new()
	noise.seed = 4471
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	_cache["noise"] = tex
	return tex


static func apply_basalt(m: StandardMaterial3D, tile := 6.0) -> void:
	_apply(m, "basalt", tile, true)


static func apply_grime(m: StandardMaterial3D, tile := 3.0, world := true) -> void:
	_apply(m, "grime", tile, world)


static func _apply(m: StandardMaterial3D, kind: String, tile: float, world: bool) -> void:
	if m == null or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.emission_enabled:
		return
	var tex: Array = _textures(kind)
	m.albedo_texture = tex[0]
	m.normal_enabled = true
	m.normal_texture = tex[1]
	m.normal_scale = 0.6 if kind == "basalt" else 0.35
	m.roughness_texture = tex[0]
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / tile


## [albedo (greyscale, ~1 = clean), normal map] for a kind, built on first use.
static func _textures(kind: String) -> Array:
	if _cache.has(kind):
		return _cache[kind]
	var img := Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 4471
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var cells := FastNoiseLite.new()
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.seed = 7
	cells.frequency = 0.035
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	for y in SIZE:
		for x in SIZE:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var v := 1.0
			match kind:
				"hull":
					v = _hull_value(x, y, n)
				"basalt":
					# Edges between cells read as the cracks between basalt columns.
					var edge := clampf(cells.get_noise_2d(x, y) * 6.0, 0.0, 1.0)
					v = lerpf(0.55, 1.0, edge) * lerpf(0.82, 1.05, n)
				"grime":
					v = lerpf(0.78, 1.04, n)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var albedo := ImageTexture.create_from_image(img)
	var bump := img.duplicate() as Image
	bump.clear_mipmaps()
	bump.bump_map_to_normal_map(6.0 if kind == "basalt" else 3.0)
	bump.generate_mipmaps()
	var normal := ImageTexture.create_from_image(bump)
	_cache[kind] = [albedo, normal]
	return _cache[kind]


## Panels on a staggered grid, dark seams, rivet rows, and grime pooling in the noise.
static func _hull_value(x: int, y: int, n: float) -> float:
	var row := y / 64
	var px := (x + (32 if row % 2 == 1 else 0)) % 128
	var py := y % 64
	var v := 0.97 + (hash(Vector2i((x + (32 if row % 2 == 1 else 0)) / 128, row)) % 7) * 0.006
	if px < 1 or py < 1:
		v = 0.68
	elif px < 2 or py < 2:
		v = 0.86
	elif (px == 6 or px == 121) and py % 8 == 4:
		v = 0.8
	return v * lerpf(0.9, 1.02, smoothstep(0.25, 0.75, n))
