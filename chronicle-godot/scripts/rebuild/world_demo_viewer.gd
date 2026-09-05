extends "res://scripts/rebuild/v5_live_location_viewer.gd"
## Generated-world UI. The legacy viewer remains a synchronous regression fixture.

const Graph = preload("res://scripts/rebuild/region_graph.gd")
const REED_ART = preload("res://art/environments/reed_bank_landing_v1.png")
const DEFAULT_SAVE := "user://world_demo/manual.json"

@export var save_path: String = DEFAULT_SAVE
@export var initial_seed: int = 81001
var busy := false
var last_operation: Dictionary = {}
var _worker: Thread
var _operation_name := ""
var _disabled_buttons: Dictionary = {}
var _save_dialog: ConfirmationDialog
var _load_dialog: ConfirmationDialog
var _quit_dialog: ConfirmationDialog
var _quit_after_save := false
var _status: Label
var _graph: Control
var _region_heading: Label
var _road_text: Label
var _picture: TextureRect
var _picture_caption: Label
var _seed_input: SpinBox
var _startup := true
var _startup_message := ""


func _ready() -> void:
	super._ready()
	_install_save_controls()
	_install_region_page()
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_request_quit)
	refresh_view(current_view_data)
	_status.text = _startup_message
	if current_view_data.get("ready", false):
		print("CHRONICLE_WORLD_READY seed=%d location=%s" % [
			current_view_data.region_map.get("seed", 0), current_view_data.location.id])


func restart_session() -> void:
	if busy:
		return
	_playtest_end_state = ""
	completion_dialog.hide()
	failure_dialog.hide()
	restart_dialog.hide()
	if _startup:
		_startup = false
		if FileAccess.file_exists(save_path):
			var restored: Dictionary = view_model.load_from_path(save_path)
			if restored.get("success", false):
				_startup_message = "已继续上次保存的世界。"
				refresh_view()
				return
			_startup_message = "存档无法读取，原文件已保留。已进入新世界；请勿覆盖原存档。错误：" + str(restored.get("error", "unknown"))
		view_model.start({"scenario": "generated_network", "challenge_seed_override": initial_seed})
		refresh_view()
	else:
		_begin_operation("start", [{"scenario": "generated_network", "challenge_seed_override": int(_seed_input.value)}])


func refresh_view(projected: Dictionary = {}) -> void:
	if busy:
		return
	super.refresh_view(projected)
	brand_subtitle.text = "北境三镇 / 世界原型"
	# The generated-world observer prompt is background help, not a quest objective.
	(surface.scene_record as RichTextLabel).text += "\n\n[b]区域概况[/b]\n" + goal_summary.text
	goal_progress.hide()
	goal_title.hide()
	goal_summary.hide()
	restart_button.text = "新世界"
	restart_button.custom_minimum_size.x = 80
	if _graph == null:
		return
	var region: Dictionary = current_view_data.get("region_map", {})
	_graph.show_region(region)
	var names := {}
	for site: Dictionary in region.get("sites", []):
		names[site.id] = site.name
	_region_heading.text = "北境道路 · 种子 %d\n当前位置：%s" % [region.get("seed", 0), location_title.text]
	var roads: Array[String] = []
	for road: Dictionary in region.get("roads", []):
		roads.append("%s ↔ %s    %d 小时" % [names.get(road.from, "未知"), names.get(road.to, "未知"), road.hours])
	_road_text.text = "\n".join(roads) + "\n\n线路示意，不代表真实方位或比例。\n回到「现场」选择路线；查看区域不推进时间。"
	var at_reed: bool = region.get("current_settlement_id", "") == "generated_settlement.reed_bay"
	_picture.visible = at_reed
	_picture_caption.text = ("苇岸水边 · 地点美术样例\n静态环境画，不代表实时天气、人物或货物数量。"
		if at_reed else "%s\n此处的地点画面尚未制作。" % location_title.text)


func _begin_operation(method: String, arguments: Array = []) -> Dictionary:
	if busy:
		return {"success": false, "error": "operation_in_progress"}
	busy = true
	_operation_name = method
	_disabled_buttons.clear()
	for node: Node in find_children("*", "BaseButton", true, false):
		_disabled_buttons[node] = node.disabled
		node.disabled = true
	_status.text = "正在处理，请稍候。此时不会接受第二次行动。"
	_worker = Thread.new()
	var error := _worker.start(_execute_model.bind(method, arguments))
	if error != OK:
		_worker = null
		_restore_input()
		_status.text = "无法启动结算，未执行行动。错误：%d" % error
		return {"success": false, "error": "worker_start_failed"}
	return {"success": true, "pending": true}


func _execute_model(method: String, arguments: Array) -> Dictionary:
	# This worker exclusively owns the model until joined; the UI uses its cached view.
	var began := Time.get_ticks_usec()
	var result: Dictionary = view_model.callv(method, arguments)
	var settled := Time.get_ticks_usec()
	var projected: Dictionary = view_model.build_view_data()
	return {"result": result, "view": projected, "method": method,
		"operation_ms": (settled - began) / 1000.0,
		"projection_ms": (Time.get_ticks_usec() - settled) / 1000.0}


func _process(_delta: float) -> void:
	if _worker == null or _worker.is_alive():
		return
	last_operation = _worker.wait_to_finish()
	_worker = null
	_restore_input()
	refresh_view(last_operation.view)
	var result: Dictionary = last_operation.result
	if not result.get("success", false):
		_status.text = "未能完成：%s。未自动重试，请先核对现场与记录。" % str(result.get("error", result.get("error_reason", "unknown")))
	elif _operation_name == "save_to_path":
		_status.text = "世界已保存。下次启动会从这里继续。"
		if _quit_after_save:
			get_tree().quit()
	elif _operation_name == "load_from_path":
		_status.text = "已恢复保存时的地点、时间与世界状态。"
	else:
		_status.text = "已结算。行动结果见「现场」，完整过程见「记录」。"
	_quit_after_save = false


func _restore_input() -> void:
	busy = false
	for button: BaseButton in _disabled_buttons:
		if is_instance_valid(button):
			button.disabled = bool(_disabled_buttons[button])
	_disabled_buttons.clear()


func _exit_tree() -> void:
	if _worker != null:
		_worker.wait_to_finish()
		_worker = null
	get_tree().auto_accept_quit = true


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_request_quit()
		get_viewport().set_input_as_handled()


func _request_quit() -> void:
	if busy:
		_status.text = "结算尚未结束，请稍候再退出。"
		return
	_quit_dialog.popup_centered(Vector2i(580, 180))
	_quit_dialog.get_cancel_button().grab_focus()


func _save_and_quit(_action: StringName) -> void:
	_quit_dialog.hide()
	_quit_after_save = true
	var started := _begin_operation("save_to_path", [save_path, true])
	if not started.get("success", false):
		_quit_after_save = false


func perform_action(id: String) -> Dictionary:
	return _begin_operation("perform_action", [id])


func perform_travel(id: String) -> Dictionary:
	return _begin_operation("perform_travel", [id])


func perform_challenge(id: String) -> Dictionary:
	return _begin_operation("perform_challenge", [id])


func perform_combat_encounter(id: String, metadata: Dictionary = {}) -> Dictionary:
	return _begin_operation("perform_combat_encounter", [id, metadata])


func perform_return_echo(id: String) -> Dictionary:
	return _begin_operation("perform_return_echo", [id])


func perform_investigation(id: String) -> Dictionary:
	return _begin_operation("perform_investigation", [id])


func advance_time() -> Dictionary:
	return _begin_operation("advance_time", [1])


func wait_until_north_quay_ferry() -> Dictionary:
	return _begin_operation("wait_until_north_quay_ferry")


func _install_save_controls() -> void:
	var header := restart_button.get_parent()
	for item: Array in [["SaveWorld", "保存", _request_save], ["LoadWorld", "读档", _request_load]]:
		var button := Button.new()
		button.name = item[0]
		button.text = item[1]
		button.pressed.connect(item[2])
		header.add_child(button)
		SharedInterfaceStyle.apply_command_button(button)
	_status = Label.new()
	_status.name = "WorldOperationStatus"
	_status.custom_minimum_size.y = 20
	_status.add_theme_font_size_override("font_size", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$Margin/RootLayout.add_child(_status)
	$Margin/RootLayout.move_child(_status, 1)
	_save_dialog = _confirmation("覆盖世界存档？", "将覆盖上次手动保存。当前世界的全部状态会写入同一个存档。", "覆盖存档")
	_save_dialog.confirmed.connect(func() -> void: _begin_operation("save_to_path", [save_path, true]))
	_load_dialog = _confirmation("恢复保存的世界？", "未保存的行动将丢失。恢复保存时的地点、时间、人物和物资。", "恢复存档")
	_load_dialog.confirmed.connect(func() -> void: _begin_operation("load_from_path", [save_path]))
	_quit_dialog = _confirmation("退出 Chronicle？", "未保存的行动会丢失。\n「保存并退出」将覆盖上次手动存档；存档失败时不会退出。", "退出而不保存")
	_quit_dialog.add_button("保存并退出", false, "save_exit")
	_quit_dialog.confirmed.connect(func() -> void: get_tree().quit())
	_quit_dialog.custom_action.connect(_save_and_quit)
	restart_dialog.title = "创建新世界？"
	restart_dialog.dialog_text = ""
	restart_dialog.get_ok_button().text = "创建新世界"
	var new_world_form := VBoxContainer.new()
	new_world_form.add_theme_constant_override("separation", 16)
	restart_dialog.add_child(new_world_form)
	var explanation := Label.new()
	explanation.text = "未保存的行动将丢失。已有存档不会删除或覆盖。\n种子相同会生成相同的初始区域。"
	new_world_form.add_child(explanation)
	_seed_input = SpinBox.new()
	_seed_input.min_value = 1
	_seed_input.max_value = 2147483647
	_seed_input.value = initial_seed
	_seed_input.prefix = "世界种子 "
	new_world_form.add_child(_seed_input)


func _confirmation(title_text: String, message: String, action: String) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title_text
	dialog.dialog_text = message
	dialog.get_ok_button().text = action
	dialog.get_cancel_button().text = "取消"
	add_child(dialog)
	return dialog


func _request_save() -> void:
	if busy:
		return
	if FileAccess.file_exists(save_path):
		_save_dialog.popup_centered(Vector2i(520, 180))
		_save_dialog.get_cancel_button().grab_focus()
	else:
		_begin_operation("save_to_path", [save_path, false])


func _request_load() -> void:
	if busy:
		return
	if not FileAccess.file_exists(save_path):
		_status.text = "还没有保存的世界。先使用「保存」。"
		return
	_load_dialog.popup_centered(Vector2i(520, 180))
	_load_dialog.get_cancel_button().grab_focus()


func _install_region_page() -> void:
	var tabs: TabContainer = surface.tabs
	tabs.use_hidden_tabs_for_min_size = false
	var page := HBoxContainer.new()
	page.name = "区域"
	page.add_theme_constant_override("separation", 24)
	tabs.add_child(page)
	tabs.move_child(page, 1)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.5
	page.add_child(left)
	_region_heading = Label.new()
	_region_heading.add_theme_font_size_override("font_size", 22)
	left.add_child(_region_heading)
	_graph = Graph.new()
	left.add_child(_graph)
	_road_text = Label.new()
	_road_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_road_text.add_theme_font_size_override("font_size", 16)
	left.add_child(_road_text)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(right)
	_picture = TextureRect.new()
	_picture.texture = REED_ART
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picture.custom_minimum_size.y = 240
	right.add_child(_picture)
	_picture_caption = Label.new()
	_picture_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_picture_caption.add_theme_font_size_override("font_size", 14)
	right.add_child(_picture_caption)
