extends Node
## Saves written by the builds Jake has played (tests/fixtures/saves, made by running
## tools/make_save_fixtures on those commits: 767aeb7 = 07h, 30133c5 = 08 expansion, eb48fe3 =
## 09 missions, 114e918 = 09c loom, d1e5520 = 09d departure) load in this one: Juno is where the
## save was, the repairs match, there's an objective and a marker, and the part she's after can
## still be got and fitted. A part a Kettle-era save had in her arms that now comes from a region
## counts as sent home.

const DIR := "res://tests/fixtures/saves/"

var failures := 0
var main: Node


func _ready() -> void:
	Game.save_path = "user://test_saves_save.json"
	Game.difficulty = 1
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".json"):
			await _load(file)
	print("SAVES TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		failures += 1
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _load(file: String) -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + file))
	var f := FileAccess.open(Game.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	Game.reset()
	var data := Game.read_save()
	var tag := file.get_basename()
	_check("%s: reads" % tag, not data.is_empty())
	if data.is_empty():
		return
	Game.pending_load = data
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	await _frames(90)
	var region := String(data.get("region", "kettle"))
	_check("%s: back in %s" % [tag, region], main.regions.current == region, main.regions.current)
	var repaired: Dictionary = raw.get("repaired", {})
	var same := true
	for id in Kestrel.REPAIR_ORDER:
		if bool(repaired.get(id, false)) != Game.is_repaired(id):
			same = false
	_check("%s: the same repairs" % tag, same)
	_check("%s: an objective" % tag, Game.objective_text() != "", Game.objective_text())
	_check("%s: a marker" % tag, main._waypoint() is Vector3 or Game.phase() == "done", str(main._waypoint()))
	var cur := Game.current_repair()
	if cur != "":
		var comp: String = Campaign.get_repair(cur)["component"]
		if Campaign.sourced(cur) and main.regions.current != String(Campaign.SOURCED[cur]["region"]):
			_check("%s: %s comes from its region, not her arms" % [tag, cur], Game.carrying != comp, Game.carrying)
		_check("%s: %s's part can still be had" % [tag, cur], Game.phase() == "find" or Game.delivered(comp) or Game.carrying == comp, "%s carrying '%s'" % [Game.phase(), Game.carrying])
	_check("%s: the opening isn't replayed" % tag, not main.opening.active())
	main.queue_free()
	await _frames(5)
	Game.delete_save()
