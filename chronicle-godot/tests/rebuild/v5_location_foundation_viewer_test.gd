extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_location_foundation_viewer.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. 独立 rebuild viewer 场景可加载")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var scene_title := viewer.get_node("%SceneTitle") as Label
	var scene_text := viewer.get_node("%SceneText") as RichTextLabel
	var character_summary := viewer.get_node("%CharacterSummary") as RichTextLabel
	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer
	var location_buttons := viewer.get_node("%LocationButtons") as FlowContainer
	var modal_body := viewer.get_node("%ModalBody") as RichTextLabel

	_check(
		"阿尔维斯" in character_summary.text
		and "湖湾镇" in scene_title.text
		and "老陈铺子" in scene_text.text,
		"2. 初始局面显示角色、湖湾镇叙述和地点切面"
	)
	_check(
		_button_texts(action_buttons).find("[对话] 走近陈米") >= 0,
		"3. 初始行动包含走近陈米"
	)

	viewer.perform_action("approach_chen_mi")
	await process_frame
	_check(
		"陈米" in scene_title.text
		and _button_texts(action_buttons).find("[普通] 给她食物") >= 0
		and _button_texts(action_buttons).find("[对话] 问粮从哪来的") >= 0
		and _button_texts(action_buttons).find("[普通] 装作没看见") >= 0,
		"4. 走近陈米后中央叙述和底部行动切换"
	)

	viewer.perform_action("inspect_price_notice")
	await process_frame
	_check(
		"涨价告示" in scene_title.text
		and _clue_text(viewer).find("[线索] 粮价明天再涨一次") >= 0,
		"5. 查看涨价告示后新增粮价线索"
	)

	viewer.open_clue_card("price_rise_tomorrow")
	await process_frame
	_check(
		"线索：粮价明天再涨一次" in scene_text.text
		and "来源" in scene_text.text
		and "可信度" in scene_text.text
		and "去市场打听粮价 1小时" in scene_text.text,
		"6. 点击线索可打开线索行动卡"
	)

	viewer.perform_action("ask_market_grain_price")
	await process_frame
	_check(
		"市场粮价" in scene_title.text
		and "北路商队迟了三天" in region_status.text
		and _clue_text(viewer).find("[线索] 北路商队迟到") >= 0,
		"7. 去市场打听粮价后更新地区状态并新增线索"
	)

	viewer.perform_action("go_abandoned_granary")
	await process_frame
	_check(
		"废弃粮仓" in scene_title.text
		and "灰白色粮粉" in scene_text.text
		and _button_texts(location_buttons).find("湖湾镇") >= 0
		and _button_texts(location_buttons).find("废弃粮仓") >= 0,
		"8. 前往废弃粮仓后切换地点且右侧仍保留地点节点"
	)

	viewer.perform_action("stay_one_month")
	await process_frame
	viewer.open_life_panel()
	await process_frame
	_check(
		viewer.is_menu_modal_open()
		and "在湖湾镇停留一月" in modal_body.text,
		"9. 长期停留后生涯面板写入已完成经历"
	)
	_check(
		viewer.state.get_action_history().size() >= 5,
		"10. 行动历史记录最小交互闭环"
	)

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


func _clue_text(viewer: Node) -> String:
	var clue_buttons := viewer.get_node("%ClueButtons")
	return _button_texts(clue_buttons)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LOCATION VIEWER LOOP RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 LOCATION VIEWER LOOP FAIL] " + failure)
		print("[V5 LOCATION VIEWER LOOP RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 LOCATION VIEWER LOOP PASS] " + message)
	else:
		failures.append(message)
