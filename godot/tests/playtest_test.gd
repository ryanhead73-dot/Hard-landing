extends Node
## M13.10 playtest kit: the session log records objectives, deaths, areas and F8 flags, and
## writes a readable timeline. Run:
##   godot --headless --path . res://tests/playtest_test.tscn

var failures := 0


func _ready() -> void:
	Game.save_path = "user://playtest_test_scratch.json"
	Game.reset()
	Game.pending_load = {}
	Game.intro_pending = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	await get_tree().create_timer(0.3).timeout
	_check("tests and the benchmark are not recorded", main.playtest == null)
	main._start_playtest(false, true)
	var log: PlaytestLog = main.playtest
	_check("a forced session starts recording", log != null and log.events[0]["kind"] == "start")
	_check("the start names difficulty and preset", log.events[0]["text"].contains(Game.GRAPHICS_NAMES[Game.graphics]))
	_check("Juno starts at Kestrel", log.area_at(main.SPAWN) == "Kestrel", log.area_at(main.SPAWN))
	var relay: Node3D = main.sites["aux_power"]
	_check("the relay is its own area", log.area_at(relay.global_position) == "Relay Station", log.area_at(relay.global_position))
	await get_tree().create_timer(0.6).timeout
	var first: String = log.events.filter(func(e): return e["kind"] == "objective")[0]["text"]
	Game.objective_changed.emit("A test objective")
	var done: Array = log.events.filter(func(e): return e["kind"] == "objective_done")
	_check("a finished objective records how long it took", done.size() == 1 and done[0]["objective"] == first and done[0]["seconds"] > 0.3, str(done))
	main.player.revive(relay.global_position + Vector3(0, 1, 8))
	await get_tree().create_timer(0.3).timeout
	_check("moving to the relay logs the area change", log.events.any(func(e): return e["kind"] == "area" and e["text"] == "Relay Station"))
	main.player.take_damage(40.0)
	main.player.take_damage(9999.0)
	var deaths: Array = log.events.filter(func(e): return e["kind"] == "death")
	_check("a death is logged with where and why", deaths.size() == 1 and deaths[0]["area"] == "Relay Station" and deaths[0]["text"].contains("damage in the last 10 s"), str(deaths))
	_check("damage and deaths add up by area", log.areas["Relay Station"]["deaths"] == 1 and log.areas["Relay Station"]["damage"] > 40.0, str(log.areas))
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F8
	key.pressed = true
	log._unhandled_key_input(key)
	_check("F8 flags the moment", log.flags == 1 and log.events[-1]["kind"] == "flag")
	_check("the flag is confirmed on screen", main.hud.message_age() < 0.5)
	var json := FileAccess.get_file_as_string(log.file_base + ".json")
	var txt := FileAccess.get_file_as_string(log.file_base + ".txt")
	var data = JSON.parse_string(json)
	_check("the session is saved as JSON", data is Dictionary and data["deaths"] == 1 and data["flags"] == 1, json.left(200))
	_check("and as a readable timeline", txt.contains("DEATH") and txt.contains("FLAG") and txt.contains("Where the time went"), txt)
	print(PlaytestLog.timeline(log.report()))
	var base := log.file_base
	main.queue_free()
	await get_tree().process_frame
	_check("the session closes with an end event", FileAccess.get_file_as_string(base + ".txt").contains("END"))
	DirAccess.remove_absolute(base + ".json")
	DirAccess.remove_absolute(base + ".txt")
	print("PLAYTEST TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures else 0)


func _check(what: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", what, detail if not ok else ""])
	if not ok:
		failures += 1
