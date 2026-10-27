extends Node3D
## Vertical slice flow: sky and sun, player, HUD, enemies, interactions and dev controls.
## Loop: recover the aux power cell from the relay station, carry it home, install it,
## then spend scrap at the now-powered workshop fabricator.

const SPAWN := Vector3(-3.0, 0.5, 15.0)
const INTERACT_RANGE := 1.8
const FABRICATOR_POINT := Vector3(16.2, 0.0, 10.7)
const ROAMER_POINTS := [Vector3(-28.0, 0.5, 30.0), Vector3(-42.0, 0.5, 22.0)]
const RESPAWN_DELAY := 2.5
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

var player: Player
var hud: Hud
var dusk := false
var dev_panel := false

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _interaction: Dictionary = {}


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

	for p in station.spawn_points():
		spawn_scuttler(p)
	for p in ROAMER_POINTS:
		spawn_scuttler(p)
	_set_dusk(false)


func _process(_delta: float) -> void:
	_interaction = _find_interaction()
	hud.set_prompt(_interaction.get("label", ""))
	if _interaction.has("action") and Input.is_action_just_pressed("interact") and not player.dead:
		(_interaction["action"] as Callable).call()
	hud.set_waypoint(_waypoint())
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
		player.revive(station.cell_point() + Vector3(0.0, 0.5, 4.0))
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


# --- Interactions -------------------------------------------------------------------------

func _find_interaction() -> Dictionary:
	if player.dead:
		return {}
	var pos := player.global_position
	if station.has_cell() and pos.distance_to(station.cell_point()) < INTERACT_RANGE:
		return {"label": "[E] Take the aux power cell", "action": _take_cell}
	for i in station.crate_count():
		if not station.crate_searched(i) and pos.distance_to(station.crate_point(i)) < INTERACT_RANGE:
			return {"label": "[E] Search salvage crate", "action": _search_crate.bind(i)}
	var aux_point := kestrel.to_global(kestrel.interact_points["aux_power"])
	if not kestrel.is_repaired("aux_power") and pos.distance_to(aux_point) < INTERACT_RANGE:
		if Game.carrying == "aux_cell":
			return {"label": "[E] Install the aux power cell", "action": _install_cell}
		return {"label": "Aux power bay: needs a replacement power cell"}
	var bench := kestrel.to_global(kestrel.plan(FABRICATOR_POINT.x, FABRICATOR_POINT.y, FABRICATOR_POINT.z))
	if pos.distance_to(bench) < INTERACT_RANGE + 0.6:
		if not kestrel.is_repaired("aux_power"):
			return {"label": "Fabricator offline: no power"}
		var id := Game.next_upgrade()
		if id == "":
			return {"label": "Fabricator: every upgrade built"}
		var info: Dictionary = Game.UPGRADES[id]
		if Game.scrap < int(info["cost"]):
			return {"label": "%s needs %d scrap (%s)" % [info["name"], info["cost"], info["effect"]]}
		return {"label": "[E] Fabricate %s, %d scrap (%s)" % [info["name"], info["cost"], info["effect"]], "action": Game.buy_upgrade.bind(id)}
	return {}


func _take_cell() -> void:
	station.take_cell()
	Game.take_cell()
	# The cell's hum draws the scuttlers out: an ambush on the way home.
	var home := kestrel.global_position
	var from := station.global_position
	for t in [0.35, 0.55, 0.75]:
		var p: Vector3 = from.lerp(home, t)
		var side := (home - from).cross(Vector3.UP).normalized() * (9.0 if t != 0.55 else -9.0)
		spawn_scuttler(p + side + Vector3.UP * 0.5).alert(false)


func _search_crate(i: int) -> void:
	var found := station.search_crate(i)
	Game.add_scrap(found)
	hud.show_message("Found %d scrap." % found)


func _install_cell() -> void:
	kestrel.set_repaired("aux_power", true)
	Game.install_cell()


func _waypoint():
	match Game.stage:
		Game.Stage.RECOVER_CELL:
			return station.cell_point()
		Game.Stage.RETURN_CELL:
			return kestrel.to_global(kestrel.interact_points["aux_power"])
	var id := Game.next_upgrade()
	if id != "" and Game.scrap >= int(Game.UPGRADES[id]["cost"]):
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


func _on_player_died() -> void:
	hud.set_dead(true)
	for s in get_tree().get_nodes_in_group("scuttlers"):
		s.calm()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	player.revive(SPAWN)
	hud.set_dead(false)


# --- Setup --------------------------------------------------------------------------------

func _dev_text() -> String:
	var lines: PackedStringArray = ["DEV  1-7 repairs · N dusk · K +50 scrap · T station · H home"]
	for i in Kestrel.REPAIR_ORDER.size():
		var id := Kestrel.REPAIR_ORDER[i]
		lines.append("%d %s %s" % [i + 1, Kestrel.REPAIR_NAMES[id], "■" if kestrel.is_repaired(id) else "□"])
	var boom := player.boom_current()
	lines.append("Camera boom %.1f m%s" % [boom, "  SQUEEZED" if boom < player.boom_target() - 0.2 else ""])
	lines.append("Scuttlers alive: %d" % get_tree().get_nodes_in_group("scuttlers").size())
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
