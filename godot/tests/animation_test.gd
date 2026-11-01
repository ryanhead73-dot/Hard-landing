extends "res://tests/test_base.gd"
## Milestone 5 animation: Juno's walk, run, crouch, jump, aim, recoil, reload, actions, hurt and
## down poses; the wildlife gaits and per-creature poses; the repair install, the turret's idle
## sweep and the crash intro. Run:
##   godot --headless --path . res://tests/animation_test.tscn

const ARENA := Vector3(45.0, 0.5, 45.0)


func _name() -> String:
	return "ANIMATION TEST"


func _run() -> void:
	await _frames(30)
	_clear_enemies()
	await _juno_locomotion()
	await _juno_upper_body()
	await _juno_down()
	await _wildlife()
	await _ship()
	await _intro()
	finished = true


func _rot(joint: String) -> Vector3:
	return player.anim.pose.rot_of(joint)


func _juno_locomotion() -> void:
	var a := player.anim
	_place(ARENA, 0.0)
	await _frames(20)
	_check("Juno stands idle", a.state == "idle", a.state)
	_check("the weapon rides on her chest", player.weapon.get_parent().name == "Chest")
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
	Input.action_press("sprint")
	await _frames(40)
	_check("sprinting runs", a.state == "run", a.state)
	_check("running leans her forward", _rot("Spine").x < -5.0, "spine=%.1f" % _rot("Spine").x)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _frames(30)
	# Crouch folds the legs instead of squashing the model.
	Input.action_press("crouch")
	await _frames(40)
	var hips := player.anim.pose.node("Hips")
	_check("crouching folds her legs", a.state == "crouch" and _rot("LegL").x > 50.0 and _rot("ShinL").x < -80.0, "leg=%.0f shin=%.0f" % [_rot("LegL").x, _rot("ShinL").x])
	_check("crouch lowers the hips, no squash", hips.position.y < 0.6 and is_equal_approx(player._body.scale.y, 1.0), "hips=%.2f" % hips.position.y)
	Input.action_release("crouch")
	await _frames(40)
	await _press("jump")
	await _frames(4)
	_check("jumping tucks her legs", (a.state == "jump" or a.state == "fall") and _rot("LegL").x > 10.0, "%s leg=%.0f" % [a.state, _rot("LegL").x])
	await _frames(60)


func _juno_upper_body() -> void:
	var a := player.anim
	var w := player.weapon
	_place(ARENA, 0.0)
	await _frames(10)
	Input.action_press("aim")
	player.aim_at(player.global_position + Vector3(0.0, 9.0, -10.0))
	await _frames(30)
	_check("aiming up pitches her chest", _rot("Chest").x > 8.0, "chest=%.1f" % _rot("Chest").x)
	Input.action_release("aim")
	await _frames(5)
	w.fired.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("firing kicks the weapon back", w.position.z > a._weapon_rest.z + 0.03, "dz=%.3f" % (w.position.z - a._weapon_rest.z))
	await _frames(30)
	Game.set_ammo(w.current, 0, 50)
	w.start_reload()
	await _frames(20)
	_check("reloading tilts the weapon and drops the left hand", w.reloading and w.rotation_degrees.z > 12.0 and _rot("ForearmL").x > 40.0, "roll=%.0f forearm=%.0f" % [w.rotation_degrees.z, _rot("ForearmL").x])
	await get_tree().create_timer(2.5).timeout
	_check("reload pose clears", not w.reloading and w.rotation_degrees.z < 3.0)
	_check("a stim plays its action", a.play("stim") and a.action == "stim")
	await get_tree().create_timer(0.45).timeout
	_check("the stim goes to her chest", _rot("ForearmL").x > 70.0, "forearm=%.0f" % _rot("ForearmL").x)
	await get_tree().create_timer(0.6).timeout
	_check("actions finish", a.action == "")
	_check("a throw plays its action", a.play("throw") and a.action == "throw")
	var wound := 0.0
	var release := 999.0
	var start := Time.get_ticks_msec()
	while a.action == "throw":
		await get_tree().process_frame
		var arm := _rot("ArmL").x
		if Time.get_ticks_msec() - start < 260:
			wound = maxf(wound, arm)
		elif wound > 0.0:
			release = minf(release, arm)
	_check("the throw winds up and whips through", wound > 75.0 and release < wound - 30.0, "wind-up=%.0f release=%.0f" % [wound, release])
	a.play("install")
	await get_tree().create_timer(0.6).timeout
	_check("installing uses both hands, weapon stowed", not w.visible and _rot("ArmR").x > 40.0 and _rot("Spine").x < -10.0)
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
	await get_tree().create_timer(1.0).timeout
	_check("she goes down", a.state == "down" and player.rig.rotation_degrees.x < -60.0, "%s %.0f" % [a.state, player.rig.rotation_degrees.x])
	_check("no actions while down", not a.play("stim"))
	player.revive(ARENA)
	await _frames(3)
	_check("revived, she's back on her feet", absf(player.rig.rotation_degrees.x) < 1.0 and player.weapon.visible and a.state != "down")


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
	var ranges := {}
	for f in 50:
		await get_tree().process_frame
		for kind in made:
			var e: Enemy = made[kind]
			var leg: String = e.anim.legs[0][0]
			var r: Vector3 = e.anim.pose.rot_of(leg)
			var v := r.y if e.anim._cfg["legs"] == "splay" else r.x
			var span: Vector2 = ranges.get(kind, Vector2(999.0, -999.0))
			ranges[kind] = Vector2(minf(span.x, v), maxf(span.y, v))
	var detail := ""
	for kind in ranges:
		var span: Vector2 = ranges[kind]
		detail += "%s=%.0f " % [kind, span.y - span.x]
		swing_ok = swing_ok and span.y - span.x > 10.0
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
	await get_tree().create_timer(main.INTRO_SLIDE + main.INTRO_HOLD + 0.5).timeout
	_check("the intro ends with Kestrel at the crash site", not main.intro_playing and kestrel.global_transform.is_equal_approx(rest))
	_check("Juno has control again", player.visible and player.is_physics_processing() and get_viewport().get_camera_3d() == player.camera())
	_check("the HUD comes back", main.hud._objective.is_visible_in_tree())
	main.play_intro()
	await _frames(5)
	await _press("interact")
	_check("interact skips the intro", not main.intro_playing and kestrel.global_transform.is_equal_approx(rest))
