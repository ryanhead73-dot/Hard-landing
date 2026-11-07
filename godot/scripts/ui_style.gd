class_name UiStyle
extends RefCounted
## Hard Landing's type and colour, in one place. One family: Barlow for reading (subtitles,
## messages, menus) and Barlow Condensed for display and readouts (title cards, ammo, objectives).
## Both are SIL Open Font License (fonts/OFL.txt, ASSETS.md). Sizes are in the 1600x900 base
## viewport; the canvas_items stretch scales them for 1080p and 1440p.

const BODY: FontFile = preload("res://fonts/Barlow-Medium.ttf")
const BODY_STRONG: FontFile = preload("res://fonts/Barlow-SemiBold.ttf")
const DISPLAY: FontFile = preload("res://fonts/BarlowCondensed-SemiBold.ttf")
const DISPLAY_BOLD: FontFile = preload("res://fonts/BarlowCondensed-Bold.ttf")

## The type scale: role -> [font, size].
const ROLES := {
	"title": ["display_bold", 84],
	"banner": ["display_bold", 42],
	"readout": ["display_bold", 36],
	"heading": ["display", 25],
	"lead": ["body", 24],
	"prompt": ["body_strong", 22],
	"body": ["body", 20],
	"label": ["body_strong", 17],
	"small": ["body_strong", 15],
}

const CREAM := Color("e9e1cc")
const AMBER := Color("ffd08a")
const ORANGE := Color("ffb24d")
const TEAL := Color("9fe8d8")
const DIM := Color("a8a294")
const OUTLINE := Color(0.02, 0.03, 0.04, 0.85)

static var _fonts: Dictionary = {}
static var _theme: Theme


## The font for a role. Display caps get a little tracking.
static func font(role: String) -> Font:
	var key: String = ROLES.get(role, ROLES["body"])[0]
	if _fonts.has(key):
		return _fonts[key]
	var f: Font
	match key:
		"display_bold", "display":
			var v := FontVariation.new()
			v.base_font = DISPLAY_BOLD if key == "display_bold" else DISPLAY
			v.spacing_glyph = 1
			f = v
		"body_strong":
			f = BODY_STRONG
		_:
			f = BODY
	_fonts[key] = f
	return f


static func size(role: String) -> int:
	return ROLES.get(role, ROLES["body"])[1]


## Styles a Label (or anything with font and font_size theme items) for a role, with an outline
## and a soft shadow so it reads over bright sky, steam and the cream hull alike.
static func apply(control: Control, role: String, color := CREAM) -> void:
	control.add_theme_font_override("font", font(role))
	control.add_theme_font_size_override("font_size", size(role))
	control.add_theme_color_override("font_color", color)
	control.add_theme_constant_override("outline_size", 4 if size(role) < 30 else 6)
	control.add_theme_color_override("font_outline_color", OUTLINE)
	control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	control.add_theme_constant_override("shadow_offset_x", 1)
	control.add_theme_constant_override("shadow_offset_y", 2)


## The game-wide theme: Barlow everywhere by default, cream text, display-face buttons. It is
## saved as ui/theme.tres (the project's custom theme, gui/theme/custom); after changing it here,
## regenerate with ResourceSaver.save(UiStyle.theme(), "res://ui/theme.tres"). visuals_test
## checks the two agree.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = BODY
	t.default_font_size = size("body")
	for type in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit", "RichTextLabel", "PopupMenu", "TooltipLabel"]:
		t.set_color("font_color" if type != "RichTextLabel" else "default_color", type, CREAM)
	t.set_font("bold_font", "RichTextLabel", BODY_STRONG)
	t.set_font("font", "Button", font("heading"))
	t.set_font_size("font_size", "Button", 22)
	t.set_font("font", "OptionButton", BODY_STRONG)
	t.set_color("font_hover_color", "Button", AMBER)
	t.set_color("font_focus_color", "Button", AMBER)
	t.set_color("font_pressed_color", "Button", ORANGE)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.06, 0.07, 0.985)
	panel.border_color = Color(ORANGE, 0.8)
	panel.border_width_top = 3
	panel.set_corner_radius_all(3)
	panel.set_content_margin_all(28)
	t.set_stylebox("panel", "PanelContainer", panel)
	_theme = t
	return t
