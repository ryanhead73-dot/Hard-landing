class_name UtilityDrone
extends Node3D
## The landing gear's reward (production pack, repair 4): a utility drone docked on a station in
## Kestrel's cargo bay, launched from it once the ship stands level. Out, it rides at Juno's
## shoulder wherever she goes (regions included); it flies out to scrap, ammo and supplies she
## leaves on the ground and sends them to her, and when she's badly hurt it sprays a med-seal
## patch over her suit (once a minute). Docking it at the station puts it away again.
## State: Game.flags.drone_out.

const FOLLOW := Vector3(0.75, 2.1, 0.45)
const FETCH_RANGE := 16.0
const SPEED := 9.0
const PATCH_BELOW := 0.35
const PATCH_HEAL := 30.0
const PATCH_COOLDOWN := 60.0
const AMBER := Color("ffb24d")

var player: Node3D
## Pickups sent her way, and patches given (tests read these).
var fetched := 0
var patches := 0
var patch_cool := 0.0
var _goal: Node3D
var _look := 0.0
var _rotors: Array[MeshInstance3D] = []
var _eye: StandardMaterial3D


func _ready() -> void:
	top_level = true
	name = "UtilityDrone"
	_build()
	if player:
		global_position = player.global_position + FOLLOW


func _build() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color("d9d2c2")
	shell.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("3a3d42")
	dark.metallic = 0.5
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.14, 0.42)
	body.mesh = bm
	body.material_override = shell
	add_child(body)
	_eye = StandardMaterial3D.new()
	_eye.albedo_color = AMBER.darkened(0.4)
	_eye.emission_enabled = true
	_eye.emission = AMBER
	_eye.emission_energy_multiplier = 2.0
	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.18, 0.05, 0.02)
	eye.mesh = em
	eye.material_override = _eye
	eye.position = Vector3(0.0, 0.0, -0.22)
	add_child(eye)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var arm := MeshInstance3D.new()
			var am := BoxMesh.new()
			am.size = Vector3(0.22, 0.03, 0.03)
			arm.mesh = am
			arm.material_override = dark
			arm.position = Vector3(x * 0.22, 0.03, z * 0.2)
			add_child(arm)
			var rotor := MeshInstance3D.new()
			var rm := CylinderMesh.new()
			rm.top_radius = 0.12
			rm.bottom_radius = 0.12
			rm.height = 0.01
			rm.radial_segments = 10
			rotor.mesh = rm
			var rmat := StandardMaterial3D.new()
			rmat.albedo_color = Color(0.2, 0.2, 0.22, 0.45)
			rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rotor.material_override = rmat
			rotor.position = Vector3(x * 0.32, 0.06, z * 0.28)
			add_child(rotor)
			_rotors.append(rotor)


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	patch_cool = maxf(patch_cool - delta, 0.0)
	var dead: bool = "dead" in player and player.dead
	if not dead:
		_tend(delta)
	var aim: Vector3
	if _goal and is_instance_valid(_goal):
		aim = _goal.global_position + Vector3.UP * 1.0
		if global_position.distance_to(aim) < 0.8:
			_send(_goal)
			_goal = null
	else:
		_goal = null
		var back: Basis = player.global_basis
		aim = player.global_position + back * FOLLOW
		if not dead and Engine.get_physics_frames() % 24 == 0:
			_goal = _find_pickup()
	var to := aim - global_position
	# A teleport (a respawn, a region) and it catches up at once.
	if to.length() > 40.0:
		global_position = aim
	else:
		global_position += to.normalized() * minf(to.length(), (SPEED if _goal else maxf(to.length() * 4.0, 1.0)) * delta)
	global_position.y += sin(Time.get_ticks_msec() * 0.004) * 0.002
	var flat := Vector2(to.x, to.z)
	if flat.length() > 0.3:
		_look = lerp_angle(_look, atan2(-flat.x, -flat.y), clampf(6.0 * delta, 0.0, 1.0))
	rotation = Vector3(-clampf(to.length() * 0.05, 0.0, 0.25), _look, 0.0)
	for r in _rotors:
		r.rotation.y += delta * 40.0


## The nearest thing on the ground she'd want, within reach of her.
func _find_pickup() -> Node3D:
	var best: Node3D = null
	var best_d := FETCH_RANGE
	for p in get_tree().get_nodes_in_group("scrap"):
		if not (p is ScrapPickup) or not p.is_visible_in_tree():
			continue
		if not (p as ScrapPickup)._wanted():
			continue
		var d: float = p.global_position.distance_to(player.global_position)
		if d < best_d and d > (p as ScrapPickup).magnet_range:
			best_d = d
			best = p
	return best


## Sends a pickup homing in on her.
func _send(p: Node3D) -> void:
	if not (p is ScrapPickup):
		return
	var sp := p as ScrapPickup
	sp.target = player
	sp.magnet_range = 80.0
	fetched += 1
	Sfx.play("ui_click", global_position, -10.0, 0.2)


## Patches her suit when she's badly hurt.
func _tend(_delta: float) -> void:
	if patch_cool > 0.0 or not player.has_method("max_health"):
		return
	if player.health < player.max_health() * PATCH_BELOW:
		player.health = minf(player.health + PATCH_HEAL, player.max_health())
		patch_cool = PATCH_COOLDOWN
		patches += 1
		Sfx.play("med_seal", global_position, -4.0, 0.0)
		var tree := get_tree()
		var main := tree.current_scene if tree else null
		if main and main.get("hud"):
			main.hud.show_message("The drone sprays a med-seal patch across your suit.")
