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
		var label := Label.new()
		label.name = str(site.id)
		label.text = str(site.name)
		var current: bool = site.id == data.get("current_settlement_id", "")
		label.text += "\n你在这里" if current else "\n" + str(site.terrain_label)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Style.COLOR_TEXT_PRIMARY if current else Style.COLOR_TEXT_MUTED)
		add_child(label)
	_layout_nodes()


func _layout_nodes() -> void:
	positions.clear()
	var nodes := get_children()
	for i: int in nodes.size():
		var fraction := float(i) / maxi(nodes.size() - 1, 1)
		var point := Vector2(90 + fraction * maxf(size.x - 180, 0), size.y * (0.38 if i % 2 == 0 else 0.72))
		positions[str((data.sites[i] as Dictionary).id)] = point
		var label := nodes[i] as Label
		label.position = point - NODE_SIZE / 2
		label.size = NODE_SIZE
	queue_redraw()


func _draw() -> void:
	for road: Dictionary in data.get("roads", []):
		if positions.has(road.from) and positions.has(road.to):
			draw_line(positions[road.from], positions[road.to], Style.accent_for("travel"), 3, true)
	for id: String in positions:
		var rectangle := Rect2(positions[id] - NODE_SIZE / 2, NODE_SIZE)
		draw_rect(rectangle, Style.COLOR_SURFACE)
		draw_rect(rectangle, Style.accent_for("travel") if id == data.get("current_settlement_id", "") else Style.COLOR_DISABLED, false, 2)
