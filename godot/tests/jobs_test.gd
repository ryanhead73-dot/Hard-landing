extends "res://tests/test_base.gd"
## Side jobs (SideJobDB / SideJobs): each one is offered once its requirements hold, shows in the
## journal, and can be worked to the end where it says (every point on open ground, clear of
## rock and hull), with its teal marker leading on, the scrap paid once and the quest done.

var rm: RegionManager
var jobs: SideJobs


func _name() -> String:
	return "JOBS TEST"


func _run() -> void:
	await _frames(10)
	Game.reset()
	rm = main.regions
	jobs = main.jobs
	_check("nothing's on offer at the start", SideJobDB.JOBS.all(func(j): return not jobs.available(j["id"])))
	for r in ["aux_power", "cooling", "canopy", "landing_gear", "wing", "engine"]:
		Game.set_repaired(r, true)
		kestrel.set_repaired(r, true)
	for f in ["shatterlands_open", "reached_greenhouses", "met_reyes", "nest_cleared", "greenhouse_open", "reyes_talked",
			"reached_gillwood", "found_ferro9", "ferro_canopy", "ferro_gear", "marigold_wing", "lamp_cell_fitted", "loom_open", "reached_loom", "loom_crown_seen", "weave_grips"]:
		Game.set_flag(f)
	await _frames(3)
	main.quests.refresh()
	await get_tree().process_frame
	_check("once the story's moved on, the first jobs are on offer", jobs.available("weather_eye") and jobs.available("east_glass") and jobs.available("survey_stakes"))
	_check("a job that follows another waits for it", not jobs.available("spindle_chord"))
	_check("the journal lists them as side quests", main.quests.state_of("job_weather_eye") == "active" and QuestDB.get_quest("job_weather_eye")["kind"] == "side", main.quests.state_of("job_weather_eye"))
	for id in ["weather_eye", "the_roost", "east_glass", "cap_watch", "brandt_flare", "stay_line", "survey_stakes", "spindle_chord", "voss_recorder", "spore_count", "ridge_watch", "old_warden"]:
		await _job(id)
	_check("every job is done", SideJobDB.JOBS.all(func(j): return jobs.done(j["id"]) and main.quests.is_done("job_" + j["id"])))
	_check("and nothing is tracked", jobs.tracked == "" and jobs.waypoint() == null)
	Game.delete_save()
	finished = true


func _go(region: String) -> void:
	if rm.current == region:
		return
	# The regions hang off each other: Kettle - Shatterlands - (Gillwood | Loom Expanse).
	if rm.current != "kettle" and region != "kettle" and rm.parent_of(rm.current) != region and rm.parent_of(region) != rm.current:
		rm.travel(rm.parent_of(rm.current), true)
		await _wait_travel()
	if rm.current == "kettle" and region != "shatterlands" and region != "kettle":
		rm.travel("shatterlands", true)
		await _wait_travel()
	if rm.current != region and region == "kettle" and rm.current != "shatterlands":
		rm.travel("shatterlands", true)
		await _wait_travel()
	if rm.current != region:
		rm.travel(region, true)
		await _wait_travel()
	_clear_enemies()


func _wait_travel() -> void:
	await _frames(2)
	var t := 0.0
	while rm.travelling and t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _frames(10)


func _heal() -> void:
	if player.dead:
		player.revive(player.global_position)
	player.health = player.max_health()


## Open ground at a job's point: something to stand on, and no rock or hull in the way.
func _open_ground(region: String, local: Vector3) -> String:
	var w := jobs.at(region, Vector3(local.x, 0.0, local.z))
	var space := main.get_world_3d().direct_space_state
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(w + Vector3.UP * 1.0, w - Vector3.UP * 1.5, Game.LAYER_WORLD))
	if down.is_empty() and region != "kettle":
		return "no ground under %s" % local
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), w + Vector3.UP * 1.0)
	q.collision_mask = Game.LAYER_WORLD
	var hits := space.intersect_shape(q, 4)
	return "" if hits.is_empty() else "%s is inside %s" % [local, hits[0]["collider"].name]


func _job(id: String) -> void:
	var j := SideJobDB.get_job(id)
	var g: Dictionary = j["giver"]
	await _go(String(g["region"]))
	await _frames(5)
	main.quests.refresh()
	_check("%s: on offer" % id, jobs.available(id))
	var gp = jobs.giver_point(id)
	_check("%s: its giver is here" % id, gp != null)
	if gp == null:
		return
	if g.has("pos"):
		var why := _open_ground(String(g["region"]), g["pos"])
		_check("%s: the post stands on open ground" % id, why == "", why)
	_heal()
	_place((gp as Vector3) + Vector3(0.0, 0.3, 1.4), 0.0)
	await _frames(4)
	_check("%s: the giver offers it" % id, _label() == jobs.prompt(id, false), _label())
	await _press("interact")
	await _frames(2)
	_check("%s: taken and tracked" % id, jobs.taken(id) and jobs.tracked == id)
	var scrap := Game.scrap
	var stages: Array = j["stages"]
	for i in stages.size():
		var s: Dictionary = stages[i]
		var region := SideJobDB.stage_region(j, s)
		await _go(region)
		await _frames(4)
		_heal()
		var tag := "%s stage %d (%s)" % [id, i, s["type"]]
		_check("%s: the marker leads on" % tag, jobs.waypoint() is Vector3, str(jobs.waypoint()))
		match String(s["type"]):
			"reach":
				_place(jobs.at(region, s["pos"]) + Vector3(0.0, 0.3, 1.0), 0.0)
				await _frames(4)
			"use":
				var pts: Array = s["points"]
				for k in pts.size():
					var why := _open_ground(region, pts[k])
					_check("%s: point %d on open ground" % [tag, k], why == "", why)
					_place(jobs.at(region, pts[k]) + Vector3(0.0, 0.3, 1.2), 0.0)
					await _frames(4)
					_check("%s: point %d prompts" % [tag, k], _label().contains(String(s["label"])), _label())
					if main._interaction.has("action"):
						(main._interaction["action"] as Callable).call()
					await _frames(2)
			"clear":
				var why := _open_ground(region, s["pos"])
				_check("%s: the fight's on open ground" % tag, why == "", why)
				_place(jobs.at(region, s["pos"]) + Vector3(0.0, 0.3, 6.0), 0.0)
				await _frames(6)
				var foes: Array = jobs._foes.get(id, [])
				_check("%s: they come out" % tag, foes.size() == (s["spawns"] as Array).size(), "%d" % foes.size())
				for e in foes:
					if is_instance_valid(e):
						(e as Enemy).take_damage(9999.0, (e as Enemy).global_position)
				await _frames(6)
			"hold":
				var why := _open_ground(region, s["pos"])
				_check("%s: the ring's on open ground" % tag, why == "", why)
				_place(jobs.at(region, s["pos"]) + Vector3(0.0, 0.3, 1.2), 0.0)
				await _frames(4)
				_check("%s: it starts here" % tag, _label().contains(String(s["label"])), _label())
				await _press("interact")
				await _frames(2)
				_check("%s: the ring is up" % tag, jobs.ring_visible() and jobs.hold_ratio() >= 0.0)
				jobs._hold["wave_t"] = 0.0
				await _frames(3)
				_check("%s: a wave comes" % tag, jobs._foes_left(id) > 0)
				_place(jobs.at(region, s["pos"]) + Vector3(float(s["radius"]) + 4.0, 0.3, 0.0), 0.0)
				jobs._hold["stray"] = SideJobs.STRAY_TIME - 0.05
				await _frames(6)
				_check("%s: straying too long starts it over" % tag, jobs.hold_ratio() < 0.0 and not jobs.ring_visible())
				_place(jobs.at(region, s["pos"]) + Vector3(0.0, 0.3, 1.2), 0.0)
				await _frames(3)
				await _press("interact")
				await _frames(2)
				jobs._hold["t"] = float(s["seconds"]) - 0.1
				await get_tree().create_timer(0.4).timeout
			"report":
				var rp = jobs.giver_point(id)
				_place((rp as Vector3) + Vector3(0.0, 0.3, 1.4), 0.0)
				await _frames(4)
				_check("%s: the giver hears the report" % tag, _label() == jobs.prompt(id, true), _label())
				await _press("interact")
				await _frames(2)
		_check("%s: done" % tag, Game.flags.get(SideJobDB.stage_flag(id, i), false) == true, jobs.stage_text(id))
	await _frames(3)
	main.quests.refresh()
	await get_tree().process_frame
	_check("%s: finished, paid %d scrap" % [id, j["scrap"]], jobs.done(id) and main.quests.is_done("job_" + id) and Game.scrap >= scrap + int(j["scrap"]), "scrap %d -> %d" % [scrap, Game.scrap])
