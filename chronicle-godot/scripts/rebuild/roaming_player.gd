extends Control
## The native UI and code agent use the same legal action boundary and native saves.

const Agent = preload("res://scripts/agent/agent_game_session.gd")
const Presentation = preload("res://scripts/rebuild/roaming_presentation.gd")
const FONT = preload("res://art/fonts/SourceHanSerifSC-VF.ttf")
const EquipmentPanel = preload("res://scripts/rebuild/equipment_journal_panel.gd")
const WorldAudio = preload("res://scripts/rebuild/world_audio.gd")

var agent = Agent.new()
var slot := "situation_manual"
var economy_variant := "world_situation_v1"
var initial_seed := 81001
var auto_load := true
var busy := false
var response: Dictionary = {}
var page := "scene"
var family := ""
var offset := 0
var pending_result := false
var result_art := ""
var before_player: Dictionary = {}
var before_view: Dictionary = {}
var delta_text := ""
var _worker: Thread
var _serial := 0
var _operation := ""
var _root: VBoxContainer
var _body: HBoxContainer
var _story: VBoxContainer
var _choices: VBoxContainer
var _picture: TextureRect
var _heading: Label
var _paragraph: Label
var _status: Label
var _toast: Label
var _dialog: ConfirmationDialog
var _dialog_action := ""
var _pending_choice_id := ""
var _quit_after_save := false
var _discard_button: Button
var _menu: AcceptDialog
var _audio: Node


func _ready() -> void:
	if "--authored-roaming" in OS.get_cmdline_user_args():
		economy_variant = "world_roaming_v1"
		if slot == "situation_manual":
			slot = "roaming_manual"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	agent.control_source = "native_ui"
	get_tree().auto_accept_quit = false
	var theme_resource := Theme.new()
	theme_resource.default_font = FONT
	theme_resource.default_font_size = 20
	theme_resource.set_color("font_color", "Label", Color("e5dfcf"))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("243b37") if state in ["hover", "pressed"] else Color("192321")
		box.border_color = Color("dac18a") if state in ["hover", "focus"] else Color("526258")
		box.set_border_width_all(2 if state == "focus" else 1)
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		theme_resource.set_stylebox(state, "Button", box)
	theme = theme_resource
	var background := ColorRect.new()
	background.color = Color("101917")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	margin.add_child(_root)
	_dialog = ConfirmationDialog.new()
	_dialog.dialog_autowrap = true
	_dialog.confirmed.connect(_confirm)
	add_child(_dialog)
	_discard_button = _dialog.add_button("退出，不保存", false, "discard")
	_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "discard" and _dialog_action == "quit" and not busy:
			get_tree().quit())
	_audio = WorldAudio.new()
	add_child(_audio)
	_menu = AcceptDialog.new()
	_menu.title = "旅途菜单"
	_menu.min_size = Vector2i(720, 520)
	_menu.get_ok_button().text = "返回旅途"
	add_child(_menu)
	var help := VBoxContainer.new()
	help.add_theme_constant_override("separation", 16)
	_menu.add_child(help)
	var instructions := _label(help, "自由漫游，无需先谋生。\n现场：看清局面，问话或用自己的物品介入。\n地图：查看路线，随时选择离开。\n行囊与人物：查看装备、属性和成长。\n买卖：对方必须在场，并且有钱或有货。\n普通结果留在现场，不必额外点击继续。\n阅读不耗时；等候可被眼前变化打断。\n未知的事情先问清楚，不保证一定有收获。\n请主动保存。Esc 打开此菜单。", 18)
	instructions.custom_minimum_size.x = 620
	instructions.autowrap_mode = TextServer.AUTOWRAP_OFF
	_audio.install_control(help)
	var quit_button := Button.new()
	quit_button.text = "结束这次游玩"
	help.add_child(quit_button)
	quit_button.pressed.connect(func() -> void:
		_menu.hide()
		_ask("quit", "保存这次旅途并退出？也可以不保存退出。"))
	_begin("start", {"mode": "play", "scenario": "echo_realm", "seed": initial_seed, "economy_variant": economy_variant})


func _request(command: String, fields: Dictionary) -> Dictionary:
	_serial += 1
	var request := {"protocol": 1, "command": command, "request_id": "ui_" + str(_serial),
		"session_id": agent.session_id, "expected_revision": agent.revision}
	request.merge(fields)
	return agent.handle(request)


func _begin(command: String, fields: Dictionary = {}) -> void:
	if busy:
		return
	busy = true
	_operation = command
	if command == "act":
		before_view = response.get("observation", {}).duplicate(true)
		before_player = before_view.get("player", {})
		result_art = Presentation.art(response.get("observation", {}))
	_render()
	_worker = Thread.new()
	_worker.start(func() -> Dictionary: return _request(command, fields))


func _process(_delta: float) -> void:
	if _worker == null or _worker.is_alive():
		return
	var settled: Dictionary = _worker.wait_to_finish()
	_worker = null
	busy = false
	var command := _operation
	if settled.has("observation"):
		response = settled
	if not settled.get("ok", false):
		_quit_after_save = false
		_render()
		_toast.text = "未能完成：" + str(settled.get("error", settled.get("receipt", {}).get("error", "未知原因"))) + "。没有自动重试。"
		_toast.show()
		return
	if command == "start" and auto_load:
		auto_load = false
		if FileAccess.file_exists(Agent.SAVE_ROOT + "play/echo_realm/" + slot + ".json"):
			_begin("load", {"slot": slot})
			return
	if command == "act":
		_audio.play(WorldAudio.cue_for("act", settled.get("receipt", {}), before_view, response.observation))
		pending_result = int(response.observation.player.get("health", 100)) <= 0 \
			or int(before_player.get("health", 100)) - int(response.observation.player.get("health", 100)) >= 20
		page = "scene"
		family = ""
		offset = 0
		delta_text = _changes(before_player, response.observation.player)
	elif command in ["load", "start"]:
		pending_result = false
		before_view = {}
		before_player = {}
		delta_text = ""
		page = "scene"
		family = ""
		offset = 0
	_render()
	if command in ["start", "load"]:
		print("CHRONICLE_WORLD_READY " + JSON.stringify({"surface": "roaming", "journey_version": agent.model.session.fixture_source_data.get("journey_rules", {}).get("version"), "situation_version": agent.model.session.fixture_source_data.get("situation_rules", {}).get("version", 0), "elapsed_hours": agent.model.session.elapsed_hours_since_start}))
	if command == "save":
		_toast.text = "旅途已保存。新版与旧版存档分开存放。"
		_toast.show()
		if _quit_after_save:
			get_tree().quit()
	elif command == "load":
		_toast.text = "已回到保存时的地点、人物和选择。"
		_toast.show()


func _exit_tree() -> void:
	if _worker != null:
		_worker.wait_to_finish()
		_worker = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not busy:
		_ask("quit", "保存这次旅途并退出？取消后仍可继续游玩。")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not busy:
		if _dialog.visible:
			_dialog.hide()
		elif _menu.visible:
			_menu.hide()
		else:
			_menu.popup_centered()
		get_viewport().set_input_as_handled()


func _ask(action: String, text: String) -> void:
	_dialog_action = action
	_discard_button.visible = action == "quit"
	_dialog.get_ok_button().text = "保存并退出" if action == "quit" else "确认"
	if action == "act":
		_dialog.get_ok_button().text = "采取这个行动"
	_dialog.get_cancel_button().text = "取消"
	_dialog.dialog_text = text
	_dialog.popup_centered(Vector2i(520, 180))


func _confirm() -> void:
	match _dialog_action:
		"act": _begin("act", {"choice_id": _pending_choice_id, "confirm": true})
		"new":
			auto_load = false
			_begin("start", {"mode": "play", "scenario": "echo_realm", "seed": initial_seed, "economy_variant": economy_variant})
		"load": _begin("load", {"slot": slot})
		"quit":
			_quit_after_save = true
			_begin("save", {"slot": slot, "overwrite": true})


func _render() -> void:
	if _root == null:
		return
	for child: Node in _root.get_children():
		child.free()
	var header := HBoxContainer.new()
	_root.add_child(header)
	var brand := _label(header, "CHRONICLE  /  漫游", 24)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(header, "保存", func() -> void: _begin("save", {"slot": slot, "overwrite": true}))
	_button(header, "读档", func() -> void: _ask("load", "读取上次保存，会放弃当前尚未保存的进展。"))
	_button(header, "新旅途", func() -> void: _ask("new", "开始新的旅途。原存档不会自动覆盖，直到你再次点击保存。"))
	_button(header, "菜单", func() -> void: _menu.popup_centered())
	_status = _label(_root, _status_text(), 18)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	_root.add_child(nav)
	for entry: Array in [["scene", "现场"], ["map", "地图与去向"], ["inventory", "行囊"], ["character", "人物"], ["journal", "旅途记录"]]:
		var key := str(entry[0])
		var button := _button(nav, str(entry[1]), func() -> void: _navigate(key))
		button.modulate = Color("efd39b") if page == key else Color.WHITE
	_toast = _label(_root, "世界正在运行，请稍候……" if busy else "", 16)
	_toast.custom_minimum_size.y = 22
	_toast.visible = busy
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 30)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_body)
	var art_column := VBoxContainer.new()
	art_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_column.size_flags_stretch_ratio = 0.85
	_body.add_child(art_column)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.custom_minimum_size.y = 280
	_picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_column.add_child(_picture)
	_label(art_column, str(response.get("observation", {}).get("location", {}).get("title", "镜湖北岸")), 19)
	_label(art_column, "临时授权像素插图 / 场景氛围不代表实时人物", 13)
	_story = VBoxContainer.new()
	_story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story.size_flags_stretch_ratio = 1.55
	_story.add_theme_constant_override("separation", 8)
	_body.add_child(_story)
	var projected := Presentation.build(response, page)
	var path: String = result_art if pending_result and page == "scene" else str(projected.art)
	if ResourceLoader.exists(path):
		_picture.texture = load(path)
	if page in ["inventory", "character", "journal"]:
		_render_collection()
	elif pending_result and page == "scene":
		_render_result()
	else:
		_label(_story, str(projected.eyebrow), 17).modulate = Color("bfaa7b")
		_heading = _label(_story, str(projected.title), 28)
		_paragraph = _label(_story, str(projected.body), 21)
		if page == "scene" and not before_view.is_empty():
			var feedback: Dictionary = response.get("observation", {}).get("feedback", {})
			var result_line := _label(_story, str(feedback.get("compact_body", feedback.get("body", ""))), 17)
			result_line.name = "InlineOutcome"
			result_line.max_lines_visible = 2
			result_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			result_line.modulate = Color("dfc787")
			result_line.visible = result_line.text != "" and not str(projected.body).contains(result_line.text)
			var detail := LinkButton.new()
			detail.text = "查看完整结果"
			detail.pressed.connect(func() -> void: _navigate("journal"))
			_story.add_child(detail)
		_choices = VBoxContainer.new()
		_choices.add_theme_constant_override("separation", 8)
		_story.add_child(_choices)
		_render_choices(projected.choices, str(projected.empty))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	_root.add_child(footer)
	for entry: Array in [["talk", "交谈"], ["trade", "买卖与赠送"], ["rest", "吃饭与休整"], ["work", "谋生 / 制作"]]:
		var key := str(entry[0])
		_button(footer, str(entry[1]), func() -> void: _navigate(key))
	if pending_result and page != "scene":
		_button(footer, "回到行动结果", func() -> void: _navigate("scene"))


func _render_result() -> void:
	var feedback: Dictionary = response.observation.get("feedback", {})
	_label(_story, "刚刚发生", 17).modulate = Color("bfaa7b")
	_heading = _label(_story, str(feedback.get("title", "行动之后")), 28)
	_paragraph = _label(_story, str(feedback.get("compact_body", feedback.get("body", ""))), 21)
	for detail: Variant in feedback.get("summary_details", []).slice(0, 1):
		if str(detail) not in _paragraph.text:
			_label(_story, str(detail), 18)
	if delta_text != "":
		_label(_story, delta_text, 18).modulate = Color("dfc787")
	_button(_story, "继续旅途", func() -> void:
		pending_result = false
		family = ""
		offset = 0
		_render())
	if not feedback.get("details", []).is_empty() or str(feedback.get("body", "")) != _paragraph.text:
		_button(_story, "查看这次行动的完整记录", func() -> void: _navigate("journal"))


func _render_choices(rows: Array, empty_text: String) -> void:
	var visible_rows: Array = []
	var groups := {}
	for row: Dictionary in rows:
		var group := Presentation.family(row)
		if page == "scene" and response.get("observation", {}).get("situation_mode", false) and row.get("kind") == "travel":
			group = "选择去向"
		if group != "":
			if not groups.has(group):
				groups[group] = []
			groups[group].append(row)
		else:
			visible_rows.append(row)
	if family != "":
		_button(_choices, "返回 " + {"trade": "买卖", "rest": "休整", "talk": "交谈"}.get(page, "选择"), func() -> void:
			family = ""
			offset = 0
			_render())
		visible_rows = groups.get(family, [])
	else:
		for group: String in groups:
			if groups[group].size() == 1:
				visible_rows.append(groups[group][0])
			else:
				visible_rows.append({"group": group, "label": "%s · %d个选择" % [group, groups[group].size()]})
	if visible_rows.is_empty():
		_label(_choices, empty_text, 19)
		return
	var count := 4
	if page == "scene":
		count = 2 if get_viewport_rect().size.y < 850 else 3
		if rows.any(func(row: Dictionary) -> bool: return row.get("kind") == "combat_encounter"):
			count = 3
	offset = clampi(offset, 0, maxi(0, visible_rows.size() - 1))
	for row: Dictionary in visible_rows.slice(offset, offset + count):
		if row.has("group"):
			_button(_choices, str(row.label), func() -> void:
				family = str(row.group)
				offset = 0
				_render())
		else:
			_action_button(_choices, row)
	if visible_rows.size() > count:
		_pager(_choices, visible_rows.size(), count)


func _action_button(parent: Node, row: Dictionary) -> Button:
	var cost := str(row.get("cost", ""))
	var title := str(row.get("purpose", row.get("label", "选择")))
	var hint := str(row.get("hint", row.get("known_effect", "")))
	if row.kind == "travel":
		hint = str(row.get("label", ""))
	var enabled: bool = row.get("enabled", true)
	var text := title + ("  ·  " + cost if cost != "" else "")
	if not enabled:
		text += "\n" + str(row.get("blocked_reason", "当前无法执行"))
	elif hint != "" and row.kind != "combat_encounter":
		text += "\n" + hint
	var button := _button(parent, text, func() -> void:
		if row.kind == "combat_encounter" or row.get("requires_confirmation", false):
			_pending_choice_id = str(row.choice_id)
			_ask("act", title + "\n\n" + hint + "\n\n耗时：" + cost + "\n" + str(row.get("tradeoff", "")))
		else:
			_begin("act", {"choice_id": row.choice_id}))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 17)
	button.disabled = busy or not enabled
	button.tooltip_text = hint
	button.set_meta("choice_id", row.choice_id)
	return button


func _render_collection() -> void:
	var view: Dictionary = response.get("observation", {})
	var journal: Dictionary = view.get("equipment_journal", {})
	_heading = _label(_story, {"inventory": "行囊与穿戴", "character": "旅人", "journal": "旅途记录"}[page], 28)
	if page == "journal":
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_story.add_child(scroll)
		var log_box := VBoxContainer.new()
		log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(log_box)
		var feedback: Dictionary = view.get("feedback", {})
		_label(log_box, str(feedback.get("title", "")) + "\n" + str(feedback.get("body", "")), 20)
		for detail: Variant in feedback.get("details", []):
			_label(log_box, str(detail), 18)
		for notice: Dictionary in view.get("situation_notices", []):
			_label(log_box, str(notice.text), 18)
		for entry: Variant in view.get("knowledge", []).duplicate():
			_label(log_box, str(entry), 18)
		return
	if page == "character":
		var player: Dictionary = view.get("player", {})
		_label(_story, "力量 %s  敏捷 %s  体质 %s\n感知 %s  智慧 %s  魅力 %s" % [player.get("strength", 0), player.get("dexterity", 0), player.get("constitution", 0), player.get("perception", 0), player.get("wisdom", 0), player.get("charisma", 0)], 22)
		var features: Array = journal.get("features", [])
		for feature: Dictionary in features.slice(offset, offset + 3):
			_label(_story, str(feature.name) + " · " + str(feature.state) + "\n" + str(feature.description), 19)
		_pager(_story, features.size(), 3)
		return
	var items: Array = journal.get("items", [])
	for item: Dictionary in items.slice(offset, offset + 2):
		var item_header := HBoxContainer.new()
		_story.add_child(item_header)
		var icon_texture: Texture2D = EquipmentPanel._icon(str(item.definition_id))
		if icon_texture != null:
			var icon := TextureRect.new()
			icon.texture = icon_texture
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(40, 40)
			item_header.add_child(icon)
		_label(item_header, "%s × %d%s" % [item.name, item.quantity, " · 已穿戴" if item.equipped != "" else ""], 22)
		_label(_story, str(item.description), 17)
		var actions := HBoxContainer.new()
		_story.add_child(actions)
		for choice: Dictionary in response.get("choices", []):
			if (str(choice.get("item_instance_id", "")) == str(item.id) and str(choice.id).begins_with("equip:")) or (item.equipped != "" and str(choice.id).begins_with("unequip:") and str(choice.label).contains(str(item.name))):
				_action_button(actions, choice)
	if items.is_empty():
		_label(_story, "行囊暂时没有物品。", 20)
	_pager(_story, items.size(), 2)


func _pager(parent: Node, total: int, count: int) -> void:
	if total <= count:
		return
	var controls := HBoxContainer.new()
	parent.add_child(controls)
	var previous := _button(controls, "上一页", func() -> void:
		offset = maxi(0, offset - count)
		_render())
	previous.disabled = busy or offset == 0
	_label(controls, "%d–%d / %d" % [offset + 1, mini(total, offset + count), total], 16)
	var next := _button(controls, "下一页", func() -> void:
		offset += count
		_render())
	next.disabled = busy or offset + count >= total


func _navigate(target: String) -> void:
	if busy:
		return
	page = target
	family = ""
	offset = 0
	_render()


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = busy or response.is_empty()
	button.pressed.connect(action, CONNECT_DEFERRED)
	parent.add_child(button)
	return button


func _status_text() -> String:
	var view: Dictionary = response.get("observation", {})
	var player: Dictionary = view.get("player", {})
	var time: Dictionary = view.get("time", {})
	var hunger := str({"none": "不饿", "low": "微饿", "medium": "饥饿", "high": "很饿", "extreme": "极饿，请进食"}.get(player.get("hunger", "none"), "不饿"))
	return "第%d天  %02d:%02d     健康 %d   疲劳 %d/10   %s     食物 %d   铜币 %d" % [time.get("day", 1), time.get("hour", 8), time.get("minute", 0), player.get("health", 100), player.get("fatigue", 0), hunger, player.get("food_count", 0), player.get("coins", 0)]


static func _changes(before: Dictionary, after: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in ["health", "fatigue", "coins", "food_count"]:
		if before.get(key) != after.get(key):
			parts.append("%s %s → %s" % [{"health": "健康", "fatigue": "疲劳", "coins": "铜币", "food_count": "食物"}[key], before.get(key, 0), after.get(key, 0)])
	return "　".join(parts)
