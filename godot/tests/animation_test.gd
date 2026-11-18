extends "res://tests/test_base.gd"
## Juno's Blender clips in game (walk, run, crouch, jump, aim, recoil, reload, actions, hurt and
## going down, hands on the rifle); the wildlife gaits and per-creature poses; the repair install, the turret's idle
## sweep and the crash intro. Run:
##   godot --headless --path . res://tests/animation_test.tscn

const GRIP_L := Vector3(0, -0.118, -0.27)
const ARENA := Vector3(45.0, 0.5, 45.0)


func _name() -> String:
	return "ANIMATION TEST"


func _run() -> void:
	await _frames(30)
	_clear_enemies()
	_juno_contacts()
	await _juno_locomotion()
	await _juno_grips()
	await _juno_unarmed()
	await _juno_landings()
	await _juno_upper_body()
	await _juno_down()
	await _wildlife()
	await _lurker_emerge()
	await _skinned_wildlife()
	await _ship()
	await _intro()
	finished = true


func _rot(joint: String) -> Vector3:
	return player.anim.bone_rot(joint)


func _grip_gap(side: String) -> float:
	var weapon := player.weapon
	var model: Node3D = weapon._models[weapon.shown_model()]
	var grip := Rig.joint(model, "Grip" + side)
	if grip == null:
		return INF
	var a := player.anim
	return a.hand(side).distance_to(a.skeleton.to_local(grip.global_position))


## Cast from the palm towards the underside, against imported render triangles.
func _surface_gap(model: Node3D, meshes: Array[Node], palm: Vector3) -> float:
	var nearest := INF
	var end := palm + model.global_basis.y.normalized() * 0.04
	for node in meshes:
		var part := node as MeshInstance3D
		var triangles := part.mesh.generate_triangle_mesh()
		var hit := triangles.intersect_segment(part.to_local(palm), part.to_local(end))
		if not hit.is_empty():
			nearest = minf(nearest, palm.distance_to(part.to_global(hit.position)))
	return nearest


## Seek the equipped player's imported clips at 60 Hz, including the entire four-second idle.
func _juno_grips() -> void:
	var a := player.anim
	var w := player.weapon
	_place(ARENA, 0.0)
	await _frames(30)
	a.tree.active = false
	for id in ["rifle", "scattergun", "arc_lance"]:
		if id != "rifle":
			Game.give_weapon(id)
			w.equip(id)
			await _frames(30)
		_check("%s equipped for grip checks" % id, w.shown_model() == id and w.current == id)
		var model: Node3D = w._models[id]
		var muzzle := Rig.joint(model, "Muzzle")
		var grip := Rig.joint(model, "GripL")
		_check("%s forward support marker" % id,
			grip != null and model.to_local(grip.global_position).distance_to(GRIP_L) < .002)
		var fore_end := Rig.joint(model, "Pump") if id == "scattergun" else model
		var meshes := fore_end.find_children("*", "MeshInstance3D", true, false)
		for clip in ["idle", "walk", "run", "crouch", "crouch_walk", "fall", "aim", "jump", "land", "roll", "reload"]:
			a._clips.play(clip)
			a._clips.pause()
			var length := a._clips.get_animation(clip).length
			var steps := ceili(length * 60)
			var worst := Vector2.ZERO
			var elbow_min := INF
			var check_elbow: bool = clip in ["idle", "walk", "run", "aim"]
			var surface_max := 0.0
			var yaw_max := 0.0
			var pitch_min := 90.0
			var pitch_max := -90.0
			for i in range(steps + 1):
				if clip == "reload" and i != 0 and i != steps:
					continue
				a._clips.seek(length * i / steps, true)
				await get_tree().process_frame
				if check_elbow:
					elbow_min = minf(elbow_min, a.bone_pos("ArmR").y - a.bone_pos("ForearmR").y)
				worst.x = maxf(worst.x, _grip_gap("R"))
				worst.y = maxf(worst.y, _grip_gap("L"))
				var forward := player.rig.global_basis.inverse() * -muzzle.global_basis.z.normalized()
				if clip in ["idle", "walk"]:
					yaw_max = maxf(yaw_max, absf(rad_to_deg(atan2(forward.x, -forward.z))))
				if clip == "idle":
					var palm := a.skeleton.to_global(a.hand("L"))
					surface_max = maxf(surface_max, _surface_gap(model, meshes, palm))
					var pitch := rad_to_deg(asin(-forward.y))
					pitch_min = minf(pitch_min, pitch)
					pitch_max = maxf(pitch_max, pitch)
			_check("%s %s max grip gap" % [id, clip], worst.x < .06 and worst.y < .08,
				"R %.4f m, L %.4f m" % [worst.x, worst.y])
			if check_elbow:
				_check("%s %s right elbow drop" % [id, clip], elbow_min >= (0.0 if clip == "aim" else .12),
					"%.4f m min" % elbow_min)
			if clip in ["idle", "walk"]:
				_check("%s %s muzzle yaw" % [id, clip], yaw_max <= 15, "%.2f degrees max" % yaw_max)
			if clip == "idle":
				_check("%s idle palm to surface" % id, surface_max <= .04, "%.4f m max" % surface_max)
				_check("%s idle muzzle pitch" % id, pitch_min >= 15 and pitch_max <= 25,
					"%.2f to %.2f degrees down" % [pitch_min, pitch_max])
	a._clips.stop()
	a.tree.active = true
	w.equip("rifle")
	await _frames(30)


## Sample both boots through heel strike, flat support and toe-off on the imported rig.
## Advance the rig by gameplay distance so a planted tread stays at one world point.
func _juno_contacts() -> void:
	var rig := Rig.spawn("juno_rigged", self)
	var sk := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var ap := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for gait in [["walk", JunoAnimator.WALK_CYCLE, 13.0 / 24.0], ["run", JunoAnimator.RUN_CYCLE, .25],
			["crouch_walk", JunoAnimator.CROUCH_CYCLE, .58]]:
		var distance := float(gait[1])
		var stance := float(gait[2])
		var worst := 0.0
		var floor_error := 0.0
		ap.play(gait[0])
		for side in ["L", "R"]:
			var b := sk.find_bone("Foot" + side)
			var rest := sk.get_bone_global_rest(b)
			var offset := 0.0 if side == "L" else .5
			var footprint_samples := PackedVector3Array()
			for i in 121:
				var u := i / 120.0
				var phase := stance * u + offset
				ap.seek(fmod(phase, 1.0) * JunoAnimator.CYCLE_TIME, true)
				var pose := sk.get_bone_global_pose(b)
				var pivot := Vector3(0, -.105, .073 if u < .5 else -.17)
				var tread := pose * (rest.basis.inverse() * pivot) + Vector3.FORWARD * distance * phase
				floor_error = maxf(floor_error, absf(tread.y))
				# Both pivot locations are specified relative to the same flat footprint.
				var footprint := tread - pivot
				for previous in footprint_samples:
					worst = maxf(worst, footprint.distance_to(previous))
				footprint_samples.append(footprint)
		_check("%s planted tread slide" % gait[0], worst <= .04 and floor_error <= .04,
			"max %.2f cm, floor error %.2f cm" % [100*worst, 100*floor_error])
		if gait[0] == "walk":
			for side in ["L", "R"]:
				var phase := stance * .5 + (0.0 if side == "L" else .5)
				ap.seek(phase * JunoAnimator.CYCLE_TIME, true)
				var hip := sk.get_bone_global_pose(sk.find_bone("Leg" + side)).origin
				var knee := sk.get_bone_global_pose(sk.find_bone("Shin" + side)).origin
				var ankle := sk.get_bone_global_pose(sk.find_bone("Foot" + side)).origin
				var bend := rad_to_deg((knee - hip).angle_to(ankle - knee))
				_check("walk %s knee extends at mid-stance" % side, bend >= 5 and bend <= 15,
					"%.1f degrees" % bend)
		if gait[0] == "run":
			for phase in [.375, .875]:
				ap.seek(phase * JunoAnimator.CYCLE_TIME, true)
				var clearance := INF
				for side in ["L", "R"]:
					var b := sk.find_bone("Foot" + side)
					var rest := sk.get_bone_global_rest(b)
					var pose := sk.get_bone_global_pose(b)
					for z in [.073, -.17]:
						var tread := pose * (rest.basis.inverse() * Vector3(0, -.105, z))
						clearance = minf(clearance, tread.y)
				_check("run flight at phase %.3f clears both boots" % phase, clearance > .02,
					"lowest tread %.2f cm" % (100 * clearance))
	rig.queue_free()


func _juno_locomotion() -> void:
	var a := player.anim
	_place(ARENA, 0.0)
	await _frames(20)
	_check("Juno stands idle", a.state == "idle", a.state)
	_check("she's a skinned model driven by an AnimationTree", a.skeleton != null and a.tree != null and a.tree.active)
	_check("the weapon hangs on her WeaponMount bone", player.weapon.get_parent().name == "WeaponMount")
	_check("both hands are on the rifle", _grip_gap("R") < 0.06 and _grip_gap("L") < 0.08, "R %.2f L %.2f" % [_grip_gap("R"), _grip_gap("L")])
	# Walk: legs swing in opposition, knees bend.
	Input.action_press("move_forward")
	await _frames(30)
	var lo := 999.0
	var hi := -999.0
	var opposed := false
	for i in 60:
		await get_tree().physics_frame
		var l := _rot("LegL").x
		var r := _rot("LegR").x
		lo = minf(lo, l)
		hi = maxf(hi, l)
		opposed = opposed or (absf(l) > 8.0 and l * r < 0.0)
	_check("walking swings her legs", a.state == "walk" and hi - lo > 25.0, "%s range=%.0f" % [a.state, hi - lo])
	_check("legs move in opposition", opposed)
	_check("the walk plays at a speed that keeps her feet with the ground", absf(float(a.tree.get("parameters/gait_speed/scale")) - player.walk_speed / (a.WALK_CYCLE / a.CYCLE_TIME)) < 0.2, "%.2f" % float(a.tree.get("parameters/gait_speed/scale")))
	Input.action_press("sprint")
	await _frames(40)
	_check("sprinting runs", a.state == "run", a.state)
	_check("running leans her forward", _rot("Spine").x < -4.0, "spine=%.1f" % _rot("Spine").x)
	_check("her hands stay on the rifle while running", _grip_gap("R") < 0.08, "R %.2f" % _grip_gap("R"))
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _frames(30)
	# Crouch folds the legs instead of squashing the model.
	Input.action_press("crouch")
	await _frames(40)
	_check("crouching folds her legs", a.state == "crouch" and _rot("LegL").x > 50.0 and a.bone_bend("ShinL") > 80.0, "leg=%.0f knee=%.0f" % [_rot("LegL").x, a.bone_bend("ShinL")])
	_check("crouch lowers the hips, no squash", a.bone_pos("Hips").y < 0.6 and is_equal_approx(player._body.scale.y, 1.0), "hips=%.2f" % a.bone_pos("Hips").y)
	Input.action_release("crouch")
	await _frames(40)
	await _press("jump")
	await _frames(4)
	_check("jumping tucks her legs", (a.state == "jump" or a.state == "fall") and _rot("LegL").x > 10.0, "%s leg=%.0f" % [a.state, _rot("LegL").x])
	var landed := false
	var low_hips := 2.0
	for i in 90:
		await get_tree().physics_frame
		if a.tree.get("parameters/land/active"):
			landed = true
			low_hips = minf(low_hips, a.bone_pos("Hips").y)
	_check("touchdown absorbs weight and recovers", landed and low_hips < .81 and a.bone_pos("Hips").y > .86
		and is_equal_approx(a._clips.get_animation("land").length, .35), "lowest hips %.2f" % low_hips)


func _juno_unarmed() -> void:
	var a := player.anim
	_place(ARENA, 0.0)
	player.armed = false
	Input.action_press("aim")
	await _frames(36)
	for side in ["L", "R"]:
		var gap := _grip_gap(side)
		var height := a.hand(side).y
		_check("unarmed idle lowers hand %s even with aim held" % side,
			a.state == "idle" and gap >= .25 and height < a.bone_pos("Chest").y,
			"grip gap %.2f m, hand height %.2f m" % [gap, height])
	Input.action_release("aim")
	Input.action_press("move_forward")
	await _frames(30)
	# Check both exchanges in model space. A stationary hand cannot pass both.
	var left_leads := false
	var right_leads := false
	for i in 72:
		await get_tree().physics_frame
		var hands := a.hand("L").z - a.hand("R").z
		var feet := a.bone_pos("FootL").z - a.bone_pos("FootR").z
		left_leads = left_leads or (hands < -.20 and feet > .25)
		right_leads = right_leads or (hands > .20 and feet < -.25)
	_check("unarmed walking swings both arms opposite the legs", a.state == "walk" and left_leads and right_leads)
	Input.action_press("sprint")
	await _frames(40)
	var elbow_l := _rot("ForearmL").x
	var elbow_r := _rot("ForearmR").x
	_check("unarmed running keeps both elbows bent", a.state == "run" and absf(elbow_l - 85) < 10
		and absf(elbow_r - 85) < 10, "L %.1f, R %.1f degrees" % [elbow_l, elbow_r])
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _frames(30)
	a.play("interact")
	var reach := 0.0
	for i in 60:
		await get_tree().physics_frame
		reach = minf(reach, a.hand("L").z)
	_check("unarmed interact reaches forward over the idle arms", reach < -.45, "hand z %.2f m" % reach)
	player.armed = true
	await _frames(36)
	_check("equipping returns both hands to the rifle", _grip_gap("R") < .06 and _grip_gap("L") < .08,
		"R %.3f m, L %.3f m" % [_grip_gap("R"), _grip_gap("L")])


func _juno_landings() -> void:
	var a := player.anim
	for approach in ["running", "crouched", "slow"]:
		_place(ARENA, 0.0)
		await _frames(20)
		if approach == "running":
			Input.action_press("move_forward")
			Input.action_press("sprint")
			await _frames(30)
		await _press("jump")
		var airborne := not player.is_on_floor()
		if approach == "crouched":
			Input.action_press("crouch")
		var landed := false
		var touchdown_speed := 0.0
		var touchdown_crouched := false
		var impact_speed := 0.0
		var recovery := false
		for i in 75:
			await get_tree().physics_frame
			if not landed and airborne and player.is_on_floor():
				landed = true
				touchdown_speed = Vector2(player.velocity.x, player.velocity.z).length()
				touchdown_crouched = player.crouching
				impact_speed = -player._airborne_speed
			recovery = recovery or bool(a.tree.get("parameters/land/active"))
			if approach == "slow" and landed and recovery:
				break
		Input.action_release("move_forward")
		Input.action_release("sprint")
		Input.action_release("crouch")
		var real_landing := landed and impact_speed > 3.0
		match approach:
			"running":
				_check("running touchdown skips landing recovery", real_landing and touchdown_speed > player.walk_speed + 0.5
					and not touchdown_crouched and not recovery)
			"crouched":
				_check("crouched touchdown skips landing recovery", real_landing and touchdown_crouched
					and touchdown_speed < player.walk_speed * 0.5 and not recovery)
			"slow":
				_check("slow standing touchdown starts landing recovery", real_landing and not touchdown_crouched
					and touchdown_speed < player.walk_speed * 0.5 and recovery)
				await _press("jump")
				_check("jumping during landing recovery aborts it", recovery and not player.is_on_floor()
					and player.velocity.y > 0.0 and not a.tree.get("parameters/land/active"))


func _juno_upper_body() -> void:
	var a := player.anim
	var w := player.weapon
	_place(ARENA, 0.0)
	await _frames(10)
	Input.action_press("aim")
	player.aim_at(player.global_position + Vector3(0.0, 9.0, -10.0))
	await _frames(30)
	_check("aiming up pitches her chest", _rot("Chest").x > 8.0, "chest=%.1f" % _rot("Chest").x)
	_check("aiming shoulders the rifle", a.weapon_point(Vector3.ZERO).y > 1.45, "%.2f" % a.weapon_point(Vector3.ZERO).y)
	_check("her hands follow the rifle up", _grip_gap("R") < 0.06, "R %.2f" % _grip_gap("R"))
	Input.action_release("aim")
	await _frames(5)
	w.fired.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("firing kicks the weapon back", w.position.z > a._weapon_rest.z + 0.03, "dz=%.3f" % (w.position.z - a._weapon_rest.z))
	await _frames(30)
	Game.set_ammo(w.current, 0, 50)
	w.start_reload()
	var left_off := 0.0
	var tilt := 0.0
	var start := Time.get_ticks_msec()
	while w.reloading and Time.get_ticks_msec() - start < 4000:
		await get_tree().process_frame
		left_off = maxf(left_off, _grip_gap("L"))
		tilt = maxf(tilt, absf(w.global_basis.x.y))
	_check("reloading tilts the rifle and the left hand leaves it for a fresh cell", left_off > 0.2 and tilt > 0.25, "hand off %.2f tilt %.2f" % [left_off, tilt])
	await _frames(20)
	_check("reload pose clears, hands back on", not w.reloading and _grip_gap("L") < 0.08, "L %.2f" % _grip_gap("L"))
	_check("a stim plays its action", a.play("stim") and a.action == "stim")
	await get_tree().create_timer(0.4).timeout
	_check("the stim goes into her thigh", a.hand("L").y < 1.0 and _grip_gap("L") > 0.3, "hand y %.2f" % a.hand("L").y)
	await get_tree().create_timer(0.7).timeout
	_check("actions finish", a.action == "")
	_check("a throw plays its action", a.play("throw") and a.action == "throw")
	var high := -9.0
	var forward := 9.0
	start = Time.get_ticks_msec()
	while a.action == "throw":
		await get_tree().process_frame
		var h := a.hand("L")
		if Time.get_ticks_msec() - start < 260:
			high = maxf(high, h.y)
		else:
			forward = minf(forward, h.z)
	_check("the throw winds up and whips through", high > 1.5 and forward < -0.45, "wind-up y=%.2f release z=%.2f" % [high, forward])
	a.play("install")
	await get_tree().create_timer(0.6).timeout
	_check("installing kneels and uses both hands, weapon stowed", not w.visible and a.bone_pos("Hips").y < 0.75 and a.hand("L").z < -0.35 and a.hand("R").z < -0.35, "hips %.2f hands %.2f %.2f" % [a.bone_pos("Hips").y, a.hand("L").z, a.hand("R").z])
	await get_tree().create_timer(1.0).timeout
	_check("the weapon comes back after", w.visible)
	_check("unknown actions are refused", not a.play("cartwheel"))
	player.take_damage(5.0)
	await get_tree().process_frame
	_check("a hit makes her flinch", a._flinch > 0.5)
	await _frames(30)


func _juno_down() -> void:
	var a := player.anim
	player.take_damage(9999.0)
	await get_tree().create_timer(1.6).timeout
	_check("she goes down", a.state == "down" and a.bone_pos("Hips").y < 0.4 and not player.weapon.visible, "%s hips %.2f" % [a.state, a.bone_pos("Hips").y])
	_check("no actions while down", not a.play("stim"))
	player.revive(ARENA)
	await _frames(20)
	_check("revived, she's back on her feet", a.bone_pos("Hips").y > 0.8 and player.weapon.visible and a.state != "down", "hips %.2f" % a.bone_pos("Hips").y)


func _wildlife() -> void:
	var kinds := {"scuttler": 6, "spitter": 4, "ram": 4, "warden": 6}
	var leg_ok := true
	var made := {}
	var i := 0
	for kind in kinds:
		var e: Enemy = main.spawn_enemy(kind, ARENA + Vector3(-14.0 + i * 9.0, 0.0, -14.0))
		e.target = null
		e.set_physics_process(false)
		made[kind] = e
		leg_ok = leg_ok and e.anim != null and e.anim.legs.size() == kinds[kind]
		i += 1
	_check("every creature has an animator and all its legs", leg_ok)
	var sc: Enemy = made["scuttler"]
	var tri: Dictionary = {}
	for leg in sc.anim.legs:
		tri[leg[0]] = leg[2]
	var clipped := true
	for kind in made:
		clipped = clipped and (made[kind] as Enemy).anim.tree != null
	_check("the scuttler, spitter, ram and Warden play keyframed Blender clips", clipped)
	_check("their states have clips", "paw" in (made["ram"] as Enemy).anim._state_clips and "open" in (made["warden"] as Enemy).anim._state_clips and "slam" in (made["warden"] as Enemy).anim._shots, str((made["ram"] as Enemy).anim._state_clips))
	_check("six legs walk a tripod gait", tri["LegL1"] == tri["LegR2"] and tri["LegL1"] == tri["LegL3"] and tri["LegL1"] != tri["LegR1"])
	var ram: Enemy = made["ram"]
	var quad: Dictionary = {}
	for leg in ram.anim.legs:
		quad[leg[0]] = leg[2]
	_check("four legs walk in diagonal pairs", quad["LegFL"] == quad["LegBR"] and quad["LegFL"] != quad["LegFR"])
	# Moving: legs sweep.
	var swing_ok := true
	for kind in made:
		var e: Enemy = made[kind]
		e.velocity = Vector3(2.5, 0.0, 0.0)
	# How far the first leg's hip turns, about whichever axis it turns most (the procedural legs
	# swing about one axis; the IK legs of the skinned models about a slanted one).
	var lo := {}
	var hi := {}
	# Over a full stride or so (the IK legs turn less per step but keep at it all cycle).
	var t := 0.0
	var frames := 0
	while t < 1.2 and frames < 600:
		frames += 1
		await get_tree().process_frame
		t += get_process_delta_time()
		for kind in made:
			var e: Enemy = made[kind]
			var leg: String = e.anim.legs[0][0]
			var r: Vector3 = e.anim.pose.rot_of(leg)
			lo[kind] = (lo.get(kind, r) as Vector3).min(r)
			hi[kind] = (hi.get(kind, r) as Vector3).max(r)
	var detail := ""
	for kind in lo:
		var span: Vector3 = hi[kind] - lo[kind]
		var most := maxf(span.x, maxf(span.y, span.z))
		detail += "%s=%.0f " % [kind, most]
		swing_ok = swing_ok and most > 10.0
	_check("every creature's legs walk", swing_ok, detail)
	for kind in made:
		(made[kind] as Enemy).velocity = Vector3.ZERO
	# States.
	sc.state = Scuttler.State.WINDUP
	var sp: Spitter = made["spitter"]
	sp.state = Spitter.State.WINDUP
	var wd: Warden = made["warden"]
	wd.state = Warden.State.OPEN
	ram.state = Ram.State.STUNNED
	await get_tree().create_timer(0.8).timeout
	_check("a scuttler winding up opens its jaws", sc.anim.pose.rot_of("JawL").y > 20.0)
	_check("a spitter rears its neck back", sp.anim.pose.rot_of("Neck").x > 20.0)
	_check("the Warden's carapace opens", wd.anim.plate_angle() > 35.0, "%.0f" % wd.anim.plate_angle())
	_check("a stunned ram hangs its head", ram.anim.pose.rot_of("Head").x < -15.0)
	wd.state = Warden.State.APPROACH
	await get_tree().create_timer(0.8).timeout
	_check("the carapace closes again", wd.anim.plate_angle() < 10.0)
	sc.state = Scuttler.State.CHASE
	sc._lunge()
	_check("a lunge plays the attack", sc.anim.shot == "attack")
	wd._slam()
	_check("a slam plays the slam", wd.anim.shot == "slam")
	sp.take_damage(1.0, sp.global_position, Vector3.FORWARD)
	_check("a hit plays a flinch", sp.anim.shot == "hurt")
	sc.take_damage(9999.0, sc.global_position, Vector3.FORWARD)
	await get_tree().create_timer(0.5).timeout
	_check("dead creatures curl their legs", is_instance_valid(sc) and sc.anim._dead > 0.9 and sc.anim.pose.rot_of("LegR1").z < -30.0)
	_clear_enemies()


## A lurker bursting out of its pool eases its jaw open over a few frames instead of snapping it.
## The creatures modelled as one skinned mesh (blender/build_creatures.py): each has its clips,
## a weak spot that follows its bone, and the clip for the state it is in plays.
func _skinned_wildlife() -> void:
	var clips := {"drifter": ["idle", "walk", "swell", "die"], "veilwing": ["roost", "flare", "swoop", "climb", "die"],
		"ridge_diver": ["surfaced", "attack", "dive", "die"], "pinweaver": ["idle", "walk", "anchor", "spool", "recover", "die"],
		"chord_singer": ["idle", "walk", "plant", "inhale", "sing", "stagger", "die"],
		"patience_guardian": ["idle", "walk", "dormant", "brace", "charge", "pinned", "die"], "cantor": ["listen", "open", "die"]}
	for kind in clips:
		var e := main.spawn_enemy("guardian" if kind == "patience_guardian" else kind, ARENA + Vector3(0.0, 0.5, -6.0), "") as Enemy
		await _frames(3)
		var player_clips := e.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var missing: Array = []
		for c in clips[kind]:
			if player_clips == null or not player_clips.has_animation(c):
				missing.append(c)
		var meshes := 0
		for n in e.find_children("*", "MeshInstance3D", true, false):
			if (n as MeshInstance3D).skeleton != NodePath():
				meshes += 1
		_check("%s: one skinned mesh with its clips" % kind, missing.is_empty() and meshes == 1 and e.anim and e.anim.tree != null,
			"missing %s, skinned meshes %d" % [missing, meshes])
		_check("%s: its weak spot follows a bone" % kind, e._weak != null and is_instance_valid(e._weak), e.weak_joint)
		e.queue_free()
		await _frames(2)


func _lurker_emerge() -> void:
	var lk: Enemy = main.spawn_enemy("lurker", ARENA + Vector3(0.0, 0.0, -20.0))
	lk.target = null
	lk.set_physics_process(false)
	await _frames(10)
	var jaw_rest: float = _jaw(lk)
	lk.state = Lurker.State.EMERGE
	await _frames(1)
	var jaw_first: float = _jaw(lk)
	await get_tree().create_timer(0.6).timeout
	var jaw_open: float = _jaw(lk)
	_check("a lurker's jaw eases open as it emerges", absf(jaw_first - jaw_rest) < 15.0 and absf(jaw_open - jaw_rest) > 22.0,
		"rest %.0f, first frame %.0f, after 0.6 s %.0f" % [jaw_rest, jaw_first, jaw_open])
	_clear_enemies()


func _jaw(e: Enemy) -> float:
	return e.anim.pose.rot_of("Jaw").x


func _ship() -> void:
	kestrel.set_repaired("aux_power", true)
	var r: Repairable = kestrel.repairs["aux_power"]
	var part := r._repaired_child()
	var rest := part.scale
	var bursts := get_tree().get_nodes_in_group("vfx_burst").size()
	kestrel.play_repair("aux_power")
	_check("an install settles the new part in", part.scale.x < rest.x * 0.9 and get_tree().get_nodes_in_group("vfx_burst").size() > bursts)
	await get_tree().create_timer(1.1).timeout
	_check("and it ends at its proper size", part.scale.is_equal_approx(rest))
	kestrel.set_repaired("wing", true)
	var head: Node3D = kestrel.turret._head
	await _frames(10)
	var before := head.global_basis.z
	await get_tree().create_timer(1.0).timeout
	_check("the turret sweeps while idle", head.global_basis.z.angle_to(before) > 0.05)


func _intro() -> void:
	var rest := kestrel.global_transform
	main.play_intro()
	await _frames(2)
	_check("the intro starts with Kestrel in the sky", main.intro_playing and kestrel.global_position.distance_to(rest.origin) > 60.0 and not player.visible)
	_check("the intro has its own camera", get_viewport().get_camera_3d() == main._cine_cam)
	await get_tree().create_timer(main.INTRO_FALL + 0.3).timeout
	_check("she hits the ground and throws dust", kestrel.global_position.y < rest.origin.y + 1.0 and main._shake > 0.0)
	await get_tree().create_timer(main.INTRO_SLIDE + main.INTRO_HOLD + main.INTRO_REVEAL + 1.3).timeout
	_check("the intro ends with Kestrel at the crash site", not main.intro_playing and kestrel.global_transform.is_equal_approx(rest))
	_check("Juno has control again", player.visible and player.is_physics_processing() and get_viewport().get_camera_3d() == player.camera())
	_check("the HUD comes back", main.hud._objective.is_visible_in_tree())
	main.play_intro()
	await _frames(5)
	await _press("interact")
	_check("interact skips the intro", not main.intro_playing and kestrel.global_transform.is_equal_approx(rest))
