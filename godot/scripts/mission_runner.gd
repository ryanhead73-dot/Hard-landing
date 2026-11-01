class_name MissionRunner
extends Node
## Runs each repair's mission: the stages a site sets in its `mission` array, worked through in
## order before the component can be taken. Stage types:
##   reach    get within `radius` of `pos`.
##   activate work every device (E, or hold E for `hold` seconds; a hit or walking off interrupts).
##   pulse    as activate, but a Loom pulse during the hold knocks it out of tune.
##   defend   start the device, then stay within `radius` for `seconds` while waves come in.
##   elite    kill a named elite (`kind`, `name`, `pos`).
##   search   search spots (hold E) for the one thing hidden in one of them (`answer`); a signal
##            meter climbs as Juno closes on it, the waypoint only points at the area (`pos`)
##            until she is in it, and the wrong spots turn up scrap or (`nests`) a scuttler nest.
## After the last stage comes the implicit "take" stage. Stage index and the devices done in the
## current stage live in Game (mission_stage, mission_done) so they save with the session.

signal stage_completed(repair: String, index: int)

const REACH := 2.1
const HOLD_RANGE := 2.6
## Seconds between a defend stage's waves, unless the stage says otherwise.
const WAVE_EVERY := 10.0
## A search's signal meter: full at the hidden thing, nothing past this range.
const SIGNAL_RANGE := 30.0
## Inside this distance of a search area's centre the waypoint goes quiet.
const SEARCH_AREA := 20.0

## Tests that cover other systems skip missions: every component is takeable straight away.
var bypass := false

var main: Node
## repair id -> Array (per stage) of Array[MissionDevice].
var devices: Dictionary = {}

## The hold in progress: {stage, index, time, need, label}, or empty.
var _channel: Dictionary = {}
var _defend_running := false
var _defend_progress := 0.0
var _wave_timer := 0.0
var _wave_index := 0
var _elite: Enemy
var _ping_timer := 0.0
var _last_text := ""
var _last_repair := ""
## Sites whose opening lines have played this session.
var _intro_said: Dictionary = {}


func setup(game_main: Node) -> void:
	main = game_main
	for r in Campaign.REPAIRS:
		var id: String = r["id"]
		var site: ExpeditionSite = main.sites[id]
		var per_stage: Array = []
		for s in site.mission:
			var list: Array[MissionDevice] = []
			var specs: Array = s.get("devices", [])
			if s.has("device"):
				specs = [s["device"]]
			for spec in specs:
				var d := MissionDevice.new()
				d.kind = spec.get("kind", "breaker")
				d.position = spec["pos"]
				d.rotation.y = spec.get("yaw", 0.0)
				d.name = "Mission%s" % d.kind.capitalize()
				site.add_child(d)
				list.append(d)
			per_stage.append(list)
		devices[id] = per_stage
		var pulse = site.get("pulse")
		if pulse is LoomPulse:
			(pulse as LoomPulse).pulsed.connect(_on_pulse)
	main.player.damaged.connect(func(_amount): _interrupt("You were hit. Start again."))
	main.player.died.connect(_on_player_died)
	Game.repairs_changed.connect(_on_repairs_changed)
	_last_repair = Game.current_repair()
	refresh(false)


# --- Queries --------------------------------------------------------------------------------

func stage_index(id: String) -> int:
	var site: ExpeditionSite = main.sites.get(id)
	if site == null:
		return 0
	if bypass:
		return site.mission.size()
	return mini(int(Game.mission_stage.get(id, 0)), site.mission.size())


## The stage dictionary the repair is on; {"type": "take"} once the mission is done.
func stage(id: String) -> Dictionary:
	var site: ExpeditionSite = main.sites.get(id)
	var i := stage_index(id)
	if site == null or i >= site.mission.size():
		return {"type": "take"}
	return site.mission[i]


func can_take(id: String) -> bool:
	return stage(id)["type"] == "take"


func stage_count(id: String) -> int:
	return (main.sites[id] as ExpeditionSite).mission.size()


func device(id: String, stage_i: int, index: int) -> MissionDevice:
	return devices[id][stage_i][index]


## The text for the objective line, or "" when the campaign's own line applies.
func objective() -> String:
	var id := Game.current_repair()
	if id == "" or Game.carrying != "":
		return ""
	var s := stage(id)
	var text: String = s.get("text", "")
	match s["type"]:
		"activate", "pulse":
			var total: int = devices[id][stage_index(id)].size()
			if total > 1:
				text += " (%d/%d)" % [Game.mission_done.size(), total]
		"search":
			if not Game.mission_done.is_empty():
				text += " (%d searched)" % Game.mission_done.size()
		"defend":
			if _defend_running:
				text = s.get("running_text", text)
	return text


## Where the waypoint points during a mission stage, or null to use the component.
func waypoint():
	var id := Game.current_repair()
	if id == "" or Game.carrying != "":
		return null
	var site: ExpeditionSite = main.sites[id]
	var s := stage(id)
	var pos: Vector3 = main.player.global_position
	match s["type"]:
		"reach":
			return site.to_global(s["pos"])
		"activate", "pulse", "defend":
			var best = null
			var best_d := INF
			var list: Array = devices[id][stage_index(id)]
			for i in list.size():
				if i in Game.mission_done:
					continue
				var d: float = (list[i] as Node3D).global_position.distance_to(pos)
				if d < best_d:
					best_d = d
					best = (list[i] as Node3D).global_position
			return best
		"elite":
			if _elite and is_instance_valid(_elite) and not _elite.dead:
				return _elite.global_position
			return site.to_global(s["pos"])
		"search":
			var area := site.to_global(s["pos"])
			return area if _flat(area - pos) > SEARCH_AREA else null
	return null


## The prompt and action for a device in reach, or {}.
func interaction(pos: Vector3) -> Dictionary:
	var id := Game.current_repair()
	if bypass or id == "" or Game.carrying != "":
		return {}
	var s := stage(id)
	if not s["type"] in ["activate", "pulse", "defend", "search"]:
		return {}
	var si := stage_index(id)
	var list: Array = devices[id][si]
	var specs: Array = [s["device"]] if s.has("device") else s["devices"]
	for i in list.size():
		var d: MissionDevice = list[i]
		if i in Game.mission_done or _flat(d.global_position - pos) > REACH or absf(d.global_position.y - pos.y) > 1.6:
			continue
		var spec: Dictionary = specs[i]
		var label: String = spec.get("label", "Work the device")
		if s["type"] == "defend":
			if _defend_running:
				return {"label": "%s: %d%%" % [s.get("bar", "WORKING").capitalize(), int(defend_ratio() * 100.0)]}
			return {"label": "[E] %s" % label, "action": _start_defend}
		if not _channel.is_empty() and _channel["index"] == i:
			return {"label": "%s..." % label}
		var hold: float = spec.get("hold", 0.0)
		if hold > 0.0:
			return {"label": "[Hold E] %s" % label, "action": _start_channel.bind(i, hold, label)}
		return {"label": "[E] %s" % label, "action": _complete_device.bind(i)}
	return {}


func defend_ratio() -> float:
	var s := stage(Game.current_repair())
	return clampf(_defend_progress / float(s.get("seconds", 1.0)), 0.0, 1.0)


func defending() -> bool:
	return _defend_running


func channel_ratio() -> float:
	return -1.0 if _channel.is_empty() else clampf(_channel["time"] / _channel["need"], 0.0, 1.0)


func elite() -> Enemy:
	return _elite


# --- Running --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_objective()
	var id := Game.current_repair()
	var hud: Hud = main.hud
	if bypass or id == "" or Game.carrying != "" or main.player.dead:
		hud.set_task(-1.0)
		return
	var site: ExpeditionSite = main.sites[id]
	var s := stage(id)
	var pos: Vector3 = main.player.global_position
	if not _intro_said.has(id) and pos.distance_to(site.global_position) < site.wake_radius * 0.7:
		_intro_said[id] = true
		if stage_index(id) == 0 and s.has("say") and s["type"] != "elite":
			main.voice.interrupt(s["say"])
	match s["type"]:
		"reach":
			var target := site.to_global(s["pos"])
			if _flat(target - pos) < float(s.get("radius", 3.0)) and absf(target.y - pos.y) < 2.0:
				_advance(id)
		"elite":
			_run_elite(id, site, s)
		"defend":
			_run_defend(id, site, s, delta)
	if not _channel.is_empty():
		_run_channel(id, delta)
	elif s["type"] == "search":
		_run_search(id, s, delta)
	elif not _defend_running:
		hud.set_task(-1.0)


func _run_channel(id: String, delta: float) -> void:
	var d: MissionDevice = devices[id][_channel["stage"]][_channel["index"]]
	if not Input.is_action_pressed("interact") or _flat(d.global_position - main.player.global_position) > HOLD_RANGE:
		_interrupt("")
		return
	_channel["time"] += delta
	main.hud.set_task(channel_ratio(), _channel["label"].to_upper())
	if _channel["time"] >= _channel["need"]:
		var i: int = _channel["index"]
		_channel = {}
		main.hud.set_task(-1.0)
		_complete_device(i)


## 0..1: how strong the hidden thing's signal is where Juno stands.
func search_signal() -> float:
	var id := Game.current_repair()
	if id == "" or stage(id)["type"] != "search":
		return 0.0
	var hidden: MissionDevice = devices[id][stage_index(id)][int(stage(id)["answer"])]
	var d := _flat(hidden.global_position - main.player.global_position)
	return clampf(1.0 - d / SIGNAL_RANGE, 0.0, 1.0)


## The signal meter and its ping, faster the closer she gets.
func _run_search(_id: String, s: Dictionary, delta: float) -> void:
	var strength := search_signal()
	main.hud.set_task(strength, "%s  %d%%" % [s.get("signal", "SIGNAL"), int(strength * 100.0)])
	if strength <= 0.0:
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = lerpf(1.6, 0.18, strength)
		Sfx.play("signal_ping", null, lerpf(-16.0, -6.0, strength), 0.0)


func _run_elite(id: String, site: ExpeditionSite, s: Dictionary) -> void:
	if _elite and is_instance_valid(_elite):
		if _elite.dead:
			_elite = null
			_advance(id)
		return
	# Wakes when the player comes near the site (or comes back after it was lost).
	if main.player.global_position.distance_to(site.global_position) > site.wake_radius:
		return
	_elite = main.spawn_enemy(s.get("kind", "ram"), site.to_global(s["pos"]), s.get("name", "ELITE"))
	_elite.alert(false)
	main.hud.show_boss(_elite)
	if s.has("say"):
		main.voice.interrupt(s["say"])


func _run_defend(id: String, site: ExpeditionSite, s: Dictionary, delta: float) -> void:
	if not _defend_running:
		return
	var d: MissionDevice = devices[id][stage_index(id)][0]
	var inside := _flat(d.global_position - main.player.global_position) < float(s.get("radius", 10.0))
	if inside:
		_defend_progress += delta
	var ratio := defend_ratio()
	site.set_component_lift(float(s.get("lift", 0.0)) * (1.0 - ratio))
	var bar: String = s.get("bar", "WORKING")
	main.hud.set_task(ratio, bar if inside else "%s PAUSED: GET BACK TO IT" % bar)
	_wave_timer -= delta
	var waves: Array = s.get("waves", [])
	if _wave_timer <= 0.0 and _wave_index < waves.size():
		_wave_timer = float(s.get("wave_every", WAVE_EVERY))
		_spawn_wave(site, s, waves[_wave_index])
		_wave_index += 1
	if ratio >= 1.0:
		_defend_running = false
		main.hud.set_task(-1.0)
		_advance(id)


func _spawn_wave(site: ExpeditionSite, s: Dictionary, kinds: Array) -> void:
	var points: Array[Vector3] = site.ambush_points()
	if points.is_empty():
		points = site.spawn_points()
	if s.has("spawns"):
		points.clear()
		for p in s["spawns"]:
			points.append(site.to_global(p))
	for i in kinds.size():
		var at: Vector3 = points[(i + _wave_index) % points.size()] + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		main.spawn_enemy(kinds[i], at).alert(false)


func _start_defend() -> void:
	if _defend_running:
		return
	var id := Game.current_repair()
	var s := stage(id)
	_defend_running = true
	_defend_progress = 0.0
	_wave_index = 0
	_wave_timer = 2.0
	devices[id][stage_index(id)][0].set_state(MissionDevice.State.DONE)
	main.player.anim.play("interact")
	Sfx.play("power_up", devices[id][stage_index(id)][0].global_position, -2.0)
	if s.has("start_say"):
		main.voice.interrupt(s["start_say"])
	_update_objective()


func _start_channel(index: int, need: float, label: String) -> void:
	var id := Game.current_repair()
	_channel = {"stage": stage_index(id), "index": index, "time": 0.0, "need": need, "label": label}
	main.player.anim.play("interact")
	Sfx.play("rifle_reload", devices[id][stage_index(id)][index].global_position, -6.0)


func _interrupt(why: String) -> void:
	if _channel.is_empty():
		return
	_channel = {}
	main.hud.set_task(-1.0)
	if why != "":
		main.hud.show_message(why)


func _on_pulse() -> void:
	var id := Game.current_repair()
	if not _channel.is_empty() and id != "" and stage(id)["type"] == "pulse":
		_interrupt("The pulse knocked the resonator out of tune. Start right after one passes.")


## A repair finished (or a dev toggle): devices worked belong to the old mission, so forget them.
func _on_repairs_changed() -> void:
	var current := Game.current_repair()
	if current != _last_repair:
		_last_repair = current
		Game.mission_done.clear()
		_channel = {}
		_defend_running = false
		_elite = null
	refresh(false)


func _on_player_died() -> void:
	_interrupt("")
	if _defend_running:
		_defend_running = false
		_defend_progress = 0.0
		var id := Game.current_repair()
		if id != "":
			(main.sites[id] as ExpeditionSite).set_component_lift(float(stage(id).get("lift", 0.0)))
			refresh(false)
		main.hud.set_task(-1.0)


func _complete_device(index: int) -> void:
	var id := Game.current_repair()
	var si := stage_index(id)
	if index in Game.mission_done:
		return
	Game.mission_done.append(index)
	var d: MissionDevice = devices[id][si][index]
	d.set_state(MissionDevice.State.DONE)
	main.player.anim.play("interact")
	var s := stage(id)
	if s["type"] == "search":
		_searched(id, s, d, index)
		return
	Sfx.play("repair_clunk", d.global_position, -4.0)
	(main.sites[id] as ExpeditionSite).on_device_done(si, index, true)
	if Game.mission_done.size() >= devices[id][si].size():
		_advance(id)
	else:
		_update_objective()


## A search spot turned over: the find ends the stage; anything else is scrap, or a nest.
func _searched(id: String, s: Dictionary, d: MissionDevice, index: int) -> void:
	if index == int(s["answer"]):
		Sfx.play("repair_clunk", d.global_position, -2.0)
		main.hud.show_message(s.get("found", "Found it."))
		_advance(id)
		return
	d.mark_empty()
	Sfx.play("scrap_pickup", d.global_position, -4.0)
	if index in s.get("nests", []):
		main.hud.show_message("Not here, and something was living in it.")
		for k in 3:
			var a := TAU * k / 3.0 + randf() * 0.5
			var at := d.global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(4.0, 6.0)
			main.spawn_enemy("scuttler", at).alert(false)
		Sfx.play("scuttler_alert", d.global_position, 0.0, 0.1)
	else:
		Game.add_scrap(4)
		main.hud.show_message("Not here. 4 scrap for the trouble.")
	_update_objective()


## Finishes the current stage and moves to the next (or to the take stage).
func _advance(id: String) -> void:
	var si := stage_index(id)
	var site: ExpeditionSite = main.sites[id]
	var s := stage(id)
	if s["type"] == "take":
		return
	Game.mission_stage[id] = si + 1
	Game.mission_done.clear()
	_channel = {}
	_defend_running = false
	site.on_stage_done(si, true)
	refresh(true)
	stage_completed.emit(id, si)
	var next := stage(id)
	if s.has("done_say"):
		main.voice.interrupt(s["done_say"])
	elif next.has("say") and next["type"] != "elite":
		main.voice.interrupt(next["say"])
	if next["type"] == "defend":
		site.set_component_lift(float(next.get("lift", 0.0)))
	main.hud.show_banner("OBJECTIVE COMPLETE", s.get("text", "").split(" (")[0])
	Sfx.play("log_chime", null, -4.0, 0.0)
	_update_objective()


## Completes the current stage outright (dev key and tests).
func complete_stage() -> void:
	var id := Game.current_repair()
	if id == "" or can_take(id):
		return
	if _elite and is_instance_valid(_elite):
		_elite.queue_free()
	_elite = null
	var site: ExpeditionSite = main.sites[id]
	var list: Array = devices[id][stage_index(id)]
	for i in list.size():
		if not i in Game.mission_done:
			Game.mission_done.append(i)
			site.on_device_done(stage_index(id), i, false)
	_advance(id)


## Puts every device in the state the saved progress says, and replays finished stages' effects
## on their sites (vents shut, lights on). `animate` false snaps.
func refresh(animate: bool) -> void:
	var current := Game.current_repair()
	for r in Campaign.REPAIRS:
		var id: String = r["id"]
		var done_repair := Game.is_repaired(id)
		var si := stage_index(id)
		for i in devices[id].size():
			for j in devices[id][i].size():
				var d: MissionDevice = devices[id][i][j]
				var st := MissionDevice.State.DORMANT
				if done_repair or bypass or i < si or (id == current and i == si and j in Game.mission_done):
					st = MissionDevice.State.DONE
				elif id == current and i == si:
					st = MissionDevice.State.PENDING
				d.set_state(st, animate)


## After a load: snap devices and site effects to the saved progress.
func restore() -> void:
	_channel = {}
	_defend_running = false
	_elite = null
	refresh(false)
	for r in Campaign.REPAIRS:
		var id: String = r["id"]
		var site: ExpeditionSite = main.sites[id]
		var si := site.mission.size() if Game.is_repaired(id) else stage_index(id)
		for i in si:
			for j in devices[id][i].size():
				site.on_device_done(i, j, false)
			site.on_stage_done(i, false)
		if id == Game.current_repair():
			for j in Game.mission_done:
				site.on_device_done(si, j, false)
			if stage(id)["type"] == "defend":
				site.set_component_lift(float(stage(id).get("lift", 0.0)))
	_update_objective()


func _update_objective() -> void:
	var text := objective()
	if text != _last_text:
		_last_text = text
		Game.mission_objective = text
		Game.objective_changed.emit(Game.objective_text())


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
