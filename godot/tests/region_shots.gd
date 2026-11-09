extends Node
## Dev utility: renders the expansion regions for review (the Kettle's gate and the Shatterlands
## threshold). Needs a real renderer:
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/region_shots.tscn -- <out_dir>

var main: Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	Game.window_mode = 0
	Game.apply_settings()
	Game.save_path = "user://region_shots_save.json"
	Game.intro_pending = args.size() > 1 and args[1] == "opening"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	await _frames(20)
	for s in get_tree().get_nodes_in_group("enemies"):
		s.queue_free()
	main.day_cycle = false
	main.set_daylight(0.0)
	# `-- <out_dir> greenhouses` renders only Voss's greenhouses; `shatterlands`, the whole pocket;
	# `nest`, only the wreck's nested pack; `darkhouse`, only Teo's favour; `gillwood`, the
	# north split and the Gillwood beyond it.
	if args.size() > 1 and args[1] == "opening":
		await _opening(out)
		Game.delete_save()
		get_tree().quit()
		return
	if args.size() > 1 and args[1] == "missions":
		await _missions(out)
		Game.delete_save()
		get_tree().quit()
		return
	if args.size() > 1 and args[1] == "loom2":
		Game.set_flag("shatterlands_open")
		Game.set_flag("loom_open")
		await main.regions.travel("loom_expanse", true)
		await _loom(out, main.regions.scene, true)
		Game.delete_save()
		get_tree().quit()
		return
	if args.size() > 1 and args[1] == "milestone_d":
		await _milestone_d(out)
		Game.delete_save()
		get_tree().quit()
		return
	if args.size() > 1 and args[1] == "rewards":
		await _rewards(out)
		Game.delete_save()
		get_tree().quit()
		return
	if args.size() > 1 and args[1] == "loom":
		Game.set_flag("shatterlands_open")
		await main.regions.travel("shatterlands", true)
		var shl := main.regions.scene as ShatterlandsThreshold
		var cleft := ShatterlandsThreshold.WEST_CLEFT
		await _shot(out, "loom_cleft_shut", shl.to_global(cleft + Vector3(12.0, 0.3, 4.0)), shl.to_global(cleft + Vector3(-6.0, 3.0, 0.0)))
		Game.set_flag("loom_open")
		await _shot(out, "loom_cleft_open", shl.to_global(cleft + Vector3(12.0, 0.3, 4.0)), shl.to_global(cleft + Vector3(-6.0, 3.0, 0.0)))
		await main.regions.travel("loom_expanse", true)
		await _loom(out, main.regions.scene)
		Game.delete_save()
		get_tree().quit()
		return
	if args.size() > 1 and args[1] == "gillwood":
		Game.set_flag("shatterlands_open")
		Game.set_flag("reyes_talked")
		await main.regions.travel("shatterlands", true)
		var sh := main.regions.scene as ShatterlandsThreshold
		await _shot(out, "shatter_north_split", sh.to_global(ShatterlandsThreshold.NORTH_SPLIT + Vector3(3.0, 0.3, 10.0)), sh.to_global(ShatterlandsThreshold.NORTH_SPLIT + Vector3(0.0, 3.0, -10.0)))
		await main.regions.travel("gillwood", true)
		await _gillwood(out, main.regions.scene)
		Game.delete_save()
		get_tree().quit()
		return
	if args.size() > 1 and args[1] in ["greenhouses", "shatterlands", "nest", "darkhouse"]:
		Game.set_flag("shatterlands_open")
		await main.regions.travel("shatterlands", true)
		if args[1] in ["nest", "darkhouse"]:
			if args[1] == "nest":
				await _nest(out, main.regions.scene)
			else:
				await _dark_house(out, main.regions.scene)
			Game.delete_save()
			get_tree().quit()
			return
		if args[1] == "shatterlands":
			await _pocket(out, main.regions.scene)
		await _greenhouses(out, main.regions.scene)
		Game.delete_save()
		get_tree().quit()
		return
	# The journal, with a discovery under way.
	Game.find_log("relay_1")
	Game.find_log("relay_2")
	await _frames(5)
	main.journal.open()
	await _frames(5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/journal.png" % out)
	print("shot journal")
	main.journal.close()
	# Ilse's listening post: from Kestrel's side door, from the foot of the walkway, at the hut.
	var post: ListeningPost = main.discoveries.built["listening_post"]
	await _shot(out, "post_far", Vector3(10.0, 0.5, 20.0), post.global_position + Vector3(0.0, 6.0, 0.0))
	await _shot(out, "post_walk", Vector3(ListeningPost.WALK_FROM.x - 6.0, 1.0, ListeningPost.WALK_FROM.y - 8.0), post.global_position + Vector3(0.0, 3.0, 0.0))
	await _shot(out, "post_hut", post.to_global(Vector3(-1.0, 0.5, 3.5)), post.to_global(Vector3(0.6, 1.2, -3.0)))
	# Reyes's drop pod, transmitting, at dusk so the green lamp reads.
	Game.set_flag("post_awake")
	main.set_daylight(1.0)
	var pod: DropPod = main.discoveries.built["drop_pod"]
	await _shot(out, "pod", pod.to_global(Vector3(4.0, 0.5, 9.0)), pod.global_position + Vector3(0.0, 1.0, 0.0))
	main.set_daylight(0.0)
	# The survey depot, outside (shut) and inside (open).
	var depot: SurveyDepot = main.discoveries.built["survey_depot"]
	await _shot(out, "depot_out", depot.to_global(Vector3(-3.0, 0.5, 12.0)), depot.to_global(Vector3(0.0, 1.5, 0.0)))
	Game.set_flag("depot_open")
	depot.open_door()
	await _shot(out, "depot_in", depot.to_global(Vector3(1.0, 0.3, 2.5)), depot.to_global(Vector3(0.0, 1.0, -3.0)))
	var gate: Node3D = main.regions.gates["shatterlands"]
	# The gate, shut, then open, from out on the basin floor.
	await _shot(out, "gate_shut", gate.to_global(Vector3(-3.0, 0.5, 16.0)), gate.to_global(Vector3(0.0, 5.0, -3.0)))
	Game.set_flag("shatterlands_open")
	await _shot(out, "gate_open", gate.to_global(Vector3(-3.0, 0.5, 16.0)), gate.to_global(Vector3(0.0, 5.0, -3.0)))
	await main.regions.travel("shatterlands", true)
	var r: RegionScene = main.regions.scene
	await _pocket(out, r)
	await _greenhouses(out, r)
	Game.delete_save()
	get_tree().quit()


func _pocket(out: String, r: RegionScene) -> void:
	# A drifter, held still for its portrait.
	var d: Drifter = main.spawn_enemy("drifter", r.to_global(Vector3(-1.5, 2.6, 33.0)), "", r)
	d.set_physics_process(false)
	await _shot(out, "shatter_drifter", r.to_global(Vector3(2.0, 0.3, 39.0)), d.global_position)
	d.queue_free()
	await _shot(out, "shatter_arrival", r.to_global(r.entry), r.to_global(Vector3(-6.0, 8.0, -20.0)))
	await _shot(out, "shatter_wreck", r.to_global(Vector3(4.0, 0.3, 14.0)), r.to_global(Vector3(16.0, 3.0, -10.0)))
	await _shot(out, "shatter_shelves", r.to_global(Vector3(-24.0, 9.3, -38.0)), r.to_global(Vector3(10.0, 2.0, 10.0)))
	var sh := r as ShatterlandsThreshold
	var hull: Node3D = sh.get_node("Marigold")
	await _shot(out, "shatter_marigold_climb", sh.to_global(hull.transform * Vector3(-15.0, 0.0, -16.0)) * Vector3(1, 0, 1) + Vector3(0.0, sh.global_position.y + 0.3, 0.0), sh.to_global(hull.transform * Vector3(-3.0, 4.0, -4.0)))
	await _shot(out, "shatter_marigold_top", sh.locker_pos + Vector3(0.0, 0.3, 0.0), sh.greenhouses.to_global(Vector3(0.0, 3.0, 0.0)))

	await _nest(out, r)


## The pocket's wildlife where it lives, held still: the pack under the wreck's tail lamp with a
## drifter moored over it, as Juno first sees it from the way in.
func _nest(out: String, r: RegionScene) -> void:
	var residents: Array[Enemy] = r.spawn_residents(main)
	await _frames(20)
	for e in residents:
		e.set_physics_process(false)
	var nest := r.to_global(ShatterlandsThreshold.NEST)
	await _shot(out, "shatter_nest", r.to_global(Vector3(11.0, 0.3, 9.0)), nest + Vector3(0.0, 1.4, 0.0))
	await _shot(out, "shatter_nest_close", r.to_global(Vector3(19.0, 0.3, 11.0)), nest + Vector3(0.0, 1.2, 0.0))
	for e in residents:
		e.queue_free()
	await _frames(2)


## Voss's greenhouses: from the shelves' foot across the pocket, and at the gate.
func _greenhouses(out: String, r: RegionScene) -> void:
	var gh: Greenhouses = (r as ShatterlandsThreshold).greenhouses
	await _shot(out, "greenhouses_far", r.to_global(Vector3(2.0, 0.3, -20.0)), gh.to_global(Vector3(0.0, 3.0, 0.0)))
	await _shot(out, "greenhouses_gate", gh.gate_pos + Vector3(-3.0, 0.3, 9.0), gh.gate_pos + Vector3(0.0, 2.5, -6.0))
	# With the nest cleared: the gate open, Reyes inside it, and the walk-in glasshouse.
	Game.set_flag("met_reyes")
	Game.set_flag("nest_cleared")
	Game.set_flag("greenhouse_open")
	gh._sync_gate(false)
	await _shot(out, "greenhouses_open", gh.gate_pos + Vector3(-2.5, 0.3, -6.5), gh.reyes.global_position + Vector3(0.0, 1.4, 0.0))
	await _shot(out, "greenhouses_camp", gh.to_global(Greenhouses.HEATER + Vector3(5.0, 0.3, -4.0)), gh.to_global(Greenhouses.HEATER + Vector3(0.0, 1.0, 0.5)))
	await _shot(out, "greenhouses_lookout", gh.to_global(Greenhouses.LOOKOUT + Vector3(5.0, -1.3, 3.5)), gh.to_global(Greenhouses.LOOKOUT + Vector3(0.0, 1.0, 0.0)))
	await _shot(out, "greenhouses_inside", gh.house_inside + Vector3(0.0, 0.3, 5.0), gh.house_inside + Vector3(0.0, 1.2, -6.0))
	await _dark_house(out, r)


## Teo's favour: the ramps up the shelves, Voss's cache at the top, and the east glasshouse
## before and after its lamp cell goes in.
func _dark_house(out: String, r: RegionScene) -> void:
	var sh := r as ShatterlandsThreshold
	var gh := sh.greenhouses
	Game.set_flag("greenhouse_open")
	gh._sync_gate(false)
	await _shot(out, "shatter_ramps", r.to_global(Vector3(-7.0, 0.3, 0.5)), r.to_global(Vector3(-17.0, 1.5, -6.0)))
	await _shot(out, "shatter_cache", sh.cache_pos + Vector3(2.0, 0.3, 3.0), r.to_global(ShatterlandsThreshold.CELL_CACHE + Vector3(0.0, 0.6, 0.0)))
	var from := gh.to_global(Vector3(4.5, 0.3, 8.8))
	var east := gh.to_global(Vector3(8.0, 2.5, -3.0))
	await _shot(out, "greenhouses_east_dark", from, east)
	Game.set_flag("lamp_cell_fitted")
	gh._sync_east(false)
	await _shot(out, "greenhouses_east_lit", from, east)


## The Gillwood: the way in, the forest, Ferro-9's two halves, and the salvage before and after.
func _gillwood(out: String, r: RegionScene) -> void:
	var gw := r as Gillwood
	var wreck := gw.to_global(Gillwood.WRECK)
	await _shot(out, "gillwood_arrival", gw.entry_global(), gw.to_global(Vector3(0.0, 6.0, 20.0)))
	await _shot(out, "gillwood_forest", gw.to_global(Vector3(-24.0, 0.3, 4.0)), gw.to_global(Vector3(-40.0, 4.0, -20.0)))
	await _shot(out, "gillwood_ferro", wreck + Vector3(-6.0, 0.3, 18.0), wreck + Vector3(4.0, 2.0, 2.0))
	await _shot(out, "gillwood_canopy", gw.canopy_pos + Vector3(-3.0, 0.3, 2.0), gw.canopy.global_position)
	await _shot(out, "gillwood_strut", gw.strut_pos + Vector3(-4.0, 0.3, 1.0), gw.strut.global_position)
	# A veilwing hanging at its roost, and one with its wings flared, held still.
	var vw_at := gw.to_global(Vector3(-6.0, 3.2, 40.0))
	var flyers: Array = [main.spawn_enemy("veilwing", vw_at, "", gw), main.spawn_enemy("veilwing", vw_at + Vector3(2.2, -0.6, 1.5), "", gw)]
	await _frames(5)
	for v in flyers:
		v.set_physics_process(false)
	flyers[1]._wings[0].rotation.z = -0.7
	flyers[1]._wings[1].rotation.z = 0.7
	flyers[1]._gill_mat.emission_energy_multiplier = 4.0
	await _shot(out, "gillwood_veilwing", vw_at + Vector3(1.0, -2.9, 6.0), vw_at + Vector3(1.0, -0.4, 0.0))
	for v in flyers:
		v.queue_free()
	await _shot(out, "gillwood_locker", gw.locker_pos + Vector3(2.5, 0.3, 3.0), gw.to_global(Gillwood.LOCKER + Vector3(0.0, 0.6, 0.0)))
	gw.free_canopy()
	gw.free_strut()
	await get_tree().create_timer(1.5).timeout
	await _shot(out, "gillwood_salvaged", wreck + Vector3(-9.0, 0.3, 6.0), wreck + Vector3(2.0, 1.0, 2.0))


## Milestone C: the first pocket of the Loom Expanse and its three creatures, held still.
func _loom(out: String, r: RegionScene, creatures_only := false) -> void:
	var lx := r as LoomExpanse
	var at := func(p: Vector3) -> Vector3: return lx.to_global(p)
	await _shot(out, "loom_arrival", lx.entry_global(), at.call(Vector3(0.0, 8.0, 20.0)))
	if creatures_only:
		await _loom_creatures(out, lx)
		return
	await _shot(out, "loom_weave", at.call(Vector3(-20.0, 0.3, 30.0)), at.call(Vector3(-32.0, 1.0, 8.0)))
	# A ridge mid-swell.
	var ridge: LoomRidge = lx.ridges[0]
	ridge.front = ridge.length() * 0.55
	ridge._heave()
	ridge.set_physics_process(false)
	await _shot(out, "loom_ridge_swell", at.call(Vector3(-22.0, 0.3, 20.0)), at.call(Vector3(-28.0, 0.5, 12.0)))
	ridge.set_physics_process(true)
	await _shot(out, "loom_spindles", at.call(Vector3(23.0, 0.3, 32.0)), at.call(Vector3(28.0, 3.0, 0.0)))
	await _shot(out, "loom_crown", at.call(LoomExpanse.OVERLOOK + Vector3(0.0, 0.3, 6.0)), at.call(LoomExpanse.CROWN + Vector3(0.0, 60.0, 0.0)))
	await _shot(out, "loom_bowl", at.call(Vector3(18.0, 0.3, -38.0)), at.call(Vector3(-8.0, 1.0, -58.0)))
	await _shot(out, "loom_locker", at.call(LoomExpanse.LOCKER + Vector3(3.0, 0.3, 4.0)), at.call(LoomExpanse.LOCKER + Vector3(0.0, 0.6, 0.0)))
	await _shot(out, "loom_marker", at.call(LoomExpanse.MARKER + Vector3(-4.0, 0.3, 4.0)), at.call(LoomExpanse.MARKER + Vector3(0.0, 1.2, 0.0)))
	await _shot(out, "loom_tunnel", at.call(Vector3(0.0, 0.3, 32.0)), at.call(Vector3(0.0, 2.0, 20.0)))
	await _loom_creatures(out, lx)


func _loom_creatures(out: String, lx: LoomExpanse) -> void:
	var at := func(p: Vector3) -> Vector3: return lx.to_global(p)
	# The creatures: a diver surfaced with its gills open, a pinweaver anchored with a thread
	# strung, a chord singer drawing breath.
	var d := main.spawn_enemy("ridge_diver", at.call(Vector3(-22.0, 0.0, 2.0)), "", lx) as RidgeDiver
	await _frames(3)
	d._erupt()
	await _frames(15)
	d.set_physics_process(false)
	await _shot(out, "loom_diver", at.call(Vector3(-22.0, 0.3, 7.5)), d.global_position + Vector3(0.0, 1.4, 0.0))
	d.queue_free()
	var pw := main.spawn_enemy("pinweaver", at.call(Vector3(23.0, 0.0, 10.0)), "", lx) as Pinweaver
	await _frames(3)
	pw._pair = [at.call(Vector3(19.0, 0.45, 8.0)), at.call(Vector3(27.0, 0.45, 15.0))]
	pw._start_spool()
	pw._pending.grown = 1.0
	pw._pending.live = true
	pw._pending.layout()
	pw.state = Pinweaver.State.ANCHOR
	pw.set_physics_process(false)
	await _shot(out, "loom_pinweaver", at.call(Vector3(21.0, 0.3, 18.0)), pw.global_position + Vector3(0.0, 0.8, 0.0))
	pw.queue_free()
	var s := main.spawn_enemy("chord_singer", at.call(LoomExpanse.PATCHES[1]), "", lx) as ChordSinger
	await _frames(3)
	s.state = ChordSinger.State.INHALE
	s._membrane_mat.emission_energy_multiplier = 4.0
	s.set_physics_process(false)
	await _shot(out, "loom_singer", at.call(LoomExpanse.PATCHES[1] + Vector3(4.0, 0.3, 9.0)), s.global_position + Vector3(0.0, 2.6, 0.0))
	s.queue_free()


## The pack rewards: the field beacon planted on the basin, the drone station and drone, Brandt's
## trail in the Gillwood.
func _rewards(out: String) -> void:
	var k: Kestrel = main.kestrel
	for id in ["aux_power", "cooling", "canopy", "landing_gear", "wing"]:
		Game.set_repaired(id, true)
		k.set_repaired(id, true)
	await _frames(30)
	var spot: Vector3 = main.SPAWN + Vector3(22.0, 0.0, 30.0)
	spot.y = main.site.height_at(spot.x, spot.z) + 0.3
	main.player.revive(spot, false)
	await _frames(20)
	main.beacon.place()
	await _shot(out, "reward_beacon", spot + Vector3(-4.0, 0.0, 6.0), spot + Vector3(0.0, 2.0, 0.0))
	var station: Vector3 = k.to_global(k.plan(main.DRONE_STATION.x, 0.0, main.DRONE_STATION.z))
	await _shot(out, "reward_station", k.to_global(k.plan(25.5, 0.3, 13.6)), station + Vector3(0.0, 1.0, 0.0))
	Game.set_flag("drone_out", true)
	main.player.revive(spot + Vector3(3.0, 0.0, -3.0), false)
	await _frames(60)
	await _shot(out, "reward_drone", spot + Vector3(3.0, 0.0, 1.0), spot + Vector3(3.0, 1.6, -4.0))
	Game.set_flag("shatterlands_open")
	Game.set_flag("reyes_talked")
	Game.set_flag("reached_gillwood")
	await main.regions.travel("gillwood", true)
	var gw := main.regions.scene as Gillwood
	await _shot(out, "reward_trail", gw.to_global(gw.trail_points[1] + Vector3(-3.0, 0.3, 6.0)), gw.to_global(gw.stash_points[0] + Vector3(0.0, 0.6, 0.0)))
	main.map_panel.main = main
	main.map_panel.open()
	await _frames(10)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/reward_map.png" % out)
	main.map_panel.close()


## Milestone B: the canopy rescue and the gear escort in the Gillwood, the wing chase in the pocket.
func _missions(out: String) -> void:
	Game.set_flag("shatterlands_open")
	Game.set_flag("reyes_talked")
	Game.set_flag("found_ferro9")
	await main.regions.travel("gillwood", true)
	var gw := main.regions.scene as Gillwood
	var fc := gw.ferro
	var wreck := gw.to_global(Gillwood.WRECK)
	await _shot(out, "b1_ferro_hanging", wreck + Vector3(-14.0, 0.3, 14.0), wreck + Vector3(0.0, 3.5, -2.0))
	fc.locked = [true, true, false]
	fc._sync()
	await _shot(out, "b1_stay_lines", gw.ramp_top + Vector3(0.0, 0.3, 0.0), gw.canopy.global_position)
	Game.set_flag("ferro_lines")
	fc.locked = [true, true, true]
	fc.start_winch()
	await _shot(out, "b1_winch", fc.console_pos + Vector3(4.0, 0.3, 8.0), (fc.console_pos + fc.pad_pos) * 0.5 + Vector3.UP * 1.5)
	fc.wound = FerroCanopy.WINCH_TIME
	await get_tree().create_timer(2.0).timeout
	var ge := gw.gear
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await _shot(out, "b2_drone", ge.drone.global_position + Vector3(-4.0, 0.3, 5.0), ge.drone.global_position + Vector3.UP * 0.6)
	await _shot(out, "b2_ridge", gw.to_global(Vector3(18.0, 0.3, 0.0)), gw.to_global(GearEscort.RIDGE + Vector3(0.0, 2.0, 0.0)))
	await _shot(out, "b2_tunnel", gw.to_global(Vector3(42.0, 0.3, 0.0)), gw.to_global(Vector3(42.0, 1.2, 16.0)))
	await _shot(out, "b2_hoist", gw.to_global(GearEscort.HOIST + Vector3(-8.0, 0.3, -9.0)), gw.to_global(GearEscort.HOIST + Vector3(0.0, 3.0, 0.0)))
	Game.set_flag("ferro_gear")
	await main.regions.travel("shatterlands", true)
	var sh := main.regions.scene as ShatterlandsThreshold
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	var wc := sh.wing
	wc.start()
	wc.leg = 1
	wc.along = 0.3
	wc._place()
	wc.set_process(false)
	await _shot(out, "b3_crags", sh.to_global(Vector3(30.0, 0.3, 0.0)), sh.to_global(Vector3(48.0, 1.0, -16.0)))
	await _shot(out, "b3_robot", wc.robot.global_position + Vector3(-3.0, 1.0, 4.0), wc.robot.global_position + Vector3.UP * 0.8)


## The opening: aboard in orbit, the drift, the wreck, then the trail to the relay.
func _opening(out: String) -> void:
	var op: Opening = main.opening
	var a: Approach = main.regions.scene
	main.set_daylight(0.0)
	await _shot(out, "open_bunk", a._at(Vector3(10.6, 0.1, 13.0)), a._at(Vector3(4.0, 1.6, 13.0)))
	await _shot(out, "open_workshop", a._at(Vector3(12.5, 0.1, 12.0)), a._at(Vector3(18.0, 1.0, 10.0)))
	a.sit()
	await _frames(5)
	main.player.aim_at(a._at(Vector3(-30.0, -6.0, 13.0)))
	await _still(out, "open_seat")
	for i in 4:
		a.trace()
	a.override()
	await get_tree().create_timer(2.5).timeout
	main.player.aim_at(a._at(Vector3(-30.0, -4.0, 13.0)))
	await _still(out, "open_drift")
	await op._on_fell(2)
	var waited := 0
	while not main.intro_playing and waited < 120:
		await _frames(1)
		waited += 1
	if main.intro_playing:
		main.end_intro()
	await _frames(10)
	main.player.aim_at(op._ship(Opening.MEDSEAL))
	await _still(out, "open_wake")
	main.player.seated = false
	main.player.crouching = false
	op._wake_lock = false
	Game.set_flag("opening", Opening.Beat.TRAIL)
	await _shot(out, "open_door", op._ship(Vector3(12.9, -1.0, 23.0)), op._ship(Vector3(12.9, 1.0, 17.0)))
	await _shot(out, "open_scar", op._ground(Opening.SCAR_AT + Vector2(-4.0, 6.0), 0.5), op._ground(Opening.SCAR_AT, 0.0))
	await _shot(out, "open_trail", op._ground(Vector2(-6.0, 9.0), 0.5), op._ground(Opening.LEDGE_AT, 1.5))
	Game.set_flag("bridge_down")
	await get_tree().create_timer(1.6).timeout
	await _shot(out, "open_bridge", op._ground(Opening.LEDGE_AT + Vector2(6.0, 3.5), 0.5), op._ground(Opening.LEDGE_AT + Vector2(0.0, 3.5), 2.0))
	Game.set_flag("pod_open")
	await get_tree().create_timer(1.0).timeout
	await _shot(out, "open_pod", op._ground(Opening.SURVEY_AT + Vector2(2.5, 6.0), 0.5), op._ground(Opening.SURVEY_AT, 1.0))
	await _shot(out, "open_gully", op._ground(Opening.GULLY_AT + Vector2(5.0, 4.0), 0.5), op._ground(Opening.GULLY_AT, 0.5))
	var yard: Vector3 = main.sites["aux_power"].global_position
	await _shot(out, "open_yard", op._ground(Vector2(-46.0, 49.5), 0.5), yard + Vector3(0.0, 2.0, 0.0))


## A frame without moving Juno (she's seated, or posed already).
## Milestone D: the Long Patience's hall and its guardian, the Tuning Crown's resonator bay and the
## Cantor, and the departure crisis's tethers on Kestrel.
func _milestone_d(out: String) -> void:
	for id in Kestrel.REPAIR_ORDER:
		main.kestrel.set_repaired(id, true)
	main.siege.pending = -1
	main.finale.start()
	main.finale.spool = Finale.SPOOL_TIME * 0.31
	await _frames(5)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	var k: Kestrel = main.kestrel
	for v in [["d_tethers", Vector3(12.0, 0.0, -8.0), Vector3(19.0, 1.0, 5.0)], ["d_tether_nose", Vector3(-7.0, 0.0, 19.0), Vector3(2.4, 1.0, 13.0)]]:
		var at: Vector3 = k.to_global(k.plan(v[1].x, v[1].y, v[1].z))
		at.y = main.site.height_at(at.x, at.z) + 0.3
		await _shot(out, v[0], at, k.to_global(k.plan(v[2].x, v[2].y, v[2].z)))
	main.siege.damage_hull(ShipSiege.MAX_HULL)
	await _frames(5)
	for f in ["shatterlands_open", "loom_open", "patience_open", "crown_open"]:
		Game.set_flag(f)
	await main.regions.travel("long_patience", true)
	var lp := main.regions.scene as LongPatience
	lp.adopt_guardian(main.spawn_enemy("guardian", lp.to_global(Vector3(0.0, 0.3, -14.0)), "", lp) as PatienceGuardian)
	await _shot(out, "d_patience_hall", lp.to_global(Vector3(2.0, 0.3, 24.0)), lp.to_global(Vector3(-1.0, 4.0, -20.0)))
	await _shot(out, "d_patience_guardian", lp.to_global(Vector3(3.0, 0.3, -4.0)), lp.to_global(Vector3(0.0, 2.0, -14.0)))
	await main.regions.travel("tuning_crown", true)
	var tc := main.regions.scene as TuningCrown
	await _shot(out, "d_crown_bay", tc.to_global(Vector3(-30.0, 0.3, 36.0)), tc.to_global(TuningCrown.RESONATORS[0] + Vector3(0.0, 3.0, 0.0)))
	Game.set_flag("crown_arena")
	tc.wake_cantor(main)
	await _shot(out, "d_cantor", tc.to_global(Vector3(4.0, 0.3, -30.0)), tc.to_global(TuningCrown.ARENA + Vector3(0.0, 6.0, 0.0)))


func _still(out: String, name: String) -> void:
	await _frames(30)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _shot(out: String, name: String, at: Vector3, look: Vector3) -> void:
	main.player.revive(at, false)
	var flat := look - at
	main.player.face(atan2(-flat.x, -flat.z))
	main.player.aim_at(look)
	await _frames(40)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
