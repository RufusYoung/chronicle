extends RefCounted
class_name V5SharedInterfaceStyle

const COLOR_TEXT_PRIMARY := Color("#e9e3d5")
const COLOR_TEXT_MUTED := Color("#a8b3ae")
const COLOR_CANVAS := Color("#090e0f")
const COLOR_PANEL := Color("#141b1b")
const COLOR_INSET := Color("#0e1515")
const COLOR_BORDER := Color("#34413e")
const COLOR_HEADING := Color("#d1b76f")
const FONT_BODY := 14
const FONT_CAPTION := 13
const FONT_ACTION := 13
const FONT_HEADING := 16
const FONT_TITLE := 22
const CONTROL_HEIGHT := 38
const COLOR_SURFACE := Color("#182021")
const COLOR_SURFACE_HOVER := Color("#263031")
const COLOR_SURFACE_PRESSED := Color("#111718")
const COLOR_DISABLED := Color("#4d5553")


static func panel_style(inset: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_INSET if inset else COLOR_PANEL
	box.border_color = COLOR_HEADING if inset else COLOR_BORDER
	box.set_border_width_all(0 if inset else 1)
	if inset:
		box.border_width_left = 3
	box.set_corner_radius_all(4)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


static func apply_command_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(72, CONTROL_HEIGHT)
	button.add_theme_font_size_override("font_size", FONT_BODY)
	apply_decision_button(button, "normal")


static func apply_decision_button(
		button: Button,
		action_type: String,
		emphasized: bool = false,
		compact: bool = false
) -> void:
	var accent := accent_for(action_type)
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_SURFACE.lightened(0.035) if emphasized else COLOR_SURFACE
	normal.border_color = accent.lightened(0.12) if emphasized else accent
	normal.set_border_width_all(2 if emphasized else 1)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 13.0
	normal.content_margin_top = 4.0 if compact else 8.0
	normal.content_margin_right = 13.0
	normal.content_margin_bottom = 4.0 if compact else 8.0
	var hover := normal.duplicate()
	hover.bg_color = COLOR_SURFACE_HOVER
	hover.border_color = accent.lightened(0.24)
	var pressed := normal.duplicate()
	pressed.bg_color = COLOR_SURFACE_PRESSED
	var focus := normal.duplicate()
	focus.border_color = Color("#d8c58f")
	focus.set_border_width_all(2)
	var disabled := normal.duplicate()
	disabled.bg_color = Color("#121718")
	disabled.border_color = COLOR_DISABLED
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Color("#fff8e9"))
	button.add_theme_color_override("font_focus_color", Color("#fff8e9"))
	button.add_theme_color_override("font_disabled_color", COLOR_DISABLED)


static func accent_for(action_type: String) -> Color:
	return {
		"dialogue": Color("#668c91"),
		"clue": Color("#9a7e4e"),
		"relationship": Color("#9a6c82"),
		"travel": Color("#788f68"),
		"preparation": Color("#718b9e"),
		"danger": Color("#a96555"),
		"retreat": Color("#718b9e"),
		"relic": Color("#ad8250"),
		"investigation": Color("#b9894c"),
		"life": Color("#788c72"),
		"military": Color("#8b7960"),
	}.get(action_type, Color("#a98452"))
