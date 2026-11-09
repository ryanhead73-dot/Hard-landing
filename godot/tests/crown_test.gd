extends "res://tests/test_base.gd"
## Milestone D2, repair 7 "Between the beats": the nav core is sourced from the Tuning Crown, down
## the drop past the Loom's overlook that only opens with the engine. The Crown keeps to its
## budget; a resonator retuned into step with the Crown's beat locks after two beats, and each
## lock closes the old span into its bay and opens a shortcut and the terrace gate, never
## stranding her; with three locked the door opens; in the arena the Cantor sings its phrase and
## plucks a wave on the low note, turns shots while its petals are shut, opens when an anchor is
## struck in the quiet after the low note (and not at any other time), changes phase at each third
## of its health (shear walls, then petals that open one per gap and a chord singer), and puts the
## phase back to its start when Juno goes down; it falls, the core goes home, and a save in the
## arena loads at its door.

var rm: RegionManager
var tc: TuningCrown


func _name() -> String:
	return "CROWN TEST"


func _run() -> void:
	await _frames(10)
	Game.reset()
	for r in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(r, false)
	rm = main.regions
	for r in ["aux_power", "cooling", "canopy", "landing_gear", "wing"]:
		Game.set_repaired(r, true)
		kestrel.set_repaired(r, true)
	await _frames(3)
	await _gate()
	if tc == null:
		finished = true
		return
	await _resonators()
	await _cantor()
	await _save_load()
	Game.delete_save()
	finished = true


func _wait_travel() -> void:
	await _frames(2)
	var t := 0.0
	while rm.travelling and t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _frames(10)


func _at(local: Vector3) -> Vector3:
	return tc.to_global(local)


func _gate() -> void:
	Game.set_flag("shatterlands_open")
	Game.set_flag("loom_crown_seen")
	Game.set_flag("weave_grips")
	rm.travel("shatterlands", true)
	await _wait_travel()
	rm.travel("loom_expanse", true)
	await _wait_travel()
	var loom := rm.scene as LoomExpanse
	var gate: Vector3 = loom.to_global(RegionDB.get_region("tuning_crown")["gate_pos"])
	_place(gate + Vector3(0.0, 0.5, 1.0), 0.0)
	await _frames(4)
	_check("before the engine the drop is too far", _label().contains("without thrusters") and not main._interaction.has("action"), _label())
	Game.set_repaired("engine", true)
	kestrel.set_repaired("engine", true)
	Game.set_flag("crown_open")
	await _frames(3)
	_check("navigation is next and its core comes from the Crown", Game.current_repair() == "navigation" and Campaign.SOURCED["navigation"]["region"] == "tuning_crown")
	_check("the Loom's waypoint leads to the drop", rm.waypoint().distance_to(gate) < 3.0, str(loom.to_local(rm.waypoint())))
	await _frames(2)
	_check("with the thrusters it offers the Crown", _label().contains("Tuning Crown"), _label())
	await _press("interact")
	await _wait_travel()
	tc = rm.scene as TuningCrown
	_check("down there is the Tuning Crown", rm.current == "tuning_crown" and tc != null)
	if tc == null:
		return
	_check("she stands on its floor", player.is_on_floor() and absf(player.global_position.y - tc.global_position.y) < 0.6)
	_check("the Crown keeps to its budget", _budget(tc))
	_check("the objective is the resonators", Game.objective_text().contains("resonators"), Game.objective_text())
	_check("and the waypoint leads to the west stone", rm.waypoint().distance_to(_at(TuningCrown.RESONATORS[0])) < 3.0)


func _resonators() -> void:
	_check("at first the old spans are open and the shortcuts, terrace gate and door shut",
		tc.curtain_open("old_w") and tc.curtain_open("old_e") and not tc.curtain_open("short_w") and not tc.curtain_open("terrace") and not tc.curtain_open("door"))
	# Walk to the west stone through the old span, across the ridge's stone.
	var ok := await _walk_path([Vector3(0.0, 0.0, 60.0), Vector3(-10.0, 0.0, 55.0), Vector3(-24.0, 0.0, 55.0), Vector3(-38.0, 0.0, 44.0), Vector3(-40.0, 0.0, 32.6)].map(func(p): return _at(p)), 14.0)
	_check("she can walk into the west bay to its stone", ok, str(tc.to_local(player.global_position)))
	await _frames(3)
	_check("the stone can be retuned", _label().contains("Retune"), _label())
	var r0: int = tc.rate[0]
	await _press("interact")
	_check("retuning steps its rate", tc.rate[0] == (r0 + 1) % TuningCrown.RATES.size())
	while not tc.in_tune(0):
		tc.retune(0)
	await _frames(2)
	_check("out of tune it never locks", not tc.calibrated(0))
	var t := 0.0
	while t < TuningCrown.BEAT * (TuningCrown.IN_STEP + 1) + 0.5 and not tc.calibrated(0):
		await get_tree().process_frame
		t += get_process_delta_time()
	_check("in step with the Crown it locks after two beats", tc.calibrated(0), "%.1f s" % t)
	await _frames(2)
	_check("the old span behind her closes, the shortcut and terrace gate open", not tc.curtain_open("old_w") and tc.curtain_open("short_w") and tc.curtain_open("terrace"))
	# Not stranded: out through the shortcut to the terrace and the lane.
	ok = await _walk_path([Vector3(-30.0, 0.0, 14.0), Vector3(-22.0, 0.0, 5.0), Vector3(-8.0, 0.0, 8.0), Vector3(0.0, 0.0, 18.0), Vector3(0.0, 0.0, 30.0)].map(func(p): return _at(p)), 14.0)
	_check("the shortcut and terrace gate lead her back to the lane", ok, str(tc.to_local(player.global_position)))
	# A stone tuned wrong for two beats stays out.
	tc.rate[1] = 0
	tc.in_step[1] = 0
	await get_tree().create_timer(TuningCrown.BEAT * 2.5).timeout
	_check("a stone off the beat doesn't lock", not tc.calibrated(1))
	_check("the door holds until all three", not tc.curtain_open("door"))
	for i in [1, 2]:
		while not tc.in_tune(i):
			tc.retune(i)
	t = 0.0
	while t < TuningCrown.BEAT * 4.0 and tc.calibrated_count() < 3:
		await get_tree().process_frame
		t += get_process_delta_time()
	_check("with all three in step the door opens", tc.calibrated_count() == 3 and tc.curtain_open("door"))
	_check("and the waypoint leads into the Crown", rm.waypoint().distance_to(_at(TuningCrown.ARENA_IN)) < 3.0)


func _cantor() -> void:
	ok_walk()
	var ok := await _walk_path([Vector3(0.0, 0.0, 6.0), Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -18.0)].map(func(p): return _at(p)), 14.0)
	_check("she walks through the door into the arena", ok, str(tc.to_local(player.global_position)))
	await _frames(5)
	var c := tc.cantor
	_check("the Cantor comes down", Game.flags.get("crown_arena") == true and c != null and is_instance_valid(c) and c.phase == Cantor.Phase.LISTEN)
	if c == null:
		return
	_check("the arena is her checkpoint now", tc.entry_global().distance_to(_at(TuningCrown.ARENA_IN)) < 0.5)
	# It sings and plucks.
	var waves := c.waves
	await get_tree().create_timer(Cantor.CYCLE + 0.3).timeout
	_check("it sings its phrase and plucks a wave on the low note", c.waves > waves)
	# Shut, it turns shots.
	var hp := c.health
	c.cycle_t = 0.2
	c.take_damage(100.0, c.global_position + Vector3.UP * Cantor.HEART_Y, Vector3.FORWARD)
	_check("with its petals shut, shots do nothing", c.health == hp and not c.heart_open())
	# An anchor struck out of the gap only rings.
	c.cycle_t = 0.4
	tc.strike_anchor(0)
	_check("an anchor struck mid-phrase only rings", not c.heart_open() and c.interrupts == 0)
	c.cycle_t = Cantor.GAP_FROM + 0.2
	var housing: Node = null
	for ch in tc.get_children():
		if ch is StaticBody3D and ch.has_meta("on_hit"):
			housing = ch
			break
	(housing.get_meta("on_hit") as Callable).call()
	_check("struck in the quiet after the low note, the phrase breaks and the heart opens", c.heart_open() and c.interrupts == 1)
	c.take_damage(c.health - c.phase_health(1) + 1.0, c.global_position, Vector3.FORWARD)
	_check("a third of its health and it moves to its second phase", c.phase == Cantor.Phase.RESPOND and not c.heart_open() and Game.flags.get("cantor_phase") == Cantor.Phase.RESPOND)
	# Shear walls slide on the middle note.
	var x0: float = tc._shears[0].position.x
	c.cycle_t = Cantor.NOTES[1] - 0.3
	c._sung = [true, false, false]
	await get_tree().create_timer(2.0).timeout
	_check("in the second phase the shear walls slide across", absf(tc._shears[0].position.x - x0) > TuningCrown.SHEAR_SPAN, "%.1f -> %.1f" % [x0, tc._shears[0].position.x])
	# Going down puts the phase back to its start.
	c.cycle_t = Cantor.GAP_FROM + 0.1
	tc.strike_anchor(1)
	c.take_damage(50.0, c.global_position, Vector3.FORWARD)
	player.take_damage(9999.0)
	await get_tree().create_timer(main.RESPAWN_DELAY + 0.5).timeout
	_check("going down she's back at the arena's door", not player.dead and player.global_position.distance_to(_at(TuningCrown.ARENA_IN)) < 2.0, str(tc.to_local(player.global_position)))
	_check("and the fight is back at the start of the phase", c.phase == Cantor.Phase.RESPOND and is_equal_approx(c.health, c.phase_health(1)), "phase %d, %.0f vs %.0f" % [c.phase, c.health, c.phase_health(1)])
	# To the third phase.
	c.cycle_t = Cantor.GAP_FROM + 0.1
	tc.strike_anchor(2)
	c.take_damage(c.health - c.phase_health(2) + 1.0, c.global_position, Vector3.FORWARD)
	await _frames(3)
	_check("at two thirds down it resolves, and a chord singer joins", c.phase == Cantor.Phase.RESOLVE and get_tree().get_nodes_in_group("chord_singers").size() >= 1, "phase %d, %.0f, open %s, singers %d" % [c.phase, c.health, c.heart_open(), get_tree().get_nodes_in_group("chord_singers").size()])
	c.cycle_t = Cantor.GAP_FROM + 0.1
	tc.strike_anchor(3)
	_check("in the last phase anchors don't open it", not c.heart_open())
	for e in get_tree().get_nodes_in_group("chord_singers"):
		e.queue_free()
	# One petal per gap; then the heart is bare in the gaps.
	c.cycle_t = Cantor.CYCLE - 0.05
	var t := 0.0
	while t < Cantor.CYCLE * 3.2 and c.petals < 3:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("its petals open one quiet gap at a time", c.petals == 3, "%d petals in %.1f s" % [c.petals, t])
	c.cycle_t = 0.3
	await get_tree().physics_frame
	_check("even then, mid-phrase the heart is shut", not c.heart_open())
	c.cycle_t = Cantor.GAP_FROM + 0.1
	await get_tree().physics_frame
	_check("and in the quiet it's bare", c.heart_open())
	c.take_damage(c.health + 10.0, c.global_position + Vector3.UP * Cantor.HEART_Y, Vector3.FORWARD)
	await _frames(5)
	_check("the Cantor falls", Game.flags.get("cantor_down") == true)
	_heal()
	_place(_at(TuningCrown.ARENA + Vector3(0.0, 0.3, 2.0)), 0.0)
	await _frames(5)
	_check("Marrow's core can be taken from the heart", _label().contains("nav core"), _label())
	await _press("interact")
	_check("it goes home with her", Game.delivered("nav_core") and Game.flags.get("crown_core") == true and Game.has_log(Story.log_at("navigation", "component")))
	_check("and the objective is to install it", Game.objective_text() == Campaign.get_repair("navigation")["return"], Game.objective_text())


func ok_walk() -> void:
	_heal()


func _heal() -> void:
	player.health = player.max_health()


func _save_load() -> void:
	main.save_game()
	var data := Game.read_save()
	main.queue_free()
	await _frames(3)
	Game.reset()
	Game.pending_load = data
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	main.missions.bypass = true
	kestrel = main.kestrel
	player = main.player
	rm = main.regions
	await _frames(20)
	await _wait_travel()
	tc = rm.scene as TuningCrown
	_check("a save made in the arena loads at its door", rm.current == "tuning_crown" and tc != null and player.global_position.distance_to(tc.to_global(TuningCrown.ARENA_IN)) < 2.0)
	_check("with the stones still in tune and the core still waiting at Kestrel", tc != null and tc.calibrated_count() == 3 and Game.delivered("nav_core"))


func _budget(region: Node) -> bool:
	var meshes := 0
	var lights := 0
	var shadowed := 0
	var stack: Array = [region]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			meshes += 1
		if n is Light3D:
			lights += 1
			if (n as Light3D).shadow_enabled:
				shadowed += 1
	print("  region budget: %d meshes, %d lights" % [meshes, lights])
	return meshes <= 120 and lights <= 8 and shadowed == 0
