class_name QuestDB
extends RefCounted
## Every quest in the game as data: main story quests, side missions and discoveries, grouped
## into the four acts. QuestLog tracks their state in Game.quests; this file only describes them.
##
## A quest:
##   id        unique id (also the key in Game.quests and the save).
##   title     what the journal calls it.
##   act       1-4 (see ACTS).
##   kind      "main", "side" or "discovery".
##   region    where it happens (a RegionDB id).
##   summary   one line for the journal.
##   requires  conditions that must all hold before it starts (see below). Empty: from the start.
##   steps     worked in order; each is {"text": objective line, "done": condition, "at"?}.
##             `at` marks where the step happens on the map and in the journal: a Vector3, or
##             the id of a discovery (main.discoveries) to point at.
##   rewards   optional: {"scrap": n, "flags": {id: value}} given once, on completion.
##
## Conditions (one dictionary each):
##   {"type": "quest", "id"}            that quest is done.
##   {"type": "repair", "id"}           that Kestrel repair is in (a Campaign repair id).
##   {"type": "flag", "id", "value"?}   Game.flags[id] equals value (true when value is left out).
##   {"type": "logs", "ids"}            every one of those Story logs has been found.
##   {"type": "caches", "count"}        that many drift caches opened (-1: every cache).
##   {"type": "launched"}               Kestrel has left the Kettle.
##   {"type": "any", "of": [...]}       at least one of those conditions holds.
##
## The seven repairs are built from Campaign.REPAIRS so the repair campaign stays the one source
## of truth for them: a repair quest is done exactly when Game.is_repaired() says so.

const ACTS := {
	1: {"name": "Stranded", "summary": "Crash, survive the Kettle and bring Kestrel back to life."},
	2: {"name": "The Lost", "summary": "Follow the other castaways out into the Shatterlands."},
	3: {"name": "Beneath the Kettle", "summary": "Go down into the Loom Expanse and learn what the Loom is."},
	4: {"name": "The Last Departure", "summary": "Thread the gap between pulses and leave."},
}

const KINDS := ["main", "side", "discovery"]

## Ilse Marrow's own logs, in the order she wrote them.
const ILSE_LOGS := ["relay_1", "relay_2", "relay_3", "post_1", "freighter_3", "loom_1", "loom_2", "loom_3"]

## Quests beyond the seven repairs. New content goes here.
const EXTRA: Array[Dictionary] = [
	{
		"id": "escape", "title": "The gap between pulses", "act": 1, "kind": "main", "region": "kettle",
		"summary": "Take the pilot's seat and fly Kestrel out between two Loom pulses.",
		"requires": [{"type": "quest", "id": "repair_navigation"}],
		"steps": [{"text": "Take the pilot's seat and launch", "done": {"type": "launched"}}],
	},
	{
		"id": "the_lost", "title": "The lost", "act": 2, "kind": "main", "region": "shatterlands",
		"summary": "Reyes's people are holding out in Voss's old greenhouses, past the canyon, under the big fungus.",
		"requires": [{"type": "flag", "id": "shatterlands_open"}],
		"steps": [
			{"text": "Find Voss's greenhouses in the Shatterlands", "done": {"type": "flag", "id": "reached_greenhouses"}},
			{"text": "Hail the greenhouse gate", "done": {"type": "flag", "id": "met_reyes"}},
			{"text": "Clear the nest under the wrecked hauler's tail", "done": {"type": "flag", "id": "nest_cleared"}},
			{"text": "Go back to the greenhouse gate", "done": {"type": "flag", "id": "greenhouse_open"}},
		],
	},
	{
		"id": "dark_house", "title": "The dark house", "act": 2, "kind": "side", "region": "shatterlands",
		"summary": "The east glasshouse went dark in the last pulse. Teo says Voss kept spare lamp cells up on the high shelf.",
		"requires": [{"type": "flag", "id": "lamp_cell_asked"}],
		"steps": [
			{"text": "Fetch a lamp cell from Voss's cache on the high shelf", "done": {"type": "flag", "id": "lamp_cell_found"}},
			{"text": "Bring the cell back to Teo", "done": {"type": "flag", "id": "lamp_cell_fitted"}},
		],
		"rewards": {"scrap": 25},
	},
	{
		"id": "marigold", "title": "The Marigold", "act": 2, "kind": "discovery", "region": "shatterlands",
		"summary": "A hauler lies nose-down in the growth, its back still dry. Someone stowed something up there.",
		"requires": [{"type": "flag", "id": "shatterlands_open"}],
		"steps": [{"text": "Climb the wrecked hauler and open its dorsal locker", "done": {"type": "flag", "id": "marigold_locker"}}],
		"rewards": {"scrap": 15},
	},
	{
		"id": "ilse_trail", "title": "Ilse Marrow's trail", "act": 1, "kind": "discovery", "region": "kettle",
		"summary": "The relay technician left notes everywhere she went. Find them all.",
		"requires": [{"type": "logs", "ids": ["relay_1"]}],
		"steps": [{"text": "Find every log Ilse Marrow left", "done": {"type": "logs", "ids": ILSE_LOGS}}],
		"rewards": {"scrap": 40, "flags": {"ilse_trail_read": true}},
	},
	{
		"id": "survivors", "title": "Reyes's people", "act": 1, "kind": "side", "region": "kettle",
		"summary": "Lt. Reyes's rescue team never left the planet. Learn where they went.",
		"requires": [{"type": "logs", "ids": ["moss_1"]}],
		"steps": [
			{"text": "Learn what happened to the Ferro-9's crew", "done": {"type": "logs", "ids": ["moss_3"]}},
			{"text": "Find out where Reyes's people sheltered", "done": {"type": "logs", "ids": ["freighter_3"]}},
		],
		"rewards": {"scrap": 30, "flags": {"knows_survivors": true}},
	},
	{
		"id": "listening_post", "title": "The listening post", "act": 1, "kind": "discovery", "region": "kettle",
		"summary": "A mast blinks amber high on the south-east slope. Someone left equipment running.",
		"requires": [{"type": "any", "of": [{"type": "flag", "id": "seen_listening_post"}, {"type": "flag", "id": "post_located"}]}],
		"steps": [{"text": "Climb to the listening post and wake its terminal", "done": {"type": "flag", "id": "post_awake"}, "at": "listening_post"}],
		"rewards": {"scrap": 25, "flags": {"heard_the_hollow": true}},
	},
	{
		"id": "last_drop", "title": "The last supply drop", "act": 1, "kind": "side", "region": "kettle",
		"summary": "The listening post picked up a distress beacon on the north-west flats: one of Reyes's drop pods.",
		"requires": [{"type": "flag", "id": "post_awake"}],
		"steps": [
			{"text": "Find the drop pod on the north-west flats", "done": {"type": "flag", "id": "pod_found"}, "at": "drop_pod"},
			{"text": "Pull the pod's flight recorder and hold the ground while it downloads", "done": {"type": "flag", "id": "pod_downloaded"}, "at": "drop_pod"},
		],
		"rewards": {"scrap": 30, "flags": {"knows_greenhouses": true}},
	},
	{
		"id": "survey_depot", "title": "The sealed depot", "act": 1, "kind": "discovery", "region": "kettle",
		"summary": "A survey depot on the northern flats, locked tight with an old HOB-series lock.",
		"requires": [{"type": "flag", "id": "seen_survey_depot"}],
		"steps": [
			{"text": "Get the depot open: HOB knows the lock, once he has power", "done": {"type": "flag", "id": "depot_open"}, "at": "survey_depot"},
			{"text": "Search the depot", "done": {"type": "flag", "id": "depot_core_taken"}, "at": "survey_depot"},
		],
		"rewards": {"scrap": 20, "flags": {"hob_has_wren": true}},
	},
	{
		"id": "drift_salvage", "title": "Drift salvage", "act": 1, "kind": "discovery", "region": "kettle",
		"summary": "Cargo from every ship the Loom pulled down lies half-buried across the basin.",
		"requires": [{"type": "caches", "count": 1}],
		"steps": [{"text": "Open every drift cache in the basin", "done": {"type": "caches", "count": -1}}],
		"rewards": {"scrap": 50},
	},
]

## Journal titles for the repair quests (by Campaign repair id).
const REPAIR_TITLES := {
	"aux_power": "Lights on", "cooling": "Hot springs", "canopy": "Up the spires",
	"landing_gear": "The quarry", "wing": "The moss field", "engine": "The graveyard",
	"navigation": "The Loom spire",
}

static var _all: Array[Dictionary] = []
static var _by_id: Dictionary = {}


## Every quest, repairs first in campaign order, then EXTRA.
static func all() -> Array[Dictionary]:
	if _all.is_empty():
		var prev := ""
		for r in Campaign.REPAIRS:
			var q := {
				"id": repair_quest(r["id"]), "title": REPAIR_TITLES.get(r["id"], String(r["banner"][0]).capitalize()), "act": 1,
				"kind": "main", "region": "kettle", "summary": r["find"],
				"requires": [] if prev == "" else [{"type": "quest", "id": repair_quest(prev)}],
				"steps": [
					{"text": r["find"], "done": {"type": "repair", "id": r["id"]}},
				],
				"repair": r["id"],
			}
			_all.append(q)
			prev = r["id"]
		_all.append_array(EXTRA)
		for q in _all:
			_by_id[q["id"]] = q
	return _all


static func get_quest(id: String) -> Dictionary:
	all()
	return _by_id.get(id, {})


static func repair_quest(repair_id: String) -> String:
	return "repair_" + repair_id


static func in_act(act: int) -> Array[Dictionary]:
	return all().filter(func(q): return int(q["act"]) == act)


## Problems with the data, as readable lines; empty when every reference resolves, every quest
## can be reached and no requirement loops. The content test fails on any line.
static func validate(region_ids: Array, cache_count: int, discovery_ids: Array = []) -> PackedStringArray:
	var bad: PackedStringArray = []
	var ids := {}
	for q in all():
		var id := String(q.get("id", ""))
		if id == "" or ids.has(id):
			bad.append("missing or duplicate quest id '%s'" % id)
		ids[id] = true
	for q in all():
		var id: String = q["id"]
		for key in ["title", "summary"]:
			if String(q.get(key, "")) == "":
				bad.append("%s has no %s" % [id, key])
		if not ACTS.has(int(q.get("act", 0))):
			bad.append("%s is in no act" % id)
		if not String(q.get("kind", "")) in KINDS:
			bad.append("%s has an unknown kind" % id)
		if not String(q.get("region", "")) in region_ids:
			bad.append("%s is in unknown region '%s'" % [id, q.get("region", "")])
		if (q.get("steps", []) as Array).is_empty():
			bad.append("%s has no steps" % id)
		var conds: Array = (q.get("requires", []) as Array).duplicate()
		for s in q.get("steps", []):
			if String(s.get("text", "")) == "":
				bad.append("%s has a step with no objective text" % id)
			var at = s.get("at")
			if at is String and not at in discovery_ids:
				bad.append("%s points at unknown discovery '%s'" % [id, at])
			conds.append(s.get("done", {}))
		for c in conds:
			var problem := _check_condition(c, ids, cache_count)
			if problem != "":
				bad.append("%s: %s" % [id, problem])
	# Requirement loops: a quest that (through others) needs itself can never start.
	for q in all():
		if _needs_itself(q["id"], q["id"], {}):
			bad.append("%s needs itself to start" % q["id"])
	return bad


static func _check_condition(c: Dictionary, ids: Dictionary, cache_count: int) -> String:
	match String(c.get("type", "")):
		"quest":
			return "" if ids.has(c.get("id", "")) else "needs unknown quest '%s'" % c.get("id", "")
		"repair":
			return "" if Campaign.index_of(String(c.get("id", ""))) >= 0 else "needs unknown repair '%s'" % c.get("id", "")
		"flag":
			return "" if String(c.get("id", "")) != "" else "flag condition with no id"
		"logs":
			for l in c.get("ids", []):
				if Story.get_log(String(l)).is_empty():
					return "needs unknown log '%s'" % l
			return "" if not (c.get("ids", []) as Array).is_empty() else "logs condition with no logs"
		"caches":
			return "" if int(c.get("count", 0)) <= cache_count else "needs %d caches, the basin has %d" % [c["count"], cache_count]
		"launched":
			return ""
		"any":
			var of: Array = c.get("of", [])
			if of.is_empty():
				return "an 'any' condition with nothing in it"
			for sub in of:
				var why := _check_condition(sub, ids, cache_count)
				if why != "":
					return why
			return ""
	return "unknown condition type '%s'" % c.get("type", "")


static func _needs_itself(start: String, id: String, seen: Dictionary) -> bool:
	if seen.has(id):
		return false
	seen[id] = true
	for c in get_quest(id).get("requires", []):
		if c.get("type") == "quest":
			if c["id"] == start or _needs_itself(start, c["id"], seen):
				return true
	return false
