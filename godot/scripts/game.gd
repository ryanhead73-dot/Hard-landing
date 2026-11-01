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
const NEEDS_TEXT := {
	"cooling": "the fabricator overheats on heavy builds until cooling is fixed",
	"engine": "top-tier builds need engine bleed power",
}

const SETTINGS_PATH := "user://settings.cfg"
const SAVE_VERSION := 1

var mouse_sensitivity := 0.0025
var invert_y := false
var master_volume := 0.8
var music_volume := 0.7
var difficulty := 1
## Camera shake strength (0 turns it off).
var screen_shake := 1.0
## 0 = performance (no screen-space GI or volumetric fog), 1 = quality.
var graphics := 1

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
## Owned weapons, and ammo per weapon: id -> [in magazine, reserve] (reserve -1 is unlimited).
var weapons: Array[String] = ["rifle"]
var ammo: Dictionary = {}
var stims := 1
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
## Set by the title screen for a new game: main plays the crash intro once.
var intro_pending := false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
		invert_y = cfg.get_value("controls", "invert_y", invert_y)
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
		music_volume = cfg.get_value("audio", "music_volume", music_volume)
		difficulty = clampi(cfg.get_value("game", "difficulty", difficulty), 0, 2)
		screen_shake = clampf(cfg.get_value("game", "screen_shake", screen_shake), 0.0, 1.0)
		graphics = clampi(cfg.get_value("video", "graphics", graphics), 0, 1)
	apply_settings()


## Music and Ambience buses, both feeding Master, so music has its own volume setting; an
## Interior reverb bus that enclosed spaces send to (AudioZones); and a limiter on Master so a
## pile-up of explosions never clips.
static func ensure_buses() -> void:
	for bus_name in ["Music", "Ambience", "Interior"]:
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
	var has_limiter := false
	for k in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, k) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		limiter.pre_gain_db = 0.0
		AudioServer.add_bus_effect(0, limiter)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "screen_shake", screen_shake)
	cfg.set_value("video", "graphics", graphics)
	cfg.save(SETTINGS_PATH)


func apply_settings() -> void:
	ensure_buses()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_volume, 0.0001)))
	settings_changed.emit()


func reset() -> void:
	scrap = 0
	carrying = ""
	upgrades.clear()
	repaired.clear()
	launched = false
	weapons = ["rifle"]
	ammo = {"rifle": [Weapon.SPECS["rifle"]["mag"], -1]}
	stims = 1
	logs.clear()
	launch_objective = ""
	mission_stage.clear()
	mission_done.clear()
	mission_objective = ""
	inventory_changed.emit()
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
	return FileAccess.file_exists(save_path)


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
		"logs": logs.duplicate(),
		"mission_stage": mission_stage.duplicate(),
		"mission_done": mission_done.duplicate(),
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
	mission_stage.clear()
	var stages: Dictionary = data.get("mission_stage", {})
	for id in stages:
		mission_stage[String(id)] = int(stages[id])
	mission_done.clear()
	for i in data.get("mission_done", []):
		mission_done.append(int(i))
	logs.assign(data.get("logs", []).filter(func(id): return not Story.get_log(String(id)).is_empty()))
	scrap_changed.emit(scrap)
	carrying_changed.emit(carrying)
	upgrades_changed.emit()
	inventory_changed.emit()


func write_save(data: Dictionary) -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Game: cannot write %s" % save_path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


## Reads the save file, or returns {} if there is none or it doesn't parse.
func read_save() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != SAVE_VERSION:
		return {}
	return data


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(save_path)


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


func is_repaired(id: String) -> bool:
	return repaired.get(id, false)


func repairs_done() -> int:
	return repaired.values().count(true)


## Called when a Kestrel repair changes state (install, dev toggle or load).
func set_repaired(id: String, value: bool) -> void:
	if is_repaired(id) == value:
		return
	repaired[id] = value
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
	return "return" if carrying == Campaign.get_repair(id)["component"] else "find"


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
	var r := Campaign.by_component(carrying)
	carrying = ""
	carrying_changed.emit(carrying)
	message.emit(r.get("done", ""))
	Sfx.play("power_up")


## Records a story log. Returns true if it's new.
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
	match phase():
		"find":
			if mission_objective != "":
				return mission_objective
			return Campaign.get_repair(current_repair())["find"]
		"return":
			return Campaign.get_repair(current_repair())["return"]
		"launch":
			return launch_objective if launch_objective != "" else "Start the engine spool from the pilot's seat"
	return "Kestrel is away"
