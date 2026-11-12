extends Node
## Run inside an OLD checkout: builds saves at a few points of progress with whatever that build
## has, and writes them as JSON to the folder given after "--".

var main: Node
var out := ""
var tag := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	tag = args[1]
	if "save_path" in Game:
		Game.set("save_path", "user://fixture_save.json")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(20)
	if main.get("opening") and main.opening.has_method("skip"):
		main.opening.skip()
		await _frames(10)
	if main.get("missions"):
		main.missions.bypass = true
	await _make()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _flag(id: String) -> void:
	if "flags" in Game:
		Game.flags[id] = true


func _repair(ids: Array) -> void:
	for id in ids:
		Game.set_repaired(id, true)
		main.kestrel.set_repaired(id, true)


func _component(id: String) -> String:
	return String(Campaign.get_repair(id)["component"])


func _travel(id: String) -> void:
	if not main.get("regions"):
		return
	main.regions.travel(id, true)
	await _frames(40)


func _write(name: String) -> void:
	var data: Dictionary = main.save_state()
	var f := FileAccess.open(out + "/" + tag + "_" + name + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("wrote ", tag, "_", name, " version ", data.get("version"))


func _make() -> void:
	var has_regions: bool = main.get("regions") != null
	var has_loom := ResourceLoader.exists("res://scripts/regions/loom_expanse.gd")
	var has_patience := ResourceLoader.exists("res://scripts/regions/long_patience.gd")
	# 1. Early: the relay's cell is in, cooling is next.
	_repair(["aux_power"])
	Game.scrap = 60
	await _frames(5)
	_write("early")
	# 2. Cooling in; the canopy is next, and (in a Kettle-only build) carried home by hand.
	_repair(["cooling"])
	_flag("shatterlands_open")
	await _frames(5)
	_write("canopy_next")
	Game.take_component(_component("canopy"))
	await _frames(3)
	_write("canopy_carried")
	Game.carrying = ""
	if not has_regions:
		# Kettle-only build: a late save, gear carried.
		_repair(["canopy"])
		Game.take_component(_component("landing_gear"))
		await _frames(3)
		_write("gear_carried")
		return
	# 3. At the greenhouses.
	for f in ["reached_greenhouses", "met_reyes", "nest_cleared", "greenhouse_open"]:
		_flag(f)
	await _travel("shatterlands")
	_write("shatterlands")
	# 4. In the Gillwood with the canopy in and the gear next.
	_flag("reyes_talked")
	_flag("reached_gillwood")
	_flag("found_ferro9")
	_repair(["canopy"])
	_flag("ferro_canopy")
	await _travel("gillwood")
	_write("gillwood_gear")
	await _travel("shatterlands")
	if not has_loom:
		return
	# 5. In the Loom with the engine next.
	_repair(["landing_gear", "wing"])
	for f in ["ferro_gear", "marigold_wing", "loom_open", "reached_loom"]:
		_flag(f)
	await _travel("loom_expanse")
	_write("loom_engine")
	if not has_patience:
		return
	# 6. In the Long Patience, power cut, coil in her arms.
	for f in ["patience_open", "reached_patience", "patience_power_off", "patience_coil_out"]:
		_flag(f)
	await _travel("long_patience")
	Game.take_component("drive_coil")
	await _frames(3)
	_write("patience_coil")
	# 7. Everything in: the launch is next.
	Game.carrying = ""
	_repair(["engine", "navigation"])
	await _travel("loom_expanse")
	await _travel("shatterlands")
	await _travel("kettle")
	_write("launch")
