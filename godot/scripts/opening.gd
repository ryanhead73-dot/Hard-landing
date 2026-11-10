class_name Opening
extends Node
## The new-game opening, from a working Kestrel in orbit to the aux cell in Juno's pouch (about
## twenty minutes, nothing attacks her before the relay yard). Beats:
##   APPROACH  aboard the working ship (regions/approach.gd), ending in the crash.
##   WAKE      on the wrecked deck with a punctured suit: get up, find the med-seal, use it.
##   SEALED    HOB is dark; out through the bent side door, over the spar.
##   OUTSIDE   scan the hull fracture, the stranded cargo pod and the old impact scar.
##   TRAIL     follow the reflector beads: the fibre spool, the cable bridge, the early cache,
##             the survey pod and its bench: build the rifle, test it on the sensor plate.
##   ARMED     the reed gully: a scuttler that only watches her, until wreckage startles it.
##   WATCHED   the relay yard: a hungry scuttler, one warning, the first fight; it drops the
##             battery contact the relay's mission starts with.
##   YARD      the relay mission (see RelayStation) up to the cell, which ends the opening.
## The beat is Game.flags["opening"] (saved with the session). A save without it never had an
## opening (made before it existed, or the opening was skipped), so nothing here runs for it.
## Checkpoints save after the crash, the med-seal, the rifle and the cell.

enum Beat { APPROACH, WAKE, SEALED, OUTSIDE, TRAIL, ARMED, WATCHED, YARD, DONE }

const USE := 2.0
## Remembers, across saves, that this player has seen the opening through once.
const SEEN_PATH := "user://progress.cfg"
## Plan points aboard the wreck (Kestrel.plan).
const WAKE_AT := Vector3(9.7, 0.1, 11.0)
const MEDSEAL := Vector3(9.2, 1.3, 16.55)
const HOB_CONSOLE := Vector3(4.9, 1.9, 13.0)
const CARGO_HATCH := Vector3(23.4, 1.2, 13.0)
const DOOR := Vector3(12.9, 0.0, 17.1)
const FRACTURE := Vector3(15.6, 1.4, 17.9)
## Out in the basin (x, z; height from the ground).
const POD_AT := Vector2(-11.0, 13.0)
const SCAR_AT := Vector2(7.0, 25.0)
const SPOOL_AT := Vector2(-11.0, 21.0)
const LEDGE_AT := Vector2(-12.0, 28.5)
const ISLAND_AT := Vector2(-12.0, 35.5)
const SURVEY_AT := Vector2(-31.0, 43.0)
const PLATE_AT := Vector2(-31.0, 53.0)
const GULLY_AT := Vector2(-43.0, 47.0)
const WATCHER_FROM := Vector2(-47.0, 41.0)
const WATCHER_TO := Vector2(-41.0, 38.0)
const BEADS := [
	Vector2(-7.0, 9.0), Vector2(-8.5, 14.0), Vector2(-10.0, 18.5), Vector2(-11.5, 23.0),
	Vector2(-15.5, 31.0), Vector2(-20.0, 35.5), Vector2(-25.0, 39.5), Vector2(-29.0, 41.5),
	Vector2(-35.0, 44.5), Vector2(-40.0, 46.5), Vector2(-46.0, 49.5), Vector2(-50.0, 52.0),
]
const AMBER := Color("e8a44e")
const TEAL := Color("3fd1b5")
const IVORY := Color("d9d2c2")
const OXIDE := Color("bf6835")
const BASALT := Color("2a2c2e")
const METAL := Color("5d6468")
## Starting suit health after the crash, by how many of the two braces she made.
const CRASH_HEALTH := [40.0, 50.0, 60.0]

var main: Node
var approach: Approach
var props: Node3D
var _bridge: Node3D
var _cache_lid: Node3D
var _pod_door: Node3D
var _plate: Node3D
var _door_panel: StaticBody3D
var _spar: StaticBody3D
var _beads: Array[MeshInstance3D] = []
var _bead_t := 0.0
var _watcher: Enemy
var _hungry: Enemy
var _hungry_warned := 0.0
var _contact: Node3D
var _wake_lock := false


func setup(m: Node) -> void:
	main = m
	Game.flag_changed.connect(func(_f, _v): _sync())


static func seen_before() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SEEN_PATH) == OK and bool(cfg.get_value("opening", "seen", false))


static func mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SEEN_PATH)
	cfg.set_value("opening", "seen", true)
	cfg.save(SEEN_PATH)


func beat() -> int:
	return int(Game.flags.get("opening", Beat.DONE))


func active() -> bool:
	return Game.flags.has("opening") and beat() < Beat.DONE


func _set_beat(b: int) -> void:
	Game.set_flag("opening", b)
	_update_objective()


## New game: aboard Kestrel in orbit.
func start() -> void:
	Game.set_flag("opening", Beat.APPROACH)
	main.player.armed = false
	main.regions.travel("approach", true)
	approach = main.regions.scene as Approach
	approach.fell.connect(_on_fell)
	_update_objective()


## Repeat players can sleep through it: Juno wakes armed outside the wreck, as before the
## opening existed, with the relay's contact already in hand.
func skip() -> void:
	Game.set_flag("relay_contact", true)
	Game.set_flag("opening", Beat.DONE)
	main.player.armed = true
	if not main.regions.in_kettle():
		await main.regions.travel("kettle", true)
	_clear_props()
	main.player.revive(main.SPAWN, false)
	main._face_first_goal()
	_update_objective()
	main.voice.say(Story.OPENING)
	main.save_game()


func _on_fell(braced: int) -> void:
	Game.set_flag("crash_braced", braced)
	await main.regions.travel("kettle", true)
	approach = null
	main.player.seated = false
	main.play_intro()


## After the crash (or loading a save mid-opening): the Kettle beats from where she is.
func resume() -> void:
	main.player.armed = beat() >= Beat.ARMED
	_build_props()
	_sync()
	_update_objective()


## The crash cinematic has ended: she comes to on the deck.
func wake() -> void:
	_set_beat(Beat.WAKE)
	var p: Player = main.player
	p.revive(_ship(WAKE_AT), false)
	p.face(-PI * 0.5)
	p.health = CRASH_HEALTH[clampi(int(Game.flags.get("crash_braced", 1)), 0, 2)]
	p.health_changed.emit(p.health, p.max_health())
	p.regen_blocked = true
	p.seated = true
	p.crouching = true
	_wake_lock = true
	Game.stims = 0
	resume()
	main.voice.say(Story.WAKE)
	main.save_game()


func _process(delta: float) -> void:
	if not active() or main == null:
		return
	_bead_t += delta
	for i in _beads.size():
		# The beads blink in a run toward where she's going.
		var phase := fmod(_bead_t * 1.6 - float(i) * 0.35, 3.0)
		_beads[i].visible = phase > 0.0 and phase < 0.5 or beat() < Beat.OUTSIDE
	if _wake_lock:
		main.player.crouching = true
	match beat():
		Beat.WATCHED:
			_hungry_tick(delta)


## Music for where the opening is, by layer (see MusicDirector.OPENING_LAYERS): the ship's theme
## aboard in orbit, silence after the crash, a quiet bass pulse once she has the rifle, the
## sighting's tension while the watcher is in the gully, the bass full once the hungry scuttler
## commits, and quiet again at the relay until the cell's two-note motif.
func music_levels() -> Dictionary:
	var out := {"music_ship_theme": 0.0, "music_sighting": 0.0, "music_first_fight": 0.0}
	match beat():
		Beat.APPROACH:
			if main.regions.current == "approach":
				out["music_ship_theme"] = 0.8
		Beat.TRAIL:
			if main.player.armed:
				out["music_first_fight"] = 0.3
		Beat.ARMED:
			if _watcher and is_instance_valid(_watcher) and not _watcher.dead:
				out["music_sighting"] = 1.0
			else:
				out["music_first_fight"] = 0.25
		Beat.WATCHED:
			var fighting: bool = _hungry != null and is_instance_valid(_hungry) and _hungry.hunting and not _hungry.dead
			out["music_first_fight"] = 1.0 if fighting else 0.3
	return out


## The ambience bed outdoors in the opening: the reed gully near it, the open basin elsewhere.
func ambience_zone(at: Vector3) -> String:
	return "gully" if Vector2(at.x, at.z).distance_to(GULLY_AT) < 16.0 else "basin"


## The prompt the opening offers at `pos`, or {}. Main asks this first while it is active.
func interaction(pos: Vector3) -> Dictionary:
	if not active() or not main.regions.in_kettle():
		return {}
	var b := beat()
	if _wake_lock:
		return {"label": "[Hold E] Get up", "hold": 1.0, "action": _get_up}
	if b == Beat.WAKE and not Game.flags.get("medseal_taken", false) and _near(pos, _ship(MEDSEAL)):
		return {"label": "[E] Take the emergency med-seal", "action": _take_medseal}
	if b <= Beat.SEALED and _near(pos, _ship(HOB_CONSOLE)):
		return {"label": "[E] Wake HOB", "action": func(): main.voice.interrupt(Story.HOB_DARK)}
	if b <= Beat.SEALED and _near(pos, _ship(CARGO_HATCH)):
		return {"label": "[E] Try the cargo hatch", "action": func(): main.voice.interrupt(Story.HATCH_JAMMED)}
	if b == Beat.OUTSIDE:
		for s in _scans():
			if not Game.flags.get(s[0], false) and _near(pos, s[1], 2.6):
				return {"label": "[E] %s" % s[2], "action": _scan.bind(s[0])}
	if b >= Beat.OUTSIDE:
		if not Game.flags.get("spool_scanned", false) and _near(pos, _ground(SPOOL_AT, 0.3), 2.4):
			return {"label": "[E] Scan the fibre spool", "action": _scan_spool}
		if not Game.flags.get("bridge_down", false) and _near(pos, _ground(LEDGE_AT, 2.2) + Vector3(0.0, 0.0, 1.6), 2.2):
			return {"label": "[Hold E] Crank the cable bridge across", "hold": 2.0, "action": _lower_bridge}
		if not Game.flags.has("early_reward") and _near(pos, _ground(ISLAND_AT, 2.4), 2.2):
			# Two things in the cache, and room in the pouch for one: whichever side she's on.
			if pos.x < ISLAND_AT.x:
				return {"label": "[E] Take the two med-seals (the battery stays)", "action": _take_reward.bind("seals")}
			return {"label": "[E] Take the scanner battery (the med-seals stay)", "action": _take_reward.bind("battery")}
	if b == Beat.TRAIL:
		var bench := _ground(SURVEY_AT, 0.9) + Vector3(0.0, 0.0, 2.2)
		if not Game.flags.get("pod_open", false) and _near(pos, _ground(SURVEY_AT, 0.9) + Vector3(0.0, 0.0, 2.4), 2.4):
			return {"label": "[Hold E] Pry the survey pod open", "hold": 1.5, "action": _open_pod}
		if Game.flags.get("pod_open", false) and _near(pos, bench, 2.4):
			if not Game.flags.get("rifle_cell", false):
				return {"label": "[E] Seat the cell in the rifle's receiver", "action": _assemble.bind("rifle_cell")}
			if not Game.flags.get("rifle_rail", false):
				return {"label": "[E] Align the bent rail", "action": _assemble.bind("rifle_rail")}
	if b >= Beat.ARMED and b < Beat.YARD and Game.flags.get("pod_open", false) and not Game.flags.get("spare_mag", false) and _near(pos, _ground(SURVEY_AT, 0.9) + Vector3(0.0, 0.0, 2.2), 2.4):
		return {"label": "[E] Take the spare magazine", "action": func():
			Game.set_flag("spare_mag", true)
			main.hud.show_message("Spare magazine. [R] reloads.")}
	if b == Beat.ARMED and not Game.flags.get("carcass_seen", false) and _near(pos, _ground(GULLY_AT, 0.4), 3.0):
		return {"label": "[E] Look at the dead drone", "action": _carcass}
	if b == Beat.WATCHED and _contact and is_instance_valid(_contact) and _near(pos, _contact.global_position, 2.2):
		return {"label": "[E] Take the battery contact", "action": _take_contact}
	return {}


# --- Beats --------------------------------------------------------------------------------

func _get_up() -> void:
	_wake_lock = false
	main.player.seated = false
	main.player.crouching = false
	main.voice.say(Story.GET_UP)


func _take_medseal() -> void:
	Game.set_flag("medseal_taken", true)
	Game.add_stims(1)
	main.player.anim.play("interact")
	Sfx.play("scrap_pickup", null, -4.0, 0.0)
	main.onboarding.offer("stim")


## The med-seal went on: the suit holds, the leak stops.
func on_stim() -> void:
	if beat() != Beat.WAKE:
		return
	main.player.regen_blocked = false
	Sfx.play("med_seal", null, -2.0, 0.0)
	_set_beat(Beat.SEALED)
	main.voice.interrupt(Story.SEALED)
	main.save_game()


func _scans() -> Array:
	return [
		["scan_fracture", _ship(FRACTURE), "Scan the hull fracture"],
		["scan_pod", _ground(POD_AT, 0.5), "Scan the stranded cargo pod"],
		["scan_scar", _ground(SCAR_AT, 0.3), "Scan the impact scar"],
	]


func _scan(id: String) -> void:
	Game.set_flag(id, true)
	Sfx.play("scanner_ping", null, -4.0, 0.0)
	main.player.anim.play("interact")
	main.voice.interrupt(Story.SCANS[id])
	if _scans().all(func(s): return Game.flags.get(s[0], false)):
		_set_beat(Beat.TRAIL)
		main.voice.say(Story.FIND_POWER)


func _scan_spool() -> void:
	Game.set_flag("spool_scanned", true)
	Sfx.play("scanner_ping", null, -4.0, 0.0)
	main.voice.interrupt(Story.SPOOL)


func _lower_bridge() -> void:
	Game.set_flag("bridge_down", true)
	Sfx.play("repair_clunk", _bridge.global_position, -2.0, 0.0)
	_sync_bridge(true)


func _take_reward(which: String) -> void:
	Game.set_flag("early_reward", which)
	main.player.anim.play("interact")
	if which == "seals":
		Game.add_stims(2)
		main.hud.show_message("Two med-seals.")
	else:
		Game.set_flag("scanner_battery", true)
		main.hud.show_message("Scanner battery: your suit marks salvage and wildlife nearby.")
	_cache_lid.rotation.x = -1.2
	Sfx.play("cell_pickup", null, -4.0, 0.0)


func _open_pod() -> void:
	Game.set_flag("pod_open", true)
	Sfx.play("hull_groan", _pod_door.global_position, -2.0, 0.0)
	main.voice.interrupt(Story.POD_OPEN)
	_sync_pod(true)


func _assemble(step: String) -> void:
	Game.set_flag(step, true)
	main.player.anim.play("interact")
	Sfx.play("rifle_cell_seat" if step == "rifle_cell" else "rifle_rail_align", null, -2.0, 0.0)
	if not (Game.flags.get("rifle_cell", false) and Game.flags.get("rifle_rail", false)):
		main.voice.interrupt(Story.ASSEMBLE_1)
		return
	_set_beat(Beat.ARMED)
	main.player.armed = true
	main.player.weapon.equip("rifle")
	main.player.weapon.refill()
	main.voice.interrupt(Story.ASSEMBLE_2)
	main.hud.show_message("[RMB] aim   [LMB] fire: try it on the sensor plate")
	main.save_game()


func _plate_hit() -> void:
	if Game.flags.get("test_shot", false):
		return
	Game.set_flag("test_shot", true)
	Sfx.play("hit_armor", _plate.global_position, 0.0, 0.0)
	var t := create_tween()
	t.tween_property(_plate, "rotation:x", 0.9, 0.2)
	t.tween_property(_plate, "rotation:x", -0.5, 0.5)
	t.tween_property(_plate, "rotation:x", 0.0, 0.8).set_trans(Tween.TRANS_ELASTIC)
	main.voice.interrupt(Story.TEST_SHOT)


func _carcass() -> void:
	Game.set_flag("carcass_seen", true)
	main.voice.interrupt(Story.CARCASS)
	_start_watcher()


## The scuttler that watches: it crosses the gully, takes a shard, backs off. Shooting it is
## allowed and changes nothing; wreckage falling from the ridge sends it away either way.
func _start_watcher() -> void:
	_watcher = main.spawn_enemy("scuttler", _ground(WATCHER_FROM, 0.5))
	_watcher.target = null
	_watcher.set_physics_process(false)
	_watcher.died.connect(func(_e): _watcher_gone(), CONNECT_ONE_SHOT)
	main.voice.say(Story.WATCHER)
	Sfx.play("scuttler_chitter", _watcher.global_position, -6.0, 0.0)
	var to := _ground(WATCHER_TO, 0.5)
	for i in 6:
		get_tree().create_timer(0.5 + i * 0.55).timeout.connect(func():
			if is_instance_valid(_watcher):
				Sfx.play("scuttler_step", _watcher.global_position, -8.0, 0.08))
	_watcher.look_at(to, Vector3.UP)
	var t := create_tween()
	t.tween_property(_watcher, "global_position", to, 3.5)
	t.tween_interval(3.0)
	t.tween_callback(func():
		Sfx.play("rock_impact", to + Vector3(4.0, 3.0, -3.0), 2.0, 0.0)
		Vfx.dust(main, to + Vector3(4.0, 0.0, -3.0), 0.5))
	t.tween_property(_watcher, "global_position", _ground(WATCHER_FROM, 0.5) + Vector3(-6.0, 0.0, -4.0), 1.6)
	t.tween_callback(func():
		if is_instance_valid(_watcher) and not _watcher.dead:
			_watcher.queue_free()
		_watcher_gone())


func _watcher_gone() -> void:
	if beat() != Beat.ARMED:
		return
	_set_beat(Beat.WATCHED)
	main.voice.say(Story.WATCHER_GONE)


## The yard: a field surge snaps the fence cable and corners a hungry scuttler. It threatens
## first; when she comes on or backs away it gives one warning, then attacks.
func _hungry_tick(delta: float) -> void:
	if Game.flags.get("relay_contact", false) or (_contact and is_instance_valid(_contact)):
		return
	var yard: Vector3 = main.sites["aux_power"].global_position
	if _hungry == null or not is_instance_valid(_hungry):
		if main.player.global_position.distance_to(yard) > 26.0:
			return
		_hungry = main.spawn_enemy("scuttler", yard + main.sites["aux_power"].global_basis * Vector3(-6.0, 0.4, 5.0))
		_hungry.sight_range = 0.0
		_hungry.died.connect(_on_hungry_died, CONNECT_ONE_SHOT)
		_hungry_warned = 0.0
		Sfx.play("fence_snap", yard, 2.0, 0.0)
		Sfx.play("arc_zap", yard, -2.0, 0.0)
		Sfx.play("scuttler_alert", _hungry.global_position, 0.0, 0.0)
		main.voice.interrupt(Story.YARD_SURGE)
		return
	if _hungry.hunting:
		return
	_hungry.look_at(Vector3(main.player.global_position.x, _hungry.global_position.y, main.player.global_position.z), Vector3.UP)
	var d: float = main.player.global_position.distance_to(_hungry.global_position)
	if d < 9.0 or _hungry_warned > 0.0:
		_hungry_warned += delta
		if _hungry_warned == delta:
			Sfx.play("scuttler_hiss", _hungry.global_position, 2.0, 0.0)
			main.voice.interrupt(Story.YARD_WARNING)
		if _hungry_warned > 1.8:
			_hungry.sight_range = 18.0
			_hungry.alert(false)
			main.onboarding.offer("fight")


func _on_hungry_died(e: Enemy) -> void:
	_contact = _box(props, e.global_position + Vector3(0.0, 0.3, 0.0), Vector3(0.2, 0.12, 0.3), _glow(AMBER, 3.0))
	main.voice.interrupt(Story.YARD_AFTER)


func _take_contact() -> void:
	_contact.queue_free()
	_contact = null
	Game.set_flag("relay_contact", true)
	_set_beat(Beat.YARD)
	Sfx.play("cell_pickup", null, -4.0, 0.0)
	main.hud.show_message("Battery contact. The relay's dead breaker needs it.")


## The cell is in her pouch: the opening is over.
func on_component_taken(id: String) -> void:
	if id != "aux_power" or not active():
		return
	_set_beat(Beat.DONE)
	mark_seen()
	Sfx.play("relay_two_note", null, -4.0, 0.0)
	main.spawn_roamers()
	main.voice.interrupt(Story.CELL_TAKEN)
	_clear_props()
	_update_objective()


## Dying in the opening puts her back at the last place it makes sense to start from.
func respawn():
	if not active():
		return null
	match beat():
		Beat.WATCHED, Beat.YARD:
			Game.stims = maxi(Game.stims, 2)
			return _ground(Vector2(-46.0, 49.5), 0.5)
		Beat.ARMED:
			return _ground(SURVEY_AT, 0.5) + Vector3(0.0, 0.0, 3.0)
	return null


## Where the HUD points. The trail's beads do the job outside, so mostly nothing.
func waypoint():
	match beat():
		Beat.WAKE:
			return _ship(MEDSEAL) if not Game.flags.get("medseal_taken", false) else null
		Beat.SEALED:
			return _ship(DOOR)
		Beat.OUTSIDE:
			# The nearest thing still to scan.
			var best = null
			var best_d := INF
			for s in _scans():
				if Game.flags.get(s[0], false):
					continue
				var d: float = (s[1] as Vector3).distance_to(main.player.global_position)
				if d < best_d:
					best_d = d
					best = s[1]
			return best
		Beat.YARD:
			return null
	return null


func objective() -> String:
	if not active():
		return ""
	match beat():
		Beat.APPROACH:
			return "Take the copilot's seat for the approach"
		Beat.WAKE:
			return "Seal the suit puncture" if Game.flags.get("medseal_taken", false) else "Find the emergency med-seal"
		Beat.SEALED:
			return "Get out of the wreck"
		Beat.OUTSIDE:
			var n := _scans().filter(func(s): return Game.flags.get(s[0], false)).size()
			return "Scan what's around the wreck (%d/3)" % n
		Beat.TRAIL:
			return "Follow the reflector beads toward the relay"
		Beat.ARMED:
			return "Head on to the relay station"
		Beat.WATCHED:
			return "Find a battery contact for the relay"
	return ""


func _update_objective() -> void:
	Game.opening_objective = objective()
	Game.objective_changed.emit(Game.objective_text())


## Brings the world in line with the flags (after a load, and whenever a flag moves).
func _sync() -> void:
	if props == null:
		return
	if _door_panel:
		_door_panel.process_mode = Node.PROCESS_MODE_INHERIT if active() else Node.PROCESS_MODE_DISABLED
		_door_panel.visible = active()
	if _spar:
		_spar.visible = active()
		_spar.process_mode = Node.PROCESS_MODE_INHERIT if active() else Node.PROCESS_MODE_DISABLED
	_sync_bridge(false)
	_sync_pod(false)
	if _cache_lid and Game.flags.has("early_reward"):
		_cache_lid.rotation.x = -1.2


func _physics_process(_delta: float) -> void:
	# Stepping out of the wreck is a beat of its own.
	if active() and beat() == Beat.SEALED and main.regions.in_kettle() and not main.kestrel.is_inside(main.player.global_position) and main.player.global_position.distance_to(_ship(DOOR)) > 3.5:
		_set_beat(Beat.OUTSIDE)
		main.voice.say(Story.THRESHOLD)


func _sync_bridge(animate: bool) -> void:
	if _bridge == null:
		return
	var down: bool = Game.flags.get("bridge_down", false)
	var want := 0.0 if down else -PI * 0.5
	if animate:
		create_tween().tween_property(_bridge, "rotation:x", want, 1.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	else:
		_bridge.rotation.x = want


func _sync_pod(animate: bool) -> void:
	if _pod_door == null:
		return
	var open: bool = Game.flags.get("pod_open", false)
	var want := -1.4 if open else 0.0
	if animate:
		create_tween().tween_property(_pod_door, "rotation:x", want, 0.8).set_trans(Tween.TRANS_BACK)
	else:
		_pod_door.rotation.x = want


# --- Building -----------------------------------------------------------------------------

func _clear_props() -> void:
	if props:
		props.queue_free()
		props = null
	_beads.clear()
	_door_panel = null
	_spar = null
	_bridge = null
	_pod_door = null


func _build_props() -> void:
	if props:
		return
	props = Node3D.new()
	props.name = "OpeningProps"
	main.add_child(props)
	# The bent panel across the top of the side door: crouch under it.
	_door_panel = _solid(_ship(Vector3(12.9, 1.8, 17.1)), Vector3(2.0, 1.1, 0.4), _mat(IVORY.darkened(0.3), 0.7))
	_door_panel.rotation = main.kestrel.global_rotation + Vector3(0.0, 0.0, 0.08)
	# The twisted spar across the foot of the steps: jump it.
	var foot := _ship(Vector3(12.9, 0.0, 20.4))
	_spar = _solid(Vector3(foot.x, main.site.height_at(foot.x, foot.z) + 0.22, foot.z), Vector3(3.0, 0.45, 0.3), _mat(METAL, 0.5))
	# The med-seal kit's amber strobe.
	var kit := _box(props, _ship(MEDSEAL), Vector3(0.35, 0.25, 0.12), _mat(IVORY, 0.6))
	var strobe := OmniLight3D.new()
	strobe.light_color = AMBER
	strobe.light_energy = 1.4
	strobe.omni_range = 4.0
	kit.add_child(strobe)
	var tw := strobe.create_tween().set_loops()
	tw.tween_property(strobe, "light_energy", 0.0, 0.4)
	tw.tween_property(strobe, "light_energy", 1.4, 0.1)
	# A shaft of daylight through a split in the bunk room wall.
	var shaft := SpotLight3D.new()
	shaft.light_color = Color("dfe6ee")
	shaft.light_energy = 3.0
	shaft.spot_range = 6.0
	shaft.spot_angle = 14.0
	shaft.position = _ship(Vector3(9.8, 3.0, 9.4))
	props.add_child(shaft)
	shaft.look_at(_ship(WAKE_AT), Vector3.FORWARD)
	# What she scans outside.
	var pod := _box(props, _ground(POD_AT, 0.5), Vector3(1.4, 1.0, 2.2), _mat(OXIDE, 0.6))
	pod.rotation = Vector3(0.1, 0.6, 0.25)
	_scar()
	# The reflector beads.
	for b in BEADS:
		var post := _box(props, _ground(b, 0.35), Vector3(0.06, 0.7, 0.06), _mat(METAL, 0.5))
		var bead := _box(post, Vector3(0.0, 0.38, 0.0), Vector3(0.1, 0.1, 0.1), _glow(AMBER, 4.0))
		_beads.append(bead)
	# The fibre spool, and the pale scoring on the rock beside it.
	var spool := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.35
	cm.height = 0.5
	spool.mesh = cm
	spool.material_override = _glow(TEAL.darkened(0.3), 0.6)
	spool.position = _ground(SPOOL_AT, 0.25)
	spool.rotation.z = PI * 0.5
	props.add_child(spool)
	var scored := _box(props, _ground(SPOOL_AT + Vector2(1.6, 0.8), 0.5), Vector3(1.2, 1.0, 1.0), _mat(BASALT, 0.9))
	_box(scored, Vector3(0.0, 0.1, 0.51), Vector3(1.0, 0.03, 0.01), _glow(IVORY, 0.4))
	_box(scored, Vector3(0.0, -0.1, 0.51), Vector3(0.8, 0.03, 0.01), _glow(IVORY, 0.4))
	_ledges()
	_survey_pod()
	_gully()
	_sync()


func _scar() -> void:
	var c := _ground(SCAR_AT, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 251
	for i in 9:
		var a := TAU * float(i) / 9.0
		var r := _box(props, c + Vector3(cos(a) * 3.2, 0.25, sin(a) * 3.2), Vector3(rng.randf_range(0.6, 1.2), 0.5, 0.7), _mat(BASALT, 0.95))
		r.rotation.y = a
	var crack := _box(props, c + Vector3(0.0, 0.03, 0.0), Vector3(3.6, 0.02, 0.15), _glow(TEAL, 1.5))
	crack.rotation.y = 0.7
	_box(props, c + Vector3(0.0, 0.02, 0.0), Vector3(5.0, 0.02, 5.0), _mat(Color("1a1b1c"), 1.0))


## The rock shelf she climbs, the island across the gap with the cache, and the cable bridge.
func _ledges() -> void:
	var rock := _mat(BASALT, 0.95)
	var shelf := _ground(LEDGE_AT, 0.0)
	_solid(shelf + Vector3(0.0, 1.0, 0.0), Vector3(4.0, 2.0, 3.0), rock)
	# A ramp of slabs up its back.
	var ramp := _solid(shelf + Vector3(0.0, 0.855, -3.7), Vector3(2.2, 0.3, 5.2), rock)
	ramp.rotation.x = -0.42
	var island := _ground(ISLAND_AT, 0.0)
	_solid(island + Vector3(0.0, 1.2, 0.0), Vector3(4.0, 2.4, 4.0), rock)
	# The crank on the shelf, the bridge hinged at the shelf's far edge.
	var crank := _box(props, shelf + Vector3(1.4, 2.4, 1.2), Vector3(0.12, 0.8, 0.12), _mat(METAL, 0.4))
	_box(crank, Vector3(0.0, 0.4, 0.15), Vector3(0.1, 0.1, 0.3), _mat(OXIDE, 0.5))
	_bridge = Node3D.new()
	_bridge.position = shelf + Vector3(0.0, 2.0, 1.5)
	props.add_child(_bridge)
	var span := (island.z - 2.0) - (shelf.z + 1.5) + 0.3
	var deck := _solid(Vector3(0.0, -0.06, span * 0.5), Vector3(1.4, 0.12, span), _mat(METAL, 0.5))
	props.remove_child(deck)
	_bridge.add_child(deck)
	deck.position = Vector3(0.0, -0.06 + (island.y + 2.4 - shelf.y - 2.0) * 0.5, span * 0.5)
	for side in [-0.7, 0.7]:
		_box(deck, Vector3(side, 0.5, 0.0), Vector3(0.03, 0.03, span), _glow(TEAL.darkened(0.4), 0.5))
	# The cache on the island: two med-seals, or a scanner battery.
	var cache := _box(props, island + Vector3(0.0, 2.65, 0.0), Vector3(0.9, 0.5, 0.6), _mat(OXIDE, 0.6))
	_cache_lid = Node3D.new()
	_cache_lid.position = Vector3(0.0, 0.25, -0.3)
	cache.add_child(_cache_lid)
	_box(_cache_lid, Vector3(0.0, 0.03, 0.3), Vector3(0.92, 0.06, 0.62), _mat(OXIDE.darkened(0.2), 0.6))
	var beacon := _box(cache, Vector3(0.0, 0.5, 0.0), Vector3(0.06, 0.5, 0.06), _glow(AMBER, 3.0))
	beacon.name = "CacheBeacon"


## The survey pod under its fallen slab, the field bench and the hanging sensor plate.
func _survey_pod() -> void:
	var at := _ground(SURVEY_AT, 0.0)
	var slab := _solid(at + Vector3(0.0, 3.0, -0.5), Vector3(6.0, 0.8, 5.0), _mat(BASALT, 0.95))
	slab.rotation.z = 0.18
	_solid(at + Vector3(-2.6, 1.3, -0.5), Vector3(0.8, 2.6, 0.8), _mat(BASALT, 0.95))
	_solid(at + Vector3(0.0, 0.9, 0.0), Vector3(2.0, 1.8, 2.6), _mat(IVORY.darkened(0.15), 0.6))
	_pod_door = Node3D.new()
	_pod_door.position = at + Vector3(0.0, 0.1, 1.32)
	props.add_child(_pod_door)
	_box(_pod_door, Vector3(0.0, 0.85, 0.0), Vector3(1.6, 1.6, 0.08), _mat(OXIDE, 0.6))
	# The bench, lit by one amber lamp.
	_solid(at + Vector3(0.0, 0.45, 2.2), Vector3(1.4, 0.9, 0.6), _mat(METAL, 0.5))
	var lamp := OmniLight3D.new()
	lamp.light_color = AMBER
	lamp.light_energy = 1.6
	lamp.omni_range = 4.0
	lamp.position = at + Vector3(0.0, 2.0, 2.0)
	props.add_child(lamp)
	# The sensor plate hangs from a pole ten metres on: clearly not alive.
	var pole_at := _ground(PLATE_AT, 0.0)
	_solid(pole_at + Vector3(0.0, 1.6, 0.0), Vector3(0.12, 3.2, 0.12), _mat(METAL, 0.5))
	_box(props, pole_at + Vector3(0.0, 3.1, 0.6), Vector3(0.08, 0.08, 1.2), _mat(METAL, 0.5))
	_plate = Node3D.new()
	_plate.position = pole_at + Vector3(0.0, 3.1, 1.1)
	props.add_child(_plate)
	var plate := StaticBody3D.new()
	plate.collision_layer = Game.LAYER_WORLD
	plate.position = Vector3(0.0, -0.6, 0.0)
	plate.set_meta("on_hit", _plate_hit)
	_plate.add_child(plate)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.7, 0.7, 0.05)
	cs.shape = bs
	plate.add_child(cs)
	_box(plate, Vector3.ZERO, Vector3(0.7, 0.7, 0.05), _mat(IVORY, 0.4))
	_box(plate, Vector3(0.0, 0.0, 0.03), Vector3(0.25, 0.25, 0.01), _glow(OXIDE, 1.0))


## The reed gully: dry gill-reeds and the dead salvage drone.
func _gully() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var reed := CylinderMesh.new()
	reed.top_radius = 0.01
	reed.bottom_radius = 0.035
	reed.height = 1.6
	reed.radial_segments = 4
	reed.rings = 1
	mm.mesh = reed
	mm.instance_count = 160
	for i in mm.instance_count:
		var p := GULLY_AT + Vector2(rng.randf_range(-9.0, 9.0), rng.randf_range(-7.0, 5.0))
		if p.distance_to(GULLY_AT) < 2.5:
			p += (p - GULLY_AT).normalized() * 2.5
		var b := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25)).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
		mm.set_instance_transform(i, Transform3D(b, _ground(p, 0.75)))
	var reeds := MultiMeshInstance3D.new()
	reeds.multimesh = mm
	reeds.material_override = _mat(Color("8a8566"), 0.9)
	props.add_child(reeds)
	var drone := _box(props, _ground(GULLY_AT, 0.3), Vector3(1.0, 0.4, 0.7), _mat(METAL.darkened(0.2), 0.5))
	drone.rotation = Vector3(0.3, 0.8, 0.5)
	_box(drone, Vector3(0.0, 0.22, 0.0), Vector3(0.4, 0.04, 0.3), _glow(OXIDE, 1.2))


# --- Helpers ------------------------------------------------------------------------------

func _ship(p: Vector3) -> Vector3:
	return main.kestrel.to_global(main.kestrel.plan(p.x, p.y, p.z))


func _ground(p: Vector2, up: float) -> Vector3:
	return Vector3(p.x, main.site.height_at(p.x, p.y) + up, p.y)


func _near(a: Vector3, b: Vector3, r := USE) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() < r and absf(a.y - b.y) < 2.2


func _box(parent: Node, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


func _solid(at: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.position = at
	props.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	_box(body, Vector3.ZERO, size, mat)
	return body


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.3)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m
