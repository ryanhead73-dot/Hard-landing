extends "res://tests/test_base.gd"
## Headless run through every repair's mission, stage by stage: devices stand on floors with room
## to work them, holds can be interrupted, defends pause when you leave, elites spawn and count,
## the Loom's resonators fail if a pulse lands mid-tune, and a save in the middle of a mission
## comes back where it left off. Run:
##   godot --headless --path . res://tests/missions_test.tscn

var runner: MissionRunner


func _name() -> String:
	return "MISSIONS TEST"


func _bypass_missions() -> bool:
	return false


func _run() -> void:
	runner = main.missions
	main.siege.enabled = false
	await _frames(30)
	_clear_enemies()
	_check("every repair has a mission of one or more stages", Campaign.REPAIRS.all(func(r): return runner.stage_count(r["id"]) >= 1))
	_check("first objective is a mission stage", Game.objective_text().contains("breakers"), Game.objective_text())
	_check_placement()
	for r in Campaign.REPAIRS:
		if r["id"] == "cooling":
			await _check_save_mid_mission()
		await _play_mission(r)
	_check("every repair done through its mission", Game.repairs_done() == 7, str(Game.repairs_done()))
	finished = true


## Every device sits on a floor and has a clear spot within reach where Juno can stand.
func _check_placement() -> void:
	var floating := []
	var boxed := []
	for id in runner.devices:
		for stage_devices in runner.devices[id]:
			for d in stage_devices:
				var p: Vector3 = d.global_position
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.4, p + Vector3.DOWN * 0.5, Game.LAYER_WORLD)
				q.exclude = [_device_body(d)]
				if main.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					floating.append("%s %s" % [id, d.kind])
				if _stand_spot(d) == Vector3.INF:
					boxed.append("%s %s at %s" % [id, d.kind, d.position])
	_check("every mission device stands on a floor", floating.is_empty(), str(floating))
	_check("every mission device has room to stand and work it", boxed.is_empty(), str(boxed))


func _device_body(d: Node) -> RID:
	for c in d.get_children():
		if c is StaticBody3D:
			return c.get_rid()
	return RID()


## A spot 1.2-1.6 m from the device where the player's capsule fits, with floor under it.
func _stand_spot(d: Node3D) -> Vector3:
	var space := main.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.7
	for dist in [1.3, 1.6, 1.0]:
		for i in 12:
			var a := TAU * i / 12.0
			var spot: Vector3 = d.global_position + Vector3(sin(a), 0.0, cos(a)) * dist
			var shape := PhysicsShapeQueryParameters3D.new()
			shape.shape = capsule
			shape.transform = Transform3D(Basis(), spot + Vector3.UP * 0.95)
			shape.collision_mask = Game.LAYER_WORLD
			if not space.intersect_shape(shape, 1).is_empty():
				continue
			var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.3, spot + Vector3.DOWN * 0.6, Game.LAYER_WORLD)
			if space.intersect_ray(q).is_empty():
				continue
			return spot
	return Vector3.INF


func _go_to_device(d: MissionDevice) -> void:
	var spot := _stand_spot(d)
	if spot == Vector3.INF:
		spot = d.global_position + Vector3(0.0, 0.0, 1.3)
	player.revive(spot + Vector3.UP * 0.1)
	var to := d.global_position - spot
	player.face(atan2(-to.x, -to.z))
	await _frames(8)


func _hold(seconds: float) -> void:
	await get_tree().physics_frame
	Input.action_press("interact")
	await get_tree().create_timer(seconds).timeout
	Input.action_release("interact")
	await _frames(3)


func _play_mission(r: Dictionary) -> void:
	var id: String = r["id"]
	var site: ExpeditionSite = main.sites[id]
	_clear_enemies()
	_check("%s: mission is current" % id, Game.current_repair() == id, Game.current_repair())
	player.revive(site.component_point() + Vector3.UP * 0.2)
	await _frames(8)
	_check("%s: component won't come free before the mission" % id, _label().contains("won't come free") or _label().begins_with("[Hold E]"), _label())
	await _press("interact")
	_check("%s: component stays put" % id, site.has_component() and Game.carrying == "")
	for si in range(runner.stage_index(id), runner.stage_count(id)):
		_clear_enemies()
		var s := runner.stage(id)
		_check("%s stage %d: objective shows the stage" % [id, si], Game.objective_text().begins_with(s["text"]), Game.objective_text())
		match s["type"]:
			"reach":
				player.revive(site.to_global(s["pos"]) + Vector3.UP * 0.2)
				await _frames(10)
			"activate", "pulse":
				if s.has("timer"):
					await _timed(id, si, s)
				await _work_devices(id, si, s)
			"defend":
				await _defend(id, si, s)
			"elite":
				await _elite(id, s)
			"search":
				await _search(id, si, s)
		_check("%s stage %d (%s) completes" % [id, si, s["type"]], runner.stage_index(id) == si + 1, "at %d" % runner.stage_index(id))
		if id == "cooling" and si == 0:
			var vents := (site as HaulerWreck).vents()
			_check("cooling: closing the valves shuts the vents", vents.all(func(v): return v.is_shut()))
	_clear_enemies()
	_check("%s: mission done, the component can be taken" % id, runner.can_take(id) and Game.objective_text() == r["find"], Game.objective_text())
	player.revive(site.component_point() + Vector3.UP * 0.2)
	await _frames(8)
	await _press("interact")
	_check("%s: component taken" % id, Game.carrying == r["component"], Game.carrying)
	_clear_enemies()
	for w in get_tree().get_nodes_in_group("enemies"):
		w.queue_free()
	kestrel.set_repaired(id, true)
	main.hud.show_boss(null)
	await _frames(5)


func _work_devices(id: String, si: int, s: Dictionary) -> void:
	var list: Array = runner.devices[id][si]
	_check("%s stage %d: devices are lit" % [id, si], range(list.size()).all(func(i): return list[i].state == (MissionDevice.State.DONE if i in Game.mission_done else MissionDevice.State.PENDING)))
	for i in list.size():
		var d: MissionDevice = list[i]
		if i in Game.mission_done:
			continue
		var spec: Dictionary = s["devices"][i]
		var hold: float = spec.get("hold", 0.0)
		await _go_to_device(d)
		_check("%s stage %d device %d: prompt" % [id, si, i], _label().contains(spec["label"]), _label())
		if hold <= 0.0:
			await _press("interact")
		else:
			if i == 0:
				# A short hold is not enough, and letting go cancels it.
				await _hold(hold * 0.4)
				_check("%s: letting go early cancels the hold" % id, d.state == MissionDevice.State.PENDING and runner.channel_ratio() < 0.0 and (not main.hud.task_visible() or runner.clock_ratio() >= 0.0))
				if s["type"] == "pulse":
					await _check_pulse_breaks(id, d, hold)
			if s["type"] == "pulse":
				await _wait_for_pulse(id)
				await _go_to_device(d)
			await _hold(hold + 0.4)
		_check("%s stage %d device %d: worked" % [id, si, i], d.state == MissionDevice.State.DONE or runner.stage_index(id) > si)


## A timed stage: the clock waits for Juno, harassers come with it, and running out undoes
## every device and starts the clock again.
func _timed(id: String, si: int, s: Dictionary) -> void:
	var site: ExpeditionSite = main.sites[id]
	var list: Array = runner.devices[id][si]
	# The climb ends right at the anchors, so the clock is already going: start it over as if
	# she had just come back from afar (a load, or a death).
	runner._stop_clock()
	player.revive(site.to_global(s["pos"]) + Vector3(0.0, 0.3, float(s.get("timer_range", MissionRunner.TIMER_RANGE)) + 25.0))
	await _frames(10)
	_check("%s: the clock waits until she's there" % id, runner.clock_ratio() < 0.0)
	var unreachable := range(list.size()).filter(func(i): return _stand_spot(list[i]) == Vector3.INF)
	_check("%s: every timed device can be reached" % id, unreachable.is_empty(), str(unreachable))
	await _go_to_device(list[0])
	var harassers := get_tree().get_nodes_in_group("enemies").filter(func(e): return e is Skimmer).size()
	_check("%s: the clock starts when she arrives" % id, runner.clock_ratio() > 0.9, "%.2f" % runner.clock_ratio())
	_check("%s: harassers come with the clock" % id, harassers >= s.get("harass", []).size(), str(harassers))
	_check("%s: the clock shows on the task bar" % id, main.hud.task_visible())
	_clear_enemies()
	await _frames(2)
	await _hold(float(s["devices"][0]["hold"]) + 0.4)
	_check("%s: a device locks against the clock" % id, 0 in Game.mission_done, str(Game.mission_done))
	var skiff_before: Vector3 = site.get("_skiff").position if site.get("_skiff") else Vector3.ZERO
	runner._clock = 0.05
	await _frames(4)
	_check("%s: running out undoes every device" % id, Game.mission_done.is_empty() and list[0].state == MissionDevice.State.PENDING and runner.slips() == 1, "%s, slips %d" % [Game.mission_done, runner.slips()])
	_check("%s: and the clock starts again" % id, runner.clock_ratio() > 0.9 and runner.stage_index(id) == si, "%.2f" % runner.clock_ratio())
	_check("%s: the harassers top back up" % id, get_tree().get_nodes_in_group("enemies").filter(func(e): return e is Skimmer and not e.is_queued_for_deletion()).size() >= s.get("harass", []).size())
	await get_tree().create_timer(0.8).timeout
	if site.get("_skiff"):
		_check("%s: the Lark lurches toward the brink" % id, (site.get("_skiff") as Node3D).position.distance_to(skiff_before) > 0.1)
	_clear_enemies()
	await _frames(3)


## A search: the waypoint only finds the area, the signal leads to the find, wrong spots pay
## scrap or wake a nest, and the right one ends the stage.
func _search(id: String, si: int, s: Dictionary) -> void:
	var site: ExpeditionSite = main.sites[id]
	var list: Array = runner.devices[id][si]
	var answer := int(s["answer"])
	var area := site.to_global(s["pos"])
	player.revive(area + Vector3(0.0, 0.3, MissionRunner.SEARCH_AREA + 12.0))
	await _frames(5)
	var far_point = runner.waypoint()
	_check("%s: from afar the waypoint finds the search area" % id, far_point is Vector3 and (far_point as Vector3).distance_to(area) < 0.1)
	var unreachable := range(list.size()).filter(func(i): return _stand_spot(list[i]) == Vector3.INF)
	_check("%s: every search spot can be reached" % id, unreachable.is_empty(), str(unreachable))
	var cold := 1.0
	var warm := 0.0
	for i in list.size():
		await _go_to_device(list[i])
		if i == answer:
			warm = runner.search_signal()
		else:
			cold = minf(cold, runner.search_signal())
	_check("%s: in the area the waypoint goes quiet" % id, runner.waypoint() == null)
	_check("%s: the signal is strongest at the find" % id, warm > 0.9 and warm > cold, "%.2f vs %.2f" % [warm, cold])
	_check("%s: the signal meter shows" % id, main.hud.task_visible())
	var empty := -1
	for i in list.size():
		if i != answer and not i in s.get("nests", []):
			empty = i
			break
	var scrap := Game.scrap
	await _go_to_device(list[empty])
	_check("%s: search prompt" % id, _label().contains(s["devices"][empty]["label"]), _label())
	await _hold(float(s["devices"][empty]["hold"]) + 0.4)
	_check("%s: a wrong spot turns up scrap, not the find" % id, Game.scrap == scrap + 4 and runner.stage_index(id) == si and list[empty].state == MissionDevice.State.DONE)
	if not s.get("nests", []).is_empty():
		var nest: int = s["nests"][0]
		var before := _enemy_count()
		await _go_to_device(list[nest])
		var nest_label := _label()
		await _hold(float(s["devices"][nest]["hold"]) + 0.4)
		_check("%s: a nested spot wakes the scuttlers" % id, _enemy_count() >= before + 3, "%d -> %d, '%s', state %d, done %s, msg '%s'" % [before, _enemy_count(), nest_label, list[nest].state, Game.mission_done, main.hud._message.text if "_message" in main.hud else "?"])
		_clear_enemies()
		await _frames(3)
	await _go_to_device(list[answer])
	await _hold(float(s["devices"][answer]["hold"]) + 0.4)


## The Loom pulse during a tune knocks it out.
func _check_pulse_breaks(id: String, d: MissionDevice, hold: float) -> void:
	var pulse: LoomPulse = main.sites[id].pulse
	await get_tree().physics_frame
	Input.action_press("interact")
	await _frames(20)
	pulse.fire()
	await _frames(5)
	var broke := d.state == MissionDevice.State.PENDING and runner.channel_ratio() < 0.0
	Input.action_release("interact")
	await _frames(3)
	_check("navigation: a pulse mid-tune breaks it", broke)


## Waits for a pulse to go out, so the next hold fits in the gap.
func _wait_for_pulse(id: String) -> void:
	var pulse: LoomPulse = main.sites[id].pulse
	pulse.fire()
	while pulse.radius >= 0.0:
		await get_tree().physics_frame
	await _frames(2)


func _defend(id: String, si: int, s: Dictionary) -> void:
	var d: MissionDevice = runner.devices[id][si][0]
	var site: ExpeditionSite = main.sites[id]
	await _go_to_device(d)
	_check("%s: defend prompt" % id, _label().contains(s["device"]["label"]), _label())
	await _press("interact")
	_check("%s: machine starts working" % id, runner.defending() and main.hud.task_visible())
	await get_tree().create_timer(2.6).timeout
	_check("%s: waves come in during the defend" % id, _enemy_count() >= 3, "enemies=%d" % _enemy_count())
	var before := runner.defend_ratio()
	_check("%s: progress builds while you hold the area" % id, before > 0.0, "%.2f" % before)
	player.revive(d.global_position + Vector3(0.0, 0.0, float(s["radius"]) + 6.0) + Vector3.UP * 0.5)
	await get_tree().create_timer(1.0).timeout
	_check("%s: progress pauses when you leave" % id, absf(runner.defend_ratio() - before) < 0.06, "%.2f -> %.2f" % [before, runner.defend_ratio()])
	if float(s.get("lift", 0.0)) > 0.0:
		_check("%s: the component hangs above its stand" % id, site._component.position.y > site.component_pos.y + 0.3)
	await _go_to_device(d)
	runner._defend_progress = float(s["seconds"]) - 0.4
	await get_tree().create_timer(1.0).timeout
	_check("%s: the component is down on its stand" % id, site._component.position.distance_to(site.component_pos) < 0.05)
	_clear_enemies()


func _elite(id: String, s: Dictionary) -> void:
	var site: ExpeditionSite = main.sites[id]
	player.revive(site.to_global(Vector3(0.0, 0.3, 12.0)))
	await _frames(10)
	var e := runner.elite()
	_check("%s: elite %s appears" % [id, s["name"]], e != null and is_instance_valid(e) and e.is_elite() and e.display_name() == s["name"])
	if e == null:
		runner.complete_stage()
		return
	_check("%s: elite is far tougher than its kind" % id, e.max_health >= Enemy.ELITE_MIN_HEALTH, "%.0f" % e.max_health)
	await _frames(5)
	_check("%s: elite gets a health bar" % id, main.hud.bar_visible())
	e.take_damage(99999.0, e.global_position, Vector3.FORWARD)
	await _frames(5)


## Saves halfway through the cooling mission (valves shut, one clamp cut) and loads it back.
func _check_save_mid_mission() -> void:
	runner.complete_stage()
	runner._complete_device(0)
	await _frames(3)
	var data: Dictionary = main.save_state()
	var stage_before: int = runner.stage_index("cooling")
	var done_before: Array = Game.mission_done.duplicate()
	main.queue_free()
	await _frames(3)
	Game.reset()
	Game.pending_load = JSON.parse_string(JSON.stringify(data))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.siege.enabled = false
	kestrel = main.kestrel
	player = main.player
	runner = main.missions
	await _frames(20)
	_check("save mid-mission: stage restored", runner.stage_index("cooling") == stage_before, str(runner.stage_index("cooling")))
	_check("save mid-mission: worked devices restored", Game.mission_done == done_before and runner.device("cooling", 1, 0).state == MissionDevice.State.DONE and runner.device("cooling", 1, 1).state == MissionDevice.State.PENDING, str(Game.mission_done))
	_check("save mid-mission: earlier stage effects restored", (main.sites["cooling"] as HaulerWreck).vents().all(func(v): return v.is_shut()))
	_check("save mid-mission: the earlier stage's devices show done", runner.devices["cooling"][0].all(func(d): return d.state == MissionDevice.State.DONE))
