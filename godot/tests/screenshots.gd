extends Node
## Dev utility: renders a few views of the game to PNGs for review. Needs a real renderer:
##   xvfb-run godot --path . --rendering-driver opengl3 res://tests/screenshots.tscn -- <out_dir>
## Each shot is [name, player position, camera yaw, camera pitch, repairs to apply].

var main: Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	await _frames(20)
	for s in get_tree().get_nodes_in_group("enemies"):
		s.queue_free()
	var only := args[1].split(",") if args.size() > 1 else PackedStringArray()
	for shot in _shots():
		if not only.is_empty() and not shot[0] in only:
			continue
		main.day_cycle = false
		main.set_daylight(1.0 if String(shot[0]).ends_with("_dusk") else 0.0)
		if String(shot[0]).ends_with("_storm"):
			main.weather.start_storm(true)
		elif main.weather.storm > 0.0:
			main.weather.clear_storm(true)
		if String(shot[0]).ends_with("_lit"):
			main.kestrel.set_repaired("aux_power", true)
		if shot[1] == "kestrel":
			var k: Kestrel = main.kestrel
			shot = [shot[0], "", k.to_global(k.plan(shot[2].x, shot[2].y, shot[2].z)), k.to_global(k.plan(shot[3].x, shot[3].y, shot[3].z))]
		if shot[1] == "pool" and shot[0] == "lurker_pool":
			var lp: Array = main.wildlife.lurker_pools[0]
			shot = [shot[0], "", lp[0] + Vector3(lp[1] + 5.0, 0.8, 3.0), lp[0]]
		elif shot[1] == "cache":
			var c: Node3D = main.wildlife.caches[2]
			var back := 40.0 if shot[0] == "cache_far" else 6.0
			var from: Vector3 = c.global_position + Vector3(back * 0.8, 0.0, back * 0.6)
			from.y = main.site.height_at(from.x, from.z) + 0.5
			shot = [shot[0], "", from, c.global_position + Vector3.UP * (2.0 if back > 10.0 else 0.4)]
		elif shot[1] == "pool":
			var pool: Array = main.site.pools[1]
			shot = [shot[0], "", pool[0] + Vector3(pool[1] + 6.0, 0.5, 4.0), pool[0]]
		var site: Node3D = main.sites.get(shot[1])
		var at: Vector3 = site.to_global(shot[2]) if site else shot[2]
		var look: Vector3 = site.to_global(shot[3]) if site else shot[3]
		main.player.revive(at)
		var flat := look - at
		main.player.face(atan2(-flat.x, -flat.z))
		main.player.aim_at(look)
		var cam: Camera3D = null
		if String(shot[0]).begins_with("juno"):
			# A portrait: a free camera ahead of Juno, looking back at her.
			cam = Camera3D.new()
			cam.fov = 40.0
			main.add_child(cam)
			var front: Vector3 = Vector3(flat.x, 0.0, flat.z).normalized()
			var side: Vector3 = front.cross(Vector3.UP)
			var target := at + Vector3(0.0, 1.05, 0.0)
			cam.look_at_from_position(target + front * 3.0 + side * 1.2 + Vector3(0.0, 0.3, 0.0), target)
			cam.make_current()
		var beasts: Array = []
		if shot[0] == "creatures":
			# A line-up a few metres ahead, frozen once they've settled into their idle pose.
			var fwd: Vector3 = Vector3(flat.x, 0.0, flat.z).normalized()
			var right: Vector3 = fwd.cross(Vector3.UP)
			for i in 3:
				var kind: String = ["scuttler", "spitter", "ram"][i]
				var e: Node3D = main.spawn_enemy(kind, at + fwd * (6.0 + i) + right * (float(i) - 1.0) * 2.6)
				e.look_at(at, Vector3.UP)
				beasts.append(e)
		if String(shot[0]).begins_with("lurker"):
			# On land mid-gape, or (lurker_pool) waiting in a pool with just its eyes up.
			var fwd: Vector3 = Vector3(flat.x, 0.0, flat.z).normalized()
			var in_pool: bool = shot[0] == "lurker_pool"
			var spot: Vector3 = look if in_pool else at + fwd * 4.5
			var lk: Lurker = main.spawn_enemy("lurker", spot)
			lk.look_at(Vector3(at.x, lk.global_position.y, at.z), Vector3.UP)
			if not in_pool:
				lk.state = Lurker.State.WINDUP
				lk._timer = 99.0
				lk.target = null
			await _frames(50)
			beasts.append(lk)
			# A close three-quarter view of it.
			cam = Camera3D.new()
			cam.fov = 45.0
			main.add_child(cam)
			var side: Vector3 = fwd.cross(Vector3.UP)
			var c: Vector3 = lk.global_position + Vector3.UP * 0.4
			cam.look_at_from_position(c - fwd * 3.2 + side * 2.4 + Vector3.UP * 1.3, c)
			cam.make_current()
		if shot[0] == "map":
			for c in main.wildlife.caches:
				if c.index % 2 == 0:
					Game.caches_seen.append(c.index)
			main.wildlife.caches[2].set_opened()
			main.map_panel.open()
		if shot[0] == "thief":
			# The fuse thief caught in the open, loot glowing, beside a burrow.
			var t := FuseThief.new()
			t.thief_name = "FUSE THIEF"
			main.spawn_enemy_node(t, main.sites["landing_gear"].to_global(Vector3(-11.5, 0.0, 4.5)))
			main.hud.show_boss(t)
			await _frames(2)
			t.look_at(at, Vector3.UP)
			t.rotate_y(PI * 0.6)
			beasts.append(t)
		if String(shot[0]).begins_with("skimmer"):
			# Hanging before the dive, belly lit, or (skimmer_dive) stooping with wings swept.
			var fwd: Vector3 = Vector3(flat.x, 0.0, flat.z).normalized()
			var sk: Skimmer = main.spawn_enemy("skimmer", at + fwd * 5.0)
			sk.target = null
			await _frames(2)
			sk.global_position.y += 2.6
			sk.look_at(Vector3(at.x, sk.global_position.y, at.z), Vector3.UP)
			if shot[0] == "skimmer_dive":
				sk.state = Skimmer.State.DIVE
				sk._dive_dir = (-fwd + Vector3.DOWN * 0.6).normalized()
				sk.dive_speed = 0.0
			else:
				sk.state = Skimmer.State.WINDUP
			sk._timer = 99.0
			await _frames(40)
			beasts.append(sk)
			cam = Camera3D.new()
			cam.fov = 45.0
			main.add_child(cam)
			var side: Vector3 = fwd.cross(Vector3.UP)
			var c: Vector3 = sk.global_position
			cam.look_at_from_position(c - fwd * 2.6 + side * 1.6 - Vector3.UP * 0.6, c)
			cam.make_current()
		await _frames(2)
		for e in beasts:
			e.process_mode = Node.PROCESS_MODE_DISABLED
		await _frames(40)
		for e in beasts:
			e.process_mode = Node.PROCESS_MODE_DISABLED
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out, shot[0]])
		print("shot ", shot[0])
		if main.map_panel.is_open():
			main.map_panel.close()
		if cam:
			cam.queue_free()
		for e in beasts:
			e.queue_free()
	get_tree().quit()


## [name, site repair id or "" for world space, player position, look-at point].
func _shots() -> Array:
	return [
		["spires", "canopy", Vector3(4.0, 0.3, 22.0), Vector3(0.0, 4.0, -8.0)],
		["spires_top", "canopy", Vector3(2.0, 5.1, -9.5), Vector3(-1.0, 5.5, -14.0)],
		["quarry", "landing_gear", Vector3(3.0, 0.3, 18.0), Vector3(0.0, 2.0, -8.0)],
		["quarry_bay", "landing_gear", Vector3(0.0, 1.4, -3.0), Vector3(0.0, 2.0, -13.0)],
		["crawler", "landing_gear", Vector3(14.0, 0.3, 4.0), Vector3(0.0, 2.5, -9.0)],
		["engine_room", "engine", Vector3(0.5, 0.3, -14.0), Vector3(0.0, 3.0, -26.0)],
		["hauler", "cooling", Vector3(10.0, 0.3, 18.0), Vector3(0.0, 3.0, -6.0)],
		["hauler_hold", "cooling", Vector3(0.0, 1.0, 6.0), Vector3(0.0, 1.6, -10.0)],
		["moss", "wing", Vector3(3.0, 0.3, 16.0), Vector3(-4.0, 1.5, -5.0)],
		["moss_dusk", "wing", Vector3(3.0, 0.3, 16.0), Vector3(-4.0, 1.5, -5.0)],
		["dropship", "wing", Vector3(8.0, 0.3, 2.0), Vector3(-2.0, 1.5, -9.0)],
		["graveyard", "engine", Vector3(3.0, 0.3, 18.0), Vector3(0.0, 3.0, -15.0)],
		["loom", "navigation", Vector3(3.0, 0.3, 16.0), Vector3(0.0, 6.0, -6.0)],
		["ship_aft", "", Vector3(32.0, 0.5, 10.0), Vector3(0.0, 2.0, 0.0)],
		["basin", "", Vector3(-30.0, 0.5, 38.0), Vector3(0.0, 3.0, 0.0)],
		["ship_front", "", Vector3(-30.0, 0.5, -8.0), Vector3(0.0, 2.5, 0.0)],
		["ship_side", "", Vector3(4.0, 0.5, 26.0), Vector3(0.0, 3.0, 0.0)],
		["workshop", "kestrel", Vector3(13.0, 0.3, 14.5), Vector3(22.0, 1.4, 12.0)],
		["workshop_lit", "kestrel", Vector3(13.0, 0.3, 14.5), Vector3(22.0, 1.4, 12.0)],
		["cabin_lit", "kestrel", Vector3(11.0, 0.3, 13.0), Vector3(8.5, 1.2, 10.5)],
		["cockpit", "kestrel", Vector3(7.6, 1.5, 13.0), Vector3(3.6, 2.4, 13.0)],
		["basin_out", "", Vector3(10.0, 0.5, 22.0), Vector3(-50.0, 4.0, 60.0)],
		["pool", "pool", Vector3.ZERO, Vector3.ZERO],
		["basin_dusk", "", Vector3(-30.0, 0.5, 38.0), Vector3(0.0, 3.0, 0.0)],
		["basin_storm", "", Vector3(-30.0, 0.5, 38.0), Vector3(0.0, 3.0, 0.0)],
		["ship_side_storm", "", Vector3(4.0, 0.5, 26.0), Vector3(0.0, 3.0, 0.0)],
		["creatures", "", Vector3(40.0, 0.5, 40.0), Vector3(40.0, 1.0, 30.0)],
		["lurker", "", Vector3(40.0, 0.5, 40.0), Vector3(40.0, 0.6, 30.0)],
		["lurker_pool", "pool", Vector3.ZERO, Vector3.ZERO],
		["cache", "cache", Vector3.ZERO, Vector3.ZERO],
		["map", "", Vector3(30.0, 0.5, -20.0), Vector3(40.0, 1.0, -40.0)],
		["skimmer", "", Vector3(40.0, 0.5, 40.0), Vector3(40.0, 2.0, 30.0)],
		["skimmer_dive", "", Vector3(40.0, 0.5, 40.0), Vector3(40.0, 2.0, 30.0)],
		["cache_far", "cache", Vector3.ZERO, Vector3.ZERO],
		["thief", "landing_gear", Vector3(-6.0, 0.5, 9.0), Vector3(-12.5, 0.6, 4.0)],
		["juno", "", Vector3(-24.0, 0.5, -6.0), Vector3(-30.0, 1.0, -8.0)],
		["relay", "aux_power", Vector3(2.0, 0.5, 16.0), Vector3(0.0, 2.0, -4.0)],
		["relay_near", "aux_power", Vector3(9.0, 0.5, 6.0), Vector3(2.0, 3.0, -6.0)],
		["relay_inside", "aux_power", Vector3(-3.0, 0.5, -3.0), Vector3(2.0, 1.5, -8.0)],
	]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
