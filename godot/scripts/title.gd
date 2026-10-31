extends Node3D
## Title screen: Kestrel at the crash site behind the menu. Continue picks up the saved campaign,
## New game starts over (the old save is replaced at the first install or rest).

var continue_button: Button
var new_button: Button

var _difficulty: OptionButton
var _camera: Camera3D
var _t := 0.0


func _ready() -> void:
	Game.reset()
	_build_scene()
	_build_menu()
	Sfx.loop("wind_loop", null, -14.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
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
	add_child(layer)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	layer.add_child(box)
	var title := Label.new()
	title.text = "HARD LANDING"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("e9e1cc"))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Kestrel is down on the Kettle. Get her flying."
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color("ffb24d"))
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
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
