class_name CreditsPanel
extends CanvasLayer
## Credits and licences, opened from the title screen. Who made what, the third-party typeface
## and engine with their licences, and the full licence texts the engine and fonts ask to travel
## with the game (Godot's MIT notice and its bundled components, the Barlow OFL).

signal closed

const LEDGER := "res://data/asset_ledger.json"
const OFL := "res://fonts/OFL.txt"

var text: RichTextLabel
var _back: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 760)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := Label.new()
	title.text = "CREDITS"
	UiStyle.apply(title, "banner")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	text = RichTextLabel.new()
	text.name = "CreditsText"
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.focus_mode = Control.FOCUS_ALL
	text.selection_enabled = false
	text.add_theme_font_size_override("normal_font_size", 18)
	text.add_theme_font_size_override("bold_font_size", 20)
	text.add_theme_font_override("mono_font", UiStyle.BODY)
	text.add_theme_font_size_override("mono_font_size", 14)
	text.text = body()
	box.add_child(text)
	var hint := Label.new()
	hint.text = "Scroll with the wheel, arrows or d-pad"
	UiStyle.apply(hint, "small", UiStyle.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(220, 44)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(close)
	box.add_child(_back)
	visible = false


func _process(_delta: float) -> void:
	if visible:
		UiStyle.keep_pad_focus(self, text)


func open() -> void:
	text.scroll_to_line(0)
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or Game.is_pad_back(event)):
		close()
		get_viewport().set_input_as_handled()


## The credits as BBCode. The third-party lines come from the asset ledger, so a new licensed
## asset shows up here once it has a source row.
static func body() -> String:
	var lines: Array[String] = []
	lines.append("[center][b]HARD LANDING[/b]")
	lines.append("Made by the Hard Landing team")
	lines.append("")
	lines.append("Code, models, animation, music and sound are original to this project.[/center]")
	lines.append("")
	lines.append("[b]THIRD-PARTY[/b]")
	for s in third_party():
		lines.append("%s  ·  %s" % [s.get("credit", s["origin"]), s["author"]])
		lines.append("[color=#a8a294]%s[/color]" % s["licence"])
	lines.append("")
	lines.append("[b]GODOT ENGINE[/b]")
	lines.append("[code]%s[/code]" % _escape(Engine.get_license_text()))
	lines.append("")
	lines.append("[b]ENGINE COMPONENTS[/b]")
	for c in Engine.get_copyright_info():
		var holders: Array[String] = []
		var licences: Array[String] = []
		for part in c["parts"]:
			for h in part["copyright"]:
				if h not in holders:
					holders.append(h)
			if part["license"] not in licences:
				licences.append(part["license"])
		lines.append("%s  ·  %s  [color=#a8a294](%s)[/color]" % [c["name"], ", ".join(holders), ", ".join(licences)])
	lines.append("")
	lines.append("[b]SIL OPEN FONT LICENSE (Barlow)[/b]")
	lines.append("[code]%s[/code]" % _escape(FileAccess.get_file_as_string(OFL)))
	var info := Engine.get_license_info()
	for name in info:
		lines.append("")
		lines.append("[b]%s[/b]" % _escape(name))
		lines.append("[code]%s[/code]" % _escape(info[name]))
	return "\n".join(lines)


## Ledger sources that are not the project's own work.
static func third_party() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(LEDGER))
	var out := []
	if data is Dictionary:
		for id in data.get("sources", {}):
			var s: Dictionary = data["sources"][id]
			if s.get("licence", "") != "Project original":
				out.append(s)
	return out


static func _escape(t: String) -> String:
	return t.replace("[", "[lb]")
