extends "res://tests/test_base.gd"
## Headless run through the full repair campaign: every site's layout and hazards, every
## find > carry > install loop in order, each repair's benefit, and the launch. Run:
##   godot --headless --path . res://tests/campaign_test.tscn


func _name() -> String:
	return "CAMPAIGN TEST"


func _run() -> void:
	await _frames(30)
	_clear_enemies()
	_check_sites()
	await _check_routes()
	await _check_hazards()
	await _check_pack_wakes()

	# Skip ahead past the slice's two repairs (the smoke test covers those loops).
	kestrel.set_repaired("aux_power", true)
	kestrel.set_repaired("cooling", true)
	await _frames(5)
	_check("campaign moves on to the canopy", Game.current_repair() == "canopy" and Game.phase() == "find", Game.current_repair())
	player.revive(kestrel.to_global(kestrel.plan(10.1, -1.0, 17.8)) + Vector3.UP * 0.3)
	await _frames(10)
	_check("install points don't answer through the hull", not _label().contains("Canopy") and not _label().contains("bay"), _label())
	_check("only the canopy site's beacon is active", main.sites.keys().all(func(id): return main.sites[id].active == (id == "canopy")))

	# Scanner is off until the canopy is sealed.
	player.revive(Vector3(45.0, 0.5, 45.0))
	var probe: Node3D = main.spawn_scuttler(Vector3(45.0, 0.5, 30.0))
	await _frames(5)
	_check("no scanner before the canopy", main.scanner_marks().is_empty())
	probe.queue_free()
	_clear_enemies()

	for i in range(2, Campaign.REPAIRS.size()):
		await _repair_loop(Campaign.REPAIRS[i])
		await _check_benefit(Campaign.REPAIRS[i]["id"])

	_check("every repair done", Game.repairs_done() == 7 and Game.phase() == "launch")
	player.revive(main.install_point("launch") + Vector3.UP * 0.2)
	await _frames(10)
	_check("pilot's seat offers launch", _label().contains("[E] Launch"), _label())
	await _press("interact")
	_check("Kestrel launches", Game.launched and Game.phase() == "done" and main.hud.ending_visible())
	finished = true


## Layout sanity for every site: faces the ship, the component is on a floor, clear of each other.
func _check_sites() -> void:
	var ids: Array = main.sites.keys()
	var facing := ids.all(func(id):
		var s: ExpeditionSite = main.sites[id]
		return s.global_basis.z.dot((kestrel.global_position - s.global_position).normalized()) > 0.95)
	_check("every site faces the ship", facing)
	var floors := []
	for id in ids:
		var p: Vector3 = main.sites[id].component_point()
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.8, p + Vector3.DOWN * 0.6, Game.LAYER_WORLD)
		if main.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			floors.append(id)
	_check("every component stands on a floor", floors.is_empty(), str(floors))
	var close := []
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			if main.sites[ids[a]].global_position.distance_to(main.sites[ids[b]].global_position) < 45.0:
				close.append("%s/%s" % [ids[a], ids[b]])
	_check("sites are spread out", close.is_empty(), str(close))
	_check("every site has crates", ids.all(func(id): return main.sites[id].crate_count() >= 3))


## The routes in and out: the spire climb, the crawler's bay, the engine section.
func _check_routes() -> void:
	var spire: SpireSkiff = main.sites["canopy"]
	var path := spire.climb_path()
	player.revive(path[0] + Vector3(0.0, 0.3, 2.0))
	await _frames(10)
	var ok := await _walk_path(path)
	_check("spire climb reaches the skiff", ok and player.global_position.distance_to(spire.component_point()) < 1.0, "at %s" % player.global_position)

	var quarry: QuarryCrawler = main.sites["landing_gear"]
	player.revive(quarry.to_global(Vector3(0.0, 0.3, 6.0)))
	await _frames(10)
	ok = await _walk_path([quarry.to_global(Vector3(0.0, 0.0, 1.0)), quarry.to_global(Vector3(0.0, QuarryCrawler.BAY_FLOOR, -4.0)), quarry.component_point()])
	_check("crawler bay is walkable up the ramp", ok and player.global_position.distance_to(quarry.component_point()) < 1.0, "at %s" % player.global_position)

	var yard: FreighterGraveyard = main.sites["engine"]
	for arc in yard.arcs():
		arc.set_physics_process(false)
	player.revive(yard.to_global(Vector3(0.0, 0.3, -11.5)))
	await _frames(10)
	ok = await _walk_path([yard.to_global(Vector3(0.0, 0.0, -15.0)), yard.to_global(Vector3(0.0, FreighterGraveyard.ENGINE_FLOOR, -20.0)), yard.component_point()])
	_check("engine section is walkable to the coil", ok and player.global_position.distance_to(yard.component_point()) < 1.0, "at %s" % player.global_position)
	for arc in yard.arcs():
		arc.set_physics_process(true)

	var moss: MossDropship = main.sites["wing"]
	for pod in moss.pods():
		pod.set_physics_process(false)
	player.revive(moss.to_global(Vector3(0.0, 0.3, 14.0)))
	await _frames(10)
	ok = await _walk_path([moss.to_global(Vector3(-2.5, 0.0, 6.0)), moss.to_global(Vector3(-8.0, 0.0, 1.5)), moss.component_point()])
	_check("dropship wing panel is reachable", ok, "at %s" % player.global_position)
	for pod in moss.pods():
		pod.set_physics_process(true)

	var loom: LoomSpire = main.sites["navigation"]
	player.revive(loom.to_global(Vector3(0.0, 0.3, 14.0)))
	await _frames(10)
	ok = await _walk_path([loom.component_point()])
	_check("Loom nav core is reachable", ok, "at %s" % player.global_position)
	player.revive(main.SPAWN)
	await _frames(5)


func _check_hazards() -> void:
	var quarry: QuarryCrawler = main.sites["landing_gear"]
	var rock: Rockfall = quarry.rockfalls()[0]
	player.revive(rock.global_position + Vector3.UP * 0.3)
	await _frames(10)
	rock.reset()
	var before := player.health
	rock.trigger()
	await get_tree().create_timer(rock.warning_time + 0.3).timeout
	_check("rockfall hits the player", player.health <= before - rock.burst_damage + 1.0, "health=%.0f" % player.health)

	var yard: FreighterGraveyard = main.sites["engine"]
	var arc: ArcGap = yard.arcs()[0]
	player.revive(arc.global_position + Vector3.UP * 0.3)
	await _frames(10)
	before = player.health
	arc.reset()
	arc.trigger()
	await get_tree().create_timer(arc.warning_time + 0.6).timeout
	_check("arc conduit burns the player", player.health < before, "health=%.0f" % player.health)

	var moss: MossDropship = main.sites["wing"]
	var pod: SporePod = moss.pods()[1]
	player.revive(main.SPAWN)
	await _frames(5)
	for p in moss.pods():
		p.reset()
	var victim: Scuttler = main.spawn_scuttler(pod.global_position + Vector3(1.2, 0.3, 0.0))
	victim.target = null
	await _frames(10)
	pod.take_hit()
	await get_tree().create_timer(pod.warning_time + 1.2).timeout
	_check("shot spore pod chokes a scuttler", is_instance_valid(victim) and victim.health < victim.max_health, "pod phase=%d" % pod.phase)
	victim.queue_free()
	var near_pod: SporePod = moss.pods()[0]
	player.revive(near_pod.global_position + Vector3(1.5, 0.3, 0.0))
	await _frames(10)
	_check("spore pod swells when walked up to", near_pod.phase != TimedHazard.Phase.QUIET)
	before = player.health
	await get_tree().create_timer(near_pod.warning_time + 1.5).timeout
	_check("spore cloud hurts the player", player.health < before, "health=%.0f" % player.health)
	_check("spore pods regrow before they can burst again", (func():
		near_pod.trigger()
		return near_pod.phase != TimedHazard.Phase.WARNING).call())

	var loom: LoomSpire = main.sites["navigation"]
	var pulse := loom.pulse
	# The pulse finds the player on its own.
	pulse.target = null
	player.revive(pulse.global_position + Vector3(0.0, 0.3, 8.0))
	await _frames(10)
	before = player.health
	pulse.fire()
	await get_tree().create_timer(1.2).timeout
	_check("Loom pulse knocks down a player on the ground", player.health < before, "health=%.0f" % player.health)
	player.revive(pulse.global_position + Vector3(0.0, 0.3, 8.0))
	await _frames(10)
	before = player.health
	pulse.fire()
	var hit := false
	for i in 90:
		# Hold the player in the air as the ring passes underneath.
		player.global_position.y = pulse.global_position.y + 1.0
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		hit = hit or player.health < before
	_check("jumping clears the Loom pulse", not hit)
	pulse.target = null
	player.revive(main.SPAWN)
	await _frames(5)


func _check_pack_wakes() -> void:
	main.spawn_packs = true
	var site: ExpeditionSite = main.sites["wing"]
	_check("resident pack sleeps until you get near", not site.pack_spawned)
	player.revive(site.global_position + site.global_basis.z * 30.0 + Vector3.UP * 0.5)
	await get_tree().create_timer(1.2).timeout
	_check("resident pack wakes when you near the site", site.pack_spawned and _enemy_count() >= site.spawn_pts.size(), "enemies=%d" % _enemy_count())
	main.spawn_packs = false
	main.siege.enabled = false  # sieges have their own tests in mechanics_test
	_clear_enemies()
	player.revive(main.SPAWN)
	await _frames(5)


func _repair_loop(r: Dictionary) -> void:
	var id: String = r["id"]
	var site: ExpeditionSite = main.sites[id]
	_clear_enemies()
	# The next site's component can't be taken out of order.
	var next := Campaign.index_of(id) + 1
	if next < Campaign.REPAIRS.size():
		var later: ExpeditionSite = main.sites[Campaign.REPAIRS[next]["id"]]
		player.revive(later.component_point() + Vector3.UP * 0.2)
		await _frames(10)
		_check("%s: later component waits its turn" % id, _label().contains("no use"), _label())
		await _press("interact")
		_check("%s: later component stays put" % id, later.has_component() and Game.carrying == "")

	player.revive(main.install_point(id) + Vector3.UP * 0.3)
	await _frames(10)
	_check("%s: install point asks for the part" % id, _label() == r["bay_label"], _label())

	player.revive(site.component_point() + Vector3.UP * 0.2)
	await _frames(10)
	_check("%s: component prompt at the site" % id, _label().contains(r["component_name"]), _label())
	await _press("interact")
	_check("%s: component is carried" % id, Game.carrying == r["component"] and not site.has_component() and Game.phase() == "return")
	_check("%s: taking it springs an ambush" % id, _enemy_count() >= site.ambush_pts.size(), "enemies=%d" % _enemy_count())
	_clear_enemies()

	player.revive(main.install_point(id) + Vector3.UP * 0.3)
	await _frames(10)
	_check("%s: install point accepts it" % id, _label().contains(r["install_label"]), _label())
	await _press("interact")
	_check("%s: installed" % id, kestrel.is_repaired(id) and Game.is_repaired(id) and Game.carrying == "")


func _check_benefit(id: String) -> void:
	match id:
		"canopy":
			player.revive(Vector3(45.0, 0.5, 45.0))
			var probe: Node3D = main.spawn_scuttler(Vector3(45.0, 0.5, 30.0))
			await _frames(5)
			var marks: Array = main.scanner_marks()
			_check("canopy: scanner shows wildlife", marks.any(func(m): return m["kind"] == "enemy"))
			player.revive(main.sites["landing_gear"].global_position + Vector3.UP * 0.5)
			await _frames(5)
			_check("canopy: scanner shows salvage crates", main.scanner_marks().any(func(m): return m["kind"] == "crate"))
			probe.queue_free()
			_clear_enemies()
		"landing_gear":
			await get_tree().create_timer(3.6).timeout
			_check("landing gear: ship is level and the cargo ramp is down", kestrel.ramp_open() and kestrel.rotation.length() < 0.001)
			# Walk up the ramp from the ground behind the ship into the cargo bay.
			var foot := kestrel.to_global(kestrel.plan(34.0, -1.2, 13.0))
			var inside := kestrel.to_global(kestrel.plan(27.0, 0.0, 13.0))
			player.revive(foot + Vector3.UP * 0.3)
			await _frames(10)
			var ok := await _walk_path([kestrel.to_global(kestrel.plan(31.0, -0.5, 13.0)), inside])
			var local := kestrel.to_local(player.global_position)
			_check("landing gear: cargo ramp walks up into the hold", ok and local.y > -0.2, "local=%s" % local)
			player.revive(main.install_point("armoury") + Vector3.UP * 0.2)
			player.take_damage(30.0)
			player.weapon.in_mag = 2
			await _frames(10)
			_check("landing gear: armoury locker unjammed", _label().contains("armoury locker"), _label())
			await _press("interact")
			_check("landing gear: armoury hands over the scattergun", Game.owns_weapon("scattergun") and player.weapon.current == "scattergun")
			_check("landing gear: resupply refills ammo and suit", player.weapon.in_mag == player.weapon.mag_size() and player.health == player.max_health())
			await _frames(5)
			_check("landing gear: locker then offers resupply", _label().contains("Resupply"), _label())
		"wing":
			player.revive(kestrel.to_global(kestrel.plan(18.0, 0.1, 13.0)))
			await _frames(5)
			var turret: PointDefense = kestrel.turret
			var at := turret.global_position + Vector3(6.0, 0.0, -14.0)
			at.y = 0.5
			var target: Scuttler = main.spawn_scuttler(at)
			target.target = null
			var killed := false
			for i in 60 * 8:
				await get_tree().physics_frame
				if not is_instance_valid(target) or target.state == Scuttler.State.DEAD:
					killed = true
					break
			_check("wing: point-defence turret kills a scuttler near the ship", killed)
			_clear_enemies()
		"engine":
			_check("engine: top fabricator tier unlocks", Game.can_fabricate("rapid_cycler") and Game.can_fabricate("plating_2"))
		"navigation":
			_check("navigation: departure is ready", Game.phase() == "launch" and Game.objective_text().contains("launch"))
