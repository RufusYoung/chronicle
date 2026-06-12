extends Control

const DEFAULT_REGION_JSON := "res://data/regions/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖森林带/镜湖森林带.json"
const WORLD_GENERATION_PATH := "res://scripts/gen/world_generation_v03.gd"

@onready var story_box: RichTextLabel = $StoryBox
@onready var choices_box: VBoxContainer = $ChoicesBox
@onready var btn_restart: Button = $Btns/RestartBtn
@onready var btn_new_run: Button = $Btns/NewRunBtn
@onready var btn_continue: Button = $Btns/ContinueBtn
@onready var btn_tool_map: Button = get_node_or_null("../Journey/Button")
@onready var btn_tool_log: Button = get_node_or_null("../Journey/Button2")
@onready var btn_tool_growth: Button = get_node_or_null("../Journey/Button3")
@onready var btn_tool_bag: Button = get_node_or_null("../Journey/Button4")
@onready var btn_tool_system: Button = get_node_or_null("../Journey/Button5")
@onready var hp_bar: ProgressBar = get_node_or_null("../topbar/Status/ProgressBar1")
@onready var sanity_bar: ProgressBar = get_node_or_null("../topbar/Status/ProgressBar2")
@onready var food_bar: ProgressBar = get_node_or_null("../topbar/Status/ProgressBar3")
@onready var fatigue_bar: ProgressBar = get_node_or_null("../topbar/Status/ProgressBar4")
@onready var hp_label: Label = get_node_or_null("../topbar/Status/ProgressBar1/CenterContainer/Label")
@onready var sanity_label: Label = get_node_or_null("../topbar/Status/ProgressBar2/CenterContainer/Label")
@onready var food_label: Label = get_node_or_null("../topbar/Status/ProgressBar3/CenterContainer/Label")
@onready var fatigue_label: Label = get_node_or_null("../topbar/Status/ProgressBar4/CenterContainer/Label")
@onready var str_label: Label = get_node_or_null("../topbar/attribute/lable1/TextureRect")
@onready var dex_label: Label = get_node_or_null("../topbar/attribute/lable1/TextureRect2")
@onready var int_label: Label = get_node_or_null("../topbar/attribute/lable1/TextureRect3")
@onready var cha_label: Label = get_node_or_null("../topbar/attribute/lable2/TextureRect")
@onready var con_label: Label = get_node_or_null("../topbar/attribute/lable2/TextureRect2")
@onready var wis_label: Label = get_node_or_null("../topbar/attribute/lable2/TextureRect3")

var world: Node
var _last_region_id: String = ""
var _last_action_ms: int = 0

var _goal_box: RichTextLabel
var _action_scroll: ScrollContainer
var _action_root: VBoxContainer
var _show_more_actions: bool = false

func _ready() -> void:
	story_box.bbcode_enabled = true
	story_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_box.scroll_active = true
	story_box.mouse_filter = Control.MOUSE_FILTER_STOP
	story_box.gui_input.connect(_on_story_box_input)

	if fatigue_bar != null:
		fatigue_bar.visible = false
	if fatigue_label != null:
		fatigue_label.visible = false

	btn_restart.pressed.connect(_on_restart_pressed)
	btn_new_run.pressed.connect(_on_new_run_pressed)
	btn_continue.pressed.connect(_on_continue_pressed)
	_setup_bottom_tool_buttons()

	_setup_goal_box()
	_setup_action_board()
	_start_new_run()

func _setup_bottom_tool_buttons() -> void:
	_bind_tool_button(btn_tool_map, "地图", "sys.v02.tool.map")
	_bind_tool_button(btn_tool_log, "日志", "sys.v02.tool.log")
	_bind_tool_button(btn_tool_growth, "成长", "sys.v02.tool.growth")
	_bind_tool_button(btn_tool_bag, "背包", "sys.v02.tool.inventory")
	_bind_tool_button(btn_tool_system, "系统", "sys.v02.tool.system")

func _bind_tool_button(btn: Button, title: String, action_id: String) -> void:
	if btn == null:
		return
	btn.visible = true
	btn.disabled = false
	btn.text = title
	btn.pressed.connect(_on_tool_pressed.bind(action_id))

func _setup_goal_box() -> void:
	_goal_box = RichTextLabel.new()
	_goal_box.bbcode_enabled = true
	_goal_box.fit_content = false
	_goal_box.scroll_active = false
	_goal_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal_box.offset_left = 60
	_goal_box.offset_top = 4
	_goal_box.offset_right = 628
	_goal_box.offset_bottom = 108
	add_child(_goal_box)
	move_child(_goal_box, 0)

	# Keep text/story area below goal box to avoid overlap.
	story_box.offset_top = 112
	story_box.offset_bottom = 456

func _setup_action_board() -> void:
	for c in choices_box.get_children():
		c.queue_free()
	_action_scroll = ScrollContainer.new()
	_action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choices_box.add_child(_action_scroll)

	_action_root = VBoxContainer.new()
	_action_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_action_root.add_theme_constant_override("separation", 6)
	_action_scroll.add_child(_action_root)

func _start_new_run() -> void:
	story_box.clear()
	_show_more_actions = false
	if world != null and is_instance_valid(world):
		world.queue_free()

	var world_script := load(WORLD_GENERATION_PATH)
	if world_script == null:
		_append_line("[color=crimson]世界脚本加载失败：[/color] %s" % WORLD_GENERATION_PATH)
		btn_continue.disabled = true
		return
	world = world_script.new()
	add_child(world)

	if not FileAccess.file_exists(DEFAULT_REGION_JSON):
		_append_line("[color=crimson]地区文件缺失：[/color] %s" % DEFAULT_REGION_JSON)
		btn_continue.disabled = true
		return

	world.bootstrap(DEFAULT_REGION_JSON, true)
	_last_region_id = world.current_region_id
	btn_continue.disabled = false

	_append_line("[color=gray]新旅程已开始。点击“继续”推进回合。[/color]")
	_on_continue_pressed()

func _on_story_box_input(ev: InputEvent) -> void:
	if world == null:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if not world.has_pending_choice():
			_on_continue_pressed()

func _on_restart_pressed() -> void:
	if _action_guard():
		return
	_start_new_run()

func _on_new_run_pressed() -> void:
	if _action_guard():
		return
	_start_new_run()

func _on_tool_pressed(action_id: String) -> void:
	if _action_guard():
		return
	if world == null or not world.has_method("apply_system_choice"):
		return
	var out_any: Variant = world.apply_system_choice(action_id)
	if out_any is Dictionary:
		var out: Dictionary = out_any as Dictionary
		var t: String = String(out.get("text", ""))
		if t != "":
			_append_line(t)
	_refresh_hud()
	_render_goal_panel()
	_render_action_board()

func _on_continue_pressed() -> void:
	if _action_guard():
		return
	if world == null:
		return

	_show_more_actions = false
	var snap: Dictionary = world.produce_snapshot()
	_render_snapshot(snap)
	_refresh_hud()
	_render_action_board()

func _on_choice_pressed(choice_id: String) -> void:
	if _action_guard():
		return
	if world == null:
		return

	var out: Dictionary = {}
	if choice_id.begins_with("sys.") and world.has_method("apply_system_choice"):
		var out_any: Variant = world.apply_system_choice(choice_id)
		if out_any is Dictionary:
			out = out_any as Dictionary
	else:
		out = world.apply_choice(choice_id)

	var txt: String = String(out.get("text", ""))
	if txt != "":
		_append_line(txt)

	if world.current_region_id != _last_region_id:
		var region_name: String = String(world.current_region.get("name", world.current_region_id))
		_append_line("[b]你抵达：%s[/b]" % region_name)
		_last_region_id = world.current_region_id

	_refresh_hud()
	_render_goal_panel()
	_render_action_board()

func _on_toggle_more_actions() -> void:
	_show_more_actions = not _show_more_actions
	_render_action_board()

func _render_snapshot(snap: Dictionary) -> void:
	var lines: Array[String] = []
	var now_region: String = String(snap.get("region_id", world.current_region_id))
	if now_region != _last_region_id:
		var region_name: String = String(world.current_region.get("name", now_region))
		lines.append("[b]你抵达：%s[/b]" % region_name)
		_last_region_id = now_region

	var day: int = int(snap.get("day", 1))
	var hour: int = int(snap.get("hour", 0))
	var tod: String = String(snap.get("time_of_day", "day"))
	lines.append("[color=gray]第%d天 %02d:00（%s）[/color]" % [day, hour, tod])

	if snap.has("weather") and snap["weather"] is Dictionary:
		var w: Dictionary = snap["weather"] as Dictionary
		var wn: String = String(w.get("name", ""))
		if wn != "":
			lines.append("[i]天气：%s[/i]" % wn)

	var ev_text: String = String(snap.get("event_text", ""))
	if ev_text != "":
		lines.append(ev_text)

	if lines.is_empty():
		lines.append("时间静静流逝。")

	_append_line("\n".join(lines))
	_render_goal_panel()

func _render_goal_panel() -> void:
	if _goal_box == null:
		return
	if world == null or not world.has_method("get_goal_panel_v02"):
		_goal_box.text = "[b]当前目标[/b]\n暂无目标信息。"
		return
	var p_any: Variant = world.get_goal_panel_v02()
	if not (p_any is Dictionary):
		_goal_box.text = "[b]当前目标[/b]\n暂无目标信息。"
		return
	var p: Dictionary = p_any as Dictionary
	var leads_any: Variant = p.get("leads", [])
	var reminders_any: Variant = p.get("reminders", [])
	var leads: Array = leads_any as Array if leads_any is Array else []
	var reminders: Array = reminders_any as Array if reminders_any is Array else []

	var lines: Array[String] = []
	lines.append("[b]你在：[/b] %s" % String(p.get("location", "未知地点")))
	if not leads.is_empty():
		lines.append("[b]当前线索：[/b]")
		for l in leads:
			lines.append("- %s" % String(l))
	if not reminders.is_empty():
		lines.append("[b]当前挂念：[/b]")
		for r in reminders:
			lines.append("- %s" % String(r))
	lines.append("[b]活跃线程：[/b] %s" % String(p.get("thread", "无")))
	var ro: String = String(p.get("recent_outcome", ""))
	if ro != "":
		lines.append("[b]可见回流：[/b] %s" % ro)
	_goal_box.text = "\n".join(lines)

func _render_action_board() -> void:
	if _action_root == null:
		return
	for c in _action_root.get_children():
		c.queue_free()

	if world == null:
		return

	var board: Dictionary = {}
	if world.has_method("get_action_board"):
		var b_any: Variant = world.get_action_board()
		if b_any is Dictionary:
			board = b_any as Dictionary
	if board.is_empty():
		return

	_render_board_quick_row(board.get("quick", []))

	var mode: String = String(board.get("mode", "free"))
	if mode == "event":
		_render_board_header("事件阶段")
		_render_info_box(String(board.get("event_header", "当前事件待决，请先完成本阶段。")))
		_render_action_list(board.get("actions", []))
		_render_more_actions(board.get("more_actions", []))
		return

	_render_board_header("自由行动")
	_render_guidance_summary(board.get("guidance", {}))
	_render_action_list(board.get("actions", []))
	_render_more_actions(board.get("more_actions", []))

func _render_board_header(title: String) -> void:
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 18)
	_action_root.add_child(head)

func _render_info_box(text: String) -> void:
	if text == "":
		return
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0, 64)
	info.text = text
	_action_root.add_child(info)

func _render_board_quick_row(arr_any: Variant) -> void:
	if not (arr_any is Array):
		return
	var arr: Array = arr_any as Array
	if arr.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_action_root.add_child(row)
	for d_any in arr:
		if not (d_any is Dictionary):
			continue
		var d: Dictionary = d_any as Dictionary
		var cid: String = String(d.get("id", ""))
		if cid == "":
			continue
		var btn := Button.new()
		btn.text = String(d.get("title", "入口"))
		btn.custom_minimum_size = Vector2(120, 36)
		btn.pressed.connect(_on_choice_pressed.bind(cid))
		row.add_child(btn)

func _render_guidance_summary(g_any: Variant) -> void:
	if not (g_any is Dictionary):
		return
	var g: Dictionary = g_any as Dictionary
	var percepts_any: Variant = g.get("percepts", [])
	var reminders_any: Variant = g.get("reminders", [])
	var percepts: Array = percepts_any as Array if percepts_any is Array else []
	var reminders: Array = reminders_any as Array if reminders_any is Array else []
	var lines: Array[String] = []
	if not percepts.is_empty():
		lines.append("[b]你注意到：[/b]")
		for p in percepts:
			lines.append("- " + String(p))
	if not reminders.is_empty():
		lines.append("[b]你想起：[/b]")
		for r in reminders:
			lines.append("- " + String(r))
	_render_info_box("\n".join(lines))

func _render_action_list(arr_any: Variant) -> void:
	if not (arr_any is Array):
		return
	for d_any in (arr_any as Array):
		if not (d_any is Dictionary):
			continue
		var d: Dictionary = d_any as Dictionary
		var cid: String = String(d.get("id", ""))
		if cid == "":
			continue
		var btn := Button.new()
		btn.text = _action_button_text(d)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 72)
		btn.disabled = bool(d.get("disabled", false))
		btn.pressed.connect(_on_choice_pressed.bind(cid))
		_action_root.add_child(btn)

func _render_more_actions(arr_any: Variant) -> void:
	if not (arr_any is Array):
		return
	var arr: Array = arr_any as Array
	if arr.is_empty():
		return
	var toggle := Button.new()
	toggle.text = "更多行动（%d）" % arr.size() if not _show_more_actions else "收起更多"
	toggle.custom_minimum_size = Vector2(0, 42)
	toggle.pressed.connect(_on_toggle_more_actions)
	_action_root.add_child(toggle)
	if not _show_more_actions:
		return
	_render_action_list(arr)

func _action_button_text(d: Dictionary) -> String:
	var title: String = String(d.get("title", String(d.get("text", "行动"))))
	var why: String = String(d.get("why", ""))
	var cost: String = String(d.get("cost", ""))
	var direction: String = String(d.get("direction", ""))
	var lines: Array[String] = [title]
	if why != "" or cost != "" or direction != "":
		var why_txt: String = why if why != "" else "无"
		var cost_txt: String = cost if cost != "" else "无"
		var dir_txt: String = direction if direction != "" else "无"
		lines.append("缘由：%s｜代价：%s｜走向：%s" % [why_txt, cost_txt, dir_txt])
	return "\n".join(lines)

func _refresh_hud() -> void:
	if world == null or not world.has_method("get_player_panel"):
		return
	if btn_tool_log != null and world.has_method("get_backlog_count"):
		btn_tool_log.text = "日志(%d)" % int(world.get_backlog_count())
	var panel_any: Variant = world.get_player_panel()
	if not (panel_any is Dictionary):
		return
	var p: Dictionary = panel_any as Dictionary

	_set_bar(hp_bar, hp_label, int(p.get("hp", 0)), int(p.get("hp_max", 100)))
	_set_bar(sanity_bar, sanity_label, int(p.get("sanity", 0)), int(p.get("sanity_max", 100)))
	_set_bar(food_bar, food_label, int(p.get("energy", p.get("hunger", p.get("food", 0)))), int(p.get("energy_max", p.get("hunger_max", p.get("food_max", 36)))))
	if food_label != null:
		food_label.text = "体力 %d/%d（口粮 %d）" % [
			int(p.get("energy", p.get("hunger", p.get("food", 0)))),
			int(p.get("energy_max", p.get("hunger_max", p.get("food_max", 36)))),
			int(p.get("ration", 0))
		]

	if str_label != null:
		str_label.text = str(int(p.get("str", 10)))
	if dex_label != null:
		dex_label.text = str(int(p.get("dex", 10)))
	if int_label != null:
		int_label.text = str(int(p.get("int", 10)))
	if cha_label != null:
		cha_label.text = str(int(p.get("cha", 10)))
	if con_label != null:
		con_label.text = str(int(p.get("con", 10)))
	if wis_label != null:
		wis_label.text = str(int(p.get("wis", 10)))

func _set_bar(bar: ProgressBar, label: Label, val: int, max_val: int) -> void:
	if bar != null:
		bar.max_value = max(1, max_val)
		bar.value = clamp(val, 0, max_val)
	if label != null:
		label.text = "%d/%d" % [val, max_val]

func _append_line(s: String) -> void:
	story_box.append_text(s + "\n\n")
	story_box.scroll_to_line(story_box.get_line_count())

func _action_guard() -> bool:
	var now: int = Time.get_ticks_msec()
	if now - _last_action_ms < 80:
		return true
	_last_action_ms = now
	return false
