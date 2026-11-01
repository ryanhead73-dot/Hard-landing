extends "res://tests/test_base.gd"
## Encounters out on the basin: the mire lurker's ambush, bite, dive and heal, and the wildlife
## director's lurker pools and roaming packs. Run:
##   godot --headless --path . res://tests/encounters_test.tscn


func _name() -> String:
	return "ENCOUNTERS TEST"


func _run() -> void:
	await _frames(30)
	_clear_enemies()
	await _lurker()
	await _director()
	await _weather()
	await _weak_spots()
	finished = true


func _pool() -> Array:
	return main.wildlife.lurker_pools[0]


func _lurker() -> void:
	var w: Wildlife = main.wildlife
	_check("some pools hold lurkers", w.lurker_pools.size() >= 2, str(w.lurker_pools.size()))
	var ship: Vector3 = kestrel.global_position
	_check("no lurker pool near the ship", w.lurker_pools.all(func(p): return _flat_distance(p[0], ship) > Wildlife.SHIP_CLEAR))
	var pool := _pool()
	var centre: Vector3 = pool[0]
	var radius: float = pool[1]
	# Stand well back, on the side facing the ship.
	var out := _flat_dir(ship - centre)
	var safe := centre + out * (radius + 16.0)
	safe.y = main.site.height_at(safe.x, safe.z) + 0.3
	player.revive(safe)
	await _frames(5)
	var lk: Lurker = main.spawn_enemy("lurker", centre)
	lk.pool_radius = radius
	await _frames(20)
	_check("lurker waits submerged", lk.is_submerged() and lk.anim_state() == "submerged")
	_check("only its eyes break the surface", lk._visual.position.y < -0.3, "%.2f" % lk._visual.position.y)
	var mid := centre + out * (radius + 9.0)
	mid.y = main.site.height_at(mid.x, mid.z) + 0.3
	player.revive(mid)
	var hp := lk.health
	lk.take_damage(50.0, lk.global_position, Vector3.FORWARD)
	_check("under the water it barely feels a hit", hp - lk.health < 10.0, "%.1f" % (hp - lk.health))
	await _frames(2)
	_check("a hit flushes it out", not lk.is_submerged(), lk.anim_state())
	await get_tree().create_timer(1.0).timeout
	_check("surfaced, it rises out of the water", lk._visual.position.y > -0.15, "%.2f" % lk._visual.position.y)

	# Out of reach of its pool, it gives up and goes home.
	var far := centre + out * (radius + lk.pool_leash + radius + 14.0)
	far.y = main.site.height_at(far.x, far.z) + 0.3
	player.revive(far)
	var dove := false
	for i in 60 * 8:
		await get_tree().physics_frame
		if lk.is_submerged():
			dove = true
			break
	_check("left alone, it dives back to its pool", dove and _flat_distance(lk.global_position, centre) < 1.5, "%s at %.1f m" % [lk.anim_state(), _flat_distance(lk.global_position, centre)])
	var low := lk.health
	await get_tree().create_timer(1.0).timeout
	_check("it heals under the water", lk.health > low, "%.0f -> %.0f" % [low, lk.health])

	# Walking up to the pool springs the ambush; then it bites.
	await get_tree().create_timer(2.5).timeout
	var near := centre + out * (radius - 1.0)
	near.y = main.site.height_at(near.x, near.z) + 0.3
	player.revive(near)
	var before := player.health
	var emerged := false
	var wound_up := false
	for i in 60 * 6:
		await get_tree().physics_frame
		emerged = emerged or lk.anim_state() == "emerge"
		wound_up = wound_up or lk.state == Lurker.State.WINDUP
		if player.health < before:
			break
	_check("coming close springs the ambush", emerged)
	_check("it gapes before it bites", wound_up)
	_check("the bite lands hard", before - player.health >= 15.0, "health %.0f -> %.0f" % [before, player.health])

	# Caught mid-gape it takes extra damage.
	lk.state = Lurker.State.WINDUP
	lk._timer = 5.0
	await get_tree().create_timer(0.5).timeout
	_check("the jaw gapes on the wind-up", lk.anim.pose.rot_of("Jaw").x < -25.0, "%.0f" % lk.anim.pose.rot_of("Jaw").x)
	hp = lk.health
	lk.take_damage(20.0, lk.global_position, Vector3.FORWARD)
	_check("a shot into the open mouth hits harder", hp - lk.health > 25.0, "%.1f" % (hp - lk.health))
	var dropped := [false]
	main.player.revive(safe)
	lk.died.connect(func(_e): dropped[0] = true)
	lk.take_damage(9999.0, lk.global_position, Vector3.FORWARD)
	_check("it dies and pays out", lk.dead and dropped[0])
	await _frames(5)
	_clear_enemies()


func _director() -> void:
	var w: Wildlife = main.wildlife
	_check("no packs at the ship", not w.in_the_open(main.SPAWN))
	var open := _open_point()
	_check("open ground between the sites counts as the open", open != Vector3.INF, str(open))
	if open == Vector3.INF:
		return
	player.revive(open)
	await _frames(5)
	Game.repaired.clear()
	var simple := true
	for i in 30:
		simple = simple and w.pack_kinds().all(func(k): return k == "scuttler")
	_check("early packs are scuttlers only", simple)
	for id in ["aux_power", "cooling", "canopy", "landing_gear"]:
		Game.repaired[id] = true
	var seen := {}
	for i in 60:
		for k in w.pack_kinds():
			seen[k] = true
	_check("later packs bring spitters and rams", seen.has("spitter") and seen.has("ram"), str(seen.keys()))
	Game.repaired.clear()

	var pack := w.send_pack()
	_check("a pack is sent", pack.size() >= 2, str(pack.size()))
	var ok := not pack.is_empty()
	for e in pack:
		var d := _flat_distance(e.global_position, player.global_position)
		ok = ok and d > Wildlife.ROAM_SPAWN.x - 4.0 and d < Wildlife.ROAM_SPAWN.y + 4.0
		ok = ok and _flat_distance(e.global_position, kestrel.global_position) > Wildlife.SHIP_CLEAR - 3.0
	_check("it arrives out of sight ahead, away from the ship", ok)
	_check("roamers are tracked", w.roamers.size() == pack.size())
	var count := w.roamers.size()
	for i in 20:
		w.send_pack()
	_check("roamers are capped", w.roamers.size() <= Wildlife.ROAM_MAX_ALIVE + 4 and w.roamers.size() >= count, str(w.roamers.size()))

	# Left far behind, a calm pack wanders off.
	for e in w.roamers:
		e.calm()
	var away := -open.normalized() * 80.0
	away.y = main.site.height_at(away.x, away.z) + 0.3
	player.revive(away)
	await _frames(5)
	w.update(0.5)
	await _frames(3)
	_check("stragglers left far behind wander off", w.roamers.is_empty(), str(w.roamers.size()))
	player.revive(main.SPAWN)
	await _frames(5)

	# The timer sends packs only while out in the open.
	w._roam_timer = 0.1
	w.update(0.5)
	_check("no packs while home", w.roamers.is_empty())
	player.revive(open)
	await _frames(5)
	w.update(0.5)
	_check("packs come while out in the open", not w.roamers.is_empty() and w.packs_sent > 0)
	_clear_enemies()

	# Coming near a lurker pool wakes its lurker, once.
	var pool := _pool()
	pool[2] = false
	var by := (pool[0] as Vector3) + Vector3(0.0, 0.0, float(pool[1]) + 20.0)
	by.y = main.site.height_at(by.x, by.z) + 0.3
	player.revive(by)
	await _frames(3)
	var lurkers_before := get_tree().get_nodes_in_group("lurkers").size()
	w.update(0.5)
	w.update(0.5)
	_check("a pool's lurker wakes when you come near, once", get_tree().get_nodes_in_group("lurkers").size() == lurkers_before + 1)
	_clear_enemies()


func _weather() -> void:
	var w: Weather = main.weather
	var open := _open_point()
	player.revive(open)
	await _frames(5)
	var env: Environment = main._env
	var clear_fog := env.fog_density
	var sc: Scuttler = main.spawn_enemy("scuttler", open + Vector3(0.0, 0.0, -20.0))
	await _frames(5)
	_check("in clear weather a scuttler sees you at 20 m", sc._can_see_target())
	w.start_storm(true)
	await _frames(3)
	_check("a storm comes in", w.storm == 1.0 and main.storm == 1.0 and w.state == Weather.State.STORM)
	_check("the haze closes in", env.fog_density > clear_fog + 0.008, "%.4f -> %.4f" % [clear_fog, env.fog_density])
	_check("in the storm it can't see you at 20 m", not sc._can_see_target(), "sight x%.2f" % Enemy.sight_scale)
	_check("rain falls around you outdoors", w._rain.emitting and w._splash.emitting)
	_check("rock goes wet", main.site._terrain_mat.get_shader_parameter("rain") > 0.9)
	_check("Juno remarks on it", main.voice.heard("Squall") or main.voice.heard("Rain again") or main.voice.heard("Here it comes"))
	var sun: DirectionalLight3D = main._sun
	var dim := sun.light_energy
	w.strike()
	await get_tree().create_timer(0.05).timeout
	_check("lightning flashes", main.flash > 0.5 and sun.light_energy > dim + 0.5, "%.2f -> %.2f" % [dim, sun.light_energy])
	await get_tree().create_timer(0.8).timeout
	_check("the flash passes", main.flash == 0.0)
	player.revive(main.install_point("bunk") + Vector3.UP * 0.2)
	await _frames(15)
	_check("no rain inside Kestrel", not w._rain.emitting)
	w.clear_storm(true)
	await _frames(3)
	_check("the storm clears", w.storm == 0.0 and Enemy.sight_scale == 1.0 and not w._rain.emitting)
	w.enabled = true
	w._timer = 0.05
	await _frames(5)
	_check("storms come round on their own", w.state == Weather.State.BUILDING and w.storm > 0.0)
	w.enabled = false
	w.clear_storm(true)
	_clear_enemies()


func _weak_spots() -> void:
	var open := _open_point()
	player.revive(open + Vector3(0.0, 0.0, 30.0))
	await _frames(5)
	for kind in ["scuttler", "spitter", "ram", "lurker"]:
		var at := open + Vector3(0.0, 0.0, -6.0)
		at.y = main.site.height_at(at.x, at.z) + 0.2
		var e: Enemy = main.spawn_enemy(kind, at)
		if e is Lurker:
			_check("a submerged lurker shows no weak spot", e.weak_spot() == Vector3.INF)
			e.state = Lurker.State.RECOVER
			e._timer = 99.0
		await _frames(30)
		await get_tree().physics_frame
		var ws := e.weak_spot()
		_check("%s has a weak spot" % kind, ws != Vector3.INF)
		if ws == Vector3.INF:
			continue
		# Straight down onto the glowing part, then square into its flank at mid height.
		var top := _ray(ws + Vector3.UP * 3.0, ws + Vector3.DOWN * 2.0)
		var mid := e.global_position + Vector3.UP * 0.45
		var side_dir := e.global_basis.x
		var flank := _ray(mid + side_dir * 5.0, mid - side_dir * 2.0)
		_check("%s: a shot onto its weak spot crits" % kind, top != Vector3.INF and e.is_weak_hit(top, Vector3.DOWN), "%s vs %s" % [top, ws])
		_check("%s: a shot into its flank does not" % kind, flank != Vector3.INF and not e.is_weak_hit(flank, -side_dir), "%s vs %s" % [flank, ws])
		_check("%s: a blast never crits" % kind, not e.is_weak_hit(ws, Vector3.ZERO))
		var hp := e.health
		e.take_damage(10.0, top, Vector3.DOWN)
		_check("%s: the crit hits harder" % kind, e.last_hit_crit and hp - e.health >= 10.0 * Enemy.CRIT_MULT - 0.01, "%.1f" % (hp - e.health))
		e.take_damage(9999.0, e.global_position, Vector3.ZERO)
		await _frames(3)
	_clear_enemies()

	# End to end: the rifle aimed at a scuttler's back ridge lands crits and the HUD shows them.
	player.revive(open)
	await _frames(5)
	var target := open + Vector3(0.0, 0.0, -7.0)
	target.y = main.site.height_at(target.x, target.z) + 0.2
	var sc: Scuttler = main.spawn_enemy("scuttler", target)
	sc.max_health = 9999.0
	sc.health = 9999.0
	await _frames(10)
	var crits := [0]
	player.weapon.crit_landed.connect(func(): crits[0] += 1)
	var shown: int = main.hud.crits_shown
	for i in 40:
		if crits[0] > 0 or not is_instance_valid(sc):
			break
		var ws := sc.weak_spot()
		player.aim_at(ws)
		await get_tree().physics_frame
		player.weapon._cooldown = 0.0
		player.weapon.in_mag = maxi(player.weapon.in_mag, 2)
		player.weapon.try_fire(true)
		await _frames(2)
	_check("aimed at the glowing ridge, the rifle lands a crit", crits[0] > 0 and sc.crits_taken > 0)
	_check("the HUD shows a crit marker", main.hud.crits_shown > shown)
	_clear_enemies()


func _ray(from: Vector3, to: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.LAYER_ENEMY)
	var r := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return r.position if not r.is_empty() else Vector3.INF


## A point out on the basin where packs roam, found by walking rings round the ship.
func _open_point() -> Vector3:
	var w: Wildlife = main.wildlife
	for r in [50.0, 65.0, 80.0, 95.0]:
		for k in 24:
			var a := TAU * k / 24.0
			var p: Vector3 = kestrel.global_position + Vector3(cos(a), 0.0, sin(a)) * r
			p.y = main.site.height_at(p.x, p.z) + 0.3
			if w.in_the_open(p) and not main.site.in_pool(p):
				return p
	return Vector3.INF


func _flat_dir(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()
