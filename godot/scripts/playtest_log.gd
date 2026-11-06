class_name PlaytestLog
extends Node
## Records a play session for playtest review: objectives with the time each took, deaths and
## where they happened, damage and time spent in each area, components, logs, frame rate, and
## moments the tester flags with F8. Written to user://playtests/ as JSON and a readable
## timeline every 30 seconds and when the session ends, so a crash loses at most half a minute.
## tools/playtest/summarise.py merges several sessions into one table.
##
## It runs whenever main.tscn is the current scene (a real session), not in tests or the
## benchmark, and keeps the latest KEEP sessions.

const DIR := "user://playtests"
const KEEP := 30
const FLUSH_EVERY := 30.0
const SAMPLE_EVERY := 1.0
## Within this distance of Kestrel the area is "Kestrel"; within SITE_RANGE of a site, that site.
const SHIP_RANGE := 30.0
const SITE_RANGE := 75.0
## An objective that runs longer than this is marked as a possible stuck point.
const LONG_OBJECTIVE := 300.0
const FLAG_KEY := KEY_F8

var main: Node
## True when the session picked up a save.
var continued := false
## Seconds of play (time paused in menus is not counted).
var clock := 0.0
var events: Array = []
var areas: Dictionary = {}
var deaths := 0
var flags := 0
var file_base := ""
var _objective := ""
var _objective_at := 0.0
var _objective_long := false
var _area := ""
var _area_at := 0.0
var _recent_damage: Array = []
var _frames := PackedFloat32Array()
var _frame_acc := 0.0
var _frame_count := 0
var _sample_acc := 0.0
var _flush_acc := 0.0
var _started := ""


## Whether a session in this tree should be recorded: only when main is the scene being played.
static func wanted(main_node: Node) -> bool:
	return main_node.is_inside_tree() and main_node.get_tree().current_scene == main_node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started = Time.get_datetime_string_from_system()
	var stamp := _started.replace(":", "").replace("-", "").replace("T", "_")
	file_base = "%s/session_%s" % [DIR, stamp]
	_objective = Game.objective_text()
	Game.objective_changed.connect(_on_objective)
	Game.carrying_changed.connect(func(item: String):
		if item != "":
			_event("pickup", item))
	Game.repairs_changed.connect(_on_repairs)
	Game.log_found.connect(func(id: String): _event("log", id))
	main.player.damaged.connect(_on_damaged)
	main.player.died.connect(_on_died)
	_event("start", "%s difficulty, %s preset%s" % [
		Game.DIFFICULTY_NAMES[Game.difficulty], Game.GRAPHICS_NAMES[Game.graphics],
		", continued from a save" if continued else ""])
	_event("objective", _objective)
	_prune()


func _process(delta: float) -> void:
	_frame_acc += delta
	_frame_count += 1
	_sample_acc += delta
	if _sample_acc >= SAMPLE_EVERY:
		_frames.append(_frame_count / _frame_acc)
		_frame_acc = 0.0
		_frame_count = 0
		_sample_acc = 0.0
	if get_tree().paused:
		return
	clock += delta
	var area := area_at(main.player.global_position)
	if area != _area:
		if _area != "":
			_event("area", area)
		_area = area
	var a: Dictionary = areas.get(area, {"seconds": 0.0, "damage": 0.0, "deaths": 0})
	a["seconds"] += delta
	areas[area] = a
	if not _objective_long and clock - _objective_at > LONG_OBJECTIVE:
		_objective_long = true
		_event("long_objective", "%d min on: %s" % [int(LONG_OBJECTIVE / 60.0), _objective])
	_flush_acc += delta
	if _flush_acc >= FLUSH_EVERY:
		_flush_acc = 0.0
		save()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == FLAG_KEY:
		flag()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if file_base != "" and not events.is_empty():
			_event("end", "")
			save()


## The tester marks this moment (F8): something confusing, annoying, broken or great.
func flag() -> void:
	flags += 1
	_event("flag", "#%d" % flags)
	if main.hud:
		main.hud.show_message("Moment %d flagged for the playtest notes." % flags)
	save()


## A plain name for where a point is: Kestrel, a site, or the wilds between them.
func area_at(p: Vector3) -> String:
	if main.kestrel and main.kestrel.is_inside_tree() and p.distance_to(main.kestrel.global_position) < SHIP_RANGE:
		return "Kestrel"
	var best := "Wilds"
	var best_d := SITE_RANGE
	for id in main.sites:
		var s: Node3D = main.sites[id]
		var d := p.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = String(s.name).capitalize()
	return best


func _on_objective(text: String) -> void:
	if text == _objective:
		return
	var took := clock - _objective_at
	_event("objective_done", "%s (%s)" % [_objective, _mmss(took)], {"objective": _objective, "seconds": took})
	_objective = text
	_objective_at = clock
	_objective_long = false
	_event("objective", text)


func _on_repairs() -> void:
	for r in Campaign.REPAIRS:
		var id: String = r["id"]
		if Game.is_repaired(id) and not events.any(func(e): return e["kind"] == "install" and e["text"] == id):
			_event("install", id)


func _on_damaged(amount: float) -> void:
	# A killing blow can overshoot; count at most a full health bar.
	amount = minf(amount, main.player.max_health())
	var a: Dictionary = areas.get(_area, {"seconds": 0.0, "damage": 0.0, "deaths": 0})
	a["damage"] += amount
	areas[_area] = a
	_recent_damage.append([clock, amount])


func _on_died() -> void:
	deaths += 1
	var a: Dictionary = areas.get(_area, {"seconds": 0.0, "damage": 0.0, "deaths": 0})
	a["deaths"] += 1
	areas[_area] = a
	var burst := 0.0
	for d in _recent_damage:
		if clock - d[0] <= 10.0:
			burst += d[1]
	_recent_damage.clear()
	var enemies := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Node3D).global_position.distance_to(main.player.global_position) < 25.0:
			enemies += 1
	_event("death", "%d damage in the last 10 s, %d enemies near" % [roundi(burst), enemies], {"enemies_near": enemies})


func _event(kind: String, text: String, extra := {}) -> void:
	var e := {"t": snappedf(clock, 0.1), "kind": kind, "text": text}
	if main and main.player and main.player.is_inside_tree():
		var p: Vector3 = main.player.global_position
		e["pos"] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]
		e["area"] = _area if _area != "" else area_at(p)
	e.merge(extra)
	events.append(e)


func report() -> Dictionary:
	var fps := _frames.duplicate()
	fps.sort()
	var avg := 0.0
	for f in fps:
		avg += f
	return {
		"started": _started,
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"os": OS.get_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"preset": Game.GRAPHICS_NAMES[Game.graphics],
		"difficulty": Game.DIFFICULTY_NAMES[Game.difficulty],
		"play_seconds": snappedf(clock, 0.1),
		"repairs_done": Game.repairs_done(),
		"deaths": deaths,
		"flags": flags,
		"fps_avg": snappedf(avg / fps.size(), 0.1) if fps.size() else 0.0,
		"fps_low": snappedf(fps[int(fps.size() * 0.05)], 0.1) if fps.size() else 0.0,
		"areas": areas,
		"events": events,
	}


static func timeline(r: Dictionary) -> String:
	var lines: PackedStringArray = [
		"HARD LANDING PLAYTEST  %s  (version %s)" % [r["started"], r["version"]],
		"%s · %s preset · %s difficulty" % [r["gpu"], r["preset"], r["difficulty"]],
		"Played %s · %d repairs · %d deaths · %d flags · %.0f fps average, %.0f fps low (5%%)" % [
			_mmss(r["play_seconds"]), r["repairs_done"], r["deaths"], r["flags"], r["fps_avg"], r["fps_low"]],
		"",
		"Where the time went:",
	]
	var names: Array = r["areas"].keys()
	names.sort_custom(func(a, b): return r["areas"][a]["seconds"] > r["areas"][b]["seconds"])
	for n in names:
		var a: Dictionary = r["areas"][n]
		lines.append("  %-22s %8s   %4d damage taken   %d deaths" % [n, _mmss(a["seconds"]), roundi(a["damage"]), a["deaths"]])
	lines.append("")
	lines.append("Timeline:")
	const LABELS := {
		"start": "START", "objective": "GOAL", "objective_done": "DONE", "area": "ENTER", "pickup": "PICKUP",
		"install": "INSTALL", "log": "LOG", "death": "DEATH", "flag": "FLAG", "long_objective": "STUCK?", "end": "END",
	}
	for e in r["events"]:
		lines.append("  %8s  %-8s %s" % [_mmss(e["t"]), LABELS.get(e["kind"], String(e["kind"]).to_upper()), e["text"]])
	return "\n".join(lines)


func save() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var r := report()
	var f := FileAccess.open(file_base + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(r, "  "))
		f.close()
	f = FileAccess.open(file_base + ".txt", FileAccess.WRITE)
	if f:
		f.store_string(timeline(r) + "\n")
		f.close()


## Keeps the newest KEEP sessions.
func _prune() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var jsons: Array = Array(dir.get_files()).filter(func(n: String): return n.begins_with("session_") and n.ends_with(".json"))
	jsons.sort()
	for i in maxi(0, jsons.size() - KEEP):
		var base: String = jsons[i].get_basename()
		dir.remove(base + ".json")
		dir.remove(base + ".txt")


static func _mmss(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
