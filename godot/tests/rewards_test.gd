extends "res://tests/test_base.gd"
## The three Kestrel rewards the production pack promised for the Shatterlands repairs:
##   canopy        Brandt's rescue trail in the Gillwood (waymarks, two stash tins, the map inset)
##   landing gear  the utility drone station in the cargo bay (fetches pickups, patches her)
##   wing          the field beacon (plant it with B; going down brings her back beside it)

var rm: RegionManager


func _name() -> String:
	return "REWARDS TEST"


func _run() -> void:
	await _frames(10)
	Game.reset()
	for r in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(r, false)
	rm = main.regions
	await _beacon()
	await _drone()
	await _trail()
	Game.delete_save()
	finished = true


func _wait_travel() -> void:
	await _frames(2)
	var t := 0.0
	while rm.travelling and t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _frames(10)


func _beacon() -> void:
	var fb: FieldBeacon = main.beacon
	_place(main.SPAWN + Vector3(0.0, 0.5, 30.0), 0.0)
	await _frames(10)
	_check("no beacon before the wing", not fb.unlocked() and fb.blocked_reason() != "")
	await _press("beacon")
	_check("B does nothing yet", Game.flags.get("beacon_region", "") == "")
	Game.set_repaired("wing", true)
	kestrel.set_repaired("wing", true)
	_check("the wing unlocks the beacon", fb.unlocked())
	# Not on the ship.
	_place(kestrel.global_position + Vector3(0.0, 1.0, 0.0), 0.0)
	await _frames(10)
	_check("it won't plant at Kestrel", fb.blocked_reason() != "")
	var out: Vector3 = main.SPAWN + Vector3(25.0, 0.0, 35.0)
	out.y = main.site.height_at(out.x, out.z) + 0.3
	_place(out, 0.0)
	await _frames(15)
	await _press("beacon")
	await _frames(3)
	var here = fb.here()
	_check("B plants it where she stands", here is Vector3 and _flat_distance(here, out) < 1.0, str(here))
	_check("it stands in the world with its light column", fb.visual != null and is_instance_valid(fb.visual) and fb.visual.get_node("Column") != null)
	_check("it shows on the scanner", main.scanner_marks().any(func(m): return m["kind"] == "beacon"))
	_check("and on the compass", main.hud.beacon_target is Vector3)
	main.map_panel.main = main
	_check("and on the map", main.map_panel.marks().any(func(m): return m["kind"] == "beacon"))
	# Going down brings her back beside it.
	_place(out + Vector3(30.0, 0.0, 10.0), 0.0)
	await _frames(5)
	player.take_damage(9999.0)
	await get_tree().create_timer(main.RESPAWN_DELAY + 0.5).timeout
	_check("going down brings her back up beside it", not player.dead and _flat_distance(player.global_position, here) < 3.0, str(player.global_position))
	# Planting again moves it; one at a time.
	var out2: Vector3 = out + Vector3(-12.0, 0.0, 6.0)
	out2.y = main.site.height_at(out2.x, out2.z) + 0.3
	_place(out2, 0.0)
	await _frames(15)
	fb.place()
	await _frames(3)
	_check("planting again moves it", fb.here() is Vector3 and _flat_distance(fb.here(), out2) < 1.0 and _count_beacons() == 1, "%s at %s, %d beacons, %s, %s" % [fb.here(), out2, _count_beacons(), fb.blocked_reason(), fb.visual.get_path() if fb.visual else "none"])
	# It belongs to the region it's in: away in the Shatterlands it doesn't show or catch her.
	Game.set_flag("shatterlands_open")
	rm.travel("shatterlands", true)
	await _wait_travel()
	_check("in another region the Kettle's beacon doesn't count", fb.here() == null and main.hud.beacon_target == null)
	player.take_damage(9999.0)
	await get_tree().create_timer(main.RESPAWN_DELAY + 0.5).timeout
	_check("so she comes back at the region's way in", player.global_position.distance_to(rm.scene.entry_global()) < 2.0)
	_place(rm.scene.entry_global() + Vector3(4.0, 0.0, -10.0), 0.0)
	await _frames(15)
	fb.place()
	await _frames(3)
	_check("planted in a region it stands under that region", fb.visual != null and fb.visual.get_parent() == rm.scene and Game.flags["beacon_region"] == "shatterlands")
	# Saved and loaded.
	main.save_game()
	var data := Game.read_save()
	await _reload(data)
	_check("a save keeps the beacon", main.beacon.here() is Vector3 and main.beacon.visual != null and is_instance_valid(main.beacon.visual))
	rm.travel("kettle", true)
	await _wait_travel()


func _count_beacons() -> int:
	var n := 0
	var stack: Array = [main]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		stack.append_array(c.get_children())
		if String(c.name).begins_with("BeaconPost") and c is Node3D and not c.is_queued_for_deletion():
			n += 1
	return n


func _reload(data: Dictionary) -> void:
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


func _drone() -> void:
	var station := kestrel.to_global(kestrel.plan(main.DRONE_STATION.x, 0.0, main.DRONE_STATION.z + 0.8))
	_place(station + Vector3(0.0, 0.3, 0.0), 0.0)
	await _frames(10)
	_check("the drone station waits on the landing gear", _label().contains("Drone station") and not main._interaction.has("action"), _label())
	Game.set_repaired("landing_gear", true)
	kestrel.set_repaired("landing_gear", true)
	await _frames(30)
	_place(station + Vector3(0.0, 0.3, 0.0), 0.0)
	await _frames(10)
	_check("with the gear fixed it offers the drone", _label().contains("Launch the utility drone"), _label())
	_check("standing there, nothing blocks the cargo bay", kestrel.is_inside(player.global_position))
	await _press("interact")
	await _frames(5)
	var d: UtilityDrone = main.drone
	_check("launching it puts the drone out", Game.flags.get("drone_out") == true and d != null and is_instance_valid(d))
	# It rides at her shoulder.
	_place(main.SPAWN + Vector3(10.0, 0.5, 30.0), 0.0)
	await get_tree().create_timer(1.5).timeout
	_check("it rides at her shoulder", d.global_position.distance_to(player.global_position) < 3.5, "%.1f m" % d.global_position.distance_to(player.global_position))
	# Fetches what's on the ground.
	var scrap := Game.scrap
	_drop(player.global_position + Vector3(9.0, 0.0, 0.0))
	var t := 0.0
	while t < 6.0 and Game.scrap == scrap:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("it fetches scrap she leaves on the ground", Game.scrap > scrap and d.fetched >= 1, "scrap %d -> %d" % [scrap, Game.scrap])
	# Patches her when she's badly hurt, once a minute.
	player.health = 20.0
	await _frames(5)
	_check("it patches her when she's badly hurt", player.health >= 49.0 and d.patches == 1)
	player.health = 20.0
	await _frames(5)
	_check("but only once a minute", player.health < 21.0 and d.patches == 1)
	_heal()
	# It goes where she goes.
	Game.set_flag("shatterlands_open")
	rm.travel("shatterlands", true)
	await _wait_travel()
	await get_tree().create_timer(0.5).timeout
	_check("it goes with her into a region", is_instance_valid(d) and d.is_visible_in_tree() and d.global_position.distance_to(player.global_position) < 4.0)
	rm.travel("kettle", true)
	await _wait_travel()
	# Saved out; docked.
	main.save_game()
	await _reload(Game.read_save())
	_check("a save keeps it out", main.drone != null and is_instance_valid(main.drone))
	station = kestrel.to_global(kestrel.plan(main.DRONE_STATION.x, 0.0, main.DRONE_STATION.z + 0.8))
	_place(station + Vector3(0.0, 0.3, 0.0), 0.0)
	await _frames(10)
	_check("the station docks it", _label().contains("Dock"), _label())
	await _press("interact")
	await _frames(3)
	_check("docked, it's gone from her side", Game.flags.get("drone_out") == false and main.drone == null)


func _heal() -> void:
	player.health = player.max_health()


func _drop(at: Vector3) -> void:
	var p := ScrapPickup.new()
	p.kind = "scrap"
	p.amount = 7
	p.target = player
	main.add_child(p)
	p.global_position = at


func _trail() -> void:
	Game.set_flag("shatterlands_open")
	Game.set_flag("reyes_talked")
	rm.travel("gillwood", true)
	await _wait_travel()
	var gw := rm.scene as Gillwood
	_check("no trail before the canopy", not gw.trail_open() and gw.interaction(gw.to_global(gw.stash_points[0])).is_empty())
	_check("the Gillwood keeps to its budget with the trail", _budget(gw))
	rm.travel("kettle", true)
	await _wait_travel()
	Game.set_repaired("canopy", true)
	kestrel.set_repaired("canopy", true)
	rm.travel("gillwood", true)
	await _wait_travel()
	gw = rm.scene as Gillwood
	_check("with the canopy sealed the trail is marked", gw.trail_open() and gw.trail_points.size() >= Gillwood.TRAIL.size())
	_check("still in budget with it marked", _budget(gw))
	# The waymarks stand clear of the trees, so it can be walked from the wreck to the way out.
	_place(gw.to_global(gw.trail_points[0] + Vector3(0.0, 0.3, 0.0)), 0.0)
	await _frames(5)
	var ok := await _walk_path(gw.trail_points.map(func(p): return gw.to_global(p)), 14.0)
	_check("the trail can be walked from the wreck to the south mouth", ok, str(gw.to_local(player.global_position)))
	var scrap := Game.scrap
	for i in Gillwood.TRAIL_STASHES.size():
		_place(gw.to_global(gw.stash_points[i] + Vector3(0.0, 0.3, 1.0)), 0.0)
		await _frames(4)
		_check("stash tin %d can be opened" % i, _label().contains("stash tin"), _label())
		await _press("interact")
		await _frames(3)
	_check("the stash tins pay out", Game.scrap == scrap + 30 and gw.stashes_left() == 0)
	main.map_panel.main = main
	var inset: Dictionary = main.map_panel.inset()
	_check("the map's inset shows the Gillwood and the trail", inset["nodes"].any(func(n): return n["id"] == "gillwood" and n["here"]) and not inset["trail"].is_empty())


func _budget(region: Node) -> bool:
	var meshes := 0
	var lights := 0
	var stack: Array = [region]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			meshes += 1
		if n is Light3D:
			lights += 1
	print("  region budget: %d meshes, %d lights" % [meshes, lights])
	return meshes <= 120 and lights <= 8
