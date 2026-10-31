class_name WorldProps
extends RefCounted
## The modelled world dressing from blender/build_world.py: basalt column clusters, boulders,
## crags, moss clumps and reeds. Meshes, collision shapes and the shared basalt shader are
## loaded once and reused by every instance.

const ROCK_SHADER := preload("res://shaders/rock.gdshader")
## Props that get a concave (trimesh) collider; the rest get a convex hull.
const CONCAVE := ["basalt_cluster_0", "basalt_cluster_1", "basalt_cluster_2", "basalt_step_0", "crag_0", "crag_1"]

static var _meshes: Dictionary = {}
static var _shapes: Dictionary = {}
static var _rock_mat: ShaderMaterial
static var _moss_mat: StandardMaterial3D
static var _reed_mat: StandardMaterial3D


static func mesh(prop: String) -> Mesh:
	if _meshes.has(prop):
		return _meshes[prop]
	var scene: PackedScene = load("res://assets/world/%s.glb" % prop)
	var root := scene.instantiate()
	var found: Mesh = null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		found = (node as MeshInstance3D).mesh
		break
	root.free()
	_meshes[prop] = found
	return found


static func shape(prop: String) -> Shape3D:
	if not _shapes.has(prop):
		var m := mesh(prop)
		_shapes[prop] = m.create_trimesh_shape() if prop in CONCAVE else m.create_convex_shape(true, true)
	return _shapes[prop]


static func rock_material() -> ShaderMaterial:
	if _rock_mat == null:
		_rock_mat = ShaderMaterial.new()
		_rock_mat.shader = ROCK_SHADER
		var tex: Array = Surfaces._textures("basalt")
		_rock_mat.set_shader_parameter("basalt_tex", tex[0])
		_rock_mat.set_shader_parameter("basalt_normal", tex[1])
		var noise := FastNoiseLite.new()
		noise.seed = 4471
		noise.frequency = 0.02
		noise.fractal_octaves = 4
		var nt := NoiseTexture2D.new()
		nt.seamless = true
		nt.generate_mipmaps = true
		nt.noise = noise
		_rock_mat.set_shader_parameter("detail_noise", nt)
	return _rock_mat


static func moss_material() -> StandardMaterial3D:
	if _moss_mat == null:
		_moss_mat = StandardMaterial3D.new()
		_moss_mat.albedo_color = Color("0d2a24")
		_moss_mat.roughness = 1.0
		_moss_mat.emission_enabled = true
		_moss_mat.emission = Color("3fd1b5")
		_moss_mat.emission_energy_multiplier = 0.02
	return _moss_mat


static func reed_material() -> StandardMaterial3D:
	if _reed_mat == null:
		_reed_mat = StandardMaterial3D.new()
		_reed_mat.albedo_color = Color("16241f")
		_reed_mat.roughness = 0.85
		_reed_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _reed_mat


## Dusk brings the fissures and the moss up (0 day .. 1 dusk).
static func set_glow(amount: float) -> void:
	rock_material().set_shader_parameter("glow", amount)
	moss_material().emission_energy_multiplier = lerpf(0.02, 0.06, amount)


## A rock with collision (unless `collide` is false), standing at `pos`.
static func place(parent: Node, prop: String, pos: Vector3, yaw: float, size := 1.0, collide := true) -> Node3D:
	var holder: Node3D
	if collide:
		holder = StaticBody3D.new()
		holder.collision_layer = Game.LAYER_WORLD
		var col := CollisionShape3D.new()
		col.shape = shape(prop)
		col.scale = Vector3.ONE * size
		holder.add_child(col)
	else:
		holder = Node3D.new()
	holder.name = prop.capitalize().replace(" ", "")
	var view := MeshInstance3D.new()
	view.mesh = mesh(prop)
	view.material_override = rock_material()
	view.scale = Vector3.ONE * size
	holder.add_child(view)
	holder.position = pos
	holder.rotation.y = yaw
	parent.add_child(holder)
	return holder


## Many copies of a small prop as one MultiMesh: transforms in parent space.
static func scatter(parent: Node, prop: String, transforms: Array[Transform3D], material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh(prop)
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = prop.capitalize().replace(" ", "")
	inst.multimesh = mm
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return inst
