extends Node3D
## Dev utility: a lineup of every creature, Juno and the survivors, one framed shot each from the
## front three-quarter and one from the side, for reviewing models. Needs a real renderer:
##   xvfb-run godot --path . --rendering-driver opengl3 res://tests/creature_shots.tscn -- <out_dir> [names]

const CREATURES := ["scuttler", "spitter", "ram", "warden", "lurker", "skimmer", "drifter",
	"veilwing", "ridge_diver", "pinweaver", "chord_singer", "patience_guardian", "cantor",
	"juno", "reyes", "okafor", "brandt", "haddad", "teo"]
const CLASSES := {"scuttler": "Scuttler", "spitter": "Spitter", "ram": "Ram", "warden": "Warden",
	"lurker": "Lurker", "skimmer": "Skimmer", "drifter": "Drifter", "veilwing": "Veilwing",
	"ridge_diver": "RidgeDiver", "pinweaver": "Pinweaver", "chord_singer": "ChordSinger",
	"patience_guardian": "PatienceGuardian", "cantor": "Cantor"}

## The clip each model is shown in.
const SHOW := {"veilwing": "climb", "ridge_diver": "surfaced", "skimmer": "idle"}
## The survivors (blender/build_people.py), each in the loop they hold at the greenhouses.
const PEOPLE := {"reyes": "at_ease", "okafor": "idle", "brandt": "crouch", "haddad": "watch", "teo": "crouch"}

var out := "user://creature_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else out
	var names: Array = Array(args[1].split(",")) if args.size() > 1 else CREATURES
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(720, 720)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("5c6670")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("9aa4ad")
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("3d4248")
	floor_mesh.material_override = fm
	floor_body.add_child(floor_mesh)
	add_child(floor_body)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	for n in names:
		var subject := _spawn(n)
		for i in 40:
			await get_tree().physics_frame
		var box_w := _bounds(subject)
		var c := box_w.get_center()
		var r := maxf(box_w.size.length() * 0.5, 0.6)
		var dist := r / tan(deg_to_rad(cam.fov * 0.5)) * 1.05
		for view in [["front", Vector3(-0.75, 0.35, -1.0)], ["side", Vector3(-1.0, 0.15, 0.0)]]:
			var d: Vector3 = (view[1] as Vector3).normalized()
			cam.look_at_from_position(c + d * dist, c)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, n, view[0]])
		print("shot ", n, " size ", box_w.size)
		subject.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _spawn(n: String) -> Node3D:
	if CLASSES.has(n):
		# The model on its own, holding a pose that shows it off (in the game a ridge diver starts
		# underground and a veilwing hangs at its roost).
		var holder3 := Node3D.new()
		add_child(holder3)
		var model := Rig.spawn(n, holder3)
		var clips := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var clip: String = SHOW.get(n, "idle")
		if clips and clips.has_animation(clip):
			clips.play(clip)
			clips.seek(clips.current_animation_length * 0.3, true)
			clips.pause()
		return holder3
	var holder := Node3D.new()
	add_child(holder)
	if PEOPLE.has(n):
		var person := Rig.spawn("person_" + n, holder)
		var loops := person.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if loops:
			loops.play(PEOPLE[n])
			loops.seek(loops.current_animation_length * 0.3, true)
			loops.pause()
		return holder
	var rig := Rig.spawn("juno_rigged", holder)
	var mount := Rig.attach(rig, "WeaponMount")
	if mount and n == "juno":
		Rig.spawn("rifle", mount).position = Vector3(0.0, -0.01, 0.1)
	var player := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player and player.has_animation("idle"):
		player.play("idle")
	return holder


func _bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in Rig.meshes(root):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box
