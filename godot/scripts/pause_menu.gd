class_name PauseMenu
extends CanvasLayer
## Esc pauses the game and opens settings: mouse sensitivity, invert Y, hold or toggle aim,
## volumes, subtitles (off, on, large, largest), difficulty, shake, graphics and the fps readout.
## Settings are saved to user://settings.cfg when the menu closes.

signal quit_to_title
## Main saves on this before the game quits.
signal quit_to_desktop

var _panel: PanelContainer
var _sensitivity: HSlider
var _invert: CheckBox
var _volume: HSlider
var _music: HSlider
var _difficulty: OptionButton
var _controls: Label
var _grid: GridContainer
var bindings: KeyBindMenu
var _resume: Button
var _title_button: Button
## Opened from the title screen as Settings: no pause, no quit to title, the mouse stays free.
var from_title := false
signal closed


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
	_panel.custom_minimum_size = Vector2(1100, 0)
	centre.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	var title := Label.new()
	title.name = "Heading"
	title.text = "PAUSED"
	UiStyle.apply(title, "banner")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# Settings in two side-by-side grids (controls and audio, then game and display), each with
	# the name on the left and the control on the right, so the menu fits a 900-pixel-high window.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 56)
	box.add_child(columns)
	var grids: Array[GridContainer] = []
	for i in 2:
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 24)
		g.add_theme_constant_override("v_separation", 10)
		g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		columns.add_child(g)
		grids.append(g)
	_grid = grids[0]
	_section("CONTROLS")
	_sensitivity = _slider(_grid, "Mouse sensitivity", 0.0005, 0.006, 0.0001, Game.mouse_sensitivity)
	_invert = CheckBox.new()
	_invert.text = "Invert look Y"
	_invert.button_pressed = Game.invert_y
	_row_label("")
	_grid.add_child(_invert)
	var aim_mode := OptionButton.new()
	aim_mode.name = "AimMode"
	aim_mode.add_item("Hold")
	aim_mode.add_item("Toggle")
	aim_mode.selected = 1 if Game.toggle_aim else 0
	aim_mode.item_selected.connect(func(i: int):
		Game.toggle_aim = i == 1
		Game.apply_settings())
	_row_label("Aim")
	_grid.add_child(aim_mode)
	var keys := Button.new()
	keys.name = "KeyBindings"
	keys.text = "Key bindings…"
	keys.pressed.connect(_open_bindings)
	_row_label("Keyboard")
	_grid.add_child(keys)
	_section("AUDIO")
	_volume = _slider(_grid, "Volume", 0.0, 1.0, 0.05, Game.master_volume)
	_music = _slider(_grid, "Music", 0.0, 1.0, 0.05, Game.music_volume)
	var effects := _slider(_grid, "Effects", 0.0, 1.0, 0.05, Game.sfx_volume)
	effects.name = "EffectsVolume"
	effects.value_changed.connect(func(v: float):
		Game.sfx_volume = v
		Game.apply_settings())
	var subs := OptionButton.new()
	subs.name = "Subtitles"
	for t in Game.SUBTITLE_NAMES:
		subs.add_item(t)
	subs.selected = Game.subtitles
	subs.item_selected.connect(func(i: int):
		Game.subtitles = i
		Game.apply_settings())
	_row_label("Subtitles")
	_grid.add_child(subs)
	_grid = grids[1]
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
	_section("DISPLAY")
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
	var display := OptionButton.new()
	display.name = "WindowMode"
	for t in Game.WINDOW_NAMES:
		display.add_item(t)
	display.selected = Game.window_mode
	display.item_selected.connect(func(i: int):
		Game.window_mode = i
		Game.apply_settings())
	_row_label("Display")
	_grid.add_child(display)
	var cap := OptionButton.new()
	cap.name = "FpsCap"
	for c in Game.FPS_CAPS:
		cap.add_item("None" if c == 0 else "%d fps" % c)
	cap.selected = Game.FPS_CAPS.find(Game.fps_cap)
	cap.item_selected.connect(func(i: int):
		Game.fps_cap = Game.FPS_CAPS[i]
		Game.apply_settings())
	_row_label("Frame cap")
	_grid.add_child(cap)
	var vsync := CheckBox.new()
	vsync.name = "VSync"
	vsync.text = "V-sync"
	vsync.button_pressed = Game.vsync
	vsync.toggled.connect(func(on: bool):
		Game.vsync = on
		Game.apply_settings())
	_row_label("")
	_grid.add_child(vsync)
	Game.settings_changed.connect(func():
		display.selected = Game.window_mode
		vsync.set_pressed_no_signal(Game.vsync))
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
	resume.name = "Resume"
	resume.text = "Resume"
	_resume = resume
	resume.pressed.connect(close)
	buttons.add_child(resume)
	var title_button := Button.new()
	_title_button = title_button
	title_button.text = "Save and quit to title"
	title_button.pressed.connect(func():
		close()
		quit_to_title.emit())
	buttons.add_child(title_button)
	var quit := Button.new()
	quit.name = "QuitDesktop"
	quit.text = "Save and quit to desktop"
	quit.pressed.connect(func():
		if not from_title:
			quit_to_desktop.emit()
		get_tree().quit())
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
	# A sibling layer, not a child: it shows while this menu hides.
	bindings = KeyBindMenu.new()
	get_parent().add_child.call_deferred(bindings)
	bindings.closed.connect(func():
		_controls.text = "Controls: " + (Hud.PAD_HELP_TEXT if Game.using_pad else Hud.help_text())
		visible = true)
	visible = false


func _process(_delta: float) -> void:
	if visible:
		UiStyle.keep_pad_focus(self, _resume)


## Alt-tabbing out of a game in progress pauses it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not from_title and not visible and not get_tree().paused \
			and DisplayServer.get_name() != "headless":
		open()


func _open_bindings() -> void:
	visible = false
	bindings.open()


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
	label.custom_minimum_size = Vector2(180, 0)
	_grid.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	# Another panel (fabricator, inventory) owns the pause while it's open.
	if get_tree().paused and not visible:
		return
	# On the title screen the menu opens from its Settings button, never from Esc.
	if from_title and not visible:
		return
	if event.is_action_pressed("ui_cancel") or (visible and Game.is_pad_back(event)):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_controls.text = "Controls: " + (Hud.PAD_HELP_TEXT if Game.using_pad else Hud.help_text())
	_resume.text = "Back" if from_title else "Resume"
	(find_child("QuitDesktop", true, false) as Button).text = "Quit to desktop" if from_title else "Save and quit to desktop"
	_title_button.visible = not from_title
	(_panel.find_child("Heading", true, false) as Label).text = "SETTINGS" if from_title else "PAUSED"
	_difficulty.selected = Game.difficulty
	visible = true
	if not from_title:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	if not from_title:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.save_settings()
	closed.emit()


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
	label.custom_minimum_size = Vector2(180, 0)
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(290, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(slider)
	return slider
