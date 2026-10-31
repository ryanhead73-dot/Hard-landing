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
	for shot in _shots():
		var site: Node3D = main.sites.get(shot[1])
		var at: Vector3 = site.to_global(shot[2]) if site else shot[2]
		var look: Vector3 = site.to_global(shot[3]) if site else shot[3]
		main.player.revive(at)
		var flat := look - at
		main.player.face(atan2(-flat.x, -flat.z))
		main.player.aim_at(look)
		await _frames(40)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out, shot[0]])
		print("shot ", shot[0])
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
	]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
