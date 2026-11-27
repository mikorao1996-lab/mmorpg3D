class_name UiThemeFactory
extends RefCounted

## Builds the visual theme of the interface.
##
## The theme gives every panel the same look: a dark translucent surface with
## a thin bronze frame, rounded corners, and a light warm text. The style is
## created in code, so the whole interface changes in one place and the
## panels do not carry their own colors.

const COLOR_SURFACE: Color = Color(0.08, 0.09, 0.12, 0.88)
const COLOR_SURFACE_SOLID: Color = Color(0.1, 0.11, 0.15, 0.96)
const COLOR_FRAME: Color = Color(0.55, 0.45, 0.28, 0.75)
const COLOR_FRAME_BRIGHT: Color = Color(0.95, 0.8, 0.45, 1.0)
const COLOR_BUTTON: Color = Color(0.14, 0.16, 0.21, 0.92)
const COLOR_BUTTON_HOVER: Color = Color(0.22, 0.25, 0.32, 0.95)
const COLOR_BUTTON_PRESSED: Color = Color(0.1, 0.11, 0.14, 1.0)
const COLOR_BUTTON_DISABLED: Color = Color(0.12, 0.13, 0.16, 0.7)
const COLOR_TEXT: Color = Color(0.93, 0.91, 0.86)
const COLOR_TEXT_HOVER: Color = Color(1.0, 0.92, 0.68)
const COLOR_TEXT_DISABLED: Color = Color(0.5, 0.5, 0.52)
const COLOR_TITLE: Color = Color(0.95, 0.8, 0.45)
const COLOR_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.55)
const COLOR_TRACK: Color = Color(0.05, 0.05, 0.07, 0.9)

const FONT_SIZE_BODY: int = 13
const FONT_SIZE_TITLE: int = 15
const FONT_SIZE_SMALL: int = 11

const MARGIN_HORIZONTAL: float = 7.0
const MARGIN_VERTICAL: float = 5.0
const SCROLLBAR_WIDTH: float = 10.0


## Builds the theme of the interface.
static func create_mmorpg_theme() -> Theme:
	var theme: Theme = Theme.new()
	_apply_panel_styles(theme)
	_apply_button_styles(theme)
	_apply_label_styles(theme)
	_apply_input_styles(theme)
	_apply_bar_styles(theme)
	_apply_scrollbar_styles(theme)
	return theme


## Styles the surfaces of the panels.
static func _apply_panel_styles(theme: Theme) -> void:
	var panel: StyleBoxFlat = _build_panel_style()
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "ScrollContainer", panel.duplicate())
	theme.set_stylebox("panel", "PopupMenu", panel.duplicate())


## Styles the buttons of the interface.
static func _apply_button_styles(theme: Theme) -> void:
	var normal: StyleBoxFlat = _build_panel_style()
	normal.bg_color = COLOR_BUTTON
	normal.border_color = Color(0.45, 0.38, 0.25, 0.8)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = COLOR_BUTTON_HOVER
	hover.border_color = COLOR_FRAME_BRIGHT

	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = COLOR_BUTTON_PRESSED
	pressed.border_color = COLOR_FRAME_BRIGHT

	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = COLOR_BUTTON_DISABLED
	disabled.border_color = Color(0.3, 0.28, 0.22, 0.5)

	var focus: StyleBoxFlat = normal.duplicate()
	focus.bg_color = COLOR_BUTTON_HOVER
	focus.border_color = COLOR_FRAME_BRIGHT

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", COLOR_TEXT_HOVER)
	theme.set_color("font_pressed_color", "Button", COLOR_TEXT_HOVER)
	theme.set_color("font_disabled_color", "Button", COLOR_TEXT_DISABLED)
	theme.set_font_size("font_size", "Button", FONT_SIZE_BODY)


## Styles the labels of the interface.
static func _apply_label_styles(theme: Theme) -> void:
	theme.set_color("font_color", "Label", COLOR_TEXT)
	theme.set_font_size("font_size", "Label", FONT_SIZE_BODY)
	theme.set_color("default_color", "RichTextLabel", COLOR_TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", FONT_SIZE_BODY)


## Styles the text fields of the interface.
static func _apply_input_styles(theme: Theme) -> void:
	var field: StyleBoxFlat = _build_panel_style()
	field.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	field.border_color = Color(0.4, 0.35, 0.24, 0.7)
	field.content_margin_left = 7
	field.content_margin_right = 7
	field.content_margin_top = 4
	field.content_margin_bottom = 4
	theme.set_stylebox("normal", "LineEdit", field.duplicate())
	theme.set_stylebox("focus", "LineEdit", field.duplicate())
	theme.set_color("font_color", "LineEdit", COLOR_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(0.55, 0.55, 0.58))
	theme.set_color("caret_color", "LineEdit", COLOR_FRAME_BRIGHT)
	theme.set_font_size("font_size", "LineEdit", FONT_SIZE_BODY)


## Styles the bars of the interface.
static func _apply_bar_styles(theme: Theme) -> void:
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = COLOR_TRACK
	track.set_corner_radius_all(4)
	theme.set_stylebox("background", "ProgressBar", track)

	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(0.78, 0.24, 0.2)
	fill.set_corner_radius_all(4)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", COLOR_TEXT)
	theme.set_font_size("font_size", "ProgressBar", FONT_SIZE_SMALL)


## Styles the scrollbars of the interface.
##
## The grabber is thin and bright, so the player sees at once that the list
## under the pointer can be scrolled.
static func _apply_scrollbar_styles(theme: Theme) -> void:
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.05, 0.07, 0.7)
	track.set_corner_radius_all(4)
	# The width of the bar is the width of the track.
	track.content_margin_left = 5
	track.content_margin_right = 5

	var grabber: StyleBoxFlat = StyleBoxFlat.new()
	grabber.bg_color = Color(0.45, 0.38, 0.24, 0.9)
	grabber.set_corner_radius_all(4)
	grabber.content_margin_left = 3
	grabber.content_margin_right = 3

	var grabber_highlight: StyleBoxFlat = grabber.duplicate()
	grabber_highlight.bg_color = COLOR_FRAME_BRIGHT

	var grabber_pressed: StyleBoxFlat = grabber.duplicate()
	grabber_pressed.bg_color = Color(0.8, 0.66, 0.36, 1.0)

	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_stylebox("scroll", "HScrollBar", track)
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	theme.set_stylebox("grabber", "HScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_highlight)
	theme.set_stylebox("grabber_highlight", "HScrollBar", grabber_highlight)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_pressed)
	theme.set_stylebox("grabber_pressed", "HScrollBar", grabber_pressed)
	theme.set_constant("grabber_offset", "VScrollBar", 0)


## Builds the style of a surface.
static func _build_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_SURFACE
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = COLOR_FRAME
	style.set_corner_radius_all(6)
	style.content_margin_left = MARGIN_HORIZONTAL
	style.content_margin_right = MARGIN_HORIZONTAL
	style.content_margin_top = MARGIN_VERTICAL
	style.content_margin_bottom = MARGIN_VERTICAL
	style.shadow_color = COLOR_SHADOW
	style.shadow_size = 6
	return style
