class_name Benchmark
extends Node
## A fixed run through the slice that measures frame times. It covers the crash site, a flight
## over the basin, a fight at the relay, the lit workshop and a storm. It writes a report to
## user://benchmarks/ and shows a summary.
##
## Start it from the title screen (Benchmark), or with `-- --benchmark` on the command line.
## The target is a GTX 1660-class card at 1080p on the Medium preset: 60 fps on average, with
## the 1% lows at 45 fps or better.

signal done(report: Dictionary)

const SEGMENTS := [
	{"name": "Crash site", "seconds": 12.0},
	{"name": "Basin flight", "seconds": 12.0},
	{"name": "Relay fight", "seconds": 15.0},
	{"name": "Workshop", "seconds": 10.0},
	{"name": "Storm", "seconds": 10.0},
]
## Frames in each segment's first half second are not counted: the camera has just cut and
## streaming settles.
const SETTLE := 0.5
const TARGET_AVG_FPS := 60.0
const TARGET_LOW_FPS := 45.0

## Scales every segment's length (tests run it short).
var time_scale := 1.0
## Back to the title when done (off in tests).
var return_to_title := true
var report: Dictionary = {}
var main: Node
var _cam: Camera3D
var _summary: Label
var _shots := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var vsync := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Nothing in the run may touch the player's save.
	var save_path := Game.save_path
	Game.save_path = "user://benchmark_scratch.json"
	Game.reset()
	Game.pending_load = {}
	Game.intro_pending = false
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	main.day_cycle = false
	main.set_daylight(0.0)
	await _frames(30)
	_clear_enemies()
	main.voice.clear()
	_cam = Camera3D.new()
	_cam.fov = 70.0
	main.add_child(_cam)
	var segments: Array = []
	for seg in SEGMENTS:
		segments.append(await _segment(seg["name"], seg["seconds"] * time_scale))
	report = _report(segments)
	DisplayServer.window_set_vsync_mode(vsync)
	Game.save_path = save_path
	_save(report)
	print(_text(report))
	_show(report)
	done.emit(report)


func _segment(seg_name: String, seconds: float) -> Dictionary:
	var kestrel: Node3D = main.kestrel
	var relay: Node3D = main.sites["aux_power"]
	_clear_enemies()
	match seg_name:
		"Crash site":
			main.player.revive(main.SPAWN)
			_cam.make_current()
		"Basin flight":
			_cam.make_current()
		"Relay fight":
			main.player.revive(relay.to_global(Vector3(2.0, 0.5, 16.0)))
			main.player.camera().make_current()
			main.player.weapon.equip("rifle")
		"Workshop":
			kestrel.set_repaired("aux_power", true)
			main.player.revive(kestrel.to_global(kestrel.plan(13.0, 0.3, 14.5)))
			main.player.camera().make_current()
		"Storm":
			main.weather.enabled = true
			main.weather.start_storm(true)
			main.player.revive(main.SPAWN + Vector3(6.0, 0.0, 10.0))
			main.player.camera().make_current()
	var times := PackedFloat64Array()
	_shots = 0
	var draws := 0.0
	var t := 0.0
	var last := Time.get_ticks_usec()
	var refill := 0.0
	while t < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000000.0
		last = now
		t += dt
		var k := clampf(t / seconds, 0.0, 1.0)
		match seg_name:
			"Crash site":
				var a := k * TAU * 0.5
				var c := kestrel.global_position
				_cam.look_at_from_position(c + Vector3(cos(a) * 34.0, 9.0, sin(a) * 34.0), c + Vector3.UP * 2.0)
			"Basin flight":
				var from := kestrel.global_position + Vector3(0.0, 7.0, 0.0)
				var to := relay.global_position + Vector3(0.0, 7.0, 0.0)
				var p := from.lerp(to, k)
				_cam.look_at_from_position(p, p + (to - from).normalized() * 10.0 + Vector3.DOWN * 2.0)
			"Relay fight":
				_fight(relay, dt)
				refill -= dt
				if refill <= 0.0:
					refill = 1.0
					main.player.weapon.refill()
			"Workshop", "Storm":
				main.player.face(k * PI * 0.8)
		if t > SETTLE * minf(time_scale, 1.0):
			times.append(dt * 1000.0)
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	if seg_name == "Storm":
		main.weather.clear_storm(true)
		main.weather.enabled = false
	var stats := _stats(times)
	stats["name"] = seg_name
	stats["draw_calls"] = roundi(draws / maxf(1.0, times.size()))
	stats["shots"] = _shots
	return stats


## Juno holds the relay against a steady pack, shooting the nearest: wildlife AI, hit effects,
## casings and the HUD all working at once. She can't go down.
func _fight(relay: Node3D, _dt: float) -> void:
	var player: Node3D = main.player
	main.player.health = main.player.max_health()
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.size() < 5:
		var kinds := ["scuttler", "scuttler", "scuttler", "spitter"]
		for i in 6 - enemies.size():
			var a := randf() * TAU
			var at: Vector3 = player.global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(14.0, 20.0)
			main.spawn_enemy(kinds[i % kinds.size()], at)
	var nearest: Node3D = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if nearest == null or player.global_position.distance_to(e.global_position) < player.global_position.distance_to(nearest.global_position):
			nearest = e
	if nearest:
		var flat: Vector3 = nearest.global_position - player.global_position
		main.player.face(atan2(-flat.x, -flat.z))
		main.player.aim_at(nearest.global_position + Vector3.UP * 0.5)
		if main.player.weapon.try_fire(false):
			_shots += 1


static func _stats(times: PackedFloat64Array) -> Dictionary:
	if times.is_empty():
		return {"frames": 0, "avg_ms": 0.0, "avg_fps": 0.0, "p99_ms": 0.0, "low_fps": 0.0, "max_ms": 0.0, "hitches": 0}
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	var hitches := 0
	for ms in times:
		total += ms
		if ms > 50.0:
			hitches += 1
	var avg := total / times.size()
	var p99: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))]
	return {
		"frames": times.size(), "avg_ms": avg, "avg_fps": 1000.0 / avg, "p99_ms": p99, "low_fps": 1000.0 / p99,
		"max_ms": sorted[sorted.size() - 1], "hitches": hitches,
	}


func _report(segments: Array) -> Dictionary:
	var weighted := 0.0
	var frames := 0
	for s in segments:
		frames += s["frames"]
		weighted += s["avg_ms"] * s["frames"]
	var worst_low := INF
	for s in segments:
		if s["frames"] > 0:
			worst_low = minf(worst_low, s["low_fps"])
	var avg_ms := weighted / maxf(1.0, frames)
	var avg_fps := 1000.0 / avg_ms if avg_ms > 0.0 else 0.0
	return {
		"date": Time.get_datetime_string_from_system(),
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"engine": Engine.get_version_info()["string"],
		"os": OS.get_name(),
		"cpu": OS.get_processor_name(),
		"gpu": "%s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()],
		"driver": RenderingServer.get_video_adapter_api_version(),
		"resolution": "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"render_scale": get_viewport().scaling_3d_scale,
		"preset": Game.GRAPHICS_NAMES[Game.graphics],
		"segments": segments,
		"avg_fps": avg_fps,
		"worst_low_fps": worst_low if worst_low != INF else 0.0,
		"meets_target": avg_fps >= TARGET_AVG_FPS and worst_low >= TARGET_LOW_FPS,
	}


static func _text(r: Dictionary) -> String:
	var lines: PackedStringArray = [
		"HARD LANDING BENCHMARK  %s" % r["date"],
		"%s · %s · %s preset · Godot %s · %s" % [r["gpu"], r["resolution"], r["preset"], r["engine"], r["os"]],
		"CPU: %s · driver %s" % [r["cpu"], r["driver"]],
		"",
		"%-14s %8s %8s %10s %8s %8s %7s" % ["Segment", "Avg fps", "Avg ms", "1% low fps", "Max ms", "Hitches", "Draws"],
	]
	for s in r["segments"]:
		lines.append("%-14s %8.1f %8.2f %10.1f %8.1f %8d %7d" % [s["name"], s["avg_fps"], s["avg_ms"], s["low_fps"], s["max_ms"], s["hitches"], s["draw_calls"]])
	lines.append("")
	lines.append("Overall %.1f fps average, worst 1%% low %.1f fps. Target (Medium, 1080p): %d average, %d low: %s" % [
		r["avg_fps"], r["worst_low_fps"], TARGET_AVG_FPS, TARGET_LOW_FPS, "MET" if r["meets_target"] else "NOT MET"])
	return "\n".join(lines)


## Writes the report as text and JSON to user://benchmarks/ and remembers the path.
func _save(r: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://benchmarks")
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var base := "user://benchmarks/benchmark_%s_%s" % [String(r["preset"]).to_lower(), stamp]
	var f := FileAccess.open(base + ".txt", FileAccess.WRITE)
	if f:
		f.store_string(_text(r) + "\n")
		f.close()
	f = FileAccess.open(base + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(r, "  "))
		f.close()
	r["file"] = ProjectSettings.globalize_path(base + ".txt")


func _show(r: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	_summary = Label.new()
	_summary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_summary.offset_left = 120
	_summary.offset_right = -120
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary.add_theme_font_override("font", SystemFont.new())
	(_summary.get_theme_font("font") as SystemFont).font_names = PackedStringArray(["monospace", "Consolas", "DejaVu Sans Mono"])
	_summary.add_theme_font_size_override("font_size", 18)
	_summary.text = _text(r) + "\n\nSaved to %s\n\nPress any key to return to the title." % r.get("file", "")
	dim.add_child(_summary)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if report.is_empty() or not return_to_title:
		return
	if (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed():
		get_tree().change_scene_to_file("res://scenes/title.tscn")


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
