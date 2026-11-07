class_name JournalPanel
extends UiPanel
## J: the quest journal. The act Juno is in, what each active quest wants next (with a count
## where a quest collects things), and what's done. Reads QuestDB and main.quests; changes
## nothing.

const ROMAN := ["", "I", "II", "III", "IV"]

var main: Node


func _ready() -> void:
	super._ready()
	_toggle_action = "journal"


func _refresh() -> void:
	_clear()
	var q: QuestLog = main.quests
	var act: Dictionary = QuestDB.ACTS.get(Game.act, {})
	_title.text = "JOURNAL  ·  ACT %s  %s" % [ROMAN[clampi(Game.act, 1, 4)], String(act.get("name", "")).to_upper()]
	_row(String(act.get("summary", "")), UiStyle.DIM, 14)
	var active := q.active()
	var main_quests := active.filter(func(x): return x["kind"] == "main")
	var others := active.filter(func(x): return x["kind"] != "main")
	_row("MAIN", UiStyle.AMBER, 13)
	if main_quests.is_empty():
		_row("Nothing pressing.", UiStyle.DIM, 15)
	for x in main_quests:
		_quest(x, q)
	_row("SIDE MISSIONS AND DISCOVERIES", UiStyle.AMBER, 13)
	if others.is_empty():
		_row("None yet. Logs and caches out in the basin can start one.", UiStyle.DIM, 15)
	for x in others:
		_quest(x, q)
	var done := QuestDB.all().filter(func(x): return q.is_done(x["id"]))
	if not done.is_empty():
		_row("DONE  %d" % done.size(), UiStyle.AMBER, 13)
		_row("  ·  ".join(done.map(func(x): return x["title"])), UiStyle.DIM, 14)
	var b := Button.new()
	b.text = "Logs (%d)" % Game.logs.size()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		close()
		main.logs_panel.open_latest())
	_content.add_child(b)


func _quest(x: Dictionary, q: QuestLog) -> void:
	var tag := "" if x["kind"] == "main" else ("  (discovery)" if x["kind"] == "discovery" else "  (side)")
	_row(String(x["title"]) + tag, UiStyle.TEAL, 16)
	var line := q.objective(x["id"])
	var count := q.progress(x["id"])
	if count.y > 0:
		line += "  %d / %d" % [count.x, count.y]
	var at = q.marker(x["id"])
	if at is Vector3 and main.player:
		var from: Vector3 = main.player.global_position
		line += "  ·  %d m %s" % [int(Vector2(at.x - from.x, at.z - from.z).length()), MissionRunner.compass_word(from, at)]
	_row("◆ " + line, UiStyle.CREAM, 15)
