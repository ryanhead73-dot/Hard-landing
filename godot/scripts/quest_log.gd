class_name QuestLog
extends Node
## Tracks every QuestDB quest for the running game: which have started, which step each is on and
## which are done, kept in Game.quests ({state, step}) so it saves with the session. It works by
## re-checking conditions whenever something they read changes (repairs, logs, caches, flags, the
## launch), so existing systems never need to know quests exist.
##
## restore() rebuilds the log quietly after a load, including from a save made before quests
## existed: quests the save has already finished are marked done without rewards or messages.

signal quest_started(id: String)
signal step_advanced(id: String, step: int)
signal quest_completed(id: String)

const LOCKED := "locked"
const ACTIVE := "active"
const DONE := "done"

var main: Node
## While true, changes are recorded without rewards or messages (loading, restoring).
var quiet := false
var _dirty := false


func _ready() -> void:
	Game.repairs_changed.connect(_mark)
	Game.log_found.connect(func(_id): _mark())
	Game.inventory_changed.connect(_mark)
	Game.flag_changed.connect(func(_id, _v): _mark())


func _mark() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty or (Game.launched and state_of("escape") != DONE):
		_dirty = false
		refresh()


## Rebuilds quest state from the game as it stands, silently (after a load or a new game).
func restore() -> void:
	quiet = true
	refresh()
	quiet = false


func state_of(id: String) -> String:
	return String((Game.quests.get(id, {}) as Dictionary).get("state", LOCKED))


func step_of(id: String) -> int:
	return int((Game.quests.get(id, {}) as Dictionary).get("step", 0))


func is_done(id: String) -> bool:
	return state_of(id) == DONE


## Active quests, main ones first, as QuestDB entries.
func active() -> Array[Dictionary]:
	var out: Array[Dictionary] = QuestDB.all().filter(func(q): return state_of(q["id"]) == ACTIVE)
	out.sort_custom(func(a, b): return QuestDB.KINDS.find(a["kind"]) < QuestDB.KINDS.find(b["kind"]))
	return out


## The objective line of an active quest's current step, or "".
func objective(id: String) -> String:
	var steps: Array = QuestDB.get_quest(id).get("steps", [])
	var i := step_of(id)
	return String(steps[i]["text"]) if state_of(id) == ACTIVE and i < steps.size() else ""


## Checks every quest until nothing more changes (one quest finishing can start the next).
func refresh() -> void:
	var changed := true
	var guard := 0
	while changed and guard < 64:
		changed = false
		guard += 1
		for q in QuestDB.all():
			if _advance(q):
				changed = true


func _advance(q: Dictionary) -> bool:
	var id: String = q["id"]
	var state := state_of(id)
	if state == DONE:
		return false
	if state == LOCKED:
		if not q.get("requires", []).all(func(c): return holds(c)):
			return false
		_set_state(id, ACTIVE, 0)
		if not quiet:
			quest_started.emit(id)
			if q["kind"] != "main":
				_say("New %s: %s" % ["discovery" if q["kind"] == "discovery" else "side mission", q["title"]])
		return true
	var steps: Array = q["steps"]
	var i := step_of(id)
	var moved := false
	while i < steps.size() and holds(steps[i]["done"]):
		i += 1
		moved = true
	if not moved:
		return false
	if i >= steps.size():
		_set_state(id, DONE, i)
		if not quiet:
			_reward(q)
			quest_completed.emit(id)
			if q["kind"] != "main":
				_say("Complete: %s" % q["title"])
		elif q.has("rewards"):
			# Flags still matter after a quiet catch-up (later quests read them); scrap was
			# never earned in a save that predates quests, so none is given.
			for f in q["rewards"].get("flags", {}):
				Game.flags[f] = q["rewards"]["flags"][f]
	else:
		_set_state(id, ACTIVE, i)
		if not quiet:
			step_advanced.emit(id, i)
	return true


func _set_state(id: String, state: String, step: int) -> void:
	Game.quests[id] = {"state": state, "step": step}


func _reward(q: Dictionary) -> void:
	var r: Dictionary = q.get("rewards", {})
	if r.has("scrap"):
		Game.add_scrap(int(r["scrap"]))
	for f in r.get("flags", {}):
		Game.set_flag(f, r["flags"][f])


func _say(text: String) -> void:
	if main and main.get("hud"):
		main.hud.show_message(text)


## Whether a QuestDB condition holds right now.
func holds(c: Dictionary) -> bool:
	match String(c.get("type", "")):
		"quest":
			return is_done(String(c["id"]))
		"repair":
			return Game.is_repaired(String(c["id"]))
		"flag":
			return Game.flags.get(String(c["id"])) == c.get("value", true)
		"logs":
			return (c["ids"] as Array).all(func(l): return Game.has_log(String(l)))
		"caches":
			var need := int(c["count"])
			if need < 0:
				need = cache_total()
			return need > 0 and Game.caches_opened.size() >= need
		"launched":
			return Game.launched
	return false


func cache_total() -> int:
	if main and main.get("wildlife"):
		return main.wildlife.caches.size()
	return 0
