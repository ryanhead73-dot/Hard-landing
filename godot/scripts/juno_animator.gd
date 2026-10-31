class_name JunoAnimator
extends Node
## Juno's procedural animation. Every frame it builds a pose for her rig from what the player is
## doing: a walk or run cycle driven by ground speed (so feet keep pace at any speed), crouch,
## jump and fall, aim pitch, recoil, reload, carrying, hurt flinches and falling down when the suit
## gives out. One-shot actions (install, interact, stim) blend in over the top with play().
##
## Angles are degrees in each joint's parent space: +x swings a limb forward (or tips the torso
## back), -x on a shin or forearm bends the knee back / the elbow up.

const STRIDE := 3.2  ## Metres per full walk cycle (two footsteps).
const ACTIONS := {"install": 1.4, "interact": 0.8, "stim": 0.9}
## Two-handed actions put the weapon away while they play.
const TWO_HANDED := ["install"]

var player: Player
var pose: RigPose
var state := "idle"
var action := ""
var phase := 0.0

var _action_t := 0.0
var _walk := 0.0
var _run := 0.0
var _crouch := 0.0
var _air := 0.0
var _aim := 0.0
var _recoil := 0.0
var _flinch := 0.0
var _reload := 0.0
var _carry := 0.0
var _down := 0.0
var _time := 0.0
var _weapon_rest := Vector3.ZERO


func setup(p: Player, rig: Node3D) -> void:
	player = p
	pose = RigPose.new(rig)
	_weapon_rest = p.weapon.position
	p.weapon.fired.connect(func(): _recoil = 1.0)
	p.damaged.connect(func(_a): _flinch = 1.0)


## Starts a one-shot action ("install", "interact", "stim"). Returns false for unknown names.
func play(action_name: String) -> bool:
	if not ACTIONS.has(action_name) or player.dead:
		return false
	action = action_name
	_action_t = 0.0
	return true


func _process(delta: float) -> void:
	if player == null or pose == null:
		return
	_time += delta
	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	var grounded := player.is_on_floor()
	var k := clampf(delta * 10.0, 0.0, 1.0)
	_walk = lerpf(_walk, clampf(hv / player.walk_speed, 0.0, 1.0) if grounded else 0.0, k)
	_run = lerpf(_run, clampf((hv - player.walk_speed) / (player.sprint_speed - player.walk_speed), 0.0, 1.0) if grounded else 0.0, k)
	_crouch = lerpf(_crouch, 1.0 if player.crouching else 0.0, k)
	_air = lerpf(_air, 0.0 if grounded else 1.0, clampf(delta * 8.0, 0.0, 1.0))
	_aim = lerpf(_aim, 1.0 if (player.aiming or player._combat_face > 0.0) else 0.0, k)
	_carry = lerpf(_carry, 1.0 if Game.carrying != "" else 0.0, k)
	_reload = lerpf(_reload, 1.0 if player.weapon.reloading else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	_recoil = maxf(_recoil - delta * 9.0, 0.0)
	_flinch = maxf(_flinch - delta * 5.0, 0.0)
	_down = move_toward(_down, 1.0 if player.dead else 0.0, delta * (1.6 if player.dead else 99.0))
	if grounded:
		phase = fmod(phase + hv / STRIDE * TAU * delta, TAU)
	if action != "":
		_action_t += delta
		if _action_t >= ACTIONS[action] or player.dead:
			action = ""
	state = _state_name(hv, grounded)
	_apply(_base_pose())


func _state_name(hv: float, grounded: bool) -> String:
	if player.dead:
		return "down"
	if not grounded:
		return "jump" if player.velocity.y > 0.0 else "fall"
	if player.crouching:
		return "crouch"
	if hv > player.walk_speed + 0.5:
		return "run"
	if hv > 0.4:
		return "walk"
	return "idle"


func _base_pose() -> Dictionary:
	var p := {}
	var s := sin(phase)
	var amp := 26.0 * _walk + 14.0 * _run
	amp *= 1.0 - 0.5 * _crouch
	var bend := 18.0 * _walk + 30.0 * _run
	var breathe := sin(_time * 1.8) * (1.0 - _walk)

	# Legs: swing from the hip, knee bends as the foot comes through. Crouch folds both.
	for side in [["L", 0.0], ["R", PI]]:
		var ls := sin(phase + side[1])
		var lift := maxf(0.0, sin(phase + side[1] + 1.6))
		var leg := ls * amp + 78.0 * _crouch
		var shin := -lift * bend - 6.0 * _walk - 118.0 * _crouch
		if side[0] == "L":
			leg += 30.0 * _air
			shin -= 55.0 * _air
		else:
			leg -= 12.0 * _air
			shin -= 25.0 * _air
		p["Leg" + side[0]] = Vector3(leg, 0.0, 0.0)
		p["Shin" + side[0]] = Vector3(shin, 0.0, 0.0)

	# Torso: a bob and twist with the stride, lean into a run, a crouch, or a heavy pack.
	var bob := absf(cos(phase)) * (0.035 * _walk + 0.03 * _run) - 0.02 * _walk
	p["Hips"] = Vector3(0.0, s * 5.0 * _walk, 0.0)
	p["@Hips"] = Vector3(0.0, bob - 0.52 * _crouch, 0.0)
	var pitch := rad_to_deg(player._pitch.rotation.x)
	var lean := -10.0 * _run - 38.0 * _crouch - 7.0 * _carry
	p["Spine"] = Vector3(lean + breathe * 1.2, -s * 4.0 * _walk, 0.0)
	p["Chest"] = Vector3(clampf(pitch * 0.55, -30.0, 30.0) * _aim + 5.0 * _recoil + 9.0 * _flinch - lean * 0.35 * _crouch, 0.0, 0.0)
	p["Head"] = Vector3(clampf(pitch * 0.35, -25.0, 25.0) - 14.0 * _reload - 8.0 * _flinch, 0.0, sin(_time * 0.7) * 2.0 * (1.0 - _walk))

	# Arms hold the weapon: right hand on the grip, left supporting it. Reloading drops the left
	# hand to the magazine; recoil kicks both.
	var kick := 6.0 * _recoil
	p["ArmR"] = Vector3(12.0 + 10.0 * _aim - kick, 0.0, 0.0)
	p["ForearmR"] = Vector3(57.0 + 8.0 * _aim, 0.0, 0.0)
	var reload_wiggle := sin(_time * 9.0) * 8.0 * _reload
	p["ArmL"] = Vector3(lerpf(46.0 + 8.0 * _aim - kick, 18.0, _reload), 0.0, lerpf(38.0, 22.0, _reload))
	p["ForearmL"] = Vector3(lerpf(10.0, 72.0 + reload_wiggle, _reload), 0.0, 0.0)
	p["@Weapon"] = Vector3(0.0, -0.04 * _reload, 0.07 * _recoil)
	p["#Weapon"] = Vector3(0.0, 0.0, 28.0 * _reload)

	if action != "":
		_blend_action(p)

	# Down: she topples backwards and lies still, arms out.
	if _down > 0.0:
		var e := ease(_down, -2.0)
		p["#Root"] = Vector3(-84.0 * e, 0.0, 0.0)
		p["@Root"] = Vector3(0.0, 0.16 * e, 0.0)
		for j in ["ArmL", "ArmR"]:
			var sgn := -1.0 if j == "ArmL" else 1.0
			p[j] = p[j].lerp(Vector3(10.0, 0.0, 55.0 * sgn), e)
		p["ForearmL"] = p["ForearmL"].lerp(Vector3(20.0, 0.0, 0.0), e)
		p["ForearmR"] = p["ForearmR"].lerp(Vector3(20.0, 0.0, 0.0), e)
		p["LegL"] = p["LegL"].lerp(Vector3(18.0, 0.0, 0.0), e)
		p["ShinL"] = p["ShinL"].lerp(Vector3(-35.0, 0.0, 0.0), e)
		p["Head"] = p["Head"].lerp(Vector3(10.0, 25.0, 0.0), e)
	else:
		p["#Root"] = Vector3.ZERO
		p["@Root"] = Vector3.ZERO
	return p


## Lerps the action's pose over the base, rising and falling with a sine so it starts and ends
## where the base pose is.
func _blend_action(p: Dictionary) -> void:
	var t := _action_t / float(ACTIONS[action])
	var w := sin(clampf(t, 0.0, 1.0) * PI)
	w = minf(w * 1.6, 1.0)
	var target := {}
	match action:
		"install":
			var twist := sin(_action_t * 14.0) * 22.0
			target = {
				"ArmL": Vector3(68.0, 0.0, 12.0), "ForearmL": Vector3(25.0, 0.0, 0.0),
				"ArmR": Vector3(64.0, 0.0, -10.0), "ForearmR": Vector3(30.0, twist, 0.0),
				"Spine": Vector3(-22.0, 0.0, 0.0), "Head": Vector3(-20.0, 0.0, 0.0),
				"LegL": Vector3(32.0, 0.0, 0.0), "ShinL": Vector3(-55.0, 0.0, 0.0),
				"LegR": Vector3(28.0, 0.0, 0.0), "ShinR": Vector3(-50.0, 0.0, 0.0),
			}
			p["@Hips"] = p["@Hips"] + Vector3(0.0, -0.12 * w, 0.0)
		"interact":
			target = {
				"ArmR": Vector3(72.0, 0.0, 0.0), "ForearmR": Vector3(15.0, 0.0, 0.0),
				"Spine": Vector3(-18.0, 0.0, 0.0), "Head": Vector3(-15.0, 0.0, 0.0),
			}
		"stim":
			target = {
				"ArmL": Vector3(55.0, 0.0, 30.0), "ForearmL": Vector3(105.0, 0.0, 0.0),
				"Head": Vector3(-16.0, 0.0, 0.0), "Chest": Vector3(-6.0, 0.0, 0.0),
			}
	for j in target:
		p[j] = (p.get(j, Vector3.ZERO) as Vector3).lerp(target[j], w)


func _apply(p: Dictionary) -> void:
	for j in p:
		var key: String = j
		if key.begins_with("@") or key.begins_with("#"):
			continue
		pose.rot(key, p[j])
	pose.offset("Hips", p["@Hips"])
	pose.root.rotation_degrees = p["#Root"]
	pose.root.position = p["@Root"]
	var w := player.weapon
	w.position = _weapon_rest + p["@Weapon"]
	w.rotation_degrees = p["#Weapon"]
	w.visible = not (action in TWO_HANDED) and _down < 0.5
