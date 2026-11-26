extends RefCounted

## Unit checks of the theme of the interface.
##
## The theme is the look of the whole interface, so every control it touches
## has to keep a style.

const UiThemeFactoryType: GDScript = preload("res://client/scripts/ui_theme_factory.gd")


func run() -> bool:
	var theme: Theme = UiThemeFactoryType.create_mmorpg_theme()
	if not _check(theme != null, "the theme must be built"):
		return false

	var panel: StyleBox = theme.get_stylebox("panel", "PanelContainer")
	if not _check(panel is StyleBoxFlat, "a panel needs a flat style"):
		return false
	var panel_style: StyleBoxFlat = panel
	if not _check(panel_style.border_width_left > 0, "a panel needs a frame"):
		return false
	if not _check(panel_style.corner_radius_top_left > 0, "a panel needs rounded corners"):
		return false
	if not _check(panel_style.bg_color.a > 0.0, "a panel needs a visible surface"):
		return false

	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var button_style: StyleBox = theme.get_stylebox(state, "Button")
		if not _check(button_style != null, "a button needs the style %s" % state):
			return false

	var fill: StyleBox = theme.get_stylebox("fill", "ProgressBar")
	var track: StyleBox = theme.get_stylebox("background", "ProgressBar")
	if not _check(fill != null, "a bar needs a fill"):
		return false
	if not _check(track != null, "a bar needs a track"):
		return false

	var field: StyleBox = theme.get_stylebox("normal", "LineEdit")
	if not _check(field != null, "a text field needs a style"):
		return false

	if not _check(
			theme.get_color("font_color", "Button").a > 0.0,
			"a button needs a readable font color",
	):
		return false
	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition
