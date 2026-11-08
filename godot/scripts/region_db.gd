class_name RegionDB
extends RefCounted
## The game's regions as data. The Kettle is the resident world main.gd builds; every other
## region is a RegionScene that RegionManager builds when Juno travels there, far from the basin
## (at `origin`) so the two never touch, and frees when she leaves. Regions join through gates:
## a physical threshold in one region (`gate_pos`, in that region's space) that opens when the
## `unlock_flag` is set.
##
##   name, act      what the HUD and journal call it, and the act it belongs to.
##   resident       true for the Kettle only: built by main, never unloaded.
##   scene          the RegionScene script that builds it.
##   origin         where its local space sits in the world.
##   from           the region its gate stands in, and gate_pos places it there (the gate
##                  faces back toward the middle of that region).
##   unlock_flag    Game flag that opens the gate (the quest that opens it sets it).
##   locked_text    the gate's prompt while it is shut.
##   gate_in        for a region beyond the Kettle's ring: which way is back into the nearer
##                  region from its gate_pos (Juno comes back facing that way).
##   planned        named in the design but not built yet (no gate is placed).
##   sequence       a scripted scene with no gate (the opening's approach).

const REGIONS := {
	"kettle": {
		"name": "The Kettle", "act": 1, "resident": true,
	},
	"shatterlands": {
		"name": "The Shatterlands", "act": 2,
		"scene": "res://scripts/regions/shatterlands_threshold.gd",
		"origin": Vector3(4000.0, 0.0, 0.0),
		"from": "kettle", "gate_pos": Vector3(101.0, 0.0, -37.0),
		"unlock_flag": "shatterlands_open",
		"locked_text": "A canyon to the Shatterlands, choked with fresh rockfall",
		"enter_text": "Go through the canyon to the Shatterlands",
	},
	"gillwood": {
		"name": "The Gillwood", "act": 2,
		"scene": "res://scripts/regions/gillwood.gd",
		"origin": Vector3(8000.0, 0.0, 0.0),
		"from": "shatterlands", "gate_pos": Vector3(-45.0, 0.0, -63.0), "gate_in": Vector3(0.0, 0.0, 1.0),
		"unlock_flag": "reyes_talked",
		"locked_text": "A scrap barricade across a split in the rim. Reyes's people put it there",
		"enter_text": "Go north into the Gillwood",
	},
	# The opening's approach, aboard a Kestrel still in orbit: no gate, reached only by Opening.
	"approach": {
		"name": "Approach to HD-4471 b", "act": 1, "sequence": true,
		"scene": "res://scripts/regions/approach.gd",
		"origin": Vector3(-8000.0, 0.0, 0.0),
	},
	"loom_expanse": {
		"name": "The Loom Expanse", "act": 3, "planned": true,
	},
}


static func ids() -> Array:
	return REGIONS.keys()


static func get_region(id: String) -> Dictionary:
	return REGIONS.get(id, {})


static func display_name(id: String) -> String:
	return String(get_region(id).get("name", id))


## Built regions with a gate (not the Kettle, not planned ones).
static func travel_regions() -> Array:
	return ids().filter(func(id): return not REGIONS[id].get("resident", false) and not REGIONS[id].get("planned", false) and not REGIONS[id].get("sequence", false))
