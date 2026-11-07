extends "res://tests/test_base.gd"
## Expansion foundations (X1): saves from older builds are upgraded rather than dropped, a newer
## build's save is refused, and the expansion state (region, act, flags, quests) survives a save
## and load. Run:
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
	var bad := QuestDB.validate(["kettle"], main.wildlife.caches.size())
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
