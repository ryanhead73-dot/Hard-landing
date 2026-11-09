class_name BoostLedges
extends Node
## The engine's reward opens short new paths in the older places (production pack, repair 6):
## basalt ledges too tall to jump, each with a thrust mark on its face and a cache on top, that
## the suit thrusters reach. One in the Kettle, one in the Gillwood, one in the Loom Expanse.
## State in Game.flags: thrust_cache_<region>.

const HEIGHT := 2.5
const SIZE := Vector3(3.2, HEIGHT, 3.2)
const SCRAP := 20
## Region -> where the ledge stands (that region's local space; Kettle ground height is looked up).
const LEDGES := {
	"kettle": Vector3(-22.0, 0.0, 34.0),
	"gillwood": Vector3(12.0, 0.0, 48.0),
	"loom_expanse": Vector3(-34.0, 0.0, -48.0),
}
const MARK := Color("ffb04a")

var main: Node
var _built: Node3D
var _region := ""


func setup(m: Node) -> void:
	main = m
	main.regions.travelled.connect(func(_from: String, to: String): _build_for(to))
	_build_for.call_deferred(main.regions.current)


## Where the ledge in `region` stands (world space), or Vector3.INF.
func ledge_at(region: String) -> Vector3:
	if not LEDGES.has(region):
		return Vector3.INF
	var local: Vector3 = LEDGES[region]
	if region == "kettle":
		# On the basin's hummocks: stand it on the highest ground under it, so it's full height
		# all round.
		var h := -INF
		for dx in [-2.0, 0.0, 2.0]:
			for dz in [-2.0, 0.0, 2.0]:
				h = maxf(h, main.site.height_at(local.x + dx, local.z + dz))
		return Vector3(local.x, h, local.z)
	if main.regions.scene == null or main.regions.current != region:
		return Vector3.INF
	return main.regions.scene.to_global(local)


func cache_at(region: String) -> Vector3:
	var at := ledge_at(region)
	return at + Vector3(0.0, HEIGHT, 0.0) if at != Vector3.INF else at


func opened(region: String) -> bool:
	return Game.flags.get("thrust_cache_" + region, false) == true


func interaction(pos: Vector3) -> Dictionary:
	var region: String = main.regions.current
	var at := cache_at(region)
	if at == Vector3.INF or opened(region) or pos.distance_to(at) > 2.2:
		return {}
	return {"label": "[E] Open the thrust cache", "action": open_cache.bind(region)}


func open_cache(region: String) -> void:
	if opened(region):
		return
	Game.set_flag("thrust_cache_" + region)
	Game.add_scrap(SCRAP)
	Sfx.play("crawlspace_hatch", cache_at(region), -2.0, 0.0)
	if main.get("hud"):
		main.hud.show_message("Thrust cache: %d scrap. Someone else had thrusters once." % SCRAP)
	_build_for(region)


func _build_for(region: String) -> void:
	if _built and is_instance_valid(_built):
		if _built.get_parent():
			_built.get_parent().remove_child(_built)
		_built.queue_free()
	_built = null
	_region = region
	var at := ledge_at(region)
	if at == Vector3.INF:
		return
	var root := Node3D.new()
	root.name = "BoostLedge"
	var parent: Node = main.regions.scene if region != "kettle" and main.regions.scene else main
	parent.add_child(root)
	root.global_position = at
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color("1b1d1f")
	rock.roughness = 0.85
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.position = Vector3(0.0, HEIGHT * 0.5 - 0.3, 0.0)
	var sh := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = SIZE + Vector3(0.0, 0.6, 0.0)
	sh.shape = bx
	body.add_child(sh)
	root.add_child(body)
	# One mesh for all of it (a region's draw budget is tight): the block, an amber chevron on
	# each face, and the cache on top until it's opened.
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var block := BoxMesh.new()
	block.size = bx.size
	st.append_from(block, 0, Transform3D(Basis(), body.position))
	st.commit(mesh)
	mesh.surface_set_material(0, rock)
	var marks := SurfaceTool.new()
	marks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bar := BoxMesh.new()
	bar.size = Vector3(0.9, 0.14, 0.04)
	for k in 4:
		var face := Basis(Vector3.UP, k * PI * 0.5)
		for s in [-1.0, 1.0]:
			var arm := Basis(Vector3(0.0, 0.0, 1.0), s * 0.6)
			marks.append_from(bar, 0, Transform3D(face * arm, face * Vector3(s * 0.32, HEIGHT - 0.9, SIZE.z * 0.5 + 0.03)))
	marks.commit(mesh)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = MARK.darkened(0.3)
	glow.emission_enabled = true
	glow.emission = MARK
	glow.emission_energy_multiplier = 1.4
	mesh.surface_set_material(1, glow)
	if not opened(region):
		var crate := SurfaceTool.new()
		crate.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cm := BoxMesh.new()
		cm.size = Vector3(0.9, 0.5, 0.6)
		crate.append_from(cm, 0, Transform3D(Basis(), Vector3(0.0, HEIGHT + 0.25, 0.0)))
		crate.commit(mesh)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color("bf6835")
		mesh.surface_set_material(2, cmat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	_built = root
