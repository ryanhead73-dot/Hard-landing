class_name UiPanel
extends CanvasLayer
## Base for the full-screen panels (fabricator, inventory): dims the game, pauses it, shows the
## mouse, and closes on Esc or the key that opened it. Subclasses fill _content in _refresh().

signal closed

var _box: VBoxContainer
var _content: VBoxContainer
var _title: Label
var _toggle_action := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 9
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1b1d1f")
	style.border_color = Color("c4622d")
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	panel.add_child(_box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color("ffd08a"))
	_box.add_child(_title)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	_box.add_child(_content)
	var hint := Label.new()
	hint.text = "Esc to close"
	hint.modulate = Color(1, 1, 1, 0.6)
	_box.add_child(hint)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (_toggle_action != "" and event.is_action_pressed(_toggle_action)):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func open() -> void:
	if get_tree().paused:
		return
	_refresh()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _refresh() -> void:
	pass


func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()


func _row(text: String, color := Color.WHITE, size := 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)
	return l
