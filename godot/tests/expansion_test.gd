extends "res://tests/test_base.gd"
## Expansion foundations (X1): saves from older builds are upgraded rather than dropped, a newer
## build's save is refused, and the expansion state (region, act, flags, quests) survives a save
## and load; the quest data holds together and plays through; Juno can travel to the Shatterlands
## threshold and back, with the Kettle paused while she's away, and a save made there loads there. Run:
##   godot --headless --path . res://tests/expansion_test.tscn

const V1_FIXTURE := "res://tests/fixtures/save_v1.json"


func _name() -> String:
	return "EXPANSION TEST"


## Stands Juno at `at` and holds E long enough for a held prompt (a stay-line).
func _hold_at(at: Vector3, secs := FerroCanopy.LOCK_HOLD) -> void:
	_place(at + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	Input.action_press("interact")
	await get_tree().create_timer(secs + 0.3).timeout
	Input.action_release("interact")
	await _frames(3)


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
	await _survey_depot()
	await _relay()
	await _landmarks()
	await _drifters()
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
	var bad := QuestDB.validate(RegionDB.ids(), main.wildlife.caches.size(), main.discoveries.ids())
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
	_check("the Loom Expanse opens from the Shatterlands once the wing is in", "loom_expanse" in RegionDB.travel_regions() and RegionDB.get_region("loom_expanse")["from"] == "shatterlands" and RegionDB.get_region("loom_expanse")["unlock_flag"] == "loom_open")

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
	await get_tree().process_frame
	await get_tree().process_frame
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
	_check("the trip keeps scrap, weapons and quests", Game.scrap == 55 and Game.owns_weapon("scattergun") and Game.quests == quests_before, "%s vs %s" % [Game.quests.keys(), quests_before.keys()])
	_check("she stands on the region's ground", player.is_on_floor() and player.global_position.y > -0.5, str(player.global_position))
	_check("the waypoint points into the region", main._waypoint() != null and (main._waypoint() as Vector3).distance_to(rm.scene.global_position) < 80.0)
	_check("the region has its own look", absf(main._env.fog_density - rm.scene.look["fog_density"]) < 0.0001)
	_check("the region keeps to its budget", _region_budget(rm.scene))
	_check("the pocket wears Jake's PBR sets, compressed and mipmapped", _pbr_ok(), "")

	# The pocket's own wildlife belongs to it.
	var residents: Array[Enemy] = rm.scene.spawn_residents(main)
	await _frames(3)
	_check("the Shatterlands has its own wildlife", residents.size() == rm.scene.residents.size() and residents.all(func(e): return is_instance_valid(e) and e.get_parent() == rm.scene))
	_check("which stands on the region's ground", residents.all(func(e): return e.global_position.distance_to(rm.scene.global_position) < 90.0 and e.global_position.y > rm.scene.global_position.y - 0.5), str(residents.map(func(e): return e.global_position)))
	# The layout pays the drifter off: one hangs over the nested pack, and a pair hang close.
	var drifters := residents.filter(func(e): return e is Drifter)
	var bugs := residents.filter(func(e): return e is Scuttler)
	var best := 0
	for d in drifters:
		best = maxi(best, bugs.filter(func(b): return (d as Drifter).in_cloud(b.global_position, d.global_position)).size())
	_check("a drifter hangs over the pack, its cloud reaching most of it", best >= 3, "%d of %d" % [best, bugs.size()])
	var paired := drifters.any(func(a): return drifters.any(func(b): return a != b and (a as Drifter).in_cloud(b.global_position, a.global_position)))
	_check("and a pair hang close enough to set each other off", paired)
	var lone: Drifter = drifters.reduce(func(m, d): return d if d.global_position.distance_to(rm.scene.entry_global()) < m.global_position.distance_to(rm.scene.entry_global()) else m)
	var lone_gap: float = residents.filter(func(e): return e != lone).map(func(e): return e.global_position.distance_to(lone.global_position)).min()
	_check("the first drifter Juno meets is alone, to learn on", lone.global_position.distance_to(rm.scene.entry_global()) < 30.0 and lone_gap > 12.0, "%.0f m from the way in, %.0f m from the rest" % [lone.global_position.distance_to(rm.scene.entry_global()), lone_gap])
	# Still nested after they've had time to wander.
	await get_tree().create_timer(6.0).timeout
	var nested := bugs.filter(func(b): return b.global_position.distance_to(rm.scene.to_global(ShatterlandsThreshold.NEST)) < 4.0).size()
	_check("the pack keeps to its nest", nested == bugs.size(), "%d of %d" % [nested, bugs.size()])
	for e in residents:
		e.queue_free()
	await _frames(2)

	# Voss's greenhouses: the Act 2 hub, reached and hailed.
	_check("opening the canyon starts Act 2's first quest", main.quests.state_of("the_lost") == QuestLog.ACTIVE)
	var gh: Greenhouses = (rm.scene as ShatterlandsThreshold).greenhouses
	_check("the greenhouses stand in the pocket", gh != null and gh.is_inside_tree())
	_check("the waypoint leads to their gate", _flat_distance(main._waypoint(), gh.gate_pos) < 3.0)
	_place(gh.gate_pos + Vector3(0.0, 0.5, 6.0), 0.0)
	await _frames(5)
	_check("coming up on them counts as finding them", gh.reached() and main.quests.step_of("the_lost") == 1)
	_place(gh.intercom_pos + Vector3(0.0, 0.5, 0.3), 0.0)
	await _frames(3)
	_check("the gate can be hailed", _label().contains("Hail the greenhouses"), _label())
	await _press("interact")
	await _frames(3)
	_check("hailing it meets Reyes, who wants the nest cleared", gh.hailed() and main.quests.step_of("the_lost") == 2 and not gh.is_open())
	_check("the gate stays shut till then", _label().contains("Clear that nest"), _label())

	# The Marigold: walk up the fallen plate and along the spine to the locker.
	var sh := rm.scene as ShatterlandsThreshold
	_check("the hauler's locker waits on its back", sh.locker_pos != Vector3.INF and sh.locker_pos.y - sh.global_position.y > 4.0, str(sh.locker_pos - sh.global_position))
	var foot: Vector3 = sh.to_global(sh.get_node("Marigold").transform * Vector3(-11.5, 0.0, -10.0)) if sh.has_node("Marigold") else Vector3.INF
	_check("the climb starts on the ground", foot != Vector3.INF)
	var route: Array[Vector3] = [sh.to_global(sh.get_node("Marigold").transform * Vector3(-2.0, 5.2, -10.0)), sh.to_global(sh.get_node("Marigold").transform * Vector3(0.0, 5.2, 0.0)), sh.locker_pos]
	_place(Vector3(foot.x, sh.global_position.y + 0.5, foot.z), 0.0)
	await _frames(5)
	var leg := 0
	var t := 0.0
	Input.action_press("move_forward")
	while t < 20.0 and leg < route.size():
		var d: Vector3 = route[leg] - player.global_position
		d.y = 0.0
		if d.length() < 0.9:
			leg += 1
			continue
		player.face(atan2(-d.x, -d.z))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release("move_forward")
	await _frames(5)
	_check("Juno can walk up onto the wreck and along to the locker", leg == route.size() and player.global_position.y - sh.global_position.y > 4.0, "leg %d at %s after %.1f s" % [leg, player.global_position - sh.global_position, t])
	_check("the locker can be opened", _label().contains("dorsal locker"), _label())
	var charges := Game.charges
	await _press("interact")
	await _frames(3)
	_check("it holds Voss's log and two charges", sh.locker_open() and Game.has_log("voss_1") and Game.charges == mini(charges + 2, Game.max_charges()) and main.quests.is_done("marigold"))

	# Reyes's price: the nest under the Marigold's tail. Cleared, it stays cleared.
	var pocket: Array[Enemy] = sh.spawn_residents(main)
	await _frames(3)
	var nest_bugs := pocket.filter(func(e): return e.is_in_group("resident_nest"))
	_check("the nest is the pack under the tail", nest_bugs.size() == 4 and nest_bugs.all(func(e): return e is Scuttler))
	for e in nest_bugs:
		e.take_damage(999.0, e.global_position, Vector3.FORWARD)
	await _frames(3)
	_check("killing the nest clears it and moves the quest on", sh.nest_cleared() and main.quests.step_of("the_lost") == 3)
	for e in pocket:
		if is_instance_valid(e):
			e.queue_free()
	await _frames(2)
	var again: Array[Enemy] = sh.spawn_residents(main)
	_check("a cleared nest doesn't come back", again.size() == sh.residents.size() - 4 and not again.any(func(e): return e.is_in_group("resident_nest")), "%d spawned" % again.size())
	for e in again:
		e.queue_free()
	await _frames(2)
	# Back at the gate, it opens, Reyes waits inside, and the middle glasshouse can be walked into.
	_place(gh.gate_pos + Vector3(0.0, 0.5, 5.0), PI)
	await _frames(5)
	_check("back at the gate, Reyes opens up and the quest is done", gh.is_open() and main.quests.is_done("the_lost"))
	await get_tree().create_timer(2.0).timeout
	_check("Reyes waits inside the gate", gh.reyes.visible and gh.reyes.global_position.distance_to(gh.gate_pos) < 6.0)
	route = [gh.gate_pos + Vector3(0.0, 0.0, -3.0), gh.house_door, gh.house_inside]
	leg = 0
	t = 0.0
	Input.action_press("move_forward")
	while t < 20.0 and leg < route.size():
		var d: Vector3 = route[leg] - player.global_position
		d.y = 0.0
		if d.length() < 0.9:
			leg += 1
			continue
		player.face(atan2(-d.x, -d.z))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release("move_forward")
	await _frames(5)
	_check("Juno walks through the gate, up the ramp and into the glasshouse", leg == route.size() and player.global_position.y > gh.house_inside.y - 0.2, "leg %d at %s after %.1f s" % [leg, player.global_position - gh.house_inside, t])
	_place(gh.reyes.global_position + Vector3(0.0, 0.5, 1.4), 0.0)
	await _frames(3)
	_check("Reyes can be talked to", _label().contains("Talk to Reyes"), _label())
	await _press("interact")
	await _frames(3)
	_check("and talking to her is remembered", Game.flags.get("reyes_talked", false) == true)
	# Some of the eleven about the camp, each with a word for Juno.
	_check("the camp has more of the eleven", gh.survivors.size() >= 4)
	var words := 0
	for p in gh.survivors:
		_place(p.global_position + Vector3(0.0, 0.5, 0.0) - p.global_transform.basis.z * 1.0, 0.0)
		await _frames(3)
		if _label().contains("Talk to %s" % p.name) and not Story.SURVIVORS.get(p.name, []).is_empty():
			words += 1
		else:
			print("  no word from %s: %s" % [p.name, _label()])
	_check("each can be talked to", words == gh.survivors.size(), "%d of %d" % [words, gh.survivors.size()])
	var haddad: Node3D = gh.survivors.filter(func(p): return p.name == "Haddad")[0]
	_check("the lookout stands high enough to see over the wall", haddad.global_position.y - gh.global_position.y > 1.4)

	# Teo's favour, the dark house: Teo asks, Voss's cache on the high shelf gives a cell, the east
	# house lights up again.
	var teo: Node3D = gh.survivors.filter(func(p): return p.name == "Teo")[0]
	_place(sh.cache_pos + Vector3(0.0, 0.5, 0.0), PI)
	await _frames(3)
	_check("Voss's cache stays shut until someone wants a cell", _label().contains("Voss's mark") and not _label().contains("[E]"), _label())
	_place(teo.global_position + Vector3(0.0, 0.5, 0.0) - teo.global_transform.basis.z * 1.0, 0.0)
	await _frames(3)
	await _press("interact")
	await _frames(3)
	_check("Teo asks for a lamp cell, and the favour starts", Game.flags.get("lamp_cell_asked") == true and main.quests.state_of("dark_house") == QuestLog.ACTIVE)
	_check("the east house is dark until then", not gh._east_glass.emission_enabled)
	# The climb: up the three shelves' ramps from the pocket floor to the cache.
	_place(sh.to_global(Vector3(-9.0, 0.5, -6.0)), 0.0)
	route = []
	for p in [Vector3(-12.0, 0.0, -6.0), Vector3(-19.0, 0.0, -6.0), Vector3(-29.0, 0.0, -9.0), Vector3(-30.0, 0.0, -10.0), Vector3(-30.0, 0.0, -16.0), Vector3(-24.0, 0.0, -26.0), Vector3(-17.0, 0.0, -34.0), Vector3(-20.0, 0.0, -39.0)]:
		route.append(sh.to_global(p))
	route.append(sh.cache_pos)
	await _frames(5)
	leg = 0
	t = 0.0
	Input.action_press("move_forward")
	while t < 30.0 and leg < route.size():
		var d: Vector3 = route[leg] - player.global_position
		d.y = 0.0
		if d.length() < 0.9:
			leg += 1
			continue
		player.face(atan2(-d.x, -d.z))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release("move_forward")
	await _frames(5)
	_check("Juno can climb the shelves to the cache", leg == route.size() and player.global_position.y - sh.global_position.y > 8.5, "leg %d at %s after %.1f s" % [leg, player.global_position - sh.global_position, t])
	_check("and take a cell", _label().contains("Take a lamp cell"), _label())
	await _press("interact")
	await _frames(3)
	_check("taking it moves the favour on", Game.flags.get("lamp_cell_found") == true and main.quests.step_of("dark_house") == 1 and not sh._cache_tell.visible)
	_place(teo.global_position + Vector3(0.0, 0.5, 0.0) - teo.global_transform.basis.z * 1.0, 0.0)
	await _frames(3)
	_check("Teo takes the cell", _label().contains("Give Teo the lamp cell"), _label())
	var scrap_before := Game.scrap
	var charges_before := Game.charges
	await _press("interact")
	await _frames(3)
	_check("the east house lights up, and the favour pays", gh.east_lit() and gh._east_glass.emission_enabled and main.quests.is_done("dark_house") and Game.scrap == scrap_before + 25 and Game.charges == mini(charges_before + 2, Game.max_charges()), "scrap %d -> %d" % [scrap_before, Game.scrap])
	_check("after that Teo has other things to say", _label().contains("Talk to Teo"), _label())

	# The way north: Reyes had the barricade on the north split pulled back when Juno talked to her.
	var split: Vector3 = sh.to_global(RegionDB.get_region("gillwood")["gate_pos"])
	_check("talking to Reyes opens the north split and points the waypoint there", sh.way_north_open() and not sh._barricade.visible and rm.waypoint().distance_to(sh.to_global(ShatterlandsThreshold.NORTH_SPLIT)) < 2.0)
	_check("Ferro-9's quest starts", main.quests.state_of("ferro_9") == QuestLog.ACTIVE)
	# Walked in from the pocket floor, not placed: nothing in the split may block the way.
	_place(split + Vector3(0.0, 0.5, 12.0), 0.0)
	await _frames(5)
	t = 0.0
	Input.action_press("move_forward")
	while t < 8.0 and _flat_distance(player.global_position, split) > 1.5:
		var d: Vector3 = split - player.global_position
		player.face(atan2(-d.x, -d.z))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release("move_forward")
	await _frames(3)
	_check("Juno walks up the split and it offers the Gillwood", _label().contains("Gillwood"), "%s at %s" % [_label(), player.global_position - split])
	await _press("interact")
	await _wait_travel(rm)
	var gw := rm.scene as Gillwood
	_check("through it is the Gillwood", rm.current == "gillwood" and gw != null and Game.region == "gillwood")
	_check("the Kettle stays asleep", not main.site.visible and main.site.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("arriving moves the quest on", Game.flags.get("reached_gillwood") == true and main.quests.step_of("ferro_9") == 1)
	_check("the Gillwood keeps to the budget", _region_budget(gw))
	_check("its waypoint leads to the wreck", rm.waypoint().distance_to(gw.to_global(Gillwood.WRECK)) < 3.0)
	_place(gw.to_global(Gillwood.WRECK + Vector3(0.0, 0.5, 14.0)), 0.0)
	await _frames(3)
	_check("coming near finds Ferro-9", Game.flags.get("found_ferro9") == true and main.quests.step_of("ferro_9") == 2)
	# B1, the canopy rescue: the nose hangs in the trees, reached up a fallen trunk.
	var fc := gw.ferro
	_check("Ferro-9's nose hangs in the trees", gw.fore.global_position.y - gw.global_position.y > 3.0 and fc.active())
	_check("the waypoint points to the fallen trunk", rm.waypoint().distance_to(gw.ramp_foot) < 2.0)
	_place(gw.ramp_foot + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	var walked := await _walk_path([gw.ramp_top, gw.cockpit_pos], 8.0)
	_check("Juno walks up the trunk onto the wing", walked and fc.on_wing(), "at %s" % (player.global_position - gw.global_position))
	await _frames(3)
	_check("her weight starts the canopy sliding", fc.sliding and fc.objective().contains("stay-lines"), fc.objective())
	_place(gw.cockpit_pos + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	_check("her flight recorder can be pulled", _label().contains("flight recorder"), _label())
	await _press("interact")
	await _frames(2)
	_check("it's Brandt's log", Game.has_log("ferro_1"))
	await _hold_at(fc.anchor_pos[0])
	_check("a stay-line locks with a held E", fc.locked[0] and not fc.lines_done(), str(fc.locked))
	fc.slide_left = 0.05
	await _frames(4)
	_check("too slow: the lines spring and the canopy is hauled back, no fail", not fc.locked.has(true) and not fc.lines_done() and not Game.flags.get("ferro_canopy", false))
	await get_tree().create_timer(2.4).timeout
	_check("then it starts over at full time", fc.sliding and fc.slide_left > fc.slide_time() - 1.0, "%s %.1f" % [fc.sliding, fc.slide_left])
	for k in 3:
		await _hold_at(fc.anchor_pos[k])
	_check("three lines on (the third across the plank) hold it", fc.lines_done() and not fc.sliding, str(fc.locked))
	_check("the next step is the winch under the nose", fc.objective().contains("winch") and rm.waypoint().distance_to(fc.console_pos) < 2.5, Game.objective_text())
	_place(fc.console_pos + Vector3(0.0, 0.5, 1.6), 0.0)
	await _frames(3)
	_check("the console offers the winch", _label().contains("Start Ferro-9's winch"), _label())
	await _press("interact")
	await _frames(3)
	_check("starting it sends veilwings for the coupler", fc.winching and fc.veilwings.size() == 2 and fc.veilwings.all(func(v): return v.target == fc.coupler))
	await get_tree().create_timer(1.0).timeout
	_check("it winds while Juno is by the console", fc.wound > 0.5, "%.2f" % fc.wound)
	fc.coupler.take_damage(14.0, fc.coupler.global_position)
	var w0 := fc.wound
	await get_tree().create_timer(0.5).timeout
	_check("a hit on the coupler shorts it and stops the winch", fc.shorted > 0.0 and is_equal_approx(fc.wound, w0) and fc.objective().contains("chime"), fc.objective())
	fc.ring_chime(0)
	await _frames(2)
	_check("ringing a chime scatters the veilwings", fc.veilwings.all(func(v): return v.state == Veilwing.State.CLIMB), str(fc.veilwings.map(func(v): return v.state)))
	await get_tree().create_timer(3.0).timeout
	_place(fc.console_pos + Vector3(0.0, 0.5, 14.0), 0.0)
	await _frames(3)
	w0 = fc.wound
	await get_tree().create_timer(0.6).timeout
	_check("walking off pauses it, without losing any", is_equal_approx(fc.wound, w0) and w0 > 0.5 and fc.objective().contains("paused"), fc.objective())
	_check("progress is saved as it goes", Game.flags.has("ferro_winch") or fc.wound < 5.0)
	fc.wound = FerroCanopy.WINCH_TIME - 0.4
	_place(fc.console_pos + Vector3(0.0, 0.5, 1.6), 0.0)
	await get_tree().create_timer(1.6).timeout
	_check("at 100%% the canopy is on the pad and sent home", Game.flags.get("ferro_canopy") == true and Game.delivered("glazing") and gw.canopy.global_position.distance_to(fc.pad_pos) < 1.5, "%.1f m" % gw.canopy.global_position.distance_to(fc.pad_pos))
	_check("the veilwings lose interest", fc.coupler.dead and not fc.winching)
	# B2, the gear escort: strut onto Ferro-9's hauler drone, the drone along a powered route.
	var ge := gw.gear
	_clear_enemies()
	_check("with the canopy down, the gear is next", ge.active() and rm.waypoint().distance_to(gw.strut_pos) < 2.0, str(rm.waypoint() - gw.strut_pos))
	await _hold_at(gw.strut_pos, GearEscort.CUT_HOLD)
	_check("the strut is cut free with a held E", ge.cut() and Game.flags.get("ferro_gear", false) != true)
	_place(ge.drone.global_position + Vector3(0.0, 0.0, 2.2), 0.0)
	await _frames(3)
	_check("the hauler drone takes the strut", _label().contains("Mount the strut"), _label())
	await _press("interact")
	var d0 := ge.drone.global_position
	await get_tree().create_timer(1.0).timeout
	_check("mounted, the drone sets off for the fork by itself", ge.mounted() and ge.drone.global_position.distance_to(d0) > 1.0 and not gw.strut.visible)
	ge.along = 1.0
	await _frames(3)
	_check("at the fork it waits for Juno to pick a route", ge.waiting() == "route" and ge.objective().contains("route"), ge.objective())
	_place(gw.to_global(GearEscort.LEVER_HIGH) + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	_check("the ridge lever says what it costs", _label().contains("ridge") and _label().contains("spore"), _label())
	await _press("interact")
	_check("the route is chosen", ge.route() == "high" and ge.powered(1))
	await get_tree().create_timer(0.5).timeout
	_check("it stops at the next unpowered node", ge.waiting() == "post" or ge.at == 1, "%s at %d" % [ge.waiting(), ge.at])
	_place(ge.post_pos(3) + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	_check("route nodes can be powered", _label().contains("route node"), _label())
	await _press("interact")
	_check("powering one lights it for the drone", ge.powered(3))
	_place(ge.post_pos(3) + Vector3(2.0, 0.5, -3.0), 0.0)
	ge.at = 3
	ge.along = 0.1
	var gear_wait := 0.0
	while gear_wait < 4.0 and not ge.jammed:
		await get_tree().physics_frame
		gear_wait += get_physics_process_delta_time()
	_check("an unburst spore pod on the ridge jams the drone", ge.jammed and ge.objective().contains("jammed"), ge.objective())
	ge.pods[1].take_hit()
	await get_tree().create_timer(5.5).timeout
	await _hold_at(ge.drone.global_position + Vector3(1.4, -0.2, 0.0), GearEscort.PATCH_HOLD)
	_check("it's patched with scrap, never lost", not ge.jammed)
	_place(ge.post_pos(5) + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	await _press("interact")
	# Well clear of the hoist while the drone comes down off the ridge and the brood wakes.
	_place(gw.to_global(GearEscort.START + Vector3(-4.0, 0.5, 0.0)), 0.0)
	gear_wait = 0.0
	while gear_wait < 14.0 and ge.at < 5:
		await get_tree().physics_frame
		gear_wait += get_physics_process_delta_time()
	_check("a pod Juno burst first lets it pass", ge.at == 5 and ge.jams == 1, "at %d, jams %d" % [ge.at, ge.jams])
	# Path recovery: a fresh escort built from the flags puts the drone back where it was.
	var ge2 := GearEscort.new()
	ge2.gw = gw
	gw.add_child(ge2)
	await _frames(1)
	_check("after a load the drone is back on its route", ge2.route() == "high" and ge2.at == 5 and ge2.powered(3) and ge2.drone.global_position.distance_to(ge.drone.global_position) < 0.5)
	for p in ge2.pods:
		p.queue_free()
	ge2.drone.queue_free()
	ge2.queue_free()
	await _frames(3)
	_check("a brood holds the hoist clearing and stops the drone", ge.brood.size() == GearEscort.BROOD and ge.waiting() == "brood", "%d, %s" % [ge.brood.size(), ge.waiting()])
	for e in ge.brood:
		if is_instance_valid(e) and not e.dead:
			e.take_damage(999.0, e.global_position, Vector3.FORWARD)
	player.health = 100.0
	await get_tree().create_timer(0.5).timeout
	_check("cleared, the hoist can be powered", ge.brood_cleared() and ge.waiting() == "hoist")
	_place(ge.post_pos(6) + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	_check("Reyes's hoist takes power", _label().contains("hoist"), _label())
	await _press("interact")
	gear_wait = 0.0
	while gear_wait < 10.0 and not ge.done():
		await get_tree().physics_frame
		gear_wait += get_physics_process_delta_time()
	_check("at the hoist the strut goes up and home", ge.done() and Game.delivered("struts"), "at %d" % ge.at)
	await get_tree().create_timer(1.6).timeout
	_check("both off: the quest is done and the waypoint points home", main.quests.is_done("ferro_9") and rm.waypoint().distance_to(gw.exit_global()) < 2.0, "quest %s, step %d, waypoint %s, dead %s, hp %.0f" % [main.quests.state_of("ferro_9"), main.quests.step_of("ferro_9"), rm.waypoint() - gw.exit_global(), player.dead, player.health])
	_check("the canopy sits on its skids and the strut lies on the ground", gw.canopy.position.y < 1.5 and gw.strut.global_position.y - gw.global_position.y < 1.5)
	# The Gillwood's own creature: roosts under the caps, flares, swoops; stepping aside dodges.
	_check("veilwings roost in the Gillwood", gw.residents.filter(func(r): return r[0] == "veilwing").size() == 3)
	var vw_at: Vector3 = gw.to_global(Vector3(-20.0, 0.0, 30.0))
	_place(vw_at + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	var vw := main.spawn_enemy("veilwing", vw_at + Vector3(0.0, 7.0, -8.0), "", gw) as Veilwing
	var hp := player.health
	var waited := 0.0
	while waited < 4.0 and vw.state != Veilwing.State.FLARE:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("a veilwing that sees Juno flares, its gills open to a shot", vw.state == Veilwing.State.FLARE and vw.weak_spot() != Vector3.INF)
	waited = 0.0
	while waited < 4.0 and vw.hits == 0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check("standing still, its swoop hits her", vw.hits == 1 and player.health < hp and vw.passes == 1, "hits %d, passes %d" % [vw.hits, vw.passes])
	# Next pass: as it dives, she steps aside.
	waited = 0.0
	while waited < 10.0 and vw.passes < 2:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	var dodge_from := player.global_position
	while waited < 12.0 and vw.state == Veilwing.State.SWOOP and vw.global_position.distance_to(player.global_position + Vector3.UP * 1.2) > Veilwing.COMMIT_RANGE + 0.5:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	var away := (vw.global_position - player.global_position).cross(Vector3.UP).normalized()
	player.face(atan2(-away.x, -away.z))
	Input.action_press("move_forward")
	await get_tree().create_timer(0.8).timeout
	Input.action_release("move_forward")
	_check("stepping aside as it commits makes it miss", vw.passes == 2 and vw.hits == 1, "hits %d, passes %d, moved %.1f m" % [vw.hits, vw.passes, _flat_distance(player.global_position, dodge_from)])
	vw.take_damage(999.0, vw.global_position, Vector3.FORWARD)
	player.health = 100.0
	await _frames(3)
	# The recorder pointed west, to the crew's jettison locker in the trees.
	_check("the recorder starts the hunt for the jettison locker", main.quests.state_of("ferro_locker") == QuestLog.ACTIVE)
	_place(gw.locker_pos + Vector3(0.0, 0.5, 0.0), PI)
	await _frames(3)
	_check("the locker can be opened", _label().contains("jettison locker"), _label())
	var stims_before := Game.stims
	await _press("interact")
	await _frames(2)
	_check("it holds the crew's kit", main.quests.is_done("ferro_locker") and Game.stims == mini(stims_before + 2, Game.max_stims()))
	# Back south: at the split in the pocket, not at its canyon.
	_place(gw.exit_global() + Vector3(0.0, 0.5, -1.0), 0.0)
	await _frames(3)
	_check("the way back south is offered", _label().contains("greenhouses"), _label())
	await _press("interact")
	await _wait_travel(rm)
	sh = rm.scene as ShatterlandsThreshold
	_check("back in the pocket, at the north split", rm.current == "shatterlands" and sh != null and _flat_distance(player.global_position, sh.to_global(ShatterlandsThreshold.NORTH_SPLIT)) < 6.0, str(player.global_position - (sh.global_position if sh else Vector3.ZERO)))
	gh = sh.greenhouses
	# B3, the wing chase: Marigold's wing-tip, on a tether robot running a circuit in the crags.
	var wc := sh.wing
	_clear_enemies()
	_check("with the strut on the hoist, Marigold's wing-tip is next", wc.active() and not wc.started())
	_place(wc.search_pos() + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	_check("Marigold can be searched", _label().contains("wing-tip"), _label())
	await _press("interact")
	var r0 := wc.robot.global_position
	await get_tree().create_timer(0.6).timeout
	_check("the section's gone: a tether robot runs off with it", wc.started() and wc.robot.visible and wc.robot.global_position.distance_to(r0) > 1.5)
	var heading := (wc.point(wc.leg + 1) - wc.point(wc.leg)).normalized()
	_place(wc.robot.global_position + heading * 6.0 + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	_check("coming at it head-on makes it bolt", wc.flee > 0.0 and wc.spooks == 1)
	_place(wc.search_pos() + Vector3(0.0, 0.5, 0.0), 0.0)
	wc.flee = 0.0
	wc.leg = 1
	wc.along = 0.99
	await _frames(4)
	_check("at a cable crossing it slows to a crawl", wc.leg == 2 and wc.cable > 0.0)
	_place(wc.robot.global_position + heading.cross(Vector3.UP) * 1.8 + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(2)
	_check("cut off beside it there, the panel is in reach", _label().contains("Take the wing-tip"), _label())
	_place(wc.decoy_pos() + Vector3(0.0, 0.5, 1.6), 0.0)
	await _frames(3)
	_check("the decoy relay can be powered", _label().contains("decoy relay"), _label())
	await _press("interact")
	_check("powered, it waits for the robot", wc.decoy_on() and wc.objective().contains("decoy"), wc.objective())
	_place(wc.search_pos() + Vector3(0.0, 0.5, 0.0), 0.0)
	wc.cable = 0.0
	wc.leg = 5
	wc.along = 0.995
	await _frames(4)
	_check("its racket on the return leg brings drifters", wc.drifters.size() == 3 and Game.flags.get("wing_drifters") == true)
	wc.leg = 6
	wc.along = 0.6
	await _frames(2)
	wc.trip_siren()
	_check("its siren pulls them after the robot", wc.drifters.all(func(e): return e.target == wc.robot))
	wc.leg = 7
	wc.along = 0.4
	await _frames(4)
	_check("past the live decoy it stops to feed", wc.docked > 0.0 and wc.objective().contains("feeding"), wc.objective())
	_clear_enemies()
	_place(wc.robot.global_position + Vector3(0.0, 0.5, 2.0), 0.0)
	await _frames(3)
	await _press("interact")
	_check("the panel comes off and goes home", wc.done() and Game.delivered("wing_panel") and not wc._panel.visible)
	player.health = 100.0

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
## Every map in the Shatterlands sets imports VRAM-compressed with mipmaps (their .import files
## are checked in; without them Godot would import them raw), and the ground uses them.
func _pbr_ok() -> bool:
	for set_name in ["shatterlands_ground", "fungus_cap_underside", "fungus_stem", "hauler_hull", "basalt_hex_columns",
			"greenhouse_palisade_scrap_hull", "greenhouse_grow_bed_soil", "glasshouse_frame_metal", "greenhouse_glass_clean", "greenhouse_glass_dirty"]:
		for map in ["albedo", "normal", "roughness"]:
			var t := load("res://assets/textures/shatterlands/%s/%s.png" % [set_name, map]) as Texture2D
			if t == null:
				print("  missing %s/%s" % [set_name, map])
				return false
			var img := t.get_image()
			if not img.is_compressed() or not img.has_mipmaps():
				print("  %s/%s: compressed %s, mipmaps %s" % [set_name, map, img.is_compressed(), img.has_mipmaps()])
				return false
	return PbrSet.exists("shatterlands", "shatterlands_ground")


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
	# Unshadowed omni lights are cheap in the clustered renderer; 8 keeps any one mesh under the
	# Compatibility renderer's per-object limit too.
	return meshes <= 120 and lights <= 8 and shadowed == 0


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
	var qm: Array = main.quests.markers().filter(func(m): return m["id"] == "last_drop")
	_check("the side mission is marked where it happens", qm.size() == 1 and (qm[0]["pos"] as Vector3).distance_to(pod.global_position) < 0.1)
	_check("the map shows it", main.map_panel.marks().any(func(m): return m["kind"] == "quest" and m["label"] == "The last supply drop"))
	_place(Vector3(0.0, 0.5, 15.0), 0.0)
	await _frames(2)
	main.journal.open()
	await _frames(2)
	_check("the journal says how far and which way", _panel_text(main.journal).contains("m north-west"), _panel_text(main.journal))
	main.journal.close()
	_place(pod.recorder_pos + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(5)
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


func _survey_depot() -> void:
	Game.reset()
	for r in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(r, false)
	_clear_enemies()
	main.quests.restore()
	var depot: SurveyDepot = main.discoveries.built["survey_depot"]
	_check("the depot stands on the northern flats", depot != null and absf(depot.global_position.y - main.site.height_at(depot.global_position.x, depot.global_position.z)) < 0.1)
	_place(depot.door_pos + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(5)
	_check("seeing it starts the discovery", main.quests.state_of("survey_depot") == QuestLog.ACTIVE)
	_check("without power the lock is dead", _label().contains("Dead") and not depot.is_open(), _label())
	Input.action_press("interact")
	await get_tree().create_timer(SurveyDepot.HOLD + 0.3).timeout
	Input.action_release("interact")
	_check("holding E without power does nothing", not depot.is_open())
	kestrel.set_repaired("aux_power", true)
	await _frames(3)
	_check("with aux power HOB can try the lock", _label().contains("Let HOB talk to the lock"), _label())
	Input.action_press("interact")
	await get_tree().create_timer(SurveyDepot.HOLD + 0.3).timeout
	Input.action_release("interact")
	await _frames(3)
	_check("HOB opens the door", depot.is_open() and main.quests.step_of("survey_depot") == 1)
	# Walk in: the doorway is open now.
	var inside := depot.to_global(Vector3(0.0, 0.5, 0.5))
	_place(depot.door_pos + Vector3(0.0, 0.5, 0.0), 0.0)
	player.velocity = Vector3.ZERO
	var dir := (inside - player.global_position)
	for i in 40:
		player.global_position += Vector3(dir.x, 0.0, dir.z) / 40.0
		await get_tree().physics_frame
	_check("Juno can step through the doorway", _flat_distance(player.global_position, inside) < 1.0, str(player.global_position))
	_place(depot.core_pos + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	_check("the core can be taken", _label().contains("ship-mind core"), _label())
	var scrap := Game.scrap
	await _press("interact")
	await _frames(3)
	_check("taking it gives WREN's log and finishes the discovery", depot.core_taken() and Game.has_log("depot_1") and main.quests.is_done("survey_depot") and Game.scrap == scrap + 15 + 20)
	Game.reset()


func _relay() -> void:
	Game.reset()
	for r in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(r, false)
	_clear_enemies()
	main.quests.restore()
	var relay: RelayStation = main.sites["aux_power"]
	_place(relay.console_point() + Vector3(0.0, 0.5, 0.0), 0.0)
	await _frames(3)
	_check("the relay console is dark before the generator", _label().contains("dark") and not relay.powered(), _label())
	Game.mission_stage["aux_power"] = 1
	await _frames(3)
	_check("with the generator back the console can be read", _label().contains("traffic log"), _label())
	await _press("interact")
	await _frames(3)
	_check("reading it locates the listening post", relay.console_read() and main.quests.state_of("listening_post") == QuestLog.ACTIVE)
	var marks: Array = main.quests.markers()
	_check("the post is marked for the journal and map", marks.any(func(m): return m["id"] == "listening_post"), str(marks))
	_check("the console only reads once", _label() == "" or not _label().contains("traffic log"), _label())
	# The relay's middle stage (milestone A): read the switchbox lamps, one of three is a decoy.
	var listen: Dictionary = relay.mission[1]
	_check("the relay asks Juno to pick the live switchboxes", listen.get("decoys", []) == [0] and (listen["devices"] as Array).size() == 3)
	_clear_enemies()
	Game.reset()


func _landmarks() -> void:
	Game.reset()
	_clear_enemies()
	var lm: Landmarks = main.landmarks
	var top := -INF
	for n in lm.split.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		top = maxf(top, (mi.global_transform * mi.get_aabb().get_center()).y)
	_check("the Split towers over the rim", top > 35.0, "top %.1f" % top)
	var gate: Node3D = main.regions.gates["shatterlands"]
	_check("the Split stands either side of the canyon", lm.split.global_position.distance_to(Vector3(gate.global_position.x, 0.0, gate.global_position.z)) < 0.1)
	var names: Array = main.map_panel.marks().filter(func(m): return m["kind"] == "landmark").map(func(m): return m["label"])
	_check("the map names both landmarks", names.has("The Split") and names.has("The Chimney"), str(names))
	var g := lm.chimney
	_check("the Chimney sits on the basin floor", absf(g.global_position.y - main.site.height_at(g.global_position.x, g.global_position.z)) < 0.1)
	for id in main.sites:
		var site: Node3D = main.sites[id]
		_check("the Chimney is clear of the %s site" % id, _flat_distance(site.global_position, g.global_position) > 25.0)
	for id in main.discoveries.built:
		_check("the Chimney is clear of %s" % id, _flat_distance(main.discoveries.built[id].global_position, g.global_position) > 20.0)
	# Stand on the vent and let it go.
	g.set_time(Geyser.IDLE + Geyser.RUMBLE - 0.3)
	_place(g.vent_point() + Vector3(0.0, 0.3, 0.0), 0.0)
	player.velocity = Vector3.ZERO
	await _frames(5)
	var start_y := player.global_position.y
	var hp := player.health
	var peak := start_y
	for i in 90:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	_check("the Chimney throws Juno high", g.launches == 1 and peak - start_y > 8.0, "rose %.1f m" % (peak - start_y))
	await _frames(120)
	_check("and she comes down unhurt", not player.dead and player.health >= hp, "health %.1f -> %.1f" % [hp, player.health])
	_check("one burst throws her once", g.launches == 1)
	Game.reset()


func _drifters() -> void:
	Game.reset()
	_clear_enemies()
	var at := Vector3(12.0, 0.0, 12.0)
	at.y = main.site.height_at(at.x, at.z)
	_place(at + Vector3(0.0, 0.5, 0.0), 0.0)
	player.velocity = Vector3.ZERO
	await _frames(5)
	var d: Drifter = main.spawn_enemy("drifter", at + Vector3(11.0, 3.0, 0.0))
	await get_tree().create_timer(1.0).timeout
	var ground: float = main.site.height_at(d.global_position.x, d.global_position.z)
	_check("a drifter hangs in the air", d.global_position.y - ground > 1.5, "%.1f m up" % (d.global_position.y - ground))
	var hp := player.health
	var t := 0.0
	var swelled := false
	while t < 14.0 and d.bursts == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		swelled = swelled or d.state == Drifter.State.SWELL
		player.global_position = at + Vector3(0.0, 0.1, 0.0)
	_check("it drifts in, swells, and bursts on Juno", swelled and d.bursts == 1 and d.dead, "after %.1f s, bursts %d" % [t, d.bursts])
	_check("the burst hurts", player.health < hp - 5.0, "%.0f -> %.0f" % [hp, player.health])
	player.health = hp
	await _frames(30)
	# Shot over a pack, it takes the pack with it, and Juno, far off, is untouched.
	var far := at + Vector3(0.0, 0.0, -25.0)
	far.y = main.site.height_at(far.x, far.z)
	var bug: Enemy = main.spawn_enemy("scuttler", far + Vector3(0.0, 0.5, 0.0))
	var d2: Drifter = main.spawn_enemy("drifter", far + Vector3(0.6, 2.4, 0.0))
	var d3: Drifter = main.spawn_enemy("drifter", far + Vector3(-1.4, 2.6, 1.0))
	await _frames(3)
	var bug_hp := bug.health
	hp = player.health
	d2.take_damage(100.0, d2.global_position, Vector3.FORWARD)
	await _frames(3)
	_check("shot, it bursts where it hangs", d2.dead and d2.bursts == 1)
	_check("the cloud hurts the creatures under it", bug.dead or bug.health < bug_hp, "%.0f -> %.0f" % [bug_hp, bug.health])
	_check("and sets off its neighbours", d3.dead and d3.bursts == 1)
	_check("Juno, well away, takes nothing", player.health >= hp)
	_clear_enemies()
	Game.reset()
