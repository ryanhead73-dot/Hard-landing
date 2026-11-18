class_name JunoAnimator
extends Node
## Juno's animation. Her body is a skinned model with keyframed clips made in Blender
## (blender/build_juno.py -> assets/models/juno_rigged.glb). An AnimationTree mixes them from what
## the player is doing: idle, walk and run blended by ground speed and played at the speed that
## keeps her feet with the ground, crouch and crouch walk, jump and fall, the shouldered aim over
## the legs, reload, the one-shot actions (install, interact, stim, throw), the dodge roll and
## going down. Empty-hand poses blend onto the arms before the action layers.
##
## A small procedural layer (JunoPoseLayer) then adds what has to follow the game frame by frame:
## the chest pitching with the camera when aiming, recoil, hit flinches and the lean under a heavy
## pack.

## The model's clip lengths match these, at normal speed.
const ACTIONS := {"install": 1.4, "interact": 0.8, "stim": 0.9, "throw": 0.75}
## Two-handed actions put the weapon away while they play.
const TWO_HANDED := ["install"]
## Actions that need the whole body; the others play on the upper body over her legs.
const FULL_BODY := ["install"]
const ARM_BONES := ["ArmL", "ForearmL", "HandL", "FingersL", "ThumbL",
	"ArmR", "ForearmR", "HandR", "FingersR", "ThumbR"]
const UPPER_BONES := ARM_BONES + ["Spine", "Chest", "Neck", "Head", "WeaponMount"]
const LOOPS := ["idle", "walk", "run", "crouch", "crouch_walk", "fall", "aim",
	"idle_free", "walk_free", "run_free", "crouch_free", "fall_free"]
## Metres the walk, run and crouch-walk clips cover per cycle at normal speed (0.8 s each).
const WALK_CYCLE := 2.72
const RUN_CYCLE := 4.32
const CROUCH_CYCLE := 1.4
const CYCLE_TIME := 0.8
## Elbow to the middle of the glove: where the hands are, for tests and effects.
const HAND := 0.35

var player: Player
var model: Node3D
var skeleton: Skeleton3D
var tree: AnimationTree
var layer: JunoPoseLayer
var state := "idle"
var action := ""

var _clips: AnimationPlayer
var _action_t := 0.0
var _walk := 0.0
var _run := 0.0
var _crouch := 0.0
var _air := 0.0
var _free := 0.0
var _arm_blends: Array[String] = []
var _aim := 0.0
var _recoil := 0.0
var _flinch := 0.0
var _carry := 0.0
var _down := 0.0
var _was_reloading := false
var _was_rolling := false
var _was_grounded := false
var _was_dead := false
var _weapon_rest := Vector3.ZERO


func setup(p: Player, rig: Node3D) -> void:
	player = p
	model = rig
	skeleton = rig.find_child("Skeleton3D", true, false) as Skeleton3D
	_clips = rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_weapon_rest = p.weapon.position
	p.weapon.fired.connect(func(): _recoil = 1.0)
	p.damaged.connect(func(_a): _flinch = 1.0)
	if skeleton == null or _clips == null:
		push_warning("JunoAnimator: the model has no skeleton or clips")
		return
	_build_tree()
	layer = JunoPoseLayer.new()
	layer.name = "PoseLayer"
	layer.animator = self
	skeleton.add_child(layer)


## Starts a one-shot action ("install", "interact", "stim", "throw"). Returns false for unknown
## names or while she's down.
func play(action_name: String) -> bool:
	if not ACTIONS.has(action_name) or player.dead:
		return false
	action = action_name
	_action_t = 0.0
	if tree:
		if action_name in FULL_BODY:
			tree.set("parameters/full_act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		else:
			tree.set("parameters/upper_pick/transition_request", action_name)
			tree.set("parameters/upper_act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


func _physics_process(_delta: float) -> void:
	if tree == null:
		return
	var grounded := player.is_on_floor()
	if grounded and not _was_grounded:
		# The player retains the impact speed until its next grounded physics tick.
		var hv := Vector2(player.velocity.x, player.velocity.z).length()
		if player._airborne_speed < -3.0 and hv < player.walk_speed * 0.5 \
				and not player.crouching and not player.dead and not player.is_rolling():
			tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif not grounded and _was_grounded:
		tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_was_grounded = grounded


func _process(delta: float) -> void:
	if player == null:
		return
	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	var grounded := player.is_on_floor()
	var k := clampf(delta * 10.0, 0.0, 1.0)
	_walk = lerpf(_walk, clampf(hv / player.walk_speed, 0.0, 1.0) if grounded else 0.0, k)
	_run = lerpf(_run, clampf((hv - player.walk_speed) / (player.sprint_speed - player.walk_speed), 0.0, 1.0) if grounded else 0.0, k)
	_crouch = lerpf(_crouch, 1.0 if player.crouching else 0.0, k)
	_air = lerpf(_air, 0.0 if grounded else 1.0, clampf(delta * 8.0, 0.0, 1.0))
	_free = move_toward(_free, 0.0 if player.armed else 1.0, delta / 0.2)
	_aim = lerpf(_aim, 1.0 if player.armed and (player.aiming or player._combat_face > 0.0) else 0.0, k)
	_carry = lerpf(_carry, 1.0 if Game.carrying != "" else 0.0, k)
	_recoil = maxf(_recoil - delta * 9.0, 0.0)
	_flinch = maxf(_flinch - delta * 5.0, 0.0)
	_down = move_toward(_down, 1.0 if player.dead else 0.0, delta * (1.6 if player.dead else 99.0))
	if action != "":
		_action_t += delta
		if _action_t >= ACTIONS[action] or player.dead:
			action = ""
	state = _state_name(hv, grounded)
	if tree:
		_drive_tree(hv)
	var w := player.weapon
	w.position = _weapon_rest + Vector3(0.0, 0.0, 0.06 * _recoil)
	w.visible = player.armed and not (action in TWO_HANDED) and _down < 0.5


func _state_name(hv: float, grounded: bool) -> String:
	if player.dead:
		return "down"
	if player.is_rolling():
		return "roll"
	if not grounded:
		return "jump" if player.velocity.y > 0.0 else "fall"
	if player.crouching:
		return "crouch"
	if hv > player.walk_speed + 0.5:
		return "run"
	if hv > 0.4:
		return "walk"
	return "idle"


func _drive_tree(hv: float) -> void:
	var t := tree
	for path in _arm_blends:
		t.set(path, _free)
	t.set("parameters/free_gait/blend_position", _run)
	t.set("parameters/move/blend_amount", _walk)
	t.set("parameters/gait/blend_position", _run)
	var cycle := lerpf(WALK_CYCLE, RUN_CYCLE, _run)
	t.set("parameters/gait_speed/scale", clampf(hv / (cycle / CYCLE_TIME), 0.6, 2.2))
	t.set("parameters/cmove/blend_amount", clampf(hv / player.crouch_speed, 0.0, 1.0))
	t.set("parameters/cwalk_speed/scale", clampf(hv / (CROUCH_CYCLE / CYCLE_TIME), 0.5, 2.0))
	t.set("parameters/ground/blend_amount", _crouch)
	t.set("parameters/air/blend_amount", 1.0 if player.velocity.y < 0.0 else 0.0)
	t.set("parameters/body/blend_amount", _air)
	t.set("parameters/aim/blend_amount", _aim)
	# Reload: play the clip over the reload time; stop it if the reload is cut short.
	var reloading := player.weapon.reloading
	if reloading and not _was_reloading:
		var clip := _clips.get_animation("reload").length
		t.set("parameters/reload_speed/scale", clip / maxf(player.weapon.reload_time(), 0.2))
		t.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif not reloading and _was_reloading:
		t.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_was_reloading = reloading
	var rolling := player.is_rolling()
	if rolling and not _was_rolling:
		t.set("parameters/roll/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_was_rolling = rolling
	if player.dead != _was_dead:
		t.set("parameters/alive/transition_request", "dead" if player.dead else "alive")
		if player.dead:
			for shot in ["reload", "upper_act", "full_act", "roll", "land"]:
				t.set("parameters/%s/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_was_dead = player.dead


# --- Tree ---------------------------------------------------------------------------------

func _build_tree() -> void:
	for clip in LOOPS:
		var a := _clips.get_animation(clip)
		a.loop_mode = Animation.LOOP_LINEAR
		# The exporter adds a frame after the last key; cut it so the loop doesn't hitch.
		var last := 0.0
		for i in a.get_track_count():
			if a.track_get_key_count(i) > 0:
				last = maxf(last, a.track_get_key_time(i, a.track_get_key_count(i) - 1))
		if clip in ["walk", "run", "crouch_walk", "walk_free", "run_free"]:
			a.length = CYCLE_TIME
		elif last > 0.0:
			a.length = last
	var bt := AnimationNodeBlendTree.new()
	_node(bt, "idle", _clip("idle"))
	_node(bt, "gait", _gait(""))
	_node(bt, "free_gait", _gait("_free"))
	_node(bt, "gait_speed", AnimationNodeTimeScale.new())
	_node(bt, "move", AnimationNodeBlend2.new())
	_node(bt, "crouch", _clip("crouch"))
	_node(bt, "cwalk", _clip("crouch_walk"))
	_node(bt, "cwalk_speed", AnimationNodeTimeScale.new())
	_node(bt, "cmove", AnimationNodeBlend2.new())
	_node(bt, "ground", AnimationNodeBlend2.new())
	_node(bt, "jump", _clip("jump"))
	_node(bt, "fall", _clip("fall"))
	_node(bt, "air", AnimationNodeBlend2.new())
	_node(bt, "body", AnimationNodeBlend2.new())
	_node(bt, "land_clip", _clip("land"))
	_node(bt, "land", _shot(.025, .10))
	_node(bt, "aim_clip", _clip("aim"))
	_node(bt, "aim", _filtered(AnimationNodeBlend2.new()))
	_node(bt, "reload_clip", _clip("reload"))
	_node(bt, "reload_speed", AnimationNodeTimeScale.new())
	_node(bt, "reload", _filtered(_shot(0.12, 0.2)))
	var pick := AnimationNodeTransition.new()
	pick.xfade_time = 0.0
	for a in ACTIONS:
		if not a in FULL_BODY:
			pick.add_input(a)
			_node(bt, "act_" + a, _clip(a))
	_node(bt, "upper_pick", pick)
	_node(bt, "upper_act", _filtered(_shot(0.12, 0.2)))
	_node(bt, "install_clip", _clip("install"))
	_node(bt, "full_act", _shot(0.15, 0.25))
	_node(bt, "roll_clip", _clip("roll"))
	_node(bt, "roll_speed", AnimationNodeTimeScale.new())
	_node(bt, "roll", _shot(0.05, 0.12))
	_node(bt, "die", _clip("die"))
	var alive := AnimationNodeTransition.new()
	alive.xfade_time = 0.15
	alive.add_input("alive")
	alive.add_input("dead")
	_node(bt, "alive", alive)

	_node(bt, "idle_free", _clip("idle_free"))
	_node(bt, "crouch_free", _clip("crouch_free"))
	_node(bt, "fall_free", _clip("fall_free"))
	# The landing one-shot must end at its original recovery time.
	var landing_arms := _clip("idle_free")
	landing_arms.use_custom_timeline = true
	landing_arms.timeline_length = _clips.get_animation("land").length
	_node(bt, "landing_arms", landing_arms)
	bt.connect_node("gait_speed", 0, _arm_mix(bt, "gait", "free_gait"))
	bt.connect_node("move", 0, _arm_mix(bt, "idle", "idle_free"))
	bt.connect_node("move", 1, "gait_speed")
	bt.connect_node("cwalk_speed", 0, "cwalk")
	bt.connect_node("cmove", 0, "crouch")
	bt.connect_node("cmove", 1, "cwalk_speed")
	bt.connect_node("ground", 0, "move")
	bt.connect_node("ground", 1, _arm_mix(bt, "cmove", "crouch_free"))
	bt.connect_node("air", 0, "jump")
	bt.connect_node("air", 1, "fall")
	bt.connect_node("body", 0, "ground")
	bt.connect_node("body", 1, _arm_mix(bt, "air", "fall_free"))
	bt.connect_node("land", 0, "body")
	bt.connect_node("land", 1, _arm_mix(bt, "land_clip", "landing_arms"))
	bt.connect_node("aim", 0, "land")
	bt.connect_node("aim", 1, "aim_clip")
	bt.connect_node("reload_speed", 0, "reload_clip")
	bt.connect_node("reload", 0, "aim")
	bt.connect_node("reload", 1, "reload_speed")
	var i := 0
	for a in ACTIONS:
		if not a in FULL_BODY:
			bt.connect_node("upper_pick", i, "act_" + a)
			i += 1
	bt.connect_node("upper_act", 0, "reload")
	bt.connect_node("upper_act", 1, "upper_pick")
	bt.connect_node("full_act", 0, "upper_act")
	bt.connect_node("full_act", 1, "install_clip")
	bt.connect_node("roll_speed", 0, "roll_clip")
	bt.connect_node("roll", 0, "full_act")
	bt.connect_node("roll", 1, "roll_speed")
	bt.connect_node("alive", 0, "roll")
	bt.connect_node("alive", 1, "die")
	bt.connect_node("output", 0, "alive")

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = bt
	# Next to the AnimationPlayer, so both resolve the clips' track paths from the model root.
	_clips.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(_clips)
	tree.root_node = tree.get_path_to(_clips.get_node(_clips.root_node))
	tree.set("parameters/roll_speed/scale", _clips.get_animation("roll").length / Player.ROLL_TIME)
	tree.set("parameters/alive/transition_request", "alive")
	tree.active = true


func _gait(suffix: String) -> AnimationNodeBlendSpace1D:
	var gait := AnimationNodeBlendSpace1D.new()
	gait.add_blend_point(_clip("walk" + suffix), 0.0, -1, &"walk")
	gait.add_blend_point(_clip("run" + suffix), 1.0, -1, &"run")
	gait.min_space = 0.0
	gait.max_space = 1.0
	gait.sync = true
	return gait


func _arm_mix(bt: AnimationNodeBlendTree, body: String, arms: String) -> String:
	var blend := AnimationNodeBlend2.new()
	blend.sync = true  # Both gait clocks follow the same time scale through equip changes.
	var mix_name := body + "_arms"
	_node(bt, mix_name, _filtered(blend, ARM_BONES))
	bt.connect_node(mix_name, 0, body)
	bt.connect_node(mix_name, 1, arms)
	_arm_blends.append("parameters/%s/blend_amount" % mix_name)
	return mix_name


func _node(bt: AnimationNodeBlendTree, node_name: String, node: AnimationNode) -> void:
	bt.add_node(node_name, node)


func _clip(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n


func _shot(fade_in: float, fade_out: float) -> AnimationNodeOneShot:
	var n := AnimationNodeOneShot.new()
	n.fadein_time = fade_in
	n.fadeout_time = fade_out
	return n


## Limits a node's blend to the upper body, so the legs keep walking underneath.
func _filtered(n: AnimationNode, bones: Array = UPPER_BONES) -> AnimationNode:
	n.filter_enabled = true
	var base := String(_clips.get_node(_clips.root_node).get_path_to(skeleton))
	for b in bones:
		n.set_filter_path(NodePath("%s:%s" % [base, b]), true)
	return n


# --- Reading the pose (tests, effects) ----------------------------------------------------

## A bone's rotation away from its rest pose, in degrees, the way the clips are authored: about
## the model's x, y and z axes as carried by its parent (+x swings a limb forward or tips the
## torso back).
func bone_rot(bone: String) -> Vector3:
	if skeleton == null:
		return Vector3.ZERO
	var b := skeleton.find_bone(bone)
	if b < 0:
		return Vector3.ZERO
	var g := _pose(b).basis.orthonormalized()
	var rest := skeleton.get_bone_global_rest(b).basis.orthonormalized()
	var w := g * rest.inverse()
	var p := skeleton.get_bone_parent(b)
	if p >= 0:
		var pg := _pose(p).basis.orthonormalized()
		var prest := skeleton.get_bone_global_rest(p).basis.orthonormalized()
		w = prest * pg.inverse() * g * rest.inverse()
	return w.get_euler() * (180.0 / PI)


## How far a bone has turned from its rest pose in all, in degrees (for bends past 90, where
## Euler angles flip).
func bone_bend(bone: String) -> float:
	var r := bone_rot(bone) * (PI / 180.0)
	return rad_to_deg(Basis.from_euler(r).get_rotation_quaternion().get_angle())


## A bone's global pose as shown on screen (after the procedural layer).
func _pose(b: int) -> Transform3D:
	if layer and layer.shown.size() > b:
		return layer.shown[b]
	return skeleton.get_bone_global_pose(b)


## Where a bone's head is, in the model's space (metres).
func bone_pos(bone: String) -> Vector3:
	var b := skeleton.find_bone(bone) if skeleton else -1
	return _pose(b).origin if b >= 0 else Vector3.ZERO


## The middle of a hand ("L" or "R"), in the model's space.
func hand(side: String) -> Vector3:
	var b := skeleton.find_bone("Forearm" + side) if skeleton else -1
	if b < 0:
		return Vector3.ZERO
	return _pose(b) * Vector3(0.0, HAND, 0.0)


## A point given in the weapon's own frame, in the model's space.
func weapon_point(local: Vector3) -> Vector3:
	return skeleton.global_transform.affine_inverse() * player.weapon.global_transform * local
