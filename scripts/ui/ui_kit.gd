class_name UiKit
extends RefCounted
## Shared look for the menus: a theme for buttons and inputs, and small
## builders for panels and labels.

const ACCENT := Color(1.0, 0.72, 0.15)
const PANEL_BG := Color(0.04, 0.05, 0.07, 0.86)
const TEXT := Color(0.94, 0.95, 0.97)
const MUTED := Color(0.7, 0.73, 0.78)

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	_theme.default_font_size = 20
	var normal := _box(Color(0.1, 0.12, 0.16, 0.92), Color(1, 1, 1, 0.08))
	var hover := _box(Color(0.16, 0.18, 0.24, 0.95), Color(ACCENT, 0.7))
	var pressed := _box(Color(ACCENT, 0.9), ACCENT)
	var focus := _box(Color(0, 0, 0, 0), ACCENT, 2)
	for type in ["Button", "OptionButton"]:
		_theme.set_stylebox("normal", type, normal)
		_theme.set_stylebox("hover", type, hover)
		_theme.set_stylebox("pressed", type, pressed)
		_theme.set_stylebox("focus", type, focus)
		_theme.set_stylebox("disabled", type, normal)
		_theme.set_color("font_color", type, TEXT)
		_theme.set_color("font_hover_color", type, Color.WHITE)
		_theme.set_color("font_pressed_color", type, Color(0.05, 0.05, 0.05))
		_theme.set_color("font_focus_color", type, Color.WHITE)
	_theme.set_stylebox("normal", "LineEdit", normal)
	_theme.set_stylebox("focus", "LineEdit", _box(Color(0.1, 0.12, 0.16, 0.92), ACCENT, 2))
	_theme.set_color("font_color", "LineEdit", TEXT)
	_theme.set_color("font_color", "Label", TEXT)
	_theme.set_color("font_outline_color", "Label", Color.BLACK)
	_theme.set_stylebox("panel", "PopupMenu", _box(Color(0.08, 0.09, 0.12, 0.98), Color(ACCENT, 0.5)))
	_theme.set_color("font_color", "PopupMenu", TEXT)
	_theme.set_color("font_hover_color", "PopupMenu", ACCENT)
	_theme.set_font_size("font_size", "PopupMenu", 18)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(1, 1, 1, 0.15)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	_theme.set_stylebox("slider", "HSlider", slider)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	_theme.set_stylebox("grabber_area", "HSlider", fill)
	_theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return _theme


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(ACCENT, 0.8)
	style.border_width_top = 3
	style.set_corner_radius_all(8)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 24
	style.content_margin_bottom = 26
	p.add_theme_stylebox_override("panel", style)
	p.theme = theme()
	return p


static func label(text: String, size := 20, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", maxi(size / 7, 2))
	return l


static func button(text: String, callback: Callable, min_width := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 50)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(callback)
	return b


## Centres a control on screen, inside a full-rect holder.
static func centered(control: Control) -> CenterContainer:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(control)
	return holder


static func _box(bg: Color, border: Color, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
