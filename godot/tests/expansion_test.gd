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
