class_name PbrSet
extends RefCounted
## Materials from the tiling PBR sets in assets/textures/<folder>/<set>/ (albedo, normal,
## roughness, and an optional emission_mask), made by Jake for the Shatterlands. Mapped
## triplanar, so one material fits any size of mesh without UV work: `metres` is how much
## surface one repeat of the texture covers. World-space by default, so neighbouring pieces line
## up; `world = false` maps in the mesh's own space, for things that are rotated (the wreck).
##
## The .import files beside the PNGs are checked in on purpose (the project ignores *.import):
## code-made materials don't trigger Godot's 3D detection, so without them the maps would import
## uncompressed and without mipmaps.

const ROOT := "res://assets/textures/%s/%s/"

static var _cache := {}


static func material(folder: String, set_name: String, metres: float, world := true, tint := Color.WHITE, emission := Color.BLACK, emission_energy := 1.0) -> StandardMaterial3D:
	var key := "%s/%s/%s/%s/%s/%s/%s" % [folder, set_name, metres, world, tint.to_html(), emission.to_html(), emission_energy]
	if _cache.has(key):
		return _cache[key]
	var path := ROOT % [folder, set_name]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _load(path + "albedo.png")
	var normal := _load(path + "normal.png")
	if normal:
		m.normal_enabled = true
		m.normal_texture = normal
	var rough := _load(path + "roughness.png")
	m.roughness = 1.0
	if rough:
		m.roughness_texture = rough
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var mask := _load(path + "emission_mask.png")
	if mask and emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_texture = mask
		m.emission_energy_multiplier = emission_energy
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / metres
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


static func exists(folder: String, set_name: String) -> bool:
	return ResourceLoader.exists((ROOT % [folder, set_name]) + "albedo.png")


static func _load(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
