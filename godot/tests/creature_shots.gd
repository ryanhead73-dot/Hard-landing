extends "res://tests/test_base.gd"
## Dev utility: a lineup of every creature (and Juno) for review, frozen mid-pose, in the Kettle.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/creature_shots.tscn -- <out_dir>

const KINDS := [["scuttler", "spitter", "ram", "lurker", "skimmer", "drifter", "warden"],
	["veilwing", "ridge_diver", "pinweaver", "chord_singer", "guardian", "cantor"]]


func _name() -> String:
	return "CREATURE SHOTS"


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	await _frames(20)
	_clear_enemies()
	var base := Vector3(-30.0, 0.0, 30.0)
	player.global_position = base + Vector3(0.0, 0.5, -30.0)
	main.set_daylight(0.5) if main.has_method("set_daylight") else null
	var cam := Camera3D.new()
	cam.fov = 40.0
	main.add_child(cam)
	for row in KINDS.size():
		var spacing := 5.0 if row == 0 else 7.0
		var es: Array = []
		for i in KINDS[row].size():
			var x := (i - (KINDS[row].size() - 1) * 0.5) * spacing
			var at := base + Vector3(x, 0.0, 0.0)
			at.y = main.site.height_at(at.x, at.z) + 0.6
			var e: Enemy = main.spawn_enemy(KINDS[row][i], at)
			e.target = null
			es.append(e)
		await _frames(30)
		for e in es:
			e.set_physics_process(false)
			e.rotation.y = PI * 0.15
		cam.make_current()
		var width := spacing * KINDS[row].size()
		cam.look_at_from_position(base + Vector3(0.0, 4.0, width * 0.75), base + Vector3(0.0, 1.5, 0.0))
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/lineup_%d.png" % [out, row])
		# Close-ups, two at a time.
		for i in range(0, es.size(), 2):
			var mid: Vector3 = es[i].global_position
			if i + 1 < es.size():
				mid = (mid + es[i + 1].global_position) * 0.5
			cam.look_at_from_position(mid + Vector3(0.0, 2.2, 8.0), mid + Vector3(0.0, 1.2, 0.0))
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/close_%d_%d.png" % [out, row, i])
		for e in es:
			e.queue_free()
		await _frames(5)
	finished = true
