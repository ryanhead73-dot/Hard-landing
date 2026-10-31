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
	_check("the rig is upright again", player.anim.pose.root.rotation.length() < 0.01 and player.anim.state != "roll")
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
	_check("the kick never moves the aim", (-player.camera().global_basis.z).angle_to(aim) < 0.01)
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


func _graphics() -> void:
	var env: Environment = main._env
	Game.graphics = 1
	Game.graphics_changed.emit()
	_check("quality turns on indirect light and haze", env.ssil_enabled and env.volumetric_fog_density > 0.0)
	Game.graphics = 0
	Game.graphics_changed.emit()
	_check("performance turns them off", not env.ssil_enabled and env.volumetric_fog_density == 0.0 and env.volumetric_fog_enabled)
	Game.graphics = 1
	Game.graphics_changed.emit()
