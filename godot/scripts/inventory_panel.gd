class_name InventoryPanel
extends UiPanel
## Tab: what Juno has on them and where Kestrel stands.

var player: Player


func _ready() -> void:
	super._ready()
	_title.text = "INVENTORY"
	_toggle_action = "inventory"


func _refresh() -> void:
	_clear()
	_row("WEAPONS", Color("ffd08a"), 14)
	for id in Weapon.ORDER:
		if not Game.owns_weapon(id):
			continue
		var reserve := Game.ammo_reserve(id)
		var mark := "▸ " if player and player.weapon.current == id else "  "
		_row("%s%s  ·  %d in the magazine, %s in reserve  [%d]" % [mark, Weapon.SPECS[id]["name"], Game.ammo_in_mag(id), "unlimited" if reserve < 0 else str(reserve), Weapon.ORDER.find(id) + 1])
	_row("SUPPLIES", Color("ffd08a"), 14)
	_row("Stims %d / %d  [Q]   ·   Arc charges %d / %d  [G]   ·   Scrap %d" % [Game.stims, Game.max_stims(), Game.charges, Game.max_charges(), Game.scrap])
	var main: Node = player.get_parent() if player else null
	var beacon: FieldBeacon = main.get("beacon") if main else null
	if beacon and beacon.unlocked():
		var where: String = Game.flags.get("beacon_region", "")
		_row("Field beacon: %s  [B]" % ("planted in " + RegionDB.display_name(where) if where != "" else "not planted"))
		var b := Button.new()
		b.text = "Plant the beacon here"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			close()
			beacon.place())
		_content.add_child(b)
	if Game.carrying != "":
		_row("On your back: %s" % Campaign.by_component(Game.carrying)["component_name"])
	var built: Array = Game.UPGRADE_ORDER.filter(func(id): return Game.has_upgrade(id))
	_row("UPGRADES", Color("ffd08a"), 14)
	_row(", ".join(built.map(func(id): return Game.UPGRADES[id]["name"])) if not built.is_empty() else "None yet. The fabricator is on the workshop bench.")
	_row("LOGS", Color("ffd08a"), 14)
	_row("%d of %d recovered  [L] to read" % [Game.logs.filter(func(id): return id != Story.ORBIT_LOG["id"]).size(), Story.LOGS.size()])
	_row("KESTREL  %d / %d" % [Game.repairs_done(), Campaign.REPAIRS.size()], Color("ffd08a"), 14)
	for r in Campaign.REPAIRS:
		_row("%s %s" % ["■" if Game.is_repaired(r["id"]) else "□", Kestrel.REPAIR_NAMES[r["id"]]])
