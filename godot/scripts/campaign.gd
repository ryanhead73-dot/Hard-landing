class_name Campaign
extends RefCounted
## The repair campaign as data. Kestrel is restored in this order, one expedition per repair:
## find the component at the site, carry it home, install it at the install point.
## The current repair is always the first one Kestrel still has damaged.

const REPAIRS: Array[Dictionary] = [
	{
		"id": "aux_power", "site": "RelayStation",
		"component": "aux_cell", "component_name": "aux power cell",
		"find": "Recover the aux power cell from the relay station",
		"return": "Return to Kestrel and install the cell in the aux bay",
		"install_label": "Install the aux power cell",
		"bay_label": "Aux power bay: needs a replacement power cell",
		"done": "Auxiliary power restored. The fabricator is online, but it overheats on heavy builds. A coolant hauler went down in the hot springs: follow its strobe.",
	},
	{
		"id": "cooling", "site": "HaulerWreck",
		"component": "manifold", "component_name": "coolant manifold",
		"find": "Salvage a coolant manifold from the hauler wreck in the hot springs",
		"return": "Return to Kestrel and fit the manifold at the workshop install bay",
		"install_label": "Fit the coolant manifold",
		"bay_label": "Cooling: the manifold is cracked and venting coolant",
		"done": "Cooling restored. The fabricator can run heavy builds now. Next: the canopy. A survey skiff is perched up on the basalt spires: follow its yellow flare.",
	},
	{
		"id": "canopy", "site": "SpireSkiff",
		"component": "glazing", "component_name": "canopy glazing panel",
		"find": "Climb the basalt spires and take the glazing panel from the skiff Lark",
		"return": "Return to Kestrel and seal the cockpit canopy",
		"install_label": "Seal the canopy with the glazing panel",
		"bay_label": "Canopy: cracked and taped, a pane is missing",
		"done": "Cockpit sealed. The scanner is back: salvage crates and wildlife show on your HUD. Next: landing gear. There's a mining crawler in the quarry: follow its violet work lamp.",
	},
	{
		"id": "landing_gear", "site": "QuarryCrawler",
		"component": "struts", "component_name": "hydraulic strut pack",
		"find": "Pull a hydraulic strut pack from the mining crawler in the quarry",
		"return": "Return to Kestrel and fit the struts under the starboard hull",
		"install_label": "Fit the hydraulic strut pack",
		"bay_label": "Landing gear: struts crushed flat",
		"done": "Gear down and locked. Kestrel is level and the cargo ramp opens onto the armoury. Next: the port wing. A rescue dropship lies in the moss field: follow its green distress light.",
	},
	{
		"id": "wing", "site": "MossDropship",
		"component": "wing_panel", "component_name": "wing-tip panel",
		"find": "Cut the wing-tip panel off the dropship Ferro-9 in the moss field",
		"return": "Return to Kestrel and fit the panel to the port wing",
		"install_label": "Fit the wing-tip panel",
		"bay_label": "Port wing: tip torn off",
		"done": "Wing whole again. The point-defence turret on the wing root is live. Next: the port engine. A freighter's drive coil is out in the graveyard: follow the white beacon.",
	},
	{
		"id": "engine", "site": "FreighterGraveyard",
		"component": "drive_coil", "component_name": "drive coil",
		"find": "Recover a drive coil from the freighter Long Patience in the graveyard",
		"return": "Return to Kestrel and seat the coil in the port nacelle",
		"install_label": "Seat the drive coil",
		"bay_label": "Port engine: nacelle crushed, coil missing",
		"done": "Port engine turns over. Engine bleed feeds the fabricator's top tier. Last: navigation. Ilse Marrow left a nav core at the Loom spire, under the teal light.",
	},
	{
		"id": "navigation", "site": "LoomSpire",
		"component": "nav_core", "component_name": "pulse-timing nav core",
		"find": "Take Ilse Marrow's nav core from the foot of the Loom spire",
		"return": "Return to Kestrel and slot the nav core into the cockpit console",
		"install_label": "Slot the nav core into the console",
		"bay_label": "Navigation: the console has no core",
		"done": "Navigation online. HOB is plotting the gap between pulses. Take the pilot's seat when you're ready to leave.",
	},
]

## How each carried component looks on the player's back: [size, colour, glow].
const PACKS := {
	"aux_cell": [Vector3(0.5, 0.7, 0.3), Color("f2a93b"), 2.5],
	"manifold": [Vector3(1.1, 0.45, 0.22), Color("7fd6ff"), 1.8],
	"glazing": [Vector3(1.0, 0.8, 0.06), Color("bfe3ea"), 0.6],
	"struts": [Vector3(0.35, 1.2, 0.35), Color("9aa0a3"), 0.3],
	"wing_panel": [Vector3(1.4, 0.9, 0.08), Color("e9e1cc"), 0.2],
	"drive_coil": [Vector3(0.7, 0.7, 0.45), Color("ff7a3a"), 2.0],
	"nav_core": [Vector3(0.4, 0.4, 0.4), Color("3fd1b5"), 3.0],
}


## "aux power cell" -> "Aux power cell".
static func sentence(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


static func index_of(id: String) -> int:
	for i in REPAIRS.size():
		if REPAIRS[i]["id"] == id:
			return i
	return -1


static func get_repair(id: String) -> Dictionary:
	var i := index_of(id)
	return REPAIRS[i] if i >= 0 else {}


static func by_component(component: String) -> Dictionary:
	for r in REPAIRS:
		if r["component"] == component:
			return r
	return {}
