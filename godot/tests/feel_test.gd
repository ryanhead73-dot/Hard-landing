extends "res://tests/test_base.gd"
## Refinement M10 game feel: the dodge roll, camera shake and recoil kick, sprint FOV, pool
## splashes, damage-direction arcs, hit stop and the graphics setting. Run:
##   godot --headless --path . res://tests/feel_test.tscn

const ARENA := Vector3(45.0, 0.0, 45.0)


func _name() -> String:
	return "FEEL TEST"


func _run() -> void:
	await _frames(30)
	_clear_enemies()
	await _roll()
	await _shake()
	await _sprint_fov()
	await _splash()
	await _damage_arcs()
	await _rifle()
	await _weapon_swap()
	await _hit_stop()
	await _accessibility()
	await _key_bindings()
	await _pad_focus()
	_graphics()
	finished = true


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, main.site.height_at(p.x, p.z) + 0.3, p.z)


func _roll() -> void:
	_place(_ground(ARENA), 0.0)
	await _frames(20)
	var start := player.global_position
	await _press("dodge")
	_check("dodge starts a roll", player.is_rolling(), "t=%.2f" % player.roll_t)
	_check("Juno tucks into the roll", player.anim.state == "roll", player.anim.state)
	var hp := player.health
	player.take_damage(30.0, start + Vector3(0, 0, -3))
	_check("the start of a roll dodges damage", player.health == hp, "%.0f -> %.0f" % [hp, player.health])
	await _frames(45)
	_check("the roll ends", not player.is_rolling())
	var moved := _flat_distance(player.global_position, start)
	# Standing still, the roll goes backwards (+z when facing north).
	_check("a standing roll carries her back a few metres", moved > 2.0 and player.global_position.z > start.z, "moved %.2f" % moved)
	_check("she's upright again", absf(player.anim.bone_rot("Hips").x) < 10.0 and player.anim.bone_pos("Hips").y > 0.8 and player.anim.state != "roll", "hips %.0f %.2f" % [player.anim.bone_rot("Hips").x, player.anim.bone_pos("Hips").y])
	await _frames(30)
	# Rolling along the move direction.
	start = player.global_position
	Input.action_press("move_right")
	await _frames(3)
	await _press("dodge")
	await _frames(40)
	Input.action_release("move_right")
	_check("a roll follows the move direction", player.global_position.x - start.x > 2.0, "dx %.2f" % (player.global_position.x - start.x))
	# No rolling in mid-air.
	await _frames(30)
	player.velocity.y = 4.0
	player.global_position += Vector3.UP * 1.5
	await _frames(2)
	_check("no roll in mid-air", not player.start_roll())
	await _frames(90)


func _shake() -> void:
	player.trauma = 0.0
	player.take_damage(20.0, player.global_position + Vector3(4, 0, 0))
	_check("a hit shakes the camera", player.trauma > 0.15, "trauma %.2f" % player.trauma)
	await get_tree().create_timer(1.2).timeout
	_check("the shake settles", player.trauma == 0.0 and absf(player.camera().h_offset) < 0.001)
	player.weapon.equip("rifle")
	player.weapon.refill()
	await get_tree().create_timer(1.0).timeout
	var aim := -player.camera().global_basis.z
	var fired := player.weapon.try_fire(false)
	var kick := player._kick
	# The kick decays with real time, so a slow headless frame can eat it before a frame is
	# drawn: apply it with no time passed and read the camera.
	player._update_shake(0.0)
	_check("a shot kicks the view", fired and kick > 0.02 and player.camera().v_offset < -0.02, "fired=%s kick %.3f v_offset %.4f" % [fired, kick, player.camera().v_offset])
	await _frames(1)
	_check("one shot's climb barely moves the aim", (-player.camera().global_basis.z).angle_to(aim) < 0.01)
	await _frames(40)
	_check("the kick recovers", absf(player.camera().v_offset) < 0.003, "%.4f" % player.camera().v_offset)
	_check("hit stop is skipped headless", Engine.time_scale == 1.0)
	Game.screen_shake = 0.0
	player.take_damage(10.0, player.global_position + Vector3(4, 0, 0))
	await _frames(2)
	_check("screen shake can be turned off", absf(player.camera().h_offset) + absf(player.camera().v_offset) < 0.0001)
	Game.screen_shake = 1.0
	player.health = player.max_health()


func _sprint_fov() -> void:
	_place(_ground(ARENA), 0.0)
	await _frames(10)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(50)
	var wide := player.camera().fov
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_check("sprinting widens the view", wide > player.fov + 4.0, "fov %.1f" % wide)
	await _frames(60)
	_check("the view settles after the sprint", absf(player.camera().fov - player.fov) < 1.0, "fov %.1f" % player.camera().fov)


func _splash() -> void:
	var pool: Array = main.site.pools[0]
	var centre: Vector3 = main.site.to_global(pool[0])
	_place(Vector3(centre.x, main.site.height_at(centre.x - main.site.global_position.x, centre.z - main.site.global_position.z) + 0.3, centre.z), 0.0)
	await _frames(20)
	_check("Juno is standing in the pool", main.site.in_pool(player.global_position), "%s" % player.global_position)
	var before := get_tree().get_nodes_in_group("vfx_burst").size()
	var seen := 0
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
		seen = maxi(seen, get_tree().get_nodes_in_group("vfx_burst").size() - before)
	Input.action_release("move_forward")
	_check("footsteps in a pool splash", seen > 0, "%d" % seen)
	_place(_ground(ARENA), 0.0)
	await _frames(10)
	_check("dry ground is not a pool", not main.site.in_pool(player.global_position))


func _damage_arcs() -> void:
	var hud: Node = main.hud
	await get_tree().create_timer(1.5).timeout
	_check("no damage arcs when unhurt", hud.hurt_mark_count() == 0, "%d" % hud.hurt_mark_count())
	player.take_damage(5.0, player.global_position + Vector3(0, 0, 6))
	_check("a hit shows where it came from", hud.hurt_mark_count() == 1)
	await get_tree().create_timer(1.6).timeout
	_check("the damage arc fades", hud.hurt_mark_count() == 0)


## M13.5: the rifle blooms under sustained fire and settles, moving widens the spread, the
## muzzle climbs and mostly comes back, casings fly, and the crosshair shows the spread.
func _rifle() -> void:
	_clear_enemies()
	_place(_ground(ARENA), 0.0)
	await _frames(30)
	var w := player.weapon
	w.equip("rifle")
	w.refill()
	await get_tree().create_timer(0.8).timeout
	var still := w.current_spread(false)
	var hud: Hud = main.hud
	var gap0 := hud.crosshair_spread_px(player.camera())
	var pitch0 := player._pitch.rotation.x
	var bursts := get_tree().get_nodes_in_group("vfx_burst").size()
	var shots := 0
	for i in 12:
		if w.try_fire(false):
			shots += 1
		await get_tree().create_timer(w.fire_interval() + 0.01).timeout
	_check("sustained fire blooms the spread", w.bloom > 0.01 and w.current_spread(false) > still * 1.8, "%d shots bloom %.4f spread %.4f -> %.4f" % [shots, w.bloom, still, w.current_spread(false)])
	_check("the crosshair opens with it", hud.crosshair_spread_px(player.camera()) > gap0 + 4.0, "%.1f -> %.1f px" % [gap0, hud.crosshair_spread_px(player.camera())])
	var climbed := player._pitch.rotation.x - pitch0
	_check("the muzzle climbs", climbed > deg_to_rad(1.0), "%.2f deg" % rad_to_deg(climbed))
	_check("casings and smoke fly", get_tree().get_nodes_in_group("vfx_burst").size() > bursts + 6)
	await get_tree().create_timer(0.6).timeout
	var left := player._pitch.rotation.x - pitch0
	_check("most of the climb is pulled back", left < climbed * 0.4 and left > 0.0, "%.2f of %.2f deg" % [rad_to_deg(left), rad_to_deg(climbed)])
	_check("the bloom settles", w.bloom < 0.004, "%.4f" % w.bloom)
	_check("aiming tightens it", w.current_spread(true) < w.current_spread(false) * 0.5)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(40)
	_check("moving widens the spread", w.move_penalty > 0.5 and w.current_spread(false) > still * 1.5, "penalty %.2f" % w.move_penalty)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _frames(30)


func _graphics() -> void:
	var env: Environment = main._env
	var vp := get_viewport()
	Game.graphics = Game.GRAPHICS_HIGH
	Game.graphics_changed.emit()
	_check("High shadows every lamp", main.kestrel._aux_lights.all(func(l): return l.shadow_enabled and l.omni_shadow_mode == OmniLight3D.SHADOW_CUBE))
	_check("High adds indirect light, haze, soft shadows and 4x MSAA", env.ssil_enabled and env.ssao_enabled and env.volumetric_fog_density > 0.0 and main._sun.light_angular_distance > 0.0 and vp.msaa_3d == Viewport.MSAA_4X)
	Game.graphics = Game.GRAPHICS_MEDIUM
	Game.graphics_changed.emit()
	var lit: Array = main.kestrel._aux_lights.filter(func(l): return l.shadow_enabled)
	_check("Medium shadows only the workshop lamps, two passes each", lit.size() == Kestrel.SHADOW_LAMPS and lit.all(func(l): return l.omni_shadow_mode == OmniLight3D.SHADOW_DUAL_PARABOLOID), "%d shadowed" % lit.size())
	_check("Medium keeps SSAO and the haze, drops indirect light", not env.ssil_enabled and env.ssao_enabled and env.volumetric_fog_density > 0.0 and main._sun.directional_shadow_max_distance == 120.0 and vp.msaa_3d == Viewport.MSAA_2X)
	Game.graphics = Game.GRAPHICS_LOW
	Game.graphics_changed.emit()
	_check("Low drops SSAO, haze and cascades, renders at 85%", not env.ssil_enabled and not env.ssao_enabled and env.volumetric_fog_density == 0.0 and env.volumetric_fog_enabled and main._sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and vp.scaling_3d_scale < 1.0)
	_check("Low drops the lamps' shadows", main.kestrel._aux_lights.all(func(l): return not l.shadow_enabled))
	_check("the presets are named Low, Medium, High", Game.GRAPHICS_NAMES == ["Low", "Medium", "High"])
	Game.graphics = Game.GRAPHICS_MEDIUM
	Game.graphics_changed.emit()


## Switching weapons tips the old gun muzzle-down, swaps it at the bottom and brings the new one
## up, instead of popping.
func _weapon_swap() -> void:
	var w: Weapon = player.weapon
	Game.give_weapon("scattergun")
	w.equip("rifle")
	await get_tree().create_timer(Weapon.SWITCH_TIME + 0.1).timeout
	_check("no dip at rest", w.swap_dip() == 0.0 and w._models["rifle"].rotation.x == 0.0)
	w.equip("scattergun")
	await get_tree().create_timer(Weapon.SWITCH_TIME * 0.3).timeout
	_check("early in a switch the rifle is still in her hands, tipping down",
		w.shown_model() == "rifle" and w._models["rifle"].visible and not w._models["scattergun"].visible and w._models["rifle"].rotation.x < -0.05,
		"%s %.2f" % [w.shown_model(), w._models["rifle"].rotation.x])
	_check("it can't fire mid-switch", not w.try_fire(false))
	await get_tree().create_timer(Weapon.SWITCH_TIME * 0.4).timeout
	_check("past halfway the scattergun has replaced it, coming up", w.shown_model() == "scattergun" and w._models["scattergun"].visible and not w._models["rifle"].visible,
		w.shown_model())
	await get_tree().create_timer(Weapon.SWITCH_TIME * 0.5).timeout
	_check("and the switch settles level", w.swap_dip() == 0.0 and w._models["scattergun"].rotation.x == 0.0, "%.2f" % w._models["scattergun"].rotation.x)
	w.equip("rifle")
	await get_tree().create_timer(Weapon.SWITCH_TIME + 0.1).timeout


## Hit-stop always lets go: overlapping stops, a pause mid-stop and the player being freed
## mid-stop (quitting to the title) all come back to full speed. (Jake saw it stick.)
func _hit_stop() -> void:
	Game.hit_stop(0.1, true)
	Game.hit_stop(0.05, true)
	_check("a hit-stop slows time", Engine.time_scale == Game.HIT_STOP_SCALE)
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check("overlapping stops end on time", Engine.time_scale == 1.0, str(Engine.time_scale))
	Game.hit_stop(5.0, true)
	await get_tree().create_timer(Game.HIT_STOP_MAX + 0.15, true, false, true).timeout
	_check("no stop lasts longer than the cap", Engine.time_scale == 1.0, str(Engine.time_scale))
	Game.hit_stop(0.2, true)
	get_tree().paused = true
	await get_tree().create_timer(0.05, true, false, true).timeout
	_check("pausing mid-stop restores full speed", Engine.time_scale == 1.0, str(Engine.time_scale))
	get_tree().paused = false
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.05, true, false, true).timeout
	_check("a stray slow-down is put right", Engine.time_scale == 1.0, str(Engine.time_scale))


## Accessibility settings: toggle aim latches and unlatches, subtitles hide or grow, and both
## are in the pause menu and saved.
func _accessibility() -> void:
	player.revive(_ground(main.SPAWN + Vector3(8.0, 0.0, 8.0)))
	await _frames(5)
	Game.toggle_aim = true
	await _press("aim")
	await _frames(3)
	_check("toggle aim: one press aims and it stays on", player.aiming)
	await _press("aim")
	await _frames(3)
	_check("a second press lets go", not player.aiming)
	await _press("aim")
	player.revive(player.global_position)
	await _frames(3)
	_check("going down drops toggled aim", not player.aiming)
	Game.toggle_aim = false
	var hud: Hud = main.hud
	var base: int = hud._voice.get_theme_font_size("normal_font_size")
	Game.subtitles = 3
	Game.apply_settings()
	_check("largest subtitles are half as big again", hud._voice.get_theme_font_size("normal_font_size") >= roundi(base * 1.45), "%d vs %d" % [hud._voice.get_theme_font_size("normal_font_size"), base])
	Game.subtitles = 0
	Game.apply_settings()
	hud.set_voice("Juno", "Testing.")
	_check("subtitles off hides them", not hud._voice.visible)
	Game.subtitles = 1
	Game.apply_settings()
	hud.set_voice("Juno", "Testing.")
	_check("and on shows them", hud._voice.visible)
	hud.set_voice("", "")
	var menu: Node = main.get_children().filter(func(c): return c is PauseMenu)[0]
	_check("the pause menu has aim mode and subtitles", menu.find_child("AimMode", true, false) != null and menu.find_child("Subtitles", true, false) != null)
	var cfg := ConfigFile.new()
	Game.toggle_aim = true
	Game.subtitles = 2
	Game.save_settings()
	cfg.load(Game.SETTINGS_PATH)
	_check("both are saved", cfg.get_value("access", "toggle_aim") == true and cfg.get_value("access", "subtitles") == 2)
	Game.toggle_aim = false
	Game.subtitles = 1
	Game.save_settings()
	Game.apply_settings()


## Rebinding: a new key drives the action, the old one stops, a clash swaps, prompts and the
## help line follow, it saves, and reset puts everything back.
func _key_bindings() -> void:
	_check("default bindings come from the game's key table", Game.primary_key("interact") == KEY_E and Game.key_label("interact") == "E")
	Game.rebind("interact", KEY_H)
	_check("rebinding moves the action to the new key", _has_key("interact", KEY_H) and not _has_key("interact", KEY_E))
	Game.rebind("reload", KEY_H)
	_check("taking a key in use swaps it over", Game.primary_key("reload") == KEY_H and Game.primary_key("interact") == KEY_R,
		"%s %s" % [Game.key_label("reload"), Game.key_label("interact")])
	_check("prompts follow the binding", Game.device_text("[E] Open the armoury locker") == "[R] Open the armoury locker", Game.device_text("[E] Open the armoury locker"))
	_check("the controls line follows it", Hud.help_text().contains("H reload") and Hud.help_text().contains("R interact"), Hud.help_text())
	Game.save_settings()
	var cfg := ConfigFile.new()
	cfg.load(Game.SETTINGS_PATH)
	_check("bindings are saved", int(cfg.get_value("keys", "reload", 0)) == KEY_H)
	var menu: PauseMenu = main.get_children().filter(func(c): return c is PauseMenu)[0]
	menu.open()
	menu._open_bindings()
	await _frames(2)
	_check("the pause menu opens the bindings list", menu.bindings.visible and not menu.visible and menu.bindings._buttons.size() == Game.REBINDABLE.size())
	menu.bindings._listen("jump")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	menu.bindings._input(ev)
	_check("pressing a key while listening binds it", Game.primary_key("jump") == KEY_J and menu.bindings.listening == "")
	Game.reset_keys()
	_check("reset puts the defaults back", Game.primary_key("interact") == KEY_E and Game.primary_key("reload") == KEY_R and Game.primary_key("jump") == KEY_SPACE and _has_key("interact", KEY_E))
	menu.bindings.close()
	await _frames(2)
	_check("closing it returns to the pause menu", menu.visible and not menu.bindings.visible)
	menu.close()


## With a pad, every menu holds a focused control so the d-pad and A work; focus comes back
## after a panel rebuilds its buttons, and B backs out of listening for a key.
func _pad_focus() -> void:
	var menu: PauseMenu = main.get_children().filter(func(c): return c is PauseMenu)[0]
	var vp := get_viewport()
	Game.using_pad = true
	menu.open()
	await _frames(2)
	var owner := vp.gui_get_focus_owner()
	_check("the pause menu focuses Resume on a pad", owner != null and owner.name == "Resume", str(owner))
	menu._open_bindings()
	await _frames(2)
	owner = vp.gui_get_focus_owner()
	_check("the bindings list takes focus", owner != null and menu.bindings.is_ancestor_of(owner), str(owner))
	menu.bindings._listen("jump")
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	menu.bindings._input(back)
	_check("B stops listening without closing", menu.bindings.listening == "" and menu.bindings.visible and Game.primary_key("jump") == KEY_SPACE)
	menu.bindings.close()
	await _frames(2)
	menu.close()
	await _frames(1)
	var fab: FabricatorMenu = main.fabricator
	var was := [Game.scrap, Game.stims]
	Game.scrap = 999
	Game.stims = 0
	fab.open()
	await _frames(2)
	owner = vp.gui_get_focus_owner()
	_check("the fabricator focuses a build button", owner is Button and fab.is_ancestor_of(owner), str(owner))
	fab._refresh()
	await _frames(3)
	owner = vp.gui_get_focus_owner()
	_check("focus comes back after the list rebuilds", owner != null and fab.is_ancestor_of(owner) and not owner.is_queued_for_deletion(), str(owner))
	fab.close()
	Game.scrap = was[0]
	Game.stims = was[1]
	Game.using_pad = false
	await _frames(1)


func _has_key(action: String, key: int) -> bool:
	return InputMap.action_get_events(action).any(func(e): return e is InputEventKey and e.physical_keycode == key)
