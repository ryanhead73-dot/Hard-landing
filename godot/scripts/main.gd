extends Node3D
## Runtime setup for the Kestrel blockout: sky and sun, player, HUD and dev controls.

const SPAWN := Vector3(-3.0, 0.5, 15.0)
const INTERACT_RANGE := 1.8
const INPUTS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"crouch": [KEY_C, KEY_CTRL],
	"interact": [KEY_E],
	"flashlight": [KEY_F],
}
const CONTROLS_TEXT := """WASD move · Mouse look · Shift sprint · Space jump · C crouch
E interact · F flashlight · N day/dusk · R respawn · Esc free mouse
1-7 toggle repair states (dev)"""

@onready var kestrel: Kestrel = $Kestrel
@onready var site: CrashSite = $CrashSite

var player: Player
var dusk := false

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _prompt: Label
var _boom: Label
var _status: Label


func _ready() -> void:
	_setup_input()
	_build_environment()
	player = Player.new()
	player.name = "Player"
	add_child(player)
	_respawn()
	_build_hud()
	kestrel.repair_changed.connect(_on_repair_changed)
	_refresh_status()
	_set_dusk(false)


func _process(_delta: float) -> void:
	var boom := player.boom_current()
	var squeezed := boom < player.boom_length - 0.2
	_boom.text = "Camera boom %.1f / %.1f m%s" % [boom, player.boom_length, "  SQUEEZED" if squeezed else ""]
	_boom.modulate = Color("f2a93b") if squeezed else Color.WHITE

	var target := _nearby_repair()
	_prompt.visible = target != ""
	if target != "":
		_prompt.text = "[E] Install %s" % Kestrel.REPAIR_NAMES[target].to_lower()
		if Input.is_action_just_pressed("interact"):
			kestrel.set_repaired(target, true)
	if player.global_position.y < -20.0:
		_respawn()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	if key >= KEY_1 and key <= KEY_7:
		kestrel.toggle_repair(Kestrel.REPAIR_ORDER[key - KEY_1])
	elif key == KEY_N:
		_set_dusk(not dusk)
	elif key == KEY_R:
		_respawn()


func _nearby_repair() -> String:
	for id in kestrel.interact_points:
		if kestrel.is_repaired(id):
			continue
		var point := kestrel.to_global(kestrel.interact_points[id])
		if player.global_position.distance_to(point) < INTERACT_RANGE:
			return id
	return ""


func _respawn() -> void:
	player.velocity = Vector3.ZERO
	player.global_position = SPAWN
	player.face(0.0)


func _on_repair_changed(_id: String, _repaired: bool) -> void:
	_refresh_status()


func _refresh_status() -> void:
	var lines: PackedStringArray = []
	for i in Kestrel.REPAIR_ORDER.size():
		var id := Kestrel.REPAIR_ORDER[i]
		lines.append("%d  %s  %s" % [i + 1, "■" if kestrel.is_repaired(id) else "□", Kestrel.REPAIR_NAMES[id]])
	_status.text = "\n".join(lines)


func _setup_input() -> void:
	for action in INPUTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in INPUTS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _build_environment() -> void:
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.fog_enabled = true
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 150.0
	add_child(_sun)


## Day keeps the basalt readable (bright sky, low sun). Dusk shows the amber interior as home.
func _set_dusk(value: bool) -> void:
	dusk = value
	if dusk:
		_sky.sky_top_color = Color("1d2733")
		_sky.sky_horizon_color = Color("5b4a52")
		_sky.ground_horizon_color = Color("2a2a30")
		_sky.ground_bottom_color = Color("0e1012")
		_sun.rotation_degrees = Vector3(-8.0, 60.0, 0.0)
		_sun.light_color = Color("ff9a6a")
		_sun.light_energy = 0.25
		_env.ambient_light_energy = 0.3
		_env.fog_light_color = Color("3a3540")
		_env.fog_density = 0.004
	else:
		_sky.sky_top_color = Color("7d8a8f")
		_sky.sky_horizon_color = Color("b7bfbd")
		_sky.ground_horizon_color = Color("3c4448")
		_sky.ground_bottom_color = Color("1b1d1f")
		_sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
		_sun.light_color = Color("fff3e0")
		_sun.light_energy = 1.0
		_env.ambient_light_energy = 0.4
		_env.fog_light_color = Color("8f9a9c")
		_env.fog_density = 0.002
	site.set_dusk(dusk)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var controls := _label(hud, 14)
	controls.text = CONTROLS_TEXT
	controls.position = Vector2(16, 12)
	_status = _label(hud, 15)
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = 16
	_status.offset_top = -170
	_boom = _label(hud, 15)
	_boom.anchor_left = 1.0
	_boom.anchor_right = 1.0
	_boom.offset_left = -360
	_boom.offset_right = -16
	_boom.offset_top = 12
	_boom.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt = _label(hud, 22)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = -120
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false


func _label(parent: Node, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
	return label
