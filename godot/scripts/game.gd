extends Node
## Session state for the vertical slice: salvage, what the player carries, workshop upgrades
## and the current objective. Autoloaded as "Game".

signal scrap_changed(amount: int)
signal carrying_changed(item: String)
signal upgrades_changed
signal objective_changed(text: String)
signal message(text: String)
signal settings_changed

## Physics layer bits shared by every script.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

enum Stage { RECOVER_CELL, RETURN_CELL, FIND_MANIFOLD, RETURN_MANIFOLD, COOLED }

const UPGRADE_ORDER: Array[String] = ["extended_mag", "plating", "heavy_rounds"]
## Heavy builds overheat the fabricator until the cooling manifold is repaired.
const UPGRADES := {
	"extended_mag": {"name": "Extended magazine", "cost": 30, "effect": "Magazine 24 to 36 rounds", "needs_cooling": false},
	"plating": {"name": "Suit plating", "cost": 40, "effect": "Max health 100 to 140", "needs_cooling": true},
	"heavy_rounds": {"name": "Heavy rounds", "cost": 45, "effect": "+30% damage", "needs_cooling": true},
}

const SETTINGS_PATH := "user://settings.cfg"

var mouse_sensitivity := 0.0025
var invert_y := false
var master_volume := 0.8

var scrap := 0
var carrying := ""
var stage := Stage.RECOVER_CELL
var upgrades: Dictionary = {}


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
	stage = Stage.RECOVER_CELL
	upgrades.clear()
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


func cooling_online() -> bool:
	return stage == Stage.COOLED


## True when the fabricator can run this build at all, scrap aside.
func can_fabricate(id: String) -> bool:
	return not UPGRADES[id]["needs_cooling"] or cooling_online()


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


func take_cell() -> void:
	carrying = "aux_cell"
	stage = Stage.RETURN_CELL
	carrying_changed.emit(carrying)
	objective_changed.emit(objective_text())
	message.emit("Aux power cell recovered. It's heavy, so you can't sprint while carrying it.")
	Sfx.play("cell_pickup")


func install_cell() -> void:
	carrying = ""
	stage = Stage.FIND_MANIFOLD
	carrying_changed.emit(carrying)
	objective_changed.emit(objective_text())
	message.emit("Auxiliary power restored. The fabricator is online, but it overheats on heavy builds. A coolant hauler went down in the hot springs: follow its strobe.")
	Sfx.play("power_up")


func take_manifold() -> void:
	carrying = "manifold"
	stage = Stage.RETURN_MANIFOLD
	carrying_changed.emit(carrying)
	objective_changed.emit(objective_text())
	message.emit("Coolant manifold recovered. It's heavy, so you can't sprint while carrying it.")
	Sfx.play("manifold_pickup")


func install_manifold() -> void:
	carrying = ""
	stage = Stage.COOLED
	carrying_changed.emit(carrying)
	objective_changed.emit(objective_text())
	message.emit("Cooling restored. The fabricator can run heavy builds now.")
	Sfx.play("power_up")


func objective_text() -> String:
	match stage:
		Stage.RECOVER_CELL:
			return "Recover the aux power cell from the relay station"
		Stage.RETURN_CELL:
			return "Return to Kestrel and install the cell in the aux bay"
		Stage.FIND_MANIFOLD:
			return "Salvage a coolant manifold from the hauler wreck in the hot springs"
		Stage.RETURN_MANIFOLD:
			return "Return to Kestrel and fit the manifold at the workshop install bay"
	return "Fabricate upgrades at the workshop bench using scrap"
