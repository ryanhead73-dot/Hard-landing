class_name SporePod
extends TimedHazard
## Moss-field spore pod. Walk close or shoot it and it swells, then bursts into a choking cloud
## that hurts anything inside, scuttlers included. It regrows after a while.

const TRIGGER_RADIUS := 2.6

var _pod: MeshInstance3D
var _pod_mat: StandardMaterial3D
var _body: StaticBody3D
var _cloud: CPUParticles3D
var _sense: Area3D
var _burst_once := false


func _init() -> void:
	manual = true
	quiet_time = 18.0
	warning_time = 0.8
	active_time = 4.0
	damage_per_second = 12.0


func _build() -> void:
	add_to_group("spore_pods")
	_body = StaticBody3D.new()
	_body.collision_layer = Game.LAYER_WORLD
	_body.set_meta("on_hit", take_hit)
	add_child(_body)
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.55
	shape.shape = sphere_shape
	shape.position.y = 0.55
	_body.add_child(shape)
	_pod = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.0
	_pod.mesh = sphere
	_pod_mat = _glow_mat(Color("b4e05a"), 0.8)
	_pod.material_override = _pod_mat
	_pod.position.y = 0.5
	add_child(_pod)
	_cloud = _particles(40, 2.0, Color(0.7, 0.85, 0.35, 0.35), 1.6)
	_cloud.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_cloud.emission_sphere_radius = 2.2
	_cloud.position.y = 1.0
	_cloud.gravity = Vector3(0.0, 0.15, 0.0)
	add_child(_cloud)
	_sense = Area3D.new()
	_sense.collision_layer = 0
	_sense.collision_mask = Game.LAYER_PLAYER
	_sense.monitorable = false
	var sense_shape := CollisionShape3D.new()
	var sense_sphere := SphereShape3D.new()
	sense_sphere.radius = TRIGGER_RADIUS
	sense_shape.shape = sense_sphere
	_sense.add_child(sense_shape)
	_sense.body_entered.connect(func(_b): trigger())
	add_child(_sense)


## Shots hit the pod's collider; it bursts instead of taking damage.
func take_hit() -> void:
	trigger()


func _zone_shape() -> Shape3D:
	var s := SphereShape3D.new()
	s.radius = 3.2
	return s


func _zone_transform() -> Transform3D:
	return Transform3D(Basis(), Vector3(0.0, 1.0, 0.0))


func _phase_changed(p: Phase) -> void:
	_cloud.emitting = p == Phase.ACTIVE
	match p:
		Phase.QUIET:
			# Regrowing: shrunk and dull until the cooldown runs out.
			_pod.scale = Vector3.ONE * (0.35 if _burst_once else 1.0)
			_pod_mat.emission_energy_multiplier = 0.8
		Phase.ACTIVE:
			_pod.scale = Vector3.ONE * 0.3
			_burst_once = true
			Sfx.play("spore_burst", global_position, -2.0, 0.1)


func _warning(t: float) -> void:
	_pod.scale = Vector3.ONE * (1.0 + 0.35 * t)
	_pod_mat.emission_energy_multiplier = 0.8 + 4.0 * t


func _process(delta: float) -> void:
	if phase == Phase.QUIET and _pod.scale.x < 1.0:
		_pod.scale = Vector3.ONE * minf(_pod.scale.x + delta * 0.65 / maxf(quiet_time, 0.1), 1.0)
	if phase == Phase.QUIET and _timer <= 0.0 and _sense.has_overlapping_bodies():
		trigger()
