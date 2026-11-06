class_name FpsOverlay
extends CanvasLayer
## The frame-rate readout (F3, or "Show frame rate" in the pause menu): frames per second, the
## average frame time and the worst frame over the last second, and the draw calls.

var label: Label
var _times := PackedFloat64Array()
var _last := 0
var _refresh := 0.0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	UiStyle.apply(label, "small", UiStyle.CREAM)
	label.position = Vector2(12, 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_last = Time.get_ticks_usec()
	_sync()
	Game.settings_changed.connect(_sync)


func _sync() -> void:
	visible = Game.show_fps


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_times.append((now - _last) / 1000.0)
	_last = now
	var total := 0.0
	for ms in _times:
		total += ms
	while total > 1000.0 and _times.size() > 1:
		total -= _times[0]
		_times.remove_at(0)
	_refresh -= _delta
	if not visible or _refresh > 0.0:
		return
	_refresh = 0.25
	var worst := 0.0
	for ms in _times:
		worst = maxf(worst, ms)
	var avg := total / maxf(1.0, _times.size())
	label.text = "%d fps  ·  %.1f ms  ·  worst %.1f ms  ·  %d draws" % [
		roundi(1000.0 / maxf(avg, 0.001)), avg, worst, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
