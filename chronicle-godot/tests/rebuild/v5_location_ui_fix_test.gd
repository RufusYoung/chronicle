extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_location_foundation_viewer.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. UI fix viewer 场景可加载")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var character_summary := viewer.get_node("%CharacterSummary") as RichTextLabel
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer
	var scene_title := viewer.get_node("%SceneTitle") as Label
	var modal_title := viewer.get_node("%ModalTitle") as Label
	var modal_body := viewer.get_node("%ModalBody") as RichTextLabel

	var character_text := character_summary.text
	_check(
		_ordered(character_text, ["生命：32 / 32", "精力：48 / 60", "健康：76 / 100", "理智：67 / 100", "饥饿：28 / 100"])
		and "健康：76 / 100　无明显伤势" in character_text
		and "理智：67 / 100　夜里睡得不深" in character_text
		and "伤势：" not in character_text
		and "精神：" not in character_text,
		"2. 左侧状态栏使用新顺序，并把伤势/精神并入健康/理智"
	)

	viewer.open_location("market")
	await process_frame
	_check(
		"[线索] 去市场打听粮价 1小时" in _button_texts(action_buttons)
		and "[普通] 观察买粮的人" in _button_texts(action_buttons),
		"3. 切换到市场后行动选项刷新为市场行动"
	)

	viewer.open_location("abandoned_granary")
	await process_frame
	_check(
		"[线索] 查看灰白粮粉" in _button_texts(action_buttons)
		and "[危险] 进入粮仓" in _button_texts(action_buttons),
		"4. 切换到废弃粮仓后行动选项刷新为粮仓行动"
	)

	viewer.open_location("lake_town")
	await process_frame
	_check(
		"[对话] 走近陈米" in _button_texts(action_buttons)
		and "[危险] 前往废弃粮仓 半日" in _button_texts(action_buttons),
		"5. 切回湖湾镇后恢复湖湾镇初始行动"
	)

	viewer.perform_action("inspect_price_notice")
	viewer.open_life_panel()
	await process_frame
	_check(
		viewer.is_menu_modal_open()
		and modal_title.text == "生涯"
		and scene_title.text == "涨价告示"
		and viewer.state.has_clue("price_rise_tomorrow"),
		"6. 顶部菜单打开弹窗且不替换主界面地点局面"
	)

	var before_location: String = viewer.state.get_current_location_id()
	var before_history_size: int = viewer.state.get_action_history().size()
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	viewer._unhandled_input(event)
	await process_frame
	_check(
		not viewer.is_menu_modal_open()
		and viewer.state.get_current_location_id() == before_location
		and viewer.state.get_action_history().size() == before_history_size
		and viewer.state.has_clue("price_rise_tomorrow"),
		"7. Esc 关闭弹窗并保留地点、线索和行动历史"
	)

	viewer.open_character_panel()
	await process_frame
	_check(
		viewer.is_menu_modal_open()
		and modal_title.text == "角色"
		and "显示角色详情。" in modal_body.text
		and "力量 7" in modal_body.text,
		"8. 角色按钮弹窗包含角色详情"
	)
	viewer.close_menu_modal()
	await process_frame
	_check(not viewer.is_menu_modal_open(), "9. 关闭按钮逻辑可返回主界面")

	viewer.queue_free()
	await process_frame
	_finish()


func _button_texts(container: Node) -> String:
	var rows: Array[String] = []
	for child: Node in container.get_children():
		if child is Button:
			rows.append((child as Button).text)
		elif child is Label:
			rows.append((child as Label).text)
	return "\n".join(rows)


func _ordered(text: String, tokens: Array[String]) -> bool:
	var cursor := -1
	for token: String in tokens:
		var index := text.find(token)
		if index <= cursor:
			return false
		cursor = index
	return true


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LOCATION UI FIX RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 LOCATION UI FIX FAIL] " + failure)
		print("[V5 LOCATION UI FIX RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 LOCATION UI FIX PASS] " + message)
	else:
		failures.append(message)
