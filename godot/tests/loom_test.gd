extends "res://tests/test_base.gd"
## Milestone C, the first pocket of the Loom Expanse: the west cleft in the Shatterlands stays laced
## shut until the wing is in; the pocket keeps to its budget and its loop can be walked; the live
## ridges throw Juno on the weave but not on a stone span; ridge divers stay off stone, hear a run
## and surface with their gills open; pinweaver threads snag a walk but let a crouch slide, and two
## knots shot force a recovery; the chord singer's dissonance drags a reload in the open but not
## behind a boulder, and a membrane shot stops it; the shortcut, locker, marker and bypass; a save
## made there loads there.

var rm: RegionManager
var loom: LoomExpanse


func _name() -> String:
	return "LOOM TEST"


func _run() -> void:
	await _frames(10)
	Game.reset()
	for r in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(r, false)
	rm = main.regions
	await _gate()
	if loom == null:
		finished = true
		return
	await _pocket()
	await _ridges()
	await _diver()
	await _pinweaver()
	await _singer()
	await _places()
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
	return loom.to_global(local)


func _spawn(kind: String, local: Vector3) -> Enemy:
	var e: Enemy = main.spawn_enemy(kind, _at(local), "", loom)
	return e


func _clear_loom() -> void:
	for g in ["ridge_divers", "pinweavers", "chord_singers"]:
		for e in get_tree().get_nodes_in_group(g):
			e.queue_free()
	await _frames(3)


func _heal() -> void:
	player.health = player.max_health()


# --- The way in ----------------------------------------------------------------------------

func _gate() -> void:
	Game.set_flag("shatterlands_open")
	rm.travel("shatterlands", true)
	await _wait_travel()
	var r := RegionDB.get_region("loom_expanse")
	var gate_at: Vector3 = rm.scene.to_global(r["gate_pos"])
	var inward: Vector3 = r["gate_in"]
	_place(gate_at + inward * 1.0 + Vector3(0.0, 0.5, 0.0), atan2(inward.x, inward.z))
	await _frames(4)
	_check("the west cleft is laced shut before the wing", _label().contains("laced shut") and not main._interaction.has("action"), _label())
	var sh := rm.scene as ShatterlandsThreshold
	_check("the lacing stops her", sh._cleft_fibres.get_child(0).collision_layer == Game.LAYER_WORLD)
	_check("the Shatterlands still keeps to its budget with the cleft", _region_budget(sh))
	Game.set_repaired("wing", true)
	await _frames(3)
	_check("fitting the wing opens the Loom", Game.flags.get("loom_open", false) == true)
	_check("and the lacing lets go", sh._cleft_fibres.get_child(0).collision_layer == 0)
	_check("the Loom's quest starts", main.quests.state_of("the_loom") == QuestLog.ACTIVE)
	# Walked in from the pocket floor: nothing in the cleft may block the way.
	_place(gate_at + inward * 10.0 + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	var t := 0.0
	Input.action_press("move_forward")
	while t < 6.0 and _flat_distance(player.global_position, gate_at) > 1.5:
		var d: Vector3 = gate_at - player.global_position
		player.face(atan2(-d.x, -d.z))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release("move_forward")
	await _frames(3)
	_check("Juno walks up to the cleft and it offers the Loom", _label().contains("Loom Expanse"), "%s at %s" % [_label(), player.global_position - gate_at])
	await _press("interact")
	await _wait_travel()
	loom = rm.scene as LoomExpanse
	_check("through it is the Loom Expanse", rm.current == "loom_expanse" and loom != null and Game.region == "loom_expanse")
	if loom == null:
		return
	_check("arriving counts", Game.flags.get("reached_loom") == true and main.quests.step_of("the_loom") == 1)
	_check("she stands on the Loom's ground", player.is_on_floor() and absf(player.global_position.y - loom.global_position.y) < 0.6, str(player.global_position - loom.global_position))
	_check("the Loom has its own look", absf(main._env.fog_density - loom.look["fog_density"]) < 0.0001)
	_check("the Loom keeps to its budget", _region_budget(loom))
	_check("the waypoint leads to the overlook", rm.waypoint().distance_to(_at(LoomExpanse.OVERLOOK)) < 3.0)


# --- The pocket ----------------------------------------------------------------------------

func _pocket() -> void:
	var residents: Array[Enemy] = loom.spawn_residents(main)
	await _frames(3)
	_check("the Loom has its own wildlife", residents.size() == 5 and residents.all(func(e): return is_instance_valid(e) and e.get_parent() == loom))
	var divers := residents.filter(func(e): return e is RidgeDiver)
	_check("its divers start under the weave", divers.size() == 2 and divers.all(func(d): return loom.on_weave(d.global_position) and (d as RidgeDiver).underground()))
	_check("its pinweavers start in the Spindles", residents.filter(func(e): return e is Pinweaver).all(func(p): return loom.to_local(p.global_position).x > 15.0))
	await _clear_loom()
	# The east lane and the bowl: entry, past the massif, between the spindles, round the
	# boulders to the overlook.
	_place(loom.entry_global(), 0.0)
	await _frames(5)
	var route := [Vector3(10.0, 0.0, 44.0), Vector3(23.0, 0.0, 30.0), Vector3(23.0, 0.0, -34.0), Vector3(12.0, 0.0, -48.0), Vector3(3.0, 0.0, -66.0), Vector3(0.0, 0.0, -71.0)]
	var ok := await _walk_path(route.map(func(p): return _at(p)), 25.0)
	_check("Juno can walk the east lane and the bowl to the overlook", ok, str(loom.to_local(player.global_position)))
	await _frames(5)
	_check("from the overlook she sees the Crown", Game.flags.get("loom_crown_seen") == true and main.quests.step_of("the_loom") == 2)
	_check("then the waypoint leads to the survey locker", rm.waypoint().distance_to(_at(LoomExpanse.LOCKER)) < 3.0)
	# Back down the west side: round the bowl to the Weave's north end, then down the weave
	# between the ridges.
	var west := [Vector3(-14.0, 0.0, -50.0), Vector3(-30.0, 0.0, -36.0), Vector3(-30.0, 0.0, -20.0)]
	ok = await _walk_path(west.map(func(p): return _at(p)), 25.0)
	_check("and back down to the Weave", ok, str(loom.to_local(player.global_position)))


# --- Live ridges ---------------------------------------------------------------------------

## Waits for `ridge`'s next swell to pass the point `along` metres down it.
func _wait_swell_past(ridge: LoomRidge, along: float) -> void:
	var t := 0.0
	var started := ridge.swells
	while t < ridge.period + 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if ridge.swells > started and (ridge.front < 0.0 or ridge.front > along + 2.0):
			break
	await _frames(3)


func _ridges() -> void:
	var ridge: LoomRidge = loom.ridges[0]
	_check("two live ridges cross the Weave", loom.ridges.size() == 2)
	# On the weave, mid-ridge.
	var along := ridge.length() * 0.6
	var spot: Vector3 = ridge.from.lerp(ridge.to, 0.6)
	_heal()
	var hp: float = player.health
	_place(_at(spot) + Vector3(0.0, 0.3, 0.0), 0.0)
	var thrown := false
	var throws := ridge.throws
	var t := 0.0
	var told := false
	var started := ridge.swells
	while t < ridge.period + 4.0:
		# Keep her on the spot until it comes.
		if ridge.throws == throws:
			player.global_position = Vector3(_at(spot).x, player.global_position.y, _at(spot).z)
			player.velocity.x = 0.0
			player.velocity.z = 0.0
		if ridge._told and ridge.swells == started:
			told = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if ridge.throws > throws:
			thrown = true
			await _frames(4)
			break
	_check("the swell is told before it runs (thrum and seam)", told)
	_check("caught on the weave, the swell throws her", thrown and player.health < hp, "throws %d, health %.0f -> %.0f" % [ridge.throws - throws, hp, player.health])
	await _frames(40)
	# On the stone span, where the ridge dives under a slab.
	var safe_f: float = (ridge.safe[0][0] + ridge.safe[0][1]) * 0.5
	var stone: Vector3 = ridge.from.lerp(ridge.to, safe_f)
	_heal()
	_place(_at(stone) + Vector3(0.0, 0.3, 0.0), 0.0)
	throws = ridge.throws
	await _wait_swell_past(ridge, ridge.length() * safe_f)
	_check("on the stone span the swell passes under her", ridge.throws == throws and player.health >= player.max_health() - 0.1)
	_check("the stone span sits on a slab", not loom.on_weave(_at(stone)))
	_place(_at(Vector3(-30.0, 0.0, 40.0)), 0.0)
	await _frames(3)


# --- Ridge divers --------------------------------------------------------------------------

func _diver() -> void:
	# It never crawls onto stone: driven at a point across a slab, it stops at the edge.
	var d := _spawn("ridge_diver", Vector3(-38.0, 0.0, 5.0)) as RidgeDiver
	_place(_at(Vector3(0.0, 0.0, -70.0)), 0.0)
	await _frames(3)
	d.state = RidgeDiver.State.TRACK
	d.heard_at = _at(Vector3(-28.0, 0.0, 5.0))
	var on_stone := false
	for i in 150:
		await get_tree().physics_frame
		if not loom.on_weave(d.global_position):
			on_stone = true
	_check("a ridge diver can't cross stone", not on_stone and loom.to_local(d.global_position).x < -34.0, str(loom.to_local(d.global_position)))
	d.queue_free()
	await _frames(2)
	# Walking near it is quiet; running is loud.
	d = _spawn("ridge_diver", Vector3(-36.0, 0.0, 9.0)) as RidgeDiver
	_place(_at(Vector3(-20.0, 0.0, 3.0)), PI * 0.5)
	await _frames(3)
	var route := [_at(Vector3(-20.0, 0.0, -1.0)), _at(Vector3(-20.0, 0.0, 7.0)), _at(Vector3(-20.0, 0.0, -1.0))]
	await _walk_path(route, 6.0)
	_check("walking on the weave doesn't wake it", d.state == RidgeDiver.State.PROWL and not d.hunting, RidgeDiver.State.find_key(d.state))
	_check("underground it can't be hurt", not d.take_damage(50.0, d.global_position, Vector3.FORWARD) and d.health == d.max_health)
	Input.action_press("sprint")
	var heard := false
	for leg in 6:
		var target := _at(Vector3(-20.0, 0.0, -1.0 if leg % 2 == 0 else 7.0))
		Input.action_press("move_forward")
		for i in 60:
			var to := target - player.global_position
			if Vector2(to.x, to.z).length() < 0.6:
				break
			player.face(atan2(-to.x, -to.z))
			await get_tree().physics_frame
			if d.state != RidgeDiver.State.PROWL:
				heard = true
		Input.action_release("move_forward")
		if heard:
			break
	Input.action_release("sprint")
	_check("a run on the weave draws it", heard, RidgeDiver.State.find_key(d.state))
	# Stand still where it marks: it erupts under her.
	_heal()
	var hp: float = player.health
	var mark_t := 0.0
	while d.state != RidgeDiver.State.MARK and mark_t < 8.0:
		await get_tree().physics_frame
		mark_t += get_physics_process_delta_time()
		player.velocity = Vector3(0.0, player.velocity.y, 0.0)
		# Keep her loud for it, as if she were still running on the spot.
		if d.state == RidgeDiver.State.PROWL or d.state == RidgeDiver.State.TRACK:
			d.heard_at = player.global_position
			d.state = RidgeDiver.State.TRACK
	_check("it comes under her and marks the spot", d.state == RidgeDiver.State.MARK and d._ring.visible)
	var t := 0.0
	while d.state == RidgeDiver.State.MARK and t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("standing on the mark, the eruption hits", d.hits == 1 and player.health < hp, "hits %d, health %.0f -> %.0f" % [d.hits, hp, player.health])
	_check("out of the ground its gills are open", d.state == RidgeDiver.State.SURFACED and d.weak_spot() != Vector3.INF and d.collision_layer == Game.LAYER_ENEMY)
	var crit_before := d.crits_taken
	d.take_damage(10.0, d.weak_spot(), Vector3.FORWARD)
	_check("and a shot to the gills is a crit", d.crits_taken == crit_before + 1)
	# A dodged eruption: rolled clear, it overreaches.
	t = 0.0
	while d.state != RidgeDiver.State.PROWL and t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("then it dives again and leaves a pocket", d.underground() and d._pocket.visible)
	await _frames(5)
	_check("the loose pocket drags at her feet", player.snag_t > 0.0 or _flat_distance(player.global_position, d._pocket_at) > RidgeDiver.POCKET_RADIUS)
	_place(_at(Vector3(-20.0, 0.0, 2.0)), 0.0)
	await _frames(2)
	d._start_mark(_at(Vector3(-20.0, 0.0, 2.0)))
	_place(_at(Vector3(-20.0, 0.0, 5.2)), 0.0)
	t = 0.0
	while d.state == RidgeDiver.State.MARK and t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("stepping clear of the mark makes it overreach", d.dodged == 1 and d.hits == 1 and d._open_for > RidgeDiver.INHALE_TIME)
	# The survey team's grips: a run carries half as far.
	d.queue_free()
	await _frames(2)
	_heal()


# --- Pinweavers ----------------------------------------------------------------------------

## Waits for a live thread from `pw` (or `secs` to run out).
func _wait_thread(pw: Pinweaver, secs := 20.0) -> Pinweaver.TripThread:
	var t := 0.0
	while t < secs:
		for th in pw.threads:
			if is_instance_valid(th) and th.live:
				return th
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return null


func _pinweaver() -> void:
	_place(_at(Vector3(23.0, 0.0, 2.0)), 0.0)
	var pw := _spawn("pinweaver", Vector3(28.0, 0.0, 10.0)) as Pinweaver
	await _frames(3)
	pw.alert(false)
	var anchored := false
	var t := 0.0
	while t < 12.0 and pw.state != Pinweaver.State.ANCHOR:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		player.global_position = _at(Vector3(23.0, 0.0, 2.0))
	anchored = pw.state == Pinweaver.State.ANCHOR
	_check("a pinweaver steps to a pillar and anchors", anchored, Pinweaver.State.find_key(pw.state))
	_check("anchored, its valve is open to a shot", pw.weak_spot() != Vector3.INF)
	var th := await _wait_thread(pw)
	_check("then it spools a live trip-thread between two pillars", th != null)
	if th == null:
		return
	var anchors := loom.anchors()
	var on_pillars: bool = anchors.any(func(a): return a.distance_to(th.a) < 0.1) and anchors.any(func(a): return a.distance_to(th.b) < 0.1)
	_check("strung pillar to pillar at shin height", on_pillars and absf(th.a.y - loom.global_position.y - 0.45) < 0.05)
	_check("the thread is only for shots: nothing walks into it", th._body.collision_layer == Game.LAYER_SHOT and (player.collision_mask & Game.LAYER_SHOT) == 0)
	# Walk through it: snagged.
	var mid: Vector3 = (th.a + th.b) * 0.5
	var side: Vector3 = (th.b - th.a).cross(Vector3.UP).normalized()
	_place(Vector3(mid.x, loom.global_position.y + 0.1, mid.z) + side * 2.0, atan2(side.x, side.z))
	await _frames(3)
	Input.action_press("move_forward")
	var snags := pw.snags
	t = 0.0
	while t < 3.0 and pw.snags == snags:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("walking through a live thread snags her", pw.snags == snags + 1 and player.snag_t > 0.0)
	Input.action_press("sprint")
	await _frames(6)
	_check("snagged, she can't sprint", not player.is_sprinting() and Vector2(player.velocity.x, player.velocity.z).length() <= player.walk_speed * 0.45)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await get_tree().create_timer(Pinweaver.SNAG_TIME + 0.3).timeout
	_check("the snag wears off", player.snag_t == 0.0)
	# Crouch through the next one: it slides off.
	th = await _wait_thread(pw)
	_check("it strings another", th != null)
	if th:
		mid = (th.a + th.b) * 0.5
		side = (th.b - th.a).cross(Vector3.UP).normalized()
		_place(Vector3(mid.x, loom.global_position.y + 0.1, mid.z) + side * 1.5, atan2(side.x, side.z))
		Input.action_press("crouch")
		await _frames(10)
		Input.action_press("move_forward")
		var fails := pw.fails
		snags = pw.snags
		t = 0.0
		while t < 3.0 and pw.fails == fails and pw.snags == snags:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		Input.action_release("move_forward")
		Input.action_release("crouch")
		await _frames(10)
		_check("crouching through, it slides off and the trap fails", pw.fails > fails and pw.snags == snags and player.snag_t == 0.0, "fails %d->%d snags %d->%d" % [fails, pw.fails, snags, pw.snags])
	# Shoot through a line: it snaps back and the weaver goes somewhere new.
	th = await _wait_thread(pw)
	if th:
		var fails := pw.fails
		th._on_line_hit()
		await _frames(3)
		_check("a shot line snaps and the weaver moves on", not is_instance_valid(th) or not th in pw.threads and pw.fails == fails + 1)
	# Both knots of a line, one after the other: it has to unspool and recover, standing open.
	th = await _wait_thread(pw)
	_check("a third line", th != null)
	if th:
		th._on_knot_hit(th._knots[0], 0)
		await get_tree().create_timer(0.6).timeout
		th._on_knot_hit(th._knots[1], 1)
		await _frames(3)
		_check("two knots shot force a recovery", pw.recoveries == 1 and pw.state == Pinweaver.State.RECOVER and pw.weak_spot() != Vector3.INF)
	# The survey team's grips: lines slide off without a crouch.
	Game.set_flag("weave_grips", true)
	th = await _wait_thread(pw)
	if th:
		mid = (th.a + th.b) * 0.5
		var snags_before := pw.snags
		_place(Vector3(mid.x, loom.global_position.y + 0.1, mid.z), 0.0)
		await _frames(4)
		_check("in weave grips a line slides off", pw.snags == snags_before and player.snag_t == 0.0)
	Game.set_flag("weave_grips", false)
	pw.queue_free()
	await _frames(3)


# --- The chord singer ----------------------------------------------------------------------

func _singer() -> void:
	# In the open, ten metres off: the dissonance drags a reload.
	var s := _spawn("chord_singer", LoomExpanse.PATCHES[1]) as ChordSinger
	_place(_at(LoomExpanse.PATCHES[1] + Vector3(0.0, 0.0, 10.0)), PI)
	await _frames(5)
	s.song_index = 0
	s._sing()
	var t := 0.0
	while t < 4.0 and s.detuned_her == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		player.global_position = _at(LoomExpanse.PATCHES[1] + Vector3(0.0, 0.0, 10.0))
	_check("caught in the open, the dissonance detunes her", s.detuned_her == 1 and player.weapon.detuned > 0.0)
	var base: float = player.weapon.spec()["reload"]
	_check("a detuned reload drags", player.weapon.reload_time() > base + 1.0, "%.1f vs %.1f" % [player.weapon.reload_time(), base])
	# The pull: a tug toward it.
	s.song_index = 1
	s._sing()
	await get_tree().create_timer(0.5).timeout
	_check("the pull tugs her toward it", s.pulled_her >= 1)
	await get_tree().create_timer(2.0).timeout
	# The call: pinweavers nearby anchor twice as fast.
	var pw := _spawn("pinweaver", LoomExpanse.PATCHES[1] + Vector3(10.0, 0.0, 6.0)) as Pinweaver
	await _frames(2)
	s.song_index = 3
	s._sing()
	await _frames(2)
	_check("the call quickens nearby pinweavers", pw.called > 0.0)
	pw.queue_free()
	s.queue_free()
	await _frames(5)
	player.weapon.detuned = 0.0
	# Behind a boulder: the song breaks on the rock.
	s = _spawn("chord_singer", LoomExpanse.PATCHES[0]) as ChordSinger
	var boulder: Vector3 = LoomExpanse.BOULDERS[0][0]
	var away: Vector3 = (boulder - LoomExpanse.PATCHES[0]).normalized()
	var hide: Vector3 = boulder + away * 3.0
	_place(_at(hide), 0.0)
	await _frames(5)
	_check("the boulder stands between them", s.sheltered())
	s.song_index = 0
	s._sing()
	t = 0.0
	while t < 4.0 and s._ring_r >= 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		player.global_position = _at(hide)
	_check("behind the boulder the dissonance breaks", s.detuned_her == 0 and player.weapon.detuned == 0.0)
	# A shot through the membrane while it draws breath stops the song.
	s.state = ChordSinger.State.INHALE
	s._timer = ChordSinger.INHALE_TIME
	await _frames(2)
	_check("drawing breath, its membrane shows", s.weak_spot() != Vector3.INF)
	s.take_damage(10.0, s.weak_spot(), Vector3.FORWARD)
	await _frames(2)
	_check("a membrane shot interrupts the song", s.interrupted == 1 and s.state == ChordSinger.State.STAGGER)
	var sung := s.sung
	await get_tree().create_timer(ChordSinger.STAGGER_TIME + 0.3).timeout
	_check("and it retreats to another patch without singing", s.sung == sung and s.state == ChordSinger.State.WALK)
	s.queue_free()
	await _frames(3)


# --- Shortcut, locker, marker, bypass ------------------------------------------------------

func _places() -> void:
	# The curtain across the tunnel's south end holds until the knot is cut.
	_place(_at(Vector3(0.0, 0.3, 26.5)), 0.0)
	await _frames(3)
	_check("from the south the tunnel is laced shut", _label().contains("Taut fibres"), _label())
	await _walk(1.5)
	_check("the curtain stops her", loom.to_local(player.global_position).z > LoomExpanse.CURTAIN.z, str(loom.to_local(player.global_position)))
	# The knot at the north end.
	_place(_at(LoomExpanse.KNOT + Vector3(0.0, -2.0, -1.4)), PI)
	await _frames(3)
	_check("at the north mouth the knot can be cut", _label().contains("tension knot"), _label())
	await _press("interact")
	await _frames(3)
	_check("cutting it opens the shortcut", loom.shortcut_open() and not loom.curtain.visible and not loom.knot.visible)
	_place(_at(Vector3(0.0, 0.3, -27.0)), 0.0)
	await _frames(3)
	var ok := await _walk_path([_at(Vector3(0.0, 0.0, 0.0)), _at(Vector3(0.0, 0.0, 30.0))], 10.0)
	_check("Juno can walk the tunnel home", ok, str(loom.to_local(player.global_position)))
	# The knot can be shot as well.
	_check("the knot answers a shot", loom.knot.get_child(0).has_meta("on_hit"))
	# The survey locker.
	_place(_at(LoomExpanse.LOCKER + Vector3(0.0, 0.3, 1.4)), 0.0)
	await _frames(3)
	_check("the survey locker can be opened", _label().contains("survey team's locker"), _label())
	await _press("interact")
	await _frames(3)
	_check("it holds the weave grips", Game.flags.get("weave_grips") == true and loom.locker_lid.rotation.x < -1.0)
	# The marker on the ledge: up the ramp.
	_place(_at(Vector3(22.0, 0.3, -62.0)), 0.0)
	await _frames(3)
	ok = await _walk_path([_at(Vector3(25.0, 0.0, -62.0)), _at(Vector3(35.0, 3.0, -62.0)), _at(LoomExpanse.MARKER + Vector3(-1.2, 0.0, 1.2))], 10.0)
	_check("Juno can climb the ledge to the marker", ok and player.global_position.y - loom.global_position.y > 2.5, str(loom.to_local(player.global_position)))
	await _frames(3)
	_check("the marker can be read", _label().contains("survey marker"), _label())
	await _press("interact")
	await _frames(3)
	_check("reading it finds the survey log", Game.has_log("loom_survey"))
	# The bypass: laced until the signal flag.
	_place(_at(LoomExpanse.BYPASS_GATE + Vector3(0.0, 0.3, 1.0)), 0.0)
	await _frames(3)
	_check("the bypass is laced", not loom.bypass_open() and _label().contains("laced"), _label())
	Game.set_flag("find_signal_flag", true)
	await _frames(3)
	_check("the signal flag opens it", loom.bypass_open() and not loom.bypass.visible)
	ok = await _walk_path([_at(LoomExpanse.BYPASS_GATE + Vector3(0.0, 0.0, -3.0)), _at(Vector3(-52.0, 0.0, -28.0))], 25.0)
	_check("and the lane behind the Weave can be walked", ok, str(loom.to_local(player.global_position)))
	_check("with the shortcut open the Loom's quest is done", main.quests.is_done("the_loom"))


# --- Save and load -------------------------------------------------------------------------

func _save_load() -> void:
	main.save_game()
	var data := Game.read_save()
	_check("the save records the Loom", data.get("region") == "loom_expanse")
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
	loom = rm.scene as LoomExpanse
	_check("loading a save made there returns to the Loom", rm.current == "loom_expanse" and loom != null and Game.region == "loom_expanse")
	if loom == null:
		return
	_check("and the Loom remembers what was done", loom.shortcut_open() and not loom.curtain.visible and Game.flags.get("weave_grips") == true and loom.bypass_open())
	_check("and its way out leads back to the Shatterlands", rm.parent_of("loom_expanse") == "shatterlands")
	_place(loom.exit_global() + Vector3(0.0, 0.5, -1.0), 0.0)
	await _frames(3)
	_check("the way back is offered at the mouth", _label().contains("Shatterlands"), _label())
	await _press("interact")
	await _wait_travel()
	_check("back in the Shatterlands, at the cleft", rm.current == "shatterlands" and _flat_distance(player.global_position, rm.scene.to_global(RegionDB.get_region("loom_expanse")["gate_pos"])) < 5.0, str(player.global_position))


func _region_budget(region: Node) -> bool:
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
	print("  region budget: %d meshes, %d lights (%d shadowed)" % [meshes, lights, shadowed])
	return meshes <= 120 and lights <= 8 and shadowed == 0
