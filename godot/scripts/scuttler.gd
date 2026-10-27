class_name Scuttler
extends CharacterBody3D
## Basalt scuttler: native fauna that hides as rock until something gets close, then rushes it.
## Readable at distance by its teal spine glow. Telegraphs every bite with a crouch before lunging.

signal died(scuttler: Scuttler)

enum State { IDLE, CHASE, WINDUP, RECOVER, DEAD }

## Feeler angles in radians, tried in order until one is clear of walls.
const WHISKERS := [0.4, 0.8, 1.2, 1.6, 2.0, 2.4]
const WHISKER_LENGTH := 2.2
const STEER_INTERVAL := 0.2

@export var max_health := 60.0
@export var speed := 5.0
@export var attack_damage := 14.0
@export var attack_range := 1.9
@export var windup_time := 0.45
@export var recover_time := 0.7
@export var sight_range := 24.0
@export var leash_range := 70.0
@export var alert_radius := 14.0

var target: Node3D
var home := Vector3.ZERO
var health := 60.0
var state := State.IDLE

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _timer := 0.0
var _wander := Vector3.ZERO
var _steer := Vector3.ZERO
var _steer_timer := 0.0
var _steer_side := 0.0
var _gait := 0.0
var _visual: Node3D
var _glow: StandardMaterial3D
var _shell: StandardMaterial3D


func _ready() -> void:
	add_to_group("scuttlers")
	collision_layer = Game.LAYER_ENEMY
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_ENEMY
	floor_snap_length = 0.3
	# Only ground and wreckage count as floor, so a scuttler never rides along on the player.
	platform_floor_layers = Game.LAYER_WORLD
	health = max_health
	if home == Vector3.ZERO:
		home = global_position
	_wander = home
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	shape.shape = sphere
	shape.position.y = 0.55
	add_child(shape)
	_build_visual()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_timer -= delta
	var flat_vel := Vector3.ZERO
	match state:
		State.IDLE:
			flat_vel = _idle()
		State.CHASE:
			flat_vel = _chase(delta)
		State.WINDUP:
			_face(target.global_position, delta * 3.0)
			if _timer <= 0.0:
				_lunge()
		State.RECOVER:
			flat_vel = Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 14.0 * delta)
			if _timer <= 0.0:
				state = State.CHASE
		State.DEAD:
			flat_vel = Vector3.ZERO
	if state != State.RECOVER:
		velocity.x = move_toward(velocity.x, flat_vel.x, 25.0 * delta)
		velocity.z = move_toward(velocity.z, flat_vel.z, 25.0 * delta)
	else:
		velocity.x = flat_vel.x
		velocity.z = flat_vel.z
	move_and_slide()
	_animate(delta)


func take_damage(amount: float, _point: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO) -> bool:
	if state == State.DEAD:
		return false
	health -= amount
	velocity += Vector3(dir.x, 0.0, dir.z).normalized() * 1.5
	_flash()
	Sfx.play("scuttler_hurt", global_position, -6.0, 0.15)
	if health <= 0.0:
		_die()
		return true
	alert(true)
	return false


## Starts hunting the target. Nearby scuttlers join in when the alarm spreads.
func alert(spread := true) -> void:
	if state == State.DEAD or target == null:
		return
	if state == State.IDLE:
		state = State.CHASE
		Sfx.play("scuttler_alert", global_position, -2.0, 0.15)
	if spread:
		for other in get_tree().get_nodes_in_group("scuttlers"):
			if other != self and other.global_position.distance_to(global_position) < alert_radius:
				other.alert(false)


## Gives up and walks home, for example when the player goes down.
func calm() -> void:
	if state != State.DEAD:
		state = State.IDLE
		_wander = home


func _idle() -> Vector3:
	if target and _can_see_target():
		alert()
		return Vector3.ZERO
	if _flat(global_position).distance_to(_flat(_wander)) < 0.8:
		if _timer <= 0.0:
			var a := randf() * TAU
			_wander = home + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.0, 6.0)
			_timer = randf_range(1.5, 4.0)
		return Vector3.ZERO
	var dir := _flat(_wander - global_position).normalized()
	_face(global_position + dir, 0.1)
	return dir * speed * 0.3


func _chase(delta: float) -> Vector3:
	if target == null or ("dead" in target and target.dead):
		calm()
		return Vector3.ZERO
	var to_target := _flat(target.global_position - global_position)
	if to_target.length() < attack_range and is_on_floor():
		state = State.WINDUP
		_timer = windup_time
		Sfx.play("scuttler_lunge", global_position, -4.0, 0.1)
		return Vector3.ZERO
	if _flat(global_position - home).length() > leash_range and to_target.length() > sight_range:
		calm()
		return Vector3.ZERO
	var dir := _steer_around_walls(to_target.normalized(), delta)
	_face(global_position + dir, delta * 10.0)
	return dir * speed


## Short feelers find a clear heading around walls and wreckage. Once it picks a side of an
## obstacle it keeps to that side until the way ahead is clear, so it doesn't dither.
func _steer_around_walls(want: Vector3, delta: float) -> Vector3:
	_steer_timer -= delta
	if _steer_timer > 0.0 and _steer != Vector3.ZERO:
		return _steer
	_steer_timer = STEER_INTERVAL
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.5
	if _whisker_clear(space, origin, want):
		_steer_side = 0.0
		_steer = want
		return want
	if _steer_side == 0.0:
		# New obstacle: go round whichever side opens up sooner.
		var left := _first_clear_angle(space, origin, want, 1.0)
		var right := _first_clear_angle(space, origin, want, -1.0)
		_steer_side = 1.0 if left < right or (left == right and randf() < 0.5) else -1.0
	var angle := _first_clear_angle(space, origin, want, _steer_side)
	if angle > PI:
		_steer_side = -_steer_side
		angle = _first_clear_angle(space, origin, want, _steer_side)
	_steer = want.rotated(Vector3.UP, angle * _steer_side) if angle <= PI else -want
	return _steer


## The smallest whisker angle on one side that is clear, or INF if none are.
func _first_clear_angle(space: PhysicsDirectSpaceState3D, origin: Vector3, want: Vector3, side: float) -> float:
	for angle in WHISKERS:
		if _whisker_clear(space, origin, want.rotated(Vector3.UP, angle * side)):
			return angle
	return INF


func _whisker_clear(space: PhysicsDirectSpaceState3D, origin: Vector3, heading: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + heading * WHISKER_LENGTH, Game.LAYER_WORLD)
	var hit := space.intersect_ray(query)
	# Walkable slopes are not obstacles.
	return hit.is_empty() or (hit.normal as Vector3).y > 0.6


func _lunge() -> void:
	state = State.RECOVER
	_timer = recover_time
	var to_target := _flat(target.global_position - global_position)
	velocity += to_target.normalized() * 7.0
	if to_target.length() < attack_range + 0.6 and target.has_method("take_damage"):
		target.take_damage(attack_damage, global_position)


func _can_see_target() -> bool:
	var eye := global_position + Vector3.UP * 0.6
	var chest := target.global_position + Vector3.UP * 1.2
	if eye.distance_to(chest) > sight_range:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, chest, Game.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _die() -> void:
	state = State.DEAD
	remove_from_group("scuttlers")
	collision_layer = 0
	collision_mask = Game.LAYER_WORLD
	died.emit(self)
	Sfx.play("scuttler_death", global_position, 0.0, 0.1)
	_glow.emission_energy_multiplier = 0.0
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3(1.2, 0.25, 1.2), 0.25)
	tween.tween_interval(2.5)
	tween.tween_property(_visual, "position:y", -0.6, 1.0)
	tween.tween_callback(queue_free)


func _face(point: Vector3, weight: float) -> void:
	var dir := _flat(point - global_position)
	if dir.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(weight, 0.0, 1.0))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _flash() -> void:
	_shell.emission_enabled = true
	_shell.emission = Color("ffd0a0")
	_shell.emission_energy_multiplier = 1.5
	await get_tree().create_timer(0.07).timeout
	if is_instance_valid(self):
		_shell.emission_enabled = false


func _animate(delta: float) -> void:
	if state == State.DEAD:
		return
	var moving := Vector2(velocity.x, velocity.z).length()
	_gait += delta * (4.0 + moving * 3.0)
	var crouch := 0.0
	if state == State.WINDUP:
		crouch = -0.18 * (1.0 - _timer / windup_time)
	_visual.position.y = absf(sin(_gait)) * 0.06 * minf(moving, 1.0) + crouch
	_glow.emission_energy_multiplier = 4.0 if state == State.WINDUP else (2.0 if state != State.IDLE else 0.8)


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_shell = StandardMaterial3D.new()
	_shell.albedo_color = Color("1e2124")
	_shell.roughness = 0.9
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color("3fd1b5")
	_glow.emission_enabled = true
	_glow.emission = Color("3fd1b5")
	var carapace := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 0.8
	sphere.radial_segments = 7
	sphere.rings = 4
	carapace.mesh = sphere
	carapace.material_override = _shell
	carapace.position.y = 0.55
	carapace.scale = Vector3(1.0, 1.0, 1.3)
	_visual.add_child(carapace)
	for i in 4:
		var spine := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.08, 0.25, 0.08)
		spine.mesh = box
		spine.material_override = _glow
		spine.position = Vector3(0.0, 0.92, -0.35 + i * 0.25)
		spine.rotation.x = -0.4
		_visual.add_child(spine)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.06
		eye_mesh.height = 0.12
		eye.mesh = eye_mesh
		eye.material_override = _glow
		eye.position = Vector3(0.18 * side, 0.6, -0.75)
		_visual.add_child(eye)
		for j in 3:
			var leg := MeshInstance3D.new()
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(0.6, 0.07, 0.07)
			leg.mesh = leg_mesh
			leg.material_override = _shell
			leg.position = Vector3(0.55 * side, 0.3, -0.35 + j * 0.35)
			leg.rotation.z = 0.5 * side
			_visual.add_child(leg)
