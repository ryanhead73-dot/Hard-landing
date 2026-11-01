class_name BasinCache
extends Node3D
## A drift cache out on the open basin: cargo flung loose when a ship came down, half-buried in
## the basalt, its locator still blinking. The beam shows from a long way off, so it's worth
## stepping off the path for. Some sit in ground the scuttlers have dug into, and prising the
## lid wakes the nest. Wildlife owns these (see wildlife.gd) and saves which are opened.

const COLOR := Color("ffb347")
const BEAM_HEIGHT := 7.0

var index := 0
## A nest is dug in around it: opening it brings the pack up out of the ground.
var guarded := false
var opened := false

var _lid: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _light: OmniLight3D
var _blink := 0.0


func _ready() -> void:
	add_to_group("basin_caches")
	var holder := Node3D.new()
	# Half-sunk and canted, the way it landed.
	holder.position = Vector3(0.0, -0.18, 0.0)
	holder.rotation = Vector3(deg_to_rad(7.0 + index * 3 % 6), 0.0, deg_to_rad(-9.0 + index * 5 % 12))
	add_child(holder)
	var crate := Rig.spawn("crate", holder)
	_lid = Rig.own_material(crate, "lid_glow")
	if _lid:
		_lid.emission = COLOR
		_lid.albedo_color = COLOR.darkened(0.4)

	var body := StaticBody3D.new()
	body.name = "DriftCache"
	body.collision_layer = Game.LAYER_WORLD
	body.position = Vector3(0.0, 0.25, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 0.7, 0.9)
	shape.shape = box
	body.add_child(shape)
	add_child(body)

	# The locator: a thin column of light and a blinking lamp.
	_beam = MeshInstance3D.new()
	_beam.name = "Locator"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.13
	cyl.height = BEAM_HEIGHT
	cyl.radial_segments = 6
	cyl.rings = 1
	_beam.mesh = cyl
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(COLOR, 0.35)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3(0.0, BEAM_HEIGHT * 0.5 + 0.4, 0.0)
	add_child(_beam)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.omni_range = 4.0
	_light.position = Vector3(0.0, 0.9, 0.0)
	add_child(_light)
	_blink = index * 0.37
	if opened:
		_go_dark()


func _process(delta: float) -> void:
	if opened:
		return
	_blink += delta
	var on := fmod(_blink, 1.6) < 0.18
	_light.light_energy = 2.2 if on else 0.35
	_beam_mat.albedo_color.a = 0.42 if on else 0.24


## Pops the lid. Returns false if it was already open.
func open() -> bool:
	if opened:
		return false
	opened = true
	_go_dark()
	if is_inside_tree():
		Sfx.play("scrap_pickup", global_position, 0.0, 0.1)
		Vfx.burst(get_parent(), global_position + Vector3.UP * 0.6, COLOR, 14, 2.5, 0.06, 0.5)
	return true


## Opened already (loading a save): no light, no beam.
func set_opened() -> void:
	opened = true
	if is_inside_tree():
		_go_dark()


func _go_dark() -> void:
	_beam.visible = false
	_light.visible = false
	if _lid:
		_lid.emission_energy_multiplier = 0.0
