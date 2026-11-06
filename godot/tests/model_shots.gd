extends Node3D
## Dev utility: renders a skinned model's animations to PNGs (front and side, a few moments of
## each clip) for review. Needs a real renderer:
##   xvfb-run godot --path . --rendering-driver vulkan res://tests/model_shots.tscn -- <out_dir> [model] [clips]

var out := "user://model_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else out
	var model: String = args[1] if args.size() > 1 else "juno_rigged"
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("5c6670")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("9aa4ad")
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var inst := (load("res://assets/models/%s.glb" % model) as PackedScene).instantiate()
	add_child(inst)
	var mount := Rig.attach(inst, "WeaponMount")
	if mount:
		Rig.spawn("rifle", mount).position = Vector3(0.0, -0.01, 0.1)
	var player := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var cam := Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	cam.make_current()
	var clips: PackedStringArray = args[2].split(",") if args.size() > 2 else player.get_animation_list()
	print("clips: ", player.get_animation_list())
	for clip in clips:
		var anim := player.get_animation(clip)
		player.play(clip)
		for i in 4:
			var t := anim.length * i / 4.0
			player.seek(t, true)
			for view in [["front", Vector3(1.2, 1.3, -4.0)], ["side", Vector3(4.2, 1.2, 0.0)]]:
				cam.look_at_from_position(view[1], Vector3(0, 0.95, 0))
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/%s_%d_%s.png" % [out, clip, i, view[0]])
	get_tree().quit()
