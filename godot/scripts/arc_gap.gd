class_name ArcGap
extends TimedHazard
## A live drive conduit in the freighter graveyard: two pylon tips crackle, then an arc jumps the
## gap and burns anything in between. Set `span` before adding it to the tree.

@export var span := 4.0
@export var height := 1.2

var _tips: StandardMaterial3D
var _arc: MeshInstance3D
var _sparks: CPUParticles3D
var _light: OmniLight3D


func _init() -> void:
	quiet_time = 2.6
	quiet_jitter = 1.2
	warning_time = 0.8
	active_time = 1.1
	damage_per_second = 44.0


func _build() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("3a3f43")
	metal.metallic = 0.6
	_tips = _glow_mat(Color("9fd8ff"), 0.3)
	for side in [-0.5, 0.5]:
		var pylon := StaticBody3D.new()
		pylon.collision_layer = Game.LAYER_WORLD
		pylon.position = Vector3(side * span, (height + 0.4) * 0.5, 0.0)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.35, height + 0.4, 0.35)
		mesh.mesh = box
		mesh.material_override = metal
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box.size
		shape.shape = box_shape
		pylon.add_child(mesh)
		pylon.add_child(shape)
		add_child(pylon)
		var tip := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.16
		sphere.height = 0.32
		tip.mesh = sphere
		tip.material_override = _tips
		tip.position = Vector3(side * span, height + 0.45, 0.0)
		add_child(tip)
	_arc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = span
	_arc.mesh = cyl
	var arc_mat := _glow_mat(Color("bfe8ff"), 6.0)
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc.material_override = arc_mat
	_arc.rotation.z = PI * 0.5
	_arc.position.y = height
	_arc.visible = false
	add_child(_arc)
	_sparks = _particles(20, 0.4, Color(0.75, 0.9, 1.0, 0.9), 0.12)
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_sparks.emission_box_extents = Vector3(span * 0.5, 0.2, 0.1)
	_sparks.position.y = height
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 1.0
	_sparks.initial_velocity_max = 3.0
	add_child(_sparks)
	_light = OmniLight3D.new()
	_light.light_color = Color("9fd8ff")
	_light.light_energy = 2.5
	_light.omni_range = span + 2.0
	_light.position.y = height
	_light.visible = false
	add_child(_light)


func _zone_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(span - 0.4, 2.2, 1.2)
	return s


func _zone_transform() -> Transform3D:
	return Transform3D(Basis(), Vector3(0.0, 1.1, 0.0))


func _phase_changed(p: Phase) -> void:
	_arc.visible = p == Phase.ACTIVE
	_light.visible = p == Phase.ACTIVE
	_sparks.emitting = p == Phase.ACTIVE
	_tips.emission_energy_multiplier = 0.3 if p == Phase.QUIET else 4.0
	if p == Phase.ACTIVE:
		Sfx.play("arc_zap", global_position + Vector3.UP * height, -2.0, 0.1)


func _warning(t: float) -> void:
	_tips.emission_energy_multiplier = 0.3 + 4.0 * t * (0.6 + 0.4 * sin(t * 40.0))


func _process(_delta: float) -> void:
	if _arc.visible:
		_arc.position.z = randf_range(-0.12, 0.12)
		_arc.scale.x = randf_range(0.6, 1.6)
