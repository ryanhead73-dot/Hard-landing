class_name FabricatorMenu
extends UiPanel
## The workshop fabricator: every build on one list, with what it does, what it costs and what
## stops it (power, cooling, engine bleed, scrap). Stims and arc charges are made here too.


func _ready() -> void:
	super._ready()
	_title.text = "FABRICATOR"
	_toggle_action = "interact"


## Builds an upgrade (or "stim" / "charge"). Returns true if it was made.
func build(id: String) -> bool:
	var ok: bool
	match id:
		"stim":
			ok = Game.buy_stim()
		"charge":
			ok = Game.buy_charge()
		_:
			ok = Game.buy_upgrade(id)
	if visible:
		_refresh()
	return ok


## Why a build can't be made right now, or "" if it can.
static func blocker(id: String) -> String:
	if id == "stim":
		if Game.stims >= Game.max_stims():
			return "Stim pouch full"
		return "" if Game.scrap >= Game.STIM_COST else "Needs %d scrap" % Game.STIM_COST
	if id == "charge":
		if Game.charges >= Game.max_charges():
			return "Charge rack full"
		return "" if Game.scrap >= Game.CHARGE_COST else "Needs %d scrap" % Game.CHARGE_COST
	var info: Dictionary = Game.UPGRADES[id]
	if Game.has_upgrade(id):
		return "Built"
	if info["needs"] != "" and not Game.is_repaired(info["needs"]):
		return "Needs %s" % Kestrel.REPAIR_NAMES[info["needs"]].to_lower()
	if Game.scrap < int(info["cost"]):
		return "Needs %d scrap" % info["cost"]
	return ""


func _refresh() -> void:
	_clear()
	_row("Scrap: %d" % Game.scrap, Color("ffd08a"), 18)
	var ids: Array = Game.listed_upgrades()
	ids.append("stim")
	ids.append("charge")
	for id in ids:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		_content.add_child(line)
		var info: Dictionary = _consumable(id) if id in ["stim", "charge"] else Game.UPGRADES[id]
		var text := Label.new()
		text.text = "%s  ·  %s" % [info["name"], info["effect"]]
		text.custom_minimum_size = Vector2(430, 0)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(text)
		var why := blocker(id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 0)
		button.text = why if why != "" else "Build  %d" % info["cost"]
		button.disabled = why != ""
		button.pressed.connect(build.bind(id))
		line.add_child(button)


static func _consumable(id: String) -> Dictionary:
	if id == "charge":
		return {"name": "Arc charge", "cost": Game.CHARGE_COST, "effect": "Thrown discharge that stuns packs (you carry %d / %d)" % [Game.charges, Game.max_charges()]}
	return {"name": "Stim", "cost": Game.STIM_COST, "effect": "Heals %d (you carry %d / %d)" % [Game.STIM_HEAL, Game.stims, Game.max_stims()]}
