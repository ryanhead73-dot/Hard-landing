class_name CreatureAnimator
extends Node
## Procedural animation for the wildlife rigs. A gait driven by ground speed (tripod gait for six
## legs, diagonal pairs for four), a body bob and sway, idle head turns, and poses for each
## creature's states: wind-ups, the scuttler's jaws, the spitter's neck and acid sac, the ram's
## lowered head and stagger, and the Warden's raised arms and opening carapace. trigger() plays a
## short one-shot (attack, slam, hurt). Dead creatures curl their legs.
##
## Legs come in two kinds: "splay" legs stick out sideways (scuttler, Warden) and sweep forward
## about the vertical axis, lifting about the long axis; "hang" legs hang down (spitter, ram) and
## swing like a walker's. Angles are degrees on top of each joint's rest pose.

const KINDS := {
	"scuttler": {"legs": "splay", "stride": 1.1, "swing": 24.0, "lift": 22.0, "knee": 0.0, "bob": 0.0},
	"spitter": {"legs": "hang", "stride": 1.5, "swing": 26.0, "lift": 0.0, "knee": 38.0, "bob": 0.04},
	"ram": {"legs": "hang", "stride": 2.6, "swing": 28.0, "lift": 0.0, "knee": 45.0, "bob": 0.06},
	"warden": {"legs": "splay", "stride": 3.2, "swing": 16.0, "lift": 14.0, "knee": 0.0, "bob": 0.07},
}
const SHOTS := {"attack": 0.35, "slam": 0.45, "hurt": 0.3}

var enemy: Enemy
var kind := ""
var pose: RigPose
var phase := 0.0
var shot := ""
## [joint, side (-1 left / 1 right), gait offset] for every leg.
var legs: Array = []

var _cfg: Dictionary
var _move := 0.0
var _windup := 0.0
var _open := 0.0
var _stun := 0.0
var _charge := 0.0
var _dead := 0.0
var _shot_t := 0.0
var _time := 0.0
var _seed := 0.0


func setup(e: Enemy, rig: Node3D, kind_name: String) -> void:
	enemy = e
	kind = kind_name
	_cfg = KINDS.get(kind, KINDS["scuttler"])
	pose = RigPose.new(rig)
	_seed = randf() * TAU
	for j in pose.names():
		if not j.begins_with("Leg"):
			continue
		var side := 0
		var idx := 0
		if j.length() == 5 and (j[3] == "F" or j[3] == "B"):
			side = -1 if j[4] == "L" else 1
			idx = 0 if j[3] == "F" else 1
		else:
			side = -1 if j[3] == "L" else 1
			idx = int(j.substr(4)) - 1
		legs.append([j, side, PI * ((idx + (1 if side > 0 else 0)) % 2)])


func trigger(shot_name: String) -> void:
	if SHOTS.has(shot_name):
		shot = shot_name
		_shot_t = 0.0


## 0..1 progress of the current one-shot, or -1 when none is playing.
func shot_progress() -> float:
	return _shot_t / float(SHOTS[shot]) if shot != "" else -1.0


func _process(delta: float) -> void:
	if enemy == null or pose == null or not is_instance_valid(enemy):
		return
	_time += delta
	var st := enemy.anim_state()
	var hv := Vector2(enemy.velocity.x, enemy.velocity.z).length()
	var k := clampf(delta * 8.0, 0.0, 1.0)
	_move = lerpf(_move, clampf(hv / 3.0, 0.0, 1.0), k)
	_windup = lerpf(_windup, 1.0 if st.ends_with("windup") or st == "paw" else 0.0, clampf(delta * 5.0, 0.0, 1.0))
	_open = lerpf(_open, 1.0 if st == "open" else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	_stun = lerpf(_stun, 1.0 if st == "stunned" else 0.0, k)
	_charge = lerpf(_charge, 1.0 if st == "charge" else 0.0, k)
	_dead = move_toward(_dead, 1.0 if st == "dead" else 0.0, delta * 3.0)
	if _dead <= 0.0:
		phase = fmod(phase + maxf(hv, 0.0) / float(_cfg["stride"]) * TAU * delta, TAU)
	if shot != "":
		_shot_t += delta
		if _shot_t >= SHOTS[shot]:
			shot = ""
	_pose_legs()
	_pose_body(st)


func _pose_legs() -> void:
	var swing: float = _cfg["swing"] * _move
	var lift: float = _cfg["lift"] * _move
	var knee: float = _cfg["knee"] * _move
	var curl := ease(_dead, -2.0)
	for leg in legs:
		var j: String = leg[0]
		var s: float = leg[1]
		var psi: float = phase + leg[2]
		var foot := j.replace("Leg", "Foot")
		var up := maxf(0.0, cos(psi))
		if _cfg["legs"] == "splay":
			var hip := Vector3(0.0, s * sin(psi) * swing, s * up * lift)
			pose.rot(j, hip.lerp(Vector3(0.0, 0.0, -s * 45.0), curl))
			pose.rot(foot, Vector3(0.0, 0.0, -s * 40.0 * curl))
		else:
			var hip := Vector3(sin(psi) * swing, 0.0, 0.0)
			if j.begins_with("LegF"):
				hip.x += 12.0 * _charge + sin(_time * 14.0) * 25.0 * _windup * (1.0 if s < 0 else 0.0)
			pose.rot(j, hip.lerp(Vector3(55.0, 0.0, s * 20.0), curl))
			pose.rot(foot, Vector3(-up * knee, 0.0, 0.0).lerp(Vector3(-95.0, 0.0, 0.0), curl))


func _pose_body(st: String) -> void:
	var m := _move
	var bob := absf(sin(phase * 2.0)) * float(_cfg["bob"]) * m
	var sway := sin(phase) * 3.0 * m
	var body := Vector3(0.0, 0.0, sway)
	var head := Vector3(0.0, sin(_time * 0.6 + _seed) * 14.0 * (1.0 - m) * (1.0 - _dead), 0.0)
	var t := shot_progress()
	var punch := sin(clampf(t, 0.0, 1.0) * PI) if t >= 0.0 else 0.0
	if shot == "hurt":
		body.z += sin(_shot_t * 40.0) * 8.0 * (1.0 - t)
		head.x += 10.0 * punch
	match kind:
		"scuttler":
			body.x += 12.0 * _windup - (16.0 * punch if shot == "attack" else 0.0)
			var jaw := 32.0 * _windup - (12.0 * punch if shot == "attack" else 0.0)
			pose.rot("JawL", Vector3(0.0, jaw, 0.0))
			pose.rot("JawR", Vector3(0.0, -jaw, 0.0))
		"spitter":
			var neck := 32.0 * _windup - (40.0 * punch if shot == "attack" else 0.0)
			pose.rot("Neck", Vector3(neck, 0.0, 0.0))
			var sac := pose.node("Sac")
			if sac:
				sac.scale = Vector3.ONE * (1.0 + 0.3 * _windup + 0.06 * sin(_time * 3.0 + _seed) - 0.25 * punch)
		"ram":
			head.x += -22.0 * _charge - 10.0 * _windup + 18.0 * punch - 26.0 * _stun
			head.z += sin(_time * 9.0) * 12.0 * _stun
			body.x += -5.0 * _charge
			pose.rot("Tail", Vector3(0.0, sin(_time * 5.0 + _seed) * 20.0 * (1.0 - _dead), 0.0))
		"warden":
			var raise := 105.0 * _windup if st == "slam_windup" else 0.0
			var slam := 120.0 * punch if shot == "slam" else 0.0
			var arms := Vector3(raise - slam, 0.0, 0.0)
			pose.rot("ArmL", arms)
			pose.rot("ArmR", arms)
			body.x += -8.0 * (_windup if st == "charge_windup" else 0.0) - 6.0 * _charge
			# The carapace opens to bare the core: plates lift outward.
			var plate := 50.0 * _open + 18.0 * (_windup if st == "volley_windup" else 0.0)
			pose.rot("PlateL", Vector3(0.0, 0.0, -plate))
			pose.rot("PlateR", Vector3(0.0, 0.0, plate))
			var core := pose.node("Core")
			if core:
				core.scale = Vector3.ONE * (1.0 + 0.12 * _open * sin(_time * 8.0) + 0.2 * punch * (1.0 if shot == "attack" else 0.0))
	body = body.lerp(Vector3(0.0, 0.0, 6.0), ease(_dead, -2.0))
	pose.rot("Body", body)
	pose.offset("Body", Vector3(0.0, bob - 0.15 * _dead * float(_cfg["bob"]) * 10.0, 0.0))
	pose.rot("Head", head.lerp(Vector3(-25.0, 0.0, 0.0), ease(_dead, -2.0)))


## Read back by tests: the plate opening angle, 0 shut .. 50 fully open.
func plate_angle() -> float:
	return absf(pose.rot_of("PlateR").z) if pose.has("PlateR") else 0.0
