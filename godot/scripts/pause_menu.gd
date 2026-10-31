class_name PauseMenu
extends CanvasLayer
## Esc pauses the game and opens settings: mouse sensitivity, invert Y, volume and difficulty.
## Settings are saved to user://settings.cfg when the menu closes.

signal quit_to_title

var _panel: PanelContainer
var _sensitivity: HSlider
var _invert: CheckBox
var _volume: HSlider
var _music: HSlider
var _difficulty: OptionButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(centre)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(420, 0)
	centre.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_sensitivity = _slider(box, "Mouse sensitivity", 0.0005, 0.006, 0.0001, Game.mouse_sensitivity)
	_invert = CheckBox.new()
	_invert.text = "Invert look Y"
	_invert.button_pressed = Game.invert_y
	box.add_child(_invert)
	_volume = _slider(box, "Volume", 0.0, 1.0, 0.05, Game.master_volume)
	_music = _slider(box, "Music", 0.0, 1.0, 0.05, Game.music_volume)
	var diff_label := Label.new()
	diff_label.text = "Difficulty"
	box.add_child(diff_label)
	_difficulty = OptionButton.new()
	for d in Game.DIFFICULTY_NAMES:
		_difficulty.add_item(d)
	_difficulty.selected = Game.difficulty
	_difficulty.item_selected.connect(func(i: int):
		Game.difficulty = i
		Game.apply_settings())
	box.add_child(_difficulty)

	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(close)
	box.add_child(resume)
	var title_button := Button.new()
	title_button.text = "Save and quit to title"
	title_button.pressed.connect(func():
		close()
		quit_to_title.emit())
	box.add_child(title_button)
	var quit := Button.new()
	quit.text = "Quit to desktop"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)

	_sensitivity.value_changed.connect(_on_sensitivity)
	_invert.toggled.connect(_on_invert)
	_volume.value_changed.connect(_on_volume)
	_music.value_changed.connect(func(v: float):
		Game.music_volume = v
		Game.apply_settings())
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	# Another panel (fabricator, inventory) owns the pause while it's open.
	if get_tree().paused and not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.save_settings()


func _on_sensitivity(value: float) -> void:
	Game.mouse_sensitivity = value
	Game.apply_settings()


func _on_invert(on: bool) -> void:
	Game.invert_y = on
	Game.apply_settings()


func _on_volume(value: float) -> void:
	Game.master_volume = value
	Game.apply_settings()


func _slider(parent: Node, label_text: String, lo: float, hi: float, step: float, value: float) -> HSlider:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(380, 24)
	parent.add_child(slider)
	return slider
