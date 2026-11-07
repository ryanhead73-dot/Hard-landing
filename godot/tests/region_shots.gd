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
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	await _frames(20)
	for s in get_tree().get_nodes_in_group("enemies"):
		s.queue_free()
	main.day_cycle = false
	main.set_daylight(0.0)
	# `-- <out_dir> greenhouses` renders only Voss's greenhouses.
	if args.size() > 1 and args[1] == "greenhouses":
		Game.set_flag("shatterlands_open")
		await main.regions.travel("shatterlands", true)
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
	await _shot(out, "shatter_arrival", r.to_global(r.entry), r.to_global(Vector3(-6.0, 8.0, -20.0)))
	await _shot(out, "shatter_wreck", r.to_global(Vector3(4.0, 0.3, 14.0)), r.to_global(Vector3(16.0, 3.0, -10.0)))
	await _shot(out, "shatter_shelves", r.to_global(Vector3(-24.0, 9.3, -38.0)), r.to_global(Vector3(10.0, 2.0, 10.0)))
	await _greenhouses(out, r)
	Game.delete_save()
	get_tree().quit()


## Voss's greenhouses: from the shelves' foot across the pocket, and at the gate.
func _greenhouses(out: String, r: RegionScene) -> void:
	var gh: Greenhouses = (r as ShatterlandsThreshold).greenhouses
	await _shot(out, "greenhouses_far", r.to_global(Vector3(2.0, 0.3, -20.0)), gh.to_global(Vector3(0.0, 3.0, 0.0)))
	await _shot(out, "greenhouses_gate", gh.gate_pos + Vector3(-3.0, 0.3, 9.0), gh.gate_pos + Vector3(0.0, 2.5, -6.0))


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
