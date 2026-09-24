extends Control

const Style = preload("res://scripts/rebuild/v5_shared_interface_style.gd")
const NODE_SIZE := Vector2(152, 76)
var data: Dictionary = {}
var positions: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(480, 200)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_layout_nodes)


func show_region(value: Dictionary) -> void:
	data = value.duplicate(true)
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for site: Dictionary in data.get("sites", []):
		var current: bool = site.id == data.get("current_settlement_id", "")
		var frame := PanelContainer.new()
		frame.name = str(site.id)
		frame.custom_minimum_size = NODE_SIZE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Style.COLOR_SURFACE
		style.border_color = Style.accent_for("travel") if current else Style.COLOR_DISABLED
		style.set_border_width_all(2)
		style.set_content_margin_all(6)
		frame.add_theme_stylebox_override("panel", style)
		add_child(frame)
		var label := Label.new()
		label.text = str(site.name)
		label.text += "\n你在这里" if current else "\n" + str(site.terrain_label)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Style.COLOR_TEXT_PRIMARY if current else Style.COLOR_TEXT_MUTED)
		frame.add_child(label)
	_layout_nodes()


func _layout_nodes() -> void:
	positions.clear()
	var nodes := get_children()
	for i: int in nodes.size():
		var fraction := float(i) / maxi(nodes.size() - 1, 1)
		var point := Vector2(90 + fraction * maxf(size.x - 180, 0), size.y * (0.38 if i % 2 == 0 else 0.72))
		positions[str((data.sites[i] as Dictionary).id)] = point
		var frame := nodes[i] as PanelContainer
		frame.size = NODE_SIZE.max(frame.get_combined_minimum_size())
		frame.position = point - frame.size / 2
	queue_redraw()


func _draw() -> void:
	for road: Dictionary in data.get("roads", []):
		if positions.has(road.from) and positions.has(road.to):
			draw_line(positions[road.from], positions[road.to], Style.accent_for("travel"), 3, true)
