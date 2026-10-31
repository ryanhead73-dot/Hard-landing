class_name Rockfall
extends TimedHazard
## Quarry rockfall: grit trickles and a ring glows on the ground, then a boulder drops into it.

@export var radius := 1.8

var _ring: StandardMaterial3D
var _dust: CPUParticles3D
var _rock: MeshInstance3D


func _init() -> void:
	quiet_time = 5.0
	quiet_jitter = 3.0
	warning_time = 1.3
	active_time = 0.9
	burst_damage = 34.0


func _build() -> void:
	_ring = _glow_mat(Color("d8b48a"), 0.0)
	_ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.albedo_color.a = 0.0
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.15
	torus.outer_radius = radius
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.position.y = 0.04
	ring.material_override = _ring
	add_child(ring)
	_dust = _particles(14, 1.2, Color(0.75, 0.68, 0.6, 0.5), 0.3)
	_dust.position.y = 9.0
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_dust.emission_sphere_radius = radius * 0.6
	_dust.direction = Vector3.DOWN
	_dust.gravity = Vector3(0.0, -9.0, 0.0)
	add_child(_dust)
	_rock = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius * 0.7
	sphere.height = radius * 1.2
	sphere.radial_segments = 7
	sphere.rings = 4
	_rock.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("3c4448")
	m.roughness = 0.95
	_rock.material_override = m
	_rock.visible = false
	add_child(_rock)


func _zone_shape() -> Shape3D:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = 2.4
	return s


func _zone_transform() -> Transform3D:
	return Transform3D(Basis(), Vector3(0.0, 1.2, 0.0))


func _phase_changed(p: Phase) -> void:
	_dust.emitting = p == Phase.WARNING
	match p:
		Phase.QUIET:
			_rock.visible = false
			_ring.albedo_color.a = 0.0
			_ring.emission_energy_multiplier = 0.0
		Phase.ACTIVE:
			_rock.visible = true
			_rock.position.y = 0.4
			_rock.rotation = Vector3(randf(), randf(), randf()) * TAU
			Sfx.play("rock_impact", global_position, 0.0, 0.1)


func _warning(t: float) -> void:
	_ring.albedo_color.a = 0.3 + 0.6 * t
	_ring.emission_energy_multiplier = 0.5 + 2.5 * t
	# The boulder is visible on the way down for the last moment of the warning.
	_rock.visible = t > 0.75
	_rock.position.y = lerpf(9.0, 0.4, clampf((t - 0.75) / 0.25, 0.0, 1.0))
