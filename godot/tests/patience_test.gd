extends "res://tests/test_base.gd"
## Milestone D1, repair 6 "The cold core": the engine's coil is sourced from the Long Patience's
## stern, past the Loom. The waypoints lead there; HOB finds it from the overlook; the stern keeps
## to its budget; the mirrors see far in a lamp's pool, close in the dark, nothing while shuttered
## or behind cover, and a spot wakes the guardian; the breaker kills the cage and the lamps; taking
## the coil springs the guardian, which hunts by vibration (a run, a shot, the coil's ring on the
## pulse, not a walk at range), charges, shrugs off shots and opens up under a cargo magnet; the
## hoist sends the coil home; the engine installs and test-fires; the thrusters reach a ledge a
## jump can't; a save made in the stern loads there.

var rm: RegionManager
var lp: LongPatience


func _name() -> String:
	return "PATIENCE TEST"


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
	await _route()
	if lp == null:
		finished = true
		return
	await _mirrors()
	await _power_and_coil()
	await _guardian()
	await _hoist()
	await _save_load()
	await _install_and_boost()
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
	return lp.to_global(local)


func _heal() -> void:
	player.health = player.max_health()


# --- Getting there -------------------------------------------------------------------------

func _route() -> void:
	_check("the engine is next and its coil comes from the Long Patience", Game.current_repair() == "engine" and Campaign.sourced("engine") and Campaign.SOURCED["engine"]["region"] == "long_patience")
	_check("the Kettle's waypoint leads to the canyon", main._waypoint() is Vector3 and main._waypoint().distance_to(rm.gates["shatterlands"].global_position) < 4.0)
	_check("the objective names the stern", Game.objective_text().contains("Long Patience"), Game.objective_text())
	Game.set_flag("shatterlands_open")
	rm.travel("shatterlands", true)
	await _wait_travel()
	await _frames(3)
	var cleft: Vector3 = RegionDB.get_region("loom_expanse")["gate_pos"]
	_check("in the Shatterlands the waypoint leads to the west cleft", rm.waypoint().distance_to(rm.scene.to_global(cleft)) < 3.0, str(rm.scene.to_local(rm.waypoint())))
	rm.travel("loom_expanse", true)
	await _wait_travel()
	var loom := rm.scene as LoomExpanse
	var gate: Vector3 = loom.to_global(RegionDB.get_region("long_patience")["gate_pos"])
	_place(gate + Vector3(-1.0, 0.5, 0.0), PI * 0.5)
	await _frames(4)
	_check("the east cleft is choked before HOB finds the stern", _label().contains("east rim") and not main._interaction.has("action"), _label())
	_check("the Loom keeps to its budget with the east cleft", _budget(loom))
	_place(loom.to_global(LoomExpanse.OVERLOOK + Vector3(0.0, 0.5, 2.0)), PI)
	await _frames(5)
	_check("from the overlook HOB finds the Long Patience", Game.flags.get("patience_open") == true)
	Game.set_flag("weave_grips")
	await _frames(3)
	_check("then the Loom's waypoint leads to the east cleft", rm.waypoint().distance_to(gate) < 3.0, str(loom.to_local(rm.waypoint())))
	_place(gate + Vector3(-1.0, 0.5, 0.0), PI * 0.5)
	await _frames(4)
	_check("the east cleft offers the Long Patience", _label().contains("Long Patience"), _label())
	await _press("interact")
	await _wait_travel()
	lp = rm.scene as LongPatience
	_check("through it is the Long Patience", rm.current == "long_patience" and lp != null)
	if lp == null:
		return
	_check("she stands on the ravine floor", player.is_on_floor() and absf(player.global_position.y - lp.global_position.y) < 0.6, str(player.global_position - lp.global_position))
	_check("the stern keeps to its budget", _budget(lp))
	_check("there the objective is the breaker", Game.objective_text().contains("breaker"), Game.objective_text())
	_check("and the waypoint leads to it", rm.waypoint().distance_to(_at(LongPatience.BREAKER)) < 3.0)
	var ok := await _walk_path([Vector3(0.0, 0.0, 40.0), Vector3(0.0, 0.0, 30.0), Vector3(-8.0, 0.0, 22.0)].map(func(p): return _at(p)), 12.0)
	_check("she can walk in through the breach", ok, str(lp.to_local(player.global_position)))
	var residents: Array[Enemy] = lp.spawn_residents(main)
	await _frames(3)
	_check("the guardian sleeps in its alcove", residents.size() == 1 and lp.guardian != null and lp.guardian.asleep())


# --- The mirrors ---------------------------------------------------------------------------

func _mirrors() -> void:
	lp.set_process(false)
	lp._t = 0.0
	lp.pulse_t = 3.0
	var lit_spot := _at(Vector3(-4.5, 0.0, 13.0))
	_place(lit_spot + Vector3.UP * 0.3, 0.0)
	await _frames(4)
	_check("that spot is in a lamp's pool", lp.lit(lp.to_local(player.global_position)))
	_check("a mirror sees far into a lamp's pool", lp.mirror_sees(0, player.global_position))
	lp.pulse_t = 0.5
	_check("but not while it's shuttered after a pulse", not lp.mirror_sees(0, player.global_position))
	lp.pulse_t = 3.0
	_check("nor out of its sweep", not lp.mirror_sees(1, player.global_position) and not lp.mirror_sees(2, player.global_position))
	var far_dark := _at(Vector3(-2.5, 0.0, 9.0))
	_check("in the dark it sees only close", not lp.lit(lp.to_local(far_dark)) and not lp.mirror_sees(0, far_dark) and lp.mirror_sees(0, _at(Vector3(-8.0, 0.0, 12.2))))
	_check("and not through cover", not lp.mirror_sees(0, _at(Vector3(4.5, 0.0, 12.0))))
	lp.set_process(true)
	var t := 0.0
	while t < 1.0 and lp.spotted == 0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_check("standing in its gaze, she's spotted", lp.spotted >= 1 and Game.flags.get("patience_spotted") == true)
	_check("and the spot wakes the guardian", not lp.guardian.asleep())
	# Put it back to sleep for the rest.
	lp.guardian.queue_free()
	await _frames(2)
	lp.adopt_guardian(main.spawn_enemy("guardian", _at(LongPatience.ALCOVE), "", lp) as PatienceGuardian)
	await _frames(3)


# --- The cage and the coil -----------------------------------------------------------------

func _power_and_coil() -> void:
	_place(_at(LongPatience.COIL_USE + Vector3(0.0, 0.3, 0.0)), 0.0)
	await _frames(4)
	_check("the coil waits on the breaker", _label().contains("breaker") and not main._interaction.has("action"), _label())
	_place(_at(LongPatience.BREAKER + Vector3(-1.2, 0.3, 0.0)), PI * 0.5)
	await _frames(4)
	_check("the breaker offers to cut the cage's power", _label().contains("Cut power"), _label())
	await _press("interact")
	await _frames(3)
	_check("the cage's power is off", lp.power_off() and lp._bar_bodies.all(func(s): return s.disabled))
	_check("and the lamps with it", lp._lamps.all(func(l): return l.light_energy == 0.0) and not lp.lit(Vector3(-4.5, 0.0, 13.0)))
	lp.set_process(false)
	lp._t = 0.0
	lp.pulse_t = 3.0
	_check("in the dark the mirror no longer sees across the hall", not lp.mirror_sees(0, _at(Vector3(-4.5, 0.0, 13.0))))
	lp.set_process(true)
	_check("the objective moves on to the coil", Game.objective_text().contains("Unbolt"), Game.objective_text())
	_place(_at(LongPatience.COIL_USE + Vector3(0.0, 0.3, 0.0)), 0.0)
	await _frames(4)
	_check("the coil can be unbolted", _label().contains("Unbolt"), _label())
	await _press("interact")
	await _frames(3)
	_check("she carries the coil", Game.carrying == "drive_coil" and lp.coil_out() and not lp._coil.visible)
	_check("and finds Voss's last log with it", Game.has_log(Story.log_at("engine", "component")))
	_check("taking it wakes the guardian", not lp.guardian.asleep() and lp.guardian.heard_at != Vector3.INF)


# --- The guardian --------------------------------------------------------------------------

func _guardian() -> void:
	var g := lp.guardian
	# Hearing.
	g.global_position = _at(Vector3(-8.0, 0.0, -20.0))
	g.state = PatienceGuardian.State.SEARCH
	g._timer = 99.0
	g.heard_at = Vector3.INF
	_place(_at(Vector3(8.0, 0.3, -2.0)), 0.0)
	await _frames(4)
	player.velocity = Vector3(3.0, 0.0, 0.0)
	_check("a walk across the hall isn't felt", g._felt() == Vector3.INF)
	player.velocity = Vector3(6.5, 0.0, 0.0)
	_check("a run is", g._felt() != Vector3.INF)
	player.velocity = Vector3.ZERO
	g.heard_at = Vector3.INF
	lp._pulse()
	_check("the coil's ring on a pulse gives her away", g.heard_at.distance_to(player.global_position) < 0.5)
	g.heard_at = Vector3.INF
	g.shot_fired(player.global_position)
	_check("so does a shot", g.heard_at != Vector3.INF)
	# It charges.
	_heal()
	g.global_position = _at(Vector3(8.0, 0.0, -7.5))
	g.state = PatienceGuardian.State.HUNT
	g.heard_at = player.global_position
	var hp := player.health
	var t := 0.0
	while t < 4.0 and g.hits == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("close and sure, it braces and charges her down", g.hits >= 1 and player.health < hp, "hits %d, %.0f -> %.0f, state %s" % [g.hits, hp, player.health, g.anim_state()])
	_heal()
	# Plate and magnets.
	var before := g.health
	g.take_damage(100.0, g.global_position + Vector3.UP, Vector3.FORWARD)
	_check("its plate turns most of a shot", before - g.health < 20.0, "%.0f" % (before - g.health))
	g.global_position = _at(LongPatience.MAGNETS[0] + Vector3(0.8, 0.0, 0.5))
	g.state = PatienceGuardian.State.HUNT
	_place(_at(Vector3(8.0, 0.3, 4.0)), 0.0)
	await _frames(2)
	var housing: Node = null
	for c in lp.get_children():
		if c is StaticBody3D and c.has_meta("on_hit"):
			housing = c
			break
	_check("the cargo magnets can be shot", housing != null)
	(housing.get_meta("on_hit") as Callable).call()
	_check("a magnet fired over it pins it", g.pinned() and g.pins == 1 and Game.flags.get("patience_magnet_used") == true)
	before = g.health
	g.take_damage(100.0, g.global_position + Vector3.UP, Vector3.FORWARD)
	_check("and with its back torn open, shots tell", before - g.health > 90.0, "%.0f" % (before - g.health))
	_check("the vent is a weak spot while it's pinned", g.weak_spot() != Vector3.INF)
	_check("a spent magnet needs a moment", not lp.fire_magnet(0))
	await get_tree().create_timer(PatienceGuardian.PINNED_TIME + 0.3).timeout
	_check("and then it's loose again", not g.pinned())
	g.global_position = _at(LongPatience.ALCOVE)
	g.state = PatienceGuardian.State.SEARCH
	g._timer = 99.0
	_heal()


# --- The hoist -----------------------------------------------------------------------------

func _hoist() -> void:
	_check("the objective is the hoist", Game.objective_text().contains("hoist"), Game.objective_text())
	_check("and the waypoint", rm.waypoint().distance_to(_at(LongPatience.HOIST)) < 3.0)
	_place(_at(LongPatience.HOIST + Vector3(0.0, 0.5, 2.0)), 0.0)
	await _frames(4)
	_check("the hoist takes the coil", _label().contains("Load the coil"), _label())
	await _press("interact")
	await _frames(3)
	_check("it's loaded and rising", Game.carrying == "" and lp.hoisting() and Game.objective_text().contains("Hold out"), Game.objective_text())
	lp.hoist_t = LongPatience.HOIST_TIME - 0.5
	await get_tree().create_timer(1.0).timeout
	_check("at the top it's away home", Game.flags.get("patience_coil") == true and Game.delivered("drive_coil") and not lp.hoisting())
	_check("and the objective says it's waiting at Kestrel", Game.objective_text() == Campaign.get_repair("engine")["return"], Game.objective_text())
	_check("the waypoint leads back out", rm.waypoint().distance_to(lp.exit_global()) < 3.0)
	# The bridge's distress call.
	_place(_at(LongPatience.DISTRESS + Vector3(-1.2, 0.3, 0.0)), PI * 0.5)
	await _frames(4)
	_check("a distress call in the bridge cabin", _label().contains("distress"), _label())
	var scrap := Game.scrap
	await _press("interact")
	_check("it's a recording, with scrap", Game.has_log("patience_distress") and Game.scrap == scrap + 25)


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
	lp = rm.scene as LongPatience
	_check("a save made in the stern loads there", rm.current == "long_patience" and lp != null)
	if lp:
		_check("with its power still cut and the coil gone", lp.power_off() and not lp._coil.visible and lp._lamps.all(func(l): return l.light_energy == 0.0))
		_check("and the coil still waiting at Kestrel", Game.delivered("drive_coil"))


# --- Home --------------------------------------------------------------------------------

func _install_and_boost() -> void:
	rm.travel("kettle", true)
	await _wait_travel()
	var ledge: Vector3 = main.boost_ledges.ledge_at("kettle")
	_check("a thrust ledge stands in the Kettle", ledge != Vector3.INF and main.find_child("BoostLedge", true, false) != null)
	var top: float = ledge.y + BoostLedges.HEIGHT
	await _try_ledge(ledge)
	_check("before the engine a jump can't reach it", player.global_position.y < top - 0.5 and player.boosts == 0, "%.2f vs %.2f" % [player.global_position.y, top])
	player.revive(main.install_point("engine") + Vector3.UP * 0.3)
	await _frames(10)
	_check("the engine bay takes the coil", _label().contains(Campaign.get_repair("engine")["install_label"]), _label())
	await _press("interact")
	await _frames(5)
	_check("the engine's in", Game.is_repaired("engine") and kestrel.is_repaired("engine"))
	await _frames(30)
	_check("and it test-fires", kestrel.engine_power > 0.05, "%.2f" % kestrel.engine_power)
	await _try_ledge(ledge)
	_check("with the thrusters she boosts onto the ledge", player.boosts >= 1 and player.global_position.y > top - 0.3, "%.2f vs %.2f, %d boosts" % [player.global_position.y, top, player.boosts])
	await _frames(5)
	_check("the cache on top opens", _label().contains("thrust cache"), _label())
	var scrap := Game.scrap
	await _press("interact")
	_check("and pays out", Game.scrap == scrap + BoostLedges.SCRAP and main.boost_ledges.opened("kettle"))


## From just south of the ledge: run at it, jump, and press jump again near the top of the arc.
func _try_ledge(ledge: Vector3) -> void:
	var start := ledge + Vector3(0.0, 0.0, 3.4)
	start.y = main.site.height_at(start.x, start.z) + 0.3
	player.revive(start, false)
	player.face(0.0)
	await _frames(20)
	Input.action_press("move_forward")
	await _frames(2)
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	await get_tree().create_timer(0.3).timeout
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	await get_tree().create_timer(0.7).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(0.6).timeout


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
