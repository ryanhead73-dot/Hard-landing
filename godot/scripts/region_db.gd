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
	# The first pocket of the Loom Expanse (milestone C), west through the Shatterlands' rim. It
	# opens once the wing is fitted.
	"loom_expanse": {
		"name": "The Loom Expanse", "act": 3,
		"scene": "res://scripts/regions/loom_expanse.gd",
		"origin": Vector3(12000.0, 0.0, 0.0),
		"from": "shatterlands", "gate_pos": Vector3(-63.0, 0.0, 18.0), "gate_in": Vector3(1.0, 0.0, 0.0),
		"unlock_flag": "loom_open",
		"locked_text": "A cleft in the west rim, laced shut with pale fibres that hum when you touch them",
		"enter_text": "Go west through the cleft into the Loom Expanse",
	},
	# The Long Patience's stern (milestone D1), through the Loom's east rim. HOB finds it from the
	# overlook.
	"long_patience": {
		"name": "The Long Patience", "act": 3,
		"scene": "res://scripts/regions/long_patience.gd",
		"origin": Vector3(16000.0, 0.0, 0.0),
		"from": "loom_expanse", "gate_pos": Vector3(55.0, 0.0, -46.0), "gate_in": Vector3(-1.0, 0.0, 0.0),
		"unlock_flag": "patience_open",
		"locked_text": "A cleft in the east rim, choked with fibre. Something metal glints far back in it",
		"enter_text": "Go east through the cleft to the Long Patience",
	},
	# The Tuning Crown (milestone D2), down the drop beyond the Loom's overlook rail: a drop the
	# suit thrusters make safe, so it opens with the engine.
	"tuning_crown": {
		"name": "The Tuning Crown", "act": 4,
		"scene": "res://scripts/regions/tuning_crown.gd",
		"origin": Vector3(20000.0, 0.0, 0.0),
		"from": "loom_expanse", "gate_pos": Vector3(0.0, 0.0, -75.0), "gate_in": Vector3(0.0, 0.0, 1.0),
		"unlock_flag": "crown_open",
		"locked_text": "Beyond the rail the ground drops away toward the Crown. Too far down without thrusters",
		"enter_text": "Drop over the rail toward the Tuning Crown",
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


## The region to go through from `from` to reach `to`: the one that opens off `from` on the way,
## or "" if `to` isn't beyond `from`.
static func next_hop(from: String, to: String) -> String:
	var id := to
	while id != "" and REGIONS.has(id) and not REGIONS[id].get("resident", false):
		var parent := String(REGIONS[id].get("from", "kettle"))
		if parent == from:
			return id
		id = parent
	return ""
