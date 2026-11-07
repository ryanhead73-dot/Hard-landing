extends Node3D
## Title screen: Kestrel at the crash site behind the menu. Continue picks up the saved campaign,
## New game starts over (the old save is replaced at the first install or rest).

var continue_button: Button
var new_button: Button

var settings: PauseMenu
var credits: CreditsPanel
var _menu: CanvasLayer
var _difficulty: OptionButton
var _camera: Camera3D
var _t := 0.0


func _ready() -> void:
	Game.reset()
	# Keyboard bindings, so Settings > Key bindings and the controls line read right here too.
	if Game.default_keys.is_empty():
		Game.default_keys = (load("res://scripts/main.gd") as Script).get_script_constant_map()["KEYS"].duplicate(true)
		Game.apply_keys()
	_build_scene()
	_build_menu()
	Sfx.loop_flat("wind_loop", self, -14.0, "Ambience")
	Sfx.loop_flat("music_calm", self, -10.0, "Music")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# `-- --benchmark [low|medium|high]` runs the benchmark straight away.
	var args := OS.get_cmdline_user_args()
	if "--benchmark" in args:
		for i in Game.GRAPHICS_NAMES.size():
			if Game.GRAPHICS_NAMES[i].to_lower() in args:
				Game.graphics = i
		get_tree().change_scene_to_file.call_deferred("res://scenes/benchmark.tscn")


func _process(delta: float) -> void:
	if not settings.visible and not settings.bindings.visible and not credits.visible:
		UiStyle.keep_pad_focus(_menu, continue_button if not continue_button.disabled else new_button)
	# A slow drift around the wreck.
	_t += delta * 0.04
	_camera.position = Vector3(cos(_t) * 38.0, 9.0, sin(_t) * 38.0 + 6.0)
	_camera.look_at(Vector3(0.0, 2.5, 0.0))


func start(load_save: bool) -> void:
	Game.pending_load = Game.read_save() if load_save else {}
	Game.intro_pending = not load_save
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _build_scene() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("1d2733")
	sky_mat.sky_horizon_color = Color("5b4a52")
	sky_mat.ground_horizon_color = Color("2a2a30")
	sky_mat.ground_bottom_color = Color("0e1012")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color("3a3540")
	env.fog_density = 0.006
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-10.0, 60.0, 0.0)
	sun.light_color = Color("ff9a6a")
	sun.light_energy = 0.35
	add_child(sun)
	var site := CrashSite.new()
	add_child(site)
	site.set_dusk(true)
	var ship := Kestrel.new()
	ship.position = Vector3(0.0, 1.0, 0.0)
	add_child(ship)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)


func _build_menu() -> void:
	var layer := CanvasLayer.new()
	_menu = layer
	add_child(layer)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	layer.add_child(box)
	var title := Label.new()
	title.text = "HARD LANDING"
	UiStyle.apply(title, "title")
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Kestrel is down on the Kettle. Get her flying."
	UiStyle.apply(sub, "heading", UiStyle.ORANGE)
	box.add_child(sub)
	box.add_child(Control.new())
	continue_button = _button(box, "Continue", start.bind(true))
	continue_button.disabled = Game.read_save().is_empty()
	new_button = _button(box, "New game", start.bind(false))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Difficulty  "
	row.add_child(label)
	_difficulty = OptionButton.new()
	for d in Game.DIFFICULTY_NAMES:
		_difficulty.add_item(d)
	_difficulty.selected = Game.difficulty
	_difficulty.item_selected.connect(func(i: int):
		Game.difficulty = i
		Game.save_settings())
	row.add_child(_difficulty)
	box.add_child(row)
	settings = PauseMenu.new()
	settings.from_title = true
	add_child(settings)
	settings.closed.connect(func(): _difficulty.selected = Game.difficulty)
	credits = CreditsPanel.new()
	add_child(credits)
	_button(box, "Settings", settings.open).name = "Settings"
	var bench := _button(box, "Benchmark", func(): get_tree().change_scene_to_file("res://scenes/benchmark.tscn"))
	bench.tooltip_text = "A one-minute run through the slice that measures frame times and saves a report."
	_button(box, "Credits", credits.open).name = "Credits"
	_button(box, "Quit", func(): get_tree().quit())
	# Anchor once the contents give it a size: left edge, centred vertically at any resolution.
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 90)
	if not continue_button.disabled:
		continue_button.grab_focus.call_deferred()
	else:
		new_button.grab_focus.call_deferred()


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 44)
	b.pressed.connect(func(): Sfx.play("ui_click", null, -4.0, 0.0))
	b.pressed.connect(action)
	parent.add_child(b)
	return b
