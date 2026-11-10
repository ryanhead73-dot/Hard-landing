class_name SideJobs
extends Node
## Runs the optional jobs in SideJobDB: the givers (a lit survey post, or a greenhouse survivor),
## each job's current stage where Juno stands, a second HUD marker for the tracked job, and the
## flags the journal reads. Everything lives in Game.flags, so it saves with the session:
## job_<id>_taken, job_<id>_s<i> per stage done, job_<id>_s<i>_<k> per point worked.

const USE_RANGE := 2.4
const GIVER_RANGE := 2.8
## A hold stage gives Juno this long outside its ring before it starts over.
const STRAY_TIME := 6.0
const TEAL := Color("5fd6c0")

var main: Node
## The job the HUD's second marker follows ("" for none).
var tracked := ""
## Props for the region Juno is in, rebuilt on every trip.
var _props: Node3D
var _beacons := {}
## job id -> Array[Enemy] spawned for its current stage.
var _foes := {}
## Stages whose foes or guards came out this visit: "<id>:<i>" -> true.
var _spawned := {}
## The running hold: {job, stage, t, wave_t, wave, stray}, or empty.
var _hold := {}
var _ring: MeshInstance3D
var _rebuild_queued := false


func setup(m: Node) -> void:
	main = m
	main.regions.travelled.connect(_on_travelled)
	main.player.died.connect(_on_player_died)
	Game.flag_changed.connect(_on_flag_changed)
	tracked = String(Game.flags.get("job_tracked", ""))
	_rebuild.call_deferred()


# --- State ------------------------------------------------------------------------------------

func available(id: String) -> bool:
	var j := SideJobDB.get_job(id)
	if taken(id) or j.is_empty():
		return false
	for c in j["requires"]:
		if not main.quests.holds(c):
			return false
	return true


func taken(id: String) -> bool:
	return Game.flags.get(SideJobDB.taken_flag(id), false) == true


func done(id: String) -> bool:
	var j := SideJobDB.get_job(id)
	return taken(id) and stage_index(id) >= (j["stages"] as Array).size()


## The first stage not yet done.
func stage_index(id: String) -> int:
	var j := SideJobDB.get_job(id)
	var n := (j["stages"] as Array).size()
	for i in n:
		if not Game.flags.get(SideJobDB.stage_flag(id, i), false):
			return i
	return n


func stage(id: String) -> Dictionary:
	var j := SideJobDB.get_job(id)
	var i := stage_index(id)
	return j["stages"][i] if i < (j["stages"] as Array).size() else {}


func running() -> Array[String]:
	var out: Array[String] = []
	for j in SideJobDB.JOBS:
		if taken(j["id"]) and not done(j["id"]):
			out.append(String(j["id"]))
	return out


## "Pull the data cores (1/3)": the current stage's line.
func stage_text(id: String) -> String:
	var s := stage(id)
	if s.is_empty():
		return ""
	var text := String(s["text"])
	if s["type"] == "use" and text.contains("%d"):
		var pts: Array = s["points"]
		text = text % [_points_done(id, stage_index(id)), pts.size()]
	return text


func accept(id: String) -> void:
	if not available(id):
		return
	var j := SideJobDB.get_job(id)
	Game.set_flag(SideJobDB.taken_flag(id))
	_track(id)
	main.voice.say(j["giver"].get("offer", []))
	Sfx.play("signal_ping", null, -6.0, 0.0)
	_stage_started(id)


func _track(id: String) -> void:
	tracked = id
	Game.set_flag("job_tracked", id)


func _complete_stage(id: String) -> void:
	var i := stage_index(id)
	var j := SideJobDB.get_job(id)
	var s: Dictionary = j["stages"][i]
	_foes.erase(id)
	if not _hold.is_empty() and _hold["job"] == id:
		_end_hold()
	Game.set_flag(SideJobDB.stage_flag(id, i))
	if s.has("say"):
		main.voice.say(s["say"])
	if done(id):
		Sfx.play("relay_two_note", null, -6.0, 0.0)
		if tracked == id:
			var rest := running()
			_track(rest[0] if not rest.is_empty() else "")
	else:
		Sfx.play("signal_ping", null, -8.0, 0.0)
		_stage_started(id)
	_rebuild()


func _stage_started(id: String) -> void:
	main.hud.show_message("%s: %s" % [SideJobDB.get_job(id)["title"], stage_text(id)])


func _points_done(id: String, i: int) -> int:
	var n := 0
	var s: Dictionary = SideJobDB.get_job(id)["stages"][i]
	for k in (s.get("points", []) as Array).size():
		if Game.flags.get(SideJobDB.point_flag(id, i, k), false):
			n += 1
	return n


# --- Where things are -------------------------------------------------------------------------

func _here() -> String:
	return main.regions.current


func _origin(region: String) -> Vector3:
	if region == "kettle":
		return Vector3.ZERO
	return RegionDB.get_region(region).get("origin", Vector3.ZERO)


## A region-local point as a world position on the ground (plus its own y).
func at(region: String, local: Vector3) -> Vector3:
	var w := _origin(region) + Vector3(local.x, 0.0, local.z)
	return Vector3(w.x, _ground(w) + local.y, w.z)


func _ground(w: Vector3) -> float:
	if _here() == "kettle":
		return main.site.height_at(w.x, w.z)
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(w.x, w.y + 30.0, w.z), Vector3(w.x, w.y - 10.0, w.z), Game.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else w.y


func giver_point(id: String):
	var g: Dictionary = SideJobDB.get_job(id)["giver"]
	if String(g["region"]) != _here():
		return null
	if g.has("npc"):
		var scene = main.regions.scene
		var gh = scene.get("greenhouses") if scene else null
		if gh == null:
			return null
		if g["npc"] == "Reyes":
			return gh.reyes.global_position if gh.reyes and gh.reyes.visible else null
		for p in gh.survivors:
			if p.name == g["npc"]:
				return p.global_position
		return null
	return at(String(g["region"]), g["pos"])


## Where the HUD's job marker points: the tracked job's next thing in this region, or null.
func waypoint():
	if tracked == "" or done(tracked) or not taken(tracked):
		return null
	var j := SideJobDB.get_job(tracked)
	var s := stage(tracked)
	if SideJobDB.stage_region(j, s) != _here():
		return null
	var region := _here()
	match String(s["type"]):
		"reach", "clear", "hold":
			return at(region, s["pos"]) + Vector3.UP
		"use":
			var best = null
			var best_d := INF
			var pts: Array = s["points"]
			for k in pts.size():
				if Game.flags.get(SideJobDB.point_flag(tracked, stage_index(tracked), k), false):
					continue
				var p := at(region, pts[k])
				var d: float = p.distance_to(main.player.global_position)
				if d < best_d:
					best_d = d
					best = p + Vector3.UP
			return best
		"report":
			var g = giver_point(tracked)
			return g + Vector3.UP * 1.5 if g != null else null
	return null


# --- Prompts ------------------------------------------------------------------------------------

func interaction(pos: Vector3) -> Dictionary:
	for j in SideJobDB.JOBS:
		var id: String = j["id"]
		if available(id):
			var g = giver_point(id)
			if g != null and pos.distance_to(g) < GIVER_RANGE:
				return {"label": prompt(id, false), "action": accept.bind(id)}
			continue
		if not taken(id) or done(id):
			continue
		var s := stage(id)
		if SideJobDB.stage_region(j, s) != _here():
			continue
		var i := stage_index(id)
		match String(s["type"]):
			"use":
				var pts: Array = s["points"]
				for k in pts.size():
					if Game.flags.get(SideJobDB.point_flag(id, i, k), false):
						continue
					if pos.distance_to(at(_here(), pts[k])) < USE_RANGE:
						var hold := float(s.get("hold", 0.0))
						if hold > 0.0:
							return {"label": "[Hold E] %s" % s["label"], "hold": hold, "action": _use.bind(id, i, k)}
						return {"label": "[E] %s" % s["label"], "action": _use.bind(id, i, k)}
			"hold":
				if _hold.is_empty() and pos.distance_to(at(_here(), s["pos"])) < USE_RANGE + 0.6:
					return {"label": "[E] %s" % s["label"], "action": _start_hold.bind(id, i)}
			"report":
				var g = giver_point(id)
				if g != null and pos.distance_to(g) < GIVER_RANGE:
					return {"label": prompt(id, true), "action": _complete_stage.bind(id)}
	return {}


## A survivor's prompt stays "Talk to <name>" (with the job's mark); a post says what it is.
func prompt(id: String, report: bool) -> String:
	var g: Dictionary = SideJobDB.get_job(id)["giver"]
	if g.has("npc"):
		return "[E] Talk to %s ◇ %s" % [g["npc"], "report" if report else "work"]
	return "[E] Report: %s" % SideJobDB.get_job(id)["title"] if report else "[E] %s" % g["label"]


func _use(id: String, i: int, k: int) -> void:
	if stage_index(id) != i:
		return
	Game.set_flag(SideJobDB.point_flag(id, i, k))
	_track(id)
	main.player.anim.play("interact")
	Sfx.play("scrap_pickup", null, -4.0, 0.0)
	var s: Dictionary = SideJobDB.get_job(id)["stages"][i]
	if _points_done(id, i) >= (s["points"] as Array).size():
		_complete_stage(id)
	else:
		main.hud.show_message(stage_text(id))
		_rebuild()


# --- Running ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null or main.player.dead:
		return
	var pos: Vector3 = main.player.global_position
	for id in running():
		var j := SideJobDB.get_job(id)
		var s := stage(id)
		if SideJobDB.stage_region(j, s) != _here():
			continue
		var key := "%s:%d" % [id, stage_index(id)]
		if s.has("guards") and not _spawned.has(key + "g"):
			_spawned[key + "g"] = true
			for g in s["guards"]:
				_spawn(id, String(g[0]), g[1], false)
		match String(s["type"]):
			"reach":
				if pos.distance_to(at(_here(), s["pos"])) < float(s.get("radius", 4.0)):
					_complete_stage(id)
			"clear":
				if not _spawned.has(key):
					if float(s.get("trigger", 30.0)) <= 0.0 or pos.distance_to(at(_here(), s["pos"])) < float(s.get("trigger", 30.0)):
						_spawned[key] = true
						for sp in s["spawns"]:
							_spawn(id, String(sp[0]), sp[1], true)
				elif _foes_left(id) == 0:
					_complete_stage(id)
	if not _hold.is_empty():
		_run_hold(delta)


func _spawn(id: String, kind: String, local: Vector3, count: bool) -> Enemy:
	var parent: Node = main.regions.scene if _here() != "kettle" else null
	var w := at(_here(), local)
	w.y = maxf(w.y, _ground(w) + 0.5)
	var e: Enemy = main.spawn_enemy(kind, w, "", parent)
	if count:
		if not _foes.has(id):
			_foes[id] = []
		_foes[id].append(e)
	return e


func _foes_left(id: String) -> int:
	var n := 0
	for e in _foes.get(id, []):
		if is_instance_valid(e) and not (e as Enemy).dead:
			n += 1
	return n


func _start_hold(id: String, i: int) -> void:
	_hold = {"job": id, "stage": i, "t": 0.0, "wave_t": 2.0, "wave": 0, "stray": 0.0}
	_track(id)
	var s := stage(id)
	_show_ring(at(_here(), s["pos"]), float(s["radius"]))
	Sfx.play("power_up", null, -6.0, 0.0)
	main.hud.show_message("Hold the ring: %d s" % int(s["seconds"]))


func hold_ratio() -> float:
	if _hold.is_empty():
		return -1.0
	return float(_hold["t"]) / float(stage(_hold["job"])["seconds"])


func _run_hold(delta: float) -> void:
	var id: String = _hold["job"]
	var s := stage(id)
	if s.is_empty() or s["type"] != "hold" or SideJobDB.stage_region(SideJobDB.get_job(id), s) != _here():
		_end_hold()
		return
	var centre := at(_here(), s["pos"])
	if main.player.global_position.distance_to(centre) > float(s["radius"]):
		_hold["stray"] += delta
		if _hold["stray"] > STRAY_TIME:
			_fail_hold("Too far from the sensor: the calibration started over")
			return
	else:
		_hold["stray"] = 0.0
	_hold["t"] += delta
	_hold["wave_t"] -= delta
	if _hold["wave_t"] <= 0.0:
		_hold["wave_t"] = float(s.get("every", 10.0))
		var waves: Array = s["waves"]
		var from: Array = s["from"]
		var wave: Array = waves[int(_hold["wave"]) % waves.size()]
		for n in wave.size():
			var e := _spawn(id, String(wave[n]), from[(int(_hold["wave"]) + n) % from.size()], true)
			e.alert(false)
		_hold["wave"] += 1
	main.hud.set_task(hold_ratio(), String(SideJobDB.get_job(id)["title"]).to_upper())
	if _hold["t"] >= float(s["seconds"]):
		main.hud.set_task(-1.0)
		_complete_stage(id)


func _fail_hold(why: String) -> void:
	_end_hold()
	main.hud.show_message(why)


func _end_hold() -> void:
	_hold = {}
	if _ring:
		_ring.visible = false
	if main and main.hud:
		main.hud.set_task(-1.0)


func _on_player_died() -> void:
	if not _hold.is_empty():
		_fail_hold("")


func _show_ring(centre: Vector3, radius: float) -> void:
	if _ring == null:
		_ring = MeshInstance3D.new()
		var m := TorusMesh.new()
		m.rings = 48
		m.ring_segments = 6
		_ring.mesh = m
		_ring.material_override = Vfx.glow(TEAL, 2.0)
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	(_ring.mesh as TorusMesh).inner_radius = radius - 0.12
	(_ring.mesh as TorusMesh).outer_radius = radius
	_ring.global_position = centre + Vector3.UP * 0.1
	_ring.visible = true


func ring_visible() -> bool:
	return _ring != null and _ring.visible


## A new place: whatever was spawned for a stage is gone with the old one, so it comes out again.
func _on_travelled(_from: String, _to: String) -> void:
	_spawned.clear()
	_foes.clear()
	if not _hold.is_empty():
		_end_hold()
	_rebuild.call_deferred()


func _on_flag_changed(id: String, _value: Variant) -> void:
	# A requirement coming true can put a new giver's light up.
	if not id.begins_with("job_") and not _rebuild_queued:
		_rebuild_queued = true
		_rebuild.call_deferred()


# --- Props --------------------------------------------------------------------------------------

## The lights where jobs are on offer and where the current stages' points wait, for this region.
func _rebuild() -> void:
	_rebuild_queued = false
	if main == null:
		return
	if _props and is_instance_valid(_props):
		_props.queue_free()
	_props = Node3D.new()
	_props.name = "JobProps"
	add_child(_props)
	_beacons.clear()
	var here := _here()
	if here == "approach":
		return
	for j in SideJobDB.JOBS:
		var id: String = j["id"]
		var g: Dictionary = j["giver"]
		if String(g["region"]) == here and g.has("pos") and (available(id) or taken(id)):
			_post(at(here, g["pos"]), available(id) or (taken(id) and stage(id).get("type", "") == "report"))
		if not taken(id) or done(id):
			continue
		var s := stage(id)
		if SideJobDB.stage_region(j, s) != here or s["type"] != "use":
			continue
		var pts: Array = s["points"]
		for k in pts.size():
			if not Game.flags.get(SideJobDB.point_flag(id, stage_index(id), k), false):
				_crate(at(here, pts[k]))
	# A survivor with a job to give or a report to hear wears a small teal light.
	for j in SideJobDB.JOBS:
		var id: String = j["id"]
		if not j["giver"].has("npc") or String(j["giver"]["region"]) != here:
			continue
		if available(id) or (taken(id) and stage(id).get("type", "") == "report"):
			var p = giver_point(id)
			if p != null:
				_diamond(p + Vector3.UP * 2.3)


func _post(p: Vector3, lit: bool) -> void:
	var post := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.25, 1.6, 0.25)
	post.mesh = m
	post.material_override = Vfx.glow(Color("4a5052"), 0.0)
	post.position = p + Vector3.UP * 0.8
	_props.add_child(post)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.5, 0.35, 0.3)
	head.mesh = hm
	head.material_override = Vfx.glow(TEAL if lit else Color("2c3a38"), 2.5 if lit else 0.2)
	head.position = p + Vector3.UP * 1.75
	_props.add_child(head)
	if lit:
		_diamond(p + Vector3.UP * 2.3)


func _crate(p: Vector3) -> void:
	var box := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.7, 0.5, 0.5)
	box.mesh = m
	box.material_override = Vfx.glow(Color("8a7a5c"), 0.0)
	box.position = p + Vector3.UP * 0.25
	_props.add_child(box)
	var tag := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.72, 0.08, 0.52)
	tag.mesh = tm
	tag.material_override = Vfx.glow(TEAL, 2.0)
	tag.position = p + Vector3.UP * 0.42
	_props.add_child(tag)


## A small lit diamond over someone with work to give (no light: regions keep a light budget).
func _diamond(p: Vector3) -> void:
	var d := MeshInstance3D.new()
	var m := PrismMesh.new()
	m.size = Vector3(0.3, 0.4, 0.08)
	d.mesh = m
	d.material_override = Vfx.glow(TEAL, 3.0)
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.position = p
	d.rotation.z = PI
	_props.add_child(d)
	_beacons[p] = d
