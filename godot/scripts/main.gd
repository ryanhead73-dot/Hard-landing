extends Node3D
## Game flow: sky and sun, player, HUD, enemies, interactions and dev controls.
## The campaign (see Campaign) restores Kestrel one repair at a time: follow the active site's
## beacon, recover its component, carry it home and install it. Each repair turns on a benefit.
## When all seven are done, the pilot's seat launches Kestrel.

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
const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"crouch": [KEY_C, KEY_CTRL],
	"interact": [KEY_E],
	"flashlight": [KEY_F],
	"reload": [KEY_R],
}
const BUTTONS := {
	"fire": [MOUSE_BUTTON_LEFT],
	"aim": [MOUSE_BUTTON_RIGHT],
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
var dusk := false
var dev_panel := false

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _interaction: Dictionary = {}
var _ship_hum: Node
var _pack_check := 0.0


func _ready() -> void:
	_setup_input()
	_build_environment()
	Game.reset()

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.revive(SPAWN)

	hud = Hud.new()
	add_child(hud)
	player.health_changed.connect(hud.set_health)
	player.damaged.connect(func(_amount): hud.flash_damage())
	player.died.connect(_on_player_died)
	player.weapon.ammo_changed.connect(hud.set_ammo)
	player.weapon.hit_confirmed.connect(hud.hitmarker)
	Game.scrap_changed.connect(hud.set_scrap)
	Game.objective_changed.connect(hud.set_objective)
	Game.message.connect(hud.show_message)
	hud.set_health(player.health, player.max_health())
	hud.set_ammo(player.weapon.in_mag, player.weapon.mag_size(), false)
	hud.set_scrap(Game.scrap)
	hud.set_objective(Game.objective_text())
	hud.show_message("Kestrel is dead without power. Follow the red beacon to the relay station and find a power cell.")

	add_child(PauseMenu.new())
	Sfx.loop("wind_loop", null, -14.0)
	for r in Campaign.REPAIRS:
		var site: ExpeditionSite = get_node(String(r["site"]))
		sites[r["id"]] = site
		# Only the site you're heading for pings, so the sound points the way.
		site.beacon_flashed.connect(func(at: Vector3):
			if site.active:
				Sfx.play("beacon_ping", at, -4.0, 0.0))
	kestrel.repair_changed.connect(_on_repair_changed)
	for id in Kestrel.REPAIR_ORDER:
		Game.set_repaired(id, kestrel.is_repaired(id))
	for p in ROAMER_POINTS:
		spawn_scuttler(p)
	_update_active_site()
	_set_dusk(false)


func _process(_delta: float) -> void:
	_interaction = _find_interaction()
	hud.set_prompt(_interaction.get("label", ""))
	if _interaction.has("action") and Input.is_action_just_pressed("interact") and not player.dead:
		(_interaction["action"] as Callable).call()
	hud.set_waypoint(_waypoint())
	hud.set_scan(scanner_marks())
	_pack_check -= _delta
	if _pack_check <= 0.0:
		_pack_check = 0.5
		_wake_packs()
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
		hud.set_dev(dev_panel, _dev_text())
	elif not dev_panel:
		return
	elif key >= KEY_1 and key <= KEY_7:
		kestrel.toggle_repair(Kestrel.REPAIR_ORDER[key - KEY_1])
	elif key == KEY_N:
		_set_dusk(not dusk)
	elif key == KEY_K:
		Game.add_scrap(50)
	elif key == KEY_T:
		var site := current_site()
		if site:
			player.revive(site.component_point() + Vector3.UP * 0.5)
	elif key == KEY_H:
		player.revive(SPAWN)


func spawn_scuttler(at: Vector3) -> Scuttler:
	var s := Scuttler.new()
	s.target = player
	s.home = at
	add_child(s)
	s.global_position = at
	s.died.connect(_on_scuttler_died)
	return s


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


## Spawns a hostile of the given kind. Only scuttlers exist so far.
func spawn_enemy(_kind: String, at: Vector3) -> Node3D:
	return spawn_scuttler(at)


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
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(pos) < SCAN_ENEMIES:
			marks.append({"pos": e.global_position, "kind": "enemy"})
	return marks


# --- Interactions -------------------------------------------------------------------------

func _find_interaction() -> Dictionary:
	if player.dead or Game.launched:
		return {}
	var pos := player.global_position
	var current := Game.current_repair()
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
		return {"label": "[E] Take the %s" % r["component_name"], "action": _take_component.bind(id)}
	for id in sites:
		var site: ExpeditionSite = sites[id]
		for i in site.crate_count():
			if not site.crate_searched(i) and pos.distance_to(site.crate_point(i)) < INTERACT_RANGE:
				return {"label": "[E] Search salvage crate", "action": _search_crate.bind(site, i)}
	if current != "" and _near_install(current):
		var r := Campaign.get_repair(current)
		if Game.carrying == r["component"]:
			return {"label": "[E] %s" % r["install_label"], "action": _install.bind(current)}
		return {"label": r["bay_label"]}
	if current == "" and _near_install("launch"):
		return {"label": "[E] Launch Kestrel", "action": launch}
	if _near_install("armoury"):
		if not Game.is_repaired("landing_gear"):
			return {"label": "Armoury locker: jammed shut while the hull is twisted"}
		return {"label": "[E] Resupply: reload and patch the suit", "action": _resupply}
	var bench := kestrel.to_global(kestrel.plan(FABRICATOR_POINT.x, FABRICATOR_POINT.y, FABRICATOR_POINT.z))
	if pos.distance_to(bench) < INTERACT_RANGE + 0.6:
		if not Game.is_repaired("aux_power"):
			return {"label": "Fabricator offline: no power"}
		var id := Game.next_upgrade()
		if id == "":
			return {"label": "Fabricator: every upgrade built"}
		var info: Dictionary = Game.UPGRADES[id]
		if not Game.can_fabricate(id):
			return {"label": "%s: %s" % [info["name"], Game.NEEDS_TEXT[info["needs"]]]}
		if Game.scrap < int(info["cost"]):
			return {"label": "%s needs %d scrap (%s)" % [info["name"], info["cost"], info["effect"]]}
		return {"label": "[E] Fabricate %s, %d scrap (%s)" % [info["name"], info["cost"], info["effect"]], "action": Game.buy_upgrade.bind(id)}
	return {}


func _take_component(id: String) -> void:
	var site: ExpeditionSite = sites[id]
	site.take_component()
	Game.take_component(site.component_id)
	# Taking it stirs the wildlife: an ambush at the site, and on the way home for the first one.
	for p in site.ambush_points():
		spawn_enemy("scuttler", p).alert(false)
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


func _search_crate(site: Node3D, i: int) -> void:
	var found: int = site.search_crate(i)
	Game.add_scrap(found)
	hud.show_message("Found %d scrap." % found)


func _resupply() -> void:
	player.weapon.refill()
	player.health = player.max_health()
	player.health_changed.emit(player.health, player.max_health())
	hud.show_message("Resupplied: magazine full, suit patched.")
	Sfx.play("rifle_reload", null, -2.0, 0.0)


## Lifts off. The full departure sequence lives in a later milestone; this ends the run.
func launch() -> void:
	if Game.current_repair() != "" or Game.launched:
		return
	Game.launch()
	hud.show_ending()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.calm()
	player.visible = false
	player.set_physics_process(false)
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(kestrel, "position:y", kestrel.position.y + 80.0, 8.0)
	Sfx.play("power_up")


func _waypoint():
	match Game.phase():
		"find":
			return current_site().component_point()
		"return":
			return install_point(Game.current_repair())
		"launch":
			return install_point("launch")
		"done":
			return null
	var id := Game.next_upgrade()
	if id != "" and Game.can_fabricate(id) and Game.scrap >= int(Game.UPGRADES[id]["cost"]):
		return kestrel.to_global(kestrel.plan(FABRICATOR_POINT.x, FABRICATOR_POINT.y, FABRICATOR_POINT.z))
	return null


# --- Events -------------------------------------------------------------------------------

func _on_scuttler_died(s: Scuttler) -> void:
	for i in randi_range(1, 2):
		var scrap := ScrapPickup.new()
		scrap.amount = randi_range(4, 5)
		scrap.target = player
		add_child(scrap)
		scrap.global_position = s.global_position + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))


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
	for s in get_tree().get_nodes_in_group("scuttlers"):
		s.calm()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	player.revive(SPAWN)
	hud.set_dead(false)


# --- Setup --------------------------------------------------------------------------------

func _dev_text() -> String:
	var lines: PackedStringArray = ["DEV  1-7 repairs · N dusk · K +50 scrap · T current site · H home"]
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
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.fog_enabled = true
	# Volumetric fog stays at zero density globally; it lets local FogVolumes (spore fog) render.
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.0
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 150.0
	add_child(_sun)


## Day keeps the basalt readable (bright sky, low sun). Dusk shows the amber interior as home.
func _set_dusk(value: bool) -> void:
	dusk = value
	if dusk:
		_sky.sky_top_color = Color("1d2733")
		_sky.sky_horizon_color = Color("5b4a52")
		_sky.ground_horizon_color = Color("2a2a30")
		_sky.ground_bottom_color = Color("0e1012")
		_sun.rotation_degrees = Vector3(-8.0, 60.0, 0.0)
		_sun.light_color = Color("ff9a6a")
		_sun.light_energy = 0.25
		_env.ambient_light_energy = 0.3
		_env.fog_light_color = Color("3a3540")
		_env.fog_density = 0.004
	else:
		_sky.sky_top_color = Color("7d8a8f")
		_sky.sky_horizon_color = Color("b7bfbd")
		_sky.ground_horizon_color = Color("3c4448")
		_sky.ground_bottom_color = Color("1b1d1f")
		_sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
		_sun.light_color = Color("fff3e0")
		_sun.light_energy = 1.0
		_env.ambient_light_energy = 0.4
		_env.fog_light_color = Color("8f9a9c")
		_env.fog_density = 0.002
	site.set_dusk(dusk)
