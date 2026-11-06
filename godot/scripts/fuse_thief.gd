class_name FuseThief
extends Scuttler
## A scuttler that made off with something shiny. It never fights: it runs from Juno to one of
## its burrows, dives in, and comes up at another far from her. Shoot it while it runs or as it
## surfaces. The loot glows amber on its back so it reads at a distance and in the dark.

enum Flee { RUN, UNDER, TAUNT }

## Just under a sprint, so a chase can be won on foot but a shot is quicker.
const RUN_SPEED := 6.2
const UNDER_TIME := 2.6
## It stops to wait for her when she's this far behind.
const TAUNT_RANGE := 28.0
## A burrow this close to Juno is never a way out.
const SAFE := 9.0

## Burrow mouths, in world space.
var burrows: Array[Vector3] = []
## The name on its health bar.
var thief_name := "THIEF"
var flee := Flee.RUN
var dives := 0
var _goal := -1
var _came_from := -1
var _under := 0.0
var _rethink := 0.0
var _jink := 0.0
var _loot: Node3D


func _init() -> void:
	super()
	max_health = 70.0
	speed = RUN_SPEED


func _setup() -> void:
	super()
	remove_from_group("scuttlers")
	add_to_group("thieves")
	_loot = Node3D.new()
	_loot.name = "Loot"
	_loot.position = Vector3(0.0, 0.95, 0.1)
	add_child(_loot)
	var fuse := MeshInstance3D.new()
	var box := CylinderMesh.new()
	box.top_radius = 0.12
	box.bottom_radius = 0.12
	box.height = 0.5
	fuse.mesh = box
	fuse.rotation.z = PI * 0.5
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ffb347")
	glow.emission_enabled = true
	glow.emission = Color("ffb347")
	glow.emission_energy_multiplier = 4.0
	fuse.material_override = glow
	_loot.add_child(fuse)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb347")
	light.light_energy = 1.4
	light.omni_range = 4.0
	_loot.add_child(light)


func display_name() -> String:
	return thief_name


## Where the visor tracks it: itself, or the burrow it will come up from.
func track_point() -> Vector3:
	if flee == Flee.UNDER and _goal >= 0:
		return burrows[_goal]
	return global_position


func is_under() -> bool:
	return flee == Flee.UNDER


func _physics_process(delta: float) -> void:
	if dead:
		return
	_gravity_step(delta)
	var want := Vector3.ZERO
	match flee:
		Flee.UNDER:
			_under -= delta
			if _under <= 0.0:
				_surface()
			return
		Flee.TAUNT:
			state = State.IDLE
			if _target_alive():
				_face(target.global_position, delta * 4.0)
				if _flat(target.global_position - global_position).length() < TAUNT_RANGE * 0.7:
					flee = Flee.RUN
					Sfx.play("scuttler_alert", global_position, -4.0, 0.15)
		Flee.RUN:
			state = State.CHASE
			want = _run(delta)
	velocity.x = move_toward(velocity.x, want.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, 30.0 * delta)
	move_and_slide()
	_animate(delta)


func _run(delta: float) -> Vector3:
	if burrows.is_empty():
		return Vector3.ZERO
	_rethink -= delta
	if _goal < 0 or _rethink <= 0.0:
		_goal = _pick_burrow()
		_rethink = 1.5
	var to := _flat(burrows[_goal] - global_position)
	if to.length() < 1.2:
		_dive()
		return Vector3.ZERO
	if _target_alive() and _flat(target.global_position - global_position).length() > TAUNT_RANGE:
		flee = Flee.TAUNT
		return Vector3.ZERO
	# A little side-to-side so it isn't a straight-line shot.
	_jink += delta * 5.0
	var side := to.normalized().cross(Vector3.UP) * sin(_jink) * 0.35
	var dir := _steer_around_walls((to.normalized() + side).normalized(), delta)
	_face(global_position + dir, delta * 10.0)
	return dir * RUN_SPEED


## The burrow that best gets away from Juno: far from her, not past her, not the one it left.
func _pick_burrow() -> int:
	var me := global_position
	var her: Vector3 = target.global_position if _target_alive() else me
	var best := -1
	var best_score := -INF
	for i in burrows.size():
		if i == _came_from:
			continue
		var b := burrows[i]
		var from_her := _flat(b - her).length()
		if from_her < SAFE:
			continue
		var away := _flat(me - her).normalized().dot(_flat(b - me).normalized())
		var score := from_her - _flat(b - me).length() * 0.4 + away * 6.0
		if score > best_score:
			best_score = score
			best = i
	return best if best >= 0 else (_came_from + 1) % burrows.size()


func _dive() -> void:
	flee = Flee.UNDER
	dives += 1
	_under = UNDER_TIME
	_came_from = _goal
	Vfx.burst(get_tree().current_scene, global_position + Vector3.UP * 0.2, Color("3b3f42"), 22, 3.0, 0.12, 0.7)
	Sfx.play("rock_impact", global_position, -6.0, 0.1)
	visible = false
	collision_layer = 0
	velocity = Vector3.ZERO
	# Comes up wherever is farthest from her right now.
	_goal = _pick_burrow()


func _surface() -> void:
	_came_from = _goal
	global_position = burrows[_goal] + Vector3.UP * 0.4
	visible = true
	collision_layer = Game.LAYER_ENEMY
	flee = Flee.RUN
	_goal = -1
	Vfx.burst(get_tree().current_scene, global_position, Color("3b3f42"), 22, 3.0, 0.12, 0.7)
	Sfx.play("scuttler_alert", global_position, -2.0, 0.15)


func take_damage(amount: float, point: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO) -> bool:
	if flee == Flee.UNDER:
		return false
	if flee == Flee.TAUNT:
		flee = Flee.RUN
	return super(amount, point, dir)


func alert(_spread := true) -> void:
	hunting = true


func calm() -> void:
	pass
