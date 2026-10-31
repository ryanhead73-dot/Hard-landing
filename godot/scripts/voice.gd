class_name Voice
extends Node
## Plays story lines ([speaker, text]) one after another as subtitles. Lines queue up, so a
## repair's outro and the next mission's intro play in order. Pauses with the game.

signal line_started(speaker: String, text: String)
signal finished

var hud: Hud
## Every line said this session, as "Speaker: text" (tests and the log of what's been heard).
var history: Array[String] = []

var _queue: Array = []
var _current: Array = []
var _time := 0.0


## Queues lines; each is [speaker, text].
func say(lines: Array) -> void:
	for line in lines:
		_queue.append(line)
	if _current.is_empty():
		_next()


## Cuts off whatever is playing or queued and says these now (alarms, the finale).
func interrupt(lines: Array) -> void:
	clear()
	say(lines)


func say_line(line: Array) -> void:
	say([line])


func busy() -> bool:
	return not _current.is_empty()


func current_text() -> String:
	return "" if _current.is_empty() else "%s: %s" % _current


## True if a line containing `fragment` has been said, is on screen, or is waiting in the queue.
func heard(fragment: String) -> bool:
	if history.any(func(h): return h.contains(fragment)):
		return true
	return _queue.any(func(line): return String(line[1]).contains(fragment))


## Drops everything queued and clears the subtitle (cutscenes take over).
func clear() -> void:
	_queue.clear()
	_current = []
	if hud:
		hud.set_voice("", "")


## Reading time for a line: a bit under three words a second, within sensible bounds.
static func duration(text: String) -> float:
	return clampf(1.4 + text.length() * 0.055, 2.5, 9.0)


func _process(delta: float) -> void:
	if _current.is_empty():
		return
	_time -= delta
	if _time <= 0.0:
		_next()


func _next() -> void:
	if _queue.is_empty():
		var was_busy := not _current.is_empty()
		_current = []
		if hud:
			hud.set_voice("", "")
		if was_busy:
			finished.emit()
		return
	_current = _queue.pop_front()
	_time = duration(_current[1])
	history.append("%s: %s" % _current)
	if hud:
		hud.set_voice(_current[0], _current[1])
	line_started.emit(_current[0], _current[1])
