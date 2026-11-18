extends Node
## Dev utility: a ring of views across the Kettle from beside Kestrel, for checking that the
## basin's landmarks read from home. Needs a real renderer:
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/kettle_shots.tscn -- <out_dir> [from_x from_z | landmarks]

var main: Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shots"
	var from := Vector3(14.0, 0.5, 14.0)
	if args.size() >= 3 and args[1] != "landmarks":
		from = Vector3(float(args[1]), 0.5, float(args[2]))
	DirAccess.make_dir_recursive_absolute(out)
	Game.window_mode = 0
	Game.apply_settings()
	Game.save_path = "user://kettle_shots_save.json"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	await _frames(20)
	for s in get_tree().get_nodes_in_group("enemies"):
		s.queue_free()
	main.day_cycle = false
	main.set_daylight(0.0)
	from.y = main.site.height_at(from.x, from.z) + 0.5
	var names := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
	# `-- <out_dir> landmarks` skips the ring and renders only the close-ups.
	var ring := not (args.size() == 2 and args[1] == "landmarks")
	for i in (8 if ring else 0):
		var a := i * TAU / 8.0
		# North is -Z.
		var look := from + Vector3(sin(a), 0.0, -cos(a)) * 120.0 + Vector3(0.0, 14.0, 0.0)
		await _shot(out, "kettle_" + names[i], from, look)
	# The landmarks up close: the Split from the flats below it, the Chimney mid-burst.
	var lm: Landmarks = main.landmarks
	var gate_at: Vector3 = lm.split.global_position
	var near := gate_at + (Vector3.ZERO - gate_at).normalized() * 45.0
	near.y = main.site.height_at(near.x, near.z) + 0.5
	await _shot(out, "split", near, gate_at + Vector3(0.0, 22.0, 0.0))
	var g := lm.chimney
	var by := g.global_position + Vector3(-14.0, 0.0, 10.0)
	by.y = main.site.height_at(by.x, by.z) + 0.5
	g.set_time(Geyser.IDLE + Geyser.RUMBLE + 0.8)
	await _shot(out, "chimney", by, g.global_position + Vector3(0.0, 7.0, 0.0))
	get_tree().quit()


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
