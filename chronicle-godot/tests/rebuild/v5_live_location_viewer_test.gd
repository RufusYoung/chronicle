extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const GIVE_FOOD_ACTION := "give_food_to_hungry_person:chen_mi"
const READ_NOTICE_ACTION := (
	"read_visible_readable_object:old_chen_shop_price_notice"
)
const INSPECT_TRACE_ACTION := "inspect_visible_trace:gray_grain_powder"
const GIVE_WEN_JIAN_FOOD := (
	"give_food_to_hungry_person:north_quay_record_keeper"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. 动态地点局面场景可以独立加载")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var location_title := viewer.get_node("%LocationTitle") as Label
	var location_description := viewer.get_node("%LocationDescription") as RichTextLabel
	var player_summary := viewer.get_node("%PlayerSummary") as RichTextLabel
	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	var visible_people := viewer.get_node("%VisiblePeople") as RichTextLabel
	var visible_observations := viewer.get_node("%VisibleObservations") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var knowledge_text := viewer.get_node("%KnowledgeText") as RichTextLabel
	var history_text := viewer.get_node("%HistoryText") as RichTextLabel
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer
	var intro_dialog := viewer.get_node("%IntroDialog") as AcceptDialog

	_check(
		location_title.text == "老陈铺子"
		and "旧粮" in location_description.text
		and "食物　3 份" in player_summary.text,
		"2. 初始画面来自湖湾镇模拟 fixture，而不是静态演示状态"
	)
	_check(
		"陈米" in visible_people.text
		and "饥饿：严重" in visible_people.text
		and "涨价告示" in visible_observations.text
		and "灰白粮粉" in visible_observations.text,
		"3. 当前快照投影出可见人物、可读物件和可检查痕迹"
	)
	_check(
		"粮食压力" in region_status.text
		and "街面秩序" in region_status.text,
		"4. 地区和机构状态被翻译为玩家可读的局面压力"
	)
	_check(
		_find_action_button(action_buttons, GIVE_FOOD_ACTION) != null
		and _find_action_button(action_buttons, READ_NOTICE_ACTION) != null
		and _find_action_button(action_buttons, INSPECT_TRACE_ACTION) != null,
		"5. 底部按钮由 SimSession 当前候选动态生成"
	)
	_check(
		not intro_dialog.visible,
		"6. 开场不再用模态说明阻塞首次行动"
	)

	var give_button := _find_action_button(action_buttons, GIVE_FOOD_ACTION)
	(give_button as Button).pressed.emit()
	await process_frame
	_check(
		"食物　2 份" in player_summary.text
		and "饥饿：缓和" in visible_people.text,
		"7. 点击给食物后，玩家和陈米的持续状态立即刷新"
	)
	_check(
		"戒备已经没有先前那么重" in feedback_body.text
		and "随身食物 -1" in feedback_body.text
		and "感激 +15" in (viewer.get_node("%ResultReceipt") as RichTextLabel).text,
		"8. 结算叙事与关键状态、关系变化一起反馈"
	)
	_check(
		_find_action_button(action_buttons, GIVE_FOOD_ACTION) == null,
		"9. 陈米不再严重饥饿后，过期的给食物按钮消失"
	)

	var log_count: int = viewer.view_model.session.get_world_log_entries().size()
	var stale_result: Dictionary = viewer.perform_action(GIVE_FOOD_ACTION)
	await process_frame
	_check(
		not bool(stale_result.get("success", true))
		and "局面已经变化" in feedback_body.text
		and viewer.view_model.session.get_world_log_entries().size() == log_count,
		"10. 旧行动即使被外部重复调用也不会污染世界日志"
	)

	viewer.perform_action(READ_NOTICE_ACTION)
	viewer.perform_action(INSPECT_TRACE_ACTION)
	await process_frame
	_check(
		"你读过涨价告示" in knowledge_text.text
		and "你检查过灰白粮粉" in knowledge_text.text,
		"11. 连续调查会把已确认事实投影到认知栏"
	)
	_check(
		"递给陈米 1 份食物" in history_text.text
		and "读涨价告示" in history_text.text
		and "检查柜脚旁的灰白粮粉" in history_text.text
		and "来源不在这间铺子里" in history_text.text,
		"12. 玩家看到的是连续行动历史，不是一次性测试输出"
	)

	var visible_ui_text := "\n".join([
		location_title.text,
		player_summary.text,
		region_status.text,
		visible_people.text,
		visible_observations.text,
		feedback_body.text,
		knowledge_text.text,
		history_text.text,
	])
	_check(
		"actor_" not in visible_ui_text
		and "effect_template" not in visible_ui_text
		and "candidate_only" not in visible_ui_text,
		"13. 模拟内部标识没有泄漏到玩家界面"
	)

	viewer.restart_session()
	await process_frame
	_check(
		"食物　3 份" in player_summary.text
		and "饥饿：严重" in visible_people.text
		and "还没有发生行动" in history_text.text
		and _find_action_button(action_buttons, GIVE_FOOD_ACTION) != null,
		"14. 独立场景可以重新载入初始局面"
	)

	viewer.advance_time()
	viewer.advance_time()
	viewer.advance_time()
	await process_frame
	_check(
		"闻简" in visible_people.text
		and "饥饿：严重" in visible_people.text
		and "闻简来找吃的" in feedback_title.text
		and "北埠旧档房" in feedback_body.text
		and "north_quay_record_house" not in feedback_body.text
		and "自行作出的决定" in (viewer.get_node("%ResultReceipt") as RichTextLabel).text,
		"15. 需求变化会让异地 NPC 走进当前地点，并说明来意与自主原因"
	)
	viewer.advance_time()
	await process_frame
	_check(
		_find_action_button(action_buttons, GIVE_WEN_JIAN_FOOD) != null
		and "没买到食物后的求助" in feedback_title.text
		and "传闻：没买到食物后有人求助" in (viewer.get_node("%SceneDetailsRecord") as RichTextLabel).text
		and "翻空的食物袋" in (viewer.get_node("%SceneDetailsRecord") as RichTextLabel).text
		and "low" not in feedback_body.text
		and "medium" not in feedback_body.text,
		"16. 交易受阻后出现可介入的求助、传闻和现场痕迹"
	)
	var rumor_button := _find_action_button_containing(
		action_buttons,
		"没买到食物后有人求助"
	)
	_check(
		rumor_button != null,
		"17. 传闻按钮直接写明要听取的具体主题"
	)
	(rumor_button as Button).pressed.emit()
	await process_frame
	_check(
		"有人看见闻简在供应点翻空了食物袋" in feedback_body.text
		and "你听到过“没买到食物后有人求助”" in knowledge_text.text
		and _find_action_button_containing(
			action_buttons,
			"没买到食物后有人求助"
		) == null,
		"18. 听取后显示完整信息、写入认知并移除同一按钮"
	)
	_check(_find_action_button(action_buttons, GIVE_WEN_JIAN_FOOD) == null,
		"18a. 花时间打听消息时，闻简不会暂停自己的行程等待玩家")
	viewer.restart_session()
	for hour: int in 4:
		viewer.advance_time()
	await process_frame
	var help_button := _find_action_button(action_buttons, GIVE_WEN_JIAN_FOOD)
	_check(help_button != null, "18b. 对照流程先帮助闻简，机会仍在")
	if help_button == null:
		viewer.queue_free()
		_finish()
		return
	help_button.pressed.emit()
	await process_frame
	_check(
		str(viewer.view_model.session.get_snapshot().get_entity_state(
			"north_quay_record_keeper", "hunger", "")) == "medium"
		and _find_action_button(action_buttons, GIVE_WEN_JIAN_FOOD) == null,
		"19. 玩家介入会缓解闻简的饥饿，并立即移除过期选项"
	)
	var receipt := viewer.get_node("%ResultReceipt") as RichTextLabel
	_check(
		"闻简" in receipt.text
		and "北埠旧档房" in receipt.text
		and "north_quay_record_house" not in receipt.text
		and "闻简" not in visible_people.text,
		"20. 闻简返岗后离开本地投影，反馈只使用玩家可读地点名"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _find_action_button(container: Node, action_id: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta("action_id", "")) == action_id:
			return child as Button
	return null


func _find_action_button_containing(container: Node, text: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and text in (child as Button).text:
			return child as Button
	return null


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LIVE LOCATION VIEWER RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 LIVE LOCATION VIEWER FAIL] " + failure)
		print("[V5 LIVE LOCATION VIEWER RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 LIVE LOCATION VIEWER PASS] " + message)
	else:
		failures.append(message)
