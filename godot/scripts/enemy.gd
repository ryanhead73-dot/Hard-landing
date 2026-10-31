class_name Enemy
extends CharacterBody3D
## Shared base for the planet's wildlife: health and damage, the alarm spreading through a pack,
## sight checks, a leash back home, and whisker steering around walls. Subclasses own their
## states, attacks and looks.

signal died(enemy: Enemy)

## Feeler angles in radians, tried in order until one is clear of walls.
const WHISKERS := [0.4, 0.8, 1.2, 1.6, 2.0, 2.4]
const WHISKER_LENGTH := 2.2
const STEER_INTERVAL := 0.2

@export var max_health := 60.0
@export var speed := 5.0
@export var sight_range := 24.0
@export var leash_range := 70.0
@export var alert_radius := 14.0
## Scrap dropped on death: [min pieces, max pieces].
@export var drops := Vector2i(1, 2)

## What it hunts: the player, or a point on Kestrel's hull during a siege.
var target: Node3D
var home := Vector3.ZERO
var health := 60.0
var dead := false
var hunting := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _steer := Vector3.ZERO
var _steer_timer := 0.0
var _steer_side := 0.0
var _flash_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = Game.LAYER_ENEMY
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_ENEMY
	floor_snap_length = 0.3
	# Only ground and wreckage count as floor, so nothing rides along on the player.
	platform_floor_layers = Game.LAYER_WORLD
	max_health *= Game.enemy_health_scale()
	health = max_health
	if home == Vector3.ZERO:
		home = global_position
	_setup()


## Override: build collision and visuals.
func _setup() -> void:
	pass


func is_dead() -> bool:
	return dead


## Applies a hit. Returns true if it killed. `dir` is the direction the shot travelled.
func take_damage(amount: float, point: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO) -> bool:
	if dead:
		return false
	health -= amount * _damage_scale(point, dir)
	_on_hurt(dir)
	_flash()
	if health <= 0.0:
		_die()
		return true
	alert(true)
	return false


## Starts hunting. Nearby wildlife joins in when the alarm spreads.
func alert(spread := true) -> void:
	if dead or not _target_alive():
		return
	if not hunting:
		hunting = true
		_on_alert()
	if spread:
		for other in get_tree().get_nodes_in_group("enemies"):
			if other != self and other.global_position.distance_to(global_position) < alert_radius:
				other.alert(false)


## Gives up and goes home, for example when the player goes down.
func calm() -> void:
	if not dead:
		hunting = false
		_on_calm()


# --- Overrides ----------------------------------------------------------------------------

## Multiplier for incoming damage (armour, weak spots).
func _damage_scale(_point: Vector3, _dir: Vector3) -> float:
	return 1.0


func _on_hurt(_dir: Vector3) -> void:
	pass


func _on_alert() -> void:
	pass


func _on_calm() -> void:
	pass


func _die() -> void:
	dead = true
	hunting = false
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = Game.LAYER_WORLD
	died.emit(self)


# --- Helpers ------------------------------------------------------------------------------

func _target_alive() -> bool:
	return target != null and is_instance_valid(target) and not ("dead" in target and target.dead)


func _can_see_target() -> bool:
	var eye := global_position + Vector3.UP * 0.6
	var chest := target.global_position + Vector3.UP * 1.2
	if eye.distance_to(chest) > sight_range:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, chest, Game.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _out_of_leash(to_target: Vector3) -> bool:
	return _flat(global_position - home).length() > leash_range and to_target.length() > sight_range


func _gravity_step(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta


func _face(point: Vector3, weight: float) -> void:
	var dir := _flat(point - global_position)
	if dir.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(weight, 0.0, 1.0))


func _forward() -> Vector3:
	return -global_basis.z


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


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
		var left := _first_clear_angle(space, origin, want, 1.0)
		var right := _first_clear_angle(space, origin, want, -1.0)
		_steer_side = 1.0 if left < right or (left == right and randf() < 0.5) else -1.0
	var angle := _first_clear_angle(space, origin, want, _steer_side)
	if angle > PI:
		_steer_side = -_steer_side
		angle = _first_clear_angle(space, origin, want, _steer_side)
	_steer = want.rotated(Vector3.UP, angle * _steer_side) if angle <= PI else -want
	return _steer


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


## Registers materials that flash white-hot when hit.
func _flashes(mat: StandardMaterial3D) -> void:
	_flash_mats.append(mat)


func _flash() -> void:
	for m in _flash_mats:
		m.emission_enabled = true
		m.emission = Color("ffd0a0")
		m.emission_energy_multiplier = 1.5
	await get_tree().create_timer(0.07).timeout
	if is_instance_valid(self):
		for m in _flash_mats:
			m.emission_enabled = false


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
