extends "res://tests/test_base.gd"
## M13 vertical slice (relay station / aux power): camera framing and boom recovery, jump
## forgiveness and braking, scuttler stagger, knockback and death, and the opening objective.
## Run:
##   godot --headless --path . res://tests/slice_test.tscn

const ARENA := Vector3(45.0, 0.0, 45.0)


func _name() -> String:
	return "SLICE TEST"


## Missions stay on: the opening objective is part of what this suite checks.
func _bypass_missions() -> bool:
	return false


func _run() -> void:
	await _frames(30)
	_opening_objective()
	await _onboarding()
	_clear_enemies()
	await _framing()
	await _boom()
	await _jumps()
	await _braking()
	await _stagger()
	await _death()
	await _arrival()
	await _gamepad()
	await _intro()
	_install_signals()
	finished = true


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, main.site.height_at(p.x, p.z) + 0.3, p.z)


## From the crash site the first line names the trip, not the first chore at the relay.
func _opening_objective() -> void:
	var text := Game.objective_text()
	_check("the opening objective names the trip to the relay", text.contains("relay station") and not text.contains("breaker"), text)


## Juno stands left of the crosshair with clear space between her shoulder and its centre.
func _framing() -> void:
	_place(_ground(ARENA), 0.0)
	await _frames(30)
	var cam := player.camera()
	var size := cam.get_viewport().get_visible_rect().size
	var chest := cam.unproject_position(player.global_position + Vector3.UP * 1.2)
	var shoulder := cam.unproject_position(player.global_position + Vector3.UP * 1.45 + player.camera().global_basis.x * 0.35)
	_check("Juno sits in the left of the frame", chest.x < size.x * 0.42, "chest at %.2f of width" % (chest.x / size.x))
	_check("her shoulder stays clear of the crosshair", shoulder.x < size.x * 0.46, "shoulder at %.2f" % (shoulder.x / size.x))
	_check("the camera sits behind her at the full boom", absf(player.boom_current() - player.boom_length) < 0.05, "%.2f" % player.boom_current())


## After a squeeze the camera eases back out instead of popping, and never past the wall.
func _boom() -> void:
	player._boom_smooth = 1.0
	await _frames(6)
	var mid := player.boom_current()
	_check("the boom eases back out", mid > 1.0 and mid < player.boom_length - 0.5, "%.2f" % mid)
	_check("the camera never sits past the spring arm's hit", player.camera().position.z <= 0.0001, "%.3f" % player.camera().position.z)
	await get_tree().create_timer(1.2).timeout
	_check("the boom gets all the way back", absf(player.boom_current() - player.boom_length) < 0.05, "%.2f" % player.boom_current())


## A jump just after stepping off an edge still works; a press just before landing is kept.
func _jumps() -> void:
	var ground := _ground(ARENA)
	# Coyote time: airborne, but only just.
	_place(ground + Vector3.UP * 1.2, 0.0)
	await get_tree().physics_frame
	player._since_floor = 0.0
	await _press("jump")
	_check("a jump just after leaving the ground still fires", player.velocity.y > 1.0, "vy %.2f" % player.velocity.y)
	await _frames(90)
	# Too late: well after leaving the ground.
	_place(ground + Vector3.UP * 3.0, 0.0)
	await _frames(20)
	await _press("jump")
	var vy := player.velocity.y
	_check("no jump long after leaving the ground", vy < 0.0, "vy %.2f" % vy)
	# Buffer: pressed while still falling, jumps on touchdown.
	var rose := false
	for i in 120:
		if player.is_on_floor() or player.velocity.y > 1.0:
			break
		if player.global_position.y - ground.y < 0.45:
			break
		await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	for i in 20:
		await get_tree().physics_frame
		if player.velocity.y > 1.0:
			rose = true
			break
	_check("a jump pressed just before landing is kept", rose)
	await _frames(90)


## Letting go of the stick stops her within a short step.
func _braking() -> void:
	_place(_ground(ARENA), 0.0)
	await _frames(10)
	Input.action_press("move_forward")
	await get_tree().create_timer(0.6).timeout
	Input.action_release("move_forward")
	await get_tree().physics_frame
	var from := player.global_position
	await _frames(30)
	var slid := _flat_distance(player.global_position, from)
	_check("she stops within a short step", slid < 0.45, "slid %.2f m" % slid)


func _scuttler_near() -> Scuttler:
	var at := _ground(ARENA) + Vector3(0.0, 0.0, -2.5)
	var s: Scuttler = main.spawn_enemy("scuttler", at)
	s.target = player
	return s


## A solid hit or a weak-spot hit during the wind-up breaks the bite; a graze doesn't.
func _stagger() -> void:
	_place(_ground(ARENA), 0.0)
	player.health = player.max_health()
	await _frames(5)
	var s := _scuttler_near()
	await _frames(5)
	s.hunting = true
	s.state = Scuttler.State.WINDUP
	s._timer = s.windup_time
	s.take_damage(4.0, s.global_position + Vector3.UP * 0.2, Vector3.FORWARD)
	_check("a graze doesn't break the wind-up", s.state == Scuttler.State.WINDUP, s.anim_state())
	var hp := player.health
	s.take_damage(20.0, s.global_position + Vector3.UP * 0.2, Vector3.FORWARD)
	_check("a solid hit mid wind-up staggers it", s.state == Scuttler.State.STAGGER, s.anim_state())
	_check("a hit shoves it back", Vector2(s.velocity.x, s.velocity.z).length() > 2.0, "%.2f m/s" % Vector2(s.velocity.x, s.velocity.z).length())
	await get_tree().create_timer(s.windup_time + 0.1).timeout
	_check("a staggered scuttler doesn't bite", player.health >= hp, "%.0f -> %.0f" % [hp, player.health])
	await get_tree().create_timer(0.5).timeout
	_check("it recovers and comes back", s.state != Scuttler.State.STAGGER, s.anim_state())
	# A weak-spot hit staggers even when light.
	s.state = Scuttler.State.WINDUP
	s._timer = s.windup_time
	var spine := s.weak_spot()
	s.take_damage(4.0, spine, Vector3.FORWARD)
	_check("a light weak-spot hit staggers it too", s.last_hit_crit and s.state == Scuttler.State.STAGGER, "crit=%s %s" % [s.last_hit_crit, s.anim_state()])
	s.queue_free()
	await _frames(5)


## The killing shot bowls it over along the line of fire.
func _death() -> void:
	var s := _scuttler_near()
	await _frames(5)
	var shot := Vector3(1.0, 0.0, 0.0)
	var killed := s.take_damage(999.0, s.global_position + Vector3.UP * 0.2, shot)
	await get_tree().physics_frame
	_check("a kill flings it along the shot", killed and s.velocity.x > 2.5, "v %s" % s.velocity)
	await get_tree().create_timer(0.5).timeout
	var tilt := (s._visual.quaternion as Quaternion).get_angle()
	_check("it rolls over as it dies", tilt > 1.5, "%.2f rad" % tilt)
	await _frames(5)


## Arriving at the relay switches the objective to the first job there.
func _arrival() -> void:
	var site: ExpeditionSite = main.sites["aux_power"]
	_place(site.to_global(Vector3(0.0, 0.5, 16.0)), 0.0)
	await _frames(20)
	var text := Game.objective_text()
	_check("at the relay the objective is the breakers", text.contains("breaker"), text)


func _pad_axis(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)


func _pad_button(button: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)


## Everything Juno can do is on the pad, the right stick looks, prompts name pad buttons, and B
## dodges rather than opening the pause menu.
func _gamepad() -> void:
	var missing: Array = []
	for action in main.KEYS.keys() + main.BUTTONS.keys():
		if action.begins_with("weapon_") and action != "weapon_next":
			continue
		if not InputMap.action_get_events(action).any(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion):
			missing.append(action)
	_check("every play action has a pad binding", missing.is_empty(), str(missing))
	var b_cancels := InputMap.action_get_events("ui_cancel").any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B)
	var start_pauses := InputMap.action_get_events("ui_cancel").any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_START)
	_check("B is not cancel in play; Start pauses", not b_cancels and start_pauses)
	_place(_ground(ARENA), 0.0)
	await _frames(5)
	var yaw: float = player._yaw.rotation.y
	_pad_axis(JOY_AXIS_RIGHT_X, 1.0)
	await get_tree().create_timer(0.3).timeout
	_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	await _frames(2)
	var turned := wrapf(yaw - player._yaw.rotation.y, -PI, PI)
	_check("the right stick turns the view", turned > 0.4, "%.2f rad" % turned)
	_check("pad input switches prompts to the pad", Game.using_pad and Game.device_text("[E] Take it") == "[Y] Take it", Game.device_text("[E] Take it"))
	# A small nudge near the centre turns far less than proportionally (response curve).
	yaw = player._yaw.rotation.y
	_pad_axis(JOY_AXIS_RIGHT_X, 0.3)
	await get_tree().create_timer(0.3).timeout
	_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	await _frames(2)
	var fine := wrapf(yaw - player._yaw.rotation.y, -PI, PI)
	_check("small stick moves aim finely", fine > 0.0 and fine < turned * 0.2, "%.3f vs %.3f" % [fine, turned])
	# Right trigger fires.
	player.weapon.refill()
	var before := Game.ammo_in_mag("rifle")
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(10)
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _frames(2)
	_check("the right trigger fires", Game.ammo_in_mag("rifle") < before, "%d -> %d" % [before, Game.ammo_in_mag("rifle")])
	# B rolls.
	await get_tree().physics_frame
	_pad_button(JOY_BUTTON_B, true)
	await _frames(2)
	_pad_button(JOY_BUTTON_B, false)
	_check("B dodges", player.is_rolling() and not get_tree().paused)
	await _frames(40)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await _frames(2)
	_check("a key press switches back to keyboard prompts", not Game.using_pad)


## One hint at a time, when it's useful, cleared by doing the thing; remembered in the save.
func _onboarding() -> void:
	Game.hints_seen.clear()
	main.onboarding.current = ""
	main.onboarding._quiet = 0.0
	await _frames(5)
	_check("the first hint is move and look", main.hud.hint_text().contains("move"), main.hud.hint_text())
	_check("the old controls strip is gone", not main.hud._help.visible)
	_place(_ground(ARENA), 0.0)
	await _frames(3)
	main.onboarding._start = player.global_position
	await _walk(1.6)
	_check("moving clears the move hint", not main.hud.hint_text().contains("move") and main.onboarding.seen("move"), main.hud.hint_text())
	var data := Game.session_state()
	Game.hints_seen.clear()
	Game.apply_session(data)
	_check("seen hints are saved", "move" in Game.hints_seen)
	# Being hurt offers the roll.
	main.onboarding._quiet = 0.0
	main.onboarding.current = ""
	player.take_damage(5.0, player.global_position + Vector3(3, 0, 0))
	_check("a first hit offers the roll", main.onboarding.current == "dodge" and main.hud.hint_text().contains("roll"), main.hud.hint_text())
	await _press("dodge")
	await _frames(3)
	_check("rolling clears it", main.onboarding.current != "dodge" and main.onboarding.seen("dodge"))
	await _frames(40)
	# Everything shown once doesn't come back; the rest stay quiet for the other checks.
	Game.hints_seen.assign(Onboarding.HINTS.keys())
	main.onboarding.finish()
	player.health = player.max_health()


## A new game's intro ends looking across the basin at the relay, and Juno faces that way.
func _intro() -> void:
	_place(_ground(ARENA), 1.0)
	main.play_intro()
	await get_tree().create_timer(main.INTRO_FALL + main.INTRO_SLIDE + main.INTRO_HOLD + 1.0).timeout
	_check("after the crash the camera turns to the first goal", main._cine_focus != null)
	await get_tree().create_timer(main.INTRO_REVEAL + 1.5).timeout
	_check("the intro hands over to Juno", not main.intro_playing and player.camera().current)
	var w: Vector3 = main._waypoint()
	var to := Vector3(w.x - player.global_position.x, 0.0, w.z - player.global_position.z).normalized()
	var fwd := -player.camera().global_basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	_check("Juno starts facing the relay", fwd.angle_to(to) < 0.35, "%.2f rad off" % fwd.angle_to(to))


## Installing a repair announces itself for the payoff staging.
func _install_signals() -> void:
	var got: Array = []
	main.install_started.connect(func(id): got.append("start:" + id))
	main.install_finished.connect(func(id): got.append("end:" + id))
	Game.carrying = "aux_cell"
	main._install("aux_power")
	_check("install announces start and finish", got == ["start:aux_power", "end:aux_power"], str(got))
