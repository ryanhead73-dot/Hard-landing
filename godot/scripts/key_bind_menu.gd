class_name KeyBindMenu
extends CanvasLayer
## Keyboard bindings, opened from the pause menu: every rebindable action with its key. Click a
## key, then press the new one (Esc cancels). A key already in use swaps with it. Saved to
## user://settings.cfg when the menu closes.

signal closed

var _grid: GridContainer
var _buttons: Dictionary = {}
var _back: Button
## The action waiting for a key press, or "".
var listening := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := Label.new()
	title.text = "KEY BINDINGS"
	UiStyle.apply(title, "banner")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := Label.new()
	note.text = "Click a key, then press the new one. Esc (or B) cancels. A key in use swaps over."
	UiStyle.apply(note, "small", UiStyle.DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	# Two columns of name + key, so the list fits a 900-pixel-high window.
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_grid)
	for pair in Game.REBINDABLE:
		var action: String = pair[0]
		var label := Label.new()
		label.text = pair[1]
		label.custom_minimum_size = Vector2(190, 0)
		_grid.add_child(label)
		var b := Button.new()
		b.name = "Key_" + action
		b.custom_minimum_size = Vector2(170, 36)
		b.pressed.connect(_listen.bind(action))
		_grid.add_child(b)
		_buttons[action] = b
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(func():
		listening = ""
		Game.reset_keys())
	row.add_child(reset)
	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	_back = back
	back.pressed.connect(close)
	row.add_child(back)
	for b in [reset, back]:
		b.custom_minimum_size = Vector2(220, 44)
	Game.keys_changed.connect(_refresh)
	_refresh()
	visible = false


func open() -> void:
	listening = ""
	_refresh()
	visible = true


func close() -> void:
	listening = ""
	visible = false
	Game.save_settings()
	closed.emit()


func _process(_delta: float) -> void:
	if visible:
		UiStyle.keep_pad_focus(self, _back)


func _listen(action: String) -> void:
	listening = action
	_refresh()


func _refresh() -> void:
	for action in _buttons:
		(_buttons[action] as Button).text = "Press a key…" if action == listening else Game.key_label(action)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if listening != "" and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode != KEY_ESCAPE:
			Game.rebind(listening, event.physical_keycode)
		listening = ""
		_refresh()
		get_viewport().set_input_as_handled()
	elif listening != "" and Game.is_pad_back(event):
		listening = ""
		_refresh()
		get_viewport().set_input_as_handled()
	elif listening == "" and (event.is_action_pressed("ui_cancel") or Game.is_pad_back(event)):
		close()
		get_viewport().set_input_as_handled()
