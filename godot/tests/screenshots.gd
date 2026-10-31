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
	await _frames(20)
	for s in get_tree().get_nodes_in_group("enemies"):
		s.queue_free()
	var only := args[1].split(",") if args.size() > 1 else PackedStringArray()
	for shot in _shots():
		if not only.is_empty() and not shot[0] in only:
			continue
		main.day_cycle = false
		main.set_daylight(1.0 if String(shot[0]).ends_with("_dusk") else 0.0)
		if shot[1] == "pool":
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
		await _frames(40)
		for e in beasts:
			e.process_mode = Node.PROCESS_MODE_DISABLED
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out, shot[0]])
		print("shot ", shot[0])
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
		["moss", "wing", Vector3(3.0, 0.3, 16.0), Vector3(-4.0, 1.5, -5.0)],
		["graveyard", "engine", Vector3(3.0, 0.3, 18.0), Vector3(0.0, 3.0, -15.0)],
		["loom", "navigation", Vector3(3.0, 0.3, 16.0), Vector3(0.0, 6.0, -6.0)],
		["ship_aft", "", Vector3(32.0, 0.5, 10.0), Vector3(0.0, 2.0, 0.0)],
		["basin", "", Vector3(-30.0, 0.5, 38.0), Vector3(0.0, 3.0, 0.0)],
		["ship_front", "", Vector3(-30.0, 0.5, -8.0), Vector3(0.0, 2.5, 0.0)],
		["ship_side", "", Vector3(4.0, 0.5, 26.0), Vector3(0.0, 3.0, 0.0)],
		["workshop", "", Vector3(-3.0, 1.5, 15.0), Vector3(-3.0, 2.0, 2.0)],
		["basin_out", "", Vector3(10.0, 0.5, 22.0), Vector3(-50.0, 4.0, 60.0)],
		["pool", "pool", Vector3.ZERO, Vector3.ZERO],
		["basin_dusk", "", Vector3(-30.0, 0.5, 38.0), Vector3(0.0, 3.0, 0.0)],
		["creatures", "", Vector3(40.0, 0.5, 40.0), Vector3(40.0, 1.0, 30.0)],
		["juno", "", Vector3(-24.0, 0.5, -6.0), Vector3(-30.0, 1.0, -8.0)],
		["relay", "aux_power", Vector3(2.0, 0.5, 16.0), Vector3(0.0, 2.0, -4.0)],
	]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
