extends Node
## Session state for the vertical slice: salvage, what the player carries, workshop upgrades
## and the current objective. Autoloaded as "Game".

signal scrap_changed(amount: int)
signal carrying_changed(item: String)
signal upgrades_changed
signal objective_changed(text: String)
signal message(text: String)
signal settings_changed
signal graphics_changed
signal repairs_changed
signal inventory_changed
signal log_found(id: String)
## A world flag changed (see set_flag).
signal flag_changed(id: String, value: Variant)

## Physics layer bits shared by every script.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

const UPGRADE_ORDER: Array[String] = [
	"extended_mag", "stim_pouch", "plating", "heavy_rounds", "regen_servo", "scatter_choke",
	"rapid_cycler", "plating_2", "arc_lance", "arc_capacitor",
]
## needs: the repair that powers the build. weapon: only offered once you own that weapon.
## Heavy builds overheat the fabricator until cooling is repaired; the top tier runs on engine bleed.
const UPGRADES := {
	"extended_mag": {"name": "Extended magazine", "cost": 30, "effect": "Rifle magazine 24 to 36 rounds", "needs": ""},
	"stim_pouch": {"name": "Stim pouch", "cost": 35, "effect": "Carry 5 stims instead of 3", "needs": ""},
	"plating": {"name": "Suit plating", "cost": 40, "effect": "Max health +40", "needs": "cooling"},
	"heavy_rounds": {"name": "Heavy rounds", "cost": 45, "effect": "+30% damage, every weapon", "needs": "cooling"},
	"regen_servo": {"name": "Regen servo", "cost": 40, "effect": "Suit recovers sooner and faster", "needs": "cooling"},
	"scatter_choke": {"name": "Scattergun choke", "cost": 40, "effect": "Tighter spread, +2 shells", "needs": "cooling", "weapon": "scattergun"},
	"rapid_cycler": {"name": "Rapid cycler", "cost": 60, "effect": "+25% fire rate, every weapon", "needs": "engine"},
	"plating_2": {"name": "Reinforced plating", "cost": 70, "effect": "Max health +40 more", "needs": "engine"},
	"arc_lance": {"name": "Arc lance", "cost": 80, "effect": "Charged beam that pierces a line of targets", "needs": "engine", "grants": "arc_lance"},
	"arc_capacitor": {"name": "Arc capacitor", "cost": 50, "effect": "+2 lance cells, faster recharge", "needs": "engine", "weapon": "arc_lance"},
}
const STIM_COST := 15
const STIM_HEAL := 55.0
const CHARGE_COST := 20
const NEEDS_TEXT := {
	"cooling": "the fabricator overheats on heavy builds until cooling is fixed",
	"engine": "top-tier builds need engine bleed power",
}

var settings_path := "user://settings.cfg"
## The save format this build writes; older saves are upgraded by SaveMigrations.
const SAVE_VERSION := SaveMigrations.CURRENT

var mouse_sensitivity := 0.0025
var invert_y := false
## Controller vibration (rumble) on shots, hits taken, blasts and big kills.
var vibration := true
## The last rumble asked for, [weak, strong, seconds], and how many there have been (for tests).
var last_rumble := Vector3.ZERO
var rumbles := 0
## True after the last input came from a gamepad; prompts and look follow it.
var using_pad := false
signal input_device_changed(pad: bool)
## Right-stick look speed in radians per second at full deflection (the settings slider scales it).
var pad_look_speed := 3.2
## Controller look sensitivity, a multiplier on pad_look_speed (separate from the mouse).
const PAD_SENSITIVITY_RANGE := Vector2(0.4, 2.0)
var pad_sensitivity := 1.0
## Key or button names shown in prompts, keyboard first, then gamepad.
const PROMPT_KEYS := {
	"interact": ["E", "Y"], "stim": ["Q", "LB"], "throw": ["G", "RB"], "logs": ["L", "D-pad left"], "journal": ["J", "D-pad left"],
	"map": ["M", "D-pad down"], "inventory": ["Tab", "View"], "reload": ["R", "X"], "dodge": ["V", "B"],
}
var master_volume := 0.8
var music_volume := 0.7
## Sound effects (the SFX bus: weapons, creatures, machines, UI).
var sfx_volume := 1.0
## The frame-rate readout (F3).
var show_fps := false
## Subtitles: 0 off, 1 on, 2 large, 3 largest.
const SUBTITLE_NAMES := ["Off", "On", "Large", "Largest"]
const SUBTITLE_SCALE := [1.0, 1.0, 1.25, 1.5]
var subtitles := 1
## Aim by holding the button (false) or press once to aim, again to stop (true).
var toggle_aim := false
var difficulty := 1
## Camera shake strength (0 turns it off).
var screen_shake := 1.0
## Graphics preset: 0 Low, 1 Medium (the target: a GTX 1660-class card at 1080p60), 2 High.
## main.gd applies it; anything with its own cost (particles, shadowed lamps) checks it too.
const GRAPHICS_LOW := 0
const GRAPHICS_MEDIUM := 1
const GRAPHICS_HIGH := 2
const GRAPHICS_NAMES := ["Low", "Medium", "High"]
var graphics := GRAPHICS_MEDIUM

## Display. Fullscreen is borderless at the desktop resolution; Exclusive hands the monitor to
## the game. Alt+Enter flips between windowed and fullscreen.
const WINDOW_NAMES := ["Windowed", "Fullscreen", "Exclusive fullscreen"]
const WINDOW_MODES := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
var window_mode := 1
var vsync := true
## Frame-rate cap; 0 means none.
const FPS_CAPS := [0, 30, 60, 120, 144]
var fps_cap := 0
## Picture brightness (the environment's brightness adjustment), 1.0 as graded.
const BRIGHTNESS_RANGE := Vector2(0.7, 1.4)
var brightness := 1.0
var _shown_window := -1

var scrap := 0
## The component on the player's back (a Campaign component id), or "".
var carrying := ""
var upgrades: Dictionary = {}
## Mirrors Kestrel's repair states (id -> true), so dev toggles drive the campaign too.
var repaired: Dictionary = {}
var launched := false
## Set by the finale while it runs (the launch phase has steps of its own).
var launch_objective := ""
## Story logs found, in the order they were found.
var logs: Array[String] = []
## Drift caches out on the basin that have been opened, by index (see wildlife.gd).
var caches_opened: Array[int] = []
## Drift caches spotted (they go on the map).
var caches_seen: Array[int] = []
## First-time hints already shown (Onboarding).
var hints_seen: Array[String] = []
## Owned weapons, and ammo per weapon: id -> [in magazine, reserve] (reserve -1 is unlimited).
var weapons: Array[String] = ["rifle"]
var ammo: Dictionary = {}
var stims := 1
## Arc charges carried (thrown with G).
var charges := 1
## Main sets this while the F1 dev panel is open, so number keys toggle repairs, not weapons.
var dev_panel_open := false
## Where the campaign saves. Tests point this elsewhere so they never touch a real save.
var save_path := "user://save.json"
## A save to apply when the game scene starts (set by the title screen's Continue), or empty.
var pending_load: Dictionary = {}
## Mission progress: repair id -> stage index, and the devices worked in the current stage.
var mission_stage: Dictionary = {}
var mission_done: Array = []
## The current mission stage's objective line (set by MissionRunner), or "".
var mission_objective := ""
## A region mission's own line while Juno is there for a sourced repair (FerroCanopy), or "".
var region_objective := ""
## The opening's own objective line (see Opening); wins over the campaign's while it is set.
var opening_objective := ""
## Set by the title screen for a new game: main plays the crash intro once.
var intro_pending := false

## Expansion state (save v2). The region Juno is in (see RegionDB), the campaign act (1-4),
## world flags (id -> value, set by quests, discoveries and dialogue) and the quest log
## (quest id -> {state, step}; see QuestDB).
var region := SaveMigrations.DEFAULT_REGION
var act := 1
var flags: Dictionary = {}
var quests: Dictionary = {}


## The name to show for an action's key on the current device.
func key_name(action: String) -> String:
	var names: Array = PROMPT_KEYS.get(action, [action, action])
	return names[1 if using_pad else 0]


## Rewrites keyboard prompts ("[E] ...", "[Hold E] ...") for the current device and the
## player's key bindings.
func device_text(text: String) -> String:
	if not using_pad:
		return keyboard_text(text)
	return text.replace("[Hold E]", "[Hold %s]" % key_name("interact")).replace("[E]", "[%s]" % key_name("interact"))


# --- Key bindings ---------------------------------------------------------------------------

## Keyboard actions the player can rebind, in the order the bindings menu lists them, with
## their names there. Each has one primary key (rebindable) after main.KEYS' defaults; any
## secondary default key (arrows, Ctrl, Alt, I) stays as it is.
const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"],
	["move_right", "Move right"], ["sprint", "Sprint"], ["jump", "Jump"], ["crouch", "Crouch"],
	["dodge", "Roll"], ["interact", "Interact"], ["reload", "Reload"], ["stim", "Use stim"],
	["throw", "Throw arc charge"], ["flashlight", "Flashlight"], ["weapon_1", "Rifle"],
	["weapon_2", "Scattergun"], ["weapon_3", "Arc lance"], ["inventory", "Inventory"],
	["map", "Map"], ["logs", "Logs"], ["journal", "Journal"],
]
## Defaults, filled from main.KEYS when the game scene first sets up input.
var default_keys: Dictionary = {}
## action -> physical keycode the player chose.
var key_overrides: Dictionary = {}
signal keys_changed


func primary_key(action: String) -> int:
	if key_overrides.has(action):
		return key_overrides[action]
	var keys: Array = default_keys.get(action, [])
	return keys[0] if keys.size() > 0 else KEY_NONE


func key_label(action: String) -> String:
	var k := primary_key(action)
	return OS.get_keycode_string(k) if k != KEY_NONE else "?"


## Binds `action`'s primary key to `key`. A key already on another action swaps over, so no key
## does two things and nothing is left unbound.
func rebind(action: String, key: int) -> void:
	var old := primary_key(action)
	for pair in REBINDABLE:
		var other: String = pair[0]
		if other != action and primary_key(other) == key:
			_set_key(other, old)
	_set_key(action, key)
	apply_keys()
	keys_changed.emit()


func reset_keys() -> void:
	key_overrides.clear()
	apply_keys()
	keys_changed.emit()


func _set_key(action: String, key: int) -> void:
	var keys: Array = default_keys.get(action, [])
	if keys.size() > 0 and keys[0] == key:
		key_overrides.erase(action)
	else:
		key_overrides[action] = key


## Puts the bindings into the InputMap: the primary key (chosen or default) plus the defaults'
## secondary keys, unless one of those is now another action's primary.
func apply_keys() -> void:
	var taken := {}
	for action in default_keys:
		taken[primary_key(action)] = action
	for action in default_keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		var keys: Array = [primary_key(action)]
		for k in default_keys[action].slice(1):
			if not taken.has(k):
				keys.append(k)
		for k in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


## Rewrites the default key names in keyboard text ("[E]", "[Hold E]", "[Shift]") to the
## player's bindings.
func keyboard_text(text: String) -> String:
	if key_overrides.is_empty() or not text.contains("["):
		return text
	# Two passes through placeholders, so swapped keys (E->R, R->H) don't chain.
	var out := text
	var now: Array[String] = []
	for action in key_overrides:
		var keys: Array = default_keys.get(action, [])
		if keys.is_empty():
			continue
		var was := OS.get_keycode_string(keys[0])
		var mark := "\u0001%d\u0001" % now.size()
		now.append(key_label(action))
		out = out.replace("[%s]" % was, "[%s]" % mark).replace("[Hold %s]" % was, "[Hold %s]" % mark)
	for i in now.size():
		out = out.replace("\u0001%d\u0001" % i, now[i])
	return out


## True for the B button press that backs out of a menu.
## Rumbles every connected pad, if a pad is in use and vibration is on. Weak is the high-frequency
## motor (rattles: shots), strong the low one (thumps: hits, blasts); both 0-1.
func rumble(weak: float, strong: float, seconds: float) -> void:
	if not vibration or not using_pad:
		return
	last_rumble = Vector3(clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), seconds)
	rumbles += 1
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, last_rumble.x, last_rumble.y, seconds)


func is_pad_back(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		show_fps = not show_fps
		apply_settings()
		save_settings()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ENTER and event.alt_pressed:
		window_mode = 0 if window_mode != 0 else 1
		apply_settings()
		save_settings()
		get_viewport().set_input_as_handled()
	var pad := using_pad
	if event is InputEventJoypadButton and event.pressed:
		pad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.4:
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventMouseMotion and event.relative.length() > 4.0:
		pad = false
	if pad != using_pad:
		using_pad = pad
		input_device_changed.emit(pad)


## Hit-stop: time runs at HIT_STOP_SCALE until this wall-clock tick (msec), 0 when none.
const HIT_STOP_SCALE := 0.05
## A hit-stop never lasts longer than this, whatever asked for it.
const HIT_STOP_MAX := 0.3
var stop_until := 0


## Freezes time for a beat. Game restores it from its own _process against the wall clock, so
## nothing (a scene change, a freed player, a pause, a lost timer) can leave the game in slow
## motion. Skipped headless, where tests count frames.
func hit_stop(seconds: float, force := false) -> void:
	if DisplayServer.get_name() == "headless" and not force:
		return
	stop_until = maxi(stop_until, Time.get_ticks_msec() + int(minf(seconds, HIT_STOP_MAX) * 1000.0))
	Engine.time_scale = HIT_STOP_SCALE


func _process(_delta: float) -> void:
	if stop_until == 0:
		# Anything else that slowed time and forgot to put it back.
		if Engine.time_scale != 1.0:
			Engine.time_scale = 1.0
		return
	if Time.get_ticks_msec() >= stop_until or get_tree().paused:
		stop_until = 0
		Engine.time_scale = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_isolate_test_files()
	load_settings()
	add_child(FpsOverlay.new())


## A test scene (res://tests/...) gets its own settings and save files, so suites run side by side
## can't read each other's saves, and no test touches the player's real ones.
func _isolate_test_files() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("res://tests/"):
			var test_name := arg.get_file().get_basename()
			DirAccess.make_dir_recursive_absolute("user://tests")
			settings_path = "user://tests/%s_settings.cfg" % test_name
			save_path = "user://tests/%s_save.json" % test_name
			return


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
		invert_y = cfg.get_value("controls", "invert_y", invert_y)
		vibration = cfg.get_value("controls", "vibration", vibration)
		pad_sensitivity = clampf(cfg.get_value("controls", "pad_sensitivity", pad_sensitivity), PAD_SENSITIVITY_RANGE.x, PAD_SENSITIVITY_RANGE.y)
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
		music_volume = cfg.get_value("audio", "music_volume", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
		show_fps = cfg.get_value("video", "show_fps", show_fps)
		difficulty = clampi(cfg.get_value("game", "difficulty", difficulty), 0, 2)
		screen_shake = clampf(cfg.get_value("game", "screen_shake", screen_shake), 0.0, 1.0)
		graphics = clampi(cfg.get_value("video", "graphics", graphics), GRAPHICS_LOW, GRAPHICS_HIGH)
		subtitles = clampi(cfg.get_value("access", "subtitles", subtitles), 0, SUBTITLE_NAMES.size() - 1)
		toggle_aim = cfg.get_value("access", "toggle_aim", toggle_aim)
		window_mode = clampi(cfg.get_value("video", "window_mode", window_mode), 0, WINDOW_NAMES.size() - 1)
		vsync = cfg.get_value("video", "vsync", vsync)
		fps_cap = int(cfg.get_value("video", "fps_cap", fps_cap))
		brightness = clampf(cfg.get_value("video", "brightness", brightness), BRIGHTNESS_RANGE.x, BRIGHTNESS_RANGE.y)
		if fps_cap not in FPS_CAPS:
			fps_cap = 0
		key_overrides = {}
		if cfg.has_section("keys"):
			for action in cfg.get_section_keys("keys"):
				key_overrides[action] = int(cfg.get_value("keys", action))
	apply_settings()


## The mix. Music, Ambience and SFX buses feed Master, each with its own volume setting; an
## Interior reverb bus that enclosed spaces send to (AudioZones); and a limiter on Master so a
## pile-up of explosions never clips. Music and Ambience duck two ways: a compressor keyed off
## the SFX bus pulls them down under gunfire and blasts, and a "Duck" amplifier that Sfx.duck()
## drives for story beats (dialogue, the aux power-up).
static func ensure_buses() -> void:
	for bus_name in ["Music", "Ambience", "SFX", "Interior"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
			if bus_name == "Interior":
				var verb := AudioEffectReverb.new()
				verb.room_size = 0.42
				verb.damping = 0.55
				verb.spread = 0.8
				verb.predelay_msec = 12.0
				verb.dry = 0.0
				verb.wet = 0.55
				verb.hipass = 0.15
				AudioServer.add_bus_effect(i, verb)
			elif bus_name in ["Music", "Ambience"]:
				var duck := AudioEffectAmplify.new()
				duck.resource_name = "Duck"
				AudioServer.add_bus_effect(i, duck)
				var side := AudioEffectCompressor.new()
				side.resource_name = "Sidechain"
				side.sidechain = &"SFX"
				side.threshold = -22.0
				side.ratio = 3.0 if bus_name == "Music" else 2.0
				side.attack_us = 3000.0
				side.release_ms = 450.0
				AudioServer.add_bus_effect(i, side)
	var has_limiter := false
	for k in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, k) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		limiter.pre_gain_db = 0.0
		AudioServer.add_bus_effect(0, limiter)


## A bus effect by its resource name (e.g. the "Duck" amplifier), or null.
static func bus_effect(bus_name: String, effect_name: String) -> AudioEffect:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return null
	for k in AudioServer.get_bus_effect_count(i):
		var e := AudioServer.get_bus_effect(i, k)
		if e.resource_name == effect_name:
			return e
	return null


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "vibration", vibration)
	cfg.set_value("controls", "pad_sensitivity", pad_sensitivity)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "screen_shake", screen_shake)
	cfg.set_value("video", "graphics", graphics)
	cfg.set_value("access", "subtitles", subtitles)
	cfg.set_value("access", "toggle_aim", toggle_aim)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fps_cap", fps_cap)
	cfg.set_value("video", "brightness", brightness)
	if cfg.has_section("keys"):
		cfg.erase_section("keys")
	for action in key_overrides:
		cfg.set_value("keys", action, key_overrides[action])
	cfg.save(settings_path)


func apply_settings() -> void:
	ensure_buses()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_volume, 0.0001)))
	_apply_display()
	settings_changed.emit()


## Window mode, v-sync and the frame cap. The window only changes when the setting does, so a
## slider elsewhere in the menu doesn't make it flicker. Nothing to do without a window.
func _apply_display() -> void:
	Engine.max_fps = fps_cap
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if window_mode != _shown_window:
		_shown_window = window_mode
		DisplayServer.window_set_mode(WINDOW_MODES[window_mode])


func reset() -> void:
	scrap = 0
	carrying = ""
	upgrades.clear()
	repaired.clear()
	launched = false
	weapons = ["rifle"]
	ammo = {"rifle": [Weapon.SPECS["rifle"]["mag"], -1]}
	stims = 1
	charges = 1
	logs.clear()
	caches_opened.clear()
	caches_seen.clear()
	hints_seen.clear()
	launch_objective = ""
	mission_stage.clear()
	mission_done.clear()
	mission_objective = ""
	region_objective = ""
	region = SaveMigrations.DEFAULT_REGION
	act = 1
	flags.clear()
	quests.clear()
	inventory_changed.emit()
	flag_changed.emit("", null)
	repairs_changed.emit()
	scrap_changed.emit(scrap)
	carrying_changed.emit(carrying)
	upgrades_changed.emit()
	objective_changed.emit(objective_text())


## Difficulty: 0 story, 1 normal, 2 hard.
const DIFFICULTY_NAMES := ["Story", "Normal", "Hard"]
const DAMAGE_TAKEN := [0.5, 1.0, 1.4]
const ENEMY_HEALTH := [0.8, 1.0, 1.2]


func damage_taken_scale() -> float:
	return DAMAGE_TAKEN[difficulty]


func enemy_health_scale() -> float:
	return ENEMY_HEALTH[difficulty]


# --- Save and load -------------------------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(backup_path())


## The session half of a save. Main adds the world (sites, siege, weapon in hand).
func session_state() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"scrap": scrap,
		"carrying": carrying,
		"upgrades": upgrades.keys(),
		"repaired": repaired.duplicate(),
		"weapons": weapons.duplicate(),
		"ammo": ammo.duplicate(true),
		"stims": stims,
		"charges": charges,
		"logs": logs.duplicate(),
		"caches_opened": caches_opened.duplicate(),
		"caches_seen": caches_seen.duplicate(),
		"hints_seen": hints_seen.duplicate(),
		"mission_stage": mission_stage.duplicate(),
		"mission_done": mission_done.duplicate(),
		"region": region,
		"act": act,
		"flags": flags.duplicate(true),
		"quests": quests.duplicate(true),
	}


## Restores the session half of a save (repairs are applied through Kestrel by main).
func apply_session(data: Dictionary) -> void:
	scrap = int(data.get("scrap", 0))
	carrying = String(data.get("carrying", ""))
	upgrades.clear()
	for id in data.get("upgrades", []):
		if UPGRADES.has(id):
			upgrades[id] = true
	weapons.assign(data.get("weapons", ["rifle"]).filter(func(w): return Weapon.SPECS.has(w)))
	if not "rifle" in weapons:
		weapons.push_front("rifle")
	ammo = {}
	var saved_ammo: Dictionary = data.get("ammo", {})
	for w in weapons:
		var pair: Array = saved_ammo.get(w, [Weapon.SPECS[w]["mag"], Weapon.SPECS[w]["reserve_max"]])
		ammo[w] = [int(pair[0]), int(pair[1])]
	stims = int(data.get("stims", 1))
	charges = int(data.get("charges", 1))
	mission_stage.clear()
	var stages: Dictionary = data.get("mission_stage", {})
	for id in stages:
		mission_stage[String(id)] = int(stages[id])
	mission_done.clear()
	for i in data.get("mission_done", []):
		mission_done.append(int(i))
	logs.assign(data.get("logs", []).filter(func(id): return not Story.get_log(String(id)).is_empty()))
	caches_opened.clear()
	for i in data.get("caches_opened", []):
		caches_opened.append(int(i))
	caches_seen.clear()
	for i in data.get("caches_seen", []):
		caches_seen.append(int(i))
	hints_seen.clear()
	for h in data.get("hints_seen", []):
		hints_seen.append(String(h))
	region = String(data.get("region", SaveMigrations.DEFAULT_REGION))
	act = clampi(int(data.get("act", 1)), 1, 4)
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	quests = (data.get("quests", {}) as Dictionary).duplicate(true)
	_open_by_repairs()
	# Whatever listens for flags (gates, quests) looks again: the whole set just changed.
	flag_changed.emit("", null)
	scrap_changed.emit(scrap)
	carrying_changed.emit(carrying)
	upgrades_changed.emit()
	inventory_changed.emit()


## Cooling clears the canyon's rockfall (Jake, 2026-11-07). Saves made before that rule have
## cooling in and the canyon shut, and the canopy is salvaged beyond it now: open it for them.
func _open_by_repairs() -> void:
	if is_repaired("cooling") and not flags.get("shatterlands_open", false):
		set_flag("shatterlands_open")


## Writes the save safely: the new file goes to a temp file first and only replaces the save once
## it is complete, and the save it replaces is kept as a backup. A crash or power cut mid-write
## leaves the last good save in place.
func write_save(data: Dictionary) -> bool:
	var tmp := save_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("Game: cannot write %s" % tmp)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(backup_path())
		DirAccess.rename_absolute(save_path, backup_path())
	if DirAccess.rename_absolute(tmp, save_path) != OK:
		push_warning("Game: cannot replace %s" % save_path)
		return false
	return true


func backup_path() -> String:
	return save_path + ".bak"


## Reads the save, or the backup if the save is missing or damaged; {} if neither parses.
func read_save() -> Dictionary:
	for path in [save_path, backup_path()]:
		var data := _read_json(path)
		if not data.is_empty():
			return data
	return {}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	# Older saves are upgraded in place; a newer build's save or a damaged file comes back {}.
	var data := SaveMigrations.migrate(JSON.parse_string(FileAccess.get_file_as_string(path)))
	if int(data.get("version", 0)) != SAVE_VERSION:
		return {}
	return data


func delete_save() -> void:
	for path in [save_path, backup_path(), save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func add_scrap(amount: int) -> void:
	scrap += amount
	Sfx.play("scrap_pickup", null, -6.0)
	scrap_changed.emit(scrap)


func has_upgrade(id: String) -> bool:
	return upgrades.has(id)


## The upgrades the fabricator lists right now (weapon add-ons only once you own the weapon).
func listed_upgrades() -> Array[String]:
	var out: Array[String] = []
	for id in UPGRADE_ORDER:
		var w: String = UPGRADES[id].get("weapon", "")
		if w == "" or owns_weapon(w):
			out.append(id)
	return out


## The next upgrade not yet built, or "" once everything listed is built.
func next_upgrade() -> String:
	for id in listed_upgrades():
		if not has_upgrade(id):
			return id
	return ""


# --- Inventory ----------------------------------------------------------------------------

func owns_weapon(id: String) -> bool:
	return id in weapons


## Adds a weapon with a full magazine and reserve.
func give_weapon(id: String) -> void:
	if owns_weapon(id):
		return
	weapons.append(id)
	ammo[id] = [Weapon.SPECS[id]["mag"], Weapon.SPECS[id]["reserve_max"]]
	inventory_changed.emit()


func ammo_in_mag(id: String) -> int:
	return ammo.get(id, [0, 0])[0]


func ammo_reserve(id: String) -> int:
	return ammo.get(id, [0, 0])[1]


func set_ammo(id: String, in_mag: int, reserve: int) -> void:
	ammo[id] = [in_mag, reserve]


## Adds reserve ammo up to the weapon's cap. Returns how much was taken.
func add_ammo(id: String, amount: int) -> int:
	if not owns_weapon(id) or ammo_reserve(id) < 0:
		return 0
	var cap: int = Weapon.SPECS[id]["reserve_max"]
	var before := ammo_reserve(id)
	ammo[id][1] = mini(before + amount, cap)
	inventory_changed.emit()
	return ammo[id][1] - before


## Owned weapons with limited ammo, i.e. the ones ammo pickups can top up.
func ammo_weapons() -> Array[String]:
	var out: Array[String] = []
	for id in weapons:
		if Weapon.SPECS[id]["reserve_max"] > 0:
			out.append(id)
	return out


func max_stims() -> int:
	return 5 if has_upgrade("stim_pouch") else 3


func add_stims(n: int) -> int:
	var before := stims
	stims = mini(stims + n, max_stims())
	inventory_changed.emit()
	return stims - before


func take_stim() -> bool:
	if stims <= 0:
		return false
	stims -= 1
	inventory_changed.emit()
	return true


func buy_stim() -> bool:
	if scrap < STIM_COST or stims >= max_stims():
		return false
	scrap -= STIM_COST
	scrap_changed.emit(scrap)
	add_stims(1)
	Sfx.play("fabricate")
	return true


func max_charges() -> int:
	return 3


func add_charges(n: int) -> int:
	var before := charges
	charges = mini(charges + n, max_charges())
	inventory_changed.emit()
	return charges - before


func take_charge() -> bool:
	if charges <= 0:
		return false
	charges -= 1
	inventory_changed.emit()
	return true


func buy_charge() -> bool:
	if scrap < CHARGE_COST or charges >= max_charges():
		return false
	scrap -= CHARGE_COST
	scrap_changed.emit(scrap)
	add_charges(1)
	Sfx.play("fabricate")
	return true


func is_repaired(id: String) -> bool:
	return repaired.get(id, false)


func repairs_done() -> int:
	return repaired.values().count(true)


## Called when a Kestrel repair changes state (install, dev toggle or load).
func set_repaired(id: String, value: bool) -> void:
	if is_repaired(id) == value:
		return
	repaired[id] = value
	_open_by_repairs()
	# A dev toggle can fix the part you're carrying: drop it rather than strand it.
	if value and carrying != "" and Campaign.by_component(carrying).get("id", "") == id:
		carrying = ""
		carrying_changed.emit(carrying)
	repairs_changed.emit()
	upgrades_changed.emit()
	objective_changed.emit(objective_text())


func cooling_online() -> bool:
	return is_repaired("cooling")


## The repair the campaign is on: the first one Kestrel still has damaged, or "" when all are done.
func current_repair() -> String:
	for r in Campaign.REPAIRS:
		if not is_repaired(r["id"]):
			return r["id"]
	return ""


## "find", "return", "launch" (all repaired) or "done" (launched).
func phase() -> String:
	if launched:
		return "done"
	var id := current_repair()
	if id == "":
		return "launch"
	var component: String = Campaign.get_repair(id)["component"]
	return "return" if carrying == component or delivered(component) else "find"


## A component salvaged in another region and sent to Kestrel: waiting at the install bay.
func delivered(component: String) -> bool:
	return bool(flags.get("delivered_" + component, false))


func set_region_objective(text: String) -> void:
	if text != region_objective:
		region_objective = text
		objective_changed.emit(objective_text())


func deliver_component(component: String) -> void:
	set_flag("delivered_" + component, true)
	objective_changed.emit(objective_text())


## True when the fabricator can run this build at all, scrap aside.
func can_fabricate(id: String) -> bool:
	var needs: String = UPGRADES[id]["needs"]
	var weapon: String = UPGRADES[id].get("weapon", "")
	return (needs == "" or is_repaired(needs)) and (weapon == "" or owns_weapon(weapon))


func buy_upgrade(id: String) -> bool:
	var cost: int = UPGRADES[id]["cost"]
	if has_upgrade(id) or scrap < cost or not can_fabricate(id):
		return false
	scrap -= cost
	upgrades[id] = true
	if UPGRADES[id].has("grants"):
		give_weapon(UPGRADES[id]["grants"])
	scrap_changed.emit(scrap)
	upgrades_changed.emit()
	message.emit("%s fabricated. %s." % [UPGRADES[id]["name"], UPGRADES[id]["effect"]])
	Sfx.play("fabricate")
	return true


func take_component(component: String) -> void:
	carrying = component
	carrying_changed.emit(carrying)
	objective_changed.emit(objective_text())
	var r := Campaign.by_component(component)
	message.emit("%s recovered. It's heavy, so you can't sprint while carrying it." % Campaign.sentence(r["component_name"]))
	Sfx.play("cell_pickup" if component == "aux_cell" else "manifold_pickup")


## Fits the carried component. The caller repairs Kestrel, which mirrors back via set_repaired().
func install_component() -> void:
	var component := carrying
	if component == "":
		component = String(Campaign.get_repair(current_repair()).get("component", ""))
	var r := Campaign.by_component(component)
	if flags.has("delivered_" + component):
		set_flag("delivered_" + component, false)
	carrying = ""
	carrying_changed.emit(carrying)
	message.emit(r.get("done", ""))


## Records a story log. Returns true if it's new.
## Sets a world flag (quests, discoveries and dialogue read them; they save with the session).
func set_flag(id: String, value: Variant = true) -> void:
	if flags.get(id) == value:
		return
	flags[id] = value
	flag_changed.emit(id, value)


func find_log(id: String) -> bool:
	if id == "" or id in logs or Story.get_log(id).is_empty():
		return false
	logs.append(id)
	log_found.emit(id)
	inventory_changed.emit()
	return true


func has_log(id: String) -> bool:
	return id in logs


func launch() -> void:
	launched = true
	objective_changed.emit(objective_text())


func objective_text() -> String:
	if opening_objective != "":
		return opening_objective
	# A region mission running where Juno stands (Ferro-9's canopy or gear) has the line.
	if region_objective != "" and phase() != "launch":
		return region_objective
	match phase():
		"find":
			if mission_objective != "":
				return mission_objective
			var r := Campaign.get_repair(current_repair())
			if Campaign.sourced(r["id"]) and region == Campaign.SOURCED[r["id"]]["region"]:
				return r.get("find_there", r["find"])
			return r["find"]
		"return":
			return Campaign.get_repair(current_repair())["return"]
		"launch":
			return launch_objective if launch_objective != "" else "Start the engine spool from the pilot's seat"
	return "Kestrel is away"
