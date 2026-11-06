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
var _controls: Label
var _grid: GridContainer


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
	_panel.custom_minimum_size = Vector2(640, 0)
	centre.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	UiStyle.apply(title, "banner")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# Settings as a two-column grid: name on the left, control on the right.
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 28)
	_grid.add_theme_constant_override("v_separation", 10)
	box.add_child(_grid)
	_section("CONTROLS")
	_sensitivity = _slider(_grid, "Mouse sensitivity", 0.0005, 0.006, 0.0001, Game.mouse_sensitivity)
	_invert = CheckBox.new()
	_invert.text = "Invert look Y"
	_invert.button_pressed = Game.invert_y
	_row_label("")
	_grid.add_child(_invert)
	_section("AUDIO")
	_volume = _slider(_grid, "Volume", 0.0, 1.0, 0.05, Game.master_volume)
	_music = _slider(_grid, "Music", 0.0, 1.0, 0.05, Game.music_volume)
	var effects := _slider(_grid, "Effects", 0.0, 1.0, 0.05, Game.sfx_volume)
	effects.name = "EffectsVolume"
	effects.value_changed.connect(func(v: float):
		Game.sfx_volume = v
		Game.apply_settings())
	_section("GAME")
	_difficulty = OptionButton.new()
	for d in Game.DIFFICULTY_NAMES:
		_difficulty.add_item(d)
	_difficulty.selected = Game.difficulty
	_difficulty.item_selected.connect(func(i: int):
		Game.difficulty = i
		Game.apply_settings())
	_row_label("Difficulty")
	_grid.add_child(_difficulty)
	var shake := _slider(_grid, "Screen shake", 0.0, 1.0, 0.05, Game.screen_shake)
	shake.value_changed.connect(func(v: float): Game.screen_shake = v)
	var gfx := OptionButton.new()
	for preset in Game.GRAPHICS_NAMES:
		gfx.add_item(preset)
	gfx.tooltip_text = "Medium is tuned for a GTX 1660-class card at 1080p, 60 fps."
	gfx.selected = Game.graphics
	gfx.item_selected.connect(func(i: int):
		Game.graphics = i
		Game.graphics_changed.emit())
	_row_label("Graphics")
	_grid.add_child(gfx)
	var fps := CheckBox.new()
	fps.text = "Show frame rate (F3)"
	fps.button_pressed = Game.show_fps
	fps.toggled.connect(func(on: bool):
		Game.show_fps = on
		Game.apply_settings())
	Game.settings_changed.connect(func(): fps.set_pressed_no_signal(Game.show_fps))
	_row_label("")
	_grid.add_child(fps)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(close)
	buttons.add_child(resume)
	var title_button := Button.new()
	title_button.text = "Save and quit to title"
	title_button.pressed.connect(func():
		close()
		quit_to_title.emit())
	buttons.add_child(title_button)
	var quit := Button.new()
	quit.text = "Quit to desktop"
	quit.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit)
	for b in [resume, title_button, quit]:
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls = Label.new()
	_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStyle.apply(_controls, "small", UiStyle.DIM)
	_controls.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_controls)

	_sensitivity.value_changed.connect(_on_sensitivity)
	_invert.toggled.connect(_on_invert)
	_volume.value_changed.connect(_on_volume)
	_music.value_changed.connect(func(v: float):
		Game.music_volume = v
		Game.apply_settings())
	visible = false


## A section head spanning both columns.
func _section(text: String) -> void:
	var head := Label.new()
	head.text = text
	UiStyle.apply(head, "label", UiStyle.AMBER)
	_grid.add_child(head)
	_grid.add_child(Control.new())


func _row_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(190, 0)
	_grid.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	# Another panel (fabricator, inventory) owns the pause while it's open.
	if get_tree().paused and not visible:
		return
	if event.is_action_pressed("ui_cancel") or (visible and Game.is_pad_back(event)):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_controls.text = "Controls: " + (Hud.PAD_HELP_TEXT if Game.using_pad else Hud.HELP_TEXT)
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
	label.custom_minimum_size = Vector2(190, 0)
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(380, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(slider)
	return slider
