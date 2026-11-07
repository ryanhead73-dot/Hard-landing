extends "res://tests/test_base.gd"
## Expansion foundations (X1): saves from older builds are upgraded rather than dropped, a newer
## build's save is refused, and the expansion state (region, act, flags, quests) survives a save
## and load; the quest data holds together and plays through; Juno can travel to the Shatterlands
## threshold and back, with the Kettle paused while she's away, and a save made there loads there. Run:
##   godot --headless --path . res://tests/expansion_test.tscn

const V1_FIXTURE := "res://tests/fixtures/save_v1.json"


func _name() -> String:
	return "EXPANSION TEST"


func _run() -> void:
	await _frames(10)
	_clear_enemies()
	_migrations()
	await _load_v1_save()
	_round_trip()
	_content()
	await _quest_flow()
	await _regions()
	await _journal()
	await _listening_post()
	await _drop_pod()
	finished = true


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(V1_FIXTURE))


func _write_raw(data: Variant) -> void:
	var f := FileAccess.open(Game.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _migrations() -> void:
	var v1 := _fixture()
	var up := SaveMigrations.migrate(v1)
	_check("a v1 save upgrades to the current version", int(up.get("version", 0)) == SaveMigrations.CURRENT, str(up.get("version")))
	_check("the upgrade puts a v1 save in the Kettle, Act 1", up.get("region") == "kettle" and int(up.get("act", 0)) == 1)
	_check("the upgrade adds an empty quest log and flags", up.get("quests") == {} and up.get("flags") == {})
	_check("the upgrade keeps every v1 field", up.get("scrap") == 64.0 and up.get("logs") == ["relay_1", "relay_2", "hauler_1"] and (up.get("sites") as Dictionary).size() == 2)
	_check("migrating leaves the original untouched", not v1.has("region"))
	var current := SaveMigrations.migrate(up)
	_check("a current save passes through unchanged", current == up)
	var future := v1.duplicate()
	future["version"] = SaveMigrations.CURRENT + 1
	_check("a save from a newer build is refused", SaveMigrations.migrate(future).is_empty())
	_check("a save with no version is refused", SaveMigrations.migrate({"scrap": 5}).is_empty())
	_check("something that isn't a save is refused", SaveMigrations.migrate([1, 2]).is_empty() and SaveMigrations.migrate(null).is_empty())

	# Through the real save file, including the backup fallback.
	Game.delete_save()
	_write_raw(v1)
	_check("Game reads a v1 save file as current", int(Game.read_save().get("version", 0)) == Game.SAVE_VERSION)
	main.save_game()
	_write_raw(future)
	var fell_back := Game.read_save()
	_check("a newer build's save falls back to the backup", not fell_back.is_empty() and int(fell_back.get("version", 0)) == Game.SAVE_VERSION)
	Game.delete_save()


## Continue from a v1 save, as a player updating from 0.9.0-rc1 would.
func _load_v1_save() -> void:
	_write_raw(_fixture())
	var data := Game.read_save()
	main.queue_free()
	await _frames(3)
	Game.reset()
	Game.pending_load = data
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	main.missions.bypass = true
	kestrel = main.kestrel
	player = main.player
	await _frames(20)
	_check("v1 load restores repairs", kestrel.is_repaired("aux_power") and kestrel.is_repaired("cooling") and Game.current_repair() == "canopy")
	_check("v1 load restores scrap, upgrades and gear", Game.scrap == 64 and Game.has_upgrade("plating") and Game.owns_weapon("scattergun") and Game.ammo_reserve("scattergun") == 18 and Game.stims == 2)
	_check("v1 load restores logs and caches", Game.logs.size() == 3 and Game.caches_opened == [0, 3])
	_check("v1 load restores site state", not (main.sites["aux_power"] as ExpeditionSite).has_component() and (main.sites["aux_power"] as ExpeditionSite).crate_searched(2))
	_check("v1 load lands in the Kettle, Act 1", Game.region == "kettle" and Game.act == 1)
	var q: QuestLog = main.quests
	_check("v1 load rebuilds the quest log from the repairs", q.is_done("repair_aux_power") and q.is_done("repair_cooling") and q.state_of("repair_canopy") == QuestLog.ACTIVE and q.state_of("repair_landing_gear") == QuestLog.LOCKED)
	_check("v1 load starts discoveries the save had already begun", q.state_of("ilse_trail") == QuestLog.ACTIVE and q.state_of("survivors") == QuestLog.LOCKED)
	_check("the quiet rebuild gives no rewards", Game.scrap == 64, str(Game.scrap))
	Game.delete_save()


func _round_trip() -> void:
	Game.region = "kettle"
	Game.act = 2
	Game.flags["met_reyes"] = true
	Game.flags["signal_count"] = 3
	Game.quests["side_test"] = {"state": "active", "step": 1}
	_check("saving writes a current-version save", main.save_game() and int(Game.read_save().get("version", 0)) == Game.SAVE_VERSION)
	var data := Game.read_save()
	Game.reset()
	_check("reset clears expansion state", Game.act == 1 and Game.flags.is_empty() and Game.quests.is_empty() and Game.region == "kettle")
	Game.apply_session(data)
	_check("act survives save and load", Game.act == 2)
	_check("flags survive save and load", Game.flags.get("met_reyes") == true and int(Game.flags.get("signal_count", 0)) == 3)
	_check("quest log survives save and load", (Game.quests.get("side_test", {}) as Dictionary).get("state") == "active" and int(Game.quests["side_test"].get("step", 0)) == 1)
	Game.delete_save()
	Game.reset()


func _content() -> void:
	var bad := QuestDB.validate(RegionDB.ids(), main.wildlife.caches.size())
	_check("every quest's references resolve and nothing loops", bad.is_empty(), "; ".join(bad))
	var repairs := QuestDB.all().filter(func(q): return q.has("repair"))
	_check("each of the seven repairs is a main quest", repairs.size() == Campaign.REPAIRS.size() and repairs.all(func(q): return q["kind"] == "main"))
	for a in QuestDB.ACTS:
		_check("act %d has a name" % a, String(QuestDB.ACTS[a]["name"]) != "")
	# Every main quest can be reached by finishing the ones before it.
	var reach := {}
	var grew := true
	while grew:
		grew = false
		for q in QuestDB.all():
			if reach.has(q["id"]):
				continue
			if q["requires"].all(func(c): return c["type"] != "quest" or reach.has(c["id"])):
				reach[q["id"]] = true
				grew = true
	var stuck := QuestDB.all().filter(func(q): return not reach.has(q["id"])).map(func(q): return q["id"])
	_check("every quest is reachable", stuck.is_empty(), str(stuck))
	_check("a broken reference is caught", not QuestDB._check_condition({"type": "logs", "ids": ["no_such_log"]}, {}, 8).is_empty() and not QuestDB._check_condition({"type": "repair", "id": "warp_drive"}, {}, 8).is_empty())


func _quest_flow() -> void:
	# The v1 load left Kestrel part-repaired; start from the crash.
	for r in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(r, false)
	Game.reset()
	main.quests.restore()
	var q: QuestLog = main.quests
	await _frames(2)
	_check("a new game starts on the first repair", q.state_of("repair_aux_power") == QuestLog.ACTIVE and q.state_of("repair_cooling") == QuestLog.LOCKED)
	_check("the escape is locked until navigation", q.state_of("escape") == QuestLog.LOCKED)
	_check("the active list leads with the main quest", not q.active().is_empty() and q.active()[0]["id"] == "repair_aux_power")
	_check("the journal line is the repair objective", q.objective("repair_aux_power") == Campaign.REPAIRS[0]["find"])

	var started: Array = []
	var completed: Array = []
	q.quest_started.connect(func(id): started.append(id))
	q.quest_completed.connect(func(id): completed.append(id))
	kestrel.set_repaired("aux_power", true)
	await _frames(3)
	_check("installing a repair completes its quest", q.is_done("repair_aux_power") and "repair_aux_power" in completed)
	_check("and starts the next repair", q.state_of("repair_cooling") == QuestLog.ACTIVE and "repair_cooling" in started)

	# A side quest: locked, then started by its first log, stepped, and rewarded once.
	_check("a side quest waits for its trigger", q.state_of("survivors") == QuestLog.LOCKED)
	Game.find_log("moss_1")
	await _frames(3)
	_check("finding its first log starts it", q.state_of("survivors") == QuestLog.ACTIVE and q.step_of("survivors") == 0)
	Game.find_log("moss_3")
	await _frames(3)
	_check("its steps advance in order", q.step_of("survivors") == 1 and q.objective("survivors").contains("sheltered"))
	var scrap := Game.scrap
	Game.find_log("freighter_3")
	await _frames(3)
	_check("finishing it pays its reward once", q.is_done("survivors") and Game.scrap == scrap + 30 and Game.flags.get("knows_survivors") == true)
	q.refresh()
	_check("a finished quest doesn't pay again", Game.scrap == scrap + 30)

	# Flags start quests that wait on them.
	_check("set_flag records a flag once", not Game.flags.has("probe"))
	Game.set_flag("probe")
	_check("flags read back", Game.flags.get("probe") == true)

	# The quest log saves and comes back.
	main.save_game()
	var data := Game.read_save()
	_check("the save holds the quest log", (data.get("quests", {}) as Dictionary).has("survivors"))
	Game.reset()
	Game.apply_session(data)
	_check("quest state comes back from the save", q.is_done("survivors") and q.state_of("repair_cooling") == QuestLog.ACTIVE)

	# Every repair in, then the launch, finishes the main line.
	for r in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(r, true)
	await _frames(3)
	_check("all repairs open the escape", q.state_of("escape") == QuestLog.ACTIVE)
	Game.launched = true
	await _frames(3)
	_check("launching completes the escape", q.is_done("escape"))
	Game.delete_save()
	Game.reset()


func _regions() -> void:
	Game.reset()
	for r in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(r, false)
	var rm: RegionManager = main.regions
	# The data.
	var origins: Array = [Vector3.ZERO]
	for id in RegionDB.travel_regions():
		var r := RegionDB.get_region(id)
		_check("%s has a scene that builds" % id, ResourceLoader.exists(String(r["scene"])) and load(String(r["scene"])).new() is RegionScene)
		_check("%s opens from a known region" % id, RegionDB.REGIONS.has(r["from"]) and String(r["unlock_flag"]) != "")
		for o in origins:
			_check("%s sits well clear of other regions" % id, (r["origin"] as Vector3).distance_to(o) > 1000.0)
		origins.append(r["origin"])
	_check("the Loom Expanse is named but not built yet", RegionDB.get_region("loom_expanse").get("planned", false) and not "loom_expanse" in RegionDB.travel_regions())

	# The gate in the Kettle, shut.
	var gate: Node3D = rm.gates.get("shatterlands")
	_check("the Shatterlands gate stands in the Kettle", gate != null and gate.visible)
	_check("the gate sits on the ground", absf(gate.global_position.y - main.site.height_at(gate.global_position.x, gate.global_position.z)) < 0.1)
	_place(gate.to_global(Vector3(0.0, 0.5, 4.5)), gate.global_rotation.y)
	await _frames(3)
	_check("a shut gate says why", _label().contains("rockfall") and not main._interaction.has("action"), _label())
	_check("rubble blocks a shut gate", (gate.get_node("Rubble") as Node3D).visible)

	# Opened, then through it.
	Game.set_flag("shatterlands_open")
	await _frames(3)
	_check("opening clears the rubble", not (gate.get_node("Rubble") as Node3D).visible)
	_check("an open gate offers the way through", _label().contains("Shatterlands"), _label())
	Game.scrap = 55
	Game.give_weapon("scattergun")
	var quests_before: Dictionary = Game.quests.duplicate(true)
	var crash_site: Node3D = main.site
	var bug: Enemy = main.spawn_enemy("scuttler", gate.to_global(Vector3(6.0, 0.5, 14.0)))
	await _press("interact")
	await _wait_travel(rm)
	var bug_at: Vector3 = bug.global_position
	_check("travel lands in the Shatterlands", rm.current == "shatterlands" and Game.region == "shatterlands" and rm.scene != null)
	_check("Juno arrives at the region's entry", player.global_position.distance_to(rm.scene.entry_global()) < 2.0, str(player.global_position))
	_check("the Kettle is hidden and paused", not crash_site.visible and crash_site.process_mode == Node.PROCESS_MODE_DISABLED and main.wildlife.process_mode == Node.PROCESS_MODE_DISABLED and not gate.visible)
	await get_tree().create_timer(1.0).timeout
	_check("Kettle creatures freeze while she's away", is_instance_valid(bug) and bug.global_position.distance_to(bug_at) < 0.01 and bug.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("the trip keeps scrap, weapons and quests", Game.scrap == 55 and Game.owns_weapon("scattergun") and Game.quests == quests_before)
	_check("she stands on the region's ground", player.is_on_floor() and player.global_position.y > -0.5, str(player.global_position))
	_check("the waypoint points into the region", main._waypoint() != null and (main._waypoint() as Vector3).distance_to(rm.scene.global_position) < 80.0)
	_check("the region has its own look", absf(main._env.fog_density - rm.scene.look["fog_density"]) < 0.0001)
	_check("the region keeps to its budget", _region_budget(rm.scene))

	# Going down there comes back at the region's entry, not at Kestrel.
	player.take_damage(9999.0)
	await get_tree().create_timer(main.RESPAWN_DELAY + 0.5).timeout
	_check("dying there respawns at the region's entry", not player.dead and player.global_position.distance_to(rm.scene.entry_global()) < 2.0, str(player.global_position))

	# A save made there loads there.
	main.save_game()
	var data := Game.read_save()
	_check("the save records the region", data.get("region") == "shatterlands")
	main.queue_free()
	await _frames(3)
	Game.reset()
	Game.pending_load = data
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	main.missions.bypass = true
	kestrel = main.kestrel
	player = main.player
	rm = main.regions
	await _frames(20)
	_check("loading a save made there returns to the region", rm.current == "shatterlands" and rm.scene != null and Game.region == "shatterlands")
	_check("and puts Juno at its entry", player.global_position.distance_to(rm.scene.entry_global()) < 2.0, str(player.global_position))

	# Home again.
	var fog_home: float = main.regions._old_look.get("fog_density", -1.0)
	_place(rm.scene.exit_global() + Vector3(0.0, 0.5, -1.0), 0.0)
	await _frames(3)
	_check("the way back is offered at the canyon", _label().contains("Kettle"), _label())
	await _press("interact")
	await _wait_travel(rm)
	gate = rm.gates["shatterlands"]
	_check("back in the Kettle", rm.current == "kettle" and Game.region == "kettle" and rm.scene == null)
	_check("the Kettle wakes up again", main.site.visible and main.site.process_mode != Node.PROCESS_MODE_DISABLED and main.wildlife.process_mode != Node.PROCESS_MODE_DISABLED and gate.visible)
	_check("Juno comes out at the gate", _flat_distance(player.global_position, gate.global_position) < 6.0, str(player.global_position))
	_check("the Kettle's look comes back", absf(main._env.fog_density - fog_home) < 0.0001 or fog_home < 0.0)
	_check("the region is unloaded", main.get_children().filter(func(c): return c is RegionScene).is_empty())
	Game.delete_save()
	Game.reset()


func _wait_travel(rm: RegionManager) -> void:
	await _frames(2)
	var t := 0.0
	while rm.travelling and t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _frames(10)


## Draw-call proxies for the prototype: few meshes (the undergrowth is one multimesh), a handful
## of unshadowed lights.
func _region_budget(region: Node) -> bool:
	var meshes := 0
	var lights := 0
	var shadowed := 0
	var stack: Array = [region]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			meshes += 1
		if n is Light3D:
			lights += 1
			if (n as Light3D).shadow_enabled:
				shadowed += 1
	print("  region budget: %d meshes, %d lights (%d shadowed)" % [meshes, lights, shadowed])
	return meshes <= 120 and lights <= 6 and shadowed == 0


func _panel_text(panel: UiPanel) -> String:
	var parts: PackedStringArray = [panel._title.text]
	for c in panel._content.get_children():
		if c is Label or c is Button:
			parts.append(c.text)
	return "\n".join(parts)


func _journal() -> void:
	Game.reset()
	for r in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(r, false)
	main.quests.restore()
	Game.find_log("relay_1")
	Game.find_log("relay_2")
	await _frames(3)
	_check("new discoveries point at the journal", main.hud._message.text.contains("journal") if main.hud.get("_message") else true)
	await _press("journal")
	var j: JournalPanel = main.journal
	_check("J opens the journal", j.is_open())
	var text := _panel_text(j)
	_check("the journal names the act", text.contains("ACT I") and text.contains("STRANDED"), text)
	_check("it shows the current repair and its objective", text.contains(QuestDB.REPAIR_TITLES["aux_power"]) and text.contains(Campaign.REPAIRS[0]["find"]), text)
	_check("it counts what a discovery has collected", text.contains("Ilse Marrow's trail") and text.contains("2 / %d" % QuestDB.ILSE_LOGS.size()), text)
	j.close()
	await _frames(2)
	_check("the journal closes", not j.is_open() and not get_tree().paused)
	main.logs_panel.open_log("")
	await _frames(2)
	_check("the logs list links to the journal (the pad's way in)", _panel_text(main.logs_panel).contains("Journal"))
	main.logs_panel.close()
	Game.reset()


func _listening_post() -> void:
	Game.reset()
	main.quests.restore()
	var post: ListeningPost = main.discoveries.built["listening_post"]
	_check("the listening post stands on the slope", post != null and post.global_position.y > 8.0, str(post.global_position))
	_check("its mast is tall enough to see from Kestrel", post.global_position.distance_to(kestrel.global_position) < 140.0)
	_check("the post's quest waits until Juno notices it", main.quests.state_of("listening_post") == QuestLog.LOCKED)
	# The walkway: Juno can stand on every plank from the basin floor up.
	var start := Vector3(ListeningPost.WALK_FROM.x, 0.0, ListeningPost.WALK_FROM.y)
	var top := post.to_global(Vector3(0.0, 0.0, 5.6))
	var ok := true
	for i in 6:
		var p := start.lerp(top, (i + 0.5) / 7.0)
		p.y = maxf(main.site.height_at(p.x, p.z), top.y if i == 6 else 0.0) + 2.0
		_place(p, 0.0)
		await get_tree().create_timer(0.6).timeout
		if not player.is_on_floor() or player.global_position.y < p.y - 2.6:
			ok = false
			print("  walkway gap at ", p, " juno ", player.global_position)
	_check("the walkway carries Juno up the slope", ok and player.global_position.y > main.site.height_at(start.x, start.z) + 4.0, str(player.global_position))
	await _frames(5)
	_check("coming close starts the discovery", main.quests.state_of("listening_post") == QuestLog.ACTIVE)
	_place(post.terminal_pos + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(5)
	_check("the terminal asks for a hold", _label().contains("Wake the listening post"), _label())
	var scrap := Game.scrap
	Input.action_press("interact")
	await get_tree().create_timer(ListeningPost.HOLD * 0.5).timeout
	_check("letting go early doesn't wake it", not post.is_awake())
	Input.action_release("interact")
	await _frames(3)
	Input.action_press("interact")
	await get_tree().create_timer(ListeningPost.HOLD + 0.4).timeout
	Input.action_release("interact")
	await _frames(5)
	_check("holding E wakes the post", post.is_awake() and Game.has_log("post_1"))
	_check("waking it finishes the discovery and pays once", main.quests.is_done("listening_post") and Game.scrap == scrap + 25 and Game.flags.get("heard_the_hollow") == true, str(Game.scrap - scrap))
	_check("HOB has something to say about it", main.voice.history.any(func(h): return String(h).contains("listening posts")))
	Game.reset()


func _drop_pod() -> void:
	Game.reset()
	_clear_enemies()
	main.quests.restore()
	var pod: DropPod = main.discoveries.built["drop_pod"]
	_check("the drop pod lies out on the flats, clear of the pools", pod != null and not main.site.in_pool(pod.global_position))
	_place(pod.recorder_pos + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(5)
	_check("the pod is silent until the listening post hears it", not pod.transmitting() and _label() == "" and main.quests.state_of("last_drop") == QuestLog.LOCKED, _label())
	Game.set_flag("post_awake")
	await _frames(5)
	_check("waking the post starts the side mission and the pod reaching", main.quests.state_of("last_drop") == QuestLog.ACTIVE and Game.flags.get("pod_found") == true and main.quests.step_of("last_drop") == 1)
	_check("the recorder can be pulled", _label().contains("flight recorder"), _label())
	await _press("interact")
	_check("pulling it starts the download", pod.downloading())
	await get_tree().create_timer(5.0).timeout
	_check("the noise brings a wave", pod.waves >= 1 and _enemy_count() >= 2, "%d waves, %d enemies" % [pod.waves, _enemy_count()])
	_clear_enemies()
	var before := pod.progress
	_place(pod.global_position + Vector3(25.0, 1.0, 0.0), 0.0)
	await get_tree().create_timer(1.0).timeout
	_check("walking off stalls the download", is_equal_approx(pod.progress, before) or absf(pod.progress - before) < 0.1, "%.2f -> %.2f" % [before, pod.progress])
	_place(pod.recorder_pos + Vector3(0.0, 0.5, 0.0), 0.0)
	await get_tree().create_timer(0.5).timeout
	_check("coming back picks it up again", pod.progress > before)
	pod.progress = DropPod.DOWNLOAD - 0.3
	var scrap := Game.scrap
	var charges := Game.charges
	await get_tree().create_timer(1.0).timeout
	_clear_enemies()
	_check("a full download gives Reyes's last log", pod.is_done() and Game.has_log("pod_1"))
	_check("and the pod's locker", Game.charges > charges)
	_check("the side mission completes and pays", main.quests.is_done("last_drop") and Game.scrap == scrap + 30 and Game.flags.get("knows_greenhouses") == true)
	_check("the pod goes quiet", not pod.transmitting() and _label() == "")
	Game.reset()
