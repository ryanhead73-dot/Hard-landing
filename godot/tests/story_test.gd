extends "res://tests/test_base.gd"
## Milestone 3 story: the data holds together, logs are found where they should be and survive a
## save, HOB and Juno speak at the right moments, and the finale runs from engine spool through a
## failed and a held assault to the launch cinematic and the ending card. Run:
##   godot --headless --path . res://tests/story_test.tscn


func _name() -> String:
	return "STORY TEST"


func _run() -> void:
	await _frames(30)
	_clear_enemies()
	_data()
	_opening()
	await _logs()
	await _mission_lines()
	await _finale()
	finished = true


func _data() -> void:
	var ids := {}
	var sources := {}
	var bad: PackedStringArray = []
	for l in Story.LOGS:
		if ids.has(l["id"]):
			bad.append("duplicate id " + l["id"])
		ids[l["id"]] = true
		var key := "%s/%s" % [l["site"], l["source"]]
		if sources.has(key):
			bad.append("two logs at " + key)
		sources[key] = true
		if Campaign.index_of(l["site"]) < 0:
			bad.append("unknown site " + l["site"])
			continue
		var site: ExpeditionSite = main.sites[l["site"]]
		var src: String = l["source"]
		if src.begins_with("crate:") and int(src.substr(6)) >= site.crate_count():
			bad.append("%s has no crate %s" % [l["site"], src])
		elif not src.begins_with("crate:") and src != "component":
			bad.append("bad source " + key)
		if String(l["text"]).length() < 80:
			bad.append("%s is too short" % l["id"])
	_check("every log has a unique id and a real crate or component", bad.is_empty(), ", ".join(bad))
	var per_site := Campaign.REPAIRS.all(func(r): return Story.logs_at(r["id"]).size() >= 3 and Story.log_at(r["id"], "component") != "")
	_check("every site holds three or more logs, one with the component", per_site)
	_check("every repair has install lines", Campaign.REPAIRS.all(func(r): return Story.INSTALLED.has(r["id"]) and not Story.INSTALLED[r["id"]].is_empty()))
	_check("a siege line for each ordinary siege", Story.SIEGE.size() == ShipSiege.SIEGES.size())
	_check("line timing stays readable", Voice.duration("Go.") >= 2.5 and Voice.duration("x".repeat(400)) <= 9.0)


func _opening() -> void:
	_check("a new game opens with Juno", main.voice.history.size() > 0 and main.voice.history[0].begins_with("Juno:"), str(main.voice.history.slice(0, 1)))
	_check("subtitle shows on the HUD", main.hud.voice_text().contains("JUNO"), main.hud.voice_text())


func _logs() -> void:
	var relay: ExpeditionSite = main.sites["aux_power"]
	# Crate 0 at the relay holds Ilse's first log.
	player.revive(relay.crate_point(0) + (relay.component_point() - relay.crate_point(0)).normalized() * 1.2 + Vector3.UP * 0.3)
	await _frames(8)
	_check("crate offers a search", _label().contains("Search"), _label())
	await _press("interact")
	_check("searching crate 0 at the relay finds Ilse's first log", Game.has_log("relay_1"), str(Game.logs))
	# A crate without a log finds nothing new.
	var before := Game.logs.size()
	main._search_crate(relay, 1)
	_check("crate 1 holds no log", Game.logs.size() == before)
	# The component carries one too.
	player.revive(relay.component_point() + Vector3.UP * 0.3)
	await _frames(8)
	await _press("interact")
	_check("the cell carries Ilse's day-112 log", Game.has_log("relay_3") and Game.carrying == "aux_cell", str(Game.logs))
	_check("finding a log can't count twice", not Game.find_log("relay_3"))
	_clear_enemies()

	# L opens the newest log; the list shows all of them.
	await _press("logs")
	_check("L opens the newest log", main.logs_panel.is_open() and main.logs_panel.showing == "relay_3" and get_tree().paused)
	main.logs_panel.showing = ""
	main.logs_panel._refresh()
	_check("log list counts what's found", main.logs_panel._title.text.contains("2 / %d" % Story.LOGS.size()), main.logs_panel._title.text)
	main.logs_panel.close()
	_check("closing the log resumes the game", not get_tree().paused)

	# Logs survive a save.
	var data := Game.session_state()
	Game.reset()
	_check("reset clears logs", Game.logs.is_empty())
	Game.apply_session(data)
	_check("logs survive save and load", Game.has_log("relay_1") and Game.has_log("relay_3"))


func _mission_lines() -> void:
	player.revive(main.install_point("aux_power") + Vector3.UP * 0.2)
	await _frames(8)
	await _press("interact")
	_check("installing the cell brings HOB online", Game.is_repaired("aux_power") and main.voice.heard("HOB online"), main.voice.current_text())
	# The canopy repair arms a siege, and HOB calls it in.
	for id in ["cooling", "canopy"]:
		kestrel.set_repaired(id, true)
	main.siege.start(0)
	await _frames(2)
	_check("HOB calls the first siege", main.voice.heard("Contacts on the rim"))
	main.siege.damage_hull(ShipSiege.MAX_HULL)
	await _frames(2)
	_check("HOB reports a breach", main.voice.heard("Hull's breached"))
	main.siege.pending = -1
	_clear_enemies()


func _finale() -> void:
	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, true)
	main.siege.pending = -1
	player.revive(main.install_point("launch") + Vector3.UP * 0.2)
	await _frames(10)
	_check("the pilot's seat offers the engine spool", _label().contains("engine spool"), _label())
	_check("objective says to start the spool", Game.objective_text().contains("spool"), Game.objective_text())
	await _press("interact")
	var f: Finale = main.finale
	_check("spool starts the final assault", f.state == Finale.State.SPOOLING and main.siege.active == ShipSiege.FINALE and main.siege.siege_enemies().size() > 0)
	_check("objective: hold the hull", Game.objective_text().contains("Hold"), Game.objective_text())
	await _frames(5)
	_check("seat shows the spool while it runs", _label().contains("spooling"), _label())
	_check("top bar shows the spool", main.hud.bar_visible())

	# Waves keep coming: clearing one brings the next.
	var first_wave: int = main.siege.wave
	for e in main.siege.siege_enemies():
		e.queue_free()
	await get_tree().create_timer(ShipSiege.FINALE_WAVE_GAP + 0.6).timeout
	_check("the finale sends wave after wave", main.siege.wave > first_wave and main.siege.is_active(), "wave=%d" % main.siege.wave)

	f.spool = Finale.SPOOL_TIME * 0.5 + 0.1
	await _frames(3)
	_check("HOB calls the halfway mark", main.voice.heard("Halfway"))

	# A breach dumps the spool, with no scrap lost and no re-arm.
	Game.scrap = 40
	main.siege.damage_hull(ShipSiege.MAX_HULL)
	await _frames(3)
	_check("a breach dumps the spool", f.state == Finale.State.IDLE and f.spool == 0.0 and main.voice.heard("spool's dumped"))
	_check("HOB says the spool dumped, not the ordinary breach line", main.voice.current_text().contains("spool's dumped"), main.voice.current_text())
	_check("the finale breach costs no scrap and doesn't re-arm", Game.scrap == 40 and main.siege.pending == -1, "scrap=%d pending=%d" % [Game.scrap, main.siege.pending])
	_check("the seat offers the spool again", _label().contains("engine spool"), _label())

	# Second try, with an ordinary siege still armed: the finale folds it in.
	main.siege.arm(2, 5.0)
	await _press("interact")
	_check("starting the spool cancels a waiting siege", main.siege.pending == -1 and main.siege.active == ShipSiege.FINALE)
	f.spool = Finale.SPOOL_TIME - 0.05
	await _frames(6)
	_check("a full spool ends the assault", f.state == Finale.State.READY and not main.siege.is_active() and main.siege.siege_enemies().is_empty())
	_check("HOB calls for the launch", main.voice.current_text().contains("pilot's seat"), main.voice.current_text())
	_check("objective: get to the seat", Game.objective_text().contains("launch"), Game.objective_text())
	_check("the seat offers the launch", _label().contains("[E] Launch"), _label())
	await get_tree().create_timer(9.0).timeout
	_check("the wildlife runs off and is gone", _enemy_count() == 0, "left=%d" % _enemy_count())

	var y0 := kestrel.global_position.y
	await _press("interact")
	_check("launch starts the cinematic", Game.launched and f.state == Finale.State.LAUNCHING and main._cine_cam != null and main.get_viewport().get_camera_3d() == main._cine_cam)
	await _press("inventory")
	_check("no inventory during the cinematic", not main.inventory.is_open())
	await get_tree().create_timer(main.LIFT_TIME + 0.5).timeout
	_check("Kestrel lifts", kestrel.global_position.y > y0 + 4.0, "dy=%.1f" % (kestrel.global_position.y - y0))
	await get_tree().create_timer(main.CLIMB_TIME + 1.5).timeout
	_check("Kestrel climbs out", kestrel.global_position.y > y0 + 60.0, "dy=%.1f" % (kestrel.global_position.y - y0))
	_check("the ending card shows", main.ending_shown and main.hud.ending_visible() and main.hud.ending_text().contains("warning buoy"))
	_check("Ilse's orbital log arrives", Game.has_log("orbit") and main.hud.ending_text().contains("Ilse Marrow"))
