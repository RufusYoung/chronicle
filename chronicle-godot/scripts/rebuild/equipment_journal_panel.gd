extends VBoxContainer

signal action_requested(id: String)

const Style = preload("res://scripts/rebuild/v5_shared_interface_style.gd")
const PAGE_SIZE := 3
const ART_PATH := "res://art/icons/coastal_equipment_pixel_v1.png"
const ART_IDS := ["knotted_fiber_whip", "woven_reed_vest", "reed_quarterstaff", "bound_reed_pike",
	"woven_sap", "reed_buckler", "rescue_harness", "casting_snare", "light_reed_mantle",
	"layered_reed_cuirass", "trail_sandals", "braced_reed_sleeve"]
var data: Dictionary = {}
var category := "items"
var page := 0
var entries: VBoxContainer
var page_label: Label
var previous: Button
var next: Button
var note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "行囊与成长"
	title.add_theme_font_size_override("font_size", Style.FONT_HEADING)
	add_child(title)
	note = Label.new()
	note.text = "物品提供准备，经历留下能力。查看与翻页不推进时间，穿戴花费1小时。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var choices := HBoxContainer.new()
	add_child(choices)
	var group := ButtonGroup.new()
	for key: String in ["items", "features", "catalog"]:
		var button := Button.new()
		button.text = {"items": "物品与穿戴", "features": "技艺与特质", "catalog": "当地装备图鉴"}[key]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = key == category
		Style.apply_command_button(button)
		choices.add_child(button)
		button.pressed.connect(func() -> void:
			category = key
			page = 0
			_render())
	entries = VBoxContainer.new()
	entries.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entries.add_theme_constant_override("separation", 16)
	add_child(entries)
	var paging := HBoxContainer.new()
	paging.add_theme_constant_override("separation", 16)
	add_child(paging)
	previous = Button.new()
	previous.text = "上一页"
	paging.add_child(previous)
	page_label = Label.new()
	paging.add_child(page_label)
	next = Button.new()
	next.text = "下一页"
	paging.add_child(next)
	previous.pressed.connect(func() -> void:
		page -= 1
		_render())
	next.pressed.connect(func() -> void:
		page += 1
		_render())
	Style.apply_command_button(previous)
	Style.apply_command_button(next)


func show_journal(value: Dictionary) -> void:
	data = value
	note.text = str(data.get("note", "")) + " 查看与翻页不耗时，穿戴花费1小时。"
	_render()


func _render() -> void:
	if entries == null:
		return
	for child: Node in entries.get_children():
		entries.remove_child(child)
		child.queue_free()
	var rows: Array = data.get(category, [])
	var pages := maxi(1, ceili(float(rows.size()) / PAGE_SIZE))
	page = clampi(page, 0, pages - 1)
	previous.disabled = page == 0
	next.disabled = page >= pages - 1
	page_label.text = "%d / %d 页 · 共%d项" % [page + 1, pages, rows.size()]
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "行囊里还没有物品。到现场查看能做的作业与真实现货。"
		entries.add_child(empty)
	for row: Dictionary in rows.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE):
		var layout := HBoxContainer.new()
		layout.add_theme_constant_override("separation", 16)
		entries.add_child(layout)
		var icon := _icon(str(row.get("definition_id", "")))
		if icon != null:
			var picture := TextureRect.new()
			picture.texture = icon
			picture.custom_minimum_size = Vector2(96, 96)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			layout.add_child(picture)
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layout.add_child(card)
		var title := Label.new()
		title.text = str(row.name) + (" × %d%s" % [row.quantity, " · 已装备在" + str(row.equipped) if row.equipped != "" else " · 行囊中"] if category == "items" else " · " + str(row.state))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", Style.FONT_HEADING)
		card.add_child(title)
		var description := Label.new()
		description.text = str(row.description)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(description)
		if category != "items":
			continue
		var buttons := HBoxContainer.new()
		card.add_child(buttons)
		for action: Dictionary in data.get("actions", []):
			if action.item_instance_id != row.id and not (row.equipped != "" and str(action.action_id).begins_with("unequip:") and str(row.equipped) == str({"main_hand": "手持", "body_outer": "外衣", "utility": "随身用具"}.get(action.slot_id, ""))):
				continue
			var button := Button.new()
			button.text = str(action.label) + " · 1小时"
			button.tooltip_text = str(action.hint)
			Style.apply_command_button(button)
			buttons.add_child(button)
			button.pressed.connect(func() -> void: action_requested.emit(str(action.action_id)))


static func _icon(definition_id: String) -> Texture2D:
	var index := ART_IDS.find(definition_id.trim_prefix("item."))
	if index < 0:
		return null
	var texture := load(ART_PATH) as Texture2D
	if texture == null:
		return null
	var rows := [0.0, 0.337, 0.63, 1.0]
	var row := int(index / 4)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2((index % 4) * texture.get_width() / 4.0, rows[row] * texture.get_height(),
		texture.get_width() / 4.0, (rows[row + 1] - rows[row]) * texture.get_height())
	return atlas
