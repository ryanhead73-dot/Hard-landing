extends Node
## M13.10 performance tooling: the benchmark runs every segment and writes a report, and the
## frame-rate readout toggles. (Headless numbers mean nothing; this checks the tool works.) Run:
##   godot --headless --path . res://tests/perf_test.tscn

var failures := 0


func _ready() -> void:
	var save_path := Game.save_path
	var bench: Benchmark = load("res://scenes/benchmark.tscn").instantiate()
	bench.time_scale = 0.15
	bench.return_to_title = false
	add_child(bench)
	var r: Dictionary = await bench.done
	var names: Array = r["segments"].map(func(s): return s["name"])
	_check("the benchmark runs every segment", names == Benchmark.SEGMENTS.map(func(s): return s["name"]), str(names))
	_check("every segment counts frames", r["segments"].all(func(s): return s["frames"] > 5 and s["avg_ms"] > 0.0 and s["low_fps"] > 0.0))
	var fight: Dictionary = r["segments"][2]
	_check("the relay fight has shooting in it", fight["shots"] > 3, "%d shots" % fight["shots"])
	_check("the report names the machine and preset", r["gpu"] != "" and r["preset"] == Game.GRAPHICS_NAMES[Game.graphics] and r.has("meets_target"))
	_check("the report is saved", FileAccess.file_exists(String(r["file"])) and FileAccess.get_file_as_string(String(r["file"])).contains("1% low"), str(r.get("file")))
	_check("the player's save is left alone", Game.save_path == save_path)
	print(Benchmark._text(r))
	var overlay: FpsOverlay = Game.get_children().filter(func(c): return c is FpsOverlay)[0]
	Game.show_fps = true
	Game.apply_settings()
	await get_tree().create_timer(0.5).timeout
	_check("F3 readout shows the frame rate", overlay.visible and overlay.label.text.contains("fps"), overlay.label.text)
	Game.show_fps = false
	Game.apply_settings()
	_check("and hides again", not overlay.visible)
	print("PERF TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures else 0)


func _check(what: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		failures += 1
