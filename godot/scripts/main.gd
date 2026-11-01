extends Node3D
## Game flow: sky and sun, player, HUD, enemies, interactions and dev controls.
## The campaign (see Campaign) restores Kestrel one repair at a time: follow the active site's
## beacon, recover its component, carry it home and install it. Each repair turns on a benefit.
## When all seven are done, the pilot's seat starts the engine spool (Finale), and then launches.

const SPAWN := Vector3(-3.0, 0.5, 15.0)
const INTERACT_RANGE := 1.8
const FABRICATOR_POINT := Vector3(16.2, 0.0, 10.7)
const ROAMER_POINTS := [Vector3(-28.0, 0.5, 30.0), Vector3(-42.0, 0.5, 22.0)]
const RESPAWN_DELAY := 2.5
## Install points are checked on the flat with a little height slack, since the ship sits tilted,
## but not so much that a point inside the hull answers from the ground outside.
const INSTALL_HEIGHT_SLACK := 0.7
## How far the scanner (canopy repair) picks up crates and wildlife.
const SCAN_CRATES := 70.0
const SCAN_ENEMIES := 45.0
## Reserve rounds in a crate bundle and in an enemy's ammo drop, per weapon.
const AMMO_BUNDLE := {"scattergun": 12, "arc_lance": 4}
const AMMO_DROP := {"scattergun": 6, "arc_lance": 2}
const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"crouch": [KEY_C, KEY_CTRL],
	"dodge": [KEY_V, KEY_ALT],
	"interact": [KEY_E],
	"flashlight": [KEY_F],
	"reload": [KEY_R],
	"stim": [KEY_Q],
	"throw": [KEY_G],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"weapon_3": [KEY_3],
	"inventory": [KEY_TAB, KEY_I],
	"logs": [KEY_L],
	"map": [KEY_M],
}
## The launch cinematic: lift, climb out, then the ending card.
const LIFT_TIME := 3.0
const CLIMB_TIME := 7.0
## A full day: noon, through dusk and back. Mostly day, with a long amber dusk in the middle.
const DAY_LENGTH := 1200.0
## The crash intro: Kestrel's last approach, the impact, the slide, a beat of quiet.
const INTRO_FALL := 3.4
const INTRO_SLIDE := 1.6
const INTRO_HOLD := 1.6
const BUTTONS := {
	"fire": [MOUSE_BUTTON_LEFT],
	"aim": [MOUSE_BUTTON_RIGHT],
	"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN],
	"weapon_prev": [MOUSE_BUTTON_WHEEL_UP],
}

@onready var kestrel: Kestrel = $Kestrel
@onready var site: CrashSite = $CrashSite
@onready var station: RelayStation = $RelayStation
@onready var wreck: HaulerWreck = $HaulerWreck

## Expedition sites by repair id.
var sites: Dictionary = {}
## Set false (tests) to stop resident packs waking up as the player nears a site.
var spawn_packs := true

var player: Player
var hud: Hud
var fabricator: FabricatorMenu
var inventory: InventoryPanel
var siege: ShipSiege
## Lurkers in the pools and roaming packs on the open basin.
var wildlife: Wildlife
## Squalls over the basin.
var weather: Weather
var voice: Voice
var logs_panel: LogPanel
var map_panel: MapPanel
var finale: Finale
var music: MusicDirector
var ambience: Ambience
var missions: MissionRunner
## True once the ending card is up; interact then returns to the title.
var ending_shown := false
var _cine_cam: Camera3D
## True while the crash intro plays (a new game from the title). Interact or Esc skips it.
var intro_playing := false
var _intro_tween: Tween
var _intro_rest: Transform3D
var _intro_smoke: Array = []
var _shake := 0.0
var dusk := false
## How stormy it is (0 clear .. 1 downpour) and a lightning flash on top; Weather sets them.
var storm := 0.0
var flash := 0.0
## 0 = full day, 1 = full dusk. The basin drifts between them over DAY_LENGTH seconds.
var daylight := 0.0
## Seconds into the day cycle (saved).
var day_time := 0.0
var day_cycle := true
var dev_panel := false

var _env: Environment
var _sky: ShaderMaterial
var _sun: DirectionalLight3D
var _interaction: Dictionary = {}
var _ship_hum: Node
var _pack_check := 0.0
var _daylight_check := 0.0


func _ready() -> void:
	_setup_input()
	_build_environment()
	Game.reset()

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.revive(SPAWN)
	Vfx.motes(player)

	hud = Hud.new()
	add_child(hud)
	player.health_changed.connect(hud.set_health)
	player.damaged.connect(func(_amount):
		hud.flash_damage()
		if player.last_hit_from != Vector3.ZERO:
			hud.damage_from(player.last_hit_from))
	player.died.connect(_on_player_died)
	player.weapon.ammo_changed.connect(_on_ammo_changed)
	player.weapon.hit_confirmed.connect(hud.hitmarker)
	player.weapon.crit_landed.connect(hud.crit_marker)
	Game.scrap_changed.connect(hud.set_scrap)
	Game.objective_changed.connect(hud.set_objective)
	Game.message.connect(hud.show_message)
	hud.set_health(player.health, player.max_health())
	_on_ammo_changed(player.weapon.in_mag, player.weapon.mag_size(), false)
	Game.inventory_changed.connect(func(): hud.set_stims(Game.stims, Game.max_stims()))
	Game.inventory_changed.connect(func(): hud.set_charges(Game.charges, Game.max_charges()))
	Game.upgrades_changed.connect(func(): hud.set_stims(Game.stims, Game.max_stims()))
	hud.set_stims(Game.stims, Game.max_stims())
	hud.set_charges(Game.charges, Game.max_charges())
	hud.set_scrap(Game.scrap)
	hud.set_objective(Game.objective_text())
	hud.show_message("Kestrel is dead without power. Follow the red beacon to the relay station and find a power cell.")

	var pause := PauseMenu.new()
	pause.quit_to_title.connect(func():
		save_game()
		get_tree().change_scene_to_file("res://scenes/title.tscn"))
	add_child(pause)
	fabricator = FabricatorMenu.new()
	add_child(fabricator)
	inventory = InventoryPanel.new()
	inventory.player = player
	add_child(inventory)
	logs_panel = LogPanel.new()
	add_child(logs_panel)
	map_panel = MapPanel.new()
	map_panel.main = self
	add_child(map_panel)
	voice = Voice.new()
	voice.hud = hud
	add_child(voice)
	Game.log_found.connect(func(id: String):
		hud.show_log_toast(Story.get_log(id)["title"])
		Sfx.play("log_chime", null, -6.0, 0.0))
	siege = ShipSiege.new()
	siege.kestrel = kestrel
	siege.player = player
	siege.spawner = spawn_enemy
	add_child(siege)
	finale = Finale.new()
	finale.siege = siege
	finale.voice = voice
	finale.hud = hud
	add_child(finale)
	siege.hull_changed.connect(func(hull: float, max_hull: float):
		hud.set_hull(hull / max_hull if hull >= 0.0 else -1.0, _siege_label(siege.wave)))
	siege.wave_started.connect(func(w: int, _total: int):
		hud.set_hull(siege.hull / ShipSiege.MAX_HULL, _siege_label(w)))
	siege.started.connect(func(index: int):
		if index < Story.SIEGE.size():
			voice.interrupt(Story.SIEGE[index]))
	siege.ended.connect(func(success: bool):
		if siege.last_ended != ShipSiege.FINALE:
			voice.interrupt([Story.SIEGE_HELD if success else Story.SIEGE_LOST]))
	music = MusicDirector.new()
	music.name = "Music"
	add_child(music)
	music.setup(self)
	ambience = Ambience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.setup(self)
	for r in Campaign.REPAIRS:
		var site: ExpeditionSite = get_node(String(r["site"]))
		sites[r["id"]] = site
		# Only the site you're heading for pings, so the sound points the way.
		site.beacon_flashed.connect(func(at: Vector3):
			if site.active:
				Sfx.play("beacon_ping", at, -4.0, 0.0))
	missions = MissionRunner.new()
	missions.name = "Missions"
	add_child(missions)
	missions.setup(self)
	kestrel.repair_changed.connect(_on_repair_changed)
	for id in Kestrel.REPAIR_ORDER:
		Game.set_repaired(id, kestrel.is_repaired(id))
	for p in ROAMER_POINTS:
		spawn_scuttler(p)
	wildlife = Wildlife.new()
	wildlife.name = "Wildlife"
	add_child(wildlife)
	wildlife.setup(self)
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(self)
	_update_active_site()
	_set_dusk(false)
	if not Game.pending_load.is_empty():
		load_state(Game.pending_load)
		Game.pending_load = {}
	elif Game.intro_pending:
		Game.intro_pending = false
		play_intro()
	else:
		voice.say(Story.OPENING)


func _process(_delta: float) -> void:
	if day_cycle:
		day_time = fmod(day_time + _delta, DAY_LENGTH)
		_daylight_check -= _delta
		if _daylight_check <= 0.0:
			_daylight_check = 0.5
			set_daylight(daylight_at(day_time))
	if _cine_cam:
		_cine_cam.look_at(kestrel.global_position + Vector3.UP * 2.0)
		if _shake > 0.0:
			_shake = maxf(_shake - _delta * 1.6, 0.0)
			_cine_cam.h_offset = randf_range(-1.0, 1.0) * 0.6 * _shake
			_cine_cam.v_offset = randf_range(-1.0, 1.0) * 0.6 * _shake
	if intro_playing:
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("jump"):
			end_intro()
		return
	if ending_shown:
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_cancel"):
			get_tree().change_scene_to_file("res://scenes/title.tscn")
		return
	_interaction = _find_interaction()
	hud.set_prompt(_interaction.get("label", ""))
	if _interaction.has("action") and Input.is_action_just_pressed("interact") and not player.dead:
		(_interaction["action"] as Callable).call()
	elif Input.is_action_just_pressed("inventory") and not player.dead and not Game.launched:
		inventory.open()
	elif Input.is_action_just_pressed("logs") and not player.dead and not Game.launched:
		logs_panel.open_latest()
	elif Input.is_action_just_pressed("map") and not player.dead and not Game.launched:
		map_panel.open()
	hud.set_waypoint(_waypoint())
	hud.set_scan(scanner_marks())
	_pack_check -= _delta
	if _pack_check <= 0.0:
		_pack_check = 0.5
		_wake_packs()
		if spawn_packs:
			wildlife.update(0.5)
	if dev_panel:
		hud.set_dev(true, _dev_text())
	if player.global_position.y < -20.0:
		player.revive(SPAWN)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_F1:
		dev_panel = not dev_panel
		Game.dev_panel_open = dev_panel
		hud.set_dev(dev_panel, _dev_text())
	elif not dev_panel:
		return
	elif key >= KEY_1 and key <= KEY_7:
		kestrel.toggle_repair(Kestrel.REPAIR_ORDER[key - KEY_1])
	elif key == KEY_N:
		day_cycle = false
		_set_dusk(not dusk)
	elif key == KEY_K:
		Game.add_scrap(50)
	elif key == KEY_T:
		var site := current_site()
		if site:
			player.revive(site.component_point() + Vector3.UP * 0.5)
	elif key == KEY_H:
		player.revive(SPAWN)
	elif key == KEY_M:
		missions.complete_stage()


func spawn_scuttler(at: Vector3) -> Scuttler:
	return spawn_enemy("scuttler", at) as Scuttler


# --- Campaign ----------------------------------------------------------------------------

## The site the campaign is heading for, or null when every repair is done.
func current_site() -> ExpeditionSite:
	return sites.get(Game.current_repair())


## Where to stand to install a repair (or "launch" / "armoury"), in world space.
func install_point(id: String) -> Vector3:
	return kestrel.to_global(kestrel.interact_points[id])


func _near_install(id: String) -> bool:
	var p := install_point(id)
	var pos := player.global_position
	return Vector2(pos.x - p.x, pos.z - p.z).length() < INTERACT_RANGE and absf(pos.y - p.y) < INSTALL_HEIGHT_SLACK


func _update_active_site() -> void:
	var current := Game.current_repair()
	for id in sites:
		(sites[id] as ExpeditionSite).active = id == current


## Resident packs wake the first time the player comes within a site's wake radius.
func _wake_packs() -> void:
	if not spawn_packs or player.dead:
		return
	for id in sites:
		var site: ExpeditionSite = sites[id]
		if site.pack_spawned or player.global_position.distance_to(site.global_position) > site.wake_radius:
			continue
		site.pack_spawned = true
		var points := site.spawn_points()
		for i in points.size():
			spawn_enemy(site.spawn_kind(i), points[i])
			# Hard brings a second scuttler to every other spawn point.
			if Game.difficulty == 2 and i % 2 == 0:
				spawn_enemy("scuttler", points[i] + Vector3(1.5, 0.0, 1.5))


## Spawns a hostile: "scuttler", "spitter", "ram", "lurker", "skimmer" or "warden". A name makes it an elite.
func spawn_enemy(kind: String, at: Vector3, elite_name := "") -> Enemy:
	var e: Enemy
	match kind:
		"spitter":
			e = Spitter.new()
		"ram":
			e = Ram.new()
		"lurker":
			e = Lurker.new()
		"skimmer":
			e = Skimmer.new()
		"warden":
			var w := Warden.new()
			w.summon = func(p: Vector3): spawn_enemy("scuttler", p).alert(false)
			e = w
		_:
			e = Scuttler.new()
	# Out among the hummocks, start on the ground, not inside it.
	var ground := site.height_at(at.x, at.z)
	if at.y < ground + 0.3:
		at.y = ground + 0.5
	e.target = player
	e.home = at
	e.elite_name = elite_name
	add_child(e)
	e.global_position = at
	e.died.connect(_on_enemy_died)
	return e


## What the cockpit scanner shows once the canopy is sealed: [{pos, kind}].
func scanner_marks() -> Array:
	var marks := []
	if not Game.is_repaired("canopy") or player == null:
		return marks
	var pos := player.global_position
	for id in sites:
		var site: ExpeditionSite = sites[id]
		for i in site.crate_count():
			if not site.crate_searched(i) and site.crate_point(i).distance_to(pos) < SCAN_CRATES:
				marks.append({"pos": site.crate_point(i), "kind": "crate"})
	if wildlife:
		marks.append_array(wildlife.cache_marks(pos, SCAN_CRATES))
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(pos) < SCAN_ENEMIES:
			marks.append({"pos": e.global_position, "kind": "enemy"})
	return marks


# --- Saving --------------------------------------------------------------------------------

## Everything needed to pick the campaign back up at Kestrel.
func save_state() -> Dictionary:
	var data := Game.session_state()
	var site_states := {}
	for id in sites:
		site_states[id] = (sites[id] as ExpeditionSite).get_state()
	data["sites"] = site_states
	# A siege in progress comes back as one waiting to happen.
	data["siege_pending"] = siege.active if siege.is_active() else siege.pending
	data["weapon"] = player.weapon.current
	data["day_time"] = day_time
	return data


## How far into dusk the basin is at `t` seconds into the cycle: day for the first third, then a
## slow fall into dusk and back out.
static func daylight_at(t: float) -> float:
	var x := fposmod(t, DAY_LENGTH) / DAY_LENGTH
	if x < 0.35:
		return 0.0
	return smoothstep(0.0, 1.0, sin((x - 0.35) / 0.65 * PI))


func save_game() -> bool:
	if Game.launched:
		return false
	return Game.write_save(save_state())


func load_state(data: Dictionary) -> void:
	Game.apply_session(data)
	# Repairs coming back would read as the mission moving on; keep the devices worked.
	var done := Game.mission_done.duplicate()
	var repaired: Dictionary = data.get("repaired", {})
	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, repaired.get(id, false))
	Game.mission_done = done
	kestrel.snap_pose()
	var site_states: Dictionary = data.get("sites", {})
	for id in sites:
		if site_states.has(id):
			(sites[id] as ExpeditionSite).set_state(site_states[id])
	missions.restore()
	wildlife.restore()
	var pending := int(data.get("siege_pending", -1))
	if pending >= 0:
		siege.arm(pending)
	player.weapon.equip(String(data.get("weapon", "rifle")))
	day_time = float(data.get("day_time", 0.0))
	set_daylight(daylight_at(day_time))
	player.revive(SPAWN, false)
	_update_active_site()
	Game.objective_changed.emit(Game.objective_text())
	hud.show_message("Back aboard Kestrel. %s." % Game.objective_text())
	_settle_spawn()


## The repaired parts move Kestrel's colliders, and the physics server only catches up on the
## next step; until then the player would be shoved out of where the old shapes were.
func _settle_spawn() -> void:
	await get_tree().physics_frame
	if is_instance_valid(player) and not player.dead:
		player.global_position = SPAWN
		player.velocity = Vector3.ZERO


## The bunk: full health, a save, and a moment's quiet.
func rest() -> void:
	player.health = player.max_health()
	player.health_changed.emit(player.health, player.max_health())
	if save_game():
		hud.show_message("You sleep a few hours in the bunk. Progress saved.")
	Sfx.play("power_up", null, -10.0, 0.0)


# --- Interactions -------------------------------------------------------------------------

func _find_interaction() -> Dictionary:
	if player.dead or Game.launched:
		return {}
	var pos := player.global_position
	var current := Game.current_repair()
	# The mission's own devices come first: near the component, the clamp you're cutting wins.
	var device := missions.interaction(pos)
	if not device.is_empty():
		return device
	for id in sites:
		var site: ExpeditionSite = sites[id]
		if not site.has_component() or pos.distance_to(site.component_point()) >= INTERACT_RANGE:
			continue
		var r := Campaign.get_repair(id)
		var label := Campaign.sentence(r["component_name"])
		if Game.is_repaired(id):
			return {"label": "%s: Kestrel doesn't need this any more" % label}
		# Out of order it would skip a repair, or replace what's in your hands.
		if id != current:
			return {"label": "%s: no use until the %s is fixed" % [label, Kestrel.REPAIR_NAMES[current].to_lower()]}
		if Game.carrying != "":
			return {"label": "%s: your hands are full" % label}
		if not missions.can_take(id):
			return {"label": "%s: it won't come free yet. %s" % [label, Game.mission_objective]}
		return {"label": "[E] Take the %s" % r["component_name"], "action": _take_component.bind(id)}
	for id in sites:
		var site: ExpeditionSite = sites[id]
		for i in site.crate_count():
			if not site.crate_searched(i) and pos.distance_to(site.crate_point(i)) < INTERACT_RANGE:
				return {"label": "[E] Search salvage crate", "action": _search_crate.bind(site, i)}
	var cache := wildlife.cache_interaction(pos, INTERACT_RANGE) if wildlife else {}
	if not cache.is_empty():
		return cache
	if current != "" and _near_install(current):
		var r := Campaign.get_repair(current)
		if Game.carrying == r["component"]:
			return {"label": "[E] %s" % r["install_label"], "action": _install.bind(current)}
		return {"label": r["bay_label"]}
	if current == "" and _near_install("launch"):
		match finale.state:
			Finale.State.READY:
				return {"label": "[E] Launch Kestrel", "action": launch}
			Finale.State.SPOOLING:
				return {"label": "Pilot's seat: engine spooling, %d%%" % int(finale.progress() * 100.0)}
		if siege.is_active():
			return {"label": "Pilot's seat: clear them off the hull first"}
		return {"label": "[E] Start the engine spool (90 seconds, and they will come)", "action": finale.start}
	if _near_install("bunk"):
		if siege.is_active():
			return {"label": "Bunk: no time to rest with them on the hull"}
		return {"label": "[E] Rest in the bunk and save", "action": rest}
	if _near_install("armoury"):
		if not Game.is_repaired("landing_gear"):
			return {"label": "Armoury locker: jammed shut while the hull is twisted"}
		if not Game.owns_weapon("scattergun"):
			return {"label": "[E] Open the armoury locker", "action": _resupply}
		return {"label": "[E] Resupply: reload and patch the suit", "action": _resupply}
	var bench := kestrel.to_global(kestrel.plan(FABRICATOR_POINT.x, FABRICATOR_POINT.y, FABRICATOR_POINT.z))
	if pos.distance_to(bench) < INTERACT_RANGE + 0.6:
		if not Game.is_repaired("aux_power"):
			return {"label": "Fabricator offline: no power"}
		return {"label": "[E] Use the fabricator (%d scrap)" % Game.scrap, "action": fabricator.open}
	return {}


func _take_component(id: String) -> void:
	var site: ExpeditionSite = sites[id]
	site.take_component()
	Game.take_component(site.component_id)
	Game.find_log(Story.log_at(id, "component"))
	# Taking it stirs the wildlife: an ambush at the site, and on the way home for the first one.
	var ambush := site.ambush_points()
	for i in ambush.size():
		spawn_enemy(site.ambush_kind(i), ambush[i]).alert(false)
	if id == "navigation":
		# The Warden rises out of the glass behind the spire.
		var w := spawn_enemy("warden", (site as LoomSpire).warden_point()) as Warden
		w.alert(false)
		hud.show_boss(w)
	if id == "aux_power":
		var home := kestrel.global_position
		var from := site.global_position
		for t in [0.35, 0.55, 0.75]:
			var p: Vector3 = from.lerp(home, t)
			var side := (home - from).cross(Vector3.UP).normalized() * (9.0 if t != 0.55 else -9.0)
			spawn_scuttler(p + side + Vector3.UP * 0.5).alert(false)


func _install(id: String) -> void:
	Game.install_component()
	kestrel.set_repaired(id, true)
	kestrel.play_repair(id)
	Sfx.play("repair_clunk", (kestrel.repairs[id] as Node3D).global_position, 2.0, 0.0)
	player.anim.play("install")
	voice.say(Story.INSTALLED.get(id, []))
	# A working ship runs hot, and the heat draws the wildlife in.
	if ShipSiege.ARMED_BY.has(id):
		siege.arm(ShipSiege.ARMED_BY[id])
	save_game()


func _search_crate(site: Node3D, i: int) -> void:
	var found: int = site.search_crate(i)
	player.anim.play("interact")
	Game.add_scrap(found)
	Game.find_log(Story.log_at(Campaign.by_component(site.component_id)["id"], "crate:%d" % i))
	var extras: PackedStringArray = []
	var limited := Game.ammo_weapons()
	if not limited.is_empty() and randf() < 0.45:
		var w: String = limited.pick_random()
		var got := Game.add_ammo(w, AMMO_BUNDLE[w])
		if got > 0:
			extras.append("%d %s rounds" % [got, Weapon.SPECS[w]["name"].to_lower()])
	if randf() < 0.3 and Game.add_stims(1) > 0:
		extras.append("a stim")
	hud.show_message("Found %d scrap%s." % [found, "" if extras.is_empty() else ", " + " and ".join(extras)])


func _resupply() -> void:
	if not Game.owns_weapon("scattergun"):
		Game.give_weapon("scattergun")
		player.weapon.equip("scattergun")
		hud.show_message("The armoury held a scattergun and a box of shells. Press 1 and 2 to switch weapons.")
	player.weapon.refill()
	player.health = player.max_health()
	player.health_changed.emit(player.health, player.max_health())
	if Game.owns_weapon("scattergun") and hud.message_age() > 0.5:
		hud.show_message("Resupplied: every weapon full, suit patched.")
	Sfx.play("rifle_reload", null, -2.0, 0.0)


## Lifts off once the spool is full: a cinematic camera watches Kestrel rise, the Loom pulse
## roll out underneath and miss, and the climb into the steam. Then the ending card.
func launch() -> void:
	if Game.current_repair() != "" or Game.launched or finale.state != Finale.State.READY:
		return
	finale.begin_launch()
	Game.launch()
	voice.interrupt(Story.LAUNCH)
	hud.enter_cinematic()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.calm()
	player.visible = false
	player.set_physics_process(false)
	var nose := -kestrel.global_basis.x
	var side := kestrel.global_basis.z
	_cine_cam = Camera3D.new()
	_cine_cam.fov = 62.0
	add_child(_cine_cam)
	_cine_cam.global_position = kestrel.global_position + side * 34.0 + nose * 14.0 + Vector3.UP * 3.0
	_cine_cam.current = true
	kestrel.set_engine_power(1.0)
	var lift := create_tween()
	lift.tween_property(kestrel, "position:y", kestrel.position.y + 6.0, LIFT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	lift.tween_callback(_loom_misses)
	lift.tween_property(kestrel, "rotation:z", -0.3, 1.2).set_trans(Tween.TRANS_SINE)
	lift.parallel().tween_property(kestrel, "position", kestrel.position + Vector3.UP * 6.0 + nose * 160.0 + Vector3.UP * 90.0, CLIMB_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	lift.tween_callback(_show_ending)
	Sfx.play("launch_roar", null, 2.0, 0.0)


## New game: Kestrel comes down. She streaks in trailing smoke along the furrow, hits, throws up
## a wall of dust and steam, ploughs to a stop where she lies for the rest of the game, and the
## camera hands over to Juno inside. Interact, jump or Esc skips.
func play_intro() -> void:
	intro_playing = true
	hud.enter_cinematic()
	player.visible = false
	player.set_physics_process(false)
	_intro_rest = kestrel.transform
	var nose := -kestrel.global_basis.x
	var side := kestrel.global_basis.z
	var rest := _intro_rest.origin
	var touch := rest - nose * 16.0
	_cine_cam = Camera3D.new()
	_cine_cam.fov = 58.0
	add_child(_cine_cam)
	_cine_cam.global_position = rest + nose * 26.0 + side * 30.0 + Vector3.UP * 5.0
	_cine_cam.current = true
	kestrel.position = touch - nose * 150.0 + Vector3.UP * 60.0
	kestrel.rotation.z = kestrel.rotation.z - 0.25
	kestrel.set_engine_power(0.5)
	for x in [8.0, 30.0]:
		_intro_smoke.append(Vfx.smoke(kestrel, kestrel.plan(x, 2.5, 13.0)))
	_intro_tween = create_tween()
	_intro_tween.tween_property(kestrel, "position", touch, INTRO_FALL).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_intro_tween.parallel().tween_property(kestrel, "rotation:z", _intro_rest.basis.get_euler().z, INTRO_FALL)
	_intro_tween.tween_callback(_intro_impact)
	_intro_tween.tween_property(kestrel, "position", rest, INTRO_SLIDE).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_interval(INTRO_HOLD)
	_intro_tween.tween_callback(end_intro)
	Sfx.play("loom_hum", null, -4.0, 0.0)


func _intro_impact() -> void:
	_shake = 1.0
	kestrel.set_engine_power(0.0)
	Vfx.dust(self, Vector3(kestrel.global_position.x, 0.5, kestrel.global_position.z), 1.6)
	Sfx.play("crash_impact", null, 4.0, 0.0)


## Ends the intro (or skips it): Kestrel at her crash site, Juno in control, the opening lines.
func end_intro() -> void:
	if not intro_playing:
		return
	intro_playing = false
	if _intro_tween:
		_intro_tween.kill()
	kestrel.transform = _intro_rest
	kestrel.set_engine_power(0.0)
	for s in _intro_smoke:
		if is_instance_valid(s):
			s.emitting = false
			get_tree().create_timer(3.0).timeout.connect(s.queue_free)
	_intro_smoke.clear()
	_shake = 0.0
	if _cine_cam:
		_cine_cam.queue_free()
		_cine_cam = null
	player.visible = true
	player.set_physics_process(true)
	player.revive(SPAWN, false)
	player.camera().current = true
	hud.exit_cinematic()
	voice.say(Story.OPENING)


## The top bar's caption during an assault: the wave count, or the spool in the finale.
func _siege_label(wave_index: int) -> String:
	if siege.active == ShipSiege.FINALE:
		return finale.bar_text()
	return "WAVE %d / %d" % [wave_index + 1, siege.waves_in(maxi(siege.active, 0))]


## The Loom's beat arrives a moment after lift-off and rolls under her.
func _loom_misses() -> void:
	var pulse := LoomPulse.new()
	pulse.one_shot = true
	pulse.damage = 0.0
	pulse.knockback = 0.0
	pulse.speed = 40.0
	pulse.max_radius = 150.0
	pulse.ring_height = 2.0
	add_child(pulse)
	pulse.global_position = Vector3(kestrel.global_position.x, 0.2, kestrel.global_position.z)
	pulse.fire()
	Sfx.play("loom_hum", null, 0.0, 0.0)


func _show_ending() -> void:
	Game.find_log(Story.ORBIT_LOG["id"])
	var text := "\n\n".join(Story.ENDING)
	text += "\n\n\"%s\"" % Story.ORBIT_LOG["text"]
	text += "\n\nHARD LANDING\n\nPress E to return to the title"
	hud.show_ending(text)
	ending_shown = true


func _waypoint():
	match Game.phase():
		"find":
			var stage_point = missions.waypoint()
			return stage_point if stage_point != null else current_site().component_point()
		"return":
			return install_point(Game.current_repair())
		"launch":
			return install_point("launch")
		"done":
			return null
	if Game.is_repaired("aux_power") and Game.listed_upgrades().any(func(id): return FabricatorMenu.blocker(id) == ""):
		return kestrel.to_global(kestrel.plan(FABRICATOR_POINT.x, FABRICATOR_POINT.y, FABRICATOR_POINT.z))
	return null


# --- Events -------------------------------------------------------------------------------

func _on_ammo_changed(in_mag: int, mag_size: int, reloading: bool) -> void:
	var w := player.weapon
	hud.set_ammo(in_mag, mag_size, reloading)
	hud.set_weapon_info(w.spec()["name"], Game.ammo_reserve(w.current))


func _on_enemy_died(e: Enemy) -> void:
	for i in randi_range(e.drops.x, e.drops.y):
		_drop("scrap", randi_range(4, 5), e.global_position)
	var limited := Game.ammo_weapons()
	if not limited.is_empty() and randf() < 0.25:
		var w: String = limited.pick_random()
		_drop(w, AMMO_DROP[w], e.global_position)
	if randf() < 0.08:
		_drop("stim", 1, e.global_position)
	if randf() < 0.06:
		_drop("charge", 1, e.global_position)


func _drop(kind: String, amount: int, at: Vector3) -> ScrapPickup:
	var p := ScrapPickup.new()
	p.kind = kind
	p.amount = amount
	p.target = player
	add_child(p)
	p.global_position = at + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	return p


## Aux power brings the ship to life: a hum you can hear from the workshop.
func _on_repair_changed(id: String, repaired: bool) -> void:
	Game.set_repaired(id, repaired)
	_update_active_site()
	if id != "aux_power":
		return
	if repaired and _ship_hum == null:
		var anchor := Node3D.new()
		kestrel.add_child(anchor)
		anchor.position = kestrel.plan(FABRICATOR_POINT.x, 1.6, FABRICATOR_POINT.z - 2.0)
		_ship_hum = Sfx.loop("ship_hum_loop", anchor, -6.0)
	elif not repaired and _ship_hum:
		_ship_hum.get_parent().queue_free()
		_ship_hum = null


func _on_player_died() -> void:
	hud.set_dead(true)
	for s in get_tree().get_nodes_in_group("enemies"):
		s.calm()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	player.revive(SPAWN)
	hud.set_dead(false)


# --- Setup --------------------------------------------------------------------------------

func _dev_text() -> String:
	var lines: PackedStringArray = ["DEV  1-7 repairs · N dusk · K +50 scrap · T current site · H home · M skip stage"]
	for i in Kestrel.REPAIR_ORDER.size():
		var id := Kestrel.REPAIR_ORDER[i]
		lines.append("%d %s %s" % [i + 1, Kestrel.REPAIR_NAMES[id], "■" if kestrel.is_repaired(id) else "□"])
	var boom := player.boom_current()
	lines.append("Camera boom %.1f m%s" % [boom, "  SQUEEZED" if boom < player.boom_target() - 0.2 else ""])
	lines.append("Hostiles alive: %d" % get_tree().get_nodes_in_group("enemies").size())
	return "\n".join(lines)


func _setup_input() -> void:
	for action in KEYS:
		_ensure_action(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in BUTTONS:
		_ensure_action(action)
		for button in BUTTONS[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)


func _ensure_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)


func _build_environment() -> void:
	_sky = ShaderMaterial.new()
	_sky.shader = preload("res://shaders/sky.gdshader")
	var clouds := NoiseTexture2D.new()
	clouds.width = 512
	clouds.height = 512
	clouds.seamless = true
	var cloud_noise := FastNoiseLite.new()
	cloud_noise.frequency = 0.008
	cloud_noise.fractal_octaves = 5
	clouds.noise = cloud_noise
	_sky.set_shader_parameter("cloud_noise", clouds)
	var sky := Sky.new()
	sky.sky_material = _sky
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	_env.ssao_enabled = true
	_env.ssao_radius = 1.6
	_env.ssao_intensity = 2.2
	_env.ssil_radius = 4.0
	_env.ssil_intensity = 0.8
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.set_glow_level(0, 0.0)
	_env.set_glow_level(2, 1.0)
	_env.set_glow_level(4, 0.8)
	_env.set_glow_level(5, 0.5)
	_env.fog_enabled = true
	# Steam hangs low over the wetlands: fog thickens toward the ground.
	_env.fog_height = 3.0
	_env.fog_height_density = 0.04
	_env.fog_sun_scatter = 0.15
	_env.fog_sky_affect = 0.25
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.08
	_env.adjustment_saturation = 1.1
	_env.glow_bloom = 0.05
	_env.glow_hdr_threshold = 0.9
	# Volumetric fog is always on so local FogVolumes (spore fog) render. On Quality it also
	# fills the basin with a thin haze the sun shines through (light shafts at dusk).
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.0
	_env.volumetric_fog_anisotropy = 0.55
	_env.volumetric_fog_length = 96.0
	_env.volumetric_fog_detail_spread = 1.5
	_env.volumetric_fog_ambient_inject = 0.1
	_env.volumetric_fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 150.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_blend_splits = true
	_sun.light_angular_distance = 0.6
	_sun.light_volumetric_fog_energy = 1.4
	add_child(_sun)
	Game.graphics_changed.connect(_apply_graphics)
	_apply_graphics()


## Quality adds screen-space indirect light and the basin haze; Performance drops both.
func _apply_graphics() -> void:
	var quality := Game.graphics >= 1
	_env.ssil_enabled = quality
	_sun.light_angular_distance = 0.6 if quality else 0.0
	if site:
		set_daylight(daylight)


## Day keeps the basalt readable (bright sky, low sun). Dusk shows the amber interior as home.
## Dev toggle (N): jumps to full day or full dusk and stops the cycle there.
func _set_dusk(value: bool) -> void:
	set_daylight(1.0 if value else 0.0)


## Blends the basin between day (0) and dusk (1): sky, sun angle and colour, ambient light, fog,
## and the moss glow, which comes up as the light goes.
func set_daylight(amount: float) -> void:
	daylight = clampf(amount, 0.0, 1.0)
	dusk = daylight > 0.5
	var k := daylight
	# A storm (Weather) drags everything toward low cloud, rain-dark light and thick haze.
	var w := clampf(storm, 0.0, 1.0)
	var top := Color("6f8590").lerp(Color("232b3d"), k)
	var horizon := Color("c9cfca").lerp(Color("c27a52"), k)
	_sky.set_shader_parameter("top_color", top.lerp(Color("3a4247").lerp(Color("1a1e26"), k), w))
	_sky.set_shader_parameter("horizon_color", horizon.lerp(Color("737b7c").lerp(Color("4a3a3a"), k), w))
	_sky.set_shader_parameter("ground_color", Color("2a2f31").lerp(Color("15161a"), k))
	_sky.set_shader_parameter("sun_tint", Color("fff1dc").lerp(Color("ffab6b"), k))
	_sky.set_shader_parameter("cloud_light", Color("eeeeea").lerp(Color("e39a6e"), k).lerp(Color("8e9597"), w * 0.8))
	_sky.set_shader_parameter("cloud_dark", Color("7b858a").lerp(Color("3a3448"), k).lerp(Color("2c3134"), w))
	_sky.set_shader_parameter("cloud_cover", lerpf(0.55, 0.95, w))
	_sky.set_shader_parameter("sun_glow", lerpf(0.8, 1.6, k) * (1.0 - w * 0.85))
	_sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0).lerp(Vector3(-8.0, 60.0, 0.0), k)
	_sun.light_color = Color("fff3e0").lerp(Color("ff9a6a"), k).lerp(Color("c9d3d8"), w * 0.6)
	_sun.light_energy = lerpf(1.0, 0.25, k) * (1.0 - w * 0.6) + flash
	_env.ambient_light_energy = lerpf(0.4, 0.3, k) * (1.0 - w * 0.25) + flash * 0.3
	_env.fog_light_color = Color("8f9a9c").lerp(Color("3a3540"), k).lerp(Color("5d6568").lerp(Color("2a2a32"), k), w)
	_env.fog_density = lerpf(0.002, 0.004, k) + w * 0.011
	if Game.graphics >= 1:
		_env.volumetric_fog_density = lerpf(0.0022, 0.007, k) + w * 0.006
		_env.volumetric_fog_albedo = Color("c9d2d0").lerp(Color("d9a58a"), k)
	else:
		_env.volumetric_fog_density = 0.0
	site.set_glow(k)
	site.set_rain(w)
