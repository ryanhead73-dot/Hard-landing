extends Node
## Headless walk-through of the vertical slice. Run:
##   godot --headless --path . res://tests/smoke_test.tscn
## Walks the ship's routes, fights a scuttler, runs the recover/return/install loop, buys an
## upgrade and checks death and respawn. Prints PASS/FAIL lines and exits 1 on any failure.

var main: Node3D
var kestrel: Kestrel
var player: Player
var failures := 0
var finished := false


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	kestrel = main.kestrel
	player = main.player
	await _run()
	# A script error aborts _run without a FAIL line, so make sure it got to the end.
	_check("test ran to the end", finished)
	print("SMOKE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures else 0)


func _run() -> void:
	await _frames(30)
	_check("player lands at spawn", player.is_on_floor(), "y=%.2f" % player.global_position.y)
	_check("relay station faces the ship", main.station.global_basis.z.dot((kestrel.global_position - main.station.global_position).normalized()) > 0.95)
	_check("sound effects load", Sfx.SOUNDS.all(func(id): return Sfx.has_sound(id)))
	var wind: AudioStreamWAV = load("res://audio/wind_loop.wav")
	_check("wind loop has loop points", wind.loop_mode != AudioStreamWAV.LOOP_DISABLED and wind.loop_end > 0, "mode=%d end=%d" % [wind.loop_mode, wind.loop_end])
	var pause: PauseMenu = main.find_children("*", "PauseMenu", false, false)[0]
	pause.open()
	_check("pause menu pauses the game", get_tree().paused and pause.visible)
	pause.close()
	_check("resume unpauses", not get_tree().paused and not pause.visible)
	_clear_scuttlers()

	# --- Ship routes -------------------------------------------------------------------------
	_place(kestrel.to_global(kestrel.plan(12.9, 0.0, 20.6)), 0.0)
	await _walk(3.0)
	var local := kestrel.to_local(player.global_position)
	_check("side door steps reach the workshop", local.z < 3.6 and local.y > -0.15, "local=%s" % local)

	_place(kestrel.to_global(kestrel.plan(14.6, 0.1, 13.0)), PI * 0.5)
	await _frames(10)
	_check("workshop camera boom is clear", player.boom_current() > player.boom_length - 0.2, "boom=%.2f" % player.boom_current())
	await _walk(3.5)
	local = kestrel.to_local(player.global_position)
	_check("stairs reach the raised cockpit", local.x < kestrel.plan(8.0, 0, 0).x and local.y > 1.0, "local=%s" % local)

	_place(kestrel.to_global(kestrel.plan(27.0, 0.1, 13.0)), 0.0)
	Input.action_press("crouch")
	await _walk(2.5)
	local = kestrel.to_local(player.global_position)
	_check("crouch through crawlway hatch", local.z < kestrel.plan(0, 0, 10.1).z and local.z > kestrel.plan(0, 0, 9.3).z, "local=%s" % local)
	Input.action_release("crouch")
	await _frames(5)
	_check("stays crouched under crawlway ceiling", player.crouching)
	_place(main.SPAWN, 0.0)
	await _frames(10)

	# --- Combat ------------------------------------------------------------------------------
	var arena := Vector3(60.0, 0.5, -70.0)
	_place(arena, 0.0)
	await _frames(10)
	var enemy: Scuttler = main.spawn_scuttler(arena + Vector3(0.6, 0.0, -9.0))
	await _frames(10)
	var hits := [0]
	player.weapon.hit_confirmed.connect(func(_k): hits[0] += 1)
	Input.action_press("fire")
	for i in 240:
		if not is_instance_valid(enemy) or enemy.state == Scuttler.State.DEAD:
			break
		player.aim_at(enemy.global_position + Vector3.UP * 0.55)
		await get_tree().physics_frame
	Input.action_release("fire")
	_check("rifle kills a scuttler", is_instance_valid(enemy) and enemy.state == Scuttler.State.DEAD, "hits=%d" % hits[0])
	await _frames(5)
	var scrap_before := Game.scrap
	for s in get_tree().get_nodes_in_group("scrap"):
		if not is_instance_valid(s):
			continue
		_place(s.global_position + Vector3.UP * 0.3, 0.0)
		await _frames(20)
	_check("scrap drops and is collected", Game.scrap > scrap_before, "scrap=%d" % Game.scrap)

	# A wall between the scuttler and the player: it has to find a way around.
	player.revive(arena)
	var wall := StaticBody3D.new()
	wall.collision_layer = Game.LAYER_WORLD
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(7.0, 2.5, 0.4)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	main.add_child(wall)
	wall.global_position = arena + Vector3(0.0, 0.75, -3.5)
	var flanker: Scuttler = main.spawn_scuttler(arena + Vector3(0.5, 0.0, -7.0))
	flanker.alert(false)
	var closest := 99.0
	for i in 60 * 8:
		await get_tree().physics_frame
		closest = minf(closest, flanker.global_position.distance_to(player.global_position))
		if closest < flanker.attack_range + 0.5:
			break
	_check("scuttler paths around a wall", closest < flanker.attack_range + 0.5, "closest=%.1f" % closest)
	flanker.queue_free()
	wall.queue_free()
	await _frames(5)

	player.revive(arena)
	var biter: Scuttler = main.spawn_scuttler(arena + Vector3(0.0, 0.0, -3.0))
	biter.alert(false)
	await get_tree().create_timer(2.0).timeout
	_check("scuttler bites the player", player.health < player.max_health(), "health=%.0f" % player.health)
	biter.queue_free()

	# --- Recover, return, install ------------------------------------------------------------
	player.revive(kestrel.to_global(kestrel.interact_points["aux_power"]) + Vector3.UP * 0.2)
	await _frames(10)
	_check("aux bay asks for a power cell", main._interaction.get("label", "").contains("needs"), main._interaction.get("label", ""))
	await _press("interact")
	_check("cannot install without the cell", not kestrel.is_repaired("aux_power"))

	_clear_scuttlers()
	player.revive(main.station.cell_point() + Vector3.UP * 0.2)
	await _frames(10)
	_check("cell prompt at the station", main._interaction.get("label", "").contains("power cell"), main._interaction.get("label", ""))
	await _press("interact")
	_check("cell is carried", Game.carrying == "aux_cell" and not main.station.has_cell())
	_check("ambush spawns on the way home", get_tree().get_nodes_in_group("scuttlers").size() >= 3)
	_clear_scuttlers()

	_check("one crate can be searched", main.station.crate_count() == 4)
	player.revive(main.station.crate_point(0) + Vector3(0.0, 0.2, 1.2))
	await _frames(10)
	var before := Game.scrap
	await _press("interact")
	_check("searching a crate gives scrap", Game.scrap == before + RelayStation.CRATE_SCRAP, "scrap=%d" % Game.scrap)

	player.revive(kestrel.to_global(kestrel.interact_points["aux_power"]) + Vector3.UP * 0.2)
	await _frames(10)
	await _press("interact")
	_check("installing the cell restores aux power", kestrel.is_repaired("aux_power") and Game.stage == Game.Stage.INSTALLED and Game.carrying == "")
	_check("ship hum starts with aux power", main._ship_hum != null and main._ship_hum.playing)

	# --- Fabricator ---------------------------------------------------------------------------
	Game.add_scrap(30)
	player.revive(kestrel.to_global(kestrel.plan(16.2, 0.1, 10.9)))
	await _frames(10)
	await _press("interact")
	_check("fabricator builds the extended magazine", Game.has_upgrade("extended_mag") and player.weapon.mag_size() == 36, "scrap=%d" % Game.scrap)

	# --- Death and respawn --------------------------------------------------------------------
	player.take_damage(999.0)
	_check("player goes down", player.dead)
	await get_tree().create_timer(main.RESPAWN_DELAY + 0.5).timeout
	_check("respawns at Kestrel with full health", not player.dead and player.health == player.max_health() and player.global_position.distance_to(main.SPAWN) < 2.0)

	# --- Repair states ------------------------------------------------------------------------
	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, true)
	await get_tree().create_timer(3.5).timeout
	_check("landing gear levels the ship", kestrel.rotation.length() < 0.001 and is_equal_approx(kestrel.position.y, Kestrel.LEVEL_DECK_Y))
	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, false)
	await _frames(5)
	_check("all repairs reset to damaged", Kestrel.REPAIR_ORDER.all(func(id): return not kestrel.is_repaired(id)))
	finished = true


func _clear_scuttlers() -> void:
	for s in get_tree().get_nodes_in_group("scuttlers"):
		s.remove_from_group("scuttlers")
		s.queue_free()


func _place(pos: Vector3, yaw: float) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.face(yaw)


func _press(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(2)


func _walk(seconds: float) -> void:
	Input.action_press("move_forward")
	await get_tree().create_timer(seconds).timeout
	Input.action_release("move_forward")
	await _frames(10)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		failures += 1
