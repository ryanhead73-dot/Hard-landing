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
## Scales every creature's sight (Weather lowers it in a storm).
static var sight_scale := 1.0
@export var leash_range := 70.0
@export var alert_radius := 14.0
## Size of the teal puff it gives off when it dies.
@export var death_puff := 1.0
## Scrap dropped on death: [min pieces, max pieces].
@export var drops := Vector2i(1, 2)

## Set before adding to the tree to make a named elite: bigger, much tougher, with a health bar.
var elite_name := ""
const ELITE_SCALE := 1.5
## Shots that land on a creature's glowing weak spot (spines, sac, vents, eyes) hit this much harder,
## and ignore armour.
const CRIT_MULT := 1.75
## The weak spot: a point `weak_offset` in the frame of rig joint `weak_joint`, `weak_radius` wide.
var weak_joint := ""
var weak_offset := Vector3.ZERO
var weak_radius := 0.0
## Whether the last hit taken was on the weak spot.
var last_hit_crit := false
var crits_taken := 0
var _weak: Node3D
const ELITE_HEALTH := 4.0
const ELITE_MIN_HEALTH := 280.0

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
var _flash_meshes: Array[MeshInstance3D] = []
## The Blender model (see Rig), under the subclass's visual root.
var _rig: Node3D
var anim: CreatureAnimator
static var _flash_overlay: StandardMaterial3D


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = Game.LAYER_ENEMY
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYER | Game.LAYER_ENEMY
	floor_snap_length = 0.3
	# Only ground and wreckage count as floor, so nothing rides along on the player.
	platform_floor_layers = Game.LAYER_WORLD
	if home == Vector3.ZERO:
		home = global_position
	_setup()
	if elite_name != "":
		_make_elite()
	max_health *= Game.enemy_health_scale()
	health = max_health


## The name on its health bar.
func display_name() -> String:
	return elite_name


func is_elite() -> bool:
	return elite_name != ""


func _make_elite() -> void:
	max_health = maxf(max_health * ELITE_HEALTH, ELITE_MIN_HEALTH)
	drops = Vector2i(drops.x + 6, drops.y + 8)
	sight_range *= 1.5
	leash_range *= 1.5
	for child in get_children():
		if child is Node3D and not child is CreatureAnimator:
			(child as Node3D).scale *= ELITE_SCALE
			(child as Node3D).position *= ELITE_SCALE
	# A hot glow under it, so it reads as the big one from across the site.
	var halo := OmniLight3D.new()
	halo.light_color = Color("ff7a3a")
	halo.light_energy = 1.6
	halo.omni_range = 4.0
	halo.position = Vector3(0.0, 1.6, 0.0)
	add_child(halo)


## Override: build collision and visuals.
func _setup() -> void:
	pass


func is_dead() -> bool:
	return dead


## Applies a hit. Returns true if it killed. `dir` is the direction the shot travelled.
func take_damage(amount: float, point: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO) -> bool:
	if dead:
		return false
	var mult := _damage_scale(point, dir)
	last_hit_crit = is_weak_hit(point, dir)
	if last_hit_crit:
		mult = maxf(mult, 1.0) * CRIT_MULT
		crits_taken += 1
		_crit_effect(point)
	health -= amount * mult
	_on_hurt(dir)
	_flash()
	if health > 0.0:
		_anim("hurt")
	if health <= 0.0:
		_die()
		return true
	alert(true)
	return false


## Where the weak spot is now, or Vector3.INF when it has none or it is hidden.
func weak_spot() -> Vector3:
	if _weak == null or not is_instance_valid(_weak) or not _weak_open():
		return Vector3.INF
	return _weak.global_transform * weak_offset


## True when a shot (not a blast: blasts have no direction) at `point` lands on the weak spot.
func is_weak_hit(point: Vector3, dir: Vector3) -> bool:
	if dir == Vector3.ZERO:
		return false
	var at := weak_spot()
	if at == Vector3.INF:
		return false
	return point.distance_to(at) <= weak_radius * (ELITE_SCALE if is_elite() else 1.0)


func _crit_effect(point: Vector3) -> void:
	if not is_inside_tree():
		return
	Vfx.burst(get_parent(), point, Color("ffd36a"), 14, 5.0, 0.06, 0.3, Vector3.UP, 120.0, -6.0)


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


## Whether the weak spot can be hit right now.
func _weak_open() -> bool:
	return true


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
	if is_inside_tree():
		Vfx.death(get_parent(), global_position, death_puff)
		# A named kill lands hard: a longer freeze and a heavy shake.
		if is_elite() or display_name() == "THE WARDEN":
			get_tree().call_group("player", "big_kill")
	died.emit(self)


# --- Helpers ------------------------------------------------------------------------------

func _target_alive() -> bool:
	return target != null and is_instance_valid(target) and not ("dead" in target and target.dead)


func _can_see_target() -> bool:
	var eye := global_position + Vector3.UP * 0.6
	var chest := target.global_position + Vector3.UP * 1.2
	if eye.distance_to(chest) > sight_range * sight_scale:
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


## Every mesh of a rig flashes when hit (an additive overlay, so the rig's own materials stay).
func _flash_rig(root: Node) -> void:
	_flash_meshes.append_array(Rig.meshes(root))


## Loads a creature's model under `parent` and registers it for hit flashes.
func _load_rig(model: String, parent: Node3D) -> Node3D:
	_rig = Rig.spawn(model, parent)
	if weak_joint != "":
		_weak = Rig.joint(_rig, weak_joint)
	_flash_rig(_rig)
	anim = CreatureAnimator.new()
	anim.name = "Animator"
	add_child(anim)
	anim.setup(self, _rig, model)
	return _rig


## The state name the animator poses for ("idle", "windup", "charge", "open", "dead"...).
func anim_state() -> String:
	return "dead" if dead else "idle"


func _anim(shot: String) -> void:
	if anim:
		anim.trigger(shot)


func _flash() -> void:
	if _flash_overlay == null:
		_flash_overlay = StandardMaterial3D.new()
		_flash_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_overlay.albedo_color = Color(1.0, 0.8, 0.6, 0.55)
	for m in _flash_mats:
		m.emission_enabled = true
		m.emission = Color("ffd0a0")
		m.emission_energy_multiplier = 1.5
	for mesh in _flash_meshes:
		mesh.material_overlay = _flash_overlay
	await get_tree().create_timer(0.07).timeout
	if is_instance_valid(self):
		for m in _flash_mats:
			m.emission_enabled = false
		for mesh in _flash_meshes:
			if is_instance_valid(mesh):
				mesh.material_overlay = null


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
