extends Node3D
## Dev utility: frames one model and renders it at chosen moments of its clips, for reviewing a
## creature while it is being modelled and animated. Needs a real renderer:
##   xvfb-run godot --path . --rendering-driver opengl3 res://tests/rig_shots.tscn -- <out_dir> <model> [clip:0.5,clip:0.0 ...] [dark]
## With no clips given: the rest pose from four sides.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var model: String = args[1]
	var shots: Array = Array(args[2].split(",")) if args.size() > 2 and args[2] != "" else []
	var dark := args.size() > 3
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(640, 640)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1c2226") if dark else Color("66707a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("9aa4ad")
	env.environment.ambient_light_energy = 0.25 if dark else 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 150, 0)
	sun.light_energy = 0.5 if dark else 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var inst := Rig.spawn(model, self)
	var box := AABB()
	var first := true
	for mi in Rig.meshes(inst):
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("3d4248")
	floor_mesh.material_override = fm
	floor_mesh.position.y = box.position.y - 0.01
	add_child(floor_mesh)
	var player := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		print("clips: ", player.get_animation_list())
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.make_current()
	var c := box.get_center()
	var dist := maxf(box.size.length() * 0.5, 0.4) / tan(deg_to_rad(15.0)) * 1.08
	var views := {"front": Vector3(-0.7, 0.3, -1.0), "side": Vector3(-1.0, 0.12, 0.05), "back": Vector3(0.8, 0.45, 1.0), "top": Vector3(0.05, 1.0, -0.35), "low": Vector3(-0.6, -0.25, -1.0)}
	if shots.is_empty():
		for v in ["front", "side", "back", "top"]:
			cam.look_at_from_position(c + (views[v] as Vector3).normalized() * dist, c)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_rest_%s.png" % [out, model, v])
	var i := 0
	for s in shots:
		var bits: PackedStringArray = (s as String).split(":")
		var clip := bits[0]
		var frac := float(bits[1]) if bits.size() > 1 else 0.5
		var view: String = bits[2] if bits.size() > 2 else "front"
		if player and player.has_animation(clip):
			player.play(clip)
			player.seek(player.get_animation(clip).length * frac, true)
			player.pause()
		cam.look_at_from_position(c + (views[view] as Vector3).normalized() * dist, c)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%02d_%s_%d.png" % [out, model, i, clip, int(frac * 100)])
		i += 1
	get_tree().quit()
