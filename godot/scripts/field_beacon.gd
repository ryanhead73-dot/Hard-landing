class_name FieldBeacon
extends Node
## The wing repair's reward (production pack, repair 5): a short-range outdoor beacon Juno plants
## from the suit scanner (B, or Place beacon in the inventory). One at a time; planting it again
## moves it. It stands as an amber pole with a pale light column, shows on the compass, the
## scanner and the map, and while it stands in the region she's in, going down brings her back
## up beside it instead of at Kestrel or the region's way in.
## State in Game.flags: beacon_region (String, "" = none) and beacon_at ([x, y, z] world).

const COLOR := Color("ffd06a")
const COLUMN := Color("ffe6b0")
## Not too close to a gate, a door or the ship.
const SHIP_CLEAR := 14.0

var main: Node
var visual: Node3D
var placed := 0


func setup(m: Node) -> void:
	main = m
	main.regions.travelled.connect(func(_from: String, _to: String): _rebuild())
	Game.flag_changed.connect(func(id: String, _v: Variant):
		if id == "beacon_region" or id == "beacon_at":
			_rebuild())
	_rebuild.call_deferred()


func unlocked() -> bool:
	return Game.is_repaired("wing")


## Why she can't plant it here, or "" if she can.
func blocked_reason() -> String:
	if not unlocked():
		return "The scanner has no beacon until the wing is fitted"
	var p: Player = main.player
	if p == null or p.dead or not p.is_on_floor():
		return "Plant the beacon on solid ground"
	if main.regions.travelling or main.regions.current == "approach" or Game.launched:
		return "Not now"
	if main.regions.in_kettle() and (main.kestrel.is_inside(p.global_position) or p.global_position.distance_to(main.kestrel.global_position) < SHIP_CLEAR):
		return "Kestrel doesn't need a beacon: plant it out on the ground"
	return ""


func place() -> bool:
	var why := blocked_reason()
	if why != "":
		main.hud.show_message(why)
		return false
	var at: Vector3 = main.player.global_position
	Game.set_flag("beacon_region", main.regions.current)
	Game.set_flag("beacon_at", [at.x, at.y, at.z])
	placed += 1
	Sfx.play("beacon_plant", at + Vector3.UP, 0.0, 0.0)
	main.hud.show_message("Beacon planted. If you go down out here, you'll come back up beside it.")
	return true


## The beacon's position if it stands in the region Juno is in, else null.
func here() -> Variant:
	var region: String = Game.flags.get("beacon_region", "")
	var at: Variant = Game.flags.get("beacon_at")
	if region == "" or region != main.regions.current or not (at is Array) or (at as Array).size() != 3:
		return null
	return Vector3(float(at[0]), float(at[1]), float(at[2]))


## Where she comes back up beside it.
func respawn_point() -> Variant:
	var at: Variant = here()
	if at == null:
		return null
	return (at as Vector3) + Vector3(1.2, 0.5, 1.2)


func _rebuild() -> void:
	if visual and is_instance_valid(visual):
		if visual.get_parent():
			visual.get_parent().remove_child(visual)
		visual.queue_free()
	visual = null
	if main == null:
		return
	var at: Variant = here()
	if at == null:
		return
	visual = _build()
	# Under the region scene, so it goes when the region does; under main in the Kettle (hidden
	# with the basin while she's away).
	var parent: Node = main.regions.scene if main.regions.scene else main
	parent.add_child(visual)
	visual.global_position = at


func _build() -> Node3D:
	var root := Node3D.new()
	root.name = "BeaconPost"
	root.set_meta("no_batch", true)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("6a6e74")
	metal.metallic = 0.6
	metal.roughness = 0.45
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.06
	cm.height = 1.6
	cm.radial_segments = 8
	pole.mesh = cm
	pole.material_override = metal
	pole.position.y = 0.8
	root.add_child(pole)
	# Three splayed feet and an amber lamp head, one mesh each, then the light column.
	var foot := BoxMesh.new()
	foot.size = Vector3(0.05, 0.05, 0.6)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var a := i * TAU / 3.0
		st.append_from(foot, 0, Transform3D(Basis(Vector3.UP, a).rotated(Vector3(cos(a), 0.0, -sin(a)), 0.5), Vector3(sin(a) * 0.22, 0.15, cos(a) * 0.22)))
	var feet := MeshInstance3D.new()
	feet.mesh = st.commit()
	feet.material_override = metal
	root.add_child(feet)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 10
	sm.rings = 5
	lamp.mesh = sm
	var lm := StandardMaterial3D.new()
	lm.albedo_color = COLOR.darkened(0.3)
	lm.emission_enabled = true
	lm.emission = COLOR
	lm.emission_energy_multiplier = 3.0
	lamp.material_override = lm
	lamp.position.y = 1.7
	lamp.name = "Lamp"
	root.add_child(lamp)
	var column := MeshInstance3D.new()
	var col := CylinderMesh.new()
	col.top_radius = 0.25
	col.bottom_radius = 0.12
	col.height = 40.0
	col.radial_segments = 8
	col.cap_top = false
	col.cap_bottom = false
	column.mesh = col
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.albedo_color = Color(COLUMN, 0.22)
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	column.material_override = cmat
	column.position.y = 21.7
	column.name = "Column"
	root.add_child(column)
	var blink := root.create_tween().set_loops()
	blink.tween_property(lm, "emission_energy_multiplier", 0.6, 0.5)
	blink.tween_property(lm, "emission_energy_multiplier", 3.0, 0.1)
	blink.tween_interval(0.6)
	return root
