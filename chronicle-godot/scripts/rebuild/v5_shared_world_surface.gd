extends RefCounted
class_name V5SharedWorldSurface

const Style = preload("res://scripts/rebuild/v5_shared_interface_style.gd")
const ACTION_PAGE_SIZE := 4
const TRAVEL_PAGE_SIZE := 3


static func install(
		viewer: Control, host: VBoxContainer, old_main: Control,
		dock: Control, slots: Dictionary
) -> Dictionary:
	# Both life scales use the same reading order; only the records page scrolls.
	_disable_nested_scrolling(viewer)
	_install_header(viewer, host, slots.get("header", {}))
	(viewer.get_node("Background") as ColorRect).color = Style.COLOR_CANVAS
	var dock_style := Style.panel_style()
	if dock.get_child(0) is MarginContainer:
		dock_style.content_margin_left = 0
		dock_style.content_margin_right = 0
		dock_style.content_margin_top = 0
		dock_style.content_margin_bottom = 0
	dock.add_theme_stylebox_override("panel", dock_style)
	var hint := viewer.get_node("%ActionHint") as Label
	hint.add_theme_color_override("font_color", Style.COLOR_TEXT_MUTED)
	hint.add_theme_font_size_override("font_size", Style.FONT_CAPTION)
	(viewer.get_node("%ActionHeading") as Label).add_theme_font_size_override("font_size", Style.FONT_HEADING)
	var tabs := TabContainer.new()
	tabs.name = "WorldSurfacePages"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.use_hidden_tabs_for_min_size = false
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
	var eyebrow := feedback.get_child(0) as Label
	eyebrow.add_theme_font_size_override("font_size", Style.FONT_CAPTION)
	eyebrow.add_theme_color_override("font_color", Style.COLOR_TEXT_MUTED)
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
	_move_nodes(slots.get("supplies", []), decision)

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
	var back_to_scene := Button.new()
	back_to_scene.name = "BackToScene"
	back_to_scene.text = "返回现场"
	back_to_scene.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	Style.apply_command_button(back_to_scene)
	record_content.add_child(back_to_scene)
	back_to_scene.owner = viewer
	back_to_scene.unique_name_in_owner = true
	back_to_scene.pressed.connect(func() -> void: tabs.current_tab = 0)
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
	var receipt_button := LinkButton.new()
	receipt_button.name = "OpenResultReceipt"
	receipt_button.text = "查看完整结果"
	receipt_button.focus_mode = Control.FOCUS_ALL
	receipt_button.custom_minimum_size.y = 24
	receipt_button.add_theme_font_size_override("font_size", Style.FONT_CAPTION)
	receipt_button.add_theme_color_override("font_color", Style.COLOR_TEXT_MUTED)
	var result_header := HBoxContainer.new()
	result_header.add_theme_constant_override("separation", 12)
	feedback.add_child(result_header)
	feedback.move_child(result_header, 0)
	eyebrow.reparent(result_header)
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_header.add_child(receipt_button)
	receipt_button.owner = viewer
	receipt_button.unique_name_in_owner = true
	receipt_button.pressed.connect(func() -> void:
		tabs.current_tab = records.get_index()
		records.scroll_vertical = 0
		back_to_scene.grab_focus())
	back_to_scene.pressed.connect(func() -> void: receipt_button.grab_focus())
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
	Style.apply_decision_button(previous, "normal", false, true)
	Style.apply_decision_button(next, "normal", false, true)
	viewer.resized.connect(func() -> void:
		_apply_action_page(surface, viewer, actions))
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
		button.custom_minimum_size.y = 86
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


static func paginate_travel(surface: Dictionary, viewer: Control, buttons: VBoxContainer) -> void:
	if not surface.has("travel_paging"):
		var pager := HBoxContainer.new()
		pager.add_theme_constant_override("separation", 8)
		buttons.get_parent().get_parent().add_child(pager)
		var paging := {"page": 0, "signature": [], "pager": pager}
		for direction: int in [-1, 1]:
			var button := Button.new()
			button.name = "PreviousTravel" if direction < 0 else "NextTravel"
			button.text = "上一页" if direction < 0 else "下一页"
			button.add_theme_font_size_override("font_size", 13)
			pager.add_child(button)
			button.owner = viewer
			button.unique_name_in_owner = true
			Style.apply_decision_button(button, "normal", false, true)
			paging["previous" if direction < 0 else "next"] = button
			button.pressed.connect(_step_travel_page.bind(paging, buttons, direction))
			if direction < 0:
				var label := Label.new()
				label.add_theme_font_size_override("font_size", 13)
				pager.add_child(label)
				paging["label"] = label
		surface["travel_paging"] = paging
	var paging: Dictionary = surface["travel_paging"]
	var signature: Array = buttons.get_children().map(func(button: Button) -> String:
		return str(button.get_meta("route_id", "")))
	if signature != paging["signature"]:
		paging["page"] = 0
		paging["signature"] = signature
	_step_travel_page(paging, buttons, 0)


static func _step_travel_page(paging: Dictionary, buttons: VBoxContainer, delta: int) -> void:
	var count := buttons.get_child_count()
	var pages := maxi(ceili(float(count) / TRAVEL_PAGE_SIZE), 1)
	var page := clampi(int(paging["page"]) + delta, 0, pages - 1)
	paging["page"] = page
	(paging["pager"] as Control).visible = pages > 1
	(paging["previous"] as Button).disabled = page == 0
	(paging["next"] as Button).disabled = page == pages - 1
	(paging["label"] as Label).text = "路线 %d-%d / %d" % [page * TRAVEL_PAGE_SIZE + 1, mini((page + 1) * TRAVEL_PAGE_SIZE, count), count]
	for index: int in count:
		(buttons.get_child(index) as Control).visible = index >= page * TRAVEL_PAGE_SIZE and index < (page + 1) * TRAVEL_PAGE_SIZE


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
	button.add_theme_font_size_override("font_size", Style.FONT_ACTION)
	Style.apply_decision_button(button, action_type)


static func action_width(viewer: Control, count: int) -> float:
	var columns := mini(maxi(count, 1), 4) if count <= 4 or count > 6 else 3
	return floor((viewer.size.x - 72.0 - (columns - 1) * 8.0) / columns)


static func _panel_column(parent: Node, ratio: float, inset: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	panel.add_theme_stylebox_override("panel", Style.panel_style(inset))
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
			node.add_theme_font_size_override("normal_font_size", Style.FONT_BODY)
			node.add_theme_font_size_override("bold_font_size", Style.FONT_BODY)
			node.add_theme_color_override("default_color", Style.COLOR_TEXT_PRIMARY)
		elif node is Label:
			node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			node.add_theme_font_size_override("font_size", Style.FONT_HEADING)
			node.add_theme_color_override("font_color", Style.COLOR_HEADING)
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


static func _install_header(viewer: Control, host: VBoxContainer, slots: Dictionary) -> void:
	if slots.is_empty():
		return
	(host.get_node("Header") as Control).hide()
	var panel := PanelContainer.new()
	panel.name = "WorldHeader"
	panel.custom_minimum_size.y = 64
	panel.add_theme_stylebox_override("panel", Style.panel_style())
	host.add_child(panel)
	host.move_child(panel, 0)
	panel.owner = viewer
	panel.unique_name_in_owner = true
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 0)
	row.add_child(brand)
	_move_nodes(slots.get("brand", []), brand)
	var title := brand.get_child(0) as Label
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_font_size_override("font_size", Style.FONT_TITLE)
	var subtitle := brand.get_child(1) as Label
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	subtitle.add_theme_font_size_override("font_size", Style.FONT_CAPTION)
	subtitle.add_theme_color_override("font_color", Style.COLOR_TEXT_MUTED)
	var clock_column := VBoxContainer.new()
	clock_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(clock_column)
	_move_nodes(slots.get("clock", []), clock_column)
	for label: Label in clock_column.get_children():
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.add_theme_font_size_override("font_size", Style.FONT_BODY)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var commands := HBoxContainer.new()
	commands.name = "WorldCommands"
	commands.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	commands.add_theme_constant_override("separation", 8)
	row.add_child(commands)
	for button: Button in slots.get("commands", []):
		button.reparent(commands)
		Style.apply_command_button(button)
