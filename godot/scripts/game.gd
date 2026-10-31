extends Node
## Session state for the vertical slice: salvage, what the player carries, workshop upgrades
## and the current objective. Autoloaded as "Game".

signal scrap_changed(amount: int)
signal carrying_changed(item: String)
signal upgrades_changed
signal objective_changed(text: String)
signal message(text: String)
signal settings_changed
signal repairs_changed

## Physics layer bits shared by every script.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

const UPGRADE_ORDER: Array[String] = ["extended_mag", "plating", "heavy_rounds", "rapid_cycler", "plating_2"]
## Heavy builds overheat the fabricator until cooling is repaired; the top tier runs on engine bleed.
const UPGRADES := {
	"extended_mag": {"name": "Extended magazine", "cost": 30, "effect": "Magazine 24 to 36 rounds", "needs": ""},
	"plating": {"name": "Suit plating", "cost": 40, "effect": "Max health +40", "needs": "cooling"},
	"heavy_rounds": {"name": "Heavy rounds", "cost": 45, "effect": "+30% damage", "needs": "cooling"},
	"rapid_cycler": {"name": "Rapid cycler", "cost": 60, "effect": "+25% fire rate", "needs": "engine"},
	"plating_2": {"name": "Reinforced plating", "cost": 70, "effect": "Max health +40 more", "needs": "engine"},
}
const NEEDS_TEXT := {
	"cooling": "the fabricator overheats on heavy builds until cooling is fixed",
	"engine": "top-tier builds need engine bleed power",
}

const SETTINGS_PATH := "user://settings.cfg"

var mouse_sensitivity := 0.0025
var invert_y := false
var master_volume := 0.8

var scrap := 0
## The component on the player's back (a Campaign component id), or "".
var carrying := ""
var upgrades: Dictionary = {}
## Mirrors Kestrel's repair states (id -> true), so dev toggles drive the campaign too.
var repaired: Dictionary = {}
var launched := false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
		invert_y = cfg.get_value("controls", "invert_y", invert_y)
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
	apply_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.save(SETTINGS_PATH)


func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	settings_changed.emit()


func reset() -> void:
	scrap = 0
	carrying = ""
	upgrades.clear()
	repaired.clear()
	launched = false
	repairs_changed.emit()
	scrap_changed.emit(scrap)
	carrying_changed.emit(carrying)
	upgrades_changed.emit()
	objective_changed.emit(objective_text())


func add_scrap(amount: int) -> void:
	scrap += amount
	Sfx.play("scrap_pickup", null, -6.0)
	scrap_changed.emit(scrap)


func has_upgrade(id: String) -> bool:
	return upgrades.has(id)


## The next upgrade the fabricator offers, or "" once everything is built.
func next_upgrade() -> String:
	for id in UPGRADE_ORDER:
		if not has_upgrade(id):
			return id
	return ""


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
	return needs == "" or is_repaired(needs)


func buy_upgrade(id: String) -> bool:
	var cost: int = UPGRADES[id]["cost"]
	if has_upgrade(id) or scrap < cost or not can_fabricate(id):
		return false
	scrap -= cost
	upgrades[id] = true
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


func launch() -> void:
	launched = true
	objective_changed.emit(objective_text())


func objective_text() -> String:
	match phase():
		"find":
			return Campaign.get_repair(current_repair())["find"]
		"return":
			return Campaign.get_repair(current_repair())["return"]
		"launch":
			return "Take the pilot's seat and launch"
	return "Kestrel is away"
