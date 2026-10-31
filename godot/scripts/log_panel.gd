class_name LogPanel
extends UiPanel
## L: the data slates Juno has recovered. Opens on one log, or on the list of all of them.

## The log on screen, or "" for the list.
var showing := ""


func _ready() -> void:
	super._ready()
	_toggle_action = "logs"


## Opens straight onto one log.
func open_log(id: String) -> void:
	showing = id
	open()


## Opens on the newest log, or the list when there are none.
func open_latest() -> void:
	open_log(Game.logs[-1] if not Game.logs.is_empty() else "")


func _refresh() -> void:
	_clear()
	if showing != "" and not Story.get_log(showing).is_empty():
		var l := Story.get_log(showing)
		_title.text = l["title"]
		_row(l["author"], Color("9fe8d8"), 15)
		_row(l["text"], Color("e9e1cc"), 17)
		if Game.logs.size() > 1:
			_button("All logs (%d)" % Game.logs.size(), func():
				showing = ""
				_refresh())
		return
	_title.text = "LOGS  %d / %d" % [Game.logs.size(), Story.LOGS.size()]
	if Game.logs.is_empty():
		_row("No logs yet. Salvage crates and components sometimes carry a data slate.")
		return
	for id in Game.logs:
		var l := Story.get_log(id)
		_button("%s  ·  %s" % [l["title"], l["author"]], func():
			showing = id
			_refresh())


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	_content.add_child(b)
	return b
