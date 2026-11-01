class_name ArcCharge
extends RigidBody3D
## A thrown arc charge: a fist-sized capacitor that bounces, blinks faster as its fuse runs down,
## then discharges in a ring of lightning. It goes off early if it strikes a creature. The blast
## hurts and shoves everything inside it (damage falls off toward the edge) and can nip Juno too.

const FUSE := 1.6
const RADIUS := 5.5
const DAMAGE := 110.0
const SELF_RADIUS := 3.0
const SELF_DAMAGE := 20.0
const KNOCKBACK := 9.0
const COLOR := Color("6ff2dc")

## Who threw it (the blast never damages them for more than SELF_DAMAGE).
var thrower: Node3D
var exploded := false

var _fuse := FUSE
var _light: OmniLight3D
var _core: MeshInstance3D
var _blink := 0.0


func _ready() -> void:
	add_to_group("arc_charges")
	collision_layer = 0
	collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMY
	mass = 0.6
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.35
	bounce.friction = 0.8
	physics_material_override = bounce
	linear_damp = 0.15
	angular_damp = 1.5
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	shape.shape = sphere
	add_child(shape)

	var shell := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.1
	cyl.height = 0.2
	cyl.radial_segments = 10
	shell.mesh = cyl
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("3a3f44")
	metal.metallic = 0.8
	metal.roughness = 0.35
	shell.material_override = metal
	add_child(shell)
	_core = MeshInstance3D.new()
	var band := CylinderMesh.new()
	band.top_radius = 0.106
	band.bottom_radius = 0.106
	band.height = 0.05
	band.radial_segments = 10
	_core.mesh = band
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = COLOR
	_core.material_override = glow
	add_child(_core)

	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.light_energy = 1.2
	_light.omni_range = 2.5
	add_child(_light)
	body_entered.connect(_on_body_entered)


## Throws a new charge from `from` with `velocity`. Returns it.
static func throw(parent: Node, from: Vector3, velocity: Vector3, by: Node3D = null) -> ArcCharge:
	var c := ArcCharge.new()
	c.thrower = by
	parent.add_child(c)
	c.global_position = from
	c.linear_velocity = velocity
	c.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	return c


func _physics_process(delta: float) -> void:
	if exploded:
		return
	_fuse -= delta
	# Blinks faster as the fuse runs out.
	_blink += delta * lerpf(4.0, 22.0, 1.0 - _fuse / FUSE)
	var on := fmod(_blink, 1.0) < 0.5
	_core.visible = on
	_light.light_energy = 1.6 if on else 0.3
	if _fuse <= 0.0:
		detonate()


func _on_body_entered(body: Node) -> void:
	if body is Enemy and not body.dead:
		detonate()
	elif linear_velocity.length() > 2.0:
		Sfx.play("charge_bounce", global_position, -8.0, 0.15)


## Discharges now. Returns how many creatures it hit.
func detonate() -> int:
	if exploded:
		return 0
	exploded = true
	var at := global_position
	var hits := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		var centre := enemy.global_position + Vector3.UP * 0.6
		var d := centre.distance_to(at)
		if d > RADIUS or not _clear_line(at, centre):
			continue
		var dir := (centre - at).normalized() if d > 0.01 else Vector3.UP
		var falloff := 1.0 - (d / RADIUS) * 0.6
		# No direction: a blast wraps around armour plates instead of glancing off them.
		enemy.take_damage(DAMAGE * falloff, centre, Vector3.ZERO)
		if not enemy.dead:
			enemy.velocity += (Vector3(dir.x, 0.0, dir.z).normalized() * KNOCKBACK + Vector3.UP * 3.0) * falloff
		hits += 1
	_hurt_thrower(at)
	_effects(at)
	queue_free()
	return hits


## Rock between the blast and a target shields it.
func _clear_line(a: Vector3, b: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 0.15, b, Game.LAYER_WORLD)
	return space.intersect_ray(q).is_empty()


func _hurt_thrower(at: Vector3) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if not p.has_method("take_damage") or p.dead:
			continue
		var d: float = (p.global_position + Vector3.UP * 0.9).distance_to(at)
		if d < SELF_RADIUS:
			p.take_damage(SELF_DAMAGE * (1.0 - d / SELF_RADIUS * 0.5), at)
		if p.has_method("add_trauma"):
			p.add_trauma(clampf(0.7 - d / 25.0, 0.1, 0.7))


func _effects(at: Vector3) -> void:
	var parent := get_parent()
	Sfx.play("charge_blast", at, 4.0)
	Vfx.burst(parent, at, COLOR, 40, 11.0, 0.14, 0.45, Vector3.UP, 180.0, -2.0)
	Vfx.burst(parent, at, Color("e8fff9"), 18, 5.0, 0.3, 0.2, Vector3.UP, 180.0, 0.0)
	Vfx.burst(parent, at + Vector3.UP * 0.1, Color("8a7d6b"), 22, 4.0, 0.1, 1.1, Vector3.UP, 50.0, -9.0)
	var flash := OmniLight3D.new()
	flash.name = "ChargeFlash"
	flash.light_color = COLOR
	flash.light_energy = 9.0
	flash.omni_range = RADIUS * 1.8
	flash.top_level = true
	parent.add_child(flash)
	flash.global_position = at + Vector3.UP * 0.4
	var t := flash.create_tween()
	t.tween_property(flash, "light_energy", 0.0, 0.35).set_ease(Tween.EASE_OUT)
	t.tween_callback(flash.queue_free)
