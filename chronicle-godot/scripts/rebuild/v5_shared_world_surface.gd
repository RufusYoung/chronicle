extends RefCounted
class_name V5SharedWorldSurface

const Style = preload("res://scripts/rebuild/v5_shared_interface_style.gd")
const ACTION_PAGE_SIZE := 4


static func install(
		viewer: Control, host: VBoxContainer, old_main: Control,
		dock: Control, slots: Dictionary
) -> Dictionary:
	# Both life scales use the same reading order; only the records page scrolls.
	_disable_nested_scrolling(viewer)
	var tabs := TabContainer.new()
	tabs.name = "WorldSurfacePages"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 15)
	tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	host.add_child(tabs)
	tabs.owner = viewer
	tabs.unique_name_in_owner = true
	host.move_child(tabs, 1)
	var scene := HBoxContainer.new()
	scene.name = "现场"
	scene.add_theme_constant_override("separation", 10)
	tabs.add_child(scene)
	var primary := _panel_column(scene, 2.0)
	var decision := _panel_column(scene, 1.0)
	_move_nodes(slots.get("scene", []), primary)
	var feedback := _panel_column(primary, 1.0, true)
	_move_nodes(slots.get("feedback", []), feedback)
	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", 14)
	primary.add_child(details)
	for section: String in ["people", "observations"]:
		var nodes: Array = slots.get(section, [])
		if nodes.is_empty():
			continue
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = 1.0 if section == "people" else 1.6
		details.add_child(column)
		_move_nodes(nodes, column)
	_heading(decision, "决定依据")
	var situation := _rich_text(decision)
	situation.name = "DecisionSituation"
	situation.owner = viewer
	situation.unique_name_in_owner = true
	_move_nodes(slots.get("decision", []), decision)

	var character := HBoxContainer.new()
	character.name = "角色"
	character.add_theme_constant_override("separation", 12)
	tabs.add_child(character)
	for column_nodes: Array in slots.get("character", []):
		var column := _panel_column(character, 1.0)
		_move_nodes(column_nodes, column)

	var records := ScrollContainer.new()
	records.name = "记录"
	records.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	records.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tabs.add_child(records)
	var record_content := _panel_column(records, 1.0)
	_heading(record_content, "本次结算 · 完整过程")
	var receipt := _rich_text(record_content)
	receipt.name = "ResultReceipt"
	receipt.owner = viewer
	receipt.unique_name_in_owner = true
	_heading(record_content, "现场与人物详情")
	var scene_record := _rich_text(record_content)
	scene_record.name = "SceneDetailsRecord"
	scene_record.owner = viewer
	scene_record.unique_name_in_owner = true
	_move_nodes(slots.get("records", []), record_content)
	old_main.hide()
	tabs.tab_changed.connect(func(index: int) -> void: dock.visible = index == 0)
	var surface := {"tabs": tabs, "situation": situation, "receipt": receipt,
		"scene_record": scene_record, "action_page": 0, "action_signature": []}
	var actions: FlowContainer = viewer.get_node("%ActionButtons")
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation", 12)
	actions.get_parent().get_parent().add_child(pager)
	var previous := Button.new()
	previous.name = "PreviousActions"
	previous.text = "上一页"
	previous.add_theme_font_size_override("font_size", 13)
	pager.add_child(previous)
	previous.owner = viewer
	previous.unique_name_in_owner = true
	var page_label := Label.new()
	pager.add_child(page_label)
	var next := Button.new()
	next.name = "NextActions"
	next.text = "下一页"
	next.add_theme_font_size_override("font_size", 13)
	pager.add_child(next)
	next.owner = viewer
	next.unique_name_in_owner = true
	surface.merge({"pager": pager, "previous": previous, "next": next,
		"page_label": page_label})
	previous.pressed.connect(func() -> void:
		surface["action_page"] -= 1
		_apply_action_page(surface, viewer, actions))
	next.pressed.connect(func() -> void:
		surface["action_page"] += 1
		_apply_action_page(surface, viewer, actions))
	Style.apply_decision_button(previous, "normal")
	Style.apply_decision_button(next, "normal")
	pager.hide()
	return surface


static func paginate_actions(surface: Dictionary, viewer: Control, actions: FlowContainer) -> void:
	var signature: Array[String] = []
	for button: Button in actions.get_children():
		signature.append(button.text)
	if signature != surface["action_signature"]:
		surface["action_page"] = 0
		surface["action_signature"] = signature
	_apply_action_page(surface, viewer, actions)


static func _apply_action_page(surface: Dictionary, viewer: Control, actions: FlowContainer) -> void:
	var count := actions.get_child_count()
	var pages := maxi(1, ceili(float(count) / ACTION_PAGE_SIZE))
	var page := clampi(int(surface["action_page"]), 0, pages - 1)
	surface["action_page"] = page
	(surface["pager"] as Control).visible = pages > 1
	(surface["previous"] as Button).disabled = page == 0
	(surface["next"] as Button).disabled = page == pages - 1
	(surface["page_label"] as Label).text = "行动 %d–%d / %d · 翻页不推进时间" % [
		page * ACTION_PAGE_SIZE + 1, mini((page + 1) * ACTION_PAGE_SIZE, count), count]
	for index: int in count:
		var button := actions.get_child(index) as Button
		button.visible = index >= page * ACTION_PAGE_SIZE and index < (page + 1) * ACTION_PAGE_SIZE
		button.custom_minimum_size.x = action_width(viewer, mini(ACTION_PAGE_SIZE, count - page * ACTION_PAGE_SIZE))


static func update_receipt(surface: Dictionary, feedback: Dictionary) -> void:
	var lines: Array[String] = [
		str(feedback.get("eyebrow", "当前局势")),
		str(feedback.get("title", "")),
		str(feedback.get("body", "")),
	]
	for detail: Variant in feedback.get("details", []):
		lines.append("• %s" % str(detail))
	(surface["receipt"] as RichTextLabel).text = "\n".join(lines)


static func compact_feedback(feedback: Dictionary, max_details: int = 3) -> String:
	var body := str(feedback.get("body", ""))
	var lines: Array[String] = [body]
	var details: Array = feedback.get("summary_details", feedback.get("details", []))
	for detail: Variant in details.slice(0, max_details):
		var text := str(detail)
		if text != "" and text not in body:
			lines.append(text)
	return "\n".join(lines)


static func style_action(button: Button, action_type: String) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 13)
	Style.apply_decision_button(button, action_type)


static func action_width(viewer: Control, count: int) -> float:
	var columns := mini(maxi(count, 1), 4) if count <= 4 or count > 6 else 3
	return floor((viewer.size.x - 72.0 - (columns - 1) * 8.0) / columns)


static func _panel_column(parent: Node, ratio: float, inset: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#0e1515") if inset else Color("#141b1b")
	box.border_color = Color("#9a7e4e") if inset else Color("#34413e")
	box.set_border_width_all(0 if inset else 1)
	if inset:
		box.border_width_left = 3
	box.set_corner_radius_all(4)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", box)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	return column


static func _move_nodes(nodes: Array, parent: Node) -> void:
	for node: Control in nodes:
		node.reparent(parent)
		node.custom_minimum_size = Vector2.ZERO
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.size_flags_vertical = Control.SIZE_FILL
		if node is RichTextLabel:
			node.fit_content = true
			node.scroll_active = false
			node.add_theme_font_size_override("normal_font_size", 14)
			node.add_theme_font_size_override("bold_font_size", 14)
		elif node is Label:
			node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		elif node is ScrollContainer:
			node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			node.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


static func _heading(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#d1b76f"))
	parent.add_child(label)


static func _rich_text(parent: Node) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.add_theme_font_size_override("normal_font_size", 14)
	parent.add_child(label)
	return label


static func _disable_nested_scrolling(node: Node) -> void:
	if node is RichTextLabel:
		node.scroll_active = false
	elif node is ScrollContainer:
		node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		node.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	for child: Node in node.get_children():
		_disable_nested_scrolling(child)
