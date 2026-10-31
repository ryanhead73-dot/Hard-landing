extends Node3D
## Dev utility: renders Kestrel alone from four sides for model review. Needs a real renderer:
##   xvfb-run godot --path . --rendering-driver vulkan res://tests/kestrel_shots.tscn -- <out_dir>

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://kshots"
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9aa4a8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a9094")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	add_child(ground)
	var k: Node3D = load("res://scripts/kestrel.gd").new()
	add_child(k)
	k.position.y = 1.4
	for id in Kestrel.REPAIR_ORDER:
		k.set_repaired(id, OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "fixed")
	var cam := Camera3D.new()
	cam.fov = 50
	add_child(cam)
	cam.current = true
	var views := {"k_front": Vector3(-30, 6, 10), "k_side": Vector3(4, 5, 32), "k_aft": Vector3(32, 7, -14), "k_top": Vector3(-14, 22, -18)}
	for name in views:
		cam.position = views[name]
		cam.look_at(Vector3(0, 2.5, 0))
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
		print("shot ", name)
	get_tree().quit()
