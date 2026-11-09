class_name Hud
extends CanvasLayer
## On-screen readouts for the slice: objective and waypoint, crosshair, ammo, health, scrap,
## interaction prompt, messages, damage feedback and a dev panel (F1).

## The keyboard controls line, from the player's current key bindings.
static func help_text() -> String:
	var k := func(a: String) -> String: return Game.key_label(a)
	return "%s%s%s%s move · Mouse look · RMB aim · LMB fire · %s reload · %s/%s/%s, wheel weapons · %s stim · %s arc charge · %s inventory · %s map · %s logs · %s sprint · %s jump · %s roll · %s crouch · %s interact · %s flashlight" % [
		k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right"), k.call("reload"),
		k.call("weapon_1"), k.call("weapon_2"), k.call("weapon_3"), k.call("stim"), k.call("throw"), k.call("inventory"),
		k.call("map"), k.call("logs"), k.call("sprint"), k.call("jump"), k.call("dodge"), k.call("crouch"),
		k.call("interact"), k.call("flashlight")]

var _objective: Label
var _hidden_for_cinematic: Array = []
var _waypoint: Label
var _crosshair: Control
var _ammo: Label
var _health_fill: ColorRect
var _health_back: ColorRect
var _health_text: Label
var _scrap: Label
var _prompt: Label
var _message: Label
var _vignette: ColorRect
var _death: Label
var _dev: Label
var _repairs: Label
var _scan: Control
var _ending: ColorRect
var _scan_marks: Array = []
var _weapon: Label
var _stims: Label
var _charges: Label
var _bar_back: ColorRect
var _bar_fill: ColorRect
var _bar_label: Label
var _boss: Enemy
var _hull_ratio := -1.0
var _help: Label
var _help_time := 150.0
const PAD_HELP_TEXT := "L stick move · R stick look · LT aim · RT fire · X reload · D-pad right weapons · LB stim · RB arc charge · View inventory · D-pad down map · D-pad left logs · L3 sprint · A jump · B roll · R3 crouch · Y interact · D-pad up flashlight · Start pause"
## Last values given, so the key names can be redrawn when the player switches device.
var _prompt_raw := ""
## First-time hint (Onboarding): one line, lower left above the suit readout.
var _hint: Label
var _stims_last := Vector2i.ZERO
var _charges_last := Vector2i.ZERO
var _compass: Control
const COMPASS_HALF_WIDTH := 260.0
## Degrees either side of the heading that the compass strip shows.
const COMPASS_SPAN := 75.0
var _voice: RichTextLabel
var _ending_text: Label
var _log_toast: Label
var _log_toast_time := 0.0

var _task_back: ColorRect
var _task_fill: ColorRect
var _task_label: Label
var _banner: Label
var _banner_sub: Label
var _banner_time := 0.0

var _hit_time := 0.0
var _hit_killed := false
var _hit_crit := false
var _hit_armor := false
## Glancing-hit markers shown (tests).
var armor_shown := 0
var crits_shown := 0
## Recent hits on Juno: [world position of the source, seconds left], drawn as red arcs.
var _hurt_marks: Array = []
var _message_time := 0.0
var _waypoint_target = null


func _ready() -> void:
	# Controls reminder, bottom centre and quiet; it fades after the first couple of minutes.
	_help = _label("small")
	_anchor(_help, 0.5, 1.0, -640, -26, 640, -8)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.text = help_text()
	Game.keys_changed.connect(func(): _help.text = PAD_HELP_TEXT if Game.using_pad else help_text())
	# The full list lives in the pause menu; play teaches through one-at-a-time hints instead.
	_help.visible = false
	_help_time = 0.0
	_hint = _label("label", UiStyle.AMBER)
	_anchor(_hint, 0.0, 1.0, 16, -170, 900, -140)
	_hint.visible = false
	Game.input_device_changed.connect(_on_device_changed)
	_help.modulate = Color(1, 1, 1, 0.6)

	# Compass strip across the top: headings, and the waypoint as an amber diamond.
	_compass = Control.new()
	_anchor(_compass, 0.5, 0.0, -COMPASS_HALF_WIDTH, 6, COMPASS_HALF_WIDTH, 30)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.draw.connect(_draw_compass)
	add_child(_compass)

	_objective = _label("heading", UiStyle.AMBER)
	_anchor(_objective, 0.5, 0.0, -560, 32, 560, 64)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_repairs = _label("small")
	_anchor(_repairs, 0.5, 0.0, -400, 64, 400, 84)
	_repairs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_repairs.modulate = Color(1, 1, 1, 0.7)
	Game.repairs_changed.connect(_update_repairs)
	_update_repairs()

	_scan = Control.new()
	_scan.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan.draw.connect(_draw_scan)
	add_child(_scan)

	_waypoint = _label("small", UiStyle.ORANGE)

	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	add_child(_crosshair)

	_health_back = ColorRect.new()
	_health_back.color = Color(0, 0, 0, 0.55)
	_anchor(_health_back, 0.0, 1.0, 16, -46, 276, -30)
	add_child(_health_back)
	_health_fill = ColorRect.new()
	_health_fill.color = Color("e9e1cc")
	_health_fill.position = Vector2(2, 2)
	_health_fill.size = Vector2(256, 12)
	_health_back.add_child(_health_fill)
	_health_text = _label("small")
	_anchor(_health_text, 0.0, 1.0, 16, -72, 300, -50)

	_scrap = _label("label")
	_anchor(_scrap, 1.0, 1.0, -300, -96, -20, -70)
	_scrap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo = _label("readout")
	_anchor(_ammo, 1.0, 1.0, -300, -70, -20, -22)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon = _label("small")
	_anchor(_weapon, 1.0, 1.0, -400, -124, -20, -100)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon.modulate = Color(1, 1, 1, 0.8)
	_stims = _label("small")
	_anchor(_stims, 0.0, 1.0, 16, -98, 300, -76)
	_charges = _label("small")
	_anchor(_charges, 0.0, 1.0, 16, -122, 300, -100)

	# Shared top bar: the Warden's health, or Kestrel's hull during a siege.
	_bar_back = ColorRect.new()
	_bar_back.color = Color(0, 0, 0, 0.6)
	_anchor(_bar_back, 0.5, 0.0, -300, 150, 300, 164)
	_bar_back.visible = false
	add_child(_bar_back)
	_bar_fill = ColorRect.new()
	_bar_fill.position = Vector2(2, 2)
	_bar_fill.size = Vector2(596, 10)
	_bar_back.add_child(_bar_fill)
	_bar_label = _label("label")
	_anchor(_bar_label, 0.5, 0.0, -300, 126, 300, 148)
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.visible = false

	# Task bar: a hold in progress, or a machine working during a defend.
	_task_back = ColorRect.new()
	_task_back.color = Color(0, 0, 0, 0.6)
	_anchor(_task_back, 0.5, 1.0, -170, -186, 170, -178)
	_task_back.visible = false
	add_child(_task_back)
	_task_fill = ColorRect.new()
	_task_fill.color = Color("ffb24d")
	_task_fill.position = Vector2(1, 1)
	_task_fill.size = Vector2(0, 6)
	_task_back.add_child(_task_fill)
	_task_label = _label("label", UiStyle.AMBER)
	_anchor(_task_label, 0.5, 1.0, -300, -208, 300, -188)
	_task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_task_label.visible = false

	# Stage banner: a short title card when a mission stage completes.
	_banner = _label("banner", UiStyle.AMBER)
	_anchor(_banner, 0.5, 0.0, -600, 180, 600, 230)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	_banner_sub = _label("body")
	_anchor(_banner_sub, 0.5, 0.0, -600, 230, 600, 258)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.visible = false

	_prompt = _label("prompt")
	_anchor(_prompt, 0.5, 1.0, -400, -150, 400, -118)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Subtitles for HOB and Juno, low and centred, under the action.
	_voice = RichTextLabel.new()
	_voice.bbcode_enabled = true
	_voice.fit_content = true
	_voice.scroll_active = false
	_voice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voice.add_theme_font_override("normal_font", UiStyle.font("body"))
	_voice.add_theme_font_override("bold_font", UiStyle.font("heading"))
	_voice.add_theme_font_size_override("normal_font_size", UiStyle.size("body") + 1)
	_voice.add_theme_font_size_override("bold_font_size", UiStyle.size("body") + 3)
	_voice.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_voice.add_theme_constant_override("shadow_offset_x", 1)
	_voice.add_theme_constant_override("shadow_offset_y", 1)
	_size_subtitles()
	Game.settings_changed.connect(func():
		_size_subtitles()
		if Game.subtitles == 0:
			_voice.visible = false)
	# An outline keeps them legible over bright sky, steam and the cream hull alike.
	_voice.add_theme_constant_override("outline_size", 6)
	_voice.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 0.85))
	# Low, below Juno's waist and the interaction prompt, as in film subtitles.
	_anchor(_voice, 0.5, 1.0, -480, -112, 480, -34)
	_voice.visible = false
	add_child(_voice)

	_log_toast = _label("label", UiStyle.TEAL)
	_anchor(_log_toast, 0.0, 0.5, 16, 40, 520, 90)
	_log_toast.visible = false

	_message = _label("body")
	_anchor(_message, 0.5, 0.0, -560, 88, 560, 140)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.6, 0.05, 0.02, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)

	_death = _label("banner")
	_anchor(_death, 0.5, 0.5, -400, -30, 400, 30)
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.text = "You went down. Hauling back to Kestrel..."
	_death.visible = false

	_dev = _label("small")
	_anchor(_dev, 1.0, 0.0, -360, 34, -16, 300)
	_dev.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dev.visible = false

	_ending = ColorRect.new()
	_ending.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ending.color = Color(0.02, 0.03, 0.04, 0.0)
	_ending.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ending.visible = false
	add_child(_ending)
	_ending_text = _label("lead")
	_ending_text.reparent(_ending)
	_ending_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ending_text.offset_left = 160
	_ending_text.offset_right = -160
	_ending_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ending_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ending_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _process(delta: float) -> void:
	_hit_time = maxf(_hit_time - delta, 0.0)
	for m in _hurt_marks:
		m[1] -= delta
	_hurt_marks = _hurt_marks.filter(func(m): return m[1] > 0.0)
	_crosshair.queue_redraw()
	if _vignette.color.a > 0.0:
		_vignette.color.a = maxf(_vignette.color.a - delta * 0.8, 0.0)
	if _log_toast_time > 0.0:
		_log_toast_time -= delta
		_log_toast.modulate.a = clampf(_log_toast_time, 0.0, 1.0)
		_log_toast.visible = _log_toast_time > 0.0
	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time, 0.0, 1.0)
	_update_waypoint()
	_compass.queue_redraw()
	if _help_time > 0.0:
		_help_time -= delta
		_help.modulate.a = clampf(_help_time / 10.0, 0.0, 0.6)
	_scan.queue_redraw()
	_update_bar()
	if _banner_time > 0.0:
		_banner_time -= delta
		var a := clampf(_banner_time, 0.0, 1.0)
		_banner.modulate.a = a
		_banner_sub.modulate.a = a
		_banner.visible = _banner_time > 0.0
		_banner_sub.visible = _banner.visible


## Progress of a hold or a working machine, 0..1, with its caption; a negative ratio hides it.
func set_task(ratio: float, label := "") -> void:
	var show := ratio >= 0.0
	_task_back.visible = show
	_task_label.visible = show
	if show:
		_task_fill.size.x = 338.0 * clampf(ratio, 0.0, 1.0)
		_task_label.text = label


func task_visible() -> bool:
	return _task_back.visible


## A title card across the upper screen for a few seconds.
func show_banner(title: String, sub := "") -> void:
	_banner.text = title
	_banner_sub.text = sub
	_banner_time = 3.5
	_banner.visible = true
	_banner_sub.visible = true


func banner_text() -> String:
	return _banner.text if _banner.visible else ""


func set_objective(text: String) -> void:
	_objective.text = "◆ " + text


## Shows a marker over a world position (Vector3), or hides it when given null.
func set_waypoint(target) -> void:
	_waypoint_target = target


func show_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = text != ""


func hint_text() -> String:
	return _hint.text if _hint.visible else ""


func set_prompt(text: String) -> void:
	_prompt_raw = text
	_prompt.text = Game.device_text(text)
	_prompt.visible = text != ""


func show_message(text: String) -> void:
	_message.text = text
	_message_time = 5.0
	_message.modulate.a = 1.0


func set_ammo(in_mag: int, mag_size: int, reloading: bool) -> void:
	if reloading:
		_ammo.text = "RELOADING"
	elif in_mag == 0:
		_ammo.text = "RELOAD  [%s]" % Game.key_name("reload")
	else:
		_ammo.text = "%d / %d" % [in_mag, mag_size]
	# Amber once a quarter of the magazine (or less) is left, so the reload never surprises.
	var low := in_mag <= maxi(2, mag_size / 4)
	_ammo.add_theme_color_override("font_color", UiStyle.ORANGE if reloading or low else UiStyle.CREAM)


func set_health(health: float, max_health: float) -> void:
	var ratio := clampf(health / max_health, 0.0, 1.0)
	_health_back.size.x = 4.0 + 256.0 * max_health / 100.0
	_health_fill.size.x = 256.0 * max_health / 100.0 * ratio
	_health_fill.color = Color("e9e1cc") if ratio > 0.35 else Color("e0603a")
	_health_text.text = "SUIT %d / %d" % [roundi(health), roundi(max_health)]


func set_weapon_info(weapon_name: String, reserve: int) -> void:
	_weapon.text = "%s  ·  %s" % [weapon_name.to_upper(), "∞" if reserve < 0 else "%d reserve" % reserve]


func set_charges(count: int, max_count: int) -> void:
	_charges_last = Vector2i(count, max_count)
	_charges.text = "CHARGES %d / %d  [%s]" % [count, max_count, Game.key_name("throw")]
	_charges.modulate = Color(0.75, 1, 0.95, 0.85 if count > 0 else 0.4)


func set_stims(count: int, max_count: int) -> void:
	_stims_last = Vector2i(count, max_count)
	_stims.text = "STIMS %d / %d  [%s]" % [count, max_count, Game.key_name("stim")]
	_stims.modulate = Color(1, 1, 1, 0.85 if count > 0 else 0.4)


## Seconds since the last message appeared (5 means it has faded).
func message_age() -> float:
	return 5.0 - _message_time


func set_scrap(amount: int) -> void:
	_scrap.text = "SCRAP %d" % amount


func flash_damage() -> void:
	_vignette.color.a = 0.35


## Shows which way a hit came from: a red arc round the crosshair, facing the source.
func damage_from(source: Vector3) -> void:
	_hurt_marks.append([source, 1.3])
	if _hurt_marks.size() > 4:
		_hurt_marks.pop_front()


func hurt_mark_count() -> int:
	return _hurt_marks.size()


func hitmarker(killed: bool) -> void:
	_hit_time = 0.22 if killed else 0.15
	_hit_killed = killed
	_hit_crit = false
	_hit_armor = false


## The hit marker for a weak-spot hit: bigger, amber, and it lingers a touch.
func crit_marker() -> void:
	_hit_time = 0.22
	_hit_crit = true
	crits_shown += 1


## The hit marker for a shot that glanced off armour: short, grey ticks over a flat bar, so it
## reads as "that did little" next to the white hit and the amber crit.
func armor_marker() -> void:
	_hit_time = 0.18
	_hit_armor = true
	armor_shown += 1


## Scanner contacts to draw: [{pos: Vector3, kind: "crate" | "enemy"}].
## The planted field beacon (Vector3) in this region, or null; shown on the compass.
var beacon_target = null


func set_scan(marks: Array) -> void:
	_scan_marks = marks


## Shows a boss health bar until it dies.
func show_boss(boss: Enemy) -> void:
	_boss = boss


## Kestrel's hull during a siege, 0..1, or a negative value to hide it.
func set_hull(ratio: float, wave_text := "") -> void:
	_hull_ratio = ratio
	_bar_label.text = "KESTREL HULL   ·   %s" % wave_text if ratio >= 0.0 else ""


func bar_visible() -> bool:
	return _bar_back.visible


func _update_bar() -> void:
	var ratio := -1.0
	var color := Color("e9e1cc")
	if _boss and is_instance_valid(_boss) and not _boss.dead:
		ratio = _boss.health / _boss.max_health
		color = Color("3fd1b5") if _boss is Warden else Color("ff7a3a")
		_bar_label.text = _boss.display_name()
	elif _hull_ratio >= 0.0:
		ratio = _hull_ratio
		color = Color("e9e1cc") if ratio > 0.35 else Color("e0603a")
	_bar_back.visible = ratio >= 0.0
	_bar_label.visible = ratio >= 0.0
	if ratio >= 0.0:
		_bar_fill.size.x = 596.0 * clampf(ratio, 0.0, 1.0)
		_bar_fill.color = color


## The closing card: fades to black, then the given text. Empty text just fades.
func show_ending(text := "") -> void:
	_ending.visible = true
	_ending_text.text = text
	_ending_text.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_ending, "color:a", 1.0, 2.5)
	tween.tween_property(_ending_text, "modulate:a", 1.0, 1.5)


## Cutscene mode for the launch: everything but the subtitles and the ending card steps aside.
func enter_cinematic() -> void:
	_hidden_for_cinematic.clear()
	for c in get_children():
		if c is CanvasItem and c != _voice and c != _ending and (c as CanvasItem).visible:
			(c as CanvasItem).visible = false
			_hidden_for_cinematic.append(c)
	set_process(false)


## Brings back what enter_cinematic() hid (after the intro).
func exit_cinematic() -> void:
	for c in _hidden_for_cinematic:
		if is_instance_valid(c):
			(c as CanvasItem).visible = true
	_hidden_for_cinematic.clear()
	set_process(true)


func ending_text() -> String:
	return _ending_text.text


## Subtitle name colours. The name is always printed, so the colour is a help, never the only cue.
const SPEAKER_COLOURS := {
	Story.HOB: "9fe8d8",
	Story.JUNO: "ffd08a",
	Story.REYES: "c9b8ff",
}


func set_voice(speaker: String, text: String) -> void:
	_voice.visible = text != "" and Game.subtitles > 0
	if text == "":
		_voice.text = ""
		return
	var colour: String = SPEAKER_COLOURS.get(speaker, "e9e1cc")
	_voice.text = "[center][b][color=#%s]%s[/color][/b]   %s[/center]" % [colour, speaker.to_upper(), text]


## Subtitle size from the accessibility setting.
func _size_subtitles() -> void:
	var k: float = Game.SUBTITLE_SCALE[Game.subtitles]
	_voice.add_theme_font_size_override("normal_font_size", roundi((UiStyle.size("body") + 1) * k))
	_voice.add_theme_font_size_override("bold_font_size", roundi((UiStyle.size("body") + 3) * k))


func voice_text() -> String:
	return _voice.get_parsed_text() if _voice.visible else ""


func show_log_toast(title: String) -> void:
	_log_toast.text = "◈ Log recovered: %s   [%s] read" % [title, Game.key_name("logs")]
	_log_toast_time = 6.0
	_log_toast.visible = true
	_log_toast.modulate.a = 1.0


func ending_visible() -> bool:
	return _ending.visible


func _update_repairs() -> void:
	_repairs.text = "KESTREL  %d / %d systems restored" % [Game.repairs_done(), Campaign.REPAIRS.size()]


func _draw_scan() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for m in _scan_marks:
		var pos: Vector3 = m["pos"] + Vector3.UP * 1.0
		if cam.is_position_behind(pos):
			continue
		var p := cam.unproject_position(pos)
		if m["kind"] == "beacon":
			var bc := Color(FieldBeacon.COLOR, 0.9)
			_scan.draw_line(p + Vector2(0, -10), p + Vector2(0, 8), bc, 2.0)
			_scan.draw_circle(p + Vector2(0, -12), 3.5, bc)
			var dist := cam.global_position.distance_to(m["pos"])
			_scan.draw_string(UiStyle.font("heading"), p + Vector2(7, -6), "%d m" % roundi(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, bc)
		elif m["kind"] == "crate":
			var col := Color(1.0, 0.7, 0.3, 0.8)
			_scan.draw_polyline(PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0), p + Vector2(0, -6)]), col, 1.5)
		else:
			_scan.draw_arc(p, 6.0, 0.0, TAU, 12, Color(0.25, 0.82, 0.71, 0.8), 1.5)


func set_dead(dead: bool) -> void:
	_death.visible = dead


func set_dev(visible_now: bool, text: String) -> void:
	_dev.visible = visible_now
	_dev.text = text


func _update_waypoint() -> void:
	var cam := get_viewport().get_camera_3d()
	if _waypoint_target == null or cam == null:
		_waypoint.visible = false
		return
	var target: Vector3 = _waypoint_target
	var screen := get_viewport().get_visible_rect().size
	var dist := cam.global_position.distance_to(target)
	var pos: Vector2
	if cam.is_position_behind(target):
		var flat := cam.global_basis.inverse() * (target - cam.global_position)
		pos = Vector2(0.0 if flat.x < 0.0 else screen.x, screen.y * 0.5)
	else:
		pos = cam.unproject_position(target + Vector3.UP * 2.0)
	pos = pos.clamp(Vector2(40, 90), screen - Vector2(140, 160))
	_waypoint.text = "◆ %d m" % roundi(dist)
	_waypoint.position = pos - Vector2(20, 10)
	_waypoint.visible = dist > 6.0


## The camera's heading in degrees: 0 is north (-Z), 90 east (+X).
func compass_heading() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var f := -cam.global_basis.z
	return fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)


func _draw_compass() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var heading := compass_heading()
	var w := COMPASS_HALF_WIDTH
	_compass.draw_rect(Rect2(0, 0, w * 2.0, 24), Color(0.04, 0.05, 0.06, 0.45))
	_compass.draw_line(Vector2(w, 0), Vector2(w, 24), Color("ffd08a", 0.9), 1.5)
	var font := UiStyle.font("heading")
	for deg in range(0, 360, 15):
		var off := wrapf(deg - heading, -180.0, 180.0)
		if absf(off) > COMPASS_SPAN:
			continue
		var x := w + off / COMPASS_SPAN * w
		var fade := 1.0 - absf(off) / COMPASS_SPAN
		if deg % 90 == 0:
			var letter: String = ["N", "E", "S", "W"][deg / 90]
			var lw := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			_compass.draw_string(font, Vector2(x - lw * 0.5, 20), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(UiStyle.CREAM, fade))
		else:
			_compass.draw_line(Vector2(x, 14 if deg % 45 else 10), Vector2(x, 22), Color("e9e1cc", 0.6 * fade), 1.0)
	if beacon_target is Vector3:
		var bd: Vector3 = beacon_target - cam.global_position
		var bb := fposmod(rad_to_deg(atan2(bd.x, -bd.z)), 360.0)
		var boff := clampf(wrapf(bb - heading, -180.0, 180.0), -COMPASS_SPAN, COMPASS_SPAN)
		var bx := w + boff / COMPASS_SPAN * w
		_compass.draw_line(Vector2(bx, 3), Vector2(bx, 14), FieldBeacon.COLOR, 2.0)
		_compass.draw_circle(Vector2(bx, 3), 2.5, FieldBeacon.COLOR)
	if _waypoint_target is Vector3:
		var d: Vector3 = _waypoint_target - cam.global_position
		var bearing := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
		var off := clampf(wrapf(bearing - heading, -180.0, 180.0), -COMPASS_SPAN, COMPASS_SPAN)
		var x := w + off / COMPASS_SPAN * w
		var c := Color("ffb24d")
		_compass.draw_colored_polygon(PackedVector2Array([Vector2(x, 2), Vector2(x + 5, 7), Vector2(x, 12), Vector2(x - 5, 7)]), c)


## How far the crosshair ticks spread for the weapon's current accuracy, in pixels: the cone a
## shot can land in, as seen through the camera.
func crosshair_spread_px(cam: Camera3D) -> float:
	var p := get_tree().get_first_node_in_group("player") as Player
	if p == null or cam == null or p.weapon == null:
		return 0.0
	var half := deg_to_rad(cam.fov) * 0.5
	return minf(tan(p.weapon.current_spread(p.aiming)) / tan(half) * _crosshair.size.y * 0.5, 60.0)


func _draw_crosshair() -> void:
	var c := _crosshair.size * 0.5
	var col := Color(1, 1, 1, 0.85)
	var cam := get_viewport().get_camera_3d()
	var gap := 6.0 + crosshair_spread_px(cam)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_crosshair.draw_line(c + d * gap, c + d * (gap + 7.0), col, 2.0)
	if cam:
		var heading := deg_to_rad(compass_heading())
		for m in _hurt_marks:
			var d: Vector3 = m[0] - cam.global_position
			if Vector2(d.x, d.z).length() < 0.5:
				continue
			var off := wrapf(atan2(d.x, -d.z) - heading, -PI, PI)
			var a := -PI * 0.5 + off
			var alpha := clampf(m[1], 0.0, 1.0)
			_crosshair.draw_arc(c, 96.0, a - 0.32, a + 0.32, 14, Color(1.0, 0.22, 0.12, 0.75 * alpha), 5.0, true)
	if _hit_time > 0.0 and _hit_armor:
		var grey := Color(0.68, 0.74, 0.8, clampf(_hit_time / 0.18, 0.0, 1.0) * 0.5 + 0.5)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_crosshair.draw_line(c + d * 8.0, c + d * 11.0, grey, 2.0)
		_crosshair.draw_line(c + Vector2(-9.0, 16.0), c + Vector2(9.0, 16.0), grey, 2.0)
	elif _hit_time > 0.0:
		var hit_col := Color("ff5a3a") if _hit_killed else (Color("ffc84a") if _hit_crit else Color.WHITE)
		# A kill is told apart by shape as well as colour (long, heavy strokes with a dark edge),
		# so it reads for colour-blind players too.
		var reach := 22.0 if _hit_killed else (19.0 if _hit_crit else 15.0)
		var width := 4.0 if _hit_killed else (3.0 if _hit_crit else 2.5)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			if _hit_killed:
				_crosshair.draw_line(c + d * 7.0, c + d * (reach + 1.0), Color(0, 0, 0, 0.55), width + 2.5)
			_crosshair.draw_line(c + d * 8.0, c + d * reach, hit_col, width)
		if _hit_crit:
			_crosshair.draw_arc(c, 24.0, 0.0, TAU, 24, Color(1.0, 0.78, 0.29, _hit_time / 0.22 * 0.8), 2.0, true)


## A HUD label in one of UiStyle's type roles.
func _label(role: String, color := UiStyle.CREAM) -> Label:
	var label := Label.new()
	UiStyle.apply(label, role, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _anchor(control: Control, ax: float, ay: float, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = ax
	control.anchor_right = ax
	control.anchor_top = ay
	control.anchor_bottom = ay
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom


func _on_device_changed(pad: bool) -> void:
	_help.text = PAD_HELP_TEXT if pad else help_text()
	set_prompt(_prompt_raw)
	set_stims(_stims_last.x, _stims_last.y)
	set_charges(_charges_last.x, _charges_last.y)
